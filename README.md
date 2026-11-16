# microG Play Store workarounds

A tested setup for passing Play Integrity on Android 13+ with microG as the Play Services implementation. It works on ROMs that ship microG, such as LineageOS for microG, and on ROMs where you install microG yourself, such as official LineageOS. The reference device passes `MEETS_STRONG_INTEGRITY`. This repository has the guide and four root modules for the Play Store side of the setup.

> [!IMPORTANT]
> Play Integrity verdicts come from Google's servers. Google changes attestation rules and revokes keys over time, so this setup can stop working, and it may behave differently on another ROM or device.

## Modules

| Module | What it does | Needed? |
|---|---|---|
| [`playstore-base`](modules/playstore-base/README.md) | Makes the real Google Play Store the privileged system app, in place of microG's FakeStore if the ROM has it. Optionally makes a user-installed microG GmsCore a privileged app too. | Yes |
| [`playstore-xray-privacy-filter`](modules/playstore-xray-privacy-filter/README.md) | Blocks the Play Store's downloads and most of its traffic, but keeps Play Integrity working. | Optional |
| [`play-provenance-repair`](modules/play-provenance-repair/README.md) | Fixes owned apps that still say they were not installed from Google Play. | Optional |
| [`omk-keybox-updater`](modules/omk-keybox-updater/README.md) | Installs the newest valid public keybox into OhMyKeymint when you tap its Action button. | Optional |

