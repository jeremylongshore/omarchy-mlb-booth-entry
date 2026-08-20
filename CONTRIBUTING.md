# Contributing

Small, focused changes are welcome.

## Ground rules

1. **The data layer stays pure.** Anything that parses or formats lives in
   `Model.js`, loads in node, and gets a test against a captured fixture.
   No network access in tests, ever.
2. **The containment pattern is not negotiable.** The controls are listed
   in [SECURITY.md](SECURITY.md); a PR that relaxes any of them gets closed
   with a pointer there.
3. **Omakase over knobs.** Cadences and row counts are fixed constants.
   Argue for a new setting only when a user genuinely owns the choice, the
   way the team picker is.
4. **Run the suite before pushing:** `npm test`.

## Adding or refreshing fixtures

Capture real statsapi bodies (exact commands in VERIFICATION.md), trim the
GUMBO feed to the subtree the parser reads, and update the assertions to the
captured ground truth. Say in the PR when and during which game the capture
happened.

## Style

Match the file you are in. Plain prose in docs: no em dashes, no filler.
