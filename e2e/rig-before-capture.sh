#!/bin/sh
# Refuse a screenshot until every production data path has consumed its
# deterministic render fixture. This makes a loading-state capture impossible.
set -eu

log_file="${XDG_RUNTIME_DIR:?}/mlb-booth-fixture.log"

# Confirm the two background feeds before the rig opens the panel. Opening the
# panel triggers a fresh schedule request and the first GUMBO poll; the
# after-open hook proves that live path before it exposes the settings surface.
attempt=0
while [ "$attempt" -lt 12 ]; do
  ready=true
  for expected in schedule standings; do
    if ! test -s "$log_file" || ! grep -Fx "$expected" "$log_file" >/dev/null; then
      ready=false
      break
    fi
  done
  if [ "$ready" = true ]; then
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

printf 'mlb-booth render fixture did not exercise schedule and standings within 12 seconds\n' >&2
exit 1
