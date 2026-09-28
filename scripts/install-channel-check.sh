#!/usr/bin/env bash
#
# install-channel-check.sh — fail when README's Install block names a
# marketplace that does not actually serve this plugin.
#
# WHY THIS EXISTS
# ---------------
# For months README.md told users to run
#
#   /plugin marketplace add Integral-Productivity/marketplace
#   /plugin install holacracy
#
# and that marketplace's catalog was `"plugins": []`. The install path resolved
# to nothing, by any route, and nothing reported it (issue #234). It is the same
# shape as #122 one level out: a documented claim about delivery that nothing
# verifies. This script is the verification. ADR-0016 records which channels
# the README is allowed to name.
#
# WHAT IT CHECKS
# --------------
# It reads the `## Install` section of README.md — exactly one level-2 heading
# may start with `## Install`; a second one (`## Installation`, `## Install
# (legacy)`) is a defect, not a choice the check makes silently — and walks it
# top to bottom, line by line. Two line forms are parsed, each alone on its line:
#
#   - `/plugin marketplace add <owner>/<repo>`  (a channel)
#   - `/plugin install holacracy@<name>`        (an install target)
#
# Any other line in the section that contains `marketplace add` or `plugin
# install` — a trailing comment, inline code in prose, the `claude plugin ...`
# CLI form, `<owner>/<repo>@<ref>` — is a FAIL naming the line as an
# unrecognised install instruction. The check must not pass a README that
# instructs something it cannot see.
#
# For each channel it loads that repo's `.claude-plugin/marketplace.json` —
# from disk when the channel is this repo, from the GitHub API otherwise — and
# requires:
#
#   - an entry named `holacracy`
#   - sourced from this repo    (`source.source == "github"`, `source.repo`)
#   - at ref `stable`           (ADR-0002: installs follow the release channel)
#   - with no `version` field   (ADR-0002: a pinned version is what drifted)
#
# Then it pairs them, in order: each install line belongs to the most recent
# channel above it, and its `@<name>` must equal THAT channel's catalog `.name`.
# An install line with no channel above it fails, and so does a channel with no
# install line of its own. Pairing is per block, not per set: a README whose
# two blocks each install from the other block's catalog names the right names
# overall and still sends every reader to the wrong one. A bare
# `/plugin install holacracy` with no `@<name>` is rejected — with more than one
# channel it does not say which one it means.
#
# EXIT CODES
# ----------
#   0  every channel serves holacracy correctly, and every pair is right
#   1  a README or catalog defect: a channel does not serve it or serves it
#      wrongly, a pair is wrong, or the Install section is malformed
#   2  usage error, a catalog could not be read (gh/network/parse/auth), or
#      nothing was measured
#
# A catalog that cannot be read is 2, never 0 and never 1. A private repo the
# token cannot see answers 404 exactly like a repo with no catalog, so the
# script cannot tell "not listed" from "not allowed to look" — and reporting
# health from absent evidence is the failure #122 documents. An Install block
# with no channel at all is also 2: there is nothing to measure.
#
# VERIFICATION AFFORDANCES
# ------------------------
# `--fixture-dir` substitutes remote catalogs with files named
# `<owner>__<repo>.json`, so the suite can drive every path offline.
# `--local-only` measures only the channel served from this repo and reports
# the rest as NOT MEASURED — an install line paired with an unmeasured channel
# is reported NOT JUDGED, while one paired with the local channel is judged; `scripts-test.yml` runs it on every PR, where no
# credential for the private labs catalog exists. The credentialed full run is
# `.github/workflows/install-channel-check.yml`.

set -euo pipefail

DEFAULT_SELF_REPO="Integral-Productivity/holacracy-claude-plugin"
PLUGIN_NAME="holacracy"
REQUIRED_REF="stable"
CATALOG_PATH=".claude-plugin/marketplace.json"

