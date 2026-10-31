# Play Install Provenance Repair

WebUI and CLI helper for APatch and KernelSU. It fixes apps you legitimately own that complain they were not installed through Google Play after you moved from Aurora, ADB, a restore tool, or another installer.

This issue is separate from Play Integrity. The real Play Store can recognize that an account owns an app while the app still sees non-Play install provenance from an earlier installation.

## What can matter

In testing, three separate pieces of state mattered:

```text
installerPackageName
initiatingPackageName
app-specific cached warning state
```

A package can therefore look partially repaired while a protected app still rejects it.

### Case 1: installer alone was enough

For one app, setting the installer to:

```text
com.android.vending
```

was sufficient because its `initiatingPackageName` was already correct.

The working state looked like:

```text
installerPackageName=com.android.vending
installerPackageUid=10144
initiatingPackageName=com.android.vending
originatingPackageName=null
```

### Case 2: installer was Play, initiator was still shell

Another app reached:

```text
installerPackageName=com.android.vending
initiatingPackageName=com.android.shell
```

and continued to fail its Play-protected licensing flow.

What fixed that case was an in-place reinstall of the app's **currently installed APK/splits** through a PackageInstaller session created by the real Play Store UID. Afterward:

```text
installerPackageName=com.android.vending
initiatingPackageName=com.android.vending
```

and the app's Play license check worked normally without losing its app data.

### Case 3: provenance repaired, sticky local warning remained

A third app had correct Play provenance and its PAIRIP license check succeeded, but it still showed its own "not installed from Google Play" warning.

That app had stored a sticky local `eFuse=true` preference when it previously observed a non-Play installer. Repairing Android's provenance did not reset that application-specific flag.

The helper therefore has a **guarded, separate** stale-warning cleanup path. It is only offered when:

- installer is Google Play;
- initiator is Google Play;
- PAIRIP/Google Play automatic-protection components are detected;
- the exact known local stale `eFuse=true` preference exists.

The cleanup is never automatic. It first saves a backup of the preference file to `/data/adb/play_provenance_repair/backups/`, which apps cannot read or modify.

`eFuse` is **not** treated as a universal PAIRIP API. It is handled only as the specific app-local pattern observed during testing.

## What the module does

The module has no boot service and does not modify apps automatically.

The WebUI can:

- search installed user apps by label or package name;
- accept a package name directly;
- inspect only the selected package instead of scanning every package with `dumpsys`;
- show version, installer package, installer UID, initiator, originator and package source;
- detect PAIRIP / Google Play automatic-protection components;
- show whether the package is fully Play-provenanced, installer-only, non-Play, or matches the guarded stale-warning case;
- explicitly repair one selected package;
- show live repair progress, elapsed time, backend step and the complete repair transcript;
- automatically re-inspect the package when a repair finishes;
- expose equivalent CLI commands from the module Action button.

There is intentionally no "repair all" action. Apps installed through F-Droid, Obtainium, Aurora, restore tools or manual installs can legitimately have non-Play provenance.

## Repair strategy

The repair is intentionally conservative.

First it tries the lightweight installer reassignment from the Play Store UID.

The equivalent operation is conceptually:

```sh
su 10144 -c 'cmd package set-installer PACKAGE com.android.vending'
```

The Play Store UID is resolved dynamically by the helper; `10144` is only the UID from the tested main-user setup.

Android can reject this operation when the old installer has a different signing certificate. A tested example was an app restored through the platform installer, where Android returned a `SecurityException` because the Play Store caller did not share the old installer's certificate.

That is not treated as a fatal repair failure. The helper then falls back to the full Play-owned in-place reinstall path.

## Play-owned in-place reinstall

A direct `cmd package install -r` from the Play Store UID is not sufficient because Android restricts reverse/install modes depending on the calling UID.

The working method is:

1. create a PackageInstaller session as the Play Store UID with `-i com.android.vending`;
2. stage the app's currently installed base APK and splits into that session;
3. commit the session as the Play Store UID.

The helper performs this automatically and preserves the app's data.

No Play Store redownload is required; it reuses the APK/splits already installed on the device.

## Repair results

The helper reports success only after it reads both installer and initiator as Google Play. An explicit `null` means PackageManager reports no package for that field. Missing or unreadable provenance fields produce an inspection error instead.

If the reinstall commits but verification cannot read the metadata, the WebUI shows "Reinstall succeeded; verification failed". Refresh inspection before retrying repair. If the repair succeeds but the automatic refresh fails, the WebUI reports that separately and preserves the repair transcript.

The CLI returns `0` for verified success, `1` for an operation error, `2` when the reinstall commits but provenance remains incomplete, and `3` when the reinstall commits but verification cannot read the metadata.

## WebUI

Open the module WebUI in your root manager, search by app name or package name, and inspect the package. Use **Repair provenance** only when the app complains about its Play install source.

After you confirm, the WebUI shows a progress panel with the backend step and transcript. When the repair finishes, it inspects the package again. Switching to another app clears the previous result.

## CLI

```sh
su -c '/data/adb/modules/play_provenance_repair/playfix.sh inspect PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh repair PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh clear-efuse PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh play-uid'
```

The module's Action button shows the same commands as a short terminal reference.

## Install and uninstall

Flash the ZIP in APatch or KernelSU. The module has no boot scripts and mounts nothing.

Each `clear-efuse` run prints the path of its backup in `/data/adb/play_provenance_repair/backups/`. Uninstalling the module keeps these backups. To remove them, delete `/data/adb/play_provenance_repair`.

## What did *not* fix the tested licensing/provenance failures

In the tested cases, these did **not** resolve the provenance problem:

- opening unrestricted Play Store network access;
- changing the device-idle/Doze whitelist;
- re-enabling Play Store `DownloadService`.

Those settings are relevant to Store networking/download behavior, but they are separate from Android installer/initiator provenance.

## Important limitation

Changing install provenance does not create a purchase entitlement and does not bypass a failed Google Play license check.

Use this only for apps you legitimately own where the real Play Store/account already recognizes the entitlement and the remaining problem is install-source metadata or the guarded stale local warning state described above.
