# C2 HIDL + MediaProfiles Fix (`c2hidl-mediaprofiles-fix`)

An APatch module to restore hardware-accelerated video recording (AVC/HEVC) and fix `MediaRecorder` "prepare failed" (`-2147483648`) errors on the **OnePlus Nord CE2 Lite 5G (CPH2381 / CPH2409, Qualcomm Snapdragon 695 / SM6375)** running Phh-based GSIs (such as crDroid GSI) on top of LineageOS / OEM vendor and boot partitions.

> ⚠️ **APatch only for now** — Magisk / KernelSU are not yet supported (the scripts use APatch-specific paths). Want Magisk support? You have two options:
> 1. Open a GitHub issue on this repo requesting it
> 2. Message me on Discord — @h6s

> General class of bug: this is a fixable **Treble GSI / Phh GSI + Qualcomm vendor** bug class, not just a OnePlus Nord CE2 Lite 5G (CPH2381 / CPH2409, Snapdragon 695 / SM6375) issue. Tested and tuned on the Nord CE2 Lite 5G (CPH2381 / CPH2409, Snapdragon 695 / SM6375) running a Phh GSI / Treble GSI, but the same failure mode affects other Qualcomm + Phh GSI / Treble GSI phones — see [Does this affect other devices?](#does-this-affect-other-devices) below.

---

## Symptoms / Search Keywords

If you landed here from Google / GitHub search, look for these exact strings in your `logcat` or camera app. Each line below is intentionally kept verbatim and grep-able:

- `failed to save video file`
- `Failed to save video file`
- `Failed to start video recording`
- `prepare failed: -2147483648`
- `StagefrightRecorder: prepare failed: -2147483648`
- `Failed to create video encoder`
- `StagefrightRecorder: Failed to create video encoder`
- `MediaProfiles: The given camcorder profile camera 0 quality 6 is not found`
- `c2.android.h263.encoder`
- `media.c2.hal.selection`
- `media.settings.xml`
- `media_profiles_vendor.xml`

Devices / setups people search for with these symptoms include: OnePlus Nord CE2 Lite 5G CPH2381 CPH2409, Snapdragon 695 SM6375, Phh GSI, Treble GSI, crDroid GSI, LineageOS vendor, OxygenOS OTA vendor.

---

## The Problem

On AOSP/Phh GSIs / Treble GSIs paired with LineageOS or OEM vendor images on the Nord CE2 Lite 5G (CPH2381 / CPH2409, Snapdragon 695 / SM6375), video recording fails in camera apps (including Open Camera, LMC8.4, and Google Camera ports) with symptoms like:

- `failed to save video file` / `Failed to save video file` / `Failed to start video recording`
- Logcat reporting `StagefrightRecorder: prepare failed: -2147483648` (also surfaces as `MediaRecorder: prepare failed: -2147483648`)
- Logcat reporting `StagefrightRecorder: Failed to create video encoder` right after allocating `c2.android.h263.encoder`
- Logcat reporting `MediaProfiles: The given camcorder profile camera 0 quality 6 is not found`

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
- **Root**: [APatch](https://github.com/bmax121/APatch) (0.13.3+) only. Magisk / KernelSU are not supported yet — see [#1](https://github.com/naextro/c2hidl-mediaprofiles-fix/issues/1).
- **APatch Mount Provider**: A meta-module providing overlay mount support (e.g., **Hybrid Mount** or **ZygiskNext / ReZygisk**) must be active for modules to mount properly.

---

## Installation

1. Download the flashable ZIP (`c2hidl_module.zip`) or create one by zipping the contents of this repository:
   ```bash
   zip -r c2hidl_module.zip ./*
   ```
2. Open the **APatch** app.
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

- The XML profiles and camera IDs (0, 2, 4) in `media_profiles_patched.xml` are tailored to the OnePlus Nord CE2 Lite 5G (CPH2381 / CPH2409, Snapdragon 695 / SM6375) camera sensor layout and its stock OxygenOS OTA configuration.
- However, the overall debugging methodology—identifying Codec2 HAL mode mismatches, resolving AOSP vs OEM profile naming discrepancies, and fixing `mediaserver` SELinux access—applies to many other Snapdragon devices running Phh GSIs / Treble GSIs with similar video recording failures.

---

## Does this affect other devices?

Short answer: yes, this is a **Treble GSI / Phh GSI bug class**, not a Nord CE2 Lite 5G-only bug. The default config in this repo targets the **OnePlus Nord CE2 Lite 5G (CPH2381 / CPH2409, Snapdragon 695 / SM6375)**, but the same two root causes recur on other Qualcomm phones running Phh-based Treble GSIs.

### 1. Is the `media.c2.hal.selection` aidl/hidl mismatch common?

Yes. Modern Treble GSIs / Phh GSIs (Android 13+, especially 14/15-based GSIs such as crDroid GSI) increasingly default `media.c2.hal.selection` to `aidl`, while many shipped Qualcomm vendors only provide a HIDL Codec2 HAL (`vendor.qti.media.c2@1.0-service`, `default` store). AOSP's `HalSelection.cpp` documents this switch, and Google has deprecated HIDL `android.hardware.media.c2` from the 202404 vendor FCM onward (Pixel / Cuttlefish device configs now set `media.c2.hal.selection=aidl`).

Result on any affected Qualcomm + Phh GSI / Treble GSI device: the vendor hardware store disappears, only `c2.android.*` software codecs remain, `c2.qti.avc.encoder` / `c2.qti.hevc.encoder` vanish, and `StagefrightRecorder` fails with:

- `StagefrightRecorder: Failed to create video encoder`
- `MediaRecorder: prepare failed: -2147483648`

If `getprop media.c2.hal.selection` returns `aidl` on a vendor that only ships a HIDL C2 service, you are in this bucket regardless of brand.

### 2. Is OPLUS `quality="high"` naming unique, or do other OEMs do the same?

Not unique in kind, though OPLUS's exact variant is distinctive. AOSP's `MediaProfiles.cpp` (`sCamcorderQualityNameMap`) treats `high` (= `QUALITY_HIGH` = 1) and `1080p` (= `QUALITY_1080P` = 6) as different IDs. When an app requests 1080p (quality 6) but the active `media_profiles_vendor.xml` only defines `quality="high"`, you get exactly:

- `MediaProfiles: The given camcorder profile camera 0 quality 6 is not found`

The same failure pattern (`... quality 5 ...`, `... quality 3 ...`, etc.) is reported for years across Sony, ASUS, Samsung and others — any vendor file missing the explicit `720p` / `1080p` / `480p` entries an app asks for will trip it. Other OEMs (Xiaomi/Redmi, vivo/iQOO, realme, Motorola, Nokia, Lenovo) each ship their own vendor profile quirks, which is why Phh's `device_phh_treble` carries per-fingerprint workarounds (e.g. `rw-system.sh` forcing `media.settings.xml` to `/vendor/etc/media_profiles_vendor.xml` for specific devices) and a Treble Settings toggle ("use alternate media profiles" under Qualcomm settings). OPLUS on the Nord CE2 Lite 5G (CPH2381 / CPH2409, Snapdragon 695 / SM6375) just happens to ship a particularly minimal vendor file.

### 3. Other users reporting the same symptoms on different devices

- Phh `treble_experimentations` issues: Moto G6/G6 Play video-record "Can't connect to camera" (#809), Tecno/MTK unable to record video (#1023), Lenovo S5 4K-profile discussion recommending the "use alternate media profiles" Qualcomm toggle (#1446).
- XDA / LineageOS threads: Open Camera `Failed to save video file` / `failed to save video file` on custom ROM + GSI setups, and Fairphone 4K→1080p fallback threads showing the same user-visible symptom from a different underlying profile/encoder mismatch.
- Generic Android reports: `prepare failed: -2147483648` + `Failed to create video encoder` is a generic `StagefrightRecorder`/`MediaRecorder` failure signature with many causes, but on Qualcomm + Phh GSI / Treble GSI setups the C2-HAL + media-profile combination above is one of the most common.

### How to check your own device

1. Check the HAL selection:
   ```bash
   getprop media.c2.hal.selection
   getprop media.settings.xml
   ```
   If the first prints `aidl` and your vendor only has a HIDL C2 service (check `lshal | grep media.c2` / `dumpsys media.codec` for missing `c2.qti.*`), try `hidl`.
2. Check your vendor profiles:
   ```bash
   grep -n 'EncoderProfile.*quality=' /vendor/etc/media_profiles_vendor.xml
   ```
   If you only see `quality="low"` / `quality="high"` (or `timelapselow`/`timelapsehigh`) and no `quality="1080p"` / `quality="720p"` / `quality="480p"`, standard `CamcorderProfile.get(camera, QUALITY_1080P)` (quality 6) calls will log `The given camcorder profile camera X quality 6 is not found`.
3. Confirm in logcat while reproducing in Open Camera / GCam:
   ```bash
   logcat -b all -d | grep -Ei 'MediaProfiles|StagefrightRecorder|MediaRecorder.*prepare|Failed to create video encoder|failed to save video file|c2\.(android|qti)'
   ```

### How to adapt this module to another phone

- Keep the Nord CE2 Lite 5G (CPH2381 / CPH2409, Snapdragon 695 / SM6375) files as the reference example.
- Extract **your own** stock OTA/vendor `media_profiles*.xml` (from your own device's OxygenOS/MIUI/FuntouchOS/etc. OTA or `/vendor/etc`), convert the vendor-specific quality names to AOSP-standard `1080p`/`720p`/`480p` entries, and replace `system/etc/media_profiles_patched.xml`.
- Adjust the camera IDs if your camera layout differs (this module assumes `0, 2, 4`; many phones use `0, 1` or `0, 2, 3, 4` — match your `CameraManager` ID list and vendor XML).
- Keep the HIDL enforcement (`media.c2.hal.selection=hidl`), the `media.settings.xml` late-boot re-apply (Phh `phh-on-data.sh` / `rw-system.sh` overwrites it), and the `mediaserver` SELinux allowances; those three mechanics are device-independent.

---

## Credits

Diagnosed and resolved through manual `adb`, `logcat`, and SELinux debugging combined with an AI-assisted debugging session.

---

## GitHub topics / tags (suggested)

For repo Settings → Topics, add:

`android`, `gsi`, `phh-gsi`, `treble`, `apatch`, `magisk`, `root`, `selinux`, `mediarecorder`, `camera2`, `codec2`, `video-recording-fix`, `mediaserver`, `sepolicy`

---

## Using This on Your Own Device (Help Grow This Repo)

Running a Phh GSI / Treble GSI on something other than the OnePlus Nord CE2 Lite 5G (CPH2381 / CPH2409, Snapdragon 695 / SM6375)? You're very welcome here — but please don't just flash the bundled `media_profiles_patched.xml` as-is. As explained in [How to adapt this module to another phone](#how-to-adapt-this-module-to-another-phone), that file encodes this phone's camera layout (`0, 2, 4`) and its stock OxygenOS vendor profile details. Your phone needs its own device-specific patched XML built from *its* stock OTA/vendor profiles, with AOSP-standard `1080p`/`720p`/`480p` quality names and *its* camera IDs — otherwise you'll just trade one `The given camcorder profile ... not found` error for another.

If that sounds like a lot of manual work, it doesn't have to be: paste your `getprop` / `grep quality=` / `logcat` outputs from the checklist above into an AI assistant (e.g. Gemini 3.8 Flash on a low-effort/fast setting, or anything similar) and ask it to walk you through pulling your own device's stock OTA, extracting the vendor `media_profiles` XML, converting the quality naming to AOSP-standard, and adjusting the camera IDs. It's the same process documented earlier in this README — an assistant can automate the boring parts and sanity-check the result for you.

And if you get your own device's fixed XML working, please help make this useful for as many people as possible: open a Pull Request adding it under a per-device folder, e.g. `system/etc/devices/<device-codename>/media_profiles_patched.xml` (plus a one-line note with your model, chipset, and GSI in the PR description). The goal is to grow this repo from a Nord CE2 Lite fix into a small community collection of known-good Treble GSI / Phh GSI media profiles — every new device helps the next person searching these exact error strings.
