# Play Store Xray Privacy Filter

Optional ARM64 root module for keeping the official Google Play Store installed for Play Integrity while default-denying ordinary Play Store network traffic for the **main Android user only**.

It does not consume Android's VPN slot and it does not globally block Google endpoints, so Aurora Store and unrelated UIDs continue to use normal networking.

## Companion `playstore-base` behavior

The normal `playstore-base` configuration adds `com.android.vending` to Android's device-idle/Doze whitelist after boot because the tested Android 16 Play Store needed that exemption for its `systemExempted` foreground download service.

This privacy module intentionally takes the opposite approach:

- disables only:

  ```text
  com.google.android.finsky.downloadservice.DownloadService
  ```

  for user 0;
- leaves Play Integrity enabled:

  ```text
  com.google.android.finsky.integrityservice.IntegrityService
  ```

- waits for boot completion and removes `com.android.vending` from the device-idle whitelist;
- repeats the removal after a short delay so it reliably overrides `playstore-base` if both modules are installed.

On the tested Android 16 setup, disabling `DownloadService` also stopped the Play Store background crash popup caused by that service attempting to start a `systemExempted` foreground service without the exemption.

The resulting device-idle state should be:

```bash
adb shell su -c 'dumpsys deviceidle whitelist =com.android.vending'
```

```text
false
```

This means **normal Play Store downloads are intentionally not supported while this privacy module is active**.

## Network policy

At boot the module dynamically resolves the main-user UID of `com.android.vending` and applies per-UID firewall/transparent-proxy rules:

- IPv4 TCP from Play Store -> local Xray transparent listener on `127.0.0.1:12345`;
- direct UDP/53 from Play Store -> local Xray DNS listener on `127.0.0.1:10853`;
- UDP/443 from Play Store -> `REJECT` to prevent QUIC/HTTP3 bypass;
- all IPv6 from Play Store -> `REJECT` to prevent bypassing the IPv4 transparent proxy;
- every other UID -> unchanged.

Xray then applies a **default-deny** TCP policy for the Play Store UID.

The currently observed Integrity-related allowlist is:

```text
play.googleapis.com
play-fe.googleapis.com
gmscompliance-pa.googleapis.com
remoteprovisioning.googleapis.com
```

All other Play Store TCP destinations are blackholed.

Examples of ordinary Store/CDN endpoints that remained blocked during testing include:

```text
play-lh.googleusercontent.com
play-apps-features.googleusercontent.com
android.clients.google.com
*.gvt1.com
playstoregatewayadapter-pa.googleapis.com
prod-lt-playstoregatewayadapter-pa.googleapis.com
```

Because the policy is UID-specific, Aurora Store continues to work normally even when it reaches infrastructure that would be blocked for `com.android.vending`.

## Architecture

```text
com.android.vending (main-user UID)
        |
        +-- IPv6 ------------------------------> REJECT
        |
        +-- UDP/443 QUIC ----------------------> REJECT
        |
        +-- UDP/53 ----------------------------> local Xray DNS :10853
        |
        +-- TCP -------------------------------> local Xray :12345
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

## Tested result

This four-domain allowlist was tested on a Pixel 8 Pro running Android 16 / SDK 36 LineageOS for microG with the official Play Store systemlessly installed as the privileged factory base.

The tested result remained:

```text
PLAY_RECOGNIZED
MEETS_BASIC_INTEGRITY
MEETS_DEVICE_INTEGRITY
LICENSED
```

The allowlist is empirical. It is not a statement that these are the only endpoints Google will ever require.

## Xray-core handling

The module ZIP does **not** redistribute the Xray binary.

During installation it will, in order:

1. reuse an existing tested `/data/adb/playstore_xray/xray`, if present;
2. reuse the Xray binary from an existing installation of this module, if present;
3. otherwise download the official Android ARM64 Xray release and verify its SHA-256 before installing it.

Xray version used by this module:

```text
v26.9.9
```

Official release:

https://github.com/XTLS/Xray-core/releases/tag/v26.9.9

Official Android ARM64 archive:

https://github.com/XTLS/Xray-core/releases/download/v26.9.9/Xray-android-arm64-v8a.zip

Official archive SHA-256:

```text
f18625edf2360df8f857d8a2d947f69dd137b31849e7b9b530200d7e5f482766
```

Source:

https://github.com/XTLS/Xray-core/tree/v26.9.9

License:

https://github.com/XTLS/Xray-core/blob/v26.9.9/LICENSE

Xray-core is MPL-2.0 licensed.

## Install

Flash the ZIP through APatch / KernelSU / a compatible Magisk-style module installer, then reboot.

This release is ARM64-only.

If no reusable Xray binary is present, the installer needs network access while flashing so it can download and verify the official archive.

## Verify after reboot

Check module boot state:

```sh
su -c 'cat /data/adb/playstore_xray_privacy_filter/boot.log'
```

Expected entries include the resolved main-user Play Store UID and confirmation that the rules were installed.

Check Xray and listeners:

```sh
su -c 'ps -A | grep xray'
su -c 'ss -lntup | grep -E "12345|10853"'
```

The module tracks its Xray process with:

```text
/dev/playstore_xray_privacy_filter.xray.pid
```

and verifies the process executable through `/proc/PID/exe` before treating that PID as its own Xray instance.

Check firewall rules:

```sh
su -c 'iptables -t nat -L OUTPUT -n -v --line-numbers | grep -E "12345|10853"'
su -c 'iptables -L OUTPUT -n -v --line-numbers | grep "udp dpt:443"'
su -c 'ip6tables -L OUTPUT -n -v --line-numbers | grep REJECT'
```

Check the intended Doze state:

```sh
su -c 'dumpsys deviceidle whitelist =com.android.vending'
```

Expected:

```text
false
```

Then retest Play Integrity with an app installed through the real Play Store.

## Logging and uninstall behavior

The shipped Xray config has access/error logging disabled to avoid creating a large local record of network activity. The module keeps only minimal boot/status information.

On uninstall it removes its exact firewall rules, stops only the Xray process it owns, and restores `DownloadService` only if this module was the component that disabled it.

## Caveats

The hostname allowlist was derived from successful traffic observed on one tested setup. Google can change required endpoints at any time. Re-test after Play Store, Android, microG, or Integrity-related updates.

Routing is based on TLS hostname/SNI visibility. Wider ECH deployment could make hostname-based routing insufficient and require redesigning this approach.
