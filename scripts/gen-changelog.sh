#!/usr/bin/env bash
# Backfill a Keep a Changelog CHANGELOG.md from this repo's real commit history.
# Entries are derived from conventional commit subjects, never invented.
# Usage: scripts/gen-changelog.sh [repo-dir] [plugin-name] [version]
set -uo pipefail

ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
NAME="${2:-}"
VERSION="${3:-}"

command -v jq >/dev/null 2>&1 || { echo "gen-changelog: jq is required" >&2; exit 2; }
[[ -f "$ROOT/manifest.json" ]] || { echo "gen-changelog: no manifest.json in $ROOT" >&2; exit 2; }
[[ -n "$NAME" ]] || NAME="$(jq -r '.name // "this plugin"' "$ROOT/manifest.json")"
[[ -n "$VERSION" ]] || VERSION="$(jq -r '.version // "1.0.0"' "$ROOT/manifest.json")"

# Unanchored "bound" covers bound, bounded, and unbounded security fixes.
SEC_RE='secur|token|credential|argv|ssrf|inject|bound|leak|proc/|memory|exhaust'

added=""; changed=""; fixed=""; security=""; internal=""
last_date=""

# Reverse order preserves the chronology inside each generated section.
while IFS=$'\t' read -r subject date; do
  [[ -n "$subject" ]] || continue
  [[ "$subject" =~ ^([a-z]+)(\(([^\)]*)\))?!?:[[:space:]]*(.+)$ ]] || continue
  typ="${BASH_REMATCH[1]}"
  scope="${BASH_REMATCH[3]}"
  rest="${BASH_REMATCH[4]}"
  last_date="$date"

  rest="$(printf '%s' "$rest" | /usr/bin/sed -E 's/[[:space:]]*\(#[0-9]+\)$//')"
  rest="$(printf '%s' "$rest" | /usr/bin/sed -e 's/ — /: /g' -e 's/ – /: /g' -e 's/—/, /g' -e 's/–/, /g')"
  rest="$(printf '%s' "$rest" | /usr/bin/sed -E 's/^(.)/\U\1/')"

  line="- $rest"
  case "$typ" in
    feat) added+="$line"$'\n' ;;
    fix)
      if printf '%s %s' "$scope" "$rest" | /usr/bin/grep -qiE "$SEC_RE"; then
        security+="$line"$'\n'
      else
        fixed+="$line"$'\n'
      fi ;;
    perf|refactor|style) changed+="$line"$'\n' ;;
    ci|build|chore|test|docs) internal+="$line"$'\n' ;;
    *) changed+="$line"$'\n' ;;
  esac
done < <(/usr/bin/git -C "$ROOT" log --reverse --pretty=$'%s\t%cs')

dedupe() { printf '%s' "$1" | /usr/bin/awk 'NF && !seen[$0]++'; }

OUT="$ROOT/CHANGELOG.md"
{
  echo "# Changelog"
  echo
  echo "Notable changes to $NAME."
  echo
  echo "Entries are derived from this repository's commit history, so every line"
  echo "corresponds to a real change. The format follows Keep a Changelog and the"
  echo "project uses Semantic Versioning."
  echo
  echo "Regenerate with \`scripts/gen-changelog.sh\`."
  echo
  echo "## [Unreleased]"
  echo
  echo "Nothing yet."
  echo
  echo "## [$VERSION] - ${last_date:-unreleased}"
  echo
  if [[ -n "$security" ]]; then echo "### Security"; echo; dedupe "$security"; echo; fi
  if [[ -n "$added" ]]; then echo "### Added"; echo; dedupe "$added"; echo; fi
  if [[ -n "$changed" ]]; then echo "### Changed"; echo; dedupe "$changed"; echo; fi
  if [[ -n "$fixed" ]]; then echo "### Fixed"; echo; dedupe "$fixed"; echo; fi
  if [[ -n "$internal" ]]; then
    echo "### Internal"
    echo
    echo "Tooling and repository changes with no effect on the shipped plugin."
    echo
    dedupe "$internal"
    echo
  fi
} > "$OUT"

# Surface non-conventional subjects that the deterministic classifier skipped.
TOTAL=$(/usr/bin/git -C "$ROOT" log --pretty=%s | /usr/bin/wc -l)
KEPT=$(/usr/bin/grep -c '^- ' "$OUT" || true)
SKIPPED=$((TOTAL - KEPT))
echo "gen-changelog: wrote $(basename "$ROOT")/CHANGELOG.md ($(/usr/bin/wc -l < "$OUT") lines, $KEPT entries)"
if [[ "$SKIPPED" -gt 0 ]]; then
  echo "gen-changelog: $SKIPPED of $TOTAL commits were not conventional and are absent from the changelog" >&2
  /usr/bin/git -C "$ROOT" log --pretty=%s \
    | /usr/bin/grep -vE '^[a-z]+(\([^)]*\))?!?: ' \
    | /usr/bin/head -5 | /usr/bin/sed 's/^/  skipped: /' >&2
fi
