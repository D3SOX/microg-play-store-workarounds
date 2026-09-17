# microG Play Store Workarounds

A practical guide and small set of root modules for getting a modern Google Play Integrity setup working on **microG-based custom ROMs**, with a focus on reaching `MEETS_DEVICE_INTEGRITY` on Android 13+ while keeping microG as the Play Services implementation.

> [!IMPORTANT]
> `MEETS_DEVICE_INTEGRITY` is a server-side verdict. Google changes the attestation rules, accepted fingerprints, key material, and detection logic over time. This repository documents a setup that worked on a rooted Android 16 LineageOS-for-microG device; it is not a permanent guarantee for every ROM or device.

## What this repository solves

There are two related but separate problems on a microG ROM:

1. **Device attestation** — getting the device-side Play Integrity verdict to include `MEETS_DEVICE_INTEGRITY`.
2. **Play Store recognition/licensing** — making apps that expect the real privileged `com.android.vending` package see an official Google Play Store installation and normal Play installer provenance.

The first problem is primarily handled by the root/Zygisk/attestation stack. The second is where the modules in this repository are useful.

A successful result can look like:

```text
PLAY_RECOGNIZED
MEETS_BASIC_INTEGRITY
MEETS_DEVICE_INTEGRITY
LICENSED
```

`PLAY_RECOGNIZED` and `LICENSED` are app/account results. `MEETS_DEVICE_INTEGRITY` is the device verdict. Do not treat them as the same check.

## Tested setup

The configuration this repository was built around was:

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

CorePatch was also present during the initial migration from microG FakeStore to Google's differently signed Play Store package. Whether a signature-compatibility workaround is needed depends on the ROM and how `com.android.vending` is currently installed.

Other root managers and Zygisk implementations can work. Follow the current upstream requirements for the integrity modules you choose rather than copying one old combination indefinitely.

## Recommended setup order

### 1. Start with a working microG ROM

Get microG itself working first: account sign-in if you use it, device registration, cloud messaging, signature spoofing support, and normal app operation.

Do not debug Play Integrity and a broken microG installation at the same time.

### 2. Install a current Zygisk implementation

For APatch/KernelSU-style setups, use a current compatible Zygisk implementation such as ReZygisk or another implementation supported by the integrity module you are using.

If you use Zygisk Assistant, follow its current upstream instructions for your root manager and enable the manager's unmount/exclude-modifications option for apps that should not see root/module mounts.

### 3. Install the Play Integrity attestation stack

For the tested Android 16 setup this consisted of:

