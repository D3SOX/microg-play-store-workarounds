# Google Play Store System Base

Source-only APatch-style module for microG ROMs where FakeStore/microG Companion occupies the privileged `com.android.vending` system slot. It systemlessly replaces that factory base with a user-supplied official Google-signed Play Store APK early enough for PackageManager to treat Google Play as the privileged base package.

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

The exact factory-base APK used for the tested setup was:

**Google Play Store 53.0.27-31 [0] [PR] 973951861**

```text
Version code: 85302730
Variant: universal / nodpi
Minimum Android: Android 12+
Package format: standalone APK, not an APK bundle
APK size: 105704839 bytes (~100.81 MiB)
Google signer SHA-256: 7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053
```

APKMirror page used during testing:

https://www.apkmirror.com/apk/google-inc/google-play-store/google-play-store-53-0-27-release/google-play-store-53-0-27-31-0-pr-973951861-3-android-apk-download/

This is a record of the tested build, **not** a requirement that everyone use this old version forever. Prefer a current compatible official Google-signed standalone build when adapting the setup, and verify its signature before using it as a privileged base.

After the tested setup was working, the active `/data/app` Play Store updated to `53.0.27-34 [0] [PR] 973951861`; the privileged base remaining on the earlier compatible build did not prevent the normal update layer from running.

## Build the module

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

The generated `playstore_base.zip` is for your own device. Do not redistribute a build containing Google's proprietary APK.

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

4. Install the official Play Store normally so it becomes the active `/data/app` update:

   ```bash
   adb install -r PlayStore.apk
   ```

5. Reboot again.
6. Open Play Store, sign in, and allow it to finish its normal initialization/update process.

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
  'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:'
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

`playstore-base` v1.1 applies this automatically in `service.sh` after `sys.boot_completed=1`:

```sh
dumpsys deviceidle whitelist +com.android.vending
```

The optional `playstore-xray-privacy-filter` module deliberately uses the opposite policy: it disables only `DownloadService` and removes `com.android.vending` from the device-idle whitelist because normal Store downloads are intentionally disabled in that privacy-hardened setup. Its delayed removal is designed to override this base module's boot-time allowlist addition.

## Why the real privileged Store matters

This module does **not** produce `MEETS_DEVICE_INTEGRITY` by itself. The device verdict still depends on the root/Zygisk/attestation stack.

What this module fixes is the Play Store side of the environment:

- the real Google-signed `com.android.vending` exists as the privileged factory base;
- expected privileged permissions are granted;
- Play Integrity can bind to the real Store service;
- Play licensing/billing components exist where applications expect them;
- apps installed through Play can be `PLAY_RECOGNIZED` / `LICENSED` instead of being confused by a FakeStore factory base.

On the tested Android 16 setup, this was used alongside APatch, ReZygisk, Zygisk Assistant, Play Integrity Fork and Tricky Store OSS.

## Final tested Integrity result

The working device was verified with [Play Integrity API Checker](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck) installed through the real Play Store. The relevant result was:

```json
{
  "appIntegrity": {
    "appRecognitionVerdict": "PLAY_RECOGNIZED",
    "packageName": "gr.nikolasspyr.integritycheck",
    "versionCode": "22"
  },
  "deviceIntegrity": {
    "deviceRecognitionVerdict": [
      "MEETS_BASIC_INTEGRITY",
      "MEETS_DEVICE_INTEGRITY"
    ],
    "recentDeviceActivity": {
      "deviceActivityLevel": "LEVEL_1"
    },
    "deviceAttributes": {
      "sdkVersion": 36
    }
  },
  "accountDetails": {
    "appLicensingVerdict": "LICENSED"
  },
  "environmentDetails": {
    "playProtectVerdict": "NO_ISSUES"
  }
}
```

Treat this as a tested reference point, not as a promise that Google's server-side verdicts will remain unchanged.
