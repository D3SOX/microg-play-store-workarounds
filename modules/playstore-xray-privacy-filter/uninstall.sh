#!/system/bin/sh

STATE="/data/adb/playstore_xray_privacy_filter"
PIDFILE="/dev/playstore_xray_privacy_filter.xray.pid"
OLD_PIDFILE="$STATE/xray.pid"
DOWNLOAD_COMPONENT="com.android.vending/com.google.android.finsky.downloadservice.DownloadService"
DOWNLOAD_MARKER="$STATE/downloadservice_disabled_by_module"

LINE="$(cmd package list packages -U 2>/dev/null | grep '^package:com.android.vending ' | head -n1)"
UIDS="${LINE##*uid:}"
PLAY_UID="${UIDS%%,*}"

case "$PLAY_UID" in
    ''|*[!0-9]*) PLAY_UID="" ;;
esac

if [ -n "$PLAY_UID" ]; then
    while iptables -t nat -C OUTPUT \
        -p tcp -m owner --uid-owner "$PLAY_UID" \
        -j REDIRECT --to-ports 12345 2>/dev/null; do
        iptables -t nat -D OUTPUT \
            -p tcp -m owner --uid-owner "$PLAY_UID" \
            -j REDIRECT --to-ports 12345
    done

    while iptables -t nat -C OUTPUT \
        -p udp --dport 53 -m owner --uid-owner "$PLAY_UID" \
        -j REDIRECT --to-ports 10853 2>/dev/null; do
        iptables -t nat -D OUTPUT \
            -p udp --dport 53 -m owner --uid-owner "$PLAY_UID" \
            -j REDIRECT --to-ports 10853
    done

    while iptables -C OUTPUT \
        -p udp --dport 443 -m owner --uid-owner "$PLAY_UID" \
        -j REJECT 2>/dev/null; do
        iptables -D OUTPUT \
            -p udp --dport 443 -m owner --uid-owner "$PLAY_UID" \
            -j REJECT
    done

    if command -v ip6tables >/dev/null 2>&1; then
        while ip6tables -C OUTPUT \
            -m owner --uid-owner "$PLAY_UID" \
            -j REJECT 2>/dev/null; do
            ip6tables -D OUTPUT \
                -m owner --uid-owner "$PLAY_UID" \
                -j REJECT
        done
    fi
fi

for PF in "$PIDFILE" "$OLD_PIDFILE"; do
    if [ -f "$PF" ]; then
        PID="$(cat "$PF" 2>/dev/null)"
        if [ -n "$PID" ] && [ "$(readlink "/proc/$PID/exe" 2>/dev/null)" = "$(dirname "$0")/bin/xray" ]; then
            kill "$PID" 2>/dev/null
        fi
    fi
done

# Restore DownloadService only if this module was the thing that disabled it.
if [ -f "$DOWNLOAD_MARKER" ]; then
    pm enable --user 0 "$DOWNLOAD_COMPONENT" >/dev/null 2>&1
fi

rm -f "$PIDFILE"
rm -rf "$STATE"
