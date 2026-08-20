# MLB Booth

Deep live MLB for the Omarchy bar. Pick any of the 30 clubs. Between games the
pill counts down to first pitch; during one it reads like the booth's
scorecard: score, half inning, count, and outs, refreshed every 20 seconds
from the same GUMBO feed the broadcast graphics run on.

```
󰡒 ATL @ CWS 1h 05m        before the game
󰡒 ATL 1-0 · T4 · 2-2, 0 out    during it
󰡒 ATL W 4-2               after it
```

## Install

```bash
omarchy plugin add https://github.com/jeremylongshore/omarchy-mlb-booth-entry --enable
```

Then add **MLB Booth** to your bar layout (Omarchy menu, Bar, or
`~/.config/omarchy/shell.json`) and pick your team in its settings.

## Remove

```bash
omarchy plugin remove io.github.jeremylongshore.mlb-booth
```

## The panel

Click the pill for the panel:

- **Line score** by inning with R H E, plus bases, count, the live matchup,
  and the last play as the scorer described it.
- **Schedule** for the coming week in your local time.
- **The division race**, your club bolded.
- **The Booth** (optional): a two-sentence storyline between games, written
  by any OpenAI-compatible model you point it at. Off by default; the widget
  is complete without it.

## Data

Everything live comes free and keyless from the MLB Stats API
(statsapi.mlb.com): the schedule endpoint with team and line-score hydration,
the GUMBO live feed per game, and the standings endpoint. No account, no
token, no scraping.

| Feed | Cadence |
| --- | --- |
| Schedule + standings | every 15 minutes |
| GUMBO live feed | every 20 seconds, only while a game runs |
| The Booth recap | once per game-state change, never during live play |

Every fetch is byte-capped and time-capped; a failed or oversized response
keeps the last good state on screen. Every string from the network is
sanitized before it reaches a text element.

## Settings

One setting matters: **Team**. The three AI fields (base URL, model, API key)
are optional and the recap stays off until all three are filled.

## Why not the existing scores plugin

The multi-sport scores widget is wide: every league, one line per game. MLB
Booth is narrow and deep: one club, the full in-game state (count, outs,
bases, last play), the division race, and an optional voice in the booth. If
you follow one team through a season, this is the difference between a
ticker and a scorecard.

## Development

```bash
node --test tests/    # unit suite over captured statsapi fixtures
```

The data layer (`Model.js`) is pure functions and loads in both Quickshell
and node; fixtures under `tests/fixtures/` are real API bodies captured
during a live game. Built from
[omarchy-widget-template](https://github.com/jeremylongshore/omarchy-widget-template).

## License

MIT.
