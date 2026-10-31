#!/system/bin/sh

STATE="/data/adb/playstore_base_initialized"
MOUNTED="/dev/playstore_base.mounted"
PRIVACY="/data/adb/modules/playstore_xray_privacy_filter"

# Wait until the framework is fully up before touching device-idle state.
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Android 16 compatibility: on the tested ROM Play Store DownloadService could
# crash when starting its systemExempted foreground service unless the package
# was device-idle allowlisted. Keep normal Play Store downloads functional.
# The privacy filter disables DownloadService and removes the exemption, so
# skip it while that module is enabled.
if [ ! -d "$PRIVACY" ] || [ -f "$PRIVACY/disable" ] || [ -f "$PRIVACY/remove" ]; then
    dumpsys deviceidle whitelist +com.android.vending >/dev/null 2>&1 || true
fi

# Mark one complete boot with the replacement base mounted.
[ ! -f "$MOUNTED" ] || touch "$STATE"
