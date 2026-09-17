# Play Store Xray Privacy Filter

## Companion `playstore-base` compatibility

The current `playstore-base` module adds `com.android.vending` to Android's
device-idle/Doze whitelist after boot so normal Play Store downloads can use
the Store's `systemExempted` foreground service on the tested Android 16 ROM.

This privacy module intentionally disables that `DownloadService`, waits for
boot completion, and removes Play Store from the device-idle whitelist. The
removal is repeated after a short delay so it reliably overrides the base
module's boot-time allowlist addition.

## Purpose

The official Google Play Store (`com.android.vending`) is kept installed so Play Integrity can bind to it, but its network access is default-denied for the main Android user.

The module:

- finds the main-user Play Store UID dynamically;
- redirects that UID's TCP through a local Xray transparent listener;
- allows only:
  - `play.googleapis.com`
  - `play-fe.googleapis.com`
  - `gmscompliance-pa.googleapis.com`
  - `remoteprovisioning.googleapis.com`
- blackholes every other Play Store TCP destination;
- rejects UDP/443 for the Play Store UID to prevent QUIC/HTTP3 bypass;
- rejects IPv6 for the Play Store UID because this transparent redirect is IPv4;
- redirects direct UDP/53 from the Play Store UID through Xray;
- does **not** use Android `VpnService`;
- does **not** affect Aurora Store or other app UIDs.

This exact four-domain allowlist was tested on a Pixel 8 Pro running Android 16 LineageOS for microG with the Play Store systemlessly installed as the privileged factory base. The resulting Play Integrity verdict remained:

- `PLAY_RECOGNIZED`
- `MEETS_BASIC_INTEGRITY`
- `MEETS_DEVICE_INTEGRITY`
- `LICENSED`

## Architecture

```text
com.android.vending (main-user UID)
        |
        +-- IPv6 ------------------------------> REJECT
        |
        +-- UDP/443 QUIC ----------------------> REJECT
        |
        +-- TCP -> local Xray TLS/SNI routing
                     |
                     +-- play.googleapis.com ------------> DIRECT
                     +-- play-fe.googleapis.com ---------> DIRECT
                     +-- gmscompliance-pa.googleapis.com -> DIRECT
                     +-- remoteprovisioning.googleapis.com -> DIRECT
                     |
                     +-- everything else ----------------> BLACKHOLE

Aurora Store / every other UID
        |
        +-- normal Android networking
```

## Xray-core

The installer reuses `/data/adb/playstore_xray/xray` when that tested manual setup already exists.

Otherwise it downloads the official ARM64 Android Xray-core v26.9.9 release and verifies the release ZIP SHA-256 before extraction.

Release:
https://github.com/XTLS/Xray-core/releases/tag/v26.9.9

Source corresponding to the bundled/downloaded executable:
https://github.com/XTLS/Xray-core/tree/v26.9.9

Xray-core is licensed under MPL-2.0:
https://github.com/XTLS/Xray-core/blob/v26.9.9/LICENSE

Official release archive SHA-256:

```text
f18625edf2360df8f857d8a2d947f69dd137b31849e7b9b530200d7e5f482766
```

## Install

Flash the ZIP through APatch / KernelSU / Magisk-compatible module installation, then reboot.

This release is ARM64-only.

If the device already has the earlier manual setup at `/data/adb/playstore_xray/xray`, the installer copies that binary. Otherwise the installer needs network access while flashing so it can download the verified official Xray release.

## Verify after reboot

```sh
su -c 'cat /data/adb/playstore_xray_privacy_filter/boot.log'
```

Expected:

```text
main-user Play Store UID=...
rules installed
```

Check Xray:

```sh
su -c 'ps -A | grep xray'
su -c 'ss -lntup | grep -E "12345|10853"'
```

Check routing rules:

```sh
su -c 'iptables -t nat -L OUTPUT -n -v --line-numbers | grep -E "12345|10853"'
su -c 'iptables -L OUTPUT -n -v --line-numbers | grep "udp dpt:443"'
su -c 'ip6tables -L OUTPUT -n -v --line-numbers | grep REJECT'
```

Then retest Play Integrity and the actual application relying on it.

## Caveats

This is an empirical allowlist derived from packet captures and Xray TLS/SNI logs on one tested setup. Google can change the hosts used by Play Integrity. If a future update breaks Integrity, capture the Play Store UID's Xray traffic again and add only the newly required hostname.

Because routing is based on TLS SNI, future ECH deployment could also require revisiting this design.

The module intentionally logs only minimal boot status. Xray access/error logging is disabled in the shipped config to avoid creating a large local record of network activity.
