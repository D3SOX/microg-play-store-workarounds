# microG Play Store Workarounds

A practical guide and small set of root modules for getting a modern Google Play Integrity setup working on **microG-based custom ROMs**, with a focus on reaching `MEETS_DEVICE_INTEGRITY` on Android 13+ while keeping microG as the Play Services implementation.

> [!IMPORTANT]
> `MEETS_DEVICE_INTEGRITY` is a server-side verdict. Google changes attestation rules, accepted device properties, key material and detection logic over time. This repository documents a setup that worked on a rooted Android 16 LineageOS-for-microG device; it is not a permanent guarantee for every ROM or device.

## What this repository covers

There are several separate layers that are easy to conflate:

1. **Device attestation** — getting `deviceRecognitionVerdict` to include `MEETS_DEVICE_INTEGRITY`.
2. **Play Store privilege/recognition** — making the real Google-signed `com.android.vending` exist as the privileged factory base instead of microG FakeStore.
3. **App recognition/licensing** — getting Play-installed apps to report `PLAY_RECOGNIZED` / `LICENSED` where appropriate.
4. **Optional privacy hardening** — keeping the real Store installed for Integrity while restricting its network access.
5. **Install provenance repair** — fixing legitimate apps whose old Aurora/ADB/restore install metadata still says they did not come from Play.

The device verdict comes primarily from the root/Zygisk/attestation stack. The modules in this repository solve the Play Store compatibility, networking and provenance pieces around that setup.

## Tested environment

The reference setup was:

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

CorePatch was also present while migrating `com.android.vending` from microG's differently signed FakeStore package to Google's Play Store. Whether a signature-compatibility workaround is needed depends on the ROM and package state.

Other root managers and Zygisk implementations may work. Follow the current upstream requirements of the integrity modules you choose rather than copying one old stack indefinitely.

## Reference result

The final tested state was verified with [Play Integrity API Checker](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck) installed through the real Play Store:

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

`PLAY_RECOGNIZED` and `LICENSED` are app/account results. `MEETS_DEVICE_INTEGRITY` is the device verdict. Do not treat them as the same check.

## Recommended setup order

### 1. Start with a working microG ROM

Get microG itself working first: device registration, cloud messaging, signature spoofing support where required by the ROM, and normal app operation.

Do not debug a broken microG installation and Play Integrity at the same time.

### 2. Install a current Zygisk implementation and root-hiding stack

For APatch/KernelSU-style setups, use a current compatible Zygisk implementation such as ReZygisk or another implementation supported by the integrity module you are using.

If you use Zygisk Assistant, follow its current upstream instructions for your root manager and enable the manager's unmount/exclude-modifications option for apps that should not see root/module mounts.

### 3. Install the Play Integrity attestation stack

The tested Android 16 setup used:

