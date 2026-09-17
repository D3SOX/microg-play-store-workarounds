#!/system/bin/sh

PLAY_PKG="com.android.vending"
USER_ID=0
SESSION=""

say() {
    printf '%s\n' "$*"
}

fail() {
    say "ERROR: $*" >&2
    exit 1
}

cleanup_session() {
    if [ -n "${SESSION:-}" ]; then
        PLAY_UID="$(get_play_uid 2>/dev/null || true)"
        if [ -n "$PLAY_UID" ]; then
            su "$PLAY_UID" -c "cmd package install-abandon '$SESSION'" >/dev/null 2>&1 || true
        fi
        SESSION=""
    fi
}

trap cleanup_session EXIT INT TERM

validate_pkg() {
    PKG="$1"
    case "$PKG" in
        ""|*[!A-Za-z0-9._]*)
            fail "Invalid package name: $PKG"
            ;;
    esac
}

package_exists() {
    pm path "$1" 2>/dev/null | grep -q '^package:'
}

get_play_uid() {
    cmd package list packages -U --user "$USER_ID" 2>/dev/null |
        sed -n "s/^package:${PLAY_PKG} uid:\([0-9][0-9]*\).*/\1/p" |
        head -n1
}

field_from_dump() {
    KEY="$1"
    sed -n "s/^[[:space:]]*${KEY}=//p" | head -n1
}

pairip_detected() {
    printf '%s\n' "$1" | grep -q 'com\.pairip\.licensecheck\.'
}

find_efuse_file() {
    PKG="$1"
    PREFDIR="/data/user/${USER_ID}/${PKG}/shared_prefs"
    [ -d "$PREFDIR" ] || return 1
    grep -RIl 'name="eFuse"' "$PREFDIR" 2>/dev/null | head -n1
}

get_efuse_state() {
    FILE="$1"
    [ -n "$FILE" ] && [ -f "$FILE" ] || {
        printf 'absent\n'
        return 0
    }

    LINE="$(grep -m1 'name="eFuse"' "$FILE" 2>/dev/null || true)"
    case "$LINE" in
        *'value="true"'*) printf 'true\n' ;;
        *'value="false"'*) printf 'false\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

inspect_pkg() {
    PKG="$1"
    validate_pkg "$PKG"
    package_exists "$PKG" || fail "Package is not installed for user $USER_ID: $PKG"

    DUMP="$(dumpsys package "$PKG" 2>/dev/null)"

    INSTALLER="$(printf '%s\n' "$DUMP" | field_from_dump installerPackageName)"
    INSTALLER_UID="$(printf '%s\n' "$DUMP" | field_from_dump installerPackageUid)"
    INITIATING="$(printf '%s\n' "$DUMP" | field_from_dump initiatingPackageName)"
    ORIGINATING="$(printf '%s\n' "$DUMP" | field_from_dump originatingPackageName)"
    PACKAGE_SOURCE="$(printf '%s\n' "$DUMP" | field_from_dump packageSource)"
    VERSION_NAME="$(printf '%s\n' "$DUMP" | field_from_dump versionName)"
    VERSION_CODE="$(printf '%s\n' "$DUMP" | sed -n 's/^[[:space:]]*versionCode=\([^[:space:]]*\).*/\1/p' | head -n1)"

    [ -n "$INSTALLER" ] || INSTALLER="null"
    [ -n "$INSTALLER_UID" ] || INSTALLER_UID="null"
    [ -n "$INITIATING" ] || INITIATING="null"
    [ -n "$ORIGINATING" ] || ORIGINATING="null"
    [ -n "$PACKAGE_SOURCE" ] || PACKAGE_SOURCE="?"
    [ -n "$VERSION_NAME" ] || VERSION_NAME="?"
    [ -n "$VERSION_CODE" ] || VERSION_CODE="?"

    if pairip_detected "$DUMP"; then
        PAIRIP="true"
    else
        PAIRIP="false"
    fi

    EFUSE_FILE="$(find_efuse_file "$PKG" 2>/dev/null || true)"
    EFUSE_STATE="$(get_efuse_state "$EFUSE_FILE")"

    say "package=$PKG"
    say "versionName=$VERSION_NAME"
    say "versionCode=$VERSION_CODE"
    say "installerPackageName=$INSTALLER"
    say "installerPackageUid=$INSTALLER_UID"
    say "initiatingPackageName=$INITIATING"
    say "originatingPackageName=$ORIGINATING"
    say "packageSource=$PACKAGE_SOURCE"
    say "pairipDetected=$PAIRIP"
    say "eFuseState=$EFUSE_STATE"
    say "eFuseFile=${EFUSE_FILE:-null}"
}