- [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork)
- [Tricky Store OSS](https://github.com/beakthoven/TrickyStoreOSS)

Use current releases and read their upstream documentation. This matters especially on Android 13+, where Play Integrity Fork by itself is not the complete solution for the modern device-attestation path.

Play Integrity Fork's current documentation explicitly recommends a supported attestation/keystore solution such as Tricky Store/Tricky Store OSS for Android 13+ `MEETS_DEVICE_INTEGRITY` attempts.

Do **not** blindly copy old fingerprints, security-patch dates, or key material from random guides. The accepted configuration is time-sensitive and inconsistent combinations can make attestation worse.

### 4. Replace microG FakeStore with an official Play Store privileged base

LineageOS for microG normally provides a FakeStore/microG Companion package at the privileged `com.android.vending` system location. Merely installing the official Play Store as a `/data/app` update can leave FakeStore as the factory package metadata, so the active Play Store may not inherit all privileged permissions expected by modern builds.

The `playstore-base` module in this repository replaces that factory base **systemlessly** with a user-supplied official Google-signed Play Store APK.

Build it locally:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

Google's Play Store APK is proprietary and is intentionally not included in this repository or its releases.

After installing the module and rebooting, install the official Play Store normally as the active update so execution comes from `/data/app` while the privileged system base remains visible to PackageManager.

See [modules/playstore-base/README.md](modules/playstore-base/README.md) for the full sequence and verification commands.

### 5. Verify the Play Store package state

Useful checks:

```bash
adb shell pm path com.android.vending
adb shell dumpsys package com.android.vending | grep -E 'codePath=|versionName=|pkgFlags='
adb shell dumpsys package com.android.vending | grep -E \
  'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:'
```

The intended layout is:

```text
/product/priv-app/FakeStore/FakeStore.apk
    -> systemlessly replaced with an official Google Play Store APK

/data/app/.../com.android.vending
    -> active official Play Store update
```

Keeping the active code on `/data/app` avoided ART/class-loading problems encountered when a downloaded Play Store build was executed directly from the privileged product path.

### 6. Test Play Integrity with a Play-installed checker

For the cleanest result, install your checker through the real Play Store after the migration. This avoids confusing a device-integrity problem with an `UNRECOGNIZED_VERSION`/licensing/provenance problem in the checker itself.

A useful checker is [Play Integrity API Checker](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck).

Look separately at:

```text
appRecognitionVerdict
appLicensingVerdict
deviceRecognitionVerdict
```

The target for this guide is that `deviceRecognitionVerdict` includes:

```text
MEETS_BASIC_INTEGRITY
MEETS_DEVICE_INTEGRITY
```

## Android 16 Play Store background-service fix

On the tested Android 16 ROM, the Play Store's background `DownloadService` crashed when it tried to start a `systemExempted` foreground service without the required exemption.

For a normal Play Store setup where downloads should keep working, the base module now adds:

```bash
dumpsys deviceidle whitelist +com.android.vending
```

after boot. This was the working fix for the foreground-service crash on the tested ROM.

The optional privacy module deliberately uses the opposite policy: it disables only that `DownloadService` and removes the Play Store from the device-idle whitelist because Store downloads are intentionally not part of that minimal-network setup.

## Included modules

### `playstore-base`

Source-only APatch-style module builder that replaces the ROM's privileged FakeStore base with a user-supplied official Play Store APK. It also applies the Android 16 device-idle whitelist workaround after boot so normal Play Store downloads can operate on the tested ROM.

See [modules/playstore-base/README.md](modules/playstore-base/README.md).

### `playstore-xray-privacy-filter`

Optional ARM64 root module for users who want the real Play Store installed for Integrity but do not want general Store networking. It applies a per-UID default-deny policy, permits only the currently observed Integrity-related endpoints, disables Play Store `DownloadService`, and removes the Store from the Doze whitelist.

This is intentionally restrictive and breaks normal Play Store browsing/download behavior.

See [modules/playstore-xray-privacy-filter/README.md](modules/playstore-xray-privacy-filter/README.md).

### `play-provenance-repair`

APatch WebUI/CLI helper for legitimately owned apps that were previously installed through Aurora, ADB, a restore tool, or another installer and still expect Google Play installer/initiator provenance.

It does not create purchase entitlements or bypass failed license checks.

See [modules/play-provenance-repair/README.md](modules/play-provenance-repair/README.md).

## Troubleshooting

### Only `MEETS_BASIC_INTEGRITY`

Treat this first as an attestation/root-hiding problem, not a Play Store problem. Verify the current Play Integrity Fork and Tricky Store OSS setup, the Zygisk implementation, root hiding, and the configuration recommended by those upstream projects for your Android version.

### `MEETS_DEVICE_INTEGRITY` works, but an app is `UNRECOGNIZED_VERSION` or `UNLICENSED`

That is an app recognition/install-source problem. Install the app from the real Play Store and verify that the Store itself is operating as the privileged `com.android.vending` base.

### Play Store opens but downloads stay pending or the background process crashes

Check logcat for `com.android.vending:background` and `DownloadService`. On the tested Android 16 ROM the device-idle whitelist was required for the Store's `systemExempted` foreground service. Current `playstore-base` applies that workaround automatically.

### A paid app is owned but still says it was not installed by Play

Use the provenance-repair module only for that specific app. Some apps inspect both `installerPackageName` and `initiatingPackageName`, and some cache their own local warning state.

## Privacy notes

The official Play Store is not required to have unrestricted network access for every Integrity check observed during testing. The optional Xray module demonstrates a per-UID allowlist approach without consuming Android's VPN slot.

Its hostname allowlist is empirical and can become stale at any time as Google changes endpoints, TLS/ECH behavior, or Integrity implementation details.

## Building release archives

```bash
./scripts/build-release.sh
```

The generated ZIPs and `SHA256SUMS` are written to `dist/` locally. `dist/` is not meant to be committed; published binaries belong in GitHub Releases.

## Scope and cautions

- Root access is required.
- The base module assumes a ROM layout where FakeStore occupies `/product/priv-app/FakeStore/FakeStore.apk`.
- A differently signed transition from FakeStore to Google's Play Store may require ROM/root-specific signature compatibility handling.
- Play Integrity behavior changes server-side; a configuration that works today may stop working later.
- Do not use random private keyboxes, fingerprints, or attestation material from unknown sources.
- Back up important data before changing privileged system-package layout or app installer provenance.
