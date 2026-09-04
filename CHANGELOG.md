# Changelog

Notable changes to MLB Booth.

Entries are derived from this repository's commit history, so every line
corresponds to a real change. The format follows Keep a Changelog and the
project uses Semantic Versioning.

Regenerate with `scripts/gen-changelog.sh`.

## [Unreleased]

Nothing yet.

## [1.1.0] - 2026-09-04

### Added

- Settings page in the popup (gear, or right-click the pill): favorite club and 12-hour or 24-hour first-pitch times
- `timeFormat` widget setting (`12h` or `24h`, default `24h`) written to the existing bar entry

## [1.0.0] - 2026-08-22

### Security

- Pass the BYOK api key over stdin, never a curl argv
- Bound every Text, restore the schedule right alignment, and correct SECURITY.md
- Bound every unbounded Text so long API data cannot clip the row

### Added

- MLB Booth v1.0.0: deep live MLB widget for the Omarchy bar
- Survive reasoning models and content-part arrays; ship live previews
- Rebuild the banner to the sibling standard
- Colour the division race and the schedule by club

### Fixed

- Keep line-score abbr bindings QString-typed before the first GUMBO poll, and read games-back as 'back' not 'GB'
- Reset a completed at-bat's count to 0-0 for display, broadcast style
- Apply the four-reviewer panel findings before submission
- Banner font stack falls back through ui-monospace and Menlo

### Internal

Tooling and repository changes with no effect on the shipped plugin.

- Refresh previews from the post-fix live render (bottom 5th)
- Add install and removal instructions
- Previews from the post-panel-fix live render, pill in frame
- Vendor the submission gate lane, CI and a pre-push hook
- Vendor c38 and widen the rig fingerprint to cover shipped .js
- Vendor rig-render, which loads the plugin into a real shell
- Add four-lane MiniMax review and backfill the changelog

