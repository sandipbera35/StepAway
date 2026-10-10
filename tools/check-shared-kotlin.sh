#!/bin/sh
# The phone app and the watch app each carry a copy of the protocol code (token, pairing offer).
# They must stay byte-identical apart from the package line, or the two devices could disagree.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
phone="$root/mobile/android/app/src/main/kotlin/io/github/sandipbera35/stepaway_mobile"
watch="$root/wear/app/src/main/kotlin/io/github/sandipbera35/stepaway/wear"
status=0
for f in Token.kt Offer.kt; do
  if ! diff -q "$phone/$f" "$watch/$f" >/dev/null 2>&1 && \
     ! [ "$(sed 1d "$phone/$f" | sed 's/stepaway_mobile/X/g')" = "$(sed 1d "$watch/$f" | sed 's/stepaway.wear/X/g')" ]; then
    echo "MISMATCH: $f differs between the phone and watch apps" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "shared Kotlin protocol code is identical in both apps"
exit $status
