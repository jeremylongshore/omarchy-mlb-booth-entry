#!/usr/bin/env bash
# Backfill a Keep a Changelog CHANGELOG.md from this repo's real commit history.
#
# Entries are DERIVED, never invented: a line is here only because a commit says
# so. Conventional-commit type picks the section, and a `fix` whose scope or
# subject concerns a credential, a bound, an injection or an SSRF is filed under
# Security rather than Fixed, because "what did this protect me from" is what a
# reader of a desktop-plugin changelog is actually looking for.
#
# Written in bash, not python, because gate c35 is right: a stock Omarchy install
# has no python3 on the graphical session PATH, and a shipped .py in a plugin
# repo is a runtime dependency waiting to be mistaken for one. The first version
# of this script was python and this repo's own pre-push hook refused it.
#
# Em and en dashes are normalised on the way out. A CHANGELOG is shipped prose,
# gate c28 refuses those characters, and commit subjects predate that rule, so a
# naive backfill produces a file this repo's own lane rejects.
#
# Usage: scripts/gen-changelog.sh [repo-dir] [plugin-name] [version]
set -uo pipefail

ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
NAME="${2:-}"
VERSION="${3:-}"

command -v jq >/dev/null 2>&1 || { echo "gen-changelog: jq is required" >&2; exit 2; }
[[ -f "$ROOT/manifest.json" ]] || { echo "gen-changelog: no manifest.json in $ROOT" >&2; exit 2; }
[[ -n "$NAME"    ]] || NAME="$(jq -r '.name // "this plugin"' "$ROOT/manifest.json")"
[[ -n "$VERSION" ]] || VERSION="$(jq -r '.version // "1.0.0"' "$ROOT/manifest.json")"

SEC_RE='secur|token|credential|argv|ssrf|inject|unbounded|bound |leak|proc/|memory'

added=""; changed=""; fixed=""; security=""; internal=""
last_date=""

# --reverse so the oldest change is listed first inside each section, which is
# the order the work actually happened in.
while IFS=$'\t' read -r subject date; do
  [[ -n "$subject" ]] || continue
  # Only conventional commits are classified; anything else is skipped rather
  # than guessed at.
  [[ "$subject" =~ ^([a-z]+)(\(([^\)]*)\))?!?:[[:space:]]*(.+)$ ]] || continue
  typ="${BASH_REMATCH[1]}"
  scope="${BASH_REMATCH[3]}"
  rest="${BASH_REMATCH[4]}"
  last_date="$date"

  # Drop a trailing PR reference; this is a record, not a link farm.
  rest="$(printf '%s' "$rest" | /usr/bin/sed -E 's/[[:space:]]*\(#[0-9]+\)$//')"
  # Normalise dashes, spaced form first so it becomes a colon rather than a comma.
  rest="$(printf '%s' "$rest" | /usr/bin/sed -e 's/ — /: /g' -e 's/ – /: /g' -e 's/—/, /g' -e 's/–/, /g')"
  # Sentence case, since a commit subject is imperative and lower case.
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
  # Security first: on a desktop plugin it is the section a reader scans for.
  if [[ -n "$security" ]]; then echo "### Security"; echo; dedupe "$security"; echo; fi
  if [[ -n "$added"    ]]; then echo "### Added";    echo; dedupe "$added";    echo; fi
  if [[ -n "$changed"  ]]; then echo "### Changed";  echo; dedupe "$changed";  echo; fi
  if [[ -n "$fixed"    ]]; then echo "### Fixed";    echo; dedupe "$fixed";    echo; fi
  if [[ -n "$internal" ]]; then
    echo "### Internal"
    echo
    echo "Tooling and repository changes with no effect on the shipped plugin."
    echo
    dedupe "$internal"
    echo
  fi
} > "$OUT"

echo "gen-changelog: wrote $(basename "$ROOT")/CHANGELOG.md ($(/usr/bin/wc -l < "$OUT") lines)"
