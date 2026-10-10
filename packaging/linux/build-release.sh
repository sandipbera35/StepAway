#!/bin/sh
# Builds the daemon, then the desktop app with the daemon bundled inside, and packs everything
# into dist/stepaway-linux-$arch.tar.gz (extract and run ./install.sh).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
case $(uname -m) in
  x86_64) arch=x64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
(cd "$root/daemon" && cargo build --release -p stepawayd)
(cd "$root/desktop" && flutter build linux --release)
out="$root/dist/stepaway-linux-$arch"
rm -rf "$out"
mkdir -p "$out"
cp -r "$root/desktop/build/linux/$arch/release/bundle" "$out/bundle"
cp "$here/install.sh" "$here/uninstall.sh" "$here/io.github.sandipbera35.StepAway.svg" "$root/LICENSE" "$out/"
[ -x "$out/bundle/stepawayd" ] || { echo "stepawayd missing from the bundle" >&2; exit 1; }
tar -C "$root/dist" -czf "$root/dist/stepaway-linux-$arch.tar.gz" stepaway-linux-$arch
(cd "$root/dist" && sha256sum stepaway-linux-$arch.tar.gz > stepaway-linux-$arch.tar.gz.sha256)
echo "built $root/dist/stepaway-linux-$arch.tar.gz"
