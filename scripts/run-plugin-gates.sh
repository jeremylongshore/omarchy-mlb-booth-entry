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

# Verify the vendored lane is the lane it claims to be, BEFORE trusting a word
# it says. Vendoring makes enforcement travel with the code, but a vendored copy
# is a copy: on 2026-08-21 every plugin repo was found running a c36 older than
# canonical, and mlb-booth's CI reported PASS on a tree the canonical gate
# blocked with three findings, while mlb-booth was already listed. A gate that
# drifts behind reports green and teaches you to trust it.
#
# This check is offline and deterministic: it proves the vendored files are the
# ones sync-gate-lane.sh recorded. It cannot detect that CANONICAL has moved on
# since — the manifest header carries the source commit so a human or a CI step
# can compare that separately.
MANIFEST="$GATES/.lane-manifest"
if [[ ! -f "$MANIFEST" ]]; then
  echo "run-plugin-gates: no scripts/gates/.lane-manifest — this vendored lane is unverifiable." >&2
  echo "  run scripts/sync-gate-lane.sh to sync from canonical and record what was taken." >&2
  exit 2
fi
drift=0
while read -r want file; do
  [[ "$want" == \#* || -z "$want" ]] && continue
  if [[ ! -f "$GATES/$file" ]]; then
    echo "run-plugin-gates: manifest lists $file but it is missing from the lane" >&2
    drift=1; continue
  fi
  got="$(cd "$GATES" && sha256sum "$file" | cut -d' ' -f1)"
  if [[ "$got" != "$want" ]]; then
    echo "run-plugin-gates: $file does not match the manifest (vendored lane edited or stale)" >&2
    drift=1
  fi
done < "$MANIFEST"
# A gate present on disk but absent from the manifest would run unverified.
while IFS= read -r f; do
  /usr/bin/grep -q "  $f\$" "$MANIFEST" || { echo "run-plugin-gates: $f is not in the manifest and would run unverified" >&2; drift=1; }
done < <(cd "$GATES" && LC_ALL=C ls c*.sh 2>/dev/null)
if [[ "$drift" -ne 0 ]]; then
  echo >&2
  echo "run-plugin-gates: REFUSING to run a lane that does not match its manifest." >&2
  echo "  re-sync with scripts/sync-gate-lane.sh, review the diff, and commit it." >&2
  exit 2
fi

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
