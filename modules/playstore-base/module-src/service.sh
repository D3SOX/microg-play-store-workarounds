#!/system/bin/sh

STATE="/data/adb/playstore_base_initialized"

# The post-fs-data script invalidates PackageManager's parser cache until one
# complete boot succeeds with the replacement APK mounted. Mark that state here.
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

touch "$STATE"
