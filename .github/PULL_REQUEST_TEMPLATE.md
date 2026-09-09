## What

<!-- What changed, in one or two sentences. -->

## Why

<!-- The problem this solves. If you chose between approaches, say which and why. -->

## Change type

- [ ] Documentation only
- [ ] Code, tests, manifest, automation, or runtime behavior
- [ ] Visible QML, layout, controls, or graphics

## Verification

<!-- Report only checks you ran. Never imply that an unavailable check passed. -->

| Check | Required when | Result |
| --- | --- | --- |
| `scripts/run-plugin-gates.sh .` | Every change | |
| `npm ci && npm test` | Anything beyond documentation | |
| Screenshot and interaction notes | Visible changes | |

Contributors do not need access to the private Buzz rig. After code review, a
maintainer runs `scripts/rig-verify.sh` and `scripts/rig-render.sh` for
applicable changes. Do not edit `.rig-proof.json`, `.render-proof.json`,
`preview.png`, or files under `scripts/gates/`.

## Risk

<!-- What could break, and what the rollback is. -->
