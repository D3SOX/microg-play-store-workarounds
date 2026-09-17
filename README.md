# microG Play Store Workarounds

Rooted Android custom-ROM utilities developed while debugging ChatGPT Android Remote Control enrollment on a Pixel 8 Pro running Android 16 LineageOS for microG.

**Author:** D3SOX (assisted by GPT)

> [!IMPORTANT]
> These are empirical rooted/custom-ROM workarounds. They are **not** a fix for the underlying Play Integrity / device-certification policy and are not intended for locked official GrapheneOS or other unrooted systems.

## Background

On the tested LineageOS-for-microG device, ChatGPT Android Remote Control enrollment failed while the device/app was outside the recognized Google Play / Play Integrity path. After replacing microG FakeStore with the official Play Store as the privileged factory base and reaching the following state, Remote Control pairing worked end-to-end:

```text
PLAY_RECOGNIZED
MEETS_BASIC_INTEGRITY
MEETS_DEVICE_INTEGRITY
LICENSED
```

This repository contains the three utilities produced while debugging that setup.

## Modules

### 1. Google Play Store System Base

`modules/playstore-base/`

A **source-only** APatch module template that replaces the ROM's privileged FakeStore base with a user-supplied official Google-signed Play Store APK before PackageManager scans system packages.

Why source-only: Google's Play Store APK is proprietary and is intentionally not redistributed here.

Build your personal module with:

```bash
cd modules/playstore-base
./build-module.sh /path/to/PlayStore.apk
```

See [modules/playstore-base/README.md](modules/playstore-base/README.md).

### 2. Play Store Xray Privacy Filter

`modules/playstore-xray-privacy-filter/`

ARM64 root module that keeps the official Play Store installed for the tested Integrity flow while applying a per-UID, default-deny network policy to the main-user Play Store UID.

Current allowlist:

```text
play.googleapis.com
play-fe.googleapis.com
gmscompliance-pa.googleapis.com
remoteprovisioning.googleapis.com
```

The module also rejects Play Store QUIC/UDP 443 and IPv6 bypass paths, redirects direct UDP/53 through its local Xray listener, disables only Play Store `DownloadService`, and removes Play Store from the device-idle whitelist after boot. Aurora and unrelated UIDs are unaffected.

The Xray executable is not redistributed in the module ZIP. The installer reuses an existing binary or downloads the official Xray-core v26.9.9 Android ARM64 archive and verifies its published SHA-256 before extraction.

See [modules/playstore-xray-privacy-filter/README.md](modules/playstore-xray-privacy-filter/README.md).

### 3. Play Install Provenance Repair

`modules/play-provenance-repair/`

APatch WebUI/CLI tool for legitimately owned apps that still complain about not being installed through Google Play after migration or restore.

It can inspect and repair Android's installer/initiator provenance, including an in-place reinstall using the existing APK/splits through a Play-owned PackageInstaller session when `set-installer` alone is insufficient. It also contains a guarded detector for the specific stale PAIRIP warning state observed during testing.

See [modules/play-provenance-repair/README.md](modules/play-provenance-repair/README.md).

## Tested environment

The primary test device was:

```text
Pixel 8 Pro
Android 16 / SDK 36
LineageOS for microG
APatch + ReZygisk
```

The Integrity result also depended on the pre-existing attestation/root-hiding setup. These modules alone do not promise any particular Play Integrity verdict.

The official Play Store was used as a privileged factory base with the active update running from `/data/app`. The tested active Store build was `53.0.27-34 [0] [PR] 973951861` after update.

## Play Store base architecture

```text
/product/priv-app/FakeStore/FakeStore.apk
    -> systemlessly replaced with official Play Store APK
       so PackageManager sees a privileged Google Play base

/data/app/.../com.android.vending
    -> active official Play Store update
```

Keeping execution on the `/data/app` update avoided ART/class-loading problems encountered when the downloaded Store APK was executed directly from the privileged product path.

## Privacy-filter architecture

```text
com.android.vending (main-user UID)
        |
        +-- IPv6 ------------------------------> REJECT
        +-- UDP/443 QUIC ----------------------> REJECT
        +-- TCP -> local Xray TLS/SNI routing
                     |
                     +-- tested Integrity hosts -> DIRECT
                     +-- everything else -------> BLACKHOLE

other application UIDs
        -> normal Android networking
```

The allowlist is empirical. Google can change endpoints, protocols, or TLS behavior at any time. Re-test after major Android, Play Store, microG, or Integrity changes.

## Build release archives locally

```bash
./scripts/build-release.sh
```

Output is written to `dist/` with `SHA256SUMS`.

## Safety / scope

- Root access is required.
- The base module is specific to a ROM layout where FakeStore occupies the privileged `com.android.vending` base path.
- A differently signed transition from FakeStore to Google's Play Store may require additional signature-compatibility handling on the user's device.
- The provenance repair tool does not grant paid entitlements and should only be used for apps the user legitimately owns.
- The privacy filter intentionally breaks most normal Play Store networking and Store browsing/download behavior.
- Back up important data before changing system package provenance or privileged package layout.

## Related issue

This work was produced while investigating:

- [OpenAI Codex issue #38128](https://github.com/openai/codex/issues/38128): Remote Control blocks ChatGPT Android enrollment on official unrooted GrapheneOS

The rooted/custom-ROM workaround here should not be interpreted as resolving that issue for official GrapheneOS. It only provides additional evidence about the role of the Google Play / Play Integrity path and a reproducible workaround for one rooted LineageOS-for-microG setup.

## Credits

Maintained by **D3SOX** (assisted by GPT).

Xray-core is a separate upstream project licensed under MPL-2.0. See the privacy module's notice and upstream repository for its license and source.
