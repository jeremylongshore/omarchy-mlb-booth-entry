#!/usr/bin/env bash
# Bind an explicit visual inspection to the exact marketplace preview hash.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREVIEW="${1:-$ROOT/preview.png}"
PROOF="${2:-$ROOT/.render-proof.json}"

[[ -s "$PREVIEW" ]] || { echo "approve-preview: preview is missing" >&2; exit 2; }
[[ -s "$PROOF" ]] || { echo "approve-preview: render proof is missing" >&2; exit 2; }
PREVIEW_SHA="$(sha256sum "$PREVIEW" | cut -d' ' -f1)"
RECORDED_SHA="$(jq -r '.previewSha256 // ""' "$PROOF")"
[[ "$PREVIEW_SHA" == "$RECORDED_SHA" ]] || {
  echo "approve-preview: preview hash does not match render proof" >&2; exit 2; }

SHORT_SHA="${PREVIEW_SHA:0:12}"
printf '%s\n' \
  "Inspect the full image at marketplace scale and confirm:" \
  "  - product value is visible without reading the README" \
  "  - no primary content is clipped" \
  "  - the visual identity is specific to this plugin" \
  "Type: approve $SHORT_SHA"
read -r ANSWER
[[ "$ANSWER" == "approve $SHORT_SHA" ]] || {
  echo "approve-preview: approval not recorded" >&2; exit 1; }

INSPECTOR="$(git -C "$ROOT" config user.name 2>/dev/null || true)"
[[ -n "$INSPECTOR" ]] || INSPECTOR="${USER:-unknown}"
TEMP_PROOF="$(mktemp "$ROOT/.render-proof.json.approval.XXXXXXXX")"
trap 'rm -f "$TEMP_PROOF"' EXIT
jq --arg sha "$PREVIEW_SHA" --arg inspector "$INSPECTOR" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.visualInspection = {
    status:"approved", previewSha256:$sha, inspector:$inspector, inspectedAt:$at,
    checks:["product value visible at marketplace scale","no primary content clipped","plugin-specific visual identity"]
  }' "$PROOF" > "$TEMP_PROOF"
mv "$TEMP_PROOF" "$PROOF"
trap - EXIT
echo "approve-preview: approved $SHORT_SHA"
