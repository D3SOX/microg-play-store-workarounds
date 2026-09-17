# Google Play Store System Base

Source-only APatch-style module for microG ROMs where FakeStore/microG Companion occupies the privileged `com.android.vending` system slot. It systemlessly replaces that factory base with a user-supplied official Google-signed Play Store APK early enough for PackageManager to treat Google Play as the privileged base package.

## Why it exists

On the tested Android 16 LineageOS-for-microG setup, installing the official Play Store only as a `/data/app` update left FakeStore as the factory package metadata. The updated Play Store then did not receive all privileged permissions expected by current builds.

The module mounts the supplied Play Store APK over:

```text
/product/priv-app/FakeStore/FakeStore.apk
```

before the package scan.

The intended end state is:

```text
/product/priv-app/FakeStore/FakeStore.apk
    official Google Play Store privileged base (systemless replacement)

/data/app/.../com.android.vending
    active official Google Play Store update
```

Keeping the active update on `/data/app` avoids the ART/class-loading problem observed when a downloaded Store APK was executed directly from the privileged product path.

## Build

This repository intentionally does **not** redistribute Google's Play Store APK.

Provide your own official Google-signed standalone APK:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

The generated `playstore_base.zip` is for your own device. Do not redistribute a build containing Google's proprietary APK.

## Install sequence

1. Build and install `playstore_base.zip` in APatch or a compatible module manager.
2. Reboot.
3. If an old FakeStore/microG Companion update is still installed, remove the update layer if needed:

   ```bash
   adb shell su -c 'pm uninstall-system-updates com.android.vending'
   ```

4. Install the same official Play Store APK normally as the active `/data/app` update:

   ```bash
   adb install -r PlayStore.apk
   ```

5. Reboot again.

6. Verify package layout and privileged grants:

   ```bash
   adb shell pm path com.android.vending
   adb shell dumpsys package com.android.vending | grep -E 'codePath=|versionName=|pkgFlags='
   adb shell dumpsys package com.android.vending | grep -E 'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:'
   ```

A differently signed migration from FakeStore to the official Play Store can require signature-compatibility handling depending on the ROM/root setup. This module does not attempt to universally patch Android package-signature policy.

## Android 16 DownloadService / device-idle workaround

On the tested Android 16 ROM, Play Store's background `DownloadService` could crash while starting a `systemExempted` foreground service when `com.android.vending` was not device-idle allowlisted.

The module's `service.sh` now waits for boot completion and applies:

```bash
dumpsys deviceidle whitelist +com.android.vending
```

This is intentional for a normal Store setup where browsing/downloads should work.

Verify after boot:

```bash
adb shell su -c 'dumpsys deviceidle whitelist =com.android.vending'
```

Expected on this configuration:

```text
true
```

The optional `playstore-xray-privacy-filter` module takes the opposite approach: it disables only Play Store `DownloadService` and removes `com.android.vending` from the device-idle whitelist because normal Store downloads are intentionally disabled in that privacy-hardened setup. Its delayed removal is designed to override the base module's boot-time allowlist addition.

## Relation to `MEETS_DEVICE_INTEGRITY`

This module does **not** create the device-integrity verdict by itself. It solves the privileged Play Store side of a microG setup: app recognition, licensing/provenance expectations, and privileged `com.android.vending` behavior.

On Android 13+, reaching `MEETS_DEVICE_INTEGRITY` still depends on the root/Zygisk/attestation stack, such as a current Play Integrity Fork plus a supported attestation/keystore solution like Tricky Store OSS, and correct root hiding for the device.
