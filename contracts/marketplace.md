# Marketplace contract

MLB Booth ships one `barWidget` whose public listing and runtime widget share
the same product promise.

- `manifest.description` and `manifest.barWidget.description` are identical and
  exactly 500 characters.
- The description states the visible bar and panel outcomes, polling cadence,
  source APIs, optional recap boundary, account boundary, and write boundary.
- `assets/banner.svg` identifies MLB Booth and depicts baseball-specific state.
- `preview.png` is accepted only with current-tree Buzz provenance, an exact
  1280x720 capture, a clean shell-log hash, and explicit visual approval.
- The plugin reads public MLB data and performs no league-account writes.
- Optional recap requests remain disabled until the user supplies and enables
  their own compatible endpoint credentials.

`tests/contract.test.js` and gate C43 enforce the machine-checkable portions.
