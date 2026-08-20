# Verification record

What has actually been proven, how, and what remains.

## Unit suite (dev box + CI)

**47 tests, all passing** (`npm test`). The whole `Model.js` data layer:
schedule parse, game-state selection, GUMBO parse, pill text, standings,
and the BYOK recap request and response shapes. Assertions against the live
capture check ground truth (ATL @ CWS, gamePk 824589, top of the 4th, 2-2
count, 0 out, Matt Olson batting); the status shapes statsapi rarely serves
are synthesized from the documented status codes: postponed and cancelled
(abstract Final with no score), suspended (abstract Live), delayed starts
(abstract Preview past first pitch), and split doubleheaders. A drift test
pins the manifest's team picker to the team table.

Fixture capture commands (2026-08-20, during the live game):

```bash
curl -s "https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=144&hydrate=team,linescore&startDate=2026-08-19&endDate=2026-08-27" -o tests/fixtures/statsapi-schedule.json
curl -s "https://statsapi.mlb.com/api/v1/standings?leagueId=103,104&season=2026" -o tests/fixtures/statsapi-standings.json
curl -s "https://statsapi.mlb.com/api/v1.1/game/824589/feed/live" | jq '{gameData: {status: .gameData.status, teams: {away: {abbreviation: .gameData.teams.away.abbreviation, name: .gameData.teams.away.name}, home: {abbreviation: .gameData.teams.home.abbreviation, name: .gameData.teams.home.name}}}, liveData: {linescore: .liveData.linescore, plays: {currentPlay: {count: .liveData.plays.currentPlay.count, matchup: {batter: {fullName: .liveData.plays.currentPlay.matchup.batter.fullName}, pitcher: {fullName: .liveData.plays.currentPlay.matchup.pitcher.fullName}}, about: .liveData.plays.currentPlay.about}, allPlays: [.liveData.plays.allPlays[] | {about: {isComplete: .about.isComplete}, result: {description: .result.description, event: .result.event}}]}}}' > tests/fixtures/statsapi-gumbo-live.json
```

## Static checks (dev box)

Pre-submit content sweep via the author's local contribute-system gate
runner (tooling lives outside this repo): em and en dash scan over the docs
and manifest, a private-name denylist over contents and filenames, a
strikethrough scan, a check that every QML `Text` binding data declares
`textFormat`, and a check that every curl argv carries `--max-filesize`.
All pass. CI runs the portable slice: JS syntax over every tracked file,
manifest field assertions, and a no-symlinks check.

## Four-reviewer panel (2026-08-20, pre-submission)

Security, correctness, taste, and Omarchy-idiom reviews ran against the
built plugin before submission. What they caught and this repo then fixed:

- **Security:** the BYOK base URL reaching curl unvalidated (a dash-prefixed
  settings value parses as curl options; `file://` was accepted). Now: the
  URL must match `https://`, the argv pins `--proto =https` and terminates
  option parsing with `--`. Also: the innings list is capped at parse, all
  parsers enforce an in-process 4 MB bound before `JSON.parse`, and
  `clean()` strips bidi overrides and Unicode tag characters.
- **Correctness:** a rain-delayed game (abstract Preview past first pitch)
  collapsed the widget exactly when a user would look at it; postponed
  games (abstract Final, no score) could render a phantom `ATL T 0-0`;
  suspended games (abstract Live) wedged the pill in live mode; the
  postgame window measured from first pitch, which skipped game one's
  result on every split doubleheader; a failed recap fetch was never
  retried and a stale recap could linger under the next game; the
  BarWidget popout-switch contract called a function the panel did not
  define. All fixed and covered by the synthetic-status tests above.
- **Taste:** the tooltip carried em dashes; the preview showed the finished
  batter still at the plate (the same GUMBO end-of-at-bat artifact the
  count fix addressed, now also fixed for the matchup); the broadcast
  claim was softened to what is checkable (Gameday, not broadcast
  graphics); dead exports removed.
- **Idiom:** the pill glyph was dropped (the marketplace-accepted sibling
  ships a plain-text pill, and the glyph was Nerd Fonts v3-only); the
  unproven `string` settings-form type was removed from the manifest schema
  (nothing in the shell tree renders schema types today; the three AI
  values configure via the widget's `shell.json` entry, which is what the
  settings accessor reads).

## Proven on the Omarchy rig (2026-08-20, during ATL @ CWS)

- [x] `omarchy-plugin-validate .` exit 0
- [x] `qmllint BarWidget.qml Panel.qml` 0 errors, exit 0 (warnings are the
      same import-path class the first-party widgets carry)
- [x] Installed in a live bar (headless sway plus Hyprland plus
      quickshell); pill rendered live from the real game
- [x] Panel opened during the game: line score with R H E, count, runner
      on second, batter and pitcher, last play prose, schedule, NL East
      race
- [x] preview.png captured from that live render
- [x] The live render caught a real boundary bug on the spot: the pill read
      `3-3, 1 out` the instant a strikeout ended an at-bat (GUMBO keeps the
      finished count until the next play); countText() now resets it 0-0

## Proven against a real completion endpoint (2026-08-20)

- [x] The exact curl argv Panel.qml builds, executed with the request body
      from `recapRequestBody` and fixture-derived context, against a hosted
      OpenAI-compatible API (Groq, openai/gpt-oss-120b): returned a correct
      storyline with the right record, streak, loss, and next opponent;
      `parseRecap` extracted and sanitized it.
- [x] That run caught two real compatibility bugs first: 220 max_tokens
      starved a reasoning model into `finish_reason: "length"` with empty
      content (now 700), and typed content-part arrays parsed to nothing
      (now joined).

## Honest boundary

The QML layer is proven by the rig render, not by unit tests. The pill's
countdown and final states are unit-tested but not yet rig-rendered (that
needs a game-day boundary). The recap's network leg is one manual
round-trip, not CI. Nothing in CI touches the network.
