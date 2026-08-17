#!/usr/bin/env bash
# Fetch skill-creator's aggregate_benchmark.py at the commit evals/aggregator-pin.txt names.
#
#   AGGREGATOR="$(bash scripts/fetch-pinned-aggregator.sh "$RUNNER_TEMP/spc")"
#
# WHY THIS IS A SCRIPT AND NOT TWO COPIES OF A WORKFLOW BLOCK
# -----------------------------------------------------------
# Two jobs need the same aggregator at the same commit: the graded job runs it
# to produce a benchmark, and the per-PR job runs it so scripts/eval-cost.py's
# correction is verified against real upstream output rather than a fixture.
# The fetch existed verbatim in both workflow files, which is a drift hazard of
# exactly the kind the pin itself exists to remove -- and a shell block inside a
# workflow is unreachable by any test.
#
# WHAT IS VALIDATED, AND WHY EACH CHECK IS HERE
# ----------------------------------------------
# * The pin must be a bare 40-hex commit. `grep -v '^#' | tr -d [:space:]`
#   concatenates every non-comment line, so a stray second line silently yields
#   a nonsense SHA -- which fails at fetch, but with a git error that names
#   neither the file nor the cause.
# * `init` + `fetch <sha>` rather than `clone --depth 1`, because a shallow
#   clone can only resolve a branch or tag. Fetching the commit directly keeps
#   the shallow, blobless, sparse shape while making the revision
#   content-addressed.
# * The resolved HEAD is asserted against the pin. Git verifies the object it
#   fetched, so this cannot disagree -- which is the point of asserting it. If
#   it ever does, something has replaced the fetch with a resolution step and
#   the pin has stopped being a pin.
# * The fetch is wrapped in a hard timeout. Without one, a hung connection
#   stalls every PR's gate for as long as the job's own ceiling allows.
set -euo pipefail

DEST="${1:?usage: fetch-pinned-aggregator.sh <dest-dir>}"
TIMEOUT_SECONDS="${AGGREGATOR_FETCH_TIMEOUT:-300}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="$REPO_ROOT/evals/aggregator-pin.txt"
UPSTREAM="https://github.com/anthropics/claude-plugins-official.git"
SUBDIR="plugins/skill-creator/skills/skill-creator/scripts"

[ -f "$PIN_FILE" ] || { echo "::error::no aggregator pin at $PIN_FILE" >&2; exit 1; }
SHA="$(grep -v '^[[:space:]]*#' "$PIN_FILE" | tr -d '[:space:]')"

if [ ${#SHA} -ne 40 ] || [ -n "${SHA//[0-9a-f]/}" ]; then
  echo "::error::$PIN_FILE does not contain exactly one bare 40-character hex commit (got '${SHA}')" >&2
  exit 1
fi

git init -q "$DEST"
git -C "$DEST" remote add origin "$UPSTREAM"
git -C "$DEST" sparse-checkout set --cone "$SUBDIR"
if ! timeout "$TIMEOUT_SECONDS" git -C "$DEST" fetch -q --depth 1 \
    --filter=blob:none origin "$SHA"; then
  echo "::error::fetching the pinned aggregator ($SHA) failed or exceeded ${TIMEOUT_SECONDS}s" >&2
  exit 1
fi
git -C "$DEST" checkout -q FETCH_HEAD

resolved="$(git -C "$DEST" rev-parse HEAD)"
if [ "$resolved" != "$SHA" ]; then
  echo "::error::aggregator pin is ${SHA} but HEAD resolved to ${resolved}" >&2
  exit 1
fi

AGGREGATOR="$DEST/$SUBDIR/aggregate_benchmark.py"
[ -f "$AGGREGATOR" ] || {
  echo "::error::no aggregate_benchmark.py at $AGGREGATOR after checkout" >&2
  exit 1
}

echo "aggregator pinned at $resolved" >&2
printf '%s\n' "$AGGREGATOR"
