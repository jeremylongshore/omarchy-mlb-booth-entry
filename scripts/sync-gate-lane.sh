#!/usr/bin/env bash
# Refresh the vendored gate lane from its canonical source and record what was
# taken, so a stale vendored copy can never pass as enforcement again.
#
# Why: the lane is vendored so enforcement travels with the code. But a vendored
# copy is a COPY, and on 2026-08-21 every plugin repo was found running a c36
# older than canonical. mlb-booth's own CI reported PASS on a tree the canonical
# gate blocked with three findings, and mlb-booth was already listed. A gate that
# silently falls behind is worse than no gate, because it reports green.
#
# So this script is the only sanctioned way to update the vendored lane, and it
# writes .lane-manifest, which run-plugin-gates.sh verifies on every run.
#
# Usage: scripts/sync-gate-lane.sh [path-to-canonical-gates-dir]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/gates"
CANON="${1:-$HOME/000-projects/contributing-clanker/skills/contribute/scripts/gates}"
CANON_REPO="${CANON%/skills/*}"

[[ -d "$CANON" ]] || { echo "sync-gate-lane: canonical lane not found at $CANON" >&2; exit 2; }

SHA="$(git -C "$CANON_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY=""
git -C "$CANON_REPO" diff --quiet 2>/dev/null || DIRTY=" (DIRTY WORKTREE)"

# Only the content gates apply to a plugin tree. c32/c33 need rig binaries and
# gate_skip off-rig; c37 needs a rig round trip and is enforced at submission.
mkdir -p "$DEST/lib"
copied=0
for g in "$CANON"/c2[89]-*.sh "$CANON"/c3[01]-*.sh "$CANON"/c3[4-9]-*.sh; do
  [[ -f "$g" ]] || continue
  case "$(basename "$g")" in c32-*|c33-*|c37-*) continue ;; esac
  cp -f "$g" "$DEST/" && copied=$((copied + 1))
done
cp -f "$CANON/lib/preamble.sh" "$DEST/lib/preamble.sh"

{
  echo "# Vendored gate lane. Regenerate with scripts/sync-gate-lane.sh — never hand-edit."
  echo "# canonical: contributing-clanker@${SHA}${DIRTY}"
  ( cd "$DEST" && LC_ALL=C ls c*.sh lib/preamble.sh 2>/dev/null | LC_ALL=C sort | while read -r f; do
      printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
    done )
} > "$DEST/.lane-manifest"

echo "sync-gate-lane: $copied gates + preamble synced from ${SHA:0:12}${DIRTY}"
echo "sync-gate-lane: manifest written to scripts/gates/.lane-manifest"
[[ -n "$DIRTY" ]] && echo "sync-gate-lane: WARNING canonical worktree is dirty; the recorded SHA does not describe what was copied" >&2
exit 0
