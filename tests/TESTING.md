# Testing posture

## Local and CI gates

| Layer | Command | Current evidence |
| --- | --- | --- |
| Static contract | `npm test` | Exact 500/500 copy, product banner semantics, pinned CI, clean conflict-marker scan, render-proof contract |
| Unit and fixture integration | `npm test` | 74 tests; 100% statements, lines, functions; 97.48% branches |
| Race repetition | `npm run test:race` | Three clean repetitions of all 74 tests |
| Mutation | `npm run test:mutation` | 90.10%; 825 killed, 3 timeout, 91 survived; blocking floor 90% |
| Shell | `shellcheck --severity=warning scripts/*.sh e2e/*.sh .githooks/pre-push` | Pass |
| Repository integrity | `npm run audit` | Hash verification plus deep audit and scan |
| Omarchy policy | `scripts/run-plugin-gates.sh .` | C28-C42 pass; C43 blocks until current Buzz proof |
| Production E2E | `npm run test:e2e` | Must run on Buzz against the exact candidate revision |

GitHub Actions uses commit-pinned actions and runs install, unit/coverage,
race, mutation, audit, and ShellCheck. CI does not call public sports or recap
APIs.

## Fixtures

`tests/fixtures/` contains bounded MLB Stats API captures from ATL at CWS on
2026-08-20. Synthetic cases cover rare or boundary states including postponed,
suspended, delayed-start, split-doubleheader, malformed, oversized, sparse,
and hostile response shapes. The complete team and division reference tables
are pinned by value, not merely counted.

## Honest boundary

Node tests prove the pure data model and repository contracts. They do not
prove QML imports, shell wiring, popup geometry, or marketplace readability.
Those require a current-revision Buzz run, a clean shell log, an exact 1280x720
preview, and explicit human approval. Historical render evidence is not accepted
for changed source.
