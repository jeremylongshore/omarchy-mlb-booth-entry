#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/rig-verify.sh" "$ROOT"
"$ROOT/scripts/rig-render.sh" "$ROOT" "$ROOT/preview.png"
test -s "$ROOT/preview.png"
jq -e '
  .dimensions == "1280 x 720" and
  .sourceDirty == false and
  .sourcePackageSha256 == .remotePackageSha256 and
  .visualInspection.status == "pending" and
  (.rawShellLogSha256 | test("^[a-f0-9]{64}$"))
' "$ROOT/.render-proof.json" >/dev/null
