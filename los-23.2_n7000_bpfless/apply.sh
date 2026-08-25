#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.tsv"
TOP="${ANDROID_BUILD_TOP:-$PWD}"
MODE="apply"
ALL=0
SELECTED_GROUPS=()

usage() {
  cat <<'USAGE'
Usage: ./n7000-los23.2-patches/apply.sh [option]

Default: apply all recommended N7000 patches.

Options:
  --check              Check repositories and patch state only
  --list               List included patches
  --status             Show active git-am and saved patch state
  --group NAME         Apply one group; may be repeated
  --all                Include optional patches
  --continue           Continue one active git-am session and record it
  --skip               Skip one active git-am patch and record the skip
  --abort              Abort all active git-am sessions; keep completed commits
  --top PATH           LineageOS source root
  -h, --help           Show this help

Groups: core, bpf, storage, graphics, media, bluetooth, hardware,
        display, audio, bluetooth-extra, vintf, tweaks
USAGE
}

while (($#)); do
  case "$1" in
    --check) MODE="check" ;;
    --list) MODE="list" ;;
    --status) MODE="status" ;;
    --all) ALL=1 ;;
    --group)
      [[ $# -ge 2 ]] || { echo "ERROR: --group requires a name"; exit 2; }
      SELECTED_GROUPS+=("$2"); shift ;;
    --continue) MODE="continue" ;;
    --skip) MODE="skip" ;;
    --abort) MODE="abort" ;;
    --top)
      [[ $# -ge 2 ]] || { echo "ERROR: --top requires a path"; exit 2; }
      TOP="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

list_rows() {
  printf '%-4s %-11s %-16s %-36s %s\n' 'No.' 'Profile' 'Group' 'Repository' 'Patch'
  while IFS=$'\t' read -r order profile group repo patch origin sha rationale; do
    [[ -z "$order" || "$order" == \#* ]] && continue
    printf '%-4s %-11s %-16s %-36s %s\n' "$order" "$profile" "$group" "$repo" "$(basename "$patch")"
  done < "$MANIFEST"
}

if [[ "$MODE" == "list" ]]; then
  list_rows
  exit 0
fi

TOP="$(cd -- "$TOP" 2>/dev/null && pwd)" || { echo "ERROR: source root not found"; exit 1; }
if [[ ! -d "$TOP/.repo" || ! -d "$TOP/build/make" ]]; then
  echo "ERROR: $TOP does not look like a LineageOS source root."
  echo "Run this from the source root or use --top PATH."
  exit 1
fi

STATE_DIR="$TOP/.n7000-patch-state"
LOG_DIR="$STATE_DIR/logs"
APPLIED_FILE="$STATE_DIR/applied.tsv"
PENDING_FILE="$STATE_DIR/pending.tsv"
SKIPPED_FILE="$STATE_DIR/skipped.tsv"
mkdir -p "$LOG_DIR"
touch "$APPLIED_FILE" "$SKIPPED_FILE"
LOG_FILE="$LOG_DIR/apply-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

is_selected() {
  local profile="$1" group="$2"
  if ((${#SELECTED_GROUPS[@]})); then
    local g
    for g in "${SELECTED_GROUPS[@]}"; do
      [[ "$g" == "$group" ]] && return 0
    done
    return 1
  fi
  [[ "$profile" == "recommended" ]] && return 0
  ((ALL == 1)) && return 0
  return 1
}

unique_repos() {
  awk -F '\t' '!/^#/ && NF>=4 {print $4}' "$MANIFEST" | awk '!seen[$0]++'
}

git_path_abs() {
  git -C "$TOP/$1" rev-parse --path-format=absolute --git-path "$2" 2>/dev/null
}

has_am_session() {
  local p
  p="$(git_path_abs "$1" rebase-apply)" || return 1
  [[ -d "$p" ]]
}

patch_subject() {
  awk '
    /^Subject: / {
      sub(/^Subject: /, "")
      sub(/^\[PATCH[^]]*\][[:space:]]*/, "")
      print
      exit
    }
  ' "$1"
}

state_has() {
  local sha="$1" repo="$2"
  awk -F '\t' -v s="$sha" -v r="$repo" '$1==s && $2==r {f=1} END{exit !f}' "$APPLIED_FILE" ||
  awk -F '\t' -v s="$sha" -v r="$repo" '$1==s && $2==r {f=1} END{exit !f}' "$SKIPPED_FILE"
}

record_applied() {
  local sha="$1" repo="$2" status="$3" patch_rel="$4"
  state_has "$sha" "$repo" && return 0
  printf '%s\t%s\t%s\t%s\n' "$sha" "$repo" "$status" "$patch_rel" >> "$APPLIED_FILE"
}

find_active_repos() {
  while IFS= read -r repo; do
    [[ -d "$TOP/$repo" ]] || continue
    has_am_session "$repo" && printf '%s\n' "$repo"
  done < <(unique_repos)
}

if [[ "$MODE" == "status" ]]; then
  echo "Source root: $TOP"
  active="$(find_active_repos || true)"
  if [[ -n "$active" ]]; then
    echo "Active git-am repositories:"
    printf '%s\n' "$active"
  else
    echo "No active git-am session."
  fi
  if [[ -s "$PENDING_FILE" ]]; then
    echo "Pending patch:"
    cat "$PENDING_FILE"
  fi
  echo "Applied records: $(wc -l < "$APPLIED_FILE")"
  echo "Skipped records: $(wc -l < "$SKIPPED_FILE")"
  exit 0
fi

if [[ "$MODE" == "abort" ]]; then
  found=0
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    echo "Aborting git am in $repo"
    git -C "$TOP/$repo" am --abort || {
      echo "WARNING: normal abort failed in $repo; removing stale rebase-apply metadata only."
      rp="$(git_path_abs "$repo" rebase-apply)"
      rm -rf -- "$rp"
    }
    found=1
  done < <(find_active_repos || true)
  rm -f "$PENDING_FILE"
  ((found)) || echo "No active git-am session found."
  echo "Completed patch commits were not reset."
  exit 0
fi

continue_or_skip() {
  local action="$1" active count repo
  active="$(find_active_repos || true)"
  count="$(printf '%s\n' "$active" | sed '/^$/d' | wc -l)"
  [[ "$count" -gt 0 ]] || { echo "No active git-am session found."; exit 1; }
  [[ "$count" -eq 1 ]] || {
    echo "ERROR: more than one active git-am session exists:"
    printf '%s\n' "$active"
    echo "Resolve or abort them individually."
    exit 1
  }
  repo="$active"

  if [[ "$action" == "continue" ]]; then
    echo "Continuing git am in $repo"
    git -C "$TOP/$repo" am --continue
    if [[ -s "$PENDING_FILE" ]]; then
      IFS=$'\t' read -r sha pending_repo patch_rel < "$PENDING_FILE"
      if [[ "$pending_repo" == "$repo" ]]; then
        head="$(git -C "$TOP/$repo" rev-parse HEAD)"
        record_applied "$sha" "$repo" "$head" "$patch_rel"
      fi
    fi
  else
    echo "Skipping active git-am patch in $repo"
    if [[ -s "$PENDING_FILE" ]]; then
      IFS=$'\t' read -r sha pending_repo patch_rel < "$PENDING_FILE"
    else
      sha="unknown"; pending_repo="$repo"; patch_rel="unknown"
    fi
    git -C "$TOP/$repo" am --skip
    printf '%s\t%s\t%s\t%s\n' "$sha" "$repo" "skipped" "$patch_rel" >> "$SKIPPED_FILE"
  fi
  rm -f "$PENDING_FILE"
  echo "Done. Run apply.sh again to process the remaining patches."
}

if [[ "$MODE" == "continue" ]]; then continue_or_skip continue; exit 0; fi
if [[ "$MODE" == "skip" ]]; then continue_or_skip skip; exit 0; fi

# Refuse to start while any repository has unfinished git-am metadata.
active="$(find_active_repos || true)"
if [[ -n "$active" ]]; then
  echo "ERROR: unfinished git-am session detected:"
  printf '%s\n' "$active"
  echo "Use apply.sh --continue, --skip, or --abort first."
  exit 1
fi

# Validate selected repositories once.
declare -A CHECKED=()
while IFS=$'\t' read -r order profile group repo patch origin sha rationale; do
  [[ -z "$order" || "$order" == \#* ]] && continue
  is_selected "$profile" "$group" || continue
  [[ -n "${CHECKED[$repo]:-}" ]] && continue
  CHECKED[$repo]=1
  if [[ ! -d "$TOP/$repo" ]] || ! git -C "$TOP/$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: missing Git repository: $repo"
    exit 1
  fi
  if [[ -n "$(git -C "$TOP/$repo" status --porcelain --untracked-files=no)" ]]; then
    echo "ERROR: tracked changes are not committed in $repo"
    echo "Commit or stash them before applying patches."
    exit 1
  fi
  echo "READY: $repo"
done < "$MANIFEST"

if [[ "$MODE" == "check" ]]; then
  echo "Check complete. Selected repositories are present and clean."
  echo "Log: $LOG_FILE"
  exit 0
fi

count=0
skipped=0
while IFS=$'\t' read -r order profile group repo patch_rel origin sha rationale; do
  [[ -z "$order" || "$order" == \#* ]] && continue
  is_selected "$profile" "$group" || continue
  patch="$SCRIPT_DIR/$patch_rel"
  [[ -f "$patch" ]] || { echo "ERROR: missing patch file: $patch_rel"; exit 1; }
  actual_sha="$(sha256sum "$patch" | awk '{print $1}')"
  [[ "$actual_sha" == "$sha" ]] || { echo "ERROR: checksum mismatch: $patch_rel"; exit 1; }

  if state_has "$sha" "$repo"; then
    echo "SKIP state: [$group] $repo/$(basename "$patch")"
    ((skipped+=1))
    continue
  fi

  if git -C "$TOP/$repo" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "SKIP already applied: [$group] $repo/$(basename "$patch")"
    record_applied "$sha" "$repo" "existing" "$patch_rel"
    ((skipped+=1))
    continue
  fi

  subject="$(patch_subject "$patch")"
  if [[ -n "$subject" ]]; then
    existing_head="$(git -C "$TOP/$repo" log -n 300 --fixed-strings --grep="^${subject}$" --format='%H' -n 1 2>/dev/null || true)"
    if [[ -n "$existing_head" ]]; then
      echo "SKIP commit subject: [$group] $repo/$(basename "$patch")"
      record_applied "$sha" "$repo" "$existing_head" "$patch_rel"
      ((skipped+=1))
      continue
    fi
  fi

  echo
  echo "APPLY [$order][$group][$origin] $repo/$(basename "$patch")"
  echo "      $rationale"
  printf '%s\t%s\t%s\n' "$sha" "$repo" "$patch_rel" > "$PENDING_FILE"
  if ! git -C "$TOP/$repo" am -3 --ignore-whitespace "$patch"; then
    echo
    echo "FAILED in repository: $repo"
    echo "Patch: $patch_rel"
    echo "Resolve conflicts, git add the fixed files, then run:"
    echo "  $SCRIPT_DIR/apply.sh --continue --top '$TOP'"
    echo "To skip this patch:"
    echo "  $SCRIPT_DIR/apply.sh --skip --top '$TOP'"
    echo "To discard the failed patch only:"
    echo "  $SCRIPT_DIR/apply.sh --abort --top '$TOP'"
    echo "Log: $LOG_FILE"
    exit 1
  fi
  head="$(git -C "$TOP/$repo" rev-parse HEAD)"
  record_applied "$sha" "$repo" "$head" "$patch_rel"
  rm -f "$PENDING_FILE"
  ((count+=1))
done < "$MANIFEST"

echo
echo "Done. Applied: $count, skipped: $skipped"
echo "Log: $LOG_FILE"
