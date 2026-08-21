#!/usr/bin/env bash
# Prove this plugin runs on a real Omarchy, and record a receipt.
#
# Why a receipt: gate C32 (omarchy-plugin-validate) and C33 (qmllint) call
# gate_skip when those binaries are not on the local box, and they never are,
# because they live on the rig. The gate runner counts SKIP as pass, so the
# submission lane happily printed "verdict PASS, 0 BLOCK" for a plugin that had
# never run on Omarchy at all. A gate cannot do the rig round trip itself: the
# runner enforces a 10 second wall clock.
#
# So this script does the round trip and writes .rig-proof.json, and gate C37
# refuses a submission whose receipt is missing, stale, failing, or written
# against different code.
#
# Usage: scripts/rig-verify.sh [plugin-dir]   (default: repo root)
set -uo pipefail

TARGET="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
HOST="${OMARCHY_RIG_HOST:-intent-ops-buzz}"
CONTAINER="${OMARCHY_RIG_CONTAINER:-omarchy-rig}"
NAME="rigcheck-$$"

command -v jq >/dev/null 2>&1 || { echo "rig-verify: jq is required" >&2; exit 2; }
[[ -f "$TARGET/manifest.json" ]] || { echo "rig-verify: no manifest.json in $TARGET" >&2; exit 2; }

# Fingerprint exactly what the rig checks: the manifest and every QML file.
# C37 recomputes this and refuses a receipt that does not match, so a receipt
# can never certify code nobody ran.
fingerprint() {
  ( cd "$TARGET" && \
    find . -maxdepth 2 \( -name '*.qml' -o -name 'manifest.json' \) \
      -not -path './.git/*' -not -path './tests/*' -print0 2>/dev/null \
    | LC_ALL=C sort -z | xargs -0 cat 2>/dev/null | sha256sum | cut -d' ' -f1 )
}
FP="$(fingerprint)"

TGZ="$(mktemp -t rigcheck-XXXXXX.tgz)"
trap 'rm -f "$TGZ"' EXIT
tar czf "$TGZ" -C "$TARGET" --exclude=.git --exclude=tests --exclude=node_modules . || {
  echo "rig-verify: could not package the tree" >&2; exit 2; }

echo "rig-verify: shipping to $HOST/$CONTAINER"
scp -q "$TGZ" "$HOST:/tmp/$NAME.tgz" || { echo "rig-verify: cannot reach $HOST" >&2; exit 2; }

RESULT="$(ssh "$HOST" "
  docker cp /tmp/$NAME.tgz $CONTAINER:/tmp/ >/dev/null 2>&1 || exit 3
  docker exec $CONTAINER sh -c 'rm -rf /tmp/$NAME && mkdir -p /tmp/$NAME && tar xzf /tmp/$NAME.tgz -C /tmp/$NAME' || exit 3
  docker exec $CONTAINER /root/omarchy/bin/omarchy-plugin-validate /tmp/$NAME >/dev/null 2>&1
  V=\$?
  # NOTE: this whole ssh argument is double quoted, so a backtick or an
  # unescaped dollar here is expanded by the LOCAL shell. Keep it plain.
  # grep -c EXITS 1 when the count is zero, which is the healthy case here, and
  # the old trailing echo-1 fallback therefore fired on every CLEAN run: the
  # remote emitted two lines, 0 then 1, the awk split read the validate field
  # as 0-newline-1, failed its numeric test, and the receipt recorded
  # omarchyPluginValidate: 1 for a plugin the rig had just passed. A receipt
  # that fails a clean plugin trains people to ignore the receipt.
  # qmllint reports a SYNTAX failure as \"Warning: ... [syntax]\" and signals it
  # only through a non-zero exit (255), so grepping for lines beginning
  # \"Error\" scored a file that does not parse at all as zero errors. The exit
  # status is the authoritative signal; the Error-line count is kept because it
  # is the more useful number when there IS one. A non-zero exit with no
  # Error line still counts as one error, or a receipt certifies a plugin the
  # linter could not even read.
  Q=\$(docker exec $CONTAINER sh -c 'cd /tmp/$NAME || exit 9; out=\$(/usr/lib/qt6/bin/qmllint *.qml 2>&1); rc=\$?; n=\$(printf %s\\\\n \"\$out\" | grep -cE \"^Error\" || true); if [ \"\$rc\" -ne 0 ] && [ \"\$n\" -eq 0 ]; then n=1; fi; echo \"\$n\"' 2>/dev/null)
  case \"\$Q\" in ''|*[!0-9]*) Q=1 ;; esac
  docker exec $CONTAINER rm -rf /tmp/$NAME /tmp/$NAME.tgz >/dev/null 2>&1
  rm -f /tmp/$NAME.tgz
  echo \"\$V \$Q\"
")" || { echo "rig-verify: rig run failed" >&2; exit 2; }

# Read ONLY the receipt line. Anything else the remote emitted is noise, and
# silently letting it shift the fields is how a pass got recorded as a failure.
VALIDATE="$(echo "$RESULT" | tail -n1 | awk '{print $1}')"
QMLLINT="$(echo "$RESULT" | tail -n1 | awk '{print $2}')"
[[ "$VALIDATE" =~ ^[0-9]+$ ]] || VALIDATE=1
[[ "$QMLLINT"  =~ ^[0-9]+$ ]] || QMLLINT=1

echo "  omarchy-plugin-validate: exit $VALIDATE"
echo "  qmllint errors:          $QMLLINT"

# Write the receipt even on failure. C37 reads the recorded results and blocks
# on a non-zero one, so a failing run must not look identical to never running.
jq -n --arg fp "$FP" --arg rig "$HOST/$CONTAINER" \
      --argjson v "$VALIDATE" --argjson q "$QMLLINT" \
      --argjson at "$(date +%s)" --arg iso "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{fingerprint:$fp, rig:$rig, omarchyPluginValidate:$v, qmllintErrors:$q,
    validatedAtEpoch:$at, validatedAt:$iso}' > "$TARGET/.rig-proof.json"

if [[ "$VALIDATE" -ne 0 || "$QMLLINT" -ne 0 ]]; then
  echo "rig-verify: FAILED on the rig; receipt records the failure" >&2
  exit 1
fi
echo "rig-verify: PASS, receipt written to .rig-proof.json"
