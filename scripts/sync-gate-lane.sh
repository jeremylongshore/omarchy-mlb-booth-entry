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
set -euo pipefail
shopt -s nullglob

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/gates"
CANON="${1:-$HOME/000-projects/contributing-clanker/skills/contribute/scripts/gates}"
CANON_REPO="${CANON%/skills/*}"

[[ -d "$CANON" ]] || { echo "sync-gate-lane: canonical lane not found at $CANON" >&2; exit 2; }

SHA="$(git -C "$CANON_REPO" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$SHA" ]] || { echo "sync-gate-lane: canonical source is not a Git worktree" >&2; exit 2; }
CANON_REL="${CANON#"$CANON_REPO"/}"
SOURCE_STATUS="$(git -C "$CANON_REPO" status --porcelain --untracked-files=all -- "$CANON_REL")"
if [[ -n "$SOURCE_STATUS" ]]; then
  echo "sync-gate-lane: REFUSING dirty canonical gate source" >&2
  printf '%s\n' "$SOURCE_STATUS" >&2
  echo "  commit or discard canonical gate changes before vendoring them" >&2
  exit 2
fi

# Only the content gates apply to a plugin tree. c32/c33 need rig binaries and
# gate_skip off-rig; c37 needs a rig round trip and is enforced at submission.
# An explicit list, not a glob.
#
# A glob is wrong in both directions here. The first version enumerated decades
# (c2x, c3x) and silently copied 8 gates instead of 9 when c40 was added. Widening
# it to every two-digit gate then swept in c01 through c27, which are PR-flow
# gates that expect a candidate markdown file and have no meaning against a
# plugin tree.
#
# So the applicable set is written down. Adding a gate here is a deliberate act,
# and the count assertion below turns any mismatch into a visible warning rather
# than a quietly shorter lane.
#
# Deliberately excluded: c32 and c33 need rig binaries and gate_skip off-rig;
# c37 needs a rig round trip and is enforced at submission time by the hook.
# c41 and c42 were added after five local-only helpers reached marketplace
# security review: the former blocks mutable-path lifecycle theater, the latter
# catches unbounded local scans before they hit a periodic QML poller.
# c43 treats listing copy, the themed banner, and a hash-bound live preview as
# release artifacts instead of optional polish.
APPLICABLE="c28 c29 c30 c31 c34 c35 c36 c38 c40 c41 c42 c43"

mkdir -p "$DEST/lib"
copied=0
for id in $APPLICABLE; do
  matches=("$CANON/$id"-*.sh)
  if [[ "${#matches[@]}" -ne 1 ]]; then
    echo "sync-gate-lane: expected exactly one canonical $id gate, found ${#matches[@]}" >&2
    exit 2
  fi
  src="${matches[0]}"
  cp -f "$src" "$DEST/" && copied=$((copied + 1))
done
# Any vendored gate that is no longer applicable must go, or the lane keeps
# running a check the source of truth has retired.
# Collect first, then delete. Removing inside the glob mutates the very list
# being iterated, so the first run only pruned part of the set and the script
# needed running twice to converge.
STALE=""
for f in "$DEST"/c*.sh; do
  [[ -e "$f" ]] || continue
  id=$(basename "$f" | cut -d- -f1)
  case " $APPLICABLE " in *" $id "*) ;; *) STALE="$STALE $f" ;; esac
done
for f in $STALE; do
  rm -f "$f"
  echo "sync-gate-lane: removed retired $(basename "$f" | cut -d- -f1)"
done
cp -f "$CANON/lib/preamble.sh" "$DEST/lib/preamble.sh"

{
  echo "# Vendored gate lane. Regenerate with scripts/sync-gate-lane.sh — never hand-edit."
  echo "# canonical: contributing-clanker@${SHA}"
  ( cd "$DEST" && LC_ALL=C ls c*.sh lib/preamble.sh 2>/dev/null | LC_ALL=C sort | while read -r f; do
      printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
    done )
} > "$DEST/.lane-manifest"

AVAIL=$(echo "$APPLICABLE" | wc -w)
echo "sync-gate-lane: $copied of $AVAIL applicable gates + preamble synced from ${SHA:0:12}"
if [[ "$copied" -ne "$AVAIL" ]]; then
  echo "sync-gate-lane: copied $copied but $AVAIL are listed applicable" >&2
  exit 2
fi
echo "sync-gate-lane: manifest written to scripts/gates/.lane-manifest"
exit 0
