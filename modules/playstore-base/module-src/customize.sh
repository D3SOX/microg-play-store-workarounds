#!/system/bin/sh

APPS="$MODPATH/system/product/priv-app"
GMS_PERMS="$MODPATH/system/product/etc/permissions/privapp-permissions-playstore-base-gmscore.xml"

[ -f "$APPS/FakeStore/FakeStore.apk" ] ||
    abort "! The module contains no Play Store APK. Build it with build-module.sh."

if [ -f /product/priv-app/FakeStore/FakeStore.apk ]; then
    ui_print "- This ROM ships microG FakeStore. The Play Store replaces it."
else
    # Without FakeStore, the root manager adds the Play Store as a new system
    # app, so use the directory name that Google's own builds use.
    ui_print "- This ROM has no FakeStore. The Play Store is added at"
    ui_print "  /product/priv-app/Phonesky."
    mkdir -p "$APPS/Phonesky"
    mv "$APPS/FakeStore/FakeStore.apk" "$APPS/Phonesky/Phonesky.apk"
    rm -rf "$APPS/FakeStore"
fi

# ROMs that ship microG install GmsCore as a privileged app themselves.
ROM_GMSCORE=
for DIR in /system/priv-app/GmsCore /product/priv-app/GmsCore /system_ext/priv-app/GmsCore; do
    [ ! -d "$DIR" ] || ROM_GMSCORE=$DIR
done
if [ ! -f "$APPS/PrebuiltGmsCore/PrebuiltGmsCore.apk" ]; then
    rm -rf "$APPS/PrebuiltGmsCore" "$GMS_PERMS"
elif [ -n "$ROM_GMSCORE" ]; then
    ui_print "- The ROM already has $ROM_GMSCORE. Skipping the GmsCore APK."
    rm -rf "$APPS/PrebuiltGmsCore" "$GMS_PERMS"
else
    ui_print "- GmsCore is added at /product/priv-app/PrebuiltGmsCore."
fi