README="README.md"
LOCAL_CATALOG="$CATALOG_PATH"
FIXTURE_DIR=""
LOCAL_ONLY=false
SELF_REPO="${INSTALL_CHECK_SELF_REPO:-$DEFAULT_SELF_REPO}"

usage() {
  cat <<'EOF'
Usage: install-channel-check.sh [options]

  --readme PATH         README to read (default: README.md)
  --local-catalog PATH  this repo's catalog (default: .claude-plugin/marketplace.json)
  --self-repo O/R       this repo's owner/name (default: Integral-Productivity/holacracy-claude-plugin)
  --fixture-dir DIR     read remote catalogs from DIR/<owner>__<repo>.json instead of
                        the GitHub API. Verification affordance; unused in CI.
  --local-only          measure only the channel served from this repo; report the
                        others as NOT MEASURED
  -h, --help            show this help

Exit: 0 = every channel serves holacracy and every pair is right,
      1 = a README or catalog defect, 2 = usage error, read failure, or nothing measured
EOF
}

die() {
  echo "::error title=install-channel-check::$*" >&2
  exit 2
}

# need_value "$@" — a value-taking option must have a value; without this,
# `shift 2` fails under set -e and the script exits 1 with no message.
need_value() {
  [ $# -ge 2 ] || die "$1 needs a value"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --readme)        need_value "$@"; README="$2"; shift 2 ;;
    --local-catalog) need_value "$@"; LOCAL_CATALOG="$2"; shift 2 ;;
    --self-repo)     need_value "$@"; SELF_REPO="$2"; shift 2 ;;
    --fixture-dir)   need_value "$@"; FIXTURE_DIR="$2"; shift 2 ;;
    --local-only)    LOCAL_ONLY=true; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required"
[ -n "$README" ] && [ -f "$README" ] || die "README not found: ${README:-<empty>}"
case "$SELF_REPO" in */*) ;; *) die "--self-repo must be owner/repo, got: $SELF_REPO" ;; esac
if [ -n "$FIXTURE_DIR" ] && [ ! -d "$FIXTURE_DIR" ]; then
  die "--fixture-dir is not a directory: $FIXTURE_DIR"
fi

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
trim()  { printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

failures=0
report=""

# ---------------------------------------------------------------------------
# 1. Read the Install section
# ---------------------------------------------------------------------------
# More than one level-2 heading starting `## Install` means the README tells
# two install stories; reading only one of them would be a silent choice.
install_headings="$(grep -cE '^## Install' "$README" || true)"
if [ "$install_headings" -gt 1 ]; then
  echo "install-channel-check: $README"
  grep -nE '^## Install' "$README" | sed -E 's/^([0-9]+):/  FAIL          line \1 — /'
  echo "::error title=install-channel-check::README has $install_headings level-2 headings starting with '## Install'; keep exactly one '## Install' section" >&2
  exit 1
fi

# From the `## Install` heading to the next level-2 heading. Sub-headings
# (`### ...`) stay inside it.
install_block="$(awk '
  /^## / { inside = ($0 ~ /^## Install[[:space:]]*$/); next }
  inside { print }
' "$README")"
[ -n "$install_block" ] || die "README has no '## Install' section: $README"

# One ordered pass. Each install line is paired with the most recent channel
# above it (`pairs`: "<target>\t<channel>", channel empty when none precedes).
CHANNEL_RE='^[[:space:]]*/plugin marketplace add[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)[[:space:]]*$'
INSTALL_RE="^[[:space:]]*/plugin install[[:space:]]+$PLUGIN_NAME@([A-Za-z0-9_.-]+)[[:space:]]*\$"
BARE_RE="^[[:space:]]*/plugin install[[:space:]]+${PLUGIN_NAME}[[:space:]]*\$"
channels=""
pairs=""
install_count=0
current=""
while IFS= read -r line; do
  if [[ $line =~ $CHANNEL_RE ]]; then
    current="${BASH_REMATCH[1]}"
    channels+="$current"$'\n'
  elif [[ $line =~ $INSTALL_RE ]]; then
    install_count=$((install_count + 1))
    pairs+="${BASH_REMATCH[1]}"$'\t'"$current"$'\n'
  elif [[ $line =~ $BARE_RE ]]; then
    install_count=$((install_count + 1))
    failures=$((failures + 1))
    report+="  FAIL          '$(trim "$line")' names no catalog — use $PLUGIN_NAME@<catalog>"$'\n'
  elif [[ $line == *"marketplace add"* || $line == *"plugin install"* ]]; then
    failures=$((failures + 1))
    report+="  FAIL          unrecognised install instruction: '$(trim "$line")' — only '/plugin marketplace add <owner>/<repo>' and '/plugin install $PLUGIN_NAME@<catalog>', each alone on its line, can be checked"$'\n'
  fi
