# Google Play Store System Base

Source-only root module for microG ROMs where FakeStore or microG Companion occupies the privileged `com.android.vending` system slot. It systemlessly replaces that factory base with your own official Google-signed Play Store APK. The replacement happens before PackageManager scans packages, so PackageManager treats Google Play as the privileged base package.

The module was tested with APatch.

## Why it exists

On the tested Android 16 LineageOS-for-microG setup, LineageOS shipped microG Companion/FakeStore as the factory `com.android.vending` package at:

```text
/product/priv-app/FakeStore/FakeStore.apk
```

Installing the official Play Store only as a `/data/app` update was not enough. Android still treated FakeStore as the factory package metadata, and the updated Play Store did not inherit all privileged permissions expected by current Play Store builds.

The first hard failures were `SecurityException`s involving privileged permissions such as:

```text
MANAGE_USERS
WRITE_SECURE_SETTINGS
```

After replacing the factory base with the official Google-signed Play Store, the expected grants were present, including:

```text
INSTALL_PACKAGES: granted=true
GET_ACCOUNTS_PRIVILEGED: granted=true
WRITE_SECURE_SETTINGS: granted=true
MANAGE_USERS: granted=true
FOREGROUND_SERVICE_SYSTEM_EXEMPTED: granted=true
```

The module mounts the supplied Play Store APK over the FakeStore path before PackageManager's package scan.

## Tested Play Store APK

The repository does **not** redistribute Google's proprietary Play Store APK. You must provide your own official Google-signed standalone APK.

The current reference device, tested on 2026-11-12, used this APK as both the factory base and the `/data/app` update:

**Google Play Store 54.1.11-34 [0] [PR] 1016840738**

```text
Version code: 85411140
Variant: universal / nodpi
Minimum Android: Android 14+ (minSdk 34, targetSdk 37)
Package format: standalone APK, not an APK bundle
APK size: 81346029 bytes (~77.58 MiB)
APK SHA-256: ecd778b259935ff75887d54e22adb21b69548faa8a9cd32048dabc66156b1ea1
Google signer SHA-256: 7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053
```

APKMirror page:

https://www.apkmirror.com/apk/google-inc/google-play-store/google-play-store-54-1-11-release/google-play-store-54-1-11-34-0-pr-1016840738-2-android-apk-download/

