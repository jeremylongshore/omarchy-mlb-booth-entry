# Security

## Threat model

MLB Booth renders strings from two sources inside the shell process: the MLB
Stats API (keyless, always on) and, only if the user opts in, an
OpenAI-compatible completion endpoint of their choosing.

## Controls

1. Network bodies only ever hit `JSON.parse` inside `Model.js` pure
   functions, behind a hard in-process length check (4 MB). Malformed,
   truncated, or oversized input returns the empty shape and the panel
   keeps last-good state. Nothing from the network is evaluated.
2. Strings go through `Model.clean()` before any text element sees them:
   angle brackets out (defuses Qt AutoText promotion to StyledText, which
   could otherwise fetch an `<img>` URL from inside the shell), ASCII
   controls out, bidi override marks and Unicode tag characters out, length
   capped.
3. `textFormat: Text.PlainText` on every data-bound `Text` in the panel, as
   a second layer over the sanitizer. Two sinks leave this plugin's control:
   the bar pill and its tooltip render inside first-party shell components
   whose text format this plugin does not set, so on those two paths the
   sanitizer is the only layer.
4. `--max-time` and `--max-filesize` on every curl argv, with `--` closing
   option parsing before the URL. The filesize flag only binds when the
   server sends a length (and only over HTTP), which is why the real bound
   is the in-process check in control 1; a body that gets truncated at the
   curl cap simply fails `JSON.parse` and the panel keeps last-good.
5. Bounded list rendering: the innings table is capped at the parse
   boundary and windowed in the view, so a corrupt feed cannot turn a
   Repeater into a hundred thousand items on the UI thread.
6. The recap is fenced. The base URL must match `https://` before the
   fetch is even built, and the argv pins `--proto =https`, so the key can
   only travel TLS to the host the user configured; a dash-prefixed or
   `file://` settings value never reaches curl as an option. The request
   fires once per game-state change, never during live play, and carries
   only the compact fact context the widget itself assembled. The response
   passes the same sanitizer with a hard length cap and is rendered as
   plain text only; it is never used as a URL, a path, or a command.

## BYOK key handling

The optional API key lives in your local shell settings and rides an
Authorization header that is written to curl over stdin, using
`--header @-`. It is never an argv element, so it does not appear in the
local process table and `ps` cannot read it. This is the same mechanism the
first-party network panel uses for a wifi passphrase.

An earlier version of this document described the opposite, because an
earlier version of the code passed the key as `-H "Authorization: Bearer
..."` and I argued the exposure was acceptable on a single-user desktop.
That was wrong, the marketplace reviewer was right to flag it, and the code
was corrected in 22642a4. The reasoning is left here rather than deleted
because a security document that quietly rewrites its own history is worth
less than one that shows where it was wrong.

The key is still stored in plain text in your shell settings, so anyone
running as your uid can read `shell.json` directly. Do not configure it on a
machine you share. Leaving the three AI values empty keeps the widget fully
keyless with zero outbound traffic beyond statsapi.mlb.com.

## Reporting

Open an issue on this repository, or email jeremy@intentsolutions.io for
anything sensitive.
