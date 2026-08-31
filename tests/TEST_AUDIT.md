# Test audit

Audit date: 2026-08-30

The repository now has blocking evidence at the static, unit, fixture
integration, race, mutation, security-hygiene, and CI layers. The earlier CI
only ran syntax and direct unit tests; it could not detect weak assertions,
shell defects, a stale gate lane, or presentation-proof drift.

## Seven-layer assessment

| Layer | Status | Evidence |
| --- | --- | --- |
| Git hook | Implemented | `.githooks/pre-push` invokes the vendored fail-closed Omarchy lane |
| Static | Implemented | ShellCheck, conflict-marker scan, manifest/banner/CI contracts, C28-C42 |
| Unit | Implemented | 74 deterministic Node tests over `Model.js` |
| Integration | Implemented | Captured schedule, GUMBO, and standings bodies plus request/response contracts |
| System | Pending exact rig | Buzz must validate QML imports and the real Omarchy shell for the candidate tree |
| E2E | Pending exact rig | `e2e/buzz.sh`, rig proof, render proof, and shell log must bind to the candidate hash |
| Acceptance | Pending human approval | Marketplace-scale screenshot inspection and final C43 approval |

## Quality gates

- Coverage: 100% statements, lines, and functions; 97.48% branches.
- Mutation: 90.10% with a blocking 90% floor.
- Race: all 74 tests pass three consecutive clean repetitions.
- Dependency audit: zero known npm vulnerabilities at installation time.
- Shell: all developer, E2E, and pre-push scripts parse cleanly under ShellCheck.
- Presentation: description is 500/500 in both manifest fields and the banner
  is MLB-specific. Current-revision screenshot proof remains intentionally
  blocked on Buzz.

The audit is not a shipment receipt. C43 and the exact-SHA marketplace
verification request remain mandatory after Buzz evidence and push.
