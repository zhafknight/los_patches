# Merge notes

## Inputs

- `n7000-los23.2-patches-v1.1.zip`
- `lineage-diff-20260727.zip`
- `skipped.tsv`

## Restored after merge

The following two `frameworks/native` patches were initially removed because they appeared in `skipped.tsv`, but were restored by request:

1. `frameworks/native/012` — Revert genTextures/deleteTextures removal
2. `frameworks/native/014` — Forward-port GLES RenderEngine to Android 16 QPR2

They retain their original order and SHA-256 values from v1.1. This restores the intended RenderEngine ancestry for patches 013, 015, 016, and 018.

## Exact skipped patches still removed

1. `system/core/027` — cap SELinux policy version on pre-4.9 kernels
2. `system/core/028` — strip xperms CIL rules
3. `system/core/029` — fix xperms CIL keyword matching
4. `packages/modules/Connectivity/044` — broader CLAT legacy permission compatibility patch

The first row in the supplied `skipped.tsv` was `unknown / system/core / skipped / unknown`. It has no hash or patch path, so no additional file can be safely removed from that row. It remains recorded in `UNKNOWN_SKIPPED.tsv`.

## Local lineage diffs appended

Patches 087–094 contain the supplied local diffs for bionic, frameworks/base, frameworks/av, hardware/ril, Connectivity, system/apex, system/netd, and vendor/lineage. They are converted to normal mail patches so the existing `apply.sh` can use `git am`.

## Overlap handling

- Standard Connectivity patch 044 remains removed. The supplied local Connectivity diff is retained because it is distinct and only changes the final `fatal` handling from `abort()` to `return`.
- The supplied `system/netd` diff expects the `exit(1)` change from standard patch 053, so it remains appended later in the order.

## User-provided patches added after N7000 pruning

Patches 097–098 are user-provided raw diffs added for the N7000 build:

- `097` (`external/chromium-webview`) removes the `optional_uses_libs` list from the prebuilt WebView import.
- `098` (`system/linkerconfig`) exposes `libicuuc.so` and `libgui.so` to the vendor default namespace for the legacy GPS daemon.

The supplied raw diffs were wrapped as normal mail patches so the existing `apply.sh` can continue to use `git am`; the diff hunks themselves are unchanged.
