# Google Play Store system base

Root module that makes the real Google Play Store the privileged `com.android.vending` system app. It does this systemlessly, before PackageManager scans packages. You build it with your own Play Store APK. This repository does not include Google's APK.

The module works on two kinds of ROM. It detects which one it is on when you flash it:

- On a ROM that ships microG, such as LineageOS for microG, FakeStore is the system app for `com.android.vending`. FakeStore is microG Companion built into the ROM. The Play Store replaces it.
- On a ROM where you install microG yourself, such as official LineageOS, there is no FakeStore. The Play Store is added as a new system app. If you also give the build your GmsCore APK, the module makes microG GmsCore a privileged app too, which Play Integrity needs. See [microG as a privileged app](#microg-as-a-privileged-app).

The module does not produce `MEETS_DEVICE_INTEGRITY` by itself. That verdict comes from the attestation setup in the [main README](../../README.md#3-set-up-attestation). This module provides what that setup needs from the Play Store and GmsCore:

- The Play Store gets the privileged permissions that current builds expect.
- Play Integrity, licensing, and billing run in the real Play Store.
- Apps installed through the Play Store can report `PLAY_RECOGNIZED` and `LICENSED`.
- GmsCore runs in the SELinux domain Android gives Google Play services, so DroidGuard can read the device state it checks.

## Why a normal install is not enough

Android grants privileged permissions only to apps in a `priv-app` folder of a system partition. A Play Store installed as a normal app in `/data/app` does not get them. On LineageOS for microG, Android also keeps FakeStore as the system copy. On the reference device, this caused `SecurityException`s for `MANAGE_USERS` and `WRITE_SECURE_SETTINGS`.

The Play Store also crashed when it ran from the system copy alone. The working layout uses the same APK twice:

```text
/product/priv-app/FakeStore/FakeStore.apk    Play Store, privileged system copy on ROMs with FakeStore
/product/priv-app/Phonesky/Phonesky.apk      Play Store, privileged system copy on ROMs without FakeStore
/data/app/.../com.android.vending            Play Store, installed update, the copy that runs
```

## microG as a privileged app

Play Integrity checks run in microG's DroidGuard process, which belongs to GmsCore. On official LineageOS with GmsCore installed as a normal app, the reference device got only `MEETS_BASIC_INTEGRITY`. DroidGuard ran in the `untrusted_app` SELinux domain, and SELinux denied it reads of `ro.secure`, `ro.debuggable`, `/sys/fs/selinux/enforce`, and the USB state.

Android puts a privileged `com.google.android.gms` in the `gmscore_app` domain instead. With GmsCore as a privileged app, the same device passed `MEETS_STRONG_INTEGRITY`, and the microG self-check also passed "interact across profiles".

Pass your installed GmsCore APK as the second argument of `build-module.sh`. The module adds it with the same two-copy layout as the Play Store:

```text
/product/priv-app/PrebuiltGmsCore/PrebuiltGmsCore.apk    GmsCore, privileged system copy
/data/app/.../com.google.android.gms                     GmsCore, your installed copy, which runs as its update
```

Use the APK of the GmsCore version you have installed, so that the system copy and your installed copy have the same signing key and version. Your installed copy keeps updating normally. When you flash the module, Android relabels GmsCore's data for the new domain, and microG keeps its data.

ROMs that ship microG, such as LineageOS for microG, already install GmsCore as a privileged app. If the ROM has a `GmsCore` folder in `/system/priv-app`, `/product/priv-app`, or `/system_ext/priv-app`, the installer skips the GmsCore APK.

## Choose a Play Store APK

Use an official Google-signed standalone APK, not an APK bundle, for your Android version. Before you build, check the signer with `apksigner` from Android SDK Build-Tools:

```bash
apksigner verify --print-certs PlayStore.apk
```

The `SHA-256 digest` line must show Google's Play Store signer, `7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053`.

If you use the tested build below, comparing the file's SHA-256 is enough. Run `sha256sum PlayStore.apk` on Linux, `shasum -a 256 PlayStore.apk` on macOS, or `certutil -hashfile PlayStore.apk SHA256` on Windows.

The reference device used **Google Play Store 54.1.11-34 [0] [PR] 1016840738** ([APKMirror](https://www.apkmirror.com/apk/google-inc/google-play-store/google-play-store-54-1-11-release/google-play-store-54-1-11-34-0-pr-1016840738-2-android-apk-download/)):

```text
Version code:  85411140
Variant:       universal, nodpi
Android:       14+ (minSdk 34, targetSdk 37)
Size:          81346029 bytes
SHA-256:       ecd778b259935ff75887d54e22adb21b69548faa8a9cd32048dabc66156b1ea1
```

This build needs module version 1.3 or later. See [Privileged permission allowlist](#privileged-permission-allowlist).

<details>
<summary>Earlier tested build: 53.0.27-31</summary>

**Google Play Store 53.0.27-31 [0] [PR] 973951861** ([APKMirror](https://www.apkmirror.com/apk/google-inc/google-play-store/google-play-store-53-0-27-release/google-play-store-53-0-27-31-0-pr-973951861-3-android-apk-download/)), used in September 2026:

```text
Version code:  85302730
Variant:       universal, nodpi
Android:       12+
Size:          105704839 bytes
```

After setup, the Play Store updated itself to 53.0.27-34 in `/data/app`. An older system copy did not stop the update from running.

</details>

These are the builds that were tested. A newer build should work as long as the module allowlists the privileged permissions it requests.

## Build

The build needs `bash` and `zip`. Run it in `modules/playstore-base` of a clone, or in the `playstore_base_module_source` folder of the release asset:

```bash
./build-module.sh /path/to/PlayStore.apk [/path/to/GmsCore.apk]
```

This writes `playstore_base.zip`. The ZIP contains Google's APK, so keep it for your own device and do not share it.

### Build on Windows

Git Bash does not include `zip`. Run the script in WSL, or build the ZIP by hand:

1. Extract `playstore_base_module_source.zip` from the [latest release](https://github.com/D3SOX/microg-play-store-workarounds/releases/latest).
2. In the extracted folder, copy your APK to `module-src\system\product\priv-app\FakeStore\FakeStore.apk`, and delete `PUT_PLAYSTORE_APK_HERE.txt` from that folder. To add GmsCore, create the folder `module-src\system\product\priv-app\PrebuiltGmsCore` and copy your GmsCore APK into it as `PrebuiltGmsCore.apk`.
3. Open `module-src`, select everything in it, right-click, and choose **Compress to ZIP file**. On Windows 10, choose **Send to > Compressed (zipped) folder**.

`module.prop` must be at the top level of the ZIP, not inside a `module-src` folder. Flash the ZIP as described in [Install](#install).

## Install

The order differs between the two kinds of ROM. Do not open the Play Store until the last step.

### ROM with FakeStore

1. Flash `playstore_base.zip` in your root manager and reboot. The installer should print that the ROM ships FakeStore.
2. If the old FakeStore update is still installed, remove it:

   ```bash
   adb shell "su -c 'pm uninstall-system-updates com.android.vending'"
   ```

   On LineageOS for microG, Android removed it by itself, because the new system copy had a higher version code.
3. Install the same Play Store APK as an update and reboot:

   ```bash
   adb install -r PlayStore.apk
   adb reboot
   ```

4. Open the Play Store, sign in, and let it update itself.

FakeStore and the Play Store have different signing keys. Depending on your ROM and root setup, you may need a signature-compatibility workaround. CorePatch was installed on the reference device. This repository does not provide one.

### ROM without FakeStore

1. If microG Companion is installed as a normal app, list the apps that name it as their installer, then uninstall it:

   ```bash
   adb shell "pm list packages -3 -i | grep installer=com.android.vending"
   adb uninstall com.android.vending
   ```

   Companion has the same package name as the Play Store but a different signing key, so the Play Store cannot replace it. Android also clears the installer of every app that named Companion as its installer, and those apps can no longer see the Play Store. Fix them with [`play-provenance-repair`](../play-provenance-repair/README.md) after the last step.
2. Flash `playstore_base.zip` in your root manager and reboot. The installer should print that the ROM has no FakeStore, and that it adds GmsCore if you built the module with it.
3. Install the same Play Store APK as an update and reboot:

   ```bash
   adb install -r PlayStore.apk
   adb reboot
   ```

4. Open the Play Store, sign in, and let it update itself.

GmsCore needs no separate update step, because your installed GmsCore is already in `/data/app` and becomes the update of the module's copy.

## Verify

The module logs each boot to `/data/adb/playstore_base-postfs.log`. On a ROM with FakeStore, it should show two `mount rc=0` lines, one for the allowlist and one for the APK, each followed by two matching SHA-256 hashes. On a ROM without FakeStore, the root manager mounts the files, and the log only says so. Check that they are there:

```bash
adb shell ls /product/priv-app/Phonesky /product/etc/permissions/privapp-permissions-com.android.vending.xml
```

If the module added GmsCore, its processes should run in the `gmscore_app` domain:

```bash
adb shell "ps -AZ | grep com.google.android.gms"
```

Check that the update runs and the permissions are granted:

```bash
adb shell pm path com.android.vending
adb shell "dumpsys package com.android.vending | grep -E 'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:|GET_ROLE_HOLDERS:'"
```

The path should be in `/data/app`, and every permission should show `granted=true`.

## What the module does

- When you flash it, `customize.sh` checks for `/product/priv-app/FakeStore/FakeStore.apk`. If the ROM has no FakeStore, it moves the APK in the module to `system/product/priv-app/Phonesky/Phonesky.apk`. It also removes the GmsCore APK and its allowlist if the ROM already has GmsCore. If you later switch ROMs, flash the module again.
- On a ROM without FakeStore, the root manager adds the APK and the allowlist as new files at boot, and the module does nothing else before boot completes.
- On a ROM with FakeStore, `post-fs-data.sh` bind-mounts the allowlist over `/product/etc/permissions/privapp-permissions-com.android.vending.xml`, then the APK over `/product/priv-app/FakeStore/FakeStore.apk`. If the allowlist mount fails, it skips the APK, so the device boots with FakeStore instead of looping.
- Until one boot completes with the APK mounted, it also clears PackageManager's package cache, so Android does not reuse what it parsed from FakeStore. After a failed mount, it clears the cache again.
- `service.sh` adds the Play Store to the device-idle whitelist once boot completes. It skips this while the privacy filter is enabled. See [Downloads stay pending](#downloads-stay-pending).

On a ROM with FakeStore, the module mounts its files itself, so it does not depend on the root manager's own module mounting. On LineageOS for microG, Hybrid Mount also mounted the same files from the module's `system/` folder, with the same result. Paths that do not exist on the ROM cannot be bind-mounted, so on a ROM without FakeStore the module needs the root manager or its metamodule to mount `system/`.

## Privileged permission allowlist

With `ro.control_privapp_permissions=enforce`, system_server crashes on every boot when a privileged app requests a privileged permission that no allowlist file grants. Android skips this check for a system app that has an update installed, but the Play Store has no update yet on the first boot after you flash the module.

Official LineageOS 24 allowlists most of the Play Store's and Google Play services' privileged permissions in `/product/etc/permissions/privapp-permissions-google-p-lineage.xml`. The module adds the ones that file lacks:

```text
privapp-permissions-com.android.vending.xml       GET_ROLE_HOLDERS, requested since Play Store 54.1.11
privapp-permissions-playstore-base-gmscore.xml    INSTALL_LOCATION_PROVIDER, NETWORK_SCAN, and WATCH_APPOPS, requested by microG 0.3.18
```

LineageOS for microG also allowlists FakeStore's permissions in `/product/etc/permissions/privapp-permissions-com.android.vending.xml`. On that ROM, the module's copy replaces the file, keeps its six entries, and adds `GET_ROLE_HOLDERS`. On ROMs without FakeStore, it is a new file.

If a newer Play Store build causes a boot loop, the crash log names the missing permission:

```text
IllegalStateException: Signature|privileged permissions not in privileged permission allowlist: {com.android.vending (/product/priv-app/FakeStore): android.permission.GET_ROLE_HOLDERS}
```

Recover as described in the [main README](../../README.md#boot-loop-after-installing-playstore-base), add the permission to the XML file, and rebuild the module.

## Updates

The Play Store and microG update themselves in `/data/app` as usual. The system copies in the module stay at the version you built it with, and an older system copy does not stop an update from running.

Android grants an updated system app only the privileged permissions that its system copy also requests. If a later Play Store or microG version requests a new privileged permission, it does not get it until you rebuild the module. When you rebuild, use APKs that are not newer than the installed versions. If the module added GmsCore, include the GmsCore APK again, because a build without it removes GmsCore's privileged copy. If the system copy is newer, Android removes the installed copy at the next boot, and you have to install the Play Store update again with `adb install -r`.

## Downloads stay pending

On the reference device, Play Store downloads first stayed on **Pending**. Logcat showed `com.android.vending:background` crashing when `com.google.android.finsky.downloadservice.DownloadService` started a `systemExempted` foreground service.

Adding the Play Store to the device-idle whitelist fixed it:

```bash
adb shell "su -c 'dumpsys deviceidle whitelist +com.android.vending'"
```

The module does this at every boot. Check it with:

```bash
adb shell "su -c 'dumpsys deviceidle whitelist =com.android.vending'"
```

It should print `true`. With the privacy filter enabled, it prints `false` on purpose. The filter disables `DownloadService` and removes the entry, and this module does not add it back.

## Uninstall

Remove the module in your root manager and reboot. On a ROM with FakeStore, FakeStore becomes the system copy again.

On a ROM without FakeStore, the Play Store and GmsCore lose their system copies, and their copies in `/data/app` stay. When the GmsCore part was removed on the reference device, GmsCore became a normal app again and kept its data. As a normal app it runs in the `untrusted_app` domain again, so expect only `MEETS_BASIC_INTEGRITY`. Removing the Play Store's system copy was not tested.

The uninstall script deletes the module's state files, clears PackageManager's package cache, and removes the device-idle whitelist entry once boot completes.

On a ROM with FakeStore, the Play Store update in `/data/app` has a different signing key than FakeStore. What Android does with it depends on your ROM and signature-compatibility setup, so check `adb shell pm path com.android.vending` after the reboot.
