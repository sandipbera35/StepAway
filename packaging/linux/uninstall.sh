#!/bin/sh
# Removes StepAway. Paired devices and settings are kept unless you pass --purge.
set -eu
pkill -x stepawayd 2>/dev/null || true
rm -rf "$HOME/.local/share/stepaway/app"
rm -f "$HOME/.local/share/applications/io.github.sandipbera35.StepAway.desktop" \
  "$HOME/.config/autostart/io.github.sandipbera35.StepAway.Daemon.desktop"
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/stepaway" "$HOME/.local/share/stepaway"
fi
echo "StepAway removed."
