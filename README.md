# microG Play Store workarounds

This repository documents a tested setup for reaching `MEETS_DEVICE_INTEGRITY` on Android 13+ microG custom ROMs while keeping microG as the Play Services implementation. The current reference device also passes `MEETS_STRONG_INTEGRITY`. The repository includes root modules for Play Store privilege, network filtering, and install provenance.

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

The reference setup, last tested on 2026-11-12, used:

```text
Pixel 8 Pro
Android 16 / SDK 36
LineageOS for microG 23.2 with microG 0.3.18
APatch with Hybrid Mount as the metamodule
ReZygisk
Zygisk Assistant
Play Integrity Fork v19 with a current Pixel 8 Pro profile
OhMyKeymint 1.2.6 (keystore module)
Public Yurikey68 keybox
Google Play Store 54.1.11-34 (privileged base and /data/app update)
```

The setup tested in September 2026 used Tricky Store OSS with Yurikey Manager and Play Store 53.0.27, and reached `MEETS_DEVICE_INTEGRITY`. In November 2026, that stack returned only `MEETS_BASIC_INTEGRITY` with the current Yurikey keybox. OhMyKeymint with the same keybox and a current Play Integrity Fork profile passed all three device verdicts. Tricky Store OSS was not retested with that profile, so this does not show which of the two changes was needed.

