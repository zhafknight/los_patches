Note: This patch pack does not guarantee that LineageOS 23.2 will boot successfully or run without bugs on your device.

This pack is specifically prepared for the **Samsung Galaxy Note GT-N7000 / Exynos 4210**, using patches taken from the following three **LineageOS 23.2** patch collections:

- https://github.com/MisterZtr/LineageOS_gsi/tree/lineage-23.2/patches/
- https://github.com/Ultra-Legacy-Hippeastrum/legacy_support_patches
- https://github.com/J0SH1X/n7000_android_16_patches
- https://github.com/rINanDO/galaxys2-patches.git (as referrence)

## Default contents

`./apply.sh` applies every patch with the `recommended` profile by default, including:

- legacy-kernel, cgroup v1, and process-group compatibility
- BPF-less networking, netd, and DNS resolver compatibility
- legacy SELinux, APEX, and dm-verity compatibility
- text relocations, ashmem, Binder, and legacy HIDL compatibility
- GLES RenderEngine and SurfaceFlinger support for legacy GPUs
- software OMX codecs and selected camera/Bluetooth compatibility fixes
- RIL v6/v8/v9, Broadcom Wi-Fi, and `mkbootimg --dt` support

## Usage

Place this folder in the root of your LineageOS 23.2 source tree, then run:

```bash
cd /path/to/lineage-23.2
chmod +x n7000-los23.2-patches/apply.sh
./n7000-los23.2-patches/apply.sh --check
./n7000-los23.2-patches/apply.sh
```

The source tree must be clean. Commit or stash your own changes before applying the patch pack.

To apply only one patch group:

```bash
./n7000-los23.2-patches/apply.sh --group core
./n7000-los23.2-patches/apply.sh --group bpf
./n7000-los23.2-patches/apply.sh --group graphics
```

To include optional patches as well:

```bash
./n7000-los23.2-patches/apply.sh --all
```

To display the complete patch list:

```bash
./n7000-los23.2-patches/apply.sh --list
```

If `git am` reports a conflict, fix the affected files in the repository shown by the script, then run:

```bash
git add <fixed-file>
git am --continue
cd /path/to/lineage-23.2
./n7000-los23.2-patches/apply.sh
```

Alternatively, abort the active `git am` session with:

```bash
./n7000-los23.2-patches/apply.sh --abort
```

## Important limitations

This pack **does not contain a complete Camera HAL1 implementation**, because neither of the two LineageOS 23.2 source collections provides one. The `Camera-Add-feature-extensions` patch only restores legacy camera enums and commands.

This pack also does not provide a complete implementation of:

- legacy ADB FunctionFS
- legacy Audio HAL 2.0
- the complete legacy Wi-Fi HIDL stack

The pack therefore addresses the core old-kernel, BPF, cgroup, and other LineageOS 23.2 compatibility requirements, but those three components may still need to be ported separately if your device requires them.

## Notes

`apply.sh` uses `git am -3 --ignore-whitespace`. It checks for missing repositories, refuses to start when tracked source changes are uncommitted, and skips patches that have already been applied. State and logs are stored under `.n7000-patch-state/` in the LineageOS source root.

## Recovering after a failed v1 run

From the LineageOS source root:

```bash
./n7000-los23.2-patches/apply.sh --abort --top "$PWD"
./n7000-los23.2-patches/apply.sh --check --top "$PWD"
./n7000-los23.2-patches/apply.sh --top "$PWD"
```

The script keeps completed patch commits and resumes by detecting commits that have already been applied.
