#!/system/bin/sh

ui_print "- Run the module's Action to update OhMyKeymint's keybox."
ui_print "- It never runs in the background."
[ -d /data/adb/modules/oh_my_keymint ] || ui_print "! OhMyKeymint is not installed."
