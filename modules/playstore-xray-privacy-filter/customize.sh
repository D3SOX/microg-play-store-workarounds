#!/system/bin/sh

# Installer for APatch / KernelSU / Magisk-style module managers.
# ARM64 only: this module uses the official Xray-core Android arm64-v8a build.

XRAY_VERSION="v26.9.9"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-android-arm64-v8a.zip"
XRAY_ZIP_SHA256="f18625edf2360df8f857d8a2d947f69dd137b31849e7b9b530200d7e5f482766"

say() {
    if command -v ui_print >/dev/null 2>&1; then
        ui_print "$*"
    else
        echo "$*"
    fi
}

fail() {
    say "! $*"
    exit 1
}

ABI="$(getprop ro.product.cpu.abi 2>/dev/null)"
case "$ABI" in
    arm64-v8a|arm64*) ;;
    *) fail "Unsupported ABI: $ABI. This ZIP currently supports ARM64 Android only." ;;
esac

mkdir -p "$MODPATH/bin" || fail "Could not create module bin directory"

# Prefer an already-tested local Xray binary when upgrading.
if [ -x /data/adb/playstore_xray/xray ]; then
    say "- Reusing existing /data/adb/playstore_xray/xray"
    cp /data/adb/playstore_xray/xray "$MODPATH/bin/xray" || fail "Could not copy existing Xray binary"
elif [ -x /data/adb/modules/playstore_xray_privacy_filter/bin/xray ]; then
    say "- Reusing existing module Xray binary"
    cp /data/adb/modules/playstore_xray_privacy_filter/bin/xray "$MODPATH/bin/xray" || fail "Could not copy existing module Xray binary"
else
    WORK="/data/local/tmp/playstore-xray-filter-installer.$$"
    ZIP="$WORK/xray.zip"
    OUT="$WORK/out"
    mkdir -p "$OUT" || fail "Could not create temporary directory"

    say "- Downloading official Xray-core ${XRAY_VERSION} ARM64 release"

    DOWNLOADED=0
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --connect-timeout 20 -o "$ZIP" "$XRAY_URL" && DOWNLOADED=1
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$ZIP" "$XRAY_URL" && DOWNLOADED=1
    elif [ -x /data/adb/ap/bin/busybox ]; then
        /data/adb/ap/bin/busybox wget -O "$ZIP" "$XRAY_URL" && DOWNLOADED=1
    elif [ -x /data/adb/ksu/bin/busybox ]; then
        /data/adb/ksu/bin/busybox wget -O "$ZIP" "$XRAY_URL" && DOWNLOADED=1
    elif [ -x /data/adb/magisk/busybox ]; then
        /data/adb/magisk/busybox wget -O "$ZIP" "$XRAY_URL" && DOWNLOADED=1
    fi

    [ "$DOWNLOADED" = "1" ] || fail "Could not download Xray. Install Xray manually at /data/adb/playstore_xray/xray and flash this ZIP again."

    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL="$(sha256sum "$ZIP" | awk '{print $1}')"
    elif command -v busybox >/dev/null 2>&1; then
        ACTUAL="$(busybox sha256sum "$ZIP" | awk '{print $1}')"
    else
        rm -rf "$WORK"
        fail "sha256sum unavailable; refusing to install an unverified download"
    fi

    [ "$ACTUAL" = "$XRAY_ZIP_SHA256" ] || {
        rm -rf "$WORK"
        fail "Xray archive SHA-256 mismatch"
    }

    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$ZIP" -d "$OUT" || fail "Could not extract Xray archive"
    elif command -v busybox >/dev/null 2>&1; then
        busybox unzip "$ZIP" -d "$OUT" >/dev/null || fail "Could not extract Xray archive"
    elif [ -x /data/adb/ap/bin/busybox ]; then
        /data/adb/ap/bin/busybox unzip "$ZIP" -d "$OUT" >/dev/null || fail "Could not extract Xray archive"
    else
        rm -rf "$WORK"
        fail "unzip unavailable"
    fi

    [ -f "$OUT/xray" ] || {
        rm -rf "$WORK"
        fail "xray executable not found in release archive"
    }

    cp "$OUT/xray" "$MODPATH/bin/xray" || fail "Could not install Xray binary"
    rm -rf "$WORK"
fi

chmod 0755 "$MODPATH/bin/xray"
chmod 0755 "$MODPATH/service.sh" "$MODPATH/uninstall.sh"
chmod 0644 "$MODPATH/config.json" "$MODPATH/module.prop"

say "- Xray binary:"
"$MODPATH/bin/xray" version 2>/dev/null | head -n 2 | while IFS= read -r line; do say "  $line"; done

say "- No App2Proxy or Android VPN is required."
say "- Filters only the main-user Google Play Store UID."
say "- Allowed Play Store hosts:"
say "    play.googleapis.com"
say "    play-fe.googleapis.com"
say "    gmscompliance-pa.googleapis.com"
say "    remoteprovisioning.googleapis.com"
say "- All other Play Store TCP destinations are denied."
say "- Reboot after installation."
