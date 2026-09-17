#!/system/bin/sh

MODDIR=${0%/*}
SRC="$MODDIR/system/product/priv-app/FakeStore/FakeStore.apk"
DST="/product/priv-app/FakeStore/FakeStore.apk"
STATE="/data/adb/playstore_base_initialized"
LOG="/data/adb/playstore_base-postfs.log"

echo "=== playstore_base post-fs-data ===" > "$LOG"
date >> "$LOG"

# PackageManager may otherwise reuse metadata parsed from the ROM FakeStore.
# Do this only until one successful boot has completed with the replacement mounted.
if [ ! -f "$STATE" ]; then
    resetprop -n pm.boot.disable_package_cache true
    rm -rf /data/system/package_cache/*
    echo "initial package cache invalidation requested" >> "$LOG"
fi

if [ ! -f "$SRC" ]; then
    echo "ERROR: missing $SRC" >> "$LOG"
    exit 1
fi

chcon u:object_r:system_file:s0 "$SRC" >> "$LOG" 2>&1

echo "Binding $SRC -> $DST" >> "$LOG"
mount -o bind "$SRC" "$DST" >> "$LOG" 2>&1
RC=$?
echo "mount rc=$RC" >> "$LOG"

sha256sum "$SRC" >> "$LOG" 2>&1
sha256sum "$DST" >> "$LOG" 2>&1
ls -lZ "$DST" >> "$LOG" 2>&1

exit $RC