done <<< "$install_block"
channels="$(printf '%s' "$channels" | awk '!seen[tolower($0)]++')"

if [ -z "$channels" ] && [ "$failures" -eq 0 ]; then
  die "the Install section names no '/plugin marketplace add <owner>/<repo>' channel — nothing to measure"
fi

# ---------------------------------------------------------------------------
# 2. Load and judge each channel's catalog
# ---------------------------------------------------------------------------
# load_catalog CHANNEL -> catalog JSON on stdout; returns 1 when it cannot be read.
load_catalog() {
  local channel="$1" b64
  if [ "$(lower "$channel")" = "$(lower "$SELF_REPO")" ]; then
    [ -f "$LOCAL_CATALOG" ] || return 1
    cat "$LOCAL_CATALOG"
    return 0
  fi
  if [ -n "$FIXTURE_DIR" ]; then
    local f="$FIXTURE_DIR/${channel%%/*}__${channel#*/}.json"
    [ -f "$f" ] || return 1
    cat "$f"
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 1
  b64="$(gh api "repos/$channel/contents/$CATALOG_PATH" --jq '.content' 2>/dev/null)" || return 1
  [ -n "$b64" ] || return 1
  printf '%s' "$b64" | tr -d '\n' | base64 --decode 2>/dev/null || return 1
}

