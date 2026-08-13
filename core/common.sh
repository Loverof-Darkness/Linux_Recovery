#!/usr/bin/env bash
# Shared safety, filesystem and process helpers. These helpers are intentionally
# dependency-light because DEVIL is often launched from a minimal live image.

declare -a DEVIL_TARGET_ROOT_CANDIDATES=()

die() { log_error "$*"; printf 'DEVIL: %s\n' "$*" >&2; exit 1; }
debug() { [[ "${DEVIL_DEBUG:-0}" == 1 ]] && { log_debug "$*"; printf '[debug] %s\n' "$*" >&2; } || true; }
have() { command -v "$1" >/dev/null 2>&1; }
shell_quote() { printf '%q' "$1"; }

json_escape() {
  local value=${1-}
  value=${value//\\/\\\\}; value=${value//\"/\\\"}; value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}; value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

devil_target_root() {
  local target=${DEVIL_TARGET_ROOT:-/}
  [[ -d "$target" ]] || target=/
  printf '%s' "$target"
}

devil_target_root_is_offline() {
  [[ "$(devil_target_root)" != / ]]
}

devil_target_path() {
  local path=$1 target
  [[ "$path" == /* ]] || return 1
  case "$path" in
    *'/../'*|../*|..|*/..) return 1 ;;
  esac
  target=$(devil_target_root)
  if [[ "$target" == / ]]; then
    printf '%s' "$path"
  else
    printf '%s%s' "$target" "$path"
  fi
}

devil_target_os_release_value() {
  local key=$1 file value
  [[ "${DEVIL_TARGET_ROOT_SOURCE:-current}" != ambiguous ]] || return 1
  file=$(devil_target_path /etc/os-release) || return 1
  [[ -r "$file" ]] || return 1
  value=$(awk -F= -v requested_key="$key" '$1 == requested_key { sub(/^[^=]*=/, ""); print; exit }' "$file")
  value=${value#\"}
  value=${value%\"}
  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

devil_path_is_linux_root() {
  local target=$1
  [[ -d "$target" && -r "$target/etc/os-release" && -d "$target/boot" ]]
}

devil_mount_source_is_live() {
  case "$1" in
    /dev/loop*|*squashfs*|overlay|overlayfs|none|tmpfs|rootfs) return 0 ;;
  esac
  return 1
}

devil_mounted_linux_roots() {
  local target source fstype child
  local -A seen=()

  while IFS=' ' read -r target source fstype; do
    [[ -n "$target" && "$target" != / && -d "$target" ]] || continue
    [[ "$source" == /dev/* ]] || continue
    devil_mount_source_is_live "$source" && continue

    if devil_path_is_linux_root "$target" && [[ -z "${seen[$target]+set}" ]]; then
      seen["$target"]=1
      printf '%s\n' "$target"
    fi

    [[ "$fstype" == btrfs ]] || continue
    for child in "$target"/*; do
      [[ -d "$child" ]] || continue
      if devil_path_is_linux_root "$child" && [[ -z "${seen[$child]+set}" ]]; then
        seen["$child"]=1
        printf '%s\n' "$child"
      fi
    done
  done < <(findmnt -rn -o TARGET,SOURCE,FSTYPE 2>/dev/null || true)
}

devil_normalize_target_root() {
  local target=$1
  [[ -d "$target" ]] || return 1
  (cd -P -- "$target" && pwd)
}

devil_select_target_root() {
  local requested=${1:-} selected
  local -a candidates=()

  DEVIL_TARGET_ROOT=/
  DEVIL_TARGET_ROOT_SOURCE=current
  DEVIL_TARGET_ROOT_CANDIDATES=()

  if [[ -n "$requested" ]]; then
    selected=$(devil_normalize_target_root "$requested") || return 1
    devil_path_is_linux_root "$selected" || return 1
    DEVIL_TARGET_ROOT=$selected
    DEVIL_TARGET_ROOT_SOURCE=explicit
    return 0
  fi

  [[ "${DEVIL_ENVIRONMENT_CLASS:-UNKNOWN}" == LIVE_ISO ]] || return 0
  mapfile -t candidates < <(devil_mounted_linux_roots)
  DEVIL_TARGET_ROOT_CANDIDATES=("${candidates[@]}")

  case "${#candidates[@]}" in
    0) return 0 ;;
    1)
      selected=$(devil_normalize_target_root "${candidates[0]}") || return 1
      DEVIL_TARGET_ROOT=$selected
      DEVIL_TARGET_ROOT_SOURCE=auto
      return 0
      ;;
    *)
      DEVIL_TARGET_ROOT_SOURCE=ambiguous
      return 0
      ;;
  esac
}

devil_target_description() {
  local target source
  target=$(devil_target_root)
  source=${DEVIL_TARGET_ROOT_SOURCE:-current}
  case "$source" in
    auto) printf 'mounted Linux root: %s (auto-selected)' "$target" ;;
    explicit) printf 'mounted Linux root: %s (selected explicitly)' "$target" ;;
    ambiguous) printf 'multiple mounted Linux roots; select one with --target-root' ;;
    *) printf 'current environment root: /' ;;
  esac
}

devil_strip_ansi() {
  # Saved reports must remain portable plain text, even when diagnostics were
  # collected from the colour-enabled interactive UI.
  sed $'s/\033\\[[0-?]*[ -\/]*[@-~]//g'
}

devil_now_ms() {
  if have date && date +%s%3N >/dev/null 2>&1; then date +%s%3N; else printf '%s000' "$(date +%s)"; fi
}

devil_init_dirs() {
  local requested_data=$DEVIL_DATA_DIR
  if ! mkdir -p -- "$DEVIL_LOG_DIR" "$DEVIL_BACKUP_DIR" "$DEVIL_CONFIG_DIR" 2>/dev/null; then
    # A readonly HOME is common on Live media. State can safely be volatile;
    # reports deliberately remain tied to the tool directory below.
    DEVIL_DATA_DIR=$(mktemp -d "${TMPDIR:-/tmp}/devil-${UID:-0}.XXXXXX") || die "cannot allocate volatile state directory"
    DEVIL_CONFIG_DIR="$DEVIL_DATA_DIR/config"; DEVIL_LOG_DIR="$DEVIL_DATA_DIR/logs"
    DEVIL_BACKUP_DIR="$DEVIL_DATA_DIR/backups"
    mkdir -p -- "$DEVIL_LOG_DIR" "$DEVIL_BACKUP_DIR" "$DEVIL_CONFIG_DIR" || die "cannot create writable state directory"
    DEVIL_WARNINGS+=("state directory $requested_data is unavailable; using volatile $DEVIL_DATA_DIR")
  fi
  if ! mkdir -p -- "$DEVIL_REPORT_DIR" 2>/dev/null || [[ ! -w "$DEVIL_REPORT_DIR" ]]; then
    DEVIL_REPORT_WRITABLE=0
    DEVIL_WARNINGS+=("project reports directory is not writable; reports and audits will not be saved: $DEVIL_REPORT_DIR")
  fi
  chmod 700 -- "$DEVIL_DATA_DIR" "$DEVIL_CONFIG_DIR" "$DEVIL_BACKUP_DIR" 2>/dev/null || true
}

require_root() { [[ ${EUID:-999} -eq 0 ]] || die "this operation requires root; rerun with sudo"; }

confirm() {
  local prompt=${1:-Continue?} answer
  [[ -t 0 ]] || { log_warn "refused non-interactive destructive action: $prompt"; return 1; }
  printf '%s [y/N] ' "$prompt" >&2
  IFS= read -r answer || return 1
  [[ "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

devil_pause() {
  local prompt=${1:-Press Enter to continue...}
  if [[ -t 0 ]]; then
    printf '%s%s%s' "${C_DIM:-}" "$prompt" "${C_RESET:-}" >&2
    read -r _ || true
    printf '\n'
  else
    printf '%s%s%s\n' "${C_DIM:-}" "$prompt" "${C_RESET:-}"
  fi
}

devil_assert_regular_file() { [[ -f "$1" && ! -L "$1" ]] || die "expected a regular file: $1"; }

devil_safe_backup_file() {
  # Usage: devil_safe_backup_file SOURCE [LABEL]. Backup names contain no user
  # controlled path segments and preserve mode/timestamps for a reliable restore.
  local source=$1 label=${2:-backup} stamp destination
  devil_assert_regular_file "$source"
  stamp=$(date +%Y%m%d-%H%M%S)
  label=${label//[^A-Za-z0-9._-]/_}
  destination="$DEVIL_BACKUP_DIR/${label}-${stamp}-$$"
  if ((DEVIL_TEST || DEVIL_DRY_RUN)); then
    log_info "simulated backup of $source to $destination"
    printf '%s' "$destination"
    return 0
  fi
  cp --preserve=mode,timestamps -- "$source" "$destination" || die "failed to back up $source"
  printf '%s' "$destination"
}

devil_is_path_within() {
  local candidate=$1 base=$2 resolved_candidate resolved_base
  [[ -e "$candidate" && -d "$base" ]] || return 1
  resolved_candidate=$(readlink -f -- "$candidate") || return 1
  resolved_base=$(readlink -f -- "$base") || return 1
  [[ "$resolved_candidate" == "$resolved_base"/* || "$resolved_candidate" == "$resolved_base" ]]
}

run_action() {
  # Records start/end/exit status for every mutating action. Simulation modes
  # never execute the supplied command.
  local description=$1; shift
  local started ended status=0 action_output=''
  DEVIL_ACTIONS+=("$description")
  if ((DEVIL_TEST || DEVIL_DRY_RUN || DEVIL_SAFE)); then
    log_action "$description" simulated 0 0
    printf '%sSIMULATED:%s %s\n' "${C_CYAN:-}" "${C_RESET:-}" "$description"
    return 0
  fi
  started=$(devil_now_ms); log_info "running action: $description"
  # Mutating commands are non-interactive. Capture their output once so it is
  # still shown to the operator and is available in the report-directory audit.
  if [[ -n "${DEVIL_AUDIT_FILE:-}" ]]; then
    action_output=$(mktemp "${TMPDIR:-/tmp}/devil-action.XXXXXX") || return 1
    if "$@" >"$action_output" 2>&1; then status=0; else status=$?; fi
    cat "$action_output"
    printf '\n--- action transcript: %s ---\n' "$description" >>"$DEVIL_AUDIT_FILE"
    devil_strip_ansi <"$action_output" >>"$DEVIL_AUDIT_FILE"
    printf '\n--- end action transcript (exit %s) ---\n' "$status" >>"$DEVIL_AUDIT_FILE"
    rm -f -- "$action_output"
  elif "$@"; then
    status=0
  else
    status=$?
  fi
  ended=$(devil_now_ms)
  log_action "$description" completed "$status" "$((ended - started))"
  if ((status != 0)); then
    log_error "action failed ($status): $description"
    return "$status"
  fi
  return 0
}
