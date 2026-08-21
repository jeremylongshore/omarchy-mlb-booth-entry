#!/usr/bin/env bash
# Point git at the in-repo hooks. Run once per clone.
#
# Hooks are deliberately not shipped in .git/hooks: git does not carry that
# directory, so a hook that lives there exists only on the machine that made
# it. core.hooksPath makes the tracked directory authoritative, which is the
# same reason the gates themselves are vendored rather than referenced from a
# personal tool.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
git -C "$ROOT" config core.hooksPath .githooks
echo "hooks installed: $(git -C "$ROOT" config core.hooksPath)"
echo "pre-push will run scripts/run-plugin-gates.sh"
