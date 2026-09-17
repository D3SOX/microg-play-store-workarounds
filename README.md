# microG Play Store workarounds

This repository documents a tested setup for reaching `MEETS_DEVICE_INTEGRITY` on Android 13+ microG custom ROMs while keeping microG as the Play Services implementation. It also includes root modules for Play Store privilege, network filtering, and install provenance.

> [!IMPORTANT]
> `MEETS_DEVICE_INTEGRITY` is a server-side verdict. Google changes attestation rules, accepted device properties, key material, and detection logic over time. The setup below worked on a rooted Android 16 LineageOS-for-microG device, but it may stop working or behave differently on another ROM or device.

## What this repository covers

This setup has five separate parts:

1. **Device attestation.** Get `deviceRecognitionVerdict` to include `MEETS_DEVICE_INTEGRITY`.
2. **Play Store privilege and recognition.** Put the real Google-signed `com.android.vending` in the privileged factory slot instead of microG FakeStore.
3. **App recognition and licensing.** Get Play-installed apps to report `PLAY_RECOGNIZED` and `LICENSED` when applicable.
4. **Optional privacy hardening.** Keep the real Store installed for Integrity while restricting its network access.
5. **Install provenance repair.** Fix legitimate apps whose Aurora, ADB, or restore metadata still says they came from another installer.

Root, Zygisk, and attestation components determine the device verdict. The modules in this repository handle the Play Store, networking, and provenance parts of the setup.

## Tested environment

The reference setup used:

```text
Pixel 8 Pro
Android 16 / SDK 36
LineageOS for microG
APatch
ReZygisk
Zygisk Assistant
Play Integrity Fork
Tricky Store OSS
```