# judge CATALOG_JSON -> prints problems (one per line); empty means healthy.
judge() {
  jq -r --arg name "$PLUGIN_NAME" --arg repo "$(lower "$SELF_REPO")" --arg ref "$REQUIRED_REF" '
    [ (.plugins // [])[] | select(.name == $name) ] as $hits
    | if ($hits | length) == 0 then "no plugin named \($name) in the catalog"
      elif ($hits | length) > 1 then "\($hits | length) entries named \($name) — ambiguous"
      else $hits[0] as $p
        | ( if ($p.source | type) != "object" or $p.source.source != "github"
              then "source is not a github source: \($p.source | tojson)" else empty end ),
          ( if ($p.source | type) == "object" and (($p.source.repo // "") | ascii_downcase) != $repo
              then "source repo is \($p.source.repo // "<none>"), expected this repo" else empty end ),
          ( if ($p.source | type) == "object" and ($p.source.ref // "") != $ref
              then "source ref is \($p.source.ref // "<none>"), expected \($ref) (ADR-0002)" else empty end ),
          ( if $p | has("version")
              then "entry pins version \($p.version) — ADR-0002 forbids a pinned version" else empty end )
      end
  '
}

unmeasured=0
measured=0
channel_status=""   # "<lowercased channel>\t<measured|unmeasured>\t<catalog name>"

while IFS= read -r channel; do
  [ -n "$channel" ] || continue
  is_self=false
  [ "$(lower "$channel")" = "$(lower "$SELF_REPO")" ] && is_self=true

  if [ "$LOCAL_ONLY" = true ] && [ "$is_self" = false ]; then
    unmeasured=$((unmeasured + 1))
    channel_status+="$(lower "$channel")"$'\t'unmeasured$'\t'$'\n'
    report+="  NOT MEASURED  $channel (--local-only)"$'\n'
    continue
  fi

  if ! catalog="$(load_catalog "$channel")"; then
    die "could not read $CATALOG_PATH from $channel — missing, private without access, or network failure. Not listed and not allowed to look answer the same; this is a read failure, not a verdict."
  fi
  if ! cat_name="$(printf '%s' "$catalog" | jq -er '.name | strings' 2>/dev/null)"; then
    die "$channel's catalog is not valid marketplace JSON (no string .name)"
  fi
  if ! problems="$(printf '%s' "$catalog" | judge 2>/dev/null)"; then
    die "$channel's catalog could not be parsed"
  fi

  measured=$((measured + 1))
  channel_status+="$(lower "$channel")"$'\t'measured$'\t'"$cat_name"$'\n'
  if [ -n "$problems" ]; then
    failures=$((failures + 1))
    report+="  FAIL          $channel (catalog $cat_name)"$'\n'
    while IFS= read -r p; do report+="                  - $p"$'\n'; done <<< "$problems"
  else
    report+="  ok            $channel (catalog $cat_name)"$'\n'
  fi
done <<< "$channels"

# ---------------------------------------------------------------------------
# 3. Judge each install line against the channel it follows
# ---------------------------------------------------------------------------
# lookup CHANNEL -> "<status>\t<catalog name>" from section 2
lookup() {
  printf '%s' "$channel_status" | awk -F'\t' -v c="$(lower "$1")" '$1 == c { print $2 "\t" $3; exit }'
}

if [ "$install_count" -eq 0 ]; then
  failures=$((failures + 1))
  report+="  FAIL          no '/plugin install $PLUGIN_NAME@<catalog>' line in the Install section"$'\n'
fi
paired=""
while IFS=$'\t' read -r target via; do
  [ -n "$target" ] || continue
  if [ -z "$via" ]; then
    failures=$((failures + 1))
    report+="  FAIL          '$PLUGIN_NAME@$target' has no '/plugin marketplace add' line above it — nothing says which channel it installs from"$'\n'
    continue
  fi
  paired+="$(lower "$via")"$'\n'
  IFS=$'\t' read -r status name <<< "$(lookup "$via")"
  if [ "$status" != measured ]; then
    report+="  NOT JUDGED    '$PLUGIN_NAME@$target' after $via — that channel was not measured (--local-only)"$'\n'
  elif [ "$name" != "$target" ]; then
    failures=$((failures + 1))
    report+="  FAIL          '$PLUGIN_NAME@$target' follows '/plugin marketplace add $via', whose catalog is named $name"$'\n'
  fi
done <<< "$pairs"
while IFS= read -r channel; do
  [ -n "$channel" ] || continue
  if ! printf '%s' "$paired" | grep -qxF "$(lower "$channel")"; then
    failures=$((failures + 1))
    IFS=$'\t' read -r status name <<< "$(lookup "$channel")"
    if [ "$status" = measured ]; then
      report+="  FAIL          catalog $name is added but no '/plugin install $PLUGIN_NAME@$name' line follows"$'\n'
    else
      report+="  FAIL          channel $channel is added but no '/plugin install $PLUGIN_NAME@<catalog>' line follows it"$'\n'
    fi
  fi
done <<< "$channels"

echo "install-channel-check: $README"
printf '%s' "$report"
echo "measured: $measured  not measured: $unmeasured  failures: $failures"

# A defect found is a verdict even when no catalog was measured; a clean
# report with nothing measured is not health — it is absent evidence.
[ "$failures" -eq 0 ] || { echo "::error title=install-channel-check::README names an install path that does not serve $PLUGIN_NAME (see report)" >&2; exit 1; }
[ "$measured" -gt 0 ] || die "no channel was measured — nothing to report health from"
exit 0
