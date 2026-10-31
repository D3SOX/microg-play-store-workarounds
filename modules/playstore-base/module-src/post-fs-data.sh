#!/system/bin/sh

MODDIR=${0%/*}
SRC="$MODDIR/system/product/priv-app/FakeStore/FakeStore.apk"
DST="/product/priv-app/FakeStore/FakeStore.apk"
STATE="/data/adb/playstore_base_initialized_v2"
LOG="/data/adb/playstore_base-postfs.log"
# On tmpfs, so it only describes the current boot.
MOUNTED="/dev/playstore_base.mounted"

echo "=== playstore_base post-fs-data ===" > "$LOG"
date >> "$LOG"

# PackageManager may otherwise reuse metadata parsed from the ROM FakeStore.
# Do this only until one successful boot has completed with the replacement mounted.
# v1.1 wrote its marker even after failed mounts, so this one has a new name.
if [ ! -f "$STATE" ]; then
    resetprop -n pm.boot.disable_package_cache true
    rm -rf /data/system/package_cache/*
    echo "initial package cache invalidation requested" >> "$LOG"
fi

if [ ! -f "$SRC" ]; then
    echo "ERROR: missing $SRC" >> "$LOG"
    exit 1
fi

{
    chcon u:object_r:system_file:s0 "$SRC"

    echo "Binding $SRC -> $DST"
    mount -o bind "$SRC" "$DST"
    RC=$?
    echo "mount rc=$RC"
    [ "$RC" -ne 0 ] || touch "$MOUNTED"

    sha256sum "$SRC"
    sha256sum "$DST"
    ls -lZ "$DST"
} >> "$LOG" 2>&1

exit $RC
