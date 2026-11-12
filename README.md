# microG Play Store workarounds

A tested setup for passing Play Integrity on Android 13+ microG ROMs while keeping microG as the Play Services implementation. The reference device passes `MEETS_STRONG_INTEGRITY`. This repository has the guide and three root modules for the Play Store side of the setup.

> [!IMPORTANT]
> Play Integrity verdicts come from Google's servers. Google changes attestation rules and revokes keys over time, so this setup can stop working, and it may behave differently on another ROM or device.

## Modules

| Module | What it does | Needed? |
|---|---|---|
| [`playstore-base`](modules/playstore-base/README.md) | Replaces microG's FakeStore with the real Google Play Store as the privileged system app. | Yes |
| [`playstore-xray-privacy-filter`](modules/playstore-xray-privacy-filter/README.md) | Blocks the Play Store's downloads and most of its traffic, but keeps Play Integrity working. | Optional |
| [`play-provenance-repair`](modules/play-provenance-repair/README.md) | Fixes owned apps that still say they were not installed from Google Play. | Optional |

Each [release](https://github.com/D3SOX/microg-play-store-workarounds/releases) has the privacy filter and provenance repair as ready-to-flash ZIPs. `playstore-base` ships as source, because you build it with your own Play Store APK. Google's APK is proprietary, so this repository does not include it.

These modules handle the Play Store. The device verdicts come from the root, Zygisk, and attestation modules in steps 2 and 3.

## Tested setup

Last tested on 2026-11-12:

```text
Pixel 8 Pro, Android 16 (SDK 36)
LineageOS for microG 23.2, microG 0.3.18
APatch, with Hybrid Mount as the metamodule
ReZygisk and Zygisk Assistant
Play Integrity Fork v19 with a current Pixel 8 Pro profile
OhMyKeymint 1.2.6
Public Yurikey68 keybox
Google Play Store 54.1.11-34
CorePatch in Vector (signature compatibility for the FakeStore swap)
```

[Play Integrity API Checker](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck), installed through the Play Store, returned these verdicts with the privacy filter enabled:

```text
deviceRecognitionVerdict  MEETS_BASIC_INTEGRITY, MEETS_DEVICE_INTEGRITY, MEETS_STRONG_INTEGRITY
appRecognitionVerdict     PLAY_RECOGNIZED
appLicensingVerdict       LICENSED
playProtectVerdict        NO_ISSUES
```

<details>
<summary>Full response</summary>

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

</details>

Other root managers, Zygisk implementations, and keystore modules may work. Use current releases and follow their upstream documentation rather than copying this list.

## Setup

Do the steps in order. Get each one working before you start the next, so you only debug one thing at a time.

### 1. Get microG working

Check device registration, cloud messaging, signature spoofing if your ROM needs it, and normal app use.

Then open microG Settings, go to **Device Attestation > Advanced**, and turn off **Block hardware attestation**. Some microG versions call this section **Google SafetyNet**. The keystore module in step 3 answers hardware attestation requests, and the reference device passed with this option off.

### 2. Install Zygisk and root hiding

On APatch or KernelSU, install a Zygisk implementation that your integrity module supports, such as [ReZygisk](https://github.com/PerformanC/ReZygisk). The reference device also used [Zygisk Assistant](https://github.com/snake-4/Zygisk-Assistant). Follow its instructions for your root manager, and turn on the manager's unmount option for apps that should not see root.

### 3. Set up attestation

On Android 13+, `MEETS_DEVICE_INTEGRITY` needs three things:

1. [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork) with an active profile. Installing the module does not configure it. Run its `autopif4.sh --strong --match` to generate a current profile in `custom.pif.prop`. The tested profile set `spoofProvider=0` and `spoofVendingSdk=0` and had its `ro.build.version.security_patch` line uncommented. Each profile records an estimated expiry date (2026-12-16 for the tested one). Generate a new one after that date.
2. A keystore module. The reference device used [OhMyKeymint](https://github.com/qwq233/OhMyKeymint) [1.2.6-9069c6c](https://github.com/qwq233/OhMyKeymint/releases/tag/1.2.6-9069c6c). Follow its [configuration guide](https://github.com/qwq233/OhMyKeymint/blob/master/docs/CONFIGURATION.md), then check two settings:
   - `/data/misc/keystore/omk/injector.toml` must target `com.google.android.gms`, `com.google.android.gsf`, and `com.android.vending`.
   - `os_patchlevel`, `vendor_patchlevel`, and `boot_patchlevel` in `/data/misc/keystore/omk/config.toml` must match the patch level of your Play Integrity Fork profile (`2026-11-05` in the tested profile). Without the profile and matching patch levels, OhMyKeymint returned only `MEETS_BASIC_INTEGRITY`.

   Run only one keystore module at a time. Disable Tricky Store OSS before you enable OhMyKeymint.
3. A working keybox. See [Keybox](#keybox).

Do not copy fingerprints, patch dates, or keys from old guides. Inconsistent device properties can make attestation fail.

### 4. Install `playstore-base`

Get an official Google-signed standalone Play Store APK. The [module README](modules/playstore-base/README.md#choose-a-play-store-apk) lists the tested build and how to verify the signer. Then build the module:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

Flash the resulting `playstore_base.zip` and reboot. Before you open the Play Store, install the same APK as a normal update and reboot again:

```bash
adb install -r PlayStore.apk
adb reboot
```

The Play Store needs both copies. The module makes it the privileged system app. The update is the copy that actually runs, because the Store crashes when it runs from the system copy alone.

Open the Play Store and sign in.

### 5. Check the Play Store

```bash
adb shell pm path com.android.vending
adb shell dumpsys package com.android.vending | grep -E \
  'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:|GET_ROLE_HOLDERS:'
```

The path should point to `/data/app/...`, and every listed permission should show `granted=true`.

### 6. Test Play Integrity

Install a checker such as Play Integrity API Checker through the Play Store, not from another source. Otherwise an install-source problem can look like a device problem.

`deviceRecognitionVerdict` should include `MEETS_BASIC_INTEGRITY` and `MEETS_DEVICE_INTEGRITY`. `appRecognitionVerdict` and `appLicensingVerdict` describe the app and your account. They are separate from the device verdicts.

### 7. Optional modules

- Install [`playstore-xray-privacy-filter`](modules/playstore-xray-privacy-filter/README.md) if you want to keep the Play Store from downloading apps and from reaching most Google hosts. Play Store pages still load with it enabled.
- Use [`play-provenance-repair`](modules/play-provenance-repair/README.md) for apps you own that still complain they were not installed from Google Play.

## Keybox

`MEETS_DEVICE_INTEGRITY` and `MEETS_STRONG_INTEGRITY` need a keybox that Google still trusts. A keybox stops working when:

- Google revokes it and lists it at <https://android.googleapis.com/attestation/status>,
- one of its certificates expires, or
- Google stops trusting it without listing it.

The reference device used the public `Yurikey68` keybox. [Yurikey Manager](https://github.com/Yurii0307/yurikey) downloads its keyboxes from the Yurikey repository to Tricky Store's path, `/data/adb/tricky_store/keybox.xml`. OhMyKeymint does not need Yurikey Manager. Copy the keybox to `/data/misc/keystore/omk/keybox.xml` yourself, keep its `keystore` owner and `0600` mode, and reboot.

Public keyboxes are leaked keys that many devices share, so expect to replace them. The November 2026 Yurikey keyboxes also had short-lived certificates. `Yurikey67` expired on the day it was published, and `Yurikey68` was valid for 12 days. When the verdict drops, check the expiry date of the first certificate:

```bash
adb shell su -c "sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' /data/misc/keystore/omk/keybox.xml" \
  | sed 's/^[[:space:]]*//' | openssl x509 -noout -subject -enddate
```

This copies only the certificates off the phone, not the private key.

Never use keyboxes, fingerprints, or other attestation material from sources you do not trust.

## Troubleshooting

### Every verdict is `UNEVALUATED`

Check the keybox. A revoked keybox produced `UNEVALUATED` for every verdict on the reference device. Compare the certificate serials in `keybox.xml` with Google's revocation list, and check the expiry date as shown in [Keybox](#keybox).

### Only `MEETS_BASIC_INTEGRITY`

This is an attestation or root-hiding problem, not a Play Store problem. Check that:

- microG's **Block hardware attestation** option is off,
- Play Integrity Fork has an active profile,
- the keystore module targets `com.google.android.gms` and `com.android.vending`, and its patch levels match the Play Integrity Fork profile,
- only one keystore module is enabled.

A valid, unrevoked keybox does not prove that Google accepts it, and a BASIC-only verdict does not prove the keybox is the problem. Before you replace the key, try other configurations with the same key. In November 2026, Tricky Store OSS with `Yurikey68` returned only BASIC. OhMyKeymint with the same keybox and a current Play Integrity Fork profile passed all three verdicts. Tricky Store OSS was not retested with that profile.

### Boot loop after installing `playstore-base`

Android refuses to boot when the Play Store requests a privileged permission that the ROM does not allowlist. ADB and root still worked during the loop on the reference device. Find the permission:

```bash
adb logcat -d -b crash | grep 'not in privileged permission allowlist'
```

Disable the module and reboot:

```bash
adb shell su -c 'touch /data/adb/modules/playstore_base/disable'
adb reboot
```

Add the permission to the module's allowlist, rebuild, and install it again. See [Privileged permission allowlist](modules/playstore-base/README.md#privileged-permission-allowlist).

### "Google Play Store keeps stopping" after the first reboot

The Store is running from the system copy without its `/data/app` update. Install the same APK with `adb install -r`, as in [step 4](#4-install-playstore-base).

### Downloads stay on Pending

If the privacy filter is enabled, this is intended. Otherwise see [Downloads stay pending](modules/playstore-base/README.md#downloads-stay-pending).

### An app is `UNRECOGNIZED_VERSION` or `UNLICENSED`

The device verdict is fine, but the app's install source is not. Install the app through the Play Store. If that is not possible, use [`play-provenance-repair`](modules/play-provenance-repair/README.md) on that app.

### Integrity fails only while the privacy filter is enabled

See the filter's [troubleshooting](modules/playstore-xray-privacy-filter/README.md#troubleshooting).

## Cautions

- Root access is required.
- `playstore-base` expects FakeStore at `/product/priv-app/FakeStore/FakeStore.apk` and its allowlist at `/product/etc/permissions/privapp-permissions-com.android.vending.xml`, as on LineageOS for microG.
- FakeStore and Google's Play Store have different signing keys. Your ROM and root setup may need a signature-compatibility workaround such as CorePatch.
- Back up important data before you change system apps or install sources.

## Earlier setup

The September 2026 setup used Tricky Store OSS with Yurikey Manager and Play Store 53.0.27-31, and passed `MEETS_DEVICE_INTEGRITY`. Tricky Store OSS reads its keybox from `/data/adb/tricky_store/keybox.xml` and reloads it without a reboot. The Yurikey Manager action overwrites that file, `target.txt`, and `security_patch.txt`, so back up `/data/adb/tricky_store/` first if you maintain them yourself.
