#!/system/bin/sh

MODDIR=${0%/*}
SRC="$MODDIR/system/product/priv-app/FakeStore/FakeStore.apk"
DST="/product/priv-app/FakeStore/FakeStore.apk"
PERMS="etc/permissions/privapp-permissions-com.android.vending.xml"
PERMS_SRC="$MODDIR/system/product/$PERMS"
PERMS_DST="/product/$PERMS"
STATE="/data/adb/playstore_base_initialized_v2"
LOG="/data/adb/playstore_base-postfs.log"
# On tmpfs, so it only describes the current boot.
MOUNTED="/dev/playstore_base.mounted"

echo "=== playstore_base post-fs-data ===" > "$LOG"
date >> "$LOG"

invalidate_package_cache() {
    resetprop -n pm.boot.disable_package_cache true
    rm -rf /data/system/package_cache/*
    echo "package cache invalidation requested ($1)" >> "$LOG"
}

# PackageManager may otherwise reuse metadata parsed from the ROM FakeStore.
# Do this only until one successful boot has completed with the replacement mounted.
# v1.1 wrote its marker even after failed mounts, so this one has a new name.
[ -f "$STATE" ] || invalidate_package_cache "not yet initialized"

bind() {
    if [ ! -f "$1" ]; then
        echo "ERROR: missing $1"
        return 1
    fi
    chcon u:object_r:system_file:s0 "$1"
    echo "Binding $1 -> $2"
    mount -o bind "$1" "$2"
    RC=$?
    echo "mount rc=$RC"
    sha256sum "$1" "$2"
    ls -lZ "$2"
    return $RC
}

# Without the allowlist, system_server rejects the Play Store's privileged
# permissions and crashes on every boot, so mount the APK only after it.
{
    bind "$PERMS_SRC" "$PERMS_DST" && bind "$SRC" "$DST"
} >> "$LOG" 2>&1
RC=$?
[ "$RC" -ne 0 ] || touch "$MOUNTED"

# The package directory's mtime does not change with the mount, so the cache
# cannot tell which APK it parsed. After a failed mount, drop the cached Play
# Store parse now and the marker, so the next mounted boot drops FakeStore's.
if [ "$RC" -ne 0 ] && [ -f "$STATE" ]; then
    rm -f "$STATE"
    invalidate_package_cache "mount failed"
fi

exit $RC
