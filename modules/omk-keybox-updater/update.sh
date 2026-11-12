#!/system/bin/sh

# Installs the newest valid public keybox into OhMyKeymint. Runs on demand from
# the module's Action button; nothing runs in the background.

MODDIR=${0%/*}
OMK_MODULE="/data/adb/modules/oh_my_keymint"
OMK_DIR="/data/misc/keystore/omk"
KEYBOX="$OMK_DIR/keybox.xml"
OMK_LOG="$OMK_DIR/logs/keymint.log"
BACKUPS="/data/adb/omk_keybox_updater/backups"
KEEP_BACKUPS=5
WAIT_SECONDS=15

STATUS_URL="https://android.googleapis.com/attestation/status"
SOURCES="yurikey integritybox"
YURIKEY_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"
INTEGRITYBOX_URL="https://github.com/MeowDump/Integrity-Box/releases/download/archive/Megatron"
# SHA-256 of the certificates at https://android.googleapis.com/attestation/root
GOOGLE_ROOTS="cedb1cb6dc896ae5ec797348bce9286753c2b38ee71ce0fbe34a9a1248800dfc 6d9db4ce6c5c0b293166d08986e05774a8776ceb525d9e4329520de12ba4bcc0"

export LC_ALL=C
umask 077

say() { echo "$*"; }
fail() {
    echo "! $*"
    exit 1
}

# YYYYMMDDHHMMSS -> YYYY-MM-DD HH:MM UTC
when() { echo "$1" | sed 's/^\(....\)\(..\)\(..\)\(..\)\(..\).*/\1-\2-\3 \4:\5 UTC/'; }
# Shell arithmetic can be 32-bit, so compare the 14-digit times in awk.
later() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }

fetch() {
    # -q skips ~/.curlrc, so neither it nor proxy variables change the download.
    if curl -q -fsSL --proto '=https' --noproxy '*' --connect-timeout 15 --max-time 60 \
        --max-filesize 4194304 -o "$2" "$1" 2>/dev/null && [ -s "$2" ]; then
        return 0
    fi
    rm -f "$2"
    return 1
}

decode_yurikey() {
    tr -d ' \t\r\n' < "$1" | base64 -d > "$2" 2>/dev/null
}

# Integrity-Box: base64 ten times, then hex, then ROT13.
decode_integritybox() {
    cp "$1" "$WORK/layer" || return 1
    i=0
    while [ "$i" -lt 10 ]; do
        tr -d ' \t\r\n' < "$WORK/layer" | base64 -d > "$WORK/next" 2>/dev/null || return 1
        mv -f "$WORK/next" "$WORK/layer"
        i=$((i + 1))
    done
    tr -d ' \t\r\n' < "$WORK/layer" > "$WORK/hex"
    grep -q '^[0-9a-fA-F]*$' "$WORK/hex" || return 1
    awk 'BEGIN { h = "0123456789abcdef" }
        { s = tolower($0)
          for (i = 1; i < length(s); i += 2)
              printf "%c", (index(h, substr(s, i, 1)) - 1) * 16 + index(h, substr(s, i + 1, 1)) - 1 }' \
        "$WORK/hex" | tr 'A-Za-z' 'N-ZA-Mn-za-m' > "$2"
}

