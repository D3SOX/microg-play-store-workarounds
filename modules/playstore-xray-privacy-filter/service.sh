#!/system/bin/sh

MODDIR=${0%/*}
STATE="/data/adb/playstore_xray_privacy_filter"
XRAY="$MODDIR/bin/xray"
CONFIG="$MODDIR/config.json"
BOOTLOG="$STATE/boot.log"

# /dev is tmpfs, so this PID file cannot survive a reboot and point at a
# recycled PID. Keep compatibility cleanup for v1.0's persistent PID file.
PIDFILE="/dev/playstore_xray_privacy_filter.xray.pid"
OLD_PIDFILE="$STATE/xray.pid"

DOWNLOAD_COMPONENT="com.android.vending/com.google.android.finsky.downloadservice.DownloadService"
DOWNLOAD_MARKER="$STATE/downloadservice_disabled_by_module"

mkdir -p "$STATE"
: > "$BOOTLOG"
rm -f "$OLD_PIDFILE"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$BOOTLOG"
}

log "starting"

# Reuse Xray only if the PID actually belongs to this module's binary.
if [ -f "$PIDFILE" ]; then
    OLD_PID="$(cat "$PIDFILE" 2>/dev/null)"
    OLD_EXE=""
    [ -n "$OLD_PID" ] && OLD_EXE="$(readlink "/proc/$OLD_PID/exe" 2>/dev/null)"
    if [ -n "$OLD_PID" ] && [ "$OLD_EXE" = "$XRAY" ]; then
        log "xray already running pid=$OLD_PID"
    else
        log "discarding stale pidfile pid=${OLD_PID:-none} exe=${OLD_EXE:-none}"
        rm -f "$PIDFILE"
    fi
fi

if [ ! -f "$PIDFILE" ]; then
    "$XRAY" run -c "$CONFIG" >/dev/null 2>&1 &
    XRAY_PID=$!
    echo "$XRAY_PID" > "$PIDFILE"
    log "started xray pid=$XRAY_PID"
fi

# Do not redirect anything unless Xray actually came up.
READY=0
I=0
while [ "$I" -lt 15 ]; do
    if ss -lnt 2>/dev/null | grep -q '127\.0\.0\.1:12345'; then
        READY=1
        break
    fi
    I=$((I + 1))
    sleep 1
done

if [ "$READY" != "1" ]; then
    log "ERROR xray did not listen on 127.0.0.1:12345; no firewall rules installed"
    rm -f "$PIDFILE"
    exit 1
fi

# PackageManager may not be ready when service.sh starts.
PLAY_UID=""
I=0
while [ "$I" -lt 90 ]; do
    LINE="$(cmd package list packages -U 2>/dev/null | grep '^package:com.android.vending ' | head -n1)"
    if [ -n "$LINE" ]; then
        UIDS="${LINE##*uid:}"
        PLAY_UID="${UIDS%%,*}"
        case "$PLAY_UID" in
            ''|*[!0-9]*) PLAY_UID="" ;;
        esac
    fi
    [ -n "$PLAY_UID" ] && break
    I=$((I + 1))
    sleep 1
done

if [ -z "$PLAY_UID" ]; then
    log "ERROR could not resolve com.android.vending UID; no firewall rules installed"
    exit 1
fi

log "main-user Play Store UID=$PLAY_UID"

# The Play Store's DownloadService crashes on this setup when it attempts a
# systemExempted foreground service without the required exemption. This
# component is not required by the tested minimal Play Integrity path.
# Only mark it as module-owned if it was enabled before we changed it.
if cmd package query-services --brief --components --user 0 \
        -n "$DOWNLOAD_COMPONENT" 2>/dev/null | grep -Fq "$DOWNLOAD_COMPONENT"; then
    if pm disable --user 0 "$DOWNLOAD_COMPONENT" >/dev/null 2>&1; then
        touch "$DOWNLOAD_MARKER"
        log "disabled Play Store DownloadService"
    else
        log "WARNING could not disable Play Store DownloadService"
    fi
else
    log "Play Store DownloadService already disabled"
fi

# TCP -> transparent Xray listener.
iptables -t nat -C OUTPUT \
    -p tcp -m owner --uid-owner "$PLAY_UID" \
    -j REDIRECT --to-ports 12345 2>/dev/null ||
iptables -t nat -I OUTPUT 1 \
    -p tcp -m owner --uid-owner "$PLAY_UID" \
    -j REDIRECT --to-ports 12345

# Direct UDP/53 -> transparent DNS listener.
iptables -t nat -C OUTPUT \
    -p udp --dport 53 -m owner --uid-owner "$PLAY_UID" \
    -j REDIRECT --to-ports 10853 2>/dev/null ||
iptables -t nat -I OUTPUT 1 \
    -p udp --dport 53 -m owner --uid-owner "$PLAY_UID" \
    -j REDIRECT --to-ports 10853

# Prevent QUIC/HTTP3 from bypassing TLS/SNI routing over TCP.
iptables -C OUTPUT \
    -p udp --dport 443 -m owner --uid-owner "$PLAY_UID" \
    -j REJECT 2>/dev/null ||
iptables -I OUTPUT 1 \
    -p udp --dport 443 -m owner --uid-owner "$PLAY_UID" \
    -j REJECT

# The transparent redirect above is IPv4. Prevent IPv6 bypass for this UID.
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -C OUTPUT \
        -m owner --uid-owner "$PLAY_UID" \
        -j REJECT 2>/dev/null ||
    ip6tables -I OUTPUT 1 \
        -m owner --uid-owner "$PLAY_UID" \
        -j REJECT
fi

log "rules installed"

# The companion playstore_base module adds com.android.vending to the
# device-idle/Doze whitelist after boot so normal Play Store downloads can use
# the Store's systemExempted foreground service on the tested Android 16 ROM.
#
# This privacy module disables that DownloadService, so the exemption is no
# longer needed. Wait until boot completion, then remove the exemption after a
# short grace period so this reliably overrides the base module.
I=0
while [ "$I" -lt 180 ] && [ "$(getprop sys.boot_completed)" != "1" ]; do
    I=$((I + 1))
    sleep 1
done

if [ "$(getprop sys.boot_completed)" = "1" ]; then
    sleep 5
    dumpsys deviceidle whitelist -com.android.vending >/dev/null 2>&1
    sleep 2
    dumpsys deviceidle whitelist -com.android.vending >/dev/null 2>&1

    if [ "$(dumpsys deviceidle whitelist =com.android.vending 2>/dev/null)" = "false" ]; then
        log "Play Store removed from device-idle whitelist"
    else
        log "WARNING could not confirm Play Store device-idle whitelist removal"
    fi
else
    log "WARNING boot completion not observed; device-idle whitelist unchanged"
fi
