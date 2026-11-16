# Agent setup instructions

These instructions are for a coding agent that helps a user set up this guide on their phone over ADB. Read [README.md](README.md) and the README of each module under [modules/](modules/) before you do anything.

## Survey

Start with a read-only survey over ADB:

- device model, Android version and SDK, ROM, and microG version
- root manager (Magisk, KernelSU, or APatch) and the installed modules in `/data/adb/modules`
- whether `/product/priv-app/FakeStore/FakeStore.apk` and `/product/etc/permissions/privapp-permissions-com.android.vending.xml` exist
- whether `com.google.android.gms` and `com.android.vending` are system apps (`pm list packages -s`) or normal apps, and which signing key `com.android.vending` has
- which apps list `com.android.vending` as their installer (`pm list packages -3 -i`), because uninstalling microG Companion clears that field
- any keystore module that is already installed

Tell the user which of the README's [supported setups](README.md#supported-setups) the phone has: a ROM that ships microG, or microG installed as normal apps. Compare the result with the matching tested setup in the README. List the differences and tell the user which steps are already done.

## Rules

- Follow the setup steps in order. Check that each step works before you start the next.
- Ask the user before every change: installing, enabling, or disabling a module, rebooting, writing anything under `/data` or `/system`, or uninstalling an app. Say what you will run and why. Read and back up any file before you overwrite it.
- Tell the user when a step needs them on the phone, such as tapping a module's Action button, signing in to the Play Store, or running the integrity checker, and wait for their result.
- The user provides the Play Store APK. Verify its signer as the [`playstore-base` README](modules/playstore-base/README.md#choose-a-play-store-apk) describes, and stop if it does not match.
- If GmsCore is a normal app, pull the installed GmsCore APK from the phone and build `playstore-base` with it. Check that its signer matches the installed GmsCore.
- Before you uninstall microG Companion, save the list of apps that name it as their installer. After the Play Store works, offer to repair them with `play-provenance-repair`.
- Never print or copy logcat lines from microG's authenticator. They can contain OAuth tokens.
- Do not copy fingerprints, patch levels, or keyboxes from the README or from old guides. Generate them with the tools the README names, or ask the user.
- Never print, copy off the phone, or send anywhere the private key in `keybox.xml`. Only the certificates may leave the device.
- Where the device differs from the tested setup, follow the current upstream documentation of that project and tell the user what you changed.
- If a verdict is wrong, use the README's Troubleshooting section and read logcat before you guess.

## Report

When you finish, report the Play Integrity verdicts, what you changed on the device, and what the user has to redo later, such as renewing the Play Integrity Fork profile or the keybox.
