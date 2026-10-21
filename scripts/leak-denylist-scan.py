#!/usr/bin/env python3
"""Fail if any tracked file carries a value on the hashed leak denylist.

Usage: leak-denylist-scan.py [--root DIR] [--denylist FILE]

The denylist (evals/leak-denylist.sha256) holds SHA-256 digests of live
organizational values: GlassFrog v5 ids, the organization's legacy number as
it appears in a web URL, and the names of real policies and domains. It holds
digests rather than the values because the earlier guard in
scripts/evals-harness.test.sh named the live ids in order to forbid them, and
so published them itself.

A digest hides a 32-hex id well. It hides a short number or a phrase poorly:
anyone can hash candidates and compare. That is acceptable only because those
values were already public in history when this file was written (see
ADR-0017). Do not treat a digest as a secret.

Every candidate token in every scanned file is lowercased, hashed, and looked
up. Candidates are:
  - prefixed GlassFrog ids: <prefix>_<32 hex>
  - `organizations/<digits>` from web URLs
  - every run of two to four words, for policy and domain names

Exit codes: 0 clean, 1 a denylisted value was found, 2 usage error.
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys

ID_RE = re.compile(r"\b(?:role|per|org|mem|ten|proj|prj|actn|act|goal|dom|pol|asg|agt)_[0-9a-f]{32}\b")
ORG_RE = re.compile(r"organizations/[0-9]+")
WORD_RE = re.compile(r"[a-z0-9]+")
SKIP_SUFFIXES = (".png", ".jpg", ".jpeg", ".gif", ".ico", ".pyc", ".sha256")


def digest(value):
    return hashlib.sha256(value.lower().encode("utf-8")).hexdigest()


def load_denylist(path):
    out = set()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                out.add(line)
    return out


def tracked_files(root):
    try:
        res = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                             capture_output=True, check=True)
        names = [n for n in res.stdout.decode().split("\0") if n]
    except (subprocess.CalledProcessError, FileNotFoundError):
        names = []
        for d, _, files in os.walk(root):
            if ".git" in d.split(os.sep):
                continue
            names += [os.path.relpath(os.path.join(d, f), root) for f in files]
    return sorted(names)


def candidates(text):
    low = text.lower()
    yield from ID_RE.findall(low)
    yield from ORG_RE.findall(low)
    words = WORD_RE.findall(low)
    for n in (2, 3, 4):
        for i in range(len(words) - n + 1):
            yield " ".join(words[i:i + n])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--denylist", default=None)
    args = ap.parse_args()
    denylist_path = args.denylist or os.path.join(args.root, "evals", "leak-denylist.sha256")
    if not os.path.isfile(denylist_path):
        print(f"leak-denylist-scan: no denylist at {denylist_path}", file=sys.stderr)
        return 2
    deny = load_denylist(denylist_path)
    if not deny:
        print("leak-denylist-scan: denylist is empty; refusing to report clean", file=sys.stderr)
        return 2

    hits = []
    for rel in tracked_files(args.root):
        if rel.endswith(SKIP_SUFFIXES):
            continue
        path = os.path.join(args.root, rel)
        try:
            with open(path, encoding="utf-8", errors="ignore") as fh:
                lines = fh.readlines()
        except (IsADirectoryError, FileNotFoundError):
            continue
        for lineno, line in enumerate(lines, 1):
            for cand in candidates(line):
                if digest(cand) in deny:
                    hits.append((rel, lineno))
                    break
    for rel, lineno in hits:
        # Location only: printing the matched value would publish it in CI logs.
        print(f"{rel}:{lineno}: a denylisted live organizational value appears here")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
