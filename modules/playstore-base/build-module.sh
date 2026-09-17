#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/PlayStore.apk" >&2
  exit 2
fi

APK=$(readlink -f "$1")
ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp -a "$ROOT/module-src/." "$WORK/"
rm -f "$WORK/system/product/priv-app/FakeStore/PUT_PLAYSTORE_APK_HERE.txt"
cp "$APK" "$WORK/system/product/priv-app/FakeStore/FakeStore.apk"
chmod 0644 "$WORK/system/product/priv-app/FakeStore/FakeStore.apk"

(
  cd "$WORK"
  zip -qr "$ROOT/playstore_base.zip" .
)

echo "Created: $ROOT/playstore_base.zip"
echo "NOTE: this built ZIP contains Google's Play Store APK. Keep it for personal use; share the source package instead."