This build requests `android.permission.GET_ROLE_HOLDERS`, a privileged permission that the 53.0.27 build did not request. On LineageOS for microG, module versions before v1.3 do not allowlist it and cause a boot loop with this APK. See [Privileged permission allowlist](#privileged-permission-allowlist).

The September 2026 setup used **Google Play Store 53.0.27-31 [0] [PR] 973951861**:

```text
Version code: 85302730
Variant: universal / nodpi
Minimum Android: Android 12+
Package format: standalone APK, not an APK bundle
APK size: 105704839 bytes (~100.81 MiB)
Google signer SHA-256: 7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053
```

APKMirror page:

https://www.apkmirror.com/apk/google-inc/google-play-store/google-play-store-53-0-27-release/google-play-store-53-0-27-31-0-pr-973951861-3-android-apk-download/

After that setup was working, the active `/data/app` Play Store updated itself to `53.0.27-34 [0] [PR] 973951861`. A privileged base on an older build did not prevent the update from running.

These are records of tested builds, not a requirement to use these versions. Prefer a current official Google-signed standalone build for your Android version. Verify its signer before you use it as a privileged base:

```bash
apksigner verify --print-certs PlayStore.apk | grep 'SHA-256'
```

## Privileged permission allowlist

With `ro.control_privapp_permissions=enforce`, system_server crashes at boot when a privileged app requests a `signature|privileged` permission that no allowlist file grants. LineageOS for microG allowlists FakeStore's permissions in:

```text
/product/etc/permissions/privapp-permissions-com.android.vending.xml
```

The module ships a replacement for that file in `system/product/etc/permissions/`. It keeps the six entries from the ROM's file and adds the permissions that current Play Store builds need but the ROM does not grant:

```text
android.permission.GET_ROLE_HOLDERS
```

`post-fs-data.sh` bind-mounts this file before the APK and mounts the APK only if the allowlist mount succeeded. If a newer Play Store build requests another permission, the crash log names it:

```text
IllegalStateException: Signature|privileged permissions not in privileged permission allowlist: {com.android.vending (/product/priv-app/FakeStore): android.permission.GET_ROLE_HOLDERS}
```

Add that permission to the XML file and rebuild the module.

## Build the module

The build needs `bash` and `zip`. Run it from `modules/playstore-base` in a clone of this repository, or from the `playstore_base_module_source` folder of the extracted release asset:

```bash
./build-module.sh /path/to/PlayStore.apk
```

The script writes `playstore_base.zip` next to itself. That ZIP contains Google's proprietary APK, so keep it for your own device and do not redistribute it. Git ignores it, and the repository's release archives exclude it.

## Intended package layout

The working arrangement was:

```text
/product/priv-app/FakeStore/FakeStore.apk
    official Google Play Store privileged factory base
    (systemless replacement)

/data/app/.../com.android.vending
    official Google Play Store active UPDATED_SYSTEM_APP
```

The important detail is that the official Store must be visible as the privileged factory base **and** the active copy should execute from `/data/app`.

Directly executing the downloaded Play Store build from `/product` caused ART/class-loading failures involving `ClassicApplication` on the tested device. Keeping the privileged base for PackageManager metadata while running the normal update from `/data/app` avoided that problem.

## Install sequence

1. Build and install `playstore_base.zip` in APatch or a compatible module manager.
2. Reboot.
3. If an old FakeStore/microG Companion update layer is still installed, remove it if needed:

   ```bash
   adb shell su -c 'pm uninstall-system-updates com.android.vending'
   ```

   On the 2026-11-12 test, PackageManager dropped the microG Companion update by itself, because the new base had a higher version code.

4. Before you open the Play Store, install the same APK normally so it becomes the active `/data/app` update:

   ```bash
   adb install -r PlayStore.apk
   ```

5. Reboot again.
6. Open the Play Store, sign in, and let it finish its normal initialization and self-update.

After each boot, `/data/adb/playstore_base-postfs.log` shows whether the bind mounts worked. Look for two `mount rc=0` lines, one for the allowlist and one for the APK. Each comes with two matching SHA-256 hashes, one for the module's file and one for the target path under `/product`.

The module mounts both files itself in `post-fs-data.sh`, so it does not depend on the root manager's own module mounting. The 2026-11-12 test ran APatch with [Hybrid Mount](https://github.com/Hybrid-Mount/meta-hybrid_mount) as the metamodule. Hybrid Mount mounted the same files from the module's `system/` tree, and the result was the same.

On the first boot after installation, the module also clears PackageManager's package cache so PackageManager does not reuse metadata parsed from FakeStore. It repeats this on every boot until one boot completes with the replacement mounted. If the mount fails on a later boot, it clears the cache again and starts over.

A differently signed migration from FakeStore to Google's Play Store can require signature-compatibility handling depending on the ROM/root setup. CorePatch was present during the tested migration because FakeStore and Google's Play Store do not share a signing certificate. This repository does not attempt to provide a universal signature-policy bypass; use a method appropriate to your ROM/root setup and understand the security implications.

## Verify the package state

Check the active path and system-package flags:

```bash
adb shell pm path com.android.vending
adb shell dumpsys package com.android.vending | grep -E 'codePath=|versionName=|pkgFlags='
```

Check important privileged grants:

```bash
adb shell dumpsys package com.android.vending | grep -E \
  'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:|GET_ROLE_HOLDERS:'
```

Useful Play Store services observed on the working setup were:

```text
Play Integrity:
com.android.vending/com.google.android.finsky.integrityservice.IntegrityService

Licensing:
com.android.vending/com.google.android.finsky.services.LicensingService

Billing:
com.android.vending/com.google.android.finsky.billing.iab.InAppBillingService
```

The Play Integrity service should remain enabled in a normal setup.

## Android 16 DownloadService / device-idle workaround

After the real Play Store was functioning and authenticated, app installs initially hung on **Pending** on the tested Android 16 ROM.

Logcat showed `com.android.vending:background` crashing when:

```text
com.google.android.finsky.downloadservice.DownloadService
```

attempted to start a `systemExempted` foreground service.

The working fix was to keep Play Store on Android's device-idle allowlist:

```bash
adb shell su -c 'dumpsys deviceidle whitelist +com.android.vending'
```

Verify:

```bash
adb shell su -c 'dumpsys deviceidle whitelist =com.android.vending'
```

Expected for a normal Store configuration:

```text
true
```

After that, Play Store downloads/installations worked normally.

`playstore-base` applies this automatically in `service.sh` once `sys.boot_completed=1`:

```sh
dumpsys deviceidle whitelist +com.android.vending
```

The optional `playstore-xray-privacy-filter` module does the opposite. It disables `DownloadService` and removes `com.android.vending` from the device-idle whitelist, because that setup blocks normal Store downloads on purpose. While the privacy filter is enabled, this module skips adding the whitelist entry.

## Uninstall

Remove the module in your root manager and reboot. FakeStore becomes the factory base again. The uninstall script deletes its state files in `/data/adb` (`playstore_base_initialized_v2` and `playstore_base-postfs.log`). It also clears PackageManager's package cache, so the next boot parses FakeStore again, and removes the device-idle whitelist entry once boot completes.

The official Play Store update in `/data/app` is signed differently from FakeStore. What PackageManager does with it then depends on the ROM and your signature-compatibility setup, so check `adb shell pm path com.android.vending` after rebooting.

## Why the real privileged Store matters

This module does **not** produce `MEETS_DEVICE_INTEGRITY` by itself. The device verdict still depends on the root/Zygisk/attestation stack.

What this module fixes is the Play Store side of the environment:

- the real Google-signed `com.android.vending` exists as the privileged factory base;
- expected privileged permissions are granted;
- Play Integrity can bind to the real Store service;
- Play licensing/billing components exist where applications expect them;
- apps installed through Play can be `PLAY_RECOGNIZED` / `LICENSED` instead of being confused by a FakeStore factory base.

On the tested Android 16 setup, this was used alongside APatch, ReZygisk, Zygisk Assistant, Play Integrity Fork, Tricky Store OSS, and a keybox from Yurikey Manager.

## Tested Integrity result

The main [README](../../README.md#reference-result) records the full Play Integrity result from the reference device. This module is only one part of that setup.
