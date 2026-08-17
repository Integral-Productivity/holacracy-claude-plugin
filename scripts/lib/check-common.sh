# shellcheck shell=bash
# Shared scaffold for this repo's static checker scripts (scripts/skills-lint.sh,
# scripts/cache-key-completeness-check.sh, and any future one). Source this
# from a checker script after `set -uo pipefail`; the caller owns argument
# parsing, its own SKIP env var, and its list of check functions.
#
# Not standalone -- has no shebang and is never executed directly. Sourced,
# not run, so its `exit 1` inside check_common_summarize() terminates the
# CALLER's process, matching the inline exit every checker used before this
# was extracted.
#
# Provides:
#   FINDINGS                     running count, incremented by finding()
#   finding ID TARGET MSG        print one finding line, increment FINDINGS
#   skipped ID                   true if ID is in the caller's $SKIP list
#   check_common_summarize NAME  print the clean/finding(s) line; exit 1 if
#                                 FINDINGS > 0, otherwise fall through (the
#                                 caller's script then ends with exit 0)
#
# WHY THIS EXISTS
# ----------------
# scripts/cache-key-completeness-check.sh named scripts/skills-lint.sh check 4
# as its direct precedent (same "for each mechanical check there is a plan
# violating only that check" discipline) and then re-pasted its FINDINGS
# counter, finding()/skipped() functions, and check-dispatch-then-exit tail
# character-for-character instead of sharing them. A third checker would have
# made that three copies to keep in sync by hand.

FINDINGS=0
finding() {  # $1 = check id, $2 = file (optionally file:line), $3 = message
  printf '%s  %s: %s\n' "[$1]" "$2" "$3"
  FINDINGS=$((FINDINGS + 1))
}
skipped() { case ",$SKIP," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

check_common_summarize() {  # $1 = checker name, e.g. "skills-lint"
  if [ "$FINDINGS" -gt 0 ]; then
    printf '\n%s: %d finding(s)\n' "$1" "$FINDINGS"
    exit 1
  fi
  printf '%s: clean\n' "$1"
}
