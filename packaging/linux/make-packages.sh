#!/bin/sh
# Builds dist/stepaway_<version>_<amd64|arm64>.deb and dist/stepaway-<version>-1.<x86_64|aarch64>.rpm from the
# Flutter bundle produced by build-release.sh (run that first). Needs dpkg-deb and rpmbuild.
# Usage: make-packages.sh [version]   (default: version in desktop/pubspec.yaml)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
case $(uname -m) in
  x86_64) flutter_arch=x64; deb_arch=amd64; rpm_arch=x86_64 ;;
  aarch64|arm64) flutter_arch=arm64; deb_arch=arm64; rpm_arch=aarch64 ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
bundle="$root/desktop/build/linux/$flutter_arch/release/bundle"
ver=${1:-$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$root/desktop/pubspec.yaml")}
ver=${ver#v}
id=io.github.sandipbera35.StepAway
[ -x "$bundle/stepaway_desktop" ] && [ -x "$bundle/stepawayd" ] || { echo "run build-release.sh first" >&2; exit 1; }
out="$root/dist"; mkdir -p "$out"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# Shared file tree: app in /opt/stepaway, launcher in /usr/bin, desktop entry + icon.
tree="$work/tree"
install -d "$tree/opt" "$tree/usr/bin" "$tree/usr/share/applications" "$tree/usr/share/icons/hicolor/scalable/apps" "$tree/usr/share/doc/stepaway" "$tree/usr/share/metainfo"
cp -r "$bundle" "$tree/opt/stepaway"
ln -s ../../opt/stepaway/stepaway_desktop "$tree/usr/bin/stepaway"
install -m 644 "$here/$id.svg" "$tree/usr/share/icons/hicolor/scalable/apps/$id.svg"
sed "s/VERSION/$ver/" "$here/$id.metainfo.xml" > "$tree/usr/share/metainfo/$id.metainfo.xml"
doc="$tree/usr/share/doc/stepaway"
install -m 644 "$here/debian-copyright" "$doc/copyright"
install -m 644 "$root/LICENSE" "$doc/LICENSE"
install -m 644 "$root/PRIVACY.md" "$doc/PRIVACY.md"
install -m 644 "$root/THIRD_PARTY_LICENSES.txt" "$doc/THIRD_PARTY_LICENSES.txt"
printf 'stepaway (%s) unstable; urgency=low\n\n  * Release %s. See https://github.com/sandipbera35/StepAway/releases\n\n -- sandipbera35 <sandipbera35@users.noreply.github.com>  %s\n' "$ver" "$ver" "$(date -R)" | gzip -9n > "$doc/changelog.gz"
install -m 644 "$here/$id.desktop" "$tree/usr/share/applications/$id.desktop"
chmod -R u+rwX,go+rX-w "$tree"

# ---- .deb ----
deb="$work/deb"; cp -r "$tree" "$deb"; install -d "$deb/DEBIAN"
size=$(du -sk "$tree" | cut -f1)
cat > "$deb/DEBIAN/control" <<CTL
Package: stepaway
Version: $ver
Section: utils
Priority: optional
Architecture: $deb_arch
Depends: libgtk-3-0, libdbus-1-3, bluez
Installed-Size: $size
Maintainer: sandipbera35 <sandipbera35@users.noreply.github.com>
Homepage: https://github.com/sandipbera35/StepAway
Description: Lock your computer when your phone moves away
 StepAway locks (and optionally unlocks) this computer based on the Bluetooth
 signal of your paired Android phone. Everything stays local.
CTL
cat > "$deb/DEBIAN/prerm" <<'SH'
#!/bin/sh
pkill -x stepawayd 2>/dev/null || true
exit 0
SH
chmod 755 "$deb/DEBIAN/prerm"
dpkg-deb --root-owner-group --build "$deb" "$out/stepaway_${ver}_${deb_arch}.deb" >/dev/null

# ---- .rpm ----
top="$work/rpm"; mkdir -p "$top/BUILD" "$top/RPMS" "$top/SOURCES" "$top/SPECS" "$top/SRPMS"
cat > "$top/SPECS/stepaway.spec" <<SPEC
Name: stepaway
Version: $ver
Release: 1
Summary: Lock your computer when your phone moves away
License: GPL-3.0-or-later
URL: https://github.com/sandipbera35/StepAway
BuildArch: $rpm_arch
AutoReqProv: no
Requires: gtk3, dbus-libs, bluez
%global debug_package %{nil}
%global __os_install_post %{nil}
%description
StepAway locks (and optionally unlocks) this computer based on the Bluetooth
signal of your paired Android phone. Everything stays local.
%install
cp -a $tree/. %{buildroot}/
%preun
pkill -x stepawayd 2>/dev/null || :
%files
/opt/stepaway
/usr/bin/stepaway
/usr/share/applications/$id.desktop
/usr/share/metainfo/$id.metainfo.xml
/usr/share/icons/hicolor/scalable/apps/$id.svg
%license /usr/share/doc/stepaway/LICENSE
%license /usr/share/doc/stepaway/THIRD_PARTY_LICENSES.txt
%doc /usr/share/doc/stepaway/PRIVACY.md
/usr/share/doc/stepaway/copyright
/usr/share/doc/stepaway/changelog.gz
%changelog
* $(date '+%a %b %d %Y') sandipbera35 <sandipbera35@users.noreply.github.com> - $ver-1
- Release $ver. See https://github.com/sandipbera35/StepAway/releases
SPEC
rpmbuild -bb --define "_topdir $top" --define "_build_id_links none" "$top/SPECS/stepaway.spec" >/dev/null
cp "$top"/RPMS/$rpm_arch/*.rpm "$out/"
(cd "$out" && sha256sum stepaway_${ver}_${deb_arch}.deb stepaway-${ver}-1.${rpm_arch}.rpm > packages-$deb_arch.sha256)
echo "built: $out/stepaway_${ver}_${deb_arch}.deb $out/stepaway-${ver}-1.${rpm_arch}.rpm"