[CorePatch](https://github.com/LSPosed/CorePatch) was also present during the move from microG's differently signed FakeStore package to Google's Play Store. Whether you need a signature-compatibility workaround depends on the ROM and current package state.

Other root managers and Zygisk implementations may work. Follow the current upstream requirements for the integrity modules you use instead of copying this stack indefinitely.

## Reference result

On the reference device, [Play Integrity API Checker](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck), installed through the real Play Store, returned:

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

`PLAY_RECOGNIZED` and `LICENSED` describe the app and account. `MEETS_DEVICE_INTEGRITY` describes the device. They are separate checks.

## Recommended setup order

### 1. Start with a working microG ROM

Get microG working before changing Integrity or Play Store components. Verify device registration, cloud messaging, signature spoofing support where the ROM requires it, and normal app operation.

Do not debug microG and Play Integrity at the same time.

### 2. Install a current Zygisk implementation and root-hiding stack

For APatch or KernelSU setups, use a current Zygisk implementation supported by your integrity module, such as [ReZygisk](https://github.com/PerformanC/ReZygisk).

If you use [Zygisk Assistant](https://github.com/snake-4/Zygisk-Assistant), follow its current upstream instructions for your root manager. Enable the manager's unmount or exclude-modifications option for apps that should not see root or module mounts.

### 3. Install the Play Integrity attestation stack

The tested Android 16 setup used:

- [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork)
- [Tricky Store OSS](https://github.com/beakthoven/TrickyStoreOSS)

Use current releases and read their upstream documentation. On Android 13+, [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork) alone is not a complete device-attestation setup. Attempts to reach `MEETS_DEVICE_INTEGRITY` also need a supported attestation or keystore component.

Do not copy old fingerprints, security-patch dates, or private key material from random guides. Accepted configurations change over time, and inconsistent device properties can make attestation fail.

### 4. Replace FakeStore with a real privileged Play Store base

LineageOS for microG normally puts FakeStore or microG Companion in the privileged `com.android.vending` system slot. If you install the real Play Store only as a `/data/app` update, FakeStore can remain as the factory package metadata. The active Store then may not inherit the privileged package state expected by modern builds.

The `playstore-base` module replaces that factory base systemlessly with a user-supplied, official Google-signed Play Store APK.

Build it locally:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

Google's Play Store APK is proprietary, so this repository and its releases do not include it.

The base module README records the exact Play Store build used on the reference device, its version code, APKMirror page, signer hash, privileged grants, package layout, and the Android 16 `DownloadService` workaround.

See [modules/playstore-base/README.md](modules/playstore-base/README.md).

### 5. Keep the active Play Store update on `/data/app`

The working layout is:

```text
/product/priv-app/FakeStore/FakeStore.apk
    -> official Google Play Store privileged base (systemless replacement)

/data/app/.../com.android.vending
    -> active official Google Play Store update
```

On the tested setup, running the downloaded Store APK directly from the privileged product path caused ART and class-loading problems. Using that APK as the system base while running the normal updated Store from `/data/app` avoided the failure.

### 6. Verify privileged Play Store state

Run these checks:

```bash
adb shell pm path com.android.vending
adb shell dumpsys package com.android.vending | grep -E 'codePath=|versionName=|pkgFlags='
adb shell dumpsys package com.android.vending | grep -E \
  'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:'
```

On the reference setup, the privileged Store had these grants:

```text
INSTALL_PACKAGES
GET_ACCOUNTS_PRIVILEGED
WRITE_SECURE_SETTINGS
MANAGE_USERS
FOREGROUND_SERVICE_SYSTEM_EXEMPTED
```

### 7. Test Play Integrity with a Play-installed checker

Install the checker through the real Play Store after the migration. This keeps app recognition or licensing problems separate from device-integrity problems.

Check these fields separately:

```text
appRecognitionVerdict
appLicensingVerdict
deviceRecognitionVerdict
```

For this guide, `deviceRecognitionVerdict` should include:

```text
MEETS_BASIC_INTEGRITY
MEETS_DEVICE_INTEGRITY
```

## Android 16 Play Store background-service issue

On the tested Android 16 ROM, the Store authenticated and opened, but downloads initially stayed on **Pending**. Logcat showed `com.android.vending:background` crashing when `DownloadService` tried to start a `systemExempted` foreground service.

This command fixed normal Play Store downloads on that setup:

```bash
adb shell su -c 'dumpsys deviceidle whitelist +com.android.vending'
```

`playstore-base` v1.1 applies the command automatically after boot. The base module README includes the service and verification details.

The optional privacy filter disables `DownloadService` and removes this whitelist entry because that configuration intentionally blocks normal Store downloads.

## Included modules

### `playstore-base`

`playstore-base` is a source-only module builder. It replaces the ROM's privileged FakeStore base with a user-supplied official Play Store APK. It also applies the tested Android 16 device-idle workaround for normal Store downloads.

Its README records the tested migration, including the exact Store APK, signing hash, privilege failures before the fix, final package layout, relevant services, and final Integrity result.

See [modules/playstore-base/README.md](modules/playstore-base/README.md).

### `playstore-xray-privacy-filter`

`playstore-xray-privacy-filter` is an optional ARM64 per-UID default-deny network filter for the real Play Store. It does not use Android `VpnService`.

Its README records the tested four-domain allowlist, blocked Store and CDN examples, firewall design, Xray binary source, download URL and hash, expected device-idle state, and uninstall behavior.

See [modules/playstore-xray-privacy-filter/README.md](modules/playstore-xray-privacy-filter/README.md).

### `play-provenance-repair`

`play-provenance-repair` is an APatch WebUI and CLI helper for legitimately owned apps previously installed through Aurora, ADB, restore tools, or another installer when those apps still expect Google Play installer or initiator provenance.

Its README documents three observed failure classes: an installer-only mismatch, an incorrect initiating package, and an app-specific local warning that remains after the real Play license check succeeds.

The helper does not create purchase entitlements or bypass failed license checks.

See [modules/play-provenance-repair/README.md](modules/play-provenance-repair/README.md).

## Optional privacy hardening

On the reference setup, the Play Store UID could reach only these observed Integrity-related hosts while the same Integrity result continued to pass:

```text
play.googleapis.com
play-fe.googleapis.com
gmscompliance-pa.googleapis.com
remoteprovisioning.googleapis.com
```

This allowlist comes from observed behavior and can become stale. The privacy module README documents the full routing policy and its limits.

## Paid and Play-protected app provenance

After you replace FakeStore with the real Store, some legitimately owned apps can still retain an old install source.

The tested cases showed that these fields and states can fail independently:

```text
installerPackageName
initiatingPackageName
app-specific cached warning state
```

A Play-owned in-place reinstall can repair both Android provenance fields without deleting app data. The helper applies that repair to one app at a time instead of offering a bulk "repair all" operation.

See [modules/play-provenance-repair/README.md](modules/play-provenance-repair/README.md) for the tested behavior.

## Troubleshooting

### Only `MEETS_BASIC_INTEGRITY`

Treat this as an attestation or root-hiding problem first, not a Play Store problem. Check the current Play Integrity Fork and Tricky Store OSS configuration, the Zygisk implementation, root hiding, and the upstream recommendations for your Android version.

### `MEETS_DEVICE_INTEGRITY` works, but an app is `UNRECOGNIZED_VERSION` or `UNLICENSED`

This points to app recognition or install provenance. Install the app through the real Play Store and verify that the Store runs as the privileged `com.android.vending` base.

### Play Store opens but downloads stay pending or its background process crashes

Check logcat for `com.android.vending:background` and `DownloadService`. On the tested Android 16 ROM, the Store needed the device-idle whitelist for its `systemExempted` foreground service. Current `playstore-base` applies the workaround automatically.

### An owned app still says it was not installed by Play

Inspect both `installerPackageName` and `initiatingPackageName`. If the app is legitimately owned and the real Play Store recognizes the entitlement, use the provenance helper only for that app.

## Scope and cautions

- Root access is required.
- The base module assumes FakeStore occupies `/product/priv-app/FakeStore/FakeStore.apk`.
- Moving from differently signed FakeStore to Google's Play Store may require ROM-specific or root-specific signature compatibility handling.
- Play Integrity behavior changes on Google's servers, so a configuration that works now may stop working later.
- Do not use private keyboxes, fingerprints, or attestation material from unknown sources.
- Back up important data before changing privileged system-package layout or app installer provenance.