# Checks a keybox and prints why it fails. Sets EXPIRES to the earliest notAfter
# of all its certificates, when the keybox stops working. OhMyKeymint needs one
# complete EC entry ("ecdsa" or "ec"); RSA is optional.
check_keybox() {
    EXPIRES=""
    open=0 ec=0
    awk -f "$MODDIR/keybox.awk" "$1" > "$WORK/items" || return 1
    while read -r kind value; do
        # A download cut off mid-entry must not pass without the END checks.
        case "$kind" in
            KEY) [ "$open" = 0 ] || { say "  incomplete $alg key"; return 1; } ;;
            *) [ "$open" = 1 ] || { say "  incomplete keybox"; return 1; } ;;
        esac
        case "$kind" in
            KEY)
                alg=$value count="" private=0 certs=0 open=1
                ;;
            COUNT) count=$value ;;
            PRIVATE) private=1 ;;
            CERT)
                certs=$((certs + 1))
                printf '%s' "$value" | base64 -d > "$WORK/cert.der" 2>/dev/null ||
                    { say "  $alg certificate $certs is not valid base64"; return 1; }
                info=$(od -An -v -tx1 "$WORK/cert.der" | awk -v now="$NOW" -f "$MODDIR/certinfo.awk")
                # shellcheck disable=SC2086 # split the five fields
                set -- $info
                [ "$#" -eq 5 ] || { say "  $alg certificate $certs cannot be parsed"; return 1; }
                case "$5" in
                    expired) say "  $alg certificate $certs expired on $(when "$4")"; return 1 ;;
                    future) say "  $alg certificate $certs is not valid before $(when "$3")"; return 1 ;;
                esac
                if grep -q -e "\"$1\"" -e "\"$2\"" "$WORK/status.json"; then
                    say "  $alg certificate $certs is revoked"
                    return 1
                fi
                if [ -z "$EXPIRES" ] || later "$EXPIRES" "$4"; then
                    EXPIRES=$4
                fi
                mv -f "$WORK/cert.der" "$WORK/last.der"
                ;;
            END)
                [ "$private" = 1 ] || { say "  $alg key has no private key"; return 1; }
                [ "$certs" -gt 0 ] && [ "$count" = "$certs" ] ||
                    { say "  $alg key lists ${count:-no} certificates but has $certs"; return 1; }
                root=$(sha256sum "$WORK/last.der" | cut -d ' ' -f 1)
                case " $GOOGLE_ROOTS " in
                    *" $root "*) ;;
                    *) say "  $alg chain does not end in a Google attestation root"; return 1 ;;
                esac
                open=0
                case "$alg" in ecdsa | ec) ec=1 ;; esac
                ;;
        esac
    done < "$WORK/items"
    [ "$open" = 0 ] || { say "  incomplete $alg key"; return 1; }
    [ "$ec" = 1 ] || { say "  incomplete keybox: no complete EC key"; return 1; }
}

# Waits for OhMyKeymint to reload keybox.xml. Sets RESULT to ok, rejected, or
# timeout.
await_reload() {
    i=0
    while [ "$i" -lt "$WAIT_SECONDS" ]; do
        sleep 1
        size=$(wc -c < "$OMK_LOG" 2>/dev/null || echo 0)
        [ "$size" -ge "$LOG_POS" ] || LOG_POS=0
        case "$(tail -c +"$((LOG_POS + 1))" "$OMK_LOG" 2>/dev/null)" in
            *"invalid keybox.xml"* | *"(fallback=true)"*) RESULT=rejected; return ;;
            *"(fallback=false)"*) RESULT=ok; return ;;
        esac
        i=$((i + 1))
    done
    RESULT=timeout
}

# Replaces keybox.xml in one rename, with the owner, mode, and SELinux label
# OhMyKeymint uses.
place() {
    tmp="$OMK_DIR/.keybox.xml.tmp-$$"
    LOG_POS=$(wc -c < "$OMK_LOG" 2>/dev/null || echo 0)
    if cp "$1" "$tmp" && chown "$OWNER" "$tmp" && chmod "$MODE" "$tmp" &&
        chcon "$CONTEXT" "$tmp" && mv -f "$tmp" "$KEYBOX"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

[ "$(id -u)" = 0 ] || fail "Run this as root."
[ -d "$OMK_MODULE" ] && [ ! -e "$OMK_MODULE/disable" ] && [ ! -e "$OMK_MODULE/remove" ] ||
    fail "OhMyKeymint is not installed or not enabled."
[ -d "$OMK_DIR" ] || fail "$OMK_DIR does not exist. Boot once with OhMyKeymint enabled."
command -v curl > /dev/null || fail "curl is missing."

WORK=$(mktemp -d "${TMPDIR:-/data/local/tmp}/omk-keybox.XXXXXX") || fail "Could not create a work directory."
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' INT TERM
NOW=$(date -u +%Y%m%d%H%M%S)
[ "${#NOW}" -eq 14 ] || fail "Could not read the current time."

say "- Downloading Google's revocation list"
if ! fetch "$STATUS_URL" "$WORK/status.json" || ! grep -q '"entries"' "$WORK/status.json"; then
    fail "Could not download the revocation list. Nothing changed."
fi

CURRENT_OK=0
CURRENT_EXPIRES=""
if [ -f "$KEYBOX" ]; then
    say "- Checking the current keybox"
    if check_keybox "$KEYBOX"; then
        CURRENT_OK=1
        CURRENT_EXPIRES=$EXPIRES
        say "  valid until $(when "$EXPIRES")"
    fi
fi

BEST=""
for source in $SOURCES; do
    say "- Checking $source"
    raw="$WORK/$source.raw"
    case "$source" in
        yurikey) fetch "$YURIKEY_URL" "$raw" && decode_yurikey "$raw" "$WORK/$source.xml" ;;
        integritybox) fetch "$INTEGRITYBOX_URL" "$raw" && decode_integritybox "$raw" "$WORK/$source.xml" ;;
    esac
    if [ ! -s "$raw" ]; then
        say "  download failed"
        continue
    fi
    if [ ! -s "$WORK/$source.xml" ]; then
        say "  could not decode the download"
        continue
    fi
    check_keybox "$WORK/$source.xml" || continue
    say "  valid until $(when "$EXPIRES")"
    if [ -z "$BEST" ] || later "$EXPIRES" "$BEST_EXPIRES"; then
        BEST=$source
        BEST_EXPIRES=$EXPIRES
    fi
