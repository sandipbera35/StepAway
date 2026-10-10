#!/bin/sh
# One place to keep the version in step across every component.
#   tools/version.sh set 0.1.3     write X.Y.Z (and build number X*10000+Y*100+Z) everywhere
#   tools/version.sh check [vX.Y.Z]  fail if anything disagrees (with the tag, when given)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

build_of() { IFS=. read -r a b c <<EOF2
$1
EOF2
  echo $((a * 10000 + b * 100 + c)); }

read_versions() {
  ui=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' ui/pubspec.yaml)
  desktop=$(sed -n 's/^version: *\(.*\)/\1/p' desktop/pubspec.yaml)
  mobile=$(sed -n 's/^version: *\(.*\)/\1/p' mobile/pubspec.yaml)
  cargo=$(sed -n '/^\[workspace.package\]/,/^\[/{s/^version = "\(.*\)"/\1/p}' daemon/Cargo.toml)
  wear=$(sed -n 's/.*versionName = "\(.*\)"/\1/p' wear/app/build.gradle.kts)
  wearcode=$(sed -n 's/.*versionCode = \([0-9]*\)/\1/p' wear/app/build.gradle.kts)
  dartver=$(sed -n "s/^const kAppVersion = '\(.*\)';/\1/p" ui/lib/src/legal.dart)
  dartbuild=$(sed -n 's/^const kBuildNumber = \([0-9]*\);/\1/p' ui/lib/src/legal.dart)
}

case "${1:-}" in
  set)
    v=${2:?usage: version.sh set X.Y.Z}
    case $v in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "version must look like 1.2.3" >&2; exit 2 ;; esac
    n=$(build_of "$v")
    sed -i "s/^version: .*/version: $v/" ui/pubspec.yaml
    sed -i "s/^version: .*/version: $v+$n/" desktop/pubspec.yaml mobile/pubspec.yaml
    sed -i "/^\[workspace.package\]/,/^\[/s/^version = \".*\"/version = \"$v\"/" daemon/Cargo.toml
    sed -i "s/versionName = \".*\"/versionName = \"$v\"/; s/versionCode = [0-9]*/versionCode = $n/" wear/app/build.gradle.kts
    sed -i "s/^const kAppVersion = '.*';/const kAppVersion = '$v';/; s/^const kBuildNumber = [0-9]*;/const kBuildNumber = $n;/" ui/lib/src/legal.dart
    echo "version set to $v (build $n)"
    ;;
  check)
    read_versions
    want=${2:-}
    want=${want#v}
    [ -n "$want" ] || want=$ui
    n=$(build_of "$want")
    bad=0
    chk() { if [ "$2" != "$3" ]; then echo "MISMATCH $1: found '$2', expected '$3'" >&2; bad=1; fi; }
    chk "ui/pubspec.yaml" "$ui" "$want"
    chk "desktop/pubspec.yaml" "$desktop" "$want+$n"
    chk "mobile/pubspec.yaml" "$mobile" "$want+$n"
    chk "daemon/Cargo.toml" "$cargo" "$want"
    chk "wear versionName" "$wear" "$want"
    chk "wear versionCode" "$wearcode" "$n"
    chk "legal.dart kAppVersion" "$dartver" "$want"
    chk "legal.dart kBuildNumber" "$dartbuild" "$n"
    [ $bad -eq 0 ] && echo "all versions are $want (build $n)"
    exit $bad
    ;;
  *) echo "usage: version.sh set X.Y.Z | check [vX.Y.Z]" >&2; exit 2 ;;
esac
