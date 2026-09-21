#!/system/bin/sh
MODDIR=${0%/*}
LOGFILE="/data/local/tmp/c2hidl_service.log"

exec > "$LOGFILE" 2>&1
echo "[$(date)] c2hidl service.sh started"

# Wait for boot completion
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done

echo "[$(date)] boot completed detected, waiting for late init scripts to settle..."
sleep 3

# Ensure patched media_profiles XML exists in /data/local/tmp
if [ -f "$MODDIR/system/etc/media_profiles_patched.xml" ]; then
    cp "$MODDIR/system/etc/media_profiles_patched.xml" /data/local/tmp/media_profiles_patched.xml
    chmod 644 /data/local/tmp/media_profiles_patched.xml
    chown shell:shell /data/local/tmp/media_profiles_patched.xml
    chcon u:object_r:shell_data_file:s0 /data/local/tmp/media_profiles_patched.xml
    echo "[$(date)] staged media_profiles_patched.xml to /data/local/tmp"
fi

# Ensure live sepolicy is active
if [ -x /data/adb/ap/bin/magiskpolicy ]; then
    /data/adb/ap/bin/magiskpolicy --live \
        "allow mediaserver shell_data_file dir { search read open getattr }" \
        "allow mediaserver shell_data_file file { read open getattr map }"
    echo "[$(date)] live sepolicy rule applied"
fi

# Enforce properties (overriding phh-on-data.sh and rw-system.sh)
RESETPROP=/data/adb/ap/bin/resetprop
[ ! -x "$RESETPROP" ] && RESETPROP=/system/bin/resetprop_phh

$RESETPROP -n media.c2.hal.selection hidl
$RESETPROP -n media.settings.xml /data/local/tmp/media_profiles_patched.xml
echo "[$(date)] properties enforced: media.c2.hal.selection=$(getprop media.c2.hal.selection), media.settings.xml=$(getprop media.settings.xml)"

# Restart mediaserver32 to load the patched profile
killall mediaserver32
echo "[$(date)] restarted mediaserver32"
