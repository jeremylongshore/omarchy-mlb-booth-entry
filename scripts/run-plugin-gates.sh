#!/usr/bin/env bash
# Run the vendored Omarchy plugin gates against a plugin tree.
#
# Why this exists: these checks used to live only in a personal tool on one
# workstation, so they ran when someone remembered. Two entries shipped with a
# Node poller that a stock Omarchy box cannot execute, and one shipped a bearer
# token in a curl argv, because nothing mechanical stopped them. Enforcement
# now travels with the repo and runs on every push.
#
# Usage: scripts/run-plugin-gates.sh [plugin-dir]   (default: repo root)
# Exit 0 when no gate blocks; exit 1 on the first BLOCK verdict.
set -uo pipefail

TARGET="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
GATES="$(cd "$(dirname "$0")/gates" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "run-plugin-gates: jq is required" >&2; exit 2; }

INPUT="$(jq -nc --arg c "$TARGET" '{candidate:$c, action:"omarchy-submit", env:{repo:""}}')"

blocked=0
pass=0
for gate in "$GATES"/c*.sh; do
  verdict="$(printf '%s' "$INPUT" | bash "$gate" 2>/dev/null)"
  # A gate that emits nothing has crashed hard. Fail closed rather than
  # silently counting it as clean, which is how a broken gate becomes theater.
  if [[ -z "$verdict" ]]; then
    printf '  %-6s CRASH  no verdict emitted\n' "$(basename "$gate" .sh | cut -d- -f1 | tr a-z A-Z)"
    blocked=1
    continue
  fi
  sev="$(printf '%s' "$verdict" | jq -r '.severity // "CRASH"')"
  id="$(printf '%s' "$verdict" | jq -r '.gate // "?"')"
  reason="$(printf '%s' "$verdict" | jq -r '.reason // ""')"
  printf '  %-6s %-6s %s\n' "$id" "$sev" "$reason"
  case "$sev" in
    BLOCK|CRASH)
      blocked=1
      hint="$(printf '%s' "$verdict" | jq -r '.fix_hint // ""')"
      [[ -n "$hint" ]] && printf '         fix: %s\n' "$hint"
      ;;
    PASS) pass=$((pass + 1)) ;;
  esac
done

echo
if [[ "$blocked" -eq 1 ]]; then
  echo "plugin gates: BLOCKED"
  exit 1
fi
echo "plugin gates: PASS ($pass enforced, others not applicable to this tree)"
