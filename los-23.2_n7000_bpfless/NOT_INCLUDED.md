# Patches intentionally not included

- All patches from `galaxys2-patches-lineage-20.0`.
- All `device/phh/treble`, Treble App, and GSI product-configuration changes.
- Qualcomm-, MediaTek-, OPlus-, and Xiaomi-specific patches.
- Samsung AIDL camera ID and multi-camera patches, because the N7000 uses the legacy Camera HAL1 stack.
- microG, `su` user-build SELinux policy changes, and tweaks that are not required for boot compatibility.
- Duplicate legacy cgroup patches when the more complete GSI equivalent is already included.
- The legacy `Do-not-require-BTF-on-pre-5.15` patch, because the GSI Connectivity patch set already modifies the same `NetBpfLoad.cpp` area.

A complete Camera HAL1 implementation, legacy FunctionFS ADB support, and Audio HAL 2.0 are not available in the two LineageOS 23.2 source patch collections used for this pack.
