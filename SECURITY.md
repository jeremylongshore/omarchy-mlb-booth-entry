# Security

## Threat model

MLB Booth renders strings from two classes of source inside the shell
process: the MLB Stats API (keyless, always on) and, only if the user opts
in, an OpenAI-compatible completion endpoint of their choosing.

## Controls

1. **Every network body parses in `Model.js` pure functions.** Malformed or
   truncated JSON returns the empty shape; the panel keeps last-good state.
   Nothing from the network is ever evaluated.
2. **Every string passes `Model.clean()`** before a `Text` element sees it:
   angle brackets stripped (defuses Qt AutoText promotion to StyledText,
   which could otherwise fetch an `<img>` URL from inside the shell),
   control characters stripped, length capped.
3. **Every `Text` that renders network data declares
   `textFormat: Text.PlainText`** as a second layer over the sanitizer.
4. **Every curl argv carries `--max-time` and `--max-filesize`.** A GUMBO
   feed grows through a game; the cap means an oversized body makes curl
   exit non-zero and the collector delivers nothing, instead of the UI
   thread stalling on a giant `JSON.parse`.
5. **The recap is fenced.** It never runs during live play, fires once per
   game-state change (cached by key), sends only the compact fact context
   the widget itself assembled, and its response passes the same sanitizer
   with a hard length cap.

## BYOK key handling

The optional API key lives in your local Omarchy shell settings and is sent
only to the base URL you configure, as an Authorization header on a curl
invocation. Because it is passed as a process argument, it is briefly
visible in the local process table (`/proc`) while the request runs, which
is the standard tradeoff for shell-side BYOK widgets on a single-user
desktop. Do not configure the key on a multi-user machine you do not
control. Leaving the three AI settings empty keeps the widget fully keyless
with zero outbound traffic beyond statsapi.mlb.com.

## Reporting

Open an issue on this repository, or email jeremy@intentsolutions.io for
anything sensitive.
