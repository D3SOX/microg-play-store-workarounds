# Play Store Xray privacy filter

Optional ARM64 root module that limits what the real Google Play Store can reach, while Play Integrity keeps working. It needs [`playstore-base`](../playstore-base/README.md) or another privileged Play Store.

With the filter enabled:

- The Play Store cannot download or update apps.
- The Play Store can reach only four Google hosts. Everything else it tries is blocked.
- Play Store pages still load app details through those four hosts. The filter does not take the Store offline.
- Play Integrity, licensing, and app recognition keep working.
- Aurora Store and all other apps keep normal networking. The filter does not use Android's VPN slot.

It filters only the Play Store of the main Android user (user 0). Work profiles and secondary users are not filtered.

## How it works

At the start of `service.sh`, before Xray starts and before the Play Store can run, the module reads the Play Store's UID from `/data/system/packages.list`. It adds rules for that UID to its own `playstore_xray` chains at the top of `OUTPUT`:

- IPv4 TCP goes to the local Xray listener on `127.0.0.1:12345`.
- DNS (UDP port 53) goes to the local Xray DNS listener on `127.0.0.1:10853`.
- Everything else is rejected, including QUIC and other UDP, ICMP, and all IPv6.

Once PackageManager is up, the module checks the UID again and also blocks the new UID if it changed. If Xray fails to start, the Play Store has no network access at all.

Xray lets TLS connections through to these hosts and drops all other Play Store TCP traffic:

```text
play.googleapis.com
play-fe.googleapis.com
gmscompliance-pa.googleapis.com
remoteprovisioning.googleapis.com
```

```text
com.android.vending (user 0)
    IPv6, ICMP, UDP except 53  ->  REJECT
    UDP 53                     ->  Xray DNS :10853
    TCP                        ->  Xray :12345
                                     allowed hosts above  ->  DIRECT
                                     everything else      ->  BLACKHOLE

all other apps                 ->  normal networking
```

These Store and CDN hosts stayed blocked in testing:

```text
play-lh.googleusercontent.com
play-apps-features.googleusercontent.com
android.clients.google.com
*.gvt1.com
playstoregatewayadapter-pa.googleapis.com
prod-lt-playstoregatewayadapter-pa.googleapis.com
```

The module also disables the Play Store's `com.google.android.finsky.downloadservice.DownloadService` for user 0 and removes the Play Store from the device-idle whitelist. `playstore-base` normally adds that entry so downloads work, and it skips it while this module is enabled. `IntegrityService` stays enabled.

The allowlist comes from observed traffic. Google may need other hosts in the future.

## Install

Flash the ZIP in APatch, KernelSU, or a compatible module manager, then reboot. The installer needs network access. It downloads the pinned [Xray-core](#xray-core) release and checks its SHA-256. If the download or check fails, the installation stops and any installed version stays in place. Upgrades replace the installed Xray binary.

## Verify

After a reboot, check the boot log. It should show the Play Store UID and `rules installed`:

```sh
su -c 'cat /data/adb/playstore_xray_privacy_filter/boot.log'
```

Check Xray and its listeners:

```sh
su -c 'ps -A | grep xray'
su -c 'ss -lntup | grep -E "12345|10853"'
```

Check the firewall rules. The packet counters show traffic going to Xray and getting rejected:

```sh
su -c 'iptables -t nat -L playstore_xray -n -v'
su -c 'iptables -L playstore_xray -n -v'
su -c 'ip6tables -L playstore_xray -n -v'
```

Check that the device-idle entry is gone. This should print `false`:

```sh
su -c 'dumpsys deviceidle whitelist =com.android.vending'
```

Check that `DownloadService` is disabled. This should print `No services found`:

```sh
su -c 'cmd package query-services --brief --components --user 0 --query-flags 786432 -n com.android.vending/com.google.android.finsky.downloadservice.DownloadService'
```

Then run a Play Integrity check with an app installed through the Play Store.

## Troubleshooting

These boot log messages point to a problem:

| Message | Meaning |
|---|---|
| `xray did not listen on 127.0.0.1:12345; Play Store traffic stays blocked` | Xray did not start, so the Play Store has no network access and Integrity checks fail. Reinstall the module to restore the Xray binary. |
| `ERROR failed: ...` and `filtering is incomplete` | A firewall command failed, and some Play Store traffic may not be filtered. The log shows the failing command. |
| `could not resolve com.android.vending UID; no firewall rules installed` | The module found no Play Store for the main user. |
| `could not query Play Store DownloadService` | The module could not tell whether `DownloadService` is enabled and left it unchanged. |

Versions before 1.5 checked `DownloadService` before user 0 was unlocked. Android hid the service from that check, so the module logged `Play Store DownloadService already disabled` and left it enabled. The first boot with 1.5 disables it.

If Integrity fails only while the module is enabled and the log shows no errors, Google may now need a host that is not on the allowlist. Retest after Play Store, Android, microG, or Integrity-related updates.

## Uninstall

Remove the module in your root manager and reboot. The uninstall script removes the `playstore_xray` chains and stops only the Xray process this module started. If the module disabled `DownloadService`, the script re-enables it once boot completes and then deletes `/data/adb/playstore_xray_privacy_filter`. If re-enabling fails, that directory stays.

If downloads still fail after you uninstall the module, re-enable the service yourself:

```sh
su -c 'pm enable --user 0 com.android.vending/com.google.android.finsky.downloadservice.DownloadService'
```

## Limits

- Allowed connections leave the device from the Xray process, which runs as root, not from the Play Store's UID. Per-app VPN and firewall rules for the Play Store do not apply to them. Rules for root traffic do.
- Xray routes by the TLS server name (SNI). If Google turns on Encrypted Client Hello (ECH) for these hosts, Xray can no longer see the name, and this design stops working.
- The shipped Xray config turns off access and error logs, so the device keeps no record of Play Store traffic. The module writes only its short boot log.

## Tested result

On a Pixel 8 Pro with Android 16 and LineageOS for microG, Integrity kept passing with the filter enabled. On 2026-11-12, with filter 1.5, Play Store 54.1.11-34, and OhMyKeymint, the result was:

```text
MEETS_BASIC_INTEGRITY, MEETS_DEVICE_INTEGRITY, MEETS_STRONG_INTEGRITY
PLAY_RECOGNIZED
LICENSED
```

A Play Store update stayed at 0 bytes until it was cancelled, and the app did not change.

## Xray-core

The module ZIP does not include Xray. The installer downloads this official release:

```text
Version:  v26.11.9
Archive:  https://github.com/XTLS/Xray-core/releases/download/v26.11.9/Xray-android-arm64-v8a.zip
SHA-256:  edcefc25b9b3195b11e18624c8269a969d6aabc39c6298a9a5ab29de15d46f3b
Source:   https://github.com/XTLS/Xray-core/tree/v26.11.9
```

Xray-core is licensed under [MPL-2.0](https://github.com/XTLS/Xray-core/blob/v26.11.9/LICENSE).