- [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork)
- [Tricky Store OSS](https://github.com/beakthoven/TrickyStoreOSS)

Use current releases and read their upstream documentation. On Android 13+, Play Integrity Fork by itself is not the complete modern device-attestation solution; a supported attestation/keystore component is also needed for `MEETS_DEVICE_INTEGRITY` attempts.

Do **not** blindly copy old fingerprints, security-patch dates or private key material from random guides. Accepted configurations are time-sensitive, and internally inconsistent device properties can make attestation worse.

### 4. Replace FakeStore with a real privileged Play Store base

LineageOS for microG normally supplies FakeStore/microG Companion in the privileged `com.android.vending` system slot. Installing the real Play Store only as a `/data/app` update can leave FakeStore as the factory package metadata, which prevents the active Store from inheriting the privileged package state expected by modern builds.

The `playstore-base` module systemlessly replaces that factory base with a user-supplied official Google-signed Play Store APK.

Build it locally:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

Google's Play Store APK is proprietary and is intentionally **not** included in this repository or its releases.

The exact Play Store build used for the reference setup, its version code, APKMirror page, signer hash, privileged grants, package layout and Android 16 `DownloadService` workaround are preserved in:

**[modules/playstore-base/README.md](modules/playstore-base/README.md)**

### 5. Keep the active Play Store update on `/data/app`

The working layout is:

```text
/product/priv-app/FakeStore/FakeStore.apk
    -> official Google Play Store privileged base (systemless replacement)

/data/app/.../com.android.vending
    -> active official Google Play Store update
```

Directly executing the downloaded Store APK from the privileged product path caused ART/class-loading problems on the tested setup. Using it as the system base while letting the normal updated Store execute from `/data/app` avoided that failure.

### 6. Verify privileged Play Store state

Useful checks:

```bash
adb shell pm path com.android.vending
adb shell dumpsys package com.android.vending | grep -E 'codePath=|versionName=|pkgFlags='
adb shell dumpsys package com.android.vending | grep -E \
  'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:'
```

On the reference setup the real privileged Store had the expected grants, including:

```text
INSTALL_PACKAGES
GET_ACCOUNTS_PRIVILEGED
WRITE_SECURE_SETTINGS
MANAGE_USERS
FOREGROUND_SERVICE_SYSTEM_EXEMPTED
```

### 7. Test Play Integrity with a Play-installed checker

For the cleanest result, install the checker through the real Play Store after the migration. This avoids confusing a device-integrity problem with an app `UNRECOGNIZED_VERSION` or licensing/provenance problem.

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

## Android 16 Play Store background-service issue

On the tested Android 16 ROM, the Store authenticated and opened but downloads initially stayed on **Pending**. Logcat showed `com.android.vending:background` crashing when `DownloadService` attempted to start a `systemExempted` foreground service.

For a normal Play Store setup, the working fix was:

```bash
adb shell su -c 'dumpsys deviceidle whitelist +com.android.vending'
```

Current `playstore-base` v1.1 applies this automatically after boot. See the base module README for the exact service and verification details.

The optional privacy filter deliberately disables `DownloadService` and removes this whitelist entry, because normal Store downloads are intentionally not part of that restricted-network configuration.

## Included modules

### `playstore-base`

Source-only module builder that replaces the ROM's privileged FakeStore base with a user-supplied official Play Store APK and applies the tested Android 16 device-idle workaround so normal Store downloads can work.

Its README contains the full tested migration details, including the exact Store APK used, signing hash, privilege failures before the fix, final package layout, relevant services and final Integrity result.

See [modules/playstore-base/README.md](modules/playstore-base/README.md).

### `playstore-xray-privacy-filter`

Optional ARM64 per-UID default-deny network filter for the real Play Store without using Android `VpnService`.

The documentation preserves the tested four-domain allowlist, blocked Store/CDN examples, firewall design, Xray binary source/download/hash, expected device-idle state and uninstall behavior.

See [modules/playstore-xray-privacy-filter/README.md](modules/playstore-xray-privacy-filter/README.md).

### `play-provenance-repair`

APatch WebUI/CLI helper for legitimately owned apps that were previously installed through Aurora, ADB, restore tools or another installer and still expect Google Play installer/initiator provenance.

Its README documents the three observed failure classes: installer-only mismatch, incorrect initiating package, and an app-specific sticky local warning after the real Play license check already succeeds.

It does not create purchase entitlements or bypass failed license checks.

See [modules/play-provenance-repair/README.md](modules/play-provenance-repair/README.md).

## Optional privacy hardening

The tested Play Store UID could be restricted to these observed Integrity-related hosts while the reference Integrity result continued to work:

```text
play.googleapis.com
play-fe.googleapis.com
gmscompliance-pa.googleapis.com
remoteprovisioning.googleapis.com
```

That allowlist is empirical and can become stale. The full routing policy and caveats are documented in the privacy module README.

## Paid / Play-protected app provenance

After replacing FakeStore with the real Store, some legitimately owned apps can still remember an old install source.

The tested cases showed that these can independently matter:

```text
installerPackageName
initiatingPackageName
app-specific cached warning state
```

A Play-owned in-place reinstall can repair both Android provenance fields without losing app data. The helper implements that per app rather than offering a dangerous bulk "repair all" operation.

See [modules/play-provenance-repair/README.md](modules/play-provenance-repair/README.md) for the complete tested behavior.

## Troubleshooting

### Only `MEETS_BASIC_INTEGRITY`

Treat this first as an attestation/root-hiding problem, not a Play Store problem. Verify the current Play Integrity Fork and Tricky Store OSS configuration, the Zygisk implementation, root hiding and the upstream recommendations for your Android version.

### `MEETS_DEVICE_INTEGRITY` works, but an app is `UNRECOGNIZED_VERSION` or `UNLICENSED`

That is an app recognition/install-source problem. Install the app through the real Play Store and verify the Store itself is operating as the privileged `com.android.vending` base.

### Play Store opens but downloads stay pending or its background process crashes

Check logcat for `com.android.vending:background` and `DownloadService`. On the tested Android 16 ROM the device-idle whitelist was required for the Store's `systemExempted` foreground service. Current `playstore-base` applies that workaround automatically.

### An owned app still says it was not installed by Play

Inspect both `installerPackageName` and `initiatingPackageName`. If the app is legitimately owned and the real Play Store recognizes the entitlement, use the provenance helper only for that specific app.

## Scope and cautions

- Root access is required.
- The base module assumes a ROM layout where FakeStore occupies `/product/priv-app/FakeStore/FakeStore.apk`.
- A differently signed transition from FakeStore to Google's Play Store may require ROM/root-specific signature compatibility handling.
- Play Integrity behavior changes server-side; a configuration that works today may stop working later.
- Do not use random private keyboxes, fingerprints or attestation material from unknown sources.
- Back up important data before changing privileged system-package layout or app installer provenance.
