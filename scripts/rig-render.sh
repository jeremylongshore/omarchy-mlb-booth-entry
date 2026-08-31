#!/usr/bin/env bash
# Load a plugin into an isolated real Omarchy shell, open it through live IPC,
# and capture the dedicated 16:9 output without crop or post-processing.
#
# Generated plugins should add e2e/render-settings.json for deterministic inline
# widget settings. An executable e2e/rig-before-shell.sh may seed state before
# Quickshell starts; e2e/rig-before-capture.sh may perform or verify a live action
# after startup. Both hooks run inside the isolated rig container with HOME,
# XDG_RUNTIME_DIR, WAYLAND_DISPLAY, SWAYSOCK, OMARCHY_PATH, MOD, and PLUGIN_DIR
# exported, and must fail non-zero when their fixture or assertion fails.
set -uo pipefail

TARGET="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
OUT="${2:-$TARGET/preview.png}"
HOST="${OMARCHY_RIG_HOST:-intent-ops-buzz}"
CONTAINER="${OMARCHY_RIG_CONTAINER:-omarchy-rig}"
RES="${OMARCHY_RIG_RESOLUTION:-1280x720}"
SCALE="${OMARCHY_RIG_SCALE:-1.25}"

for tool in jq identify convert; do
  command -v "$tool" >/dev/null 2>&1 || { echo "rig-render: $tool is required" >&2; exit 2; }
done
[[ -f "$TARGET/manifest.json" ]] || { echo "rig-render: no manifest.json in $TARGET" >&2; exit 2; }

MOD="$(jq -r '.id // empty' "$TARGET/manifest.json")"
[[ -n "$MOD" ]] || { echo "rig-render: manifest.json has no id" >&2; exit 2; }
NAME="${MOD##*.}"
RUN_ID="${NAME}-$$"

fingerprint() {
  ( cd "$TARGET" && \
    find . -type f \
      -not -path './.git/*' -not -path './tests/*' \
      -not -path './scripts/*' -not -path './node_modules/*' \
      \( -path './e2e/*' -o -name '*.qml' -o -name '*.js' -o -name 'manifest.json' -o -perm -u+x \) \
      -print0 2>/dev/null \
    | LC_ALL=C sort -z | xargs -0 cat 2>/dev/null | sha256sum | cut -d' ' -f1 )
}

FP="$(fingerprint)"
SOURCE_COMMIT="$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || printf unknown)"
SOURCE_DIRTY=false
if [[ "$SOURCE_COMMIT" == "unknown" ]] || \
   [[ -n "$(git -C "$TARGET" status --porcelain --untracked-files=all -- \
     '*.qml' '*.js' manifest.json bin preview.png README.md assets/banner.svg \
     e2e scripts/rig-render.sh 2>/dev/null)" ]]; then
  SOURCE_DIRTY=true
fi

TGZ="$(mktemp -t rigrender-XXXXXX.tgz)"
REMOTE="$(mktemp -t rigrender-XXXXXX.sh)"
trap 'rm -f "$TGZ" "$REMOTE"' EXIT
tar czf "$TGZ" -C "$TARGET" --exclude=.git --exclude=tests --exclude=scripts \
  --exclude=node_modules --exclude=reports --exclude=coverage \
  --exclude=.rig-proof.json --exclude=.render-proof.json --exclude=preview.png . || {
  echo "rig-render: could not package the runtime tree" >&2; exit 2; }
ARCHIVE_SHA="$(sha256sum "$TGZ" | cut -d' ' -f1)"

echo "rig-render: shipping $NAME to $HOST/$CONTAINER"
scp -q -o BatchMode=yes "$TGZ" "$HOST:/tmp/rigrender-$RUN_ID.tgz" || {
  echo "rig-render: cannot reach $HOST" >&2; exit 2; }

