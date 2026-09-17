#!/system/bin/sh

ui_print "- Play Install Provenance Repair v1.1.6"
ui_print "- WebUI for APatch / KernelSU-compatible managers"
ui_print "- No boot service; changes are only made when you explicitly confirm an action"
ui_print "- Includes guarded stale PAIRIP eFuse detection/cleanup"

touch "$MODPATH/skip_mount"
set_perm "$MODPATH/playfix.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
