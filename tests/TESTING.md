# Testing posture

## What runs where

| Layer | Where | What |
| --- | --- | --- |
| Unit | dev box + CI, `npm test` | The whole `Model.js` data layer against captured statsapi bodies plus synthetic edge shapes: schedule parse, game-state selection (including postponed, suspended, delayed start, and split doubleheaders), GUMBO parse, pill text, standings, BYOK recap request and response, and a drift gate pinning the manifest's team picker to the team table. |
| Static | CI | JS syntax over every tracked file, manifest field assertions, no-symlinks check. |
| Static | dev box | The contribute-system pre-submit gates (local tooling): em-dash scan over docs, private-name denylist, strikethrough scan, QML textFormat and curl-bound checks. |
| Static | Omarchy rig | `qmllint *.qml`, `omarchy-plugin-validate .` |
| Live render | Omarchy rig | Install, render the pill and open panel during a real game. MLB plays daily, so this needs no faked clock. |

## Fixtures

`tests/fixtures/` holds real MLB Stats API bodies captured 2026-08-20 during
ATL @ CWS (gamePk 824589, top of the 4th): the schedule window with a final,
a live, and six future games; the GUMBO feed trimmed to the subtree the
parser reads; the full two-league standings body. Capture commands are in
VERIFICATION.md. The status shapes statsapi rarely serves (postponed,
suspended, delayed start, doubleheaders) are synthesized in the test file
from the documented status codes, since no capture window reliably contains
them.

## Honest boundary

The unit suite proves the data layer. The QML layer (bindings, timers,
process wiring, popup layout) is exercised only by the rig render; there is
no QML unit harness here. The recap path is tested against canned JSON in
CI; one manual round-trip against a hosted endpoint is recorded in
VERIFICATION.md.