Each [release](https://github.com/D3SOX/microg-play-store-workarounds/releases) has the privacy filter, provenance repair, and keybox updater as ready-to-flash ZIPs. `playstore-base` ships as source, because you build it with your own Play Store APK. Google's APK is proprietary, so this repository does not include it.

These modules handle the Play Store. The device verdicts come from the root, Zygisk, and attestation modules in steps 2 and 3.

## Supported setups

The guide works with two ways of getting microG onto a ROM. The setup steps say where they differ.

| | ROM ships microG | You install microG yourself |
|---|---|---|
| Example | LineageOS for microG | Official LineageOS |
| microG GmsCore | Privileged system app from the ROM | Normal app. `playstore-base` adds a privileged system copy. |
| `com.android.vending` before setup | FakeStore, a system app from the ROM | microG Companion as a normal app, or nothing |
| What `playstore-base` does | Replaces FakeStore with the Play Store | You uninstall Companion, and the module adds the Play Store as a new system app |
| Signature spoofing | Built into the ROM | Built into official LineageOS, for microG-signed GmsCore only |
| Signing-key workaround such as CorePatch | May be needed, because FakeStore and the Play Store have different keys | Not needed, because no app is replaced by one with a different key |

GmsCore has to be a privileged app because Play Integrity runs in microG's DroidGuard process, which belongs to GmsCore. As a normal app, DroidGuard runs in a restricted SELinux domain, and the reference device got only `MEETS_BASIC_INTEGRITY`. See [microG as a privileged app](modules/playstore-base/README.md#microg-as-a-privileged-app).

## Tested setups

Both setups ran on the same Pixel 8 Pro with these components:

```text
APatch, with Hybrid Mount as the metamodule
ReZygisk and Zygisk Assistant
Play Integrity Fork v19 with a current Pixel 8 Pro profile
OhMyKeymint 1.2.6
Public Yurikey68 keybox
Google Play Store 54.1.11-34
microG 0.3.18
```

Other root managers, Zygisk implementations, and keystore modules may work. Use current releases and follow their upstream documentation rather than copying this list.

### Official LineageOS

Tested on 2026-11-16 with Android 17 (SDK 37), official LineageOS 24, and microG installed as normal apps. `playstore-base` 1.4 was built with the Play Store and GmsCore APKs. CorePatch was still installed in Vector, but nothing in this setup needs it.

[Play Integrity API Checker](https://play.google.com/store/apps/details?id=gr.nikolasspyr.integritycheck) returned `MEETS_BASIC_INTEGRITY`, `MEETS_DEVICE_INTEGRITY`, and `MEETS_STRONG_INTEGRITY` with the privacy filter enabled. Before GmsCore was a privileged app, it returned only `MEETS_BASIC_INTEGRITY`. The app and licensing verdicts were not recorded.

### LineageOS for microG

Tested on 2026-11-12 with Android 16 (SDK 36) and LineageOS for microG 23.2. `playstore-base` 1.3 replaced FakeStore, with CorePatch in Vector for the signing-key change. The checker returned these verdicts with the privacy filter enabled:

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

## Setup

Do the steps in order. Get each one working before you start the next, so you only debug one thing at a time.

Commands that start with `adb` run on your computer and need [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools). They work as written in PowerShell, Command Prompt, and Linux or macOS shells. On Windows, run them from the platform-tools folder (type `.\adb` in PowerShell) or add that folder to your `PATH`. Commands that start with `su -c` run on the phone, in a terminal app or after `adb shell`.

### Set up with a coding agent

A coding agent with shell access, such as Claude Code or Codex, can do most of these steps over ADB. Enable USB debugging, grant root to the ADB shell in your root manager, connect the phone, and paste this prompt into the agent:

```text
Clone https://github.com/D3SOX/microg-play-store-workarounds and follow AGENT_SETUP.md to help me pass Play Integrity on my phone.
```

[`AGENT_SETUP.md`](AGENT_SETUP.md) tells the agent to survey the phone first and to ask before each change. Read each command before you approve it.

### 1. Get microG working

If your ROM ships microG, it is already installed.

If you install microG yourself, download microG Services, which is GmsCore, and microG Services Framework Proxy from <https://microg.org/download.html> and install them as normal apps. The Services Framework Proxy targets Android 6. If Android refuses to install it because its target SDK is too low, add `--bypass-low-target-sdk-block`. The reference device on Android 17 used the flag:

```bash
adb install GmsCore.apk
adb install --bypass-low-target-sdk-block GsfProxy.apk
```

microG Companion is optional here, because step 4 puts the Play Store in its place. The reference device had Companion installed and removed it in step 4. Your ROM must support signature spoofing for microG. Official LineageOS does.

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

Get an official Google-signed standalone Play Store APK. The [module README](modules/playstore-base/README.md#choose-a-play-store-apk) lists the tested build and how to verify the signer.

#### Build the module

If you installed microG yourself, the module also needs your GmsCore APK. Check where Android has GmsCore:

```bash
adb shell "dumpsys package com.google.android.gms | grep codePath="
```

- Only a `/data/app/...` path means GmsCore is a normal app. Build with its APK.
- A path ending in `/PrebuiltGmsCore` means an earlier build of this module added it. Build with its APK again, or the new build removes GmsCore's privileged copy.
- Any other `priv-app` path, such as `/product/priv-app/GmsCore` on LineageOS for microG, means the ROM ships GmsCore. Leave out the APK.

To build with the APK, copy it to your computer. The first command prints its path. Pass that path, without the `package:` prefix, to the second:

```bash
adb shell pm path com.google.android.gms
adb pull /data/app/.../base.apk GmsCore.apk
```

Use the APK that is installed, not a newer download, so that the module's copy matches your installed GmsCore. Then build the module with both APKs:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk /path/to/GmsCore.apk
```

If the ROM ships GmsCore, leave out the GmsCore APK:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

On Windows, see [Build on Windows](modules/playstore-base/README.md#build-on-windows).

#### Remove microG Companion

Skip this if your ROM ships FakeStore, or if you never installed Companion. Check what `com.android.vending` is now:

```bash
adb shell pm list packages -3 com.android.vending
```

If this prints the package, check its version:

```bash
adb shell "dumpsys package com.android.vending | grep versionName"
```

A microG version such as `0.3.18.40226` means it is microG Companion installed as a normal app. Companion has the Play Store's package name but a different signing key, so the Play Store cannot replace it. Uninstall it. If the version is a Play Store version such as `54.1.11-34`, the real Play Store is already installed as a normal app, and you can keep it.

When you uninstall Companion, Android clears the installer of every app that lists it as its installer. Those apps can no longer see the Play Store until you repair them. On the reference device, a restore had recorded the Play Store as installer for 50 apps. List them before you uninstall:

```bash
adb shell "pm list packages -3 -i | grep installer=com.android.vending"
adb uninstall com.android.vending
```

After step 5, repair each listed app with [`play-provenance-repair`](modules/play-provenance-repair/README.md), or reinstall it from the Play Store.

#### Flash and install the update

Flash `playstore_base.zip` in your root manager. The installer prints whether the ROM has FakeStore and whether it adds GmsCore. Reboot. Then install the same Play Store APK as a normal update, and reboot again before you open the Play Store:

```bash
adb install -r PlayStore.apk
adb reboot
```

The Play Store needs both copies. The module's copy is the privileged system app. The update is the copy that actually runs, because the Store crashes when it runs from the system copy alone. GmsCore needs no extra step, because your installed GmsCore becomes the update of the module's copy.

On LineageOS for microG, if the old FakeStore update is still installed after the first reboot, remove it before you install the Play Store update. See the [module README](modules/playstore-base/README.md#rom-with-fakestore).

Open the Play Store and sign in.

### 5. Check the Play Store

```bash
adb shell pm path com.android.vending
adb shell "dumpsys package com.android.vending | grep -E 'INSTALL_PACKAGES:|GET_ACCOUNTS_PRIVILEGED:|WRITE_SECURE_SETTINGS:|MANAGE_USERS:|FOREGROUND_SERVICE_SYSTEM_EXEMPTED:|GET_ROLE_HOLDERS:'"
```

The path should point to `/data/app/...`, and every listed permission should show `granted=true`.

If the module added GmsCore, check that its processes run in the `gmscore_app` SELinux domain, not `untrusted_app`:

```bash
adb shell "ps -AZ | grep com.google.android.gms"
```

### 6. Test Play Integrity

Install a checker such as Play Integrity API Checker through the Play Store, not from another source. Otherwise an install-source problem can look like a device problem. If the checker reports that the Play Store was not found, see [the troubleshooting entry](#the-checker-reports-play-store-not-found).

`deviceRecognitionVerdict` should include `MEETS_BASIC_INTEGRITY` and `MEETS_DEVICE_INTEGRITY`. `appRecognitionVerdict` and `appLicensingVerdict` describe the app and your account. They are separate from the device verdicts.

### 7. Optional modules

- Install [`playstore-xray-privacy-filter`](modules/playstore-xray-privacy-filter/README.md) if you want to keep the Play Store from downloading apps and from reaching most Google hosts. Play Store pages still load with it enabled.
- Use [`play-provenance-repair`](modules/play-provenance-repair/README.md) for apps you own that still complain they were not installed from Google Play.

## Keybox

`MEETS_DEVICE_INTEGRITY` and `MEETS_STRONG_INTEGRITY` need a keybox that Google still trusts. A keybox stops working when:

- Google revokes it and lists it at <https://android.googleapis.com/attestation/status>,
- one of its certificates expires, or
- Google stops trusting it without listing it.

The reference device used the public `Yurikey68` keybox from [Yurikey](https://github.com/Yurii0307/yurikey). OhMyKeymint reads its keybox from `/data/misc/keystore/omk/keybox.xml` and reloads it automatically when the file changes, without a reboot. To replace it:

- Tap the Action button of [`omk-keybox-updater`](modules/omk-keybox-updater/README.md). It downloads the public keyboxes from Yurikey and Integrity-Box, checks them, and installs the one that expires last.
- Or copy a keybox yourself. Write it under a temporary name in the same folder, give it the `keystore` owner, `0600` mode, and the old file's SELinux label, then rename it to `keybox.xml` in one step.

Every keybox change makes OhMyKeymint delete the app keys tied to the old keybox, so some apps may ask you to sign in again.

Public keyboxes are leaked keys that many devices share, so expect to replace them. The November 2026 Yurikey keyboxes also had short-lived certificates. `Yurikey67` expired on the day it was published, and `Yurikey68` was valid for 12 days. When the verdict drops, check the expiry date of the first certificate:

```bash
adb shell "su -c 'sed -n /BEGIN.CERTIFICATE/,/END.CERTIFICATE/s/^[[:space:]]*//p /data/misc/keystore/omk/keybox.xml'" | openssl x509 -noout -subject -enddate
```

This copies only the certificates off the phone, not the private key. On Windows, `openssl` comes with Git for Windows. Run the command in Git Bash, or add Git's `usr\bin` folder to your `PATH`. Without `openssl`, tap the Action button of `omk-keybox-updater`. It prints when the current keybox expires before it looks for a newer one.

Never use keyboxes, fingerprints, or other attestation material from sources you do not trust.

## Troubleshooting

### Every verdict is `UNEVALUATED`

Check the keybox. A revoked keybox produced `UNEVALUATED` for every verdict on the reference device. Compare the certificate serials in `keybox.xml` with Google's revocation list, and check the expiry date as shown in [Keybox](#keybox).

### Only `MEETS_BASIC_INTEGRITY`

This is an attestation, root-hiding, or GmsCore problem, not a Play Store problem. Check that:

- GmsCore runs as a privileged app, as described in [step 4](#4-install-playstore-base),
- microG's **Block hardware attestation** option is off,
- Play Integrity Fork has an active profile,
- the keystore module targets `com.google.android.gms` and `com.android.vending`, and its patch levels match the Play Integrity Fork profile,
- only one keystore module is enabled.

A valid, unrevoked keybox does not prove that Google accepts it, and a BASIC-only verdict does not prove the keybox is the problem. Before you replace the key, try other configurations with the same key. In November 2026, Tricky Store OSS with `Yurikey68` returned only BASIC. OhMyKeymint with the same keybox and a current Play Integrity Fork profile passed all three verdicts. Tricky Store OSS was not retested with that profile.

### Boot loop after installing `playstore-base`

Android refuses to boot when the Play Store or GmsCore requests a privileged permission that no allowlist file grants. ADB and root still worked during the loop on the reference device. Find the permission:

```bash
adb shell "logcat -d -b crash | grep 'not in privileged permission allowlist'"
```

Disable the module and reboot:

```bash
adb shell "su -c 'touch /data/adb/modules/playstore_base/disable'"
adb reboot
```

Add the permission to the module's allowlist, rebuild, and install it again. See [Privileged permission allowlist](modules/playstore-base/README.md#privileged-permission-allowlist).

### The checker reports "Play Store not found"

Android 11 and later hide most apps from each other, but an app can always see its installer. When you uninstall microG Companion, Android clears the installer of the apps it installed, so they no longer see the Play Store. Logcat shows `PhoneskyVerificationUtils : Play Store package is not found.` Repair the app with [`play-provenance-repair`](modules/play-provenance-repair/README.md), or reinstall it from the Play Store.

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
- `playstore-base` was tested on LineageOS for microG, which ships FakeStore at `/product/priv-app/FakeStore/FakeStore.apk`, and on official LineageOS, which has no FakeStore. It relies on LineageOS's Google allowlist for most privileged permissions. On another ROM, a missing allowlist entry can cause a [boot loop](#boot-loop-after-installing-playstore-base).
- On a ROM without FakeStore, the root manager or its metamodule must mount the module's `system/` folder, because the module adds new files.
- On a ROM with FakeStore, FakeStore and Google's Play Store have different signing keys. Your ROM and root setup may need a signature-compatibility workaround such as CorePatch.
- Back up important data before you change system apps or install sources.

## Earlier setup

The September 2026 setup used Tricky Store OSS with Yurikey Manager and Play Store 53.0.27-31, and passed `MEETS_DEVICE_INTEGRITY`. Tricky Store OSS reads its keybox from `/data/adb/tricky_store/keybox.xml` and reloads it without a reboot. The Yurikey Manager action overwrites that file, `target.txt`, and `security_patch.txt`, so back up `/data/adb/tricky_store/` first if you maintain them yourself.