repair_pkg() {
    PKG="$1"
    validate_pkg "$PKG"
    package_exists "$PKG" || fail "Package is not installed for user $USER_ID: $PKG"
    [ "$PKG" != "$PLAY_PKG" ] || fail "Refusing to modify the Play Store package itself."

    PLAY_UID="$(get_play_uid)"
    [ -n "$PLAY_UID" ] || fail "Could not determine the main-user Play Store UID."

    say "Package: $PKG"
    say "Play Store UID: $PLAY_UID"
    say
    say "[1/4] Setting installer package to Google Play..."

    SET_OUT="$(su "$PLAY_UID" -c "cmd package set-installer '$PKG' '$PLAY_PKG'" 2>&1)"
    SET_RC=$?
    [ -n "$SET_OUT" ] && say "$SET_OUT"

    if [ "$SET_RC" -ne 0 ]; then
        say
        say "Direct set-installer was not permitted for the current installer."
        say "Continuing with a Play-owned in-place reinstall instead."
    fi

    DUMP="$(dumpsys package "$PKG" 2>/dev/null)"
    INSTALLER="$(printf '%s\n' "$DUMP" | field_from_dump installerPackageName)"
    INITIATING="$(printf '%s\n' "$DUMP" | field_from_dump initiatingPackageName)"

    say "installerPackageName=${INSTALLER:-null}"
    say "initiatingPackageName=${INITIATING:-null}"

    if [ "$INSTALLER" = "$PLAY_PKG" ] && [ "$INITIATING" = "$PLAY_PKG" ]; then
        say
        say "PackageManager provenance is already fully attributed to Google Play."
        say "No in-place reinstall is needed."
        am force-stop "$PKG" >/dev/null 2>&1 || true
        am force-stop "$PLAY_PKG" >/dev/null 2>&1 || true
        say "SUCCESS"
        return 0
    fi

    APKS="$(pm path "$PKG" 2>/dev/null | sed 's/^package://')"
    [ -n "$APKS" ] || fail "Could not locate the currently installed APKs."

    say
    say "[2/4] Creating install session owned by Google Play..."

    OUT="$(
        su "$PLAY_UID" -c \
            "cmd package install-create -r -i '$PLAY_PKG' --install-reason 4 --user '$USER_ID' --pkg '$PKG'" \
            2>&1
    )"
    say "$OUT"

    SESSION="$(printf '%s\n' "$OUT" | sed -n 's/.*\[\([0-9][0-9]*\)\].*/\1/p' | head -n1)"
    [ -n "$SESSION" ] || fail "Could not parse the install session ID."
    say "Session: $SESSION"

    # Opening the session once prepares its vmdl staging directory.
    # A zero-byte probe is sufficient; it is not used as an APK.
    cmd package install-write "$SESSION" probe /dev/null >/dev/null 2>&1 || true
    sleep 1

    STAGE="$(
        find /data/app -maxdepth 1 -type d -name "vmdl${SESSION}.tmp" -print -quit 2>/dev/null
    )"
    [ -n "$STAGE" ] || fail "Could not locate the PackageInstaller staging directory."

    say "Stage: $STAGE"
    say
    say "[3/4] Copying the currently installed APKs..."

    for APK in $APKS; do
        NAME="$(basename "$APK")"
        say "  $NAME"
        cp "$APK" "$STAGE/$NAME" || fail "Failed to copy $NAME"
    done

    chown 1000:1000 "$STAGE"/*.apk || fail "Failed to set staged APK ownership"
    chmod 0644 "$STAGE"/*.apk || fail "Failed to set staged APK permissions"
    restorecon -RF "$STAGE" >/dev/null 2>&1 || true

    say
    say "[4/4] Committing as Google Play..."

    RESULT="$(su "$PLAY_UID" -c "cmd package install-commit '$SESSION'" 2>&1)"
    say "$RESULT"

    case "$RESULT" in
        *Success*) ;;
        *) fail "Install commit failed" ;;
    esac

    # Session has been consumed successfully; do not abandon it in the trap.
    SESSION=""
    sleep 2

    am force-stop "$PKG" >/dev/null 2>&1 || true
    am force-stop "$PLAY_PKG" >/dev/null 2>&1 || true

    say
    say "Final install source:"
    inspect_pkg "$PKG"

    DUMP="$(dumpsys package "$PKG" 2>/dev/null)"
    INSTALLER="$(printf '%s\n' "$DUMP" | field_from_dump installerPackageName)"
    INITIATING="$(printf '%s\n' "$DUMP" | field_from_dump initiatingPackageName)"

    say
    if [ "$INSTALLER" = "$PLAY_PKG" ] && [ "$INITIATING" = "$PLAY_PKG" ]; then
        say "SUCCESS"
    else
        say "WARNING: provenance is still not fully Google Play."
        exit 2
    fi
}

clear_efuse() {
    PKG="$1"
    validate_pkg "$PKG"
    package_exists "$PKG" || fail "Package is not installed for user $USER_ID: $PKG"
    [ "$PKG" != "$PLAY_PKG" ] || fail "Refusing to modify the Play Store package itself."

    DUMP="$(dumpsys package "$PKG" 2>/dev/null)"
    INSTALLER="$(printf '%s\n' "$DUMP" | field_from_dump installerPackageName)"
    INITIATING="$(printf '%s\n' "$DUMP" | field_from_dump initiatingPackageName)"

    [ "$INSTALLER" = "$PLAY_PKG" ] && [ "$INITIATING" = "$PLAY_PKG" ] ||
        fail "Refusing to clear eFuse until installer and initiator are both Google Play. Repair provenance first."

    pairip_detected "$DUMP" ||
        fail "PAIRIP/Google Play protection was not detected for this package. Refusing generic preference editing."

    EFUSE_FILE="$(find_efuse_file "$PKG" 2>/dev/null || true)"
    [ -n "$EFUSE_FILE" ] || fail "No eFuse preference was found for this package."

    STATE="$(get_efuse_state "$EFUSE_FILE")"
    [ "$STATE" = "true" ] || fail "eFuse is not currently true (state: $STATE)."

    say "Package: $PKG"
    say "PAIRIP detected: true"
    say "Preference: $EFUSE_FILE"
    say "Current eFuse: true"
    say
    say "Clearing stale eFuse flag..."

    am force-stop "$PKG" >/dev/null 2>&1 || true

    BACKUP="${EFUSE_FILE}.playfix.bak"
    cp -a "$EFUSE_FILE" "$BACKUP" || fail "Could not create backup: $BACKUP"

    TMP="${EFUSE_FILE}.playfix.tmp"
    sed '/name="eFuse"/s/value="true"/value="false"/' "$EFUSE_FILE" > "$TMP" || {
        rm -f "$TMP"
        fail "Failed to edit eFuse preference"
    }

    cat "$TMP" > "$EFUSE_FILE" || {
        rm -f "$TMP"
        cp -a "$BACKUP" "$EFUSE_FILE" >/dev/null 2>&1 || true
        fail "Failed to write edited preference"
    }
    rm -f "$TMP"
    restorecon "$EFUSE_FILE" >/dev/null 2>&1 || true

    NEW_STATE="$(get_efuse_state "$EFUSE_FILE")"
    if [ "$NEW_STATE" != "false" ]; then
        cp -a "$BACKUP" "$EFUSE_FILE" >/dev/null 2>&1 || true
        restorecon "$EFUSE_FILE" >/dev/null 2>&1 || true
        fail "Verification failed; original preference restored."
    fi

    say "New eFuse: false"
    say "Backup: $BACKUP"
    say "SUCCESS"
}

case "${1:-}" in
    inspect)
        [ $# -eq 2 ] || fail "Usage: $0 inspect PACKAGE"
        inspect_pkg "$2"
        ;;
    repair)
        [ $# -eq 2 ] || fail "Usage: $0 repair PACKAGE"
        repair_pkg "$2"
        ;;
    clear-efuse)
        [ $# -eq 2 ] || fail "Usage: $0 clear-efuse PACKAGE"
        clear_efuse "$2"
        ;;
    play-uid)
        UID_VALUE="$(get_play_uid)"
        [ -n "$UID_VALUE" ] || fail "Could not determine Play Store UID"
        say "$UID_VALUE"
        ;;
    *)
        say "Usage:"
        say "  $0 inspect PACKAGE"
        say "  $0 repair PACKAGE"
        say "  $0 clear-efuse PACKAGE"
        say "  $0 play-uid"
        exit 1
        ;;
esac
