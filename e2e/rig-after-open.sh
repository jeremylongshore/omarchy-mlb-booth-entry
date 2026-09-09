#!/bin/sh
# Open the settings surface after the live panel is up so a Buzz render
# (and any owner-runnable capture) shows the new UI, not only the game panel.
# Invoked by scripts/rig-render.sh when this file is present and executable.
set -eu
: "${MOD:?}"

log_file="${XDG_RUNTIME_DIR:?}/mlb-booth-fixture.log"
attempt=0
while [ "$attempt" -lt 12 ]; do
  ready=true
  for expected in schedule standings gumbo; do
    if ! test -s "$log_file" || ! grep -Fx "$expected" "$log_file" >/dev/null; then
      ready=false
      break
    fi
  done
  if [ "$ready" = true ]; then
    qs -p /root/omarchy/shell ipc call "$MOD" settings
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

printf 'mlb-booth render fixture did not exercise the live GUMBO feed within 12 seconds after open\n' >&2
exit 1
