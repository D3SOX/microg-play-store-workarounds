# Play Install Provenance Repair

> Maintained by **D3SOX** (assisted by GPT).

APatch WebUI helper for apps you legitimately own that complain they were not installed through Google Play after migrating from Aurora, ADB, a restore tool, or another installer.

## What it repairs

Android keeps multiple install-source fields. In testing, some Play-protected apps required both of these to point to Google Play:

```text
installerPackageName=com.android.vending
initiatingPackageName=com.android.vending
```

The module can:

- search installed user apps locally in the WebUI;
- inspect one selected package without running `dumpsys` over the whole device;
- try the lightweight `set-installer` repair;
- if necessary, perform an in-place reinstall of the app's currently installed APK/splits through a PackageInstaller session owned by the real Play Store UID;
- preserve app data during the in-place reinstall;
- detect PAIRIP components;
- detect the specific guarded stale `eFuse=true` warning state observed in one Play-protected app and offer a separate explicit cleanup action;
- show live repair progress and the complete command transcript;
- expose equivalent CLI commands through the module Action button.

It intentionally has no "repair all" operation because many apps legitimately originate from F-Droid, Obtainium, Aurora, restore tools, or manual installs.

## WebUI

Open the module WebUI in APatch, search by app name or package name, inspect the package, then use **Repair provenance** only when the app is actually complaining about Play installation provenance.

## CLI

```sh
su -c '/data/adb/modules/play_provenance_repair/playfix.sh inspect PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh repair PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh clear-efuse PACKAGE'
su -c '/data/adb/modules/play_provenance_repair/playfix.sh play-uid'
```

## Important limitation

Changing install provenance does not create a purchase entitlement and does not bypass a failed Google Play license check. It is intended only to restore correct installer metadata for apps the user legitimately owns.

The stale-warning cleanup is deliberately guarded and is only offered when Play provenance is already correct, PAIRIP is detected, and the exact known preference state is present.
