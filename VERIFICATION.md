# Verification record

What has actually been proven, how, and what remains.

## Proven on the dev box (2026-08-20)

**Unit suite: 32/32.** `node --test tests/` over the whole `Model.js` data
layer. Fixtures are real MLB Stats API bodies captured that day during a
live game (ATL @ CWS, gamePk 824589, top 4th, 2-2 count, 0 out), so the
GUMBO assertions (score, inning, count, bases, batter and pitcher, last
play) check against ground truth, not hand-written samples.

Fixture capture commands:

```bash
curl -s "https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=144&hydrate=team,linescore&startDate=2026-08-19&endDate=2026-08-27" -o tests/fixtures/statsapi-schedule.json
curl -s "https://statsapi.mlb.com/api/v1.1/game/824589/feed/live" | jq '<trimmed to the parsed subtree>' > tests/fixtures/statsapi-gumbo-live.json
curl -s "https://statsapi.mlb.com/api/v1/standings?leagueId=103,104&season=2026" -o tests/fixtures/statsapi-standings.json
```

**Pre-submit content gates: PASS.** `gate-runner.sh omarchy-submit` (the
contribute system's deterministic sweep): no em dashes, no private names, no
stray strikethrough tildes, every `Text` binding data declares
`textFormat`, every curl argv byte-capped.

**Pill format, live, against the real feed:** the captured moment renders
`ATL 1-0 · T4 · 2-2, 0 out`, asserted in the unit suite.

## Proven on the Omarchy rig (2026-08-20, during ATL @ CWS)

- [x] `omarchy-plugin-validate .` exit 0
- [x] `qmllint BarWidget.qml Panel.qml` 0 errors, exit 0 (warnings are the
      same import-path class the first-party widgets carry)
- [x] Installed in a live bar (headless sway + Hyprland + quickshell);
      pill rendered live: `ATL 1-0 · T5 · 1-2, 0 out`
- [x] Panel opened during the game: line score with R H E, count, runner
      on 2nd, batter and pitcher, last play prose, schedule, NL East race
- [x] preview.png captured from that live render
- [x] The live render caught and fixed a real boundary bug: the pill read
      `3-3, 1 out` the instant a strikeout ended an at-bat (GUMBO keeps the
      finished count until the next play); countText() now resets it 0-0

## Proven against a real completion endpoint (2026-08-20)

- [x] The exact curl argv Panel.qml builds, executed with the request body
      from `recapRequestBody` and fixture-derived context, against a hosted
      OpenAI-compatible API (Groq, openai/gpt-oss-120b): returned a
      3-sentence storyline with the correct record, streak, loss, and next
      opponent; `parseRecap` extracted and sanitized it.
- [x] That run caught two real compatibility bugs first: 220 max_tokens
      starved a reasoning model into `finish_reason: "length"` with empty
      content (now 700), and typed content-part arrays parsed to nothing
      (now joined).

- [ ] Pill's countdown and final states rig-rendered (unit-tested only;
      render them after a game day boundary)

## Honest boundary

The QML layer is proven by the rig render, not by unit tests. The recap
path's network leg is proven by one manual BYOK run, not CI. Nothing in CI
touches the network.
