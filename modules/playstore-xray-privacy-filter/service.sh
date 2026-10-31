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

# Per-table chains owned by this module, hooked at the top of OUTPUT.
CHAIN="playstore_xray"

DOWNLOAD_COMPONENT="com.android.vending/com.google.android.finsky.downloadservice.DownloadService"
DOWNLOAD_MARKER="$STATE/downloadservice_disabled_by_module"

mkdir -p "$STATE"
: > "$BOOTLOG"
rm -f "$OLD_PIDFILE"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$BOOTLOG"
}

FAILED=0
ipt() {
    "$@" 2>>"$BOOTLOG" || {
        log "ERROR failed: $*"
        FAILED=1
    }
}

# Create (or empty) this module's chain and hook it at the top of OUTPUT.
setup_chain() {
    "$1" -w -t "$2" -N "$CHAIN" 2>/dev/null || ipt "$1" -w -t "$2" -F "$CHAIN"
    "$1" -w -t "$2" -C OUTPUT -j "$CHAIN" 2>/dev/null ||
        ipt "$1" -w -t "$2" -I OUTPUT 1 -j "$CHAIN"
}

add_uid_rules() {
    # Default-deny: the UID may only reach the local Xray listeners. The filter
    # table sees packets after the nat REDIRECT below, so redirected traffic
    # passes, while all other traffic, including any IPv6 or UDP, is rejected.
    # If Xray is not running, the redirected traffic fails too.
    ipt iptables -w -A "$CHAIN" -m owner --uid-owner "$1" \
        -p tcp -d 127.0.0.1 --dport 12345 -j RETURN
    ipt iptables -w -A "$CHAIN" -m owner --uid-owner "$1" \
        -p udp -d 127.0.0.1 --dport 10853 -j RETURN
    ipt iptables -w -A "$CHAIN" -m owner --uid-owner "$1" -j REJECT
    ipt ip6tables -w -A "$CHAIN" -m owner --uid-owner "$1" -j REJECT

    # IPv4 TCP and plain DNS -> Xray.
    ipt iptables -w -t nat -A "$CHAIN" -m owner --uid-owner "$1" \
        -p tcp -j REDIRECT --to-ports 12345
    ipt iptables -w -t nat -A "$CHAIN" -m owner --uid-owner "$1" \
        -p udp --dport 53 -j REDIRECT --to-ports 10853
}

package_manager_uid() {
    LINE="$(cmd package list packages -U 2>/dev/null | grep '^package:com.android.vending ' | head -n1)"
    UIDS="${LINE##*uid:}"
    case "${UIDS%%,*}" in
        ''|*[!0-9]*) ;;
        *) echo "${UIDS%%,*}" ;;
    esac
}

log "starting"

setup_chain iptables filter
setup_chain ip6tables filter
setup_chain iptables nat

# Block before the Play Store can start. packages.list is left over from the
# previous boot and is readable long before PackageManager is up.
PLAY_UID="$(sed -n 's/^com\.android\.vending \([0-9][0-9]*\) .*/\1/p' /data/system/packages.list 2>/dev/null | head -n1)"
if [ -n "$PLAY_UID" ]; then
    add_uid_rules "$PLAY_UID"
    log "main-user Play Store UID=$PLAY_UID from packages.list"
fi

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

I=0
while ! ss -lnt 2>/dev/null | grep -q '127\.0\.0\.1:12345'; do
    I=$((I + 1))
    if [ "$I" -ge 15 ]; then
        log "ERROR xray did not listen on 127.0.0.1:12345; Play Store traffic stays blocked"
        break
    fi
    sleep 1
done

# Confirm the UID once PackageManager is up.
PM_UID=""
I=0
while [ "$I" -lt 90 ]; do
    PM_UID="$(package_manager_uid)"
    [ -n "$PM_UID" ] && break
    I=$((I + 1))
    sleep 1
done

if [ -n "$PM_UID" ] && [ "$PM_UID" != "$PLAY_UID" ]; then
    [ -z "$PLAY_UID" ] || log "WARNING packages.list UID $PLAY_UID differs from PackageManager"
    PLAY_UID="$PM_UID"
    add_uid_rules "$PLAY_UID"
    log "main-user Play Store UID=$PLAY_UID from PackageManager"
fi

if [ -z "$PLAY_UID" ]; then
    log "ERROR could not resolve com.android.vending UID; no firewall rules installed"
    exit 1
fi

if [ "$FAILED" = "1" ]; then
    log "ERROR some firewall rules failed; filtering is incomplete"
else
    log "rules installed"
fi

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

# DownloadService is disabled, so the Play Store needs no device-idle
# exemption. playstore_base skips adding it while this module is enabled; this
# removes an entry left over from earlier boots.
I=0
while [ "$I" -lt 180 ] && [ "$(getprop sys.boot_completed)" != "1" ]; do
    I=$((I + 1))
    sleep 1
done

if [ "$(getprop sys.boot_completed)" = "1" ]; then
    dumpsys deviceidle whitelist -com.android.vending >/dev/null 2>&1

    if [ "$(dumpsys deviceidle whitelist =com.android.vending 2>/dev/null)" = "false" ]; then
        log "Play Store removed from device-idle whitelist"
    else
        log "WARNING could not confirm Play Store device-idle whitelist removal"
    fi
else
    log "WARNING boot completion not observed; device-idle whitelist unchanged"
fi
