# OhMyKeymint keybox updater

Root module that replaces [OhMyKeymint](https://github.com/qwq233/OhMyKeymint)'s keybox with the newest valid public keybox when you tap its Action button. It checks every downloaded keybox on the phone first and installs nothing that is expired, revoked, or has a chain that does not end in one of Google's attestation roots.

It never runs in the background. Each keybox change makes OhMyKeymint delete the app keys tied to the old keybox, so some apps may ask you to sign in again. Updating only when you choose keeps that under your control.

## Use it

Flash the ZIP in APatch, KernelSU, or Magisk and reboot. When your Play Integrity verdict drops, or the keybox is about to expire, tap the module's **Action** button. You can also run it from a root shell:

```sh
su -c 'sh /data/adb/modules/omk_keybox_updater/update.sh'
```

It needs OhMyKeymint installed and enabled, network access, and `curl`.

## What it does

1. Downloads Google's revocation list from `android.googleapis.com/attestation/status`. Without it, the module changes nothing.
2. Checks the current keybox.
3. Downloads and checks each source:

   | Source | URL |
   |---|---|
   | [Yurikey](https://github.com/Yurii0307/yurikey) | `https://raw.githubusercontent.com/Yurii0307/yurikey/main/key` |
   | [Integrity-Box](https://github.com/MeowDump/Integrity-Box) | `https://github.com/MeowDump/Integrity-Box/releases/download/archive/Megatron` |

4. Installs the valid keybox that expires last, but only if the current keybox is invalid or expires earlier. A keybox expires when the first of its certificates does.

Downloads go directly to these hosts over verified HTTPS. The module ignores proxy variables and `curl` configuration files.

A keybox counts as valid when:

- it has an EC key (`ecdsa` or `ec`) with a private key, as OhMyKeymint requires,
- each key lists as many certificates as it contains,
- every certificate is currently valid and not on Google's revocation list, by hex or decimal serial,
- each chain ends in one of [Google's attestation roots](https://android.googleapis.com/attestation/root).

The module does not verify certificate signatures, so it does not prove that Google issued the chain. It also does not check that the private key matches its certificate. OhMyKeymint checks the key itself and rejects a keybox that does not match.

## Install and rollback

Before it replaces the keybox, the module copies the current one to `/data/adb/omk_keybox_updater/backups/`, which only root can read. It keeps the five newest backups.

It writes the new keybox under a temporary name in OhMyKeymint's folder, sets the owner, mode, and SELinux label of the old file, and renames it to `keybox.xml` in one step. OhMyKeymint reloads it without a reboot. The module then watches `/data/misc/keystore/omk/logs/keymint.log`:

- If OhMyKeymint accepts the keybox, the module reports how many app keys OhMyKeymint deleted.
- If OhMyKeymint rejects it, the module restores the previous keybox.
- If OhMyKeymint logs nothing within 15 seconds and the file is unchanged, the module reports the keybox as installed and asks you to check the log.

## Limits

These are public keyboxes, leaked keys that many devices share. Google revokes them sooner or later, and it can stop trusting one without listing it as revoked. The module cannot detect that case. If the verdict stays at `MEETS_BASIC_INTEGRITY` with a valid keybox, see the [main README](../../README.md#only-meets_basic_integrity).

The sources often carry the same key. On 2026-11-12, Yurikey and Integrity-Box both served `Yurikey68`. When no source has a newer keybox, the module keeps the current one.

## Uninstall

Remove the module in your root manager. The keybox stays in place. Delete `/data/adb/omk_keybox_updater` to remove the backups.
