#!/usr/bin/env bash
# Print docs only when every changed path is presentation or contributor prose.
# Any uncertainty fails safe to the full behavioral suite.
set -euo pipefail

base="${1:-}"
head="${2:-HEAD}"

if [[ -z "$base" || "$base" =~ ^0+$ ]]; then
  echo full
  exit 0
fi

if ! git cat-file -e "$base^{commit}" 2>/dev/null ||
   ! git cat-file -e "$head^{commit}" 2>/dev/null; then
  echo full
  exit 0
fi

changed="$(git diff --name-only --diff-filter=ACDMRTUXB "$base" "$head")"
if [[ -z "$changed" ]]; then
  echo full
  exit 0
fi

while IFS= read -r path; do
  case "$path" in
    *.md|docs/*|.github/ISSUE_TEMPLATE/*.yml|.github/ISSUE_TEMPLATE/*.yaml|\
      .github/FUNDING.yml|LICENSE)
      ;;
    *)
      echo full
      exit 0
      ;;
  esac
done <<< "$changed"

echo docs
