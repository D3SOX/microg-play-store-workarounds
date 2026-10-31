#!/system/bin/sh

MODDIR=${0%/*}
STATE="/data/adb/playstore_xray_privacy_filter"
PIDFILE="/dev/playstore_xray_privacy_filter.xray.pid"
OLD_PIDFILE="$STATE/xray.pid"
CHAIN="playstore_xray"
DOWNLOAD_COMPONENT="com.android.vending/com.google.android.finsky.downloadservice.DownloadService"
DOWNLOAD_MARKER="$STATE/downloadservice_disabled_by_module"

# The chains only exist if the module is removed without a reboot.
for SPEC in "iptables filter" "ip6tables filter" "iptables nat"; do
    # shellcheck disable=SC2086 # split "binary table"
    set -- $SPEC
    while "$1" -w -t "$2" -D OUTPUT -j "$CHAIN" 2>/dev/null; do :; done
    "$1" -w -t "$2" -F "$CHAIN" 2>/dev/null
    "$1" -w -t "$2" -X "$CHAIN" 2>/dev/null
done

for PF in "$PIDFILE" "$OLD_PIDFILE"; do
    if [ -f "$PF" ]; then
        PID="$(cat "$PF" 2>/dev/null)"
        if [ -n "$PID" ] && [ "$(readlink "/proc/$PID/exe" 2>/dev/null)" = "$MODDIR/bin/xray" ]; then
            kill "$PID" 2>/dev/null
        fi
    fi
done
rm -f "$PIDFILE"

# Restore DownloadService only if this module was the thing that disabled it.
# Root managers usually run this script early in boot, before PackageManager
# is up, and the disabled state persists, so wait for boot completion. Keep the
# marker if enabling fails so the cause stays visible.
if [ -f "$DOWNLOAD_MARKER" ]; then
    (
        until [ "$(getprop sys.boot_completed)" = "1" ]; do
            sleep 2
        done
        pm enable --user 0 "$DOWNLOAD_COMPONENT" >/dev/null 2>&1 && rm -rf "$STATE"
    ) </dev/null >/dev/null 2>&1 &
else
    rm -rf "$STATE"
fi
