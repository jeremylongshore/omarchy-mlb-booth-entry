# Omarchy Widget Template

A batteries-included skeleton for an Omarchy bar widget. It carries the
architecture and security patterns two shipped entries (Pit Wall, Crew Chief)
earned the hard way, so a new widget starts from a state that already passes
the pre-submit gates.

## What you get

| File | Role |
| --- | --- |
| `BarWidget.qml` | Bar host. Owns the slot and pill button. Shape contract for shell summon/hide/toggle routing. Edit only `moduleName`. |
| `Panel.qml` | Data lifecycle and popup UI. Fetch via `Process` + `StdioCollector`, parse in `Model.js`, fixed omakase constants, IPC handler, `KeyboardPanel` popup scaffold. |
| `Model.js` | Pure data layer. Loads in Quickshell AND node, so the whole parse path unit-tests without a shell. `clean()` sanitizer included. |
| `tests/` | `node --test` harness with fixture loading. Capture real API bodies into `tests/fixtures/`. |
| `manifest.json` | Placeholder manifest with a commented settings schema. |
| `.github/workflows/test.yml` | CI: the node test suite on every push. |

## Instantiate

```bash
gh repo create YOURNAME/omarchy-your-widget-entry --template jeremylongshore/omarchy-widget-template --public --clone
cd omarchy-your-widget-entry
grep -rl 'YOURNAME\|widget-name\|WIDGET NAME' . | xargs sed -i 's/io.github.YOURNAME.widget-name/io.github.YOURNAME.your-widget/g'
```

Then replace the example fetch in `Panel.qml`, the parse functions in
`Model.js`, and the placeholder fields in `manifest.json`.

## The rules the template encodes

These are not style preferences. Each one maps to a defect that shipped in a
real entry and had to be swept after the fact.

1. **Every network body parses in `Model.js`.** Pure functions, node-testable,
   malformed input returns the empty shape so the panel keeps last-good state.
2. **Every API string passes through `Model.clean()`** before a QML `Text`
   sees it. Strips angle brackets (AutoText promotion) and control chars,
   caps length.
3. **Every `Text` that renders API data declares `textFormat:
   Text.PlainText`.** AutoText sniffs strings for HTML; a hostile payload can
   trigger outbound image fetches.
4. **Every curl argv carries `--max-time` and `--max-filesize`.** An
   unbounded body freezes the shell's UI thread on `JSON.parse`.
5. **The pill never silently vanishes.** An unreachable API reads as
   loading, not widget-gone. Return `""` from `label` only when the widget is
   legitimately quiet.
6. **Omakase constants over settings knobs.** Add a manifest settings schema
   only for choices a user genuinely owns.
7. **No em dashes, no private names, no stray tildes in anything shipped.**

## Pre-submit checklist

On the dev box:

```bash
node --test tests/           # unit suite green
~/.contribute-system/bin/gate-runner.sh omarchy-submit "$(pwd)"   # must PASS
```

On an Omarchy rig (the validator and qmllint live there):

```bash
omarchy-plugin-validate .
qmllint *.qml
# install, render, screenshot the pill + open panel for preview.png
```

Only then draft the marketplace submission issue, and have a human approve
the body before posting.

## License

MIT.
