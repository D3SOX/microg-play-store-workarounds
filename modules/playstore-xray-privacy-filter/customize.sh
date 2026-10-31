#!/system/bin/sh

# Installer for APatch / KernelSU / Magisk-style module managers.
# ARM64 only: this module uses the official Xray-core Android arm64-v8a build.

XRAY_VERSION="v26.10.31"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-android-arm64-v8a.zip"
XRAY_ZIP_SHA256="ee7878bb47ce28ff5b068e2d173ba1a9fab20ca1aec94191644919ec08ba5f1d"

say() {
    if command -v ui_print >/dev/null 2>&1; then
        ui_print "$*"
    else
        echo "$*"
    fi
}

WORK=""

# abort (from the module installer) also removes the partially staged module.
fail() {
    [ -z "$WORK" ] || rm -rf "$WORK"
    if command -v abort >/dev/null 2>&1; then
        abort "! $*"
    fi
    say "! $*"
    exit 1
}

ABI="$(getprop ro.product.cpu.abi 2>/dev/null)"
case "$ABI" in
    arm64-v8a|arm64*) ;;
    *) fail "Unsupported ABI: $ABI. This ZIP currently supports ARM64 Android only." ;;
esac

mkdir -p "$MODPATH/bin" || fail "Could not create module bin directory"

# Install the pinned release on upgrades as well as fresh installations.
WORK="$(mktemp -d "${TMPDIR:-/data/local/tmp}/playstore-xray-filter.XXXXXX")" ||
    fail "Could not create temporary directory"
ZIP="$WORK/xray.zip"
OUT="$WORK/out"
mkdir -p "$OUT" || fail "Could not create temporary directory"

BUSYBOXES="busybox /data/adb/ap/bin/busybox /data/adb/ksu/bin/busybox /data/adb/magisk/busybox"

say "- Downloading official Xray-core ${XRAY_VERSION} ARM64 release"

DOWNLOADED=0
for TOOL in curl wget $BUSYBOXES; do
    command -v "$TOOL" >/dev/null 2>&1 || continue
    case "$TOOL" in
        curl) curl -L --fail --connect-timeout 20 -o "$ZIP" "$XRAY_URL" ;;
        wget) wget -O "$ZIP" "$XRAY_URL" ;;
        *) "$TOOL" wget -O "$ZIP" "$XRAY_URL" ;;
    esac && {
        DOWNLOADED=1
        break
    }
done

[ "$DOWNLOADED" = "1" ] || fail "Could not download Xray. Check network access and flash this ZIP again."

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL="$(sha256sum "$ZIP" | awk '{print $1}')"
elif command -v busybox >/dev/null 2>&1; then
    ACTUAL="$(busybox sha256sum "$ZIP" | awk '{print $1}')"
else
    fail "sha256sum unavailable; refusing to install an unverified download"
fi

[ "$ACTUAL" = "$XRAY_ZIP_SHA256" ] || fail "Xray archive SHA-256 mismatch"

EXTRACTED=0
for TOOL in unzip $BUSYBOXES; do
    command -v "$TOOL" >/dev/null 2>&1 || continue
    case "$TOOL" in
        unzip) unzip -q "$ZIP" -d "$OUT" ;;
        *) "$TOOL" unzip "$ZIP" -d "$OUT" >/dev/null ;;
    esac && {
        EXTRACTED=1
        break
    }
done

[ "$EXTRACTED" = "1" ] || fail "Could not extract Xray archive"
[ -f "$OUT/xray" ] || fail "xray executable not found in release archive"

cp "$OUT/xray" "$MODPATH/bin/xray" || fail "Could not install Xray binary"
rm -rf "$WORK"

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
say "- All other Play Store traffic is denied."
say "- Reboot after installation."
