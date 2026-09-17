# Google Play Store System Base

> Maintained by **D3SOX** (assisted by GPT).

Source-only APatch module for the tested LineageOS-for-microG workaround. It systemlessly replaces the ROM's privileged microG FakeStore base with a user-supplied official Google-signed Play Store APK early enough for PackageManager to treat Google Play as the factory `com.android.vending` package.

## Why it exists

On the tested Android 16 LineageOS-for-microG setup, installing the official Play Store only as a `/data/app` update left the ROM FakeStore manifest as the factory package metadata. The updated Play Store then lacked privileged permissions required by current builds.

The module bind-mounts the supplied Play Store APK over:

```text
/product/priv-app/FakeStore/FakeStore.apk
```

before the package scan. On the first successful boot it also invalidates PackageManager's parser cache once so stale FakeStore metadata is not reused.

## Build

This repository intentionally does **not** redistribute Google's Play Store APK.

Provide your own official Google-signed standalone APK:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

The generated `playstore_base.zip` is for your own device. Do not redistribute a build containing Google's proprietary APK.

## Install sequence used in testing

1. Build and install `playstore_base.zip` in APatch.
2. Reboot.
3. Remove any old FakeStore/microG Companion update if necessary:

   ```bash
   adb shell su -c 'pm uninstall-system-updates com.android.vending'
   ```

4. Install the same official Play Store APK normally as the active `/data/app` update:

   ```bash
   adb install -r PlayStore.apk
   ```

5. Reboot and verify that the factory base is privileged while the active update executes from `/data/app`:

   ```bash
   adb shell pm path com.android.vending
   adb shell dumpsys package com.android.vending | grep -E 'codePath=|versionName=|pkgFlags='
   adb shell dumpsys package com.android.vending | grep -E 'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:'
   ```

## Android 16 DownloadService caveat

On the tested ROM, Play Store's `DownloadService` could crash while starting a `systemExempted` foreground service unless the package was device-idle allowlisted. If you need normal Play Store downloads, this may require ROM-specific handling.

The companion privacy module in this repository takes the opposite approach for a minimal-Store setup: it disables only that DownloadService and removes the Play Store from the Doze whitelist while preserving the tested Integrity path.

## Scope

This is a rooted/custom-ROM workaround. It does not solve the underlying Remote Control/Play Integrity policy issue for locked alternative Android operating systems such as official GrapheneOS, and it does not itself provide a `MEETS_DEVICE_INTEGRITY` verdict. That depended on the existing root/attestation configuration on the test device.
