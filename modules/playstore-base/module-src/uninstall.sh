#!/system/bin/sh

rm -f /data/adb/playstore_base_initialized /data/adb/playstore_base-postfs.log

# FakeStore returns at the same path with an older timestamp than the cached
# parse of the Play Store APK, so PackageManager could reuse that entry.
rm -rf /data/system/package_cache/*

# The device-idle exemption persists. Root managers usually run this script
# before the framework is up, so remove it once boot completes.
(
    until [ "$(getprop sys.boot_completed)" = "1" ]; do
        sleep 2
    done
    dumpsys deviceidle whitelist -com.android.vending >/dev/null 2>&1
) </dev/null >/dev/null 2>&1 &
