# Testing posture

## What runs where

| Layer | Where | What |
| --- | --- | --- |
| Unit (32 tests) | dev box + CI, `node --test tests/` | The whole `Model.js` data layer against captured statsapi bodies: schedule parse, game-state selection, GUMBO parse, pill text, standings, BYOK recap request/response. |
| Static | dev box | `gate-runner.sh omarchy-submit` content gates (voice, private names, strikethrough, QML Text/curl security). |
| Static | Omarchy rig | `qmllint *.qml`, `omarchy-plugin-validate .` |
| Live render | Omarchy rig | Install, render the pill and open panel during a real game. MLB plays daily, so this needs no faked clock. |

## Fixtures

`tests/fixtures/` holds real MLB Stats API bodies captured 2026-08-20 during
ATL @ CWS (gamePk 824589, top of the 4th): the schedule window with a final,
a live, and six future games; the GUMBO feed trimmed to the subtree the
parser reads; the full two-league standings body. Capture commands are in
VERIFICATION.md.

## Honest boundary

The unit suite proves the data layer. The QML layer (bindings, timers,
process wiring, popup layout) is exercised only by the rig render; there is
no QML unit harness here. The recap path is tested against canned JSON, not
a live model endpoint.
