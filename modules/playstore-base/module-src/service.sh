#!/system/bin/sh

STATE="/data/adb/playstore_base_initialized"

# Wait until the framework is fully up before touching device-idle state.
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Android 16 compatibility: on the tested ROM Play Store DownloadService could
# crash when starting its systemExempted foreground service unless the package
# was device-idle allowlisted. Keep normal Play Store downloads functional.
dumpsys deviceidle whitelist +com.android.vending >/dev/null 2>&1 || true

# Mark one complete boot with the replacement base mounted.
touch "$STATE"