[CorePatch](https://github.com/LSPosed/CorePatch), running in the Vector LSPosed fork, was also present during the move from microG's differently signed FakeStore package to Google's Play Store. Whether you need a signature-compatibility workaround depends on the ROM and current package state.

Other root managers and Zygisk implementations may work. Follow the current upstream requirements for the integrity modules you use instead of copying this stack indefinitely.

## Reference result

On 2026-11-12, [Play Integrity API Checker](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck), installed through the real Play Store, returned this on the reference device. The privacy filter was enabled.

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
      "MEETS_DEVICE_INTEGRITY",
      "MEETS_STRONG_INTEGRITY"
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

`PLAY_RECOGNIZED` and `LICENSED` describe the app and account. The `MEETS_*` verdicts describe the device. They are separate checks.

## Recommended setup order

### 1. Start with a working microG ROM

Get microG working before changing Integrity or Play Store components. Verify device registration, cloud messaging, signature spoofing support where the ROM requires it, and normal app operation.

Do not debug microG and Play Integrity at the same time.

For hardware-backed attestation, open microG Settings, then **Device Attestation > Advanced**, and turn off **Block hardware attestation**. Some microG versions label this section **Google SafetyNet**. The keystore module in step 3 answers hardware attestation requests, and the reference device passed with this option off.

### 2. Install a current Zygisk implementation and root-hiding stack

For APatch or KernelSU setups, use a current Zygisk implementation supported by your integrity module, such as [ReZygisk](https://github.com/PerformanC/ReZygisk).

If you use [Zygisk Assistant](https://github.com/snake-4/Zygisk-Assistant), follow its current upstream instructions for your root manager. Enable the manager's unmount or exclude-modifications option for apps that should not see root or module mounts.

### 3. Install the Play Integrity attestation stack

The tested Android 16 setup used:

- [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork) v19
- [OhMyKeymint](https://github.com/qwq233/OhMyKeymint) [1.2.6-9069c6c](https://github.com/qwq233/OhMyKeymint/releases/tag/1.2.6-9069c6c) as the keystore module
- a working keybox, see [Keybox](#keybox)

Use current releases and read their upstream documentation. On Android 13+, Play Integrity Fork alone is not a complete device-attestation setup. `MEETS_DEVICE_INTEGRITY` also needs a keystore module that signs attestations with a keybox Google trusts.

Do not copy old fingerprints, security-patch dates, or private key material from random guides. Accepted configurations change over time, and inconsistent device properties can make attestation fail.

#### Play Integrity Fork

Installing Play Integrity Fork does not configure it. On the reference device, the module's `autopif4.sh --strong --match` generated a current Pixel 8 Pro Canary profile in `custom.pif.prop`. That profile set `spoofProvider=0` and `spoofVendingSdk=0`, and its `ro.build.version.security_patch` line was uncommented. The generated profile records an estimated expiry date, 2026-12-16 for the tested one. Generate a new profile after that date.

#### OhMyKeymint

Follow the [configuration guide](https://github.com/qwq233/OhMyKeymint/blob/master/docs/CONFIGURATION.md). On the reference device:

- `/data/misc/keystore/omk/keybox.xml` held the keybox.
- `/data/misc/keystore/omk/injector.toml` targeted `com.google.android.gms`, `com.google.android.gsf`, and `com.android.vending`.
- `os_patchlevel`, `vendor_patchlevel`, and `boot_patchlevel` in `/data/misc/keystore/omk/config.toml` matched the Play Integrity Fork profile's patch level, `2026-11-05`.

OhMyKeymint without the Play Integrity Fork profile and matching patch levels returned only `MEETS_BASIC_INTEGRITY` with the same keybox.

Run only one keystore module at a time. Disable Tricky Store OSS before you enable OhMyKeymint.

#### Keybox

Every verdict above `MEETS_BASIC_INTEGRITY` needs a working keybox. A keybox works only while Google trusts it. It fails when Google revokes it, when one of its certificates expires, or when Google stops trusting it without listing it as revoked.

The reference device used the public `Yurikey68` keybox. [Yurikey Manager](https://github.com/Yurii0307/yurikey) downloads its keyboxes from the Yurikey repository and writes them to Tricky Store's path, `/data/adb/tricky_store/keybox.xml`. With OhMyKeymint, copy the file to `/data/misc/keystore/omk/keybox.xml`, keep its `keystore` owner and `0600` mode, and reboot. OhMyKeymint does not need Yurikey Manager, and the module stayed disabled on the reference device.

A public keybox is leaked key material that many devices share, so Google revokes it sooner or later. The Yurikey keyboxes from November 2026 also had short-lived certificates. `Yurikey67` expired on the day it was published, and `Yurikey68` was valid for 12 days. Check the expiry date of the first certificate whenever the verdict drops:

```bash
adb shell su -c "sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' /data/misc/keystore/omk/keybox.xml" \
  | sed 's/^[[:space:]]*//' | openssl x509 -noout -subject -enddate
```

This command copies only the certificates off the phone, not the private key.

#### Tricky Store OSS

The September 2026 setup used [Tricky Store OSS](https://github.com/beakthoven/TrickyStoreOSS) instead of OhMyKeymint. Tricky Store OSS reads its keybox from `/data/adb/tricky_store/keybox.xml` and reloads it without a reboot. Back up `/data/adb/tricky_store/` before you run the Yurikey Manager action if you maintain those files yourself.

### 4. Replace FakeStore with a real privileged Play Store base

LineageOS for microG normally puts FakeStore or microG Companion in the privileged `com.android.vending` system slot. If you install the real Play Store only as a `/data/app` update, FakeStore can remain as the factory package metadata. The active Store then may not inherit the privileged package state expected by modern builds.

The `playstore-base` module replaces that factory base systemlessly with a user-supplied, official Google-signed Play Store APK.

Build it locally:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

Google's Play Store APK is proprietary, so this repository and its releases do not include it.

Android refuses to boot when a privileged app requests a privileged permission that the ROM's allowlist does not grant. Play Store 54.1.11 requests `android.permission.GET_ROLE_HOLDERS`, which LineageOS for microG does not allowlist for `com.android.vending`, so system_server crashed on every boot. Since v1.3, the module replaces the ROM's `privapp-permissions-com.android.vending.xml` with a copy that adds this permission. It mounts the APK only after that file. A later Play Store build may request another permission. See [Boot loop after installing playstore-base](#boot-loop-after-installing-playstore-base).

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

On the tested setup, running the downloaded Store APK directly from the privileged product path caused ART and class-loading problems. The Store kept stopping with a `ClassNotFoundException` for `ClassicApplication`. Using that APK as the system base while running the normal updated Store from `/data/app` avoided the failure. Install the same APK as an update right after the first reboot with the module, before you open the Store:

```bash
adb install -r PlayStore.apk
```

### 6. Verify privileged Play Store state

Run these checks:

```bash
adb shell pm path com.android.vending
adb shell dumpsys package com.android.vending | grep -E 'codePath=|versionName=|pkgFlags='
adb shell dumpsys package com.android.vending | grep -E \
  'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:|GET_ROLE_HOLDERS:'
```

On the reference setup, the privileged Store had these grants:

```text
INSTALL_PACKAGES
GET_ACCOUNTS_PRIVILEGED
WRITE_SECURE_SETTINGS
MANAGE_USERS
FOREGROUND_SERVICE_SYSTEM_EXEMPTED
GET_ROLE_HOLDERS
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

The reference device also returned `MEETS_STRONG_INTEGRITY`.

## Android 16 Play Store background-service issue

On the tested Android 16 ROM, the Store authenticated and opened, but downloads initially stayed on **Pending**. Logcat showed `com.android.vending:background` crashing when `DownloadService` tried to start a `systemExempted` foreground service.

This command fixed normal Play Store downloads on that setup:

```bash
adb shell su -c 'dumpsys deviceidle whitelist +com.android.vending'
```

`playstore-base` applies the command automatically after boot, except while the privacy filter is enabled. The base module README includes the service and verification details.

The optional privacy filter disables `DownloadService` and removes this whitelist entry because that configuration intentionally blocks normal Store downloads.

## Included modules

Each [release](https://github.com/D3SOX/microg-play-store-workarounds/releases) has three assets:

| Asset | Module |
|---|---|
| `playstore_base_module_source.zip` | `playstore-base` source. Build the installable module yourself with your own Play Store APK. |
| `playstore_xray_privacy_filter-vX-arm64.zip` | `playstore-xray-privacy-filter`, ready to flash. |
| `play_provenance_repair-vX.zip` | `play-provenance-repair`, ready to flash. |

### `playstore-base`

`playstore-base` is a source-only module builder. It replaces the ROM's privileged FakeStore base with a user-supplied official Play Store APK. It also applies the tested Android 16 device-idle workaround for normal Store downloads.

Its README records the tested migration, including the exact Store APK, signing hash, privilege failures before the fix, final package layout, relevant services, and final Integrity result.

See [modules/playstore-base/README.md](modules/playstore-base/README.md).

### `playstore-xray-privacy-filter`

`playstore-xray-privacy-filter` is an optional ARM64 per-UID default-deny network filter for the real Play Store. It does not use Android `VpnService`.

Its README records the tested four-domain allowlist, blocked Store and CDN examples, firewall design, Xray binary source, download URL and hash, expected device-idle state, and uninstall behavior.

See [modules/playstore-xray-privacy-filter/README.md](modules/playstore-xray-privacy-filter/README.md).

### `play-provenance-repair`

`play-provenance-repair` is a WebUI and CLI helper for APatch and KernelSU. It is for legitimately owned apps that were installed through Aurora, ADB, a restore tool, or another installer and still expect Google Play as their installer or initiator.

Its README documents three observed failure classes: an installer-only mismatch, an incorrect initiating package, and an app-specific local warning that remains after the real Play license check succeeds.

The helper does not create purchase entitlements or bypass failed license checks.

See [modules/play-provenance-repair/README.md](modules/play-provenance-repair/README.md).

## Optional privacy hardening

On the reference setup, the Play Store UID could reach only these observed Integrity-related hosts, and the Integrity result above still passed:

```text
play.googleapis.com
play-fe.googleapis.com
gmscompliance-pa.googleapis.com
remoteprovisioning.googleapis.com
```

This allowlist comes from observed behavior and can become stale. With the filter enabled, Play Store downloads stall at 0 bytes, but Store pages still load app details through these hosts. The privacy module README documents the full routing policy and its limits.

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

### Every verdict is `UNEVALUATED`

Check the keybox first. On the tested device, a revoked keybox produced `UNEVALUATED` for app recognition, device integrity, and licensing. Google publishes its attestation revocation list at <https://android.googleapis.com/attestation/status>. If a certificate serial from `keybox.xml` appears there, fetch a new keybox.

An expired certificate also breaks the chain, and the revocation list does not show it. Check the expiry date with the command in [Keybox](#keybox).

### Only `MEETS_BASIC_INTEGRITY`

Treat this as an attestation or root-hiding problem first, not a Play Store problem. Check the current Play Integrity Fork and keystore module configuration, the Zygisk implementation, root hiding, and the upstream recommendations for your Android version.

Verify that microG's **Block hardware attestation** option is off. Check that the keystore module targets both `com.google.android.gms` and `com.android.vending`, and that its attested patch levels match the properties exposed to those processes. Installing Play Integrity Fork without an active configuration does not configure fingerprint spoofing.

A valid certificate chain and an unrevoked keybox do not prove that Google will accept the attestation. A BASIC-only verdict alone also does not identify the keybox as the cause. Compare configurations or keystore modules with the same key before concluding that the key needs replacing. Run only one keystore module at a time. On the reference device, Tricky Store OSS with the `Yurikey68` keybox returned only `MEETS_BASIC_INTEGRITY`. OhMyKeymint with the same keybox and a current Play Integrity Fork profile passed all three device verdicts. Tricky Store OSS was not retested with that profile.

### Boot loop after installing playstore-base

If the boot animation never finishes, check whether ADB still works. On the tested device, ADB and root were available during the loop. Look for this system_server crash:

```bash
adb logcat -d -b crash | grep 'not in privileged permission allowlist'
```

The message names the permission the Play Store requested. Disable the module and reboot:

```bash
adb shell su -c 'touch /data/adb/modules/playstore_base/disable'
adb reboot
```

Then add the permission to `system/product/etc/permissions/privapp-permissions-com.android.vending.xml` in the module source, rebuild the module, and install it again.

### Play Store keeps stopping after the first reboot

The Store is running from the product path without a `/data/app` update. Install the same APK as an update, as described in [step 5](#5-keep-the-active-play-store-update-on-dataapp).

### `MEETS_DEVICE_INTEGRITY` works, but an app is `UNRECOGNIZED_VERSION` or `UNLICENSED`

This points to app recognition or install provenance. Install the app through the real Play Store and verify that the Store runs as the privileged `com.android.vending` base.

### Play Store opens but downloads stay pending or its background process crashes

Check logcat for `com.android.vending:background` and `DownloadService`. On the tested Android 16 ROM, the Store needed the device-idle whitelist for its `systemExempted` foreground service. `playstore-base` applies the workaround automatically.

If `playstore-xray-privacy-filter` is enabled, downloads fail by design because it disables `DownloadService`. If downloads still fail after you uninstall it, see its [uninstall notes](modules/playstore-xray-privacy-filter/README.md#uninstall).

### Integrity fails only while the privacy filter is enabled

Check `/data/adb/playstore_xray_privacy_filter/boot.log`. The privacy module README lists the [error messages](modules/playstore-xray-privacy-filter/README.md#troubleshooting). If the log shows no errors, Google may now require a host that is not on the allowlist.

### An owned app still says it was not installed by Play

Inspect both `installerPackageName` and `initiatingPackageName`. If the app is legitimately owned and the real Play Store recognizes the entitlement, use the provenance helper only for that app.

## Scope and cautions

- Root access is required.
- The base module assumes FakeStore occupies `/product/priv-app/FakeStore/FakeStore.apk` and that the ROM allowlists it in `/product/etc/permissions/privapp-permissions-com.android.vending.xml`.
- Moving from differently signed FakeStore to Google's Play Store may require ROM-specific or root-specific signature compatibility handling.
- Play Integrity behavior changes on Google's servers, so a configuration that works now may stop working later.
- Do not use private keyboxes, fingerprints, or attestation material from unknown sources. Treat a public keybox from Yurikey Manager as temporary, because Google revokes shared keyboxes.
- Back up important data before changing privileged system-package layout or app installer provenance.
