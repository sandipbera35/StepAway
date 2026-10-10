#!/bin/sh
# Installs StepAway for the current user (no root needed).
# Works from the release archive (./bundle next to this script) or from a repository checkout
# after `build-release.sh`. The desktop app starts the bundled daemon itself and registers it to
# start at login the first time it runs.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
if [ -d "$here/bundle" ]; then
  bundle="$here/bundle"
else
  case $(uname -m) in aarch64|arm64) arch=arm64 ;; *) arch=x64 ;; esac
  bundle="$here/../../desktop/build/linux/$arch/release/bundle"
fi
[ -x "$bundle/stepaway_desktop" ] || { echo "no app bundle found; run build-release.sh first" >&2; exit 1; }
[ -x "$bundle/stepawayd" ] || { echo "the bundle does not contain stepawayd; rebuild with the daemon built first" >&2; exit 1; }

dest="$HOME/.local/share/stepaway/app"
# stop an older daemon so the new one is picked up
pkill -x stepawayd 2>/dev/null || true
rm -rf "$dest"
install -d "$(dirname "$dest")" "$HOME/.local/share/applications"
cp -r "$bundle" "$dest"

icon_src="$here/io.github.sandipbera35.StepAway.svg"
icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
if [ -f "$icon_src" ]; then
  install -d "$icon_dir"
  install -m 644 "$icon_src" "$icon_dir/io.github.sandipbera35.StepAway.svg"
fi

cat > "$HOME/.local/share/applications/io.github.sandipbera35.StepAway.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=StepAway
Comment=Lock your computer when your phone moves away
Exec="$dest/stepaway_desktop"
Icon=io.github.sandipbera35.StepAway
StartupWMClass=io.github.sandipbera35.stepaway_desktop
Categories=Utility;Security;
Terminal=false
DESKTOP
echo "StepAway installed. Open it from your application menu and pair your phone."
