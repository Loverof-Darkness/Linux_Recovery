#!/usr/bin/env bash
# GRUB validity checks and distribution-aware config generation.

# Canonical GRUB status constants
GRUB_STATUS_OK="GRUB_OK"
GRUB_STATUS_MISSING="GRUB_MISSING"
GRUB_STATUS_EMPTY="GRUB_EMPTY"
GRUB_STATUS_UNREADABLE="GRUB_UNREADABLE"
GRUB_STATUS_INACCESSIBLE="GRUB_INACCESSIBLE"
GRUB_STATUS_INVALID="GRUB_INVALID"
GRUB_STATUS_PRIVILEGE_REQUIRED="PRIVILEGE_REQUIRED"
GRUB_STATUS_TARGET_REQUIRED="GRUB_TARGET_ROOT_REQUIRED"

# Current GRUB status (set by grub_validate)
DEVIL_GRUB_STATUS="UNKNOWN"

grub_config_path() {
  local f path
  [[ "${DEVIL_TARGET_ROOT_SOURCE:-current}" != ambiguous ]] || return 1
  for f in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
    path=$(devil_target_path "$f") || return 1
    [[ -f "$path" ]] && { printf '%s' "$path"; return; }
  done
  return 1
}

grub_reference_token_is_path() {
  local token=$1
  [[ -z "$token" ]] && return 1
  # Kernel parameters like root=/dev/sda1 are not actual path references.
  [[ "$token" == *=* ]] && return 1
  if [[ "$token" == /* || "$token" == */* || "$token" == *vmlinuz* || "$token" == *bzImage* || "$token" == *initramfs* || "$token" == *initrd* || "$token" == *.efi || "$token" == *.img ]]; then
    return 0
  fi
  return 1
}

