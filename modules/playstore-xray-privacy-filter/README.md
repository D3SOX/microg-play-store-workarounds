# Play Store Xray Privacy Filter

Optional ARM64 root module that keeps the official Google Play Store installed for Play Integrity while blocking its ordinary network traffic. It filters only the Play Store UID of the **main Android user**.

The module does not use Android's VPN slot and does not block Google endpoints globally. Aurora Store and every other app keep normal networking.

Normal Play Store downloads do not work while this module is active. See [Play Store downloads](#play-store-downloads).

## Network policy

At the start of `service.sh`, before Xray starts and before the Play Store can run, the module reads the main-user UID of `com.android.vending` from `/data/system/packages.list`. It then adds per-UID rules to its own `playstore_xray` chains, which it hooks at the top of `OUTPUT`:

- IPv4 TCP from the Play Store goes to the local Xray transparent listener on `127.0.0.1:12345`.
- Plain DNS (UDP/53) from the Play Store goes to the local Xray DNS listener on `127.0.0.1:10853`.
- Everything else from the Play Store is rejected, including other UDP such as QUIC, ICMP, and all IPv6.
- Other UIDs are unchanged.

Once PackageManager is up, the module checks the UID again and also blocks the new UID if it changed.

Only the local Xray listeners are reachable, so the Play Store stays offline if Xray fails to start. Xray allows TLS connections to these hosts and blackholes all other Play Store TCP traffic:

```text
play.googleapis.com
play-fe.googleapis.com
gmscompliance-pa.googleapis.com
remoteprovisioning.googleapis.com
```

These Store and CDN endpoints stayed blocked during testing:

```text
play-lh.googleusercontent.com
play-apps-features.googleusercontent.com
android.clients.google.com
*.gvt1.com
playstoregatewayadapter-pa.googleapis.com
prod-lt-playstoregatewayadapter-pa.googleapis.com
```

The rules match only the Play Store UID, so Aurora Store can still reach the same infrastructure.

```text
com.android.vending (main-user UID)
        |
        +-- IPv6, ICMP, UDP other than 53 -----> REJECT
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

## Play Store downloads

The module disables this Play Store component for user 0:

```text
com.google.android.finsky.downloadservice.DownloadService
```

It leaves Play Integrity enabled:

```text
com.google.android.finsky.integrityservice.IntegrityService
```

On the tested Android 16 ROM, `DownloadService` crashed in the background when it tried to start a `systemExempted` foreground service without a device-idle exemption. `playstore-base` normally adds that exemption so downloads work. This module needs neither, so after boot completes it removes `com.android.vending` from the device-idle whitelist. `playstore-base` skips adding the entry while this module is enabled.

## Tested result

The four-host allowlist was tested on a Pixel 8 Pro running Android 16 / SDK 36 LineageOS for microG, with the official Play Store systemlessly installed as the privileged factory base. The result stayed:

```text
PLAY_RECOGNIZED
MEETS_BASIC_INTEGRITY
MEETS_DEVICE_INTEGRITY
LICENSED
```

The allowlist comes from observed traffic. Google may require other endpoints in the future.

## Install

This release is ARM64-only. Flash the ZIP in APatch, KernelSU, or a compatible Magisk-style module manager, then reboot.

The installer needs network access. It downloads the pinned official Xray-core release and checks its SHA-256 before installing it. Upgrades replace the installed Xray binary with that release. If the download or check fails, the installation aborts and any installed version stays in place.

## Verify after reboot

Check the boot log:

```sh
su -c 'cat /data/adb/playstore_xray_privacy_filter/boot.log'
```

It should show the main-user Play Store UID and end its firewall setup with `rules installed`.

Check Xray and its listeners:

```sh
su -c 'ps -A | grep xray'
su -c 'ss -lntup | grep -E "12345|10853"'
```

The module records its Xray PID in `/dev/playstore_xray_privacy_filter.xray.pid`. Before treating that PID as its own Xray process, it checks the executable through `/proc/PID/exe`.

Check the firewall rules:

```sh
su -c 'iptables -t nat -L playstore_xray -n -v'
su -c 'iptables -L playstore_xray -n -v'
su -c 'ip6tables -L playstore_xray -n -v'
```

Check the device-idle state:

```sh
su -c 'dumpsys deviceidle whitelist =com.android.vending'
```

Expected:

```text
false
```

Then retest Play Integrity with an app installed through the real Play Store.

## Troubleshooting

These boot log messages point to a problem:

- `xray did not listen on 127.0.0.1:12345; Play Store traffic stays blocked` means Xray did not start. The Play Store has no network access, so Integrity checks fail. Reinstall the module to restore the Xray binary.
- `ERROR failed: ...` followed by `filtering is incomplete` means a firewall command failed. Some Play Store traffic may not be filtered. The log shows the failing command.
- `could not resolve com.android.vending UID; no firewall rules installed` means the module found no Play Store package for the main user.

If Integrity fails only while the module is enabled, Google may now require a host that is not on the allowlist. Retest after Play Store, Android, microG, or Integrity-related updates.

## Uninstall

Remove the module in your root manager and reboot. The uninstall script removes the `playstore_xray` chains and stops only the Xray process this module started.

If the module disabled `DownloadService`, the uninstall script re-enables it once boot completes and then deletes `/data/adb/playstore_xray_privacy_filter`. If re-enabling fails, that directory stays. If Play Store downloads still fail after uninstalling, re-enable the service manually:

```sh
su -c 'pm enable --user 0 com.android.vending/com.google.android.finsky.downloadservice.DownloadService'
```

## Logging

The shipped Xray config disables access and error logs, so the device keeps no record of Play Store network activity. The module writes only a short boot log.

## Caveats

- Connections that Xray allows leave the device from the Xray process, which runs as root, not from the Play Store UID. Per-app VPN routing and per-app firewall rules that target the Play Store UID do not apply to them. Rules for root traffic do.
- Xray routes by the TLS server name (SNI). If Google deploys Encrypted Client Hello (ECH) for these hosts, Xray can no longer see the server name, and this design stops working.
- Only the main user (user 0) is filtered. Play Store instances in work profiles or secondary users are not.

## Xray-core

The module ZIP does **not** include the Xray binary. The installer downloads it from the official release:

```text
Version:  v26.10.31
Archive:  https://github.com/XTLS/Xray-core/releases/download/v26.10.31/Xray-android-arm64-v8a.zip
SHA-256:  ee7878bb47ce28ff5b068e2d173ba1a9fab20ca1aec94191644919ec08ba5f1d
Source:   https://github.com/XTLS/Xray-core/tree/v26.10.31
```

Xray-core is licensed under [MPL-2.0](https://github.com/XTLS/Xray-core/blob/v26.10.31/LICENSE).
