#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIST="$ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

# Source-only base bundle. The user's Play Store APK is intentionally absent.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/playstore_base_module_source"
cp -a "$ROOT/modules/playstore-base/." "$TMP/playstore_base_module_source/"
(
  cd "$TMP"
  zip -qr "$DIST/playstore_base_module_source.zip" playstore_base_module_source
)

# Module metadata is the source of truth for archive names.
for MODULE in playstore-xray-privacy-filter play-provenance-repair; do
  MODDIR="$ROOT/modules/$MODULE"
  ID=$(sed -n 's/^id=//p' "$MODDIR/module.prop")
  VERSION=$(sed -n 's/^version=//p' "$MODDIR/module.prop")
  VERSION="${VERSION#v}"
  [[ "$ID" =~ ^[a-zA-Z0-9_]+$ && "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || {
    echo "Invalid module metadata: $MODULE" >&2
    exit 1
  }
  SUFFIX=""
  [[ "$MODULE" != playstore-xray-privacy-filter ]] || SUFFIX="-arm64"
  (
    cd "$MODDIR"
    zip -qr "$DIST/${ID}-v${VERSION}${SUFFIX}.zip" .
  )
done

# Print hashes for the build log without creating separate checksum assets.
sha256sum "$DIST"/*.zip
