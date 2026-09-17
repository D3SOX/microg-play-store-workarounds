#!/system/bin/sh

MODID="play_provenance_repair"
MODDIR="/data/adb/modules/$MODID"
TOOL="$MODDIR/playfix.sh"

clear 2>/dev/null || true

cat <<EOF
Play Install Provenance Repair
==============================

This Action button does not repair anything by itself.
Use the module WebUI for the graphical interface, or run the
commands below from a root terminal.

Terminal usage
--------------

Inspect an installed package:
  su -c '$TOOL inspect PACKAGE'

Repair Google Play installer/initiator provenance:
  su -c '$TOOL repair PACKAGE'

Clear a detected stale PAIRIP eFuse warning after provenance
has already been repaired:
  su -c '$TOOL clear-efuse PACKAGE'

Show the main-user Google Play UID:
  su -c '$TOOL play-uid'

Example:
  su -c '$TOOL inspect com.example.app'
  su -c '$TOOL repair com.example.app'

Notes
-----
- Only use repair on apps you legitimately own.
- Repair preserves app data and reuses the installed APK/splits.
- There is intentionally no "repair all" command.
- clear-efuse is guarded and only works when the module detects
  the expected PAIRIP + stale eFuse state.

WebUI
-----
Open this module's WebUI button in APatch to search apps by
name/package and inspect or repair them interactively.
EOF

printf '\nPress Enter to close... '
IFS= read -r _unused || {
    # Some manager builds do not expose stdin to action.sh.
    # Keep the text visible for a while instead of flashing closed.
    sleep 20
}
