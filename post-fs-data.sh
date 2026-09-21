#!/system/bin/sh
MODDIR=${0%/*}

# Stage patched media_profiles XML to /data/local/tmp
if [ -f "$MODDIR/system/etc/media_profiles_patched.xml" ]; then
    cp "$MODDIR/system/etc/media_profiles_patched.xml" /data/local/tmp/media_profiles_patched.xml
    chmod 644 /data/local/tmp/media_profiles_patched.xml
    chown shell:shell /data/local/tmp/media_profiles_patched.xml
    chcon u:object_r:shell_data_file:s0 /data/local/tmp/media_profiles_patched.xml
fi

# Apply live sepolicy rules
if [ -x /data/adb/ap/bin/magiskpolicy ]; then
    /data/adb/ap/bin/magiskpolicy --live \
        "allow mediaserver shell_data_file dir { search read open getattr }" \
        "allow mediaserver shell_data_file file { read open getattr map }" 2>/dev/null
fi

# Set early props (support both resetprop and resetprop_phh)
RESETPROP=/data/adb/ap/bin/resetprop
[ ! -x "$RESETPROP" ] && RESETPROP=/system/bin/resetprop_phh

$RESETPROP -n media.c2.hal.selection hidl
$RESETPROP -n media.settings.xml /data/local/tmp/media_profiles_patched.xml
