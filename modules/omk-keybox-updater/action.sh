#!/system/bin/sh
sh "${0%/*}/update.sh"
status=$?

# APatch and KernelSU close the output as soon as the action succeeds.
printf '\nPress Enter to close... '
IFS= read -r _unused || sleep 20
exit "$status"
