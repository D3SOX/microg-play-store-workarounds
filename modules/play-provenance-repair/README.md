# Play install provenance repair

WebUI and CLI helper for APatch and KernelSU. It fixes apps you own that complain they were not installed from Google Play, for example after you installed them with Aurora, ADB, or a restore tool.

It changes only install-source metadata. It does not create purchases and does not bypass a failed license check. Use it only when the real Play Store already recognizes that your account owns the app.

This problem is separate from Play Integrity. The Play Store can know that you own an app while the app still sees a non-Play install source from an earlier installation.

## Use it

Flash the ZIP in APatch or KernelSU. The module has no boot scripts, mounts nothing, and changes nothing until you confirm an action.

In the module's WebUI:

1. Search for the app by name or package name, or enter a package name.
2. Check its status. The WebUI shows the version, installer, installer UID, initiator, originator, package source, and whether PAIRIP (Google Play automatic protection) is present.
3. Select **Repair provenance** only if the app complains about its install source.

The WebUI shows the repair's progress and full transcript, then inspects the app again. It repairs one app at a time on purpose. Apps from F-Droid, Obtainium, Aurora, restore tools, or manual installs can have a non-Play install source for good reasons.

The same actions work from the command line:

```sh
su -c '/data/adb/modules/play_provenance_repair/playfix.sh inspect PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh repair PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh clear-efuse PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh play-uid'
```

The module's Action button shows these commands.

## What it checks

Three pieces of state can each make an app reject its install source:

```text
installerPackageName      the app that installed the package
initiatingPackageName     the app that started the installation
app-specific warning      a flag some apps store after they once saw a non-Play installer
```

An app counts as repaired when both `installerPackageName` and `initiatingPackageName` are `com.android.vending`.

## How the repair works

1. The helper first sets the installer to the Play Store, running as the Play Store's UID. This equals `su <play-uid> -c 'cmd package set-installer PACKAGE com.android.vending'`. The helper looks up the UID itself.
2. If either field is still not Google Play, the helper reinstalls the app in place as the Play Store. This happens when Android rejects step 1 because the old installer has a different signing key, and when the initiator is wrong, because step 1 does not change it. The helper creates a PackageInstaller session as the Play Store's UID with `-i com.android.vending`, stages the app's currently installed APK and splits, and commits the session.

The reinstall keeps the app's data and downloads nothing. A plain `cmd package install -r` from the Play Store's UID does not work, because Android restricts install modes by calling UID.

The helper reports success only after it reads both fields as Google Play. `null` means PackageManager reports no package for that field. A missing or unreadable field is an inspection error.

| CLI exit code | Meaning |
|---|---|
| `0` | Repaired and verified. |
| `1` | The operation failed. |
| `2` | The reinstall succeeded, but the install source is still incomplete. |
| `3` | The reinstall succeeded, but verification could not read the metadata. |

When verification fails after a successful reinstall, the WebUI shows "Reinstall succeeded; verification failed". Refresh the inspection before you retry the repair.

## Stale eFuse warning

One tested app still showed its own "not installed from Google Play" warning after the repair, even though its PAIRIP license check passed. The app had stored `eFuse=true` in its preferences when it once saw a non-Play installer, and repairing Android's metadata did not reset that flag.

The helper offers `clear-efuse` only when all of these are true:

- The installer and initiator are both Google Play.
- The app has PAIRIP components.
- That exact `eFuse=true` preference exists.

It never runs automatically. It force-stops the app, saves a backup of the preferences file to `/data/adb/play_provenance_repair/backups/`, which apps cannot read, and prints the backup's path. This is a fix for the pattern seen in testing, not a general PAIRIP interface.

## Tested cases

- One app needed only the installer change, because its initiator was already `com.android.vending`.
- Another app had the Play Store as installer but `com.android.shell` as initiator, and failed its Play license check. The in-place reinstall fixed both fields, and the license check passed without data loss.
- A third app needed the [eFuse cleanup](#stale-efuse-warning) after the repair.

These did not fix any of the tested cases: unrestricted Play Store network access, changes to the device-idle whitelist, and re-enabling the Play Store's `DownloadService`. They affect Store downloads, not install sources.

## Uninstall

Remove the module in your root manager. eFuse backups stay in `/data/adb/play_provenance_repair/backups/`. Delete `/data/adb/play_provenance_repair` to remove them.
