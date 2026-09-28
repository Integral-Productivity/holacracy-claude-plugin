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
# It reads the `## Install` section of README.md and collects:
#
#   - every `/plugin marketplace add <owner>/<repo>` line  (a channel)
#   - every `/plugin install holacracy@<name>` line        (an install target)
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
# Then it cross-checks the two lists: every install target must name a catalog
# a listed channel declares, and every listed channel must have an install
# line. A bare `/plugin install holacracy` with no `@<name>` is rejected — with
# more than one channel it does not say which one it means.
#
# EXIT CODES
# ----------
#   0  every channel serves holacracy correctly, and the lists agree
#   1  a channel does not serve it, serves it wrongly, or the lists disagree
#   2  usage error, or a catalog could not be read (gh/network/parse/auth)
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
# the rest as NOT MEASURED; `scripts-test.yml` runs it on every PR, where no
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

Exit: 0 = every channel serves holacracy, 1 = a channel does not, 2 = usage or read failure
EOF
}

die() {
  echo "::error title=install-channel-check::$*" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --readme)        README="${2:-}"; shift 2 ;;
    --local-catalog) LOCAL_CATALOG="${2:-}"; shift 2 ;;
    --self-repo)     SELF_REPO="${2:-}"; shift 2 ;;
    --fixture-dir)   FIXTURE_DIR="${2:-}"; shift 2 ;;
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

# ---------------------------------------------------------------------------
# 1. Read the Install section
# ---------------------------------------------------------------------------
# From the `## Install` heading to the next level-2 heading. Sub-headings
# (`### ...`) stay inside it.
install_block="$(awk '
  /^## / { inside = ($0 ~ /^## Install[[:space:]]*$/); next }
  inside { print }
' "$README")"
[ -n "$install_block" ] || die "README has no '## Install' section: $README"

channels="$(printf '%s\n' "$install_block" \
  | sed -nE 's#^[[:space:]]*/plugin marketplace add[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)[[:space:]]*$#\1#p' \
  | awk '!seen[tolower($0)]++')"
install_lines="$(printf '%s\n' "$install_block" \
  | grep -E "^[[:space:]]*/plugin install[[:space:]]+$PLUGIN_NAME([@[:space:]]|$)" || true)"

[ -n "$channels" ] || die "the Install section names no '/plugin marketplace add <owner>/<repo>' channel — nothing to measure"

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

failures=0
unmeasured=0
measured=0
declared_names=""
report=""

while IFS= read -r channel; do
  [ -n "$channel" ] || continue
  is_self=false
  [ "$(lower "$channel")" = "$(lower "$SELF_REPO")" ] && is_self=true

  if [ "$LOCAL_ONLY" = true ] && [ "$is_self" = false ]; then
    unmeasured=$((unmeasured + 1))
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
  declared_names+="$cat_name"$'\n'
  if [ -n "$problems" ]; then
    failures=$((failures + 1))
    report+="  FAIL          $channel (catalog $cat_name)"$'\n'
    while IFS= read -r p; do report+="                  - $p"$'\n'; done <<< "$problems"
  else
    report+="  ok            $channel (catalog $cat_name)"$'\n'
  fi
done <<< "$channels"

# ---------------------------------------------------------------------------
# 3. Cross-check install lines against the catalogs that were measured
# ---------------------------------------------------------------------------
if [ -z "$install_lines" ]; then
  failures=$((failures + 1))
  report+="  FAIL          no '/plugin install $PLUGIN_NAME@<catalog>' line in the Install section"$'\n'
fi
installed_names=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  target="$(printf '%s' "$line" | sed -nE "s#^[[:space:]]*/plugin install[[:space:]]+$PLUGIN_NAME@([A-Za-z0-9_.-]+)[[:space:]]*\$#\1#p")"
  if [ -z "$target" ]; then
    failures=$((failures + 1))
    report+="  FAIL          '$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')' names no catalog — use $PLUGIN_NAME@<catalog>"$'\n'
    continue
  fi
  installed_names+="$target"$'\n'
  if [ "$LOCAL_ONLY" = false ] && ! printf '%s' "$declared_names" | grep -qxF "$target"; then
    failures=$((failures + 1))
    report+="  FAIL          '$PLUGIN_NAME@$target' — no listed channel declares a catalog named $target"$'\n'
  fi
done <<< "$install_lines"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if ! printf '%s' "$installed_names" | grep -qxF "$name"; then
    failures=$((failures + 1))
    report+="  FAIL          catalog $name is added but no '/plugin install $PLUGIN_NAME@$name' line follows"$'\n'
  fi
done <<< "$declared_names"

echo "install-channel-check: $README"
printf '%s' "$report"
echo "measured: $measured  not measured: $unmeasured  failures: $failures"

[ "$measured" -gt 0 ] || die "no channel was measured — nothing to report health from"
[ "$failures" -eq 0 ] || { echo "::error title=install-channel-check::README names an install path that does not serve $PLUGIN_NAME (see report)" >&2; exit 1; }
exit 0
