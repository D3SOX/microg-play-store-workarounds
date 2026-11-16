#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 /path/to/PlayStore.apk [/path/to/GmsCore.apk]" >&2
  exit 2
fi

APK=$(readlink -f "$1")
GMS=${2:+$(readlink -f "$2")}
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/playstore_base.zip"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$OUT.tmp"' EXIT

cp -a "$ROOT/module-src/." "$WORK/"
rm -f "$WORK/system/product/priv-app/FakeStore/PUT_PLAYSTORE_APK_HERE.txt"
cp "$APK" "$WORK/system/product/priv-app/FakeStore/FakeStore.apk"
chmod 0644 "$WORK/system/product/priv-app/FakeStore/FakeStore.apk"
if [ -n "$GMS" ]; then
  mkdir -p "$WORK/system/product/priv-app/PrebuiltGmsCore"
  cp "$GMS" "$WORK/system/product/priv-app/PrebuiltGmsCore/PrebuiltGmsCore.apk"
  chmod 0644 "$WORK/system/product/priv-app/PrebuiltGmsCore/PrebuiltGmsCore.apk"
fi

# Keep the previous ZIP until the new one is complete.
rm -f "$OUT.tmp"
(
  cd "$WORK"
  zip -qr "$OUT.tmp" .
)
mv -f "$OUT.tmp" "$OUT"

echo "Created: $OUT"
echo "NOTE: this built ZIP contains Google's Play Store APK. Keep it for personal use; share the source package instead."