cat > "$REMOTE" <<REMOTE_EOF
#!/bin/sh
set -eu
MOD="$MOD"; NAME="$NAME"; RUN_ID="$RUN_ID"; RES="$RES"; SCALE="$SCALE"
RUNTIME=/tmp/rigrender-runtime-\$RUN_ID
RIG_ROOT=/tmp/rigrender-home-\$RUN_ID
SWAY_CONFIG=/tmp/rigrender-sway-\$RUN_ID.conf
SWAY_LOG=/tmp/rigrender-sway-\$RUN_ID.log
QS_LOG=/tmp/rigrender-qs-\$RUN_ID.log
SHOT=/tmp/rigrender-\$RUN_ID.png
PLUGIN_DIR=\$RIG_ROOT/.config/omarchy/plugins/\$NAME
QS_PID=""; SWAY_PID=""
cleanup() {
  [ -z "\$QS_PID" ] || kill "\$QS_PID" 2>/dev/null || true
  [ -z "\$SWAY_PID" ] || kill "\$SWAY_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

for path in "\$RUNTIME" "\$RIG_ROOT"; do
  if [ -d "\$path" ]; then find "\$path" -depth -delete; fi
done
mkdir -p "\$RUNTIME" "\$PLUGIN_DIR"
chmod 700 "\$RUNTIME" "\$RIG_ROOT" "\$RIG_ROOT/.config" \
  "\$RIG_ROOT/.config/omarchy" "\$RIG_ROOT/.config/omarchy/plugins" "\$PLUGIN_DIR"
tar xzf /tmp/rigrender-\$RUN_ID.tgz -C "\$PLUGIN_DIR"

cat > "\$SWAY_CONFIG" <<SWAY
output * resolution \$RES scale \$SCALE
seat * hide_cursor 1000
SWAY
export XDG_RUNTIME_DIR="\$RUNTIME"
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
  sway --config "\$SWAY_CONFIG" >"\$SWAY_LOG" 2>&1 &
SWAY_PID=\$!
WAYLAND_SOCKET=""; attempt=0
while [ \$attempt -lt 30 ]; do
  WAYLAND_SOCKET=\$(find "\$RUNTIME" -maxdepth 1 -type s -name 'wayland-*' | head -1)
  [ -z "\$WAYLAND_SOCKET" ] || break
  attempt=\$((attempt + 1)); sleep 1
done
[ -n "\$WAYLAND_SOCKET" ] || { echo "rig-render: isolated Wayland socket did not start" >&2; exit 1; }
export WAYLAND_DISPLAY="\${WAYLAND_SOCKET##*/}"
export SWAYSOCK=\$(find "\$RUNTIME" -maxdepth 1 -type s -name 'sway-ipc.*.sock' | head -1)
[ -n "\$SWAYSOCK" ] || { echo "rig-render: isolated Sway IPC socket did not start" >&2; exit 1; }

SETTINGS_FILE=\$PLUGIN_DIR/e2e/render-settings.json
if [ -f "\$SETTINGS_FILE" ]; then
  jq -e 'type == "object" and (has("id") | not)' "\$SETTINGS_FILE" >/dev/null || {
    echo "rig-render: e2e/render-settings.json must be an object without id" >&2; exit 1; }
  jq -n --arg mod "\$MOD" --slurpfile settings "\$SETTINGS_FILE" \
    '{version:1,bar:{position:"top",transparent:false,centerAnchor:\$mod,
      layout:{left:[{id:"omarchy.workspaces"}],center:[],right:[({id:\$mod}+\$settings[0])]}},plugins:[]}' \
    > "\$RIG_ROOT/.config/omarchy/shell.json"
else
  jq -n --arg mod "\$MOD" \
    '{version:1,bar:{position:"top",transparent:false,centerAnchor:\$mod,
      layout:{left:[{id:"omarchy.workspaces"}],center:[],right:[{id:\$mod}]}},plugins:[]}' \
    > "\$RIG_ROOT/.config/omarchy/shell.json"
fi

