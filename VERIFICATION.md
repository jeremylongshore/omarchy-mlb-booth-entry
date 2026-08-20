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

## Proven on the Omarchy rig

Recorded here as each step lands; unchecked means not yet done.

- [ ] `omarchy-plugin-validate .` passes
- [ ] `qmllint *.qml` clean of errors
- [ ] Installed in a live bar; pill renders in all four states
      (loading, countdown, live, final)
- [ ] Panel opens with line score, bases, last play, schedule, standings
      during a real game
- [ ] preview.png captured from the live render
- [ ] BYOK recap generated once against a real endpoint, then served from
      cache

## Honest boundary

The QML layer is proven by the rig render, not by unit tests. The recap
path's network leg is proven by one manual BYOK run, not CI. Nothing in CI
touches the network.
