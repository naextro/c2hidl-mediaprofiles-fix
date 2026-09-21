# C2 HIDL + MediaProfiles Fix (`c2hidl-mediaprofiles-fix`)

An APatch / Magisk module to restore hardware-accelerated video recording (AVC/HEVC) and fix `MediaRecorder` "prepare failed" (`-2147483648`) errors on the **OnePlus Nord CE2 Lite 5G (CPH2381 / CPH2409, Qualcomm Snapdragon 695 / SM6375)** running Phh-based GSIs (such as crDroid GSI) on top of LineageOS / OEM vendor and boot partitions.

---

## The Problem

On AOSP/Phh GSIs paired with LineageOS or OEM vendor images on the Nord CE2 Lite 5G, video recording fails in camera apps (including Open Camera, LMC8.4, and Google Camera ports) with symptoms like:
- "Failed to save video file" / "Failed to start video recording"
- Logcat reporting `StagefrightRecorder: prepare failed: -2147483648`
- Logcat reporting `StagefrightRecorder: Failed to create video encoder` right after allocating `c2.android.h263.encoder`

---

## Root Cause Analysis

1. **Codec2 HAL Selection Defaults to AIDL**:
   - Modern GSIs default `media.c2.hal.selection` to `aidl`.
   - The device vendor's Codec2 HAL (`vendor.qti.media.c2@1.0-service`) is HIDL-based.
   - Setting it to AIDL hides the vendor hardware C2 store (`default`), leaving only software codecs (`c2.android.*`).

2. **Non-Standard OPLUS Profile Quality Naming**:
   - Even when forcing HIDL mode, the vendor's `/vendor/etc/media_profiles_vendor.xml` uses non-standard OPLUS quality tags (such as `quality="high"` instead of standard AOSP `quality="1080p"`).
   - When apps request standard 1080p profiles via `CamcorderProfile`, `StagefrightRecorder` cannot resolve a valid profile.
   - Lacking profile information, `StagefrightRecorder` falls back to the hardcoded default video encoder `VIDEO_ENCODER_H263` (`1`).
   - `CCodec` successfully instantiates `c2.android.h263.encoder`, but the codec immediately fails during configuration because **H.263 does not support 1080p (only up to CIF 352x288)**, triggering `prepare failed: -2147483648`.

3. **SELinux Blockers on Custom Profiles**:
   - `mediaserver` (UID `media`, SELinux domain `u:r:mediaserver:s0`) cannot traverse `/data/adb/modules` because `/data/adb` is mode `0700` (`root:root`).
   - If staged in `/data/local/tmp/`, `mediaserver` is denied access by SELinux (`avc: denied { search read open getattr } for name="tmp" tcontext=u:object_r:shell_data_file:s0`).

4. **GSI Boot Script Overwrites**:
   - Early phh boot scripts (`/system/bin/phh-on-data.sh` and `/system/bin/rw-system.sh`) explicitly reset `media.settings.xml` back to `/vendor/etc/media_profiles_vendor.xml` during boot, undoing early property changes.

---

## What This Module Does

- **Enforces HIDL Codec2 HAL**: Sets `media.c2.hal.selection=hidl` so the system exposes `c2.qti.avc.encoder` and `c2.qti.hevc.encoder`.
- **Stages AOSP-Standard Media Profiles**: Bundles a corrected `media_profiles` XML extracted from the stock OnePlus OTA vendor partition (using proper AOSP `quality="1080p"` definitions for cameras 0, 2, and 4) and stages it to `/data/local/tmp/media_profiles_patched.xml`.
- **Patches SELinux**: Injects policy rules allowing `mediaserver` to search, open, read, getattr, and mmap `shell_data_file` via `sepolicy.rule` and live `magiskpolicy`.
- **Survives GSI Late-Boot Overwrites**: `service.sh` waits for `sys.boot_completed=1` and late scripts to settle, re-applies `media.settings.xml` and `media.c2.hal.selection`, and gracefully restarts `mediaserver32` to ensure the patched profiles are actively loaded.

---

## File Structure

```
c2hidl-mediaprofiles-fix/
├── module.prop
├── post-fs-data.sh
├── service.sh
├── sepolicy.rule
└── system/
    └── etc/
        └── media_profiles_patched.xml
```

---

## Requirements

- **Device**: OnePlus Nord CE2 Lite 5G (`CPH2381` / `CPH2409`, SM6375) or similar Snapdragon 695 devices running a Phh-based GSI.
- **Root**: [APatch](https://github.com/bmax121/APatch) (0.13.3+) or Magisk / KernelSU.
- **APatch Mount Provider**: A meta-module providing overlay mount support (e.g., **Hybrid Mount** or **ZygiskNext / ReZygisk**) must be active for modules to mount properly.

---

## Installation

1. Download the flashable ZIP (`c2hidl_module.zip`) or create one by zipping the contents of this repository:
   ```bash
   zip -r c2hidl_module.zip ./*
   ```
2. Open the **APatch** app (or Magisk / KernelSU).
3. Navigate to the **Modules** tab, tap **Install**, and select `c2hidl_module.zip`.
4. Reboot the device.

---

## Verification

After rebooting, open a terminal or `adb shell` and verify:

1. **Check Codec2 HAL selection**:
   ```bash
   getprop media.c2.hal.selection
   # Expected output: hidl
   ```

2. **Check Media Profiles property**:
   ```bash
   getprop media.settings.xml
   # Expected output: /data/local/tmp/media_profiles_patched.xml
   ```

3. **Check Service Execution Log**:
   ```bash
   cat /data/local/tmp/c2hidl_service.log
   ```
   You should see entries confirming boot completion was detected, the profile was staged, sepolicy rules were applied, and `mediaserver32` was restarted.

4. **Test Video Recording**:
   Open your preferred camera application (Open Camera, GCam/LMC, stock camera) and record a video at 1080p. The video will record cleanly with Qualcomm hardware AVC/HEVC acceleration enabled (`msm_vidc`).

---

## Caveats & Notes

- The XML profiles and camera IDs (0, 2, 4) in `media_profiles_patched.xml` are tailored to the OnePlus Nord CE2 Lite 5G camera sensor layout and its stock OxygenOS OTA configuration.
- However, the overall debugging methodology—identifying Codec2 HAL mode mismatches, resolving AOSP vs OEM profile naming discrepancies, and fixing `mediaserver` SELinux access—applies to many other Snapdragon devices running GSIs with similar video recording failures.

---

## Credits

Diagnosed and resolved through manual `adb`, `logcat`, and SELinux debugging combined with an AI-assisted debugging session.
