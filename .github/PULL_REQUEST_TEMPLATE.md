## What

<!-- What changed, in one or two sentences. -->

## Why

<!-- The problem this solves. If you chose between approaches, say which and why. -->

## Verification

<!-- Delete any row you did not run. An unrun check is worse than an absent one. -->

| Check | Result |
| --- | --- |
| `npm test` | |
| `scripts/run-plugin-gates.sh .` | |
| `scripts/rig-verify.sh` | |
| `scripts/rig-render.sh` (loaded in a real shell) | |

**If this changes anything visible, say whether you rendered it.**
`omarchy-plugin-validate` and `qmllint` are static: they cannot see a QML
contract error, a missing export, or a shell string that the engine rejects.
Only loading the plugin proves it loads.

## Risk

<!-- What could break, and what the rollback is. -->