done

[ -n "$BEST" ] || fail "No source has a valid keybox. Kept the current one."
if [ "$CURRENT_OK" = 1 ] && ! later "$BEST_EXPIRES" "$CURRENT_EXPIRES"; then
    say "- The current keybox is valid and expires no earlier than the newest public one. Nothing changed."
    exit 0
fi

OWNER=$(stat -c %u:%g "$KEYBOX" 2>/dev/null) || OWNER=1017:1017
MODE=$(stat -c %a "$KEYBOX" 2>/dev/null) || MODE=600
# shellcheck disable=SC2012 # toybox stat has no SELinux context field
CONTEXT=$(ls -Z "$KEYBOX" 2>/dev/null | awk '{ print $1 }')
case "$CONTEXT" in u:object_r:*) ;; *) CONTEXT=u:object_r:keystore_data_file:s0 ;; esac

BACKUP=""
if [ -f "$KEYBOX" ]; then
    if ! mkdir -p "$BACKUPS" || ! chmod 700 "${BACKUPS%/*}" "$BACKUPS"; then
        fail "Could not create $BACKUPS. Nothing changed."
    fi
    BACKUP="$BACKUPS/keybox-$(date -u +%Y%m%d-%H%M%S)-$$.xml"
    cp "$KEYBOX" "$BACKUP" || fail "Could not back up the current keybox. Nothing changed."
fi

say "- Installing the $BEST keybox"
say "  OhMyKeymint deletes app keys tied to the old keybox, so some apps may ask you to sign in again."
place "$WORK/$BEST.xml" || fail "Could not write $KEYBOX. Nothing changed."

await_reload
if [ "$RESULT" = timeout ] && cmp -s "$WORK/$BEST.xml" "$KEYBOX"; then
    say "  OhMyKeymint did not confirm the reload within $WAIT_SECONDS seconds. Check $OMK_LOG."
    RESULT=ok
fi

if [ "$RESULT" = ok ]; then
    sleep 1
    retired=$(tail -c +"$((LOG_POS + 1))" "$OMK_LOG" 2>/dev/null |
        sed -n 's/.*found \([0-9][0-9]*\) stale keybox-bound keys to retire.*/\1/p' | tail -n 1)
    [ "${retired:-0}" = 0 ] || say "  OhMyKeymint deleted $retired app keys tied to the old keybox."
    # Backup names sort by date, so the oldest come first.
    set -- "$BACKUPS"/keybox-*.xml
    while [ "$#" -gt "$KEEP_BACKUPS" ]; do
        rm -f "$1"
        shift
    done
    say "- Done. The keybox is valid until $(when "$BEST_EXPIRES")."
    exit 0
fi

say "! OhMyKeymint rejected the new keybox."
[ -n "$BACKUP" ] || fail "OhMyKeymint is using its bundled template keybox."
if place "$BACKUP" && await_reload && [ "$RESULT" = ok ]; then
    fail "Restored the previous keybox."
fi
fail "Could not restore the previous keybox. Copy $BACKUP to $KEYBOX."