grub_root_subvolume_path() {
  local target=${1:-} options subvolume mount_target fstype relative
  [[ -n "$target" ]] || target=$(devil_target_root)
  options=$(findmnt -n -o OPTIONS --target "$target" 2>/dev/null || true)
  [[ -n "$options" ]] || options=$(findmnt -n -o OPTIONS "$target" 2>/dev/null || true)
  subvolume=$(printf '%s\n' "$options" | sed -n 's/.*\(^\|,\)subvol=\([^,]*\).*/\2/p')
  if [[ -n "$subvolume" ]]; then
    [[ "$subvolume" == /* ]] || subvolume="/$subvolume"
    printf '%s' "$subvolume"
    return 0
  fi

  fstype=$(findmnt -n -o FSTYPE --target "$target" 2>/dev/null || true)
  [[ -n "$fstype" ]] || fstype=$(findmnt -n -o FSTYPE "$target" 2>/dev/null || true)
  mount_target=$(findmnt -n -o TARGET --target "$target" 2>/dev/null || true)
  [[ -n "$mount_target" ]] || mount_target=$(findmnt -n -o TARGET "$target" 2>/dev/null || true)
  if [[ "$fstype" == btrfs && -n "$mount_target" && "$target" == "$mount_target"/* ]]; then
    relative=${target:${#mount_target}+1}
    [[ -n "$relative" ]] && printf '/%s' "$relative"
    return 0
  fi
  return 1
}

grub_reference_candidate_paths() {
  local token=$1 root_subvolume=${2:-} target=${3:-} candidate
  [[ -n "$target" ]] || target=$(devil_target_root)
  if [[ "$token" == /* ]]; then
    candidate=$token
    candidate=$(devil_target_path "$candidate") || return 1
    printf '%s\n' "$candidate"
    [[ -n "$root_subvolume" ]] || root_subvolume=$(grub_root_subvolume_path "$target" 2>/dev/null || true)
    if [[ -n "$root_subvolume" && "$token" == "$root_subvolume"/* ]]; then
      # GRUB records paths relative to the Btrfs top-level, while Linux has
      # mounted this subvolume as /.  /@/boot/vmlinuz therefore is /boot/vmlinuz
      # from the running system's view.
      candidate=${token#"$root_subvolume"}
      candidate=$(devil_target_path "$candidate") || return 1
      printf '%s\n' "$candidate"
    fi
    candidate="/boot$token"
    candidate=$(devil_target_path "$candidate") || return 1
    printf '%s\n' "$candidate"
  else
    candidate=$(devil_target_path "/boot/$token") || return 1
    printf '%s\n' "$candidate"
    candidate=$(devil_target_path "/$token") || return 1
    printf '%s\n' "$candidate"
  fi
}

grub_validate_reference() {
  local token=$1
  local command=$2
  local status
  local candidate

  if ! grub_reference_token_is_path "$token"; then
    printf '  NOT_A_REFERENCE [%s] %s\n' "$command" "$token"
    return 0
  fi

  while IFS= read -r candidate; do
    if [[ -f "$candidate" ]]; then
      printf '  VALID_REFERENCE [%s] %s -> %s\n' "$command" "$token" "$candidate"
      return 0
    fi
  done < <(grub_reference_candidate_paths "$token")

  if [[ "$token" == /* ]]; then
    status='UNRESOLVED_REFERENCE'
  else
    status='MISSING_REFERENCE'
  fi
  printf '  %s [%s] %s\n' "$status" "$command" "$token"
  return 1
}

grub_validate() {
  local cfg kernels initramfs_count boot_dir target
  local state
  local color_reset=${C_RESET:-}
  local color_white=${C_WHITE:-}
  local color_red=${C_RED:-}
  local color_green=${C_GREEN:-}
  local color_orange=${C_ORANGE:-}

  if [[ "${DEVIL_TARGET_ROOT_SOURCE:-current}" == ambiguous ]]; then
    DEVIL_GRUB_STATUS="$GRUB_STATUS_TARGET_REQUIRED"
    printf '%s✗%s Multiple mounted Linux roots were found; rerun with --target-root PATH.\n' "$color_orange" "$color_reset"
    if ((${#DEVIL_TARGET_ROOT_CANDIDATES[@]})); then
      printf '  Candidates: %s\n' "${DEVIL_TARGET_ROOT_CANDIDATES[*]}"
    fi
    return 6
  fi

  target=$(devil_target_root)
  boot_dir=$(devil_target_path /boot) || return 1
  printf '%sGRUB Configuration Check%s\n' "$color_white" "$color_reset"
  printf '========================\n'
  if [[ "$target" != / ]]; then
    printf 'Inspection target: %s\n' "$target"
  fi
  cfg=$(grub_config_path) || {
    DEVIL_GRUB_STATUS="$GRUB_STATUS_MISSING"
    printf '%s✗%s grub.cfg is missing\n' "$color_red" "$color_reset"
    return 1
  }

  if [[ ! -e "$cfg" ]]; then
      DEVIL_GRUB_STATUS="$GRUB_STATUS_MISSING"; printf '%s✗%s grub.cfg is missing\n' "$color_red" "$color_reset"
    return 1
  fi

  if [[ ! -s "$cfg" ]]; then
      DEVIL_GRUB_STATUS="$GRUB_STATUS_EMPTY"; printf '%s✗%s grub.cfg is empty\n' "$color_red" "$color_reset"
    return 4
  fi

  if [[ ! -r "$cfg" && ${EUID:-0} -ne 0 ]]; then
      DEVIL_GRUB_STATUS="$GRUB_STATUS_PRIVILEGE_REQUIRED"; printf '%s✗%s grub.cfg exists but cannot currently be validated because access is denied%s\n' "$color_red" "$color_reset" ""
    return 3
  fi

  if [[ ! -r "$cfg" ]]; then
    if ! cat "$cfg" >/dev/null 2>/dev/null; then
        DEVIL_GRUB_STATUS="$GRUB_STATUS_INACCESSIBLE"; printf '%s✗%s grub.cfg exists but cannot currently be inspected%s\n' "$color_red" "$color_reset" ""
      return 5
    fi
  fi

  printf '%s✓%s grub.cfg: readable non-empty file (%s)\n' "$color_green" "$color_reset" "$cfg"

  local menu_count
  menu_count=$(grep -c '^menuentry' "$cfg" 2>/dev/null || echo 0)
  printf '  Menu entries: %s\n' "$menu_count"

  printf '\nBoot artifacts in %s:\n' "$boot_dir"
  kernels=$(find "$boot_dir" -maxdepth 2 -type f \( -name 'vmlinuz*' -o -name 'bzImage' \) 2>/dev/null | wc -l)
  initramfs_count=$(find "$boot_dir" -maxdepth 2 -type f \( -name 'initramfs*' -o -name 'initrd*' \) 2>/dev/null | wc -l)

  if ((kernels > 0)); then
    printf '%s✓%s Found %d kernel(s)\n' "$color_green" "$color_reset" "$kernels"
  else
    printf '%s✗%s No kernels found%s\n' "$color_red" "$color_reset" ""
  fi

  if ((initramfs_count > 0)); then
    printf '%s✓%s Found %d initramfs/initrd(s)\n' "$color_green" "$color_reset" "$initramfs_count"
  else
    printf '%s✗%s No initramfs found%s\n' "$color_red" "$color_reset" ""
  fi

  if grep -q '^### BEGIN /etc/grub.d/30_os-prober' "$cfg" 2>/dev/null; then
    printf '%s✓%s os-prober entries found\n' "$color_green" "$color_reset"
  fi

  local syntax_ok=1
  if have grub2-script-check; then
    if ! grub2-script-check "$cfg" >/dev/null 2>&1; then
      printf '%s✗%s Configuration syntax has errors%s\n' "$color_red" "$color_reset" ""
      syntax_ok=0
    else
      printf '%s✓%s Configuration syntax is valid\n' "$color_green" "$color_reset"
    fi
  elif have grub-script-check; then
    if ! grub-script-check "$cfg" >/dev/null 2>&1; then
      printf '%s✗%s Configuration syntax has errors%s\n' "$color_red" "$color_reset" ""
      syntax_ok=0
    else
      printf '%s✓%s Configuration syntax is valid\n' "$color_green" "$color_reset"
    fi
  fi

  printf '\nValidating file references:\n'
  local all_valid=1
  local line command rest token

  while IFS= read -r line; do
    line=${line%%#*}
    line=${line%%$'\r'}
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^[[:space:]]*(linux|linuxefi)[[:space:]]+([^[:space:]]+) ]]; then
      command=${BASH_REMATCH[1]}
      token=${BASH_REMATCH[2]}
      if ! grub_validate_reference "$token" "$command"; then
        all_valid=0
      fi
    elif [[ "$line" =~ ^[[:space:]]*(initrd|initrdefi)[[:space:]]+([^[:space:]]+) ]]; then
      command=${BASH_REMATCH[1]}
      token=${BASH_REMATCH[2]}
      if ! grub_validate_reference "$token" "$command"; then
        all_valid=0
      fi
    fi
  done < "$cfg"

  if [[ $syntax_ok -eq 0 || $all_valid -eq 0 ]]; then
    DEVIL_GRUB_STATUS="$GRUB_STATUS_INVALID"
    return 2
  fi

  DEVIL_GRUB_STATUS="$GRUB_STATUS_OK"
  return 0
}

grub_generator() {
  if have grub-mkconfig; then
    echo grub-mkconfig
    return 0
  elif have grub2-mkconfig; then
    echo grub2-mkconfig
    return 0
  else
    return 1
  fi
}

grub_regenerate() {
  local confirmed=0
  [[ "${1:-}" == '--confirmed' ]] && confirmed=1
  if devil_target_root_is_offline; then
    printf '%s✗%s Refusing to run the live environment GRUB generator against mounted target %s.\n' "$C_RED" "$C_RESET" "$(devil_target_root)"
    printf 'Use the guided live-environment reinstall instead; it runs the target tools inside a reviewed chroot.\n'
    return 1
  fi
  require_root
  local cfg gen backup
  cfg=$(grub_config_path) || die 'cannot regenerate: no existing grub.cfg found'
  gen=$(grub_generator) || die 'GRUB config generator is not installed'
  
  printf '%sGRUB Configuration Regeneration%s\n' "$C_WHITE" "$C_RESET"
  printf '===============================\n'
  printf 'Existing config: %s\n' "$cfg"
  printf 'Using generator: %s\n\n' "$gen"
  
  # Create backup
  backup=$(devil_safe_backup_file "$cfg" grub.cfg) || die "backup failed"
  log_info "backed up $cfg to $backup"
  printf '%s✓%s Backup created: %s\n' "$C_GREEN" "$C_RESET" "$(basename "$backup")"
  
  # Callers that already collected an explicit, user-visible approval (such as
  # Automatic Recovery's privilege gate) can avoid a duplicate prompt.
  if (( ! confirmed )); then
    confirm "Regenerate GRUB configuration?" || return 1
  fi
  
  # Regenerate
  if run_action "regenerate GRUB configuration" "$gen" -o "$cfg"; then
    printf '%s✓%s GRUB regenerated successfully.%s\n' "$C_GREEN" "$C_RESET" ""
    log_info "GRUB regenerated successfully"
    return 0
  else
    printf '%s✗%s Regeneration failed. Attempting to restore backup.%s\n' "$C_RED" "$C_RESET" ""
    if run_action "restore GRUB configuration after failed regeneration" cp --preserve=mode,timestamps -- "$backup" "$cfg"; then
      printf '%s✓%s Backup restored.%s\n' "$C_GREEN" "$C_RESET" ""
      log_info "GRUB restore from backup succeeded"
    else
      die "GRUB regeneration and backup restore both failed"
    fi
    return 1
  fi
}

grub_detect_distribution() {
  devil_target_os_release_value ID 2>/dev/null || echo "unknown"
}

grub_list_entries() {
  local cfg
  cfg=$(grub_config_path) || { echo 'No GRUB configuration found'; return 1; }
  
  printf '%sGRUB Menu Entries%s\n' "$C_WHITE" "$C_RESET"
  printf '=================\n'
  
  grep '^menuentry' "$cfg" | while IFS= read -r line; do
    # Extract title from menuentry line
    if [[ $line =~ menuentry[[:space:]]\"([^\"]+)\" ]]; then
      printf '  • %s\n' "${BASH_REMATCH[1]}"
    fi
  done
}

grub_check_os_prober() {
  local cfg
  cfg=$(grub_config_path) || { echo 'No GRUB configuration found'; return 1; }
  
  printf '%sChecking os-prober status%s\n' "$C_WHITE" "$C_RESET"
  printf '=========================\n'
  
  if have os-prober; then
    printf '%s✓%s os-prober is installed\n' "$C_GREEN" "$C_RESET"
  else
    printf '%s✗%s os-prober is not installed%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
  
  if grep -q '/30_os-prober' "$cfg" 2>/dev/null; then
    printf '%s✓%s os-prober output is in grub.cfg\n' "$C_GREEN" "$C_RESET"
  else
    printf '%s✗%s os-prober output not detected%s\n' "$C_ORANGE" "$C_RESET" ""
  fi
}

grub_restore_from_backup() {
  local backup_dir
  if devil_target_root_is_offline; then
    printf '%s✗%s Restoring directly to mounted target %s is disabled.\n' "$C_RED" "$C_RESET" "$(devil_target_root)"
    return 1
  fi
  backup_dir="$DEVIL_BACKUP_DIR"
  
  printf '%sGRUB Restore from Backup%s\n' "$C_WHITE" "$C_RESET"
  printf '========================\n'
  printf 'Available backups:\n'
  
  find "$backup_dir" -maxdepth 1 -name '*grub*' -type f | sort | while read -r backup; do
    printf '  • %s (%s bytes)\n' "$(basename "$backup")" "$(wc -c <"$backup")"
  done
  
  printf '\nEnter backup filename (press Ctrl+C to cancel): '
  read -r backup_name
  
  backup="$backup_dir/$backup_name"
  # recovery_rollback_grub is the sole restore path.  It verifies that the
  # candidate is a non-symlink regular file within the backup directory and
  # routes the write through run_action, making --test/--safe/--dry-run safe.
  recovery_rollback_grub "$backup"
}

grub_display_kernel_options() {
  local cfg
  cfg=$(grub_config_path) || { echo 'No GRUB configuration found'; return 1; }
  
  printf '%sKernel Boot Options%s\n' "$C_WHITE" "$C_RESET"
  printf '===================\n'
  
  grep '^[[:space:]]*linux' "$cfg" | head -5 | while read -r line; do
    # Show just the first linux entry
    printf '  %s\n' "$line"
  done
}

grub_needs_regeneration() {
  local cfg
  cfg=$(grub_config_path 2>/dev/null) || return 0
  
  # If config doesn't exist, regeneration not needed
  if [[ ! -f "$cfg" ]]; then
    return 0
  fi
  
  # If config is very small, likely needs regeneration
  local size
  size=$(wc -c <"$cfg")
  if ((size < 100)); then
    return 1  # Needs regeneration
  fi
  
  # Check for minimal menu entries
  local entries
  entries=$(grep -c '^menuentry' "$cfg" 2>/dev/null || echo 0)
  if ((entries < 1)); then
    return 1  # Needs regeneration
  fi
  
  return 0  # Seems fine
}
