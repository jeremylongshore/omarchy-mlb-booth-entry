#!/bin/sh
# Refuse a screenshot until every production data path has consumed its
# deterministic render fixture. This makes a loading-state capture impossible.
set -eu

log_file="${XDG_RUNTIME_DIR:?}/mlb-booth-fixture.log"
test -s "$log_file"
for expected in schedule standings gumbo; do
  grep -Fx "$expected" "$log_file" >/dev/null
done
