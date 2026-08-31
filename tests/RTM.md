# Requirements traceability matrix

| Requirement | Implementation | Automated evidence | Remaining evidence |
| --- | --- | --- | --- |
| Show the chosen club's next, live, and final state | `Model.js`, `BarWidget.qml` | Schedule, state-window, pill, delayed, postponed, suspended, and doubleheader tests | Buzz bar render |
| Show score, inning, count, outs, bases, and last play | `Model.js`, `Panel.qml` | GUMBO fixture, sparse-shape, completed-play, count-reset, and base-state tests | Buzz live or fixture-driven panel render |
| Show local schedule and division race | `Panel.qml`, team/division tables | All clubs, all divisions, schedule ordering, standings ordering and fallback tests | Marketplace-scale visual inspection |
| Bound public API reads | `Panel.qml`, parser size guards | Oversized-body tests, C31, C42 | Buzz process and shell-log evidence |
| Keep optional recap disabled and bounded | `Panel.qml`, recap helpers | Exact request prompt/body, response variants, malformed and oversized tests | Optional manual endpoint test only; never CI |
| Send only selected-club/public-game context to MLB; avoid accounts, identifying data, posting, and telemetry | Read-only fetch paths and manifest copy | C29, C31, C34, C38 and copy contract | Maintainer security review |
| Explain the product within marketplace allowance | `manifest.json` | Exact 500/500 equality and claim-presence test | Live marketplace refresh after final SHA |
| Present a distinct baseball identity | `assets/banner.svg`, `Panel.qml` | Banner semantic test and C40 panel-design pass | Current 1280x720 Buzz preview plus approval |
| Reject stale or fabricated render evidence | rig scripts, C43 | Provenance/approval contract test and C43 fail-closed behavior | Clean `.rig-proof.json` and `.render-proof.json` for candidate tree |
| Prevent regression in repository governance | workflow, hash manifest, conflict scan | Pinned-action CI test, audit harness, ShellCheck, no-conflict test | Green remote workflow on final SHA |
