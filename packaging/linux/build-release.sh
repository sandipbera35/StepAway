#!/bin/sh
# Builds the daemon, then the desktop app with the daemon bundled inside, and packs everything
# into dist/stepaway-linux-x64.tar.gz (extract and run ./install.sh).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
(cd "$root/daemon" && cargo build --release -p stepawayd)
(cd "$root/desktop" && flutter build linux --release)
out="$root/dist/stepaway-linux-x64"
rm -rf "$out"
mkdir -p "$out"
cp -r "$root/desktop/build/linux/x64/release/bundle" "$out/bundle"
cp "$here/install.sh" "$here/uninstall.sh" "$here/io.github.sandipbera35.StepAway.svg" "$root/LICENSE" "$out/"
[ -x "$out/bundle/stepawayd" ] || { echo "stepawayd missing from the bundle" >&2; exit 1; }
tar -C "$root/dist" -czf "$root/dist/stepaway-linux-x64.tar.gz" stepaway-linux-x64
(cd "$root/dist" && sha256sum stepaway-linux-x64.tar.gz > stepaway-linux-x64.tar.gz.sha256)
echo "built $root/dist/stepaway-linux-x64.tar.gz"
