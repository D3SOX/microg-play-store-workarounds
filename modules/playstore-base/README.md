# Google Play Store system base

Root module that replaces microG's FakeStore (microG Companion) with the real Google Play Store as the privileged `com.android.vending` system app. It does this systemlessly, before PackageManager scans packages. You build it with your own Play Store APK. This repository does not include Google's APK.

The module does not produce `MEETS_DEVICE_INTEGRITY` by itself. That verdict comes from the attestation setup in the [main README](../../README.md#3-set-up-attestation). This module fixes the Play Store side:

- The Play Store gets the privileged permissions that current builds expect.
- Play Integrity, licensing, and billing run in the real Play Store.
- Apps installed through the Play Store can report `PLAY_RECOGNIZED` and `LICENSED`.

## Why the update alone is not enough

LineageOS for microG ships FakeStore as the system copy of `com.android.vending` at `/product/priv-app/FakeStore/FakeStore.apk`. If you install the real Play Store only as an update in `/data/app`, Android keeps FakeStore as the system copy, and the Play Store does not get its privileged permissions. On the reference device, this caused `SecurityException`s for `MANAGE_USERS` and `WRITE_SECURE_SETTINGS`.

The Play Store also crashed (`ClassNotFoundException` for `ClassicApplication`) when it ran from the system copy alone. The working layout uses the same APK twice:

```text
/product/priv-app/FakeStore/FakeStore.apk    Play Store, privileged system copy (this module)
/data/app/.../com.android.vending            Play Store, installed update (the copy that runs)
```

## Choose a Play Store APK

Use an official Google-signed standalone APK, not an APK bundle, for your Android version. Check the signer before you build:

```bash
apksigner verify --print-certs PlayStore.apk | grep 'SHA-256'
```

Google's Play Store signer is `7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053`.

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
./build-module.sh /path/to/PlayStore.apk
```

This writes `playstore_base.zip`. The ZIP contains Google's APK, so keep it for your own device and do not share it.

## Install

1. Flash `playstore_base.zip` in your root manager and reboot.
2. If the old FakeStore update is still installed, remove it:

   ```bash
   adb shell su -c 'pm uninstall-system-updates com.android.vending'
   ```

   On the reference device, Android removed it by itself, because the new system copy had a higher version code.
3. Before you open the Play Store, install the same APK as an update and reboot:

   ```bash
   adb install -r PlayStore.apk
   adb reboot
   ```

4. Open the Play Store, sign in, and let it update itself.

FakeStore and the Play Store have different signing keys. Depending on your ROM and root setup, you may need a signature-compatibility workaround. CorePatch was installed on the reference device. This repository does not provide one.

## Verify

The module logs each boot to `/data/adb/playstore_base-postfs.log`. It should show two `mount rc=0` lines, one for the allowlist and one for the APK, each followed by two matching SHA-256 hashes.

Check that the update runs and the permissions are granted:

```bash
adb shell pm path com.android.vending
adb shell dumpsys package com.android.vending | grep -E \
  'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:|GET_ROLE_HOLDERS:'
```

The path should be in `/data/app`, and every permission should show `granted=true`.

## What the module does at boot

- `post-fs-data.sh` bind-mounts the allowlist over `/product/etc/permissions/privapp-permissions-com.android.vending.xml`, then the APK over `/product/priv-app/FakeStore/FakeStore.apk`. If the allowlist mount fails, it skips the APK, so the device boots with FakeStore instead of looping.
- Until one boot completes with the APK mounted, it also clears PackageManager's package cache, so Android does not reuse what it parsed from FakeStore. After a failed mount, it clears the cache again.
- `service.sh` adds the Play Store to the device-idle whitelist once boot completes. It skips this while the privacy filter is enabled. See [Downloads stay pending](#downloads-stay-pending).

The module mounts its files itself, so it does not depend on the root manager's own module mounting. On the reference device, Hybrid Mount also mounted the same files from the module's `system/` folder, with the same result.

## Privileged permission allowlist

With `ro.control_privapp_permissions=enforce`, system_server crashes on every boot when a privileged app requests a privileged permission that no allowlist file grants. LineageOS for microG allowlists FakeStore's permissions in `/product/etc/permissions/privapp-permissions-com.android.vending.xml`.

The module replaces that file with a copy in `system/product/etc/permissions/`. The copy keeps the ROM's six entries and adds the permissions that current Play Store builds request but the ROM does not grant:

```text
android.permission.GET_ROLE_HOLDERS    requested since Play Store 54.1.11
```

If a newer Play Store build causes a boot loop, the crash log names the missing permission:

```text
IllegalStateException: Signature|privileged permissions not in privileged permission allowlist: {com.android.vending (/product/priv-app/FakeStore): android.permission.GET_ROLE_HOLDERS}
```

Recover as described in the [main README](../../README.md#boot-loop-after-installing-playstore-base), add the permission to the XML file, and rebuild the module.

## Downloads stay pending

On the reference device, Play Store downloads first stayed on **Pending**. Logcat showed `com.android.vending:background` crashing when `com.google.android.finsky.downloadservice.DownloadService` started a `systemExempted` foreground service.

Adding the Play Store to the device-idle whitelist fixed it:

```bash
adb shell su -c 'dumpsys deviceidle whitelist +com.android.vending'
```

The module does this at every boot. Check it with:

```bash
adb shell su -c 'dumpsys deviceidle whitelist =com.android.vending'
```

It should print `true`. With the privacy filter enabled, it prints `false` on purpose. The filter disables `DownloadService` and removes the entry, and this module does not add it back.

## Uninstall

Remove the module in your root manager and reboot. FakeStore becomes the system copy again. The uninstall script deletes the module's state files, clears PackageManager's package cache, and removes the device-idle whitelist entry once boot completes.

The Play Store update in `/data/app` has a different signing key than FakeStore. What Android does with it depends on your ROM and signature-compatibility setup, so check `adb shell pm path com.android.vending` after the reboot.
