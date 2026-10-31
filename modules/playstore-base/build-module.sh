#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/PlayStore.apk" >&2
  exit 2
fi

APK=$(readlink -f "$1")
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/playstore_base.zip"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$OUT.tmp"' EXIT

cp -a "$ROOT/module-src/." "$WORK/"
rm -f "$WORK/system/product/priv-app/FakeStore/PUT_PLAYSTORE_APK_HERE.txt"
cp "$APK" "$WORK/system/product/priv-app/FakeStore/FakeStore.apk"
chmod 0644 "$WORK/system/product/priv-app/FakeStore/FakeStore.apk"

# Keep the previous ZIP until the new one is complete.
rm -f "$OUT.tmp"
(
  cd "$WORK"
  zip -qr "$OUT.tmp" .
)
mv -f "$OUT.tmp" "$OUT"

echo "Created: $OUT"
echo "NOTE: this built ZIP contains Google's Play Store APK. Keep it for personal use; share the source package instead."
