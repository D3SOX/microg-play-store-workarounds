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

# Flashable privacy module.
(
  cd "$ROOT/modules/playstore-xray-privacy-filter"
  zip -qr "$DIST/playstore_xray_privacy_filter-v1.2-arm64.zip" .
)

# Flashable provenance-repair module.
(
  cd "$ROOT/modules/play-provenance-repair"
  zip -qr "$DIST/play_provenance_repair-v1.1.6.zip" .
)

(
  cd "$DIST"
  sha256sum *.zip > SHA256SUMS
)

cat "$DIST/SHA256SUMS"