export HOME="\$RIG_ROOT" OMARCHY_PATH=/root/omarchy PLUGIN_DIR MOD
if [ -d "\$PLUGIN_DIR/e2e/bin" ]; then
  for fixture_command in "\$PLUGIN_DIR"/e2e/bin/*; do
    [ -f "\$fixture_command" ] || continue
    [ -x "\$fixture_command" ] || {
      echo "rig-render: e2e/bin fixture commands must be executable" >&2; exit 1; }
  done
  export PATH="\$PLUGIN_DIR/e2e/bin:\$PATH"
fi

PRE_HOOK=\$PLUGIN_DIR/e2e/rig-before-shell.sh
if [ -f "\$PRE_HOOK" ]; then
  [ -x "\$PRE_HOOK" ] || { echo "rig-render: e2e/rig-before-shell.sh is not executable" >&2; exit 1; }
  "\$PRE_HOOK"
fi

qs -p /root/omarchy/shell >"\$QS_LOG" 2>&1 &
QS_PID=\$!
sleep 18
[ -d "/proc/\$QS_PID" ] || { echo "rig-render: isolated Quickshell exited before IPC" >&2; tail -80 "\$QS_LOG" >&2; exit 1; }

HOOK=\$PLUGIN_DIR/e2e/rig-before-capture.sh
if [ -f "\$HOOK" ]; then
  [ -x "\$HOOK" ] || { echo "rig-render: e2e/rig-before-capture.sh is not executable" >&2; exit 1; }
  "\$HOOK"
fi

qs -p /root/omarchy/shell ipc call "\$MOD" toggle >/dev/null 2>&1
sleep 8
[ -d "/proc/\$QS_PID" ] || { echo "rig-render: isolated Quickshell exited after IPC" >&2; tail -80 "\$QS_LOG" >&2; exit 1; }

echo "===QML WARNINGS==="
grep -a -iE "(WARN|ERROR).*(qml|scene)|(qml|scene).*(WARN|ERROR)|cannot assign|is not a type|unable to|handler was registered|quickshell has crashed" "\$QS_LOG" \
  | grep -avE "libEGL|MESA|ZINK|failed to get driver|failed to create dri2" | head -20
grim "\$SHOT" 2>/dev/null
echo "===RUN=== \$RUN_ID"
echo "===LOGSHA=== \$(sha256sum "\$QS_LOG" | awk '{print \$1}')"
echo "===PACKAGE=== \$(sha256sum /tmp/rigrender-\$RUN_ID.tgz | awk '{print \$1}')"
echo "===SHOT=== \$(ls -l "\$SHOT" 2>/dev/null | awk '{print \$5}') bytes"
REMOTE_EOF

scp -q -o BatchMode=yes "$REMOTE" "$HOST:/tmp/rigrender-$RUN_ID.sh" || exit 2
RESULT="$(ssh -o BatchMode=yes "$HOST" "docker cp /tmp/rigrender-$RUN_ID.tgz $CONTAINER:/tmp/ >/dev/null && \
  docker cp /tmp/rigrender-$RUN_ID.sh $CONTAINER:/tmp/ >/dev/null && \
  docker exec $CONTAINER sh /tmp/rigrender-$RUN_ID.sh" 2>&1)"

WARNINGS="$(printf '%s' "$RESULT" | sed -n '/===QML WARNINGS===/,/===RUN===/p' | grep -vE '===' || true)"
SIZE="$(printf '%s' "$RESULT" | grep -oE '===SHOT=== [0-9]+' | grep -oE '[0-9]+' || true)"
REMOTE_SHA="$(printf '%s' "$RESULT" | grep -oE '===PACKAGE=== [a-f0-9]{64}' | awk '{print $2}' || true)"
RAW_LOG_SHA="$(printf '%s' "$RESULT" | grep -oE '===LOGSHA=== [a-f0-9]{64}' | awk '{print $2}' || true)"
REMOTE_RUN_ID="$(printf '%s' "$RESULT" | grep -oE '===RUN=== [A-Za-z0-9.-]+' | awk '{print $2}' || true)"

if [[ -n "$WARNINGS" ]]; then
  echo "rig-render: shell warnings belong to this plugin run:" >&2
  printf '%s\n' "$WARNINGS" >&2
fi
if [[ -z "$SIZE" || "$SIZE" -lt 4000 ]]; then
  echo "rig-render: no usable screenshot came back (size=${SIZE:-none})" >&2
  printf '%s\n' "$RESULT" >&2
  exit 1
fi
[[ "$REMOTE_SHA" == "$ARCHIVE_SHA" ]] || { echo "rig-render: remote package hash mismatch" >&2; exit 1; }
[[ "$RAW_LOG_SHA" =~ ^[a-f0-9]{64}$ && "$REMOTE_RUN_ID" == "$RUN_ID" ]] || {
  echo "rig-render: raw shell-log provenance is missing or belongs to another run" >&2; exit 1; }

ssh -o BatchMode=yes "$HOST" "docker cp $CONTAINER:/tmp/rigrender-$RUN_ID.png /tmp/rigrender-out-$RUN_ID.png >/dev/null" || exit 1
scp -q -o BatchMode=yes "$HOST:/tmp/rigrender-out-$RUN_ID.png" "$OUT" || exit 1

DIMS="$(identify -format '%wx%h' "$OUT" 2>/dev/null || true)"
COVERAGE="$(convert "$OUT" -colorspace gray -threshold 3% -format '%[fx:mean]' info: 2>/dev/null || true)"
if [[ "$DIMS" != "1280x720" ]]; then
  echo "rig-render: preview dimensions are ${DIMS:-unreadable}, expected 1280x720" >&2; exit 1
fi
if [[ -z "$COVERAGE" ]] || ! awk -v coverage="$COVERAGE" 'BEGIN { exit !(coverage >= 0.35) }'; then
  echo "rig-render: preview nonblack coverage is ${COVERAGE:-unreadable}, expected at least 0.35" >&2; exit 1
fi
if [[ -n "$WARNINGS" ]]; then
  echo "rig-render: refusing to write a clean receipt for a warning-bearing shell log" >&2; exit 1
fi

PREVIEW_SHA="$(sha256sum "$OUT" | cut -d' ' -f1)"
jq -n --arg fp "$FP" --arg commit "$SOURCE_COMMIT" --argjson dirty "$SOURCE_DIRTY" \
  --arg archive "$ARCHIVE_SHA" --arg remote "$REMOTE_SHA" --arg rig "$HOST/$CONTAINER" \
  --arg run "$REMOTE_RUN_ID" --arg logSha "$RAW_LOG_SHA" --arg sha "$PREVIEW_SHA" \
  --arg dimensions "${DIMS/x/ x }" --arg coverage "$COVERAGE" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{fingerprint:$fp,sourceCommit:$commit,sourceDirty:$dirty,
    sourcePackageSha256:$archive,remotePackageSha256:$remote,rig:$rig,runId:$run,rawShellLogSha256:$logSha,
    packageBoundary:"runtime tree; generated proof receipts, reports, tests, developer scripts, and marketplace preview excluded",
    evidenceBoundary:"isolated real Omarchy shell and QML under a dedicated headless compositor; plugin-specific fixture hook when present; live plugin IPC toggle; direct full-frame grim capture with no crop or image post-processing",
    visualInspection:{status:"pending",previewSha256:$sha,checks:[]},
    previewSha256:$sha,dimensions:$dimensions,nonblackCoverage:($coverage|tonumber),capturedAt:$at}' \
  > "$TARGET/.render-proof.json"

echo "rig-render: wrote $OUT (${SIZE} bytes on the rig, ${DIMS}, coverage ${COVERAGE})"
echo "rig-render: loaded clean, no QML warnings"
