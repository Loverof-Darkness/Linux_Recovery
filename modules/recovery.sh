#!/usr/bin/env bash
# Recovery policy and rollback orchestration.
#
# DEVIL intentionally separates diagnosis from repair. This module never chooses
# a bootloader package or overwrites an EFI loader; it coordinates the narrow,
# reversible repair routines provided by grub.sh and efi.sh.

recovery_simulation_active() { ((DEVIL_DRY_RUN || DEVIL_TEST || DEVIL_SAFE)); }

recovery_mode_label() {
  local env=${DEVIL_ENVIRONMENT_CLASS:-UNKNOWN}
  local label
  case "$env" in
    INSTALLED_SYSTEM) label='installed system' ;;
    LIVE_ISO) label='live' ;;
    CHROOT) label='chroot' ;;
    *) label='unknown' ;;
  esac
  if ((DEVIL_TEST)); then
    printf 'test simulation (%s)' "$label"
  elif ((DEVIL_DRY_RUN)); then
    printf 'dry-run (%s)' "$label"
  elif ((DEVIL_SAFE)); then
    printf 'safe simulation (%s)' "$label"
  else
    printf '%s' "$label"
  fi
}

recovery_list_backups() {
  local file found=0
  printf 'DEVIL backup inventory (%s)\n' "$DEVIL_BACKUP_DIR"
  while IFS= read -r -d '' file; do
    found=1
    printf '%s\t%s bytes\n' "$(basename -- "$file")" "$(wc -c <"$file")"
  done < <(find "$DEVIL_BACKUP_DIR" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
  ((found)) || printf 'No backups have been created in this state directory.\n'
}

recovery_health_assessment() {
  local cfg validation skip_diagnostics=0
  local color_white=${C_WHITE:-}
  local color_reset=${C_RESET:-}
  local color_green=${C_GREEN:-}
  local color_orange=${C_ORANGE:-}
  local color_gray=${C_GRAY:-}
  [[ "${1:-}" == '--skip-diagnostics' ]] && skip_diagnostics=1
  ((skip_diagnostics)) || diagnostics_collect
  printf '%sRecovery Health Assessment%s\n' "$color_white" "$color_reset"
  printf '===========================\n'
  printf 'Mode: %s\n\n' "$(recovery_mode_label)"
  printf 'Firmware: %s\nRoot: %s\n' "${DIAG[firmware]:-unknown}" "${DIAG[root]:-unknown}"
  printf 'Inspection target: %s\n' "${DIAG[target_description]:-$(devil_target_description)}"
  if [[ -n "${DIAG[boot_target]:-}" ]]; then
    printf 'Boot target: %s\n' "${DIAG[boot_target]}"
  fi
  printf 'Environment: %s\n' "${DEVIL_ENVIRONMENT_CLASS:-UNKNOWN}"
  cfg=$(grub_config_path 2>/dev/null || true)
  if [[ -z "$cfg" ]]; then
    printf '%sGRUB Configuration: Not found%s\n' "$color_orange" "$color_reset"
    printf '  DEVIL will not install a new bootloader automatically.\n'
  else
     printf '%sGRUB Configuration: Found%s\n' "$color_green" "$color_reset"
     printf '  Status: %s\n' "${DIAG[grub_status]:-GRUB_UNKNOWN}"
     printf '  Summary: %s\n' "$(printf '%s' "${DIAG[grub]}" | head -1)"
  fi
  if [[ "${DIAG[firmware]:-}" == UEFI ]]; then
    if efi_available 2>/dev/null; then
      printf '%sEFI: Available%s\n' "$color_green" "$color_reset"
      if [[ "${DIAG[boot_target]:-}" == *"Windows Boot Manager"* ]]; then
        printf '%sBoot note:%s firmware currently prefers Windows Boot Manager; use a live USB to repair the Linux boot path.\n' "$color_orange" "$color_reset"
      fi
    else
      printf '%sEFI: Unavailable%s\n' "$color_orange" "$color_reset"
      printf '  UEFI is active, but EFI variable access is not available.\n'
    fi
  else
    printf '%sEFI: Not in UEFI mode%s\n' "$color_gray" "$color_reset"
  fi
  printf '\n%sPolicy:%s DEVIL regenerates existing GRUB configurations only when\n' "$color_white" "$color_reset"
  printf 'validation reports damage. Every change requires root, a backup, and confirmation.\n'
}

recovery_plan() {
  local dev opts name found=0
  recovery_health_assessment
  printf '\nInstalled Linux systems available for guided recovery:\n'
  while IFS=$'\t' read -r dev opts name; do
    [[ -n "$dev" ]] || continue
    printf '  - %s: %s (%s)\n' "$name" "$dev" "$opts"
    found=1
  done < <(recovery_discover_linux_roots)
  ((found)) || printf '  None found (unlock encrypted storage first, if applicable).\n'
  if [[ -n "${DEVIL_RECOVERY_ROOT_SPEC:-}" ]]; then
    printf 'Selected repair system: %s\n' "${DEVIL_RECOVERY_ROOT_SPEC%%|*}"
  fi
  printf '\n'
  recovery_automatic --dry-run --skip-health
}

recovery_advanced_grub() {
  local selection action
  while :; do
    terminal_select_menu 'Advanced GRUB Recovery' \
      'Validate GRUB configuration (read-only)' \
      'Regenerate GRUB configuration (root required)' \
      'Restore GRUB from backup (root required)' \
      'List DEVIL backups (read-only)' \
      'Exit to main menu' || return 0
    selection=$DEVIL_MENU_SELECTION

    case "$selection" in
      0) action='Validate GRUB configuration' ;;
      1) action='Regenerate GRUB configuration' ;;
      2) action='Restore GRUB from backup' ;;
      3) action='List DEVIL backups' ;;
      4) return 0 ;;
    esac
    if ! recovery_advanced_confirm_action "$action"; then
      printf '%sAction cancelled.%s\n' "$C_GRAY" "$C_RESET"
      devil_pause 'Press Enter to return to Advanced GRUB Recovery...'
      continue
    fi

    case "$selection" in
      0) grub_validate ;;
      1)
        if [[ ${EUID:-999} -ne 0 ]]; then
          recovery_root_required 'Regenerate GRUB configuration'
        else
          grub_regenerate
        fi
        ;;
      2)
        if [[ ${EUID:-999} -ne 0 ]]; then
          recovery_root_required 'Restore GRUB from backup'
        else
          recovery_restore_grub
        fi
        ;;
      3) recovery_list_backups ;;
    esac
    devil_pause 'Press Enter to return to Advanced GRUB Recovery...'
  done
}

recovery_advanced_confirm_action() {
  local action=$1
  printf '\n%sSelected:%s %s\n' "$C_CYAN" "$C_RESET" "$action"
  confirm "Continue with this action?"
}

recovery_root_required() {
  local action=$1
  # This is intentionally a UI-level guard.  Calling require_root here would
  # terminate DEVIL through die(), rather than returning the user to the menu.
  printf '\n%s⚠ This operation requires root; rerun with sudo.%s\n' "$C_ORANGE" "$C_RESET"
  printf '%sRoot privileges are required to: %s%s\n' "$C_ORANGE" "$action" "$C_RESET"
  printf '%sAction not run:%s %s\n' "$C_RED" "$C_RESET" "$action"
  printf '%sReturn to the dashboard and relaunch DEVIL with sudo only when you are ready to make a reviewed change.%s\n' "$C_GRAY" "$C_RESET"
}

recovery_efi_confirm_action() {
  local action=$1
  printf '\n%sSelected:%s %s\n' "$C_CYAN" "$C_RESET" "$action"
  confirm "Continue with this action?"
}

recovery_restore_grub() {
  local backup
  
  printf '%sAvailable GRUB backups:%s\n' "$C_WHITE" "$C_RESET"
  find "$DEVIL_BACKUP_DIR" -maxdepth 1 -name 'grub.cfg-*' -type f -exec ls -lh {} \;
  
  printf '\nEnter backup filename to restore (or press Ctrl+C to cancel): '
  read -r backup_name
  
  backup="$DEVIL_BACKUP_DIR/$backup_name"
  # Delegate to the single guarded restore implementation.  It rejects paths
  # outside DEVIL_BACKUP_DIR, creates a pre-restore backup, confirms with the
  # user, and honours all simulation modes.
  recovery_rollback_grub "$backup"
}

recovery_efi_manager() {
  local selection order id

  while :; do
    terminal_select_menu 'EFI Boot Entry Manager' \
      'List boot entries (read-only)' \
      'Set BootOrder (root required)' \
      'Delete boot entry (root required)' \
      'Back up EFI entries (root required)' \
      'Exit to main menu' || return 0
    selection=$DEVIL_MENU_SELECTION

    case "$selection" in
      0)
        recovery_efi_confirm_action 'List boot entries' &&
          efi_list || true
        ;;
      1)
        if ! recovery_efi_confirm_action 'Set BootOrder'; then
          :
        elif [[ ${EUID:-999} -ne 0 ]]; then
          recovery_root_required 'Set EFI BootOrder'
        else
          printf '%sEnter BootOrder%s (comma-separated hex IDs, e.g. 0001,0002): ' "$C_CYAN" "$C_RESET"
          read -r order
          [[ -n "$order" ]] && efi_set_order "$order" || true
        fi
        ;;
      2)
        if ! recovery_efi_confirm_action 'Delete a boot entry'; then
          :
        elif [[ ${EUID:-999} -ne 0 ]]; then
          recovery_root_required 'Delete an EFI boot entry'
        else
          printf '%sEnter boot entry ID%s (4-digit hex, e.g. 0001): ' "$C_CYAN" "$C_RESET"
          read -r id
          [[ -n "$id" ]] && efi_delete "$id" || true
        fi
        ;;
      3)
        if ! recovery_efi_confirm_action 'Back up EFI entries'; then
          :
        elif [[ ${EUID:-999} -ne 0 ]]; then
          recovery_root_required 'Back up EFI entries'
        elif efi_backup; then
          printf '%s✓ EFI backup created.%s\n' "$C_GREEN" "$C_RESET"
        fi
        ;;
      4) return 0 ;;
    esac

    devil_pause 'Press Enter to return to EFI Boot Entry Manager...'
  done
}

recovery_filesystem_check() {
  printf '%sFilesystem Check%s\n' "$C_WHITE" "$C_RESET"
  printf '=================\n'
  printf '\n%sCurrent filesystem mounts:%s\n' "$C_WHITE" "$C_RESET"
  findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS | sed 's/^/  /'
  printf '\n%sStorage summary:%s\n' "$C_WHITE" "$C_RESET"
  filesystem_summary | sed 's/^/  /'
  read -p "Press Enter to continue..."
}

recovery_restore_efi_from_backup() {
  local backup
  printf '%sEFI Restore from Backup%s\n' "$C_WHITE" "$C_RESET"
  printf 'Available EFI backups:\n'
  find "$DEVIL_BACKUP_DIR" -maxdepth 1 -name 'efi-*.txt' -type f -exec ls -lh {} \;
  printf '\n'
}

recovery_bootorder_repair() {
  printf '%sBootOrder Repair%s\n' "$C_WHITE" "$C_RESET"
  printf '=================\n'
  
  if ! efi_available; then
    printf '%sEFI variables not available on this system.%s\n' "$C_ORANGE" "$C_RESET"
    return 1
  fi
  
  printf '%sCurrently available boot entries:%s\n' "$C_WHITE" "$C_RESET"
  efi_list
  
  printf '\n%sTo change BootOrder, use the EFI Manager menu.%s\n' "$C_GRAY" "$C_RESET"
}

recovery_grub_is_damaged() {
  local validation_output
  if ! validation_output=$(grub_validate 2>&1); then
    return 0
  fi
  return 1
}

recovery_grub_install_needed() {
  # Missing config is always a reinstall case. In UEFI mode also verify that
  # firmware still has a Linux loader entry; Windows updates can remove or
  # supersede it while leaving grub.cfg untouched.
  grub_config_path >/dev/null 2>&1 || return 0
  [[ "${DIAG[firmware]:-}" != UEFI ]] && return 1
  if ! efi_available 2>/dev/null; then
    return 1
  fi
  local output target_efi
  output=$(efibootmgr -v 2>/dev/null || true)
  printf '%s\n' "$output" | grep -Eiq 'Boot[0-9A-Fa-f]{4}[^[:cntrl:]]*(grub|garuda|fedora|ubuntu|debian|linux)' || return 0
  target_efi=$(devil_target_path /boot/efi/EFI) || return 1
  if [[ -d "$target_efi" ]] && ! find "$target_efi" -type f \( -iname 'grub*.efi' -o -iname 'shim*.efi' \) -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

recovery_automatic() {
  local dry_run=0 skip_health=0 confirmed=0 arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --skip-health) skip_health=1 ;;
      --confirmed) confirmed=1 ;;
    esac
  done

  ((skip_health)) || recovery_health_assessment
  if [[ "${DEVIL_TARGET_ROOT_SOURCE:-current}" == ambiguous ]]; then
    printf '\nAutomatic repair is disabled until a mounted Linux target is selected with --target-root PATH.\n'
    return 0
  fi
  if devil_target_root_is_offline; then
    printf '\nMounted target inspection is read-only: %s\n' "$(devil_target_root)"
    printf 'Automatic GRUB writes are disabled so live-environment tools cannot modify the target with the wrong runtime context.\n'
    printf 'Use the guided live-environment reinstall for a reviewed chrooted repair.\n'
    return 0
  fi
  # A common Windows-update failure is a healthy GRUB file with firmware
  # BootOrder changed to Windows. Offer a narrowly scoped order repair before
  # touching GRUB; all existing entries remain in the resulting order.
  if [[ "${DIAG[firmware]:-}" == UEFI ]] && efi_available 2>/dev/null &&
     [[ "${DIAG[boot_target]:-}" == *"Windows Boot Manager"* ]]; then
    if ((dry_run)) || recovery_simulation_active; then
      printf '\nDEVIL would back up EFI variables and move the detected Linux/GRUB entry before Windows in BootOrder.\n'
    elif ((confirmed)); then
      efi_repair_bootorder --confirmed || return 1
    else
      efi_repair_bootorder || return 1
    fi
  fi
  if ! grub_config_path >/dev/null 2>&1 || recovery_grub_install_needed; then
    if grub_config_path >/dev/null 2>&1; then
      printf '\nGRUB configuration exists, but no Linux/GRUB EFI loader entry is present.\n'
    else
      printf '\nGRUB configuration is missing.\n'
    fi
    printf 'A guided reinstall will select the Linux root, ESP, and firmware mode before running grub-install.\n'
    if ((dry_run)) || recovery_simulation_active; then
      printf 'DEVIL would probe Linux and EFI partitions, show the mapping, then run a chrooted grub-install after confirmation.\n'
    elif ((confirmed)); then
      recovery_reinstall_grub || return 1
    else
      if confirm 'Attempt guided live-environment GRUB reinstall?'; then
        recovery_reinstall_grub || return 1
      fi
    fi
    return 0
  fi

  local validation_output
    local gs
    gs="${DIAG[grub_status]:-GRUB_UNKNOWN}"
    if [[ "$gs" == "${GRUB_STATUS_OK}" ]]; then
      printf '\nNo automatic repair was selected: the existing GRUB configuration appears healthy.\n'
      return 0
    fi

    if [[ "$gs" == "${GRUB_STATUS_PRIVILEGE_REQUIRED}" || "$gs" == "${GRUB_STATUS_UNREADABLE}" || "$gs" == "${GRUB_STATUS_INACCESSIBLE}" ]]; then
      printf '\nAutomatic repair cannot be attempted: GRUB configuration access is restricted and cannot be verified safely.\n'
      return 0
    fi

    if [[ "$gs" == "${GRUB_STATUS_EMPTY}" ]]; then
      printf '\nA damaged or incomplete existing GRUB configuration was detected (empty grub.cfg).\n'
    else
      printf '\nA damaged or incomplete existing GRUB configuration was detected.\n'
    fi

  if ((dry_run)) || recovery_simulation_active; then
    printf 'DEVIL would back up and regenerate the existing configuration; no command will run in %s mode.\n' "$(recovery_mode_label)"
    return 0
  fi

  if ((confirmed)); then
    grub_regenerate --confirmed
  else
    grub_regenerate
  fi
}

# Discover installed Linux roots without leaving anything mounted. Output is
# tab-separated: device, safe read-only mount options, distribution name.
recovery_discover_linux_roots() {
  local dev fstype mp opts name
  while read -r dev fstype; do
    [[ -b "$dev" ]] || continue
    mp=$(mktemp -d "${TMPDIR:-/tmp}/devil-root.XXXXXX") || return 1
    if [[ "$fstype" == btrfs ]]; then
      # Garuda and other Btrfs installations normally use @ or @root.
      for opts in 'ro,subvol=@' 'ro,subvol=@root' 'ro'; do
        if mount -o "$opts" "$dev" "$mp" 2>/dev/null && devil_path_is_linux_root "$mp"; then
          name=$(awk -F= '$1 == "PRETTY_NAME" { sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit }' "$mp/etc/os-release")
          [[ -n "$name" ]] || name='Linux'
          printf '%s\t%s\t%s\n' "$dev" "$opts" "$name"
          break
        fi
        umount "$mp" 2>/dev/null || true
      done
    elif mount -o ro "$dev" "$mp" 2>/dev/null && devil_path_is_linux_root "$mp"; then
      name=$(awk -F= '$1 == "PRETTY_NAME" { sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit }' "$mp/etc/os-release")
      [[ -n "$name" ]] || name='Linux'
      printf '%s\tro\t%s\n' "$dev" "$name"
    fi
    umount "$mp" 2>/dev/null || true; rmdir "$mp" 2>/dev/null || true
  done < <(lsblk -rpno PATH,FSTYPE 2>/dev/null | awk '$2 ~ /^(ext[234]|btrfs|xfs|f2fs)$/ {print $1, $2}')
}

# Locate an installed Linux root and EFI System Partition from a live ISO.
# Probing is read-only; a candidate is accepted only when it contains
# /etc/os-release and a boot directory, avoiding guesses based on filesystem
# type alone.
recovery_find_linux_root() {
  local dev opts name choice i
  local -a candidates=()
  mapfile -t candidates < <(recovery_discover_linux_roots)
  ((${#candidates[@]})) || return 1
  if ((${#candidates[@]} == 1)); then
    IFS=$'\t' read -r dev opts name <<<"${candidates[0]}"
    printf '%s|%s\n' "$dev" "$opts"
    return 0
  fi
  printf 'Multiple Linux installations were detected:\n' >&2
  for i in "${!candidates[@]}"; do
    IFS=$'\t' read -r dev opts name <<<"${candidates[i]}"
    printf '  %d) %s — %s (%s)\n' "$((i + 1))" "$name" "$dev" "$opts" >&2
  done
  printf 'Select the installation to repair [1-%d]: ' "${#candidates[@]}" >&2
  read -r choice
  [[ "$choice" =~ ^[0-9]+$ && choice -ge 1 && choice -le ${#candidates[@]} ]] || return 1
  IFS=$'\t' read -r dev opts name <<<"${candidates[$((choice - 1))]}"
  printf '%s|%s\n' "$dev" "$opts"
}

recovery_prepare_storage() {
  local dev name
  if have cryptsetup; then
    while read -r dev; do
      [[ -b "$dev" ]] || continue
      name="devil-$(basename "$dev")"
      printf 'Encrypted volume detected: %s\n' "$dev"
      confirm "Unlock this LUKS volume?" || continue
      cryptsetup luksOpen "$dev" "$name" || return 1
    done < <(lsblk -rpno PATH,FSTYPE 2>/dev/null | awk '$2 == "crypto_LUKS" {print $1}')
  fi
  if have vgchange && have pvs; then
    if pvs --noheadings >/dev/null 2>&1 && confirm 'Activate detected LVM volume groups?'; then
      vgchange -ay || return 1
    fi
  fi
  if have mdadm && [[ -r /proc/mdstat ]] && grep -q '^md' /proc/mdstat; then
    confirm 'Assemble available software RAID arrays?' && mdadm --assemble --scan || true
  fi
}

recovery_secure_boot_ready() {
  local state root=${1:-/}
  have mokutil || return 0
  state=$(mokutil --sb-state 2>/dev/null || true)
  [[ "$state" != *enabled* ]] && return 0
  # DEVIL may reuse a trusted loader, but never creates or enrolls signing
  # keys. Refuse when no standard signed loader is visible on the mounted ESP.
  if find "$root/boot/efi/EFI" -type f \( -iname 'shimx64.efi' -o -iname 'grubx64.efi' -o -iname 'bootx64.efi' -o -iname 'bootmgfw.efi' \) -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  printf 'Secure Boot is enabled, but no trusted EFI loader was found.\n'
  printf 'Install/use your distribution signed shim first; DEVIL will not enroll keys.\n'
  return 1
}

recovery_fstab_source() {
  local target=$1 mountpoint=$2 spec
  spec=$(awk -v mountpoint="$mountpoint" '
    /^[[:space:]]*#/ || NF < 2 { next }
    { sub(/[[:space:]]+#.*/, "") }
    $2 == mountpoint { print $1; exit }
  ' "$target/etc/fstab" 2>/dev/null || true)
  [[ -n "$spec" ]] || return 1
  case "$spec" in
    UUID=*) blkid -U "${spec#UUID=}" 2>/dev/null || return 1 ;;
    PARTUUID=*) blkid -t "$spec" -o device 2>/dev/null | head -1 ;;
    LABEL=*) blkid -L "${spec#LABEL=}" 2>/dev/null || return 1 ;;
    /dev/*) [[ -b "$spec" ]] && printf '%s\n' "$spec" || return 1 ;;
    *) return 1 ;;
  esac
}

recovery_same_disk_efi_partition() {
  local root_device=$1 parent candidates=()
  parent=$(lsblk -ndo PKNAME "$root_device" 2>/dev/null || true)
  [[ -n "$parent" ]] || return 1
  while read -r dev fstype device_parent; do
    [[ "$fstype" == vfat || "$fstype" == fat32 ]] || continue
    [[ "$device_parent" == "$parent" ]] || continue
    candidates+=("$dev")
  done < <(lsblk -rpno PATH,FSTYPE,PKNAME 2>/dev/null)
  ((${#candidates[@]} == 1)) || return 1
  printf '%s\n' "${candidates[0]}"
}

recovery_find_efi_partition() {
  local target=${1:-} root_device=${2:-} device
  [[ -n "$target" && -n "$root_device" ]] || return 1
  device=$(recovery_fstab_source "$target" /boot/efi 2>/dev/null || true)
  [[ -n "$device" ]] || device=$(recovery_fstab_source "$target" /efi 2>/dev/null || true)
  if [[ -n "$device" && -b "$device" ]]; then
    printf '%s\n' "$device"
    return 0
  fi
  recovery_same_disk_efi_partition "$root_device"
}

recovery_loader_id() {
  local target=$1 id candidate
  for candidate in "$target"/boot/efi/EFI/*; do
    [[ -d "$candidate" ]] || continue
    id=${candidate##*/}
    [[ "$id" == BOOT || "$id" == Microsoft ]] && continue
    [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    printf '%s\n' "$id"
    return 0
  done
  id=$(awk -F= '$1 == "ID" { sub(/^[^=]*=/, ""); print; exit }' "$target/etc/os-release" 2>/dev/null || true)
  id=${id#\"}
  id=${id%\"}
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || id=Linux
  printf '%s\n' "$id"
}

recovery_reinstall_grub() {
  local root_spec root_device root_options boot_device efi_device target generator firmware backup loader_id
  local mounted_boot=0 cleanup_rc=0
  require_root
  have mount || { printf 'Required command missing: mount\n'; return 1; }
  have umount || { printf 'Required command missing: umount\n'; return 1; }
  have chroot || { printf 'Required command missing: chroot\n'; return 1; }
  have blkid || { printf 'Required command missing: blkid\n'; return 1; }
  if [[ "${DIAG[firmware]:-UEFI}" == UEFI ]] && ! have efibootmgr; then
    printf 'efibootmgr is required for UEFI recovery. Boot the live ISO in UEFI mode and install it first.\n'
    return 1
  fi
  recovery_prepare_storage || return 1
  root_spec=${1:-${DEVIL_RECOVERY_ROOT_SPEC:-}}
  [[ -n "$root_spec" ]] || root_spec=$(recovery_find_linux_root) || { printf 'No Linux root found.\n'; return 1; }
  root_device=${root_spec%%|*}; root_options=${root_spec#*|}
  [[ "$root_options" == "$root_spec" ]] && root_options=rw
  efi_device=${2:-}
  target=${DEVIL_RECOVERY_MOUNT:-/mnt/devil-recovery}
  [[ "$target" == /mnt/* || "$target" == /tmp/* ]] || { printf 'Refusing unsafe recovery mount point: %s\n' "$target"; return 1; }
  mkdir -p "$target" || return 1
  if find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
    printf 'Refusing non-empty recovery mount point: %s\n' "$target"
    return 1
  fi
  local firmware=${DIAG[firmware]:-UEFI}
  if [[ "$firmware" == BIOS ]]; then
    printf 'Linux root: %s (%s)\nFirmware: BIOS (legacy)\nMount point: %s\n' "$root_device" "$root_options" "$target"
  else
    [[ -n "$efi_device" && -b "$efi_device" ]] || efi_device=''
  fi
  if recovery_simulation_active; then
    printf 'Linux root: %s (%s)\nFirmware: %s\nMount point: %s\n' "$root_device" "$root_options" "$firmware" "$target"
    confirm 'Simulate mounting these partitions and reinstalling GRUB?' || return 1
    printf 'SIMULATED: mount, chroot, grub-install, and grub-mkconfig\n'
    return 0
  fi
  mount -o ro,"${root_options#ro,}" "$root_device" "$target" || return 1
  boot_device=$(recovery_fstab_source "$target" /boot 2>/dev/null || true)
  if [[ -n "$boot_device" && "$boot_device" != "$root_device" ]]; then
    mkdir -p "$target/boot"
    mount -o ro "$boot_device" "$target/boot" || { umount -R "$target" 2>/dev/null || true; return 1; }
    mounted_boot=1
  fi
  if [[ "$firmware" != BIOS && -z "$efi_device" ]]; then
    efi_device=$(recovery_find_efi_partition "$target" "$root_device" 2>/dev/null || true)
  fi
  if [[ "$firmware" != BIOS ]]; then
    [[ -n "$efi_device" && -b "$efi_device" ]] || { printf 'No unambiguous EFI System Partition found for %s.\n' "$root_device"; umount -R "$target" 2>/dev/null || true; return 1; }
    mkdir -p "$target/boot/efi"
    mount -o ro "$efi_device" "$target/boot/efi" || { umount -R "$target" 2>/dev/null || true; return 1; }
    loader_id=$(recovery_loader_id "$target")
  fi
  printf 'Linux root: %s (%s)\n' "$root_device" "$root_options"
  [[ "$mounted_boot" == 1 ]] && printf 'Separate /boot: %s\n' "$boot_device"
  if [[ "$firmware" != BIOS ]]; then
    printf 'EFI System Partition: %s\nEFI loader ID: %s\n' "$efi_device" "$loader_id"
  fi
  printf 'Mount point: %s\n' "$target"
  # The ESP is mounted during the mapping probe, so perform this check before
  # unmounting it.  Checking after cleanup would inspect an empty mount point
  # and incorrectly reject Secure Boot-capable installations.
  if [[ "$firmware" != BIOS ]] && ! recovery_secure_boot_ready "$target"; then
    umount -R "$target" 2>/dev/null || true
    return 1
  fi
  umount -R "$target" 2>/dev/null || { printf 'Could not finish read-only mapping probe; refusing repair.\n'; return 1; }
  if ! confirm 'Mount these partitions and reinstall GRUB?'; then
    return 1
  fi
  mount -o "${root_options/ro/rw}" "$root_device" "$target" || return 1
  if [[ -n "$boot_device" && "$boot_device" != "$root_device" ]]; then
    mount "$boot_device" "$target/boot" || { umount -R "$target" 2>/dev/null || true; return 1; }
  fi
  if [[ "$firmware" != BIOS ]]; then
    mount "$efi_device" "$target/boot/efi" || { umount -R "$target" 2>/dev/null || true; return 1; }
  fi
  mount --rbind /dev "$target/dev" || { umount -R "$target" 2>/dev/null || true; return 1; }
  mount --make-rslave "$target/dev" || { umount -R "$target" 2>/dev/null || true; return 1; }
  mount --rbind /proc "$target/proc" || { umount -R "$target" 2>/dev/null || true; return 1; }
  mount --make-rslave "$target/proc" || { umount -R "$target" 2>/dev/null || true; return 1; }
  mount --rbind /sys "$target/sys" || { umount -R "$target" 2>/dev/null || true; return 1; }
  mount --make-rslave "$target/sys" || { umount -R "$target" 2>/dev/null || true; return 1; }
  mount --rbind /run "$target/run" || { umount -R "$target" 2>/dev/null || true; return 1; }
  mount --make-rslave "$target/run" || { umount -R "$target" 2>/dev/null || true; return 1; }
  if [[ -f "$target/boot/grub/grub.cfg" ]]; then
    backup=$(devil_safe_backup_file "$target/boot/grub/grub.cfg" 'target-grub.cfg') || {
      umount -R "$target" 2>/dev/null || true
      printf 'Could not back up target GRUB configuration; no changes made.\n'
      return 1
    }
    printf 'Target GRUB backup: %s\n' "$backup"
  fi
  # `command` is a shell builtin, so it must be evaluated by a shell inside
  # the chroot.  Invoking it directly makes every valid target look as though
  # grub-install is absent.
  chroot "$target" sh -c 'command -v grub-install' >/dev/null 2>&1 || {
    umount -R "$target" 2>/dev/null || true
    printf 'grub-install is missing inside the target system. Install the distribution GRUB package first.\n'
    return 1
  }
  generator=$(chroot "$target" sh -c 'command -v grub-mkconfig || command -v grub2-mkconfig' 2>/dev/null) || generator=''
  [[ -n "$generator" ]] || { umount -R "$target" 2>/dev/null || true; printf 'No grub-mkconfig generator exists inside the target.\n'; return 1; }
  if [[ "$firmware" == BIOS ]]; then
    local disk
    disk=$(lsblk -ndo PKNAME "$root_device" 2>/dev/null | head -1)
    [[ -n "$disk" ]] || { umount -R "$target" 2>/dev/null || true; printf 'Cannot determine BIOS boot disk.\n'; return 1; }
    chroot "$target" grub-install --target=i386-pc "/dev/$disk" --recheck || { umount -R "$target" 2>/dev/null || true; return 1; }
  else
    chroot "$target" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$loader_id" --recheck || { umount -R "$target" 2>/dev/null || true; return 1; }
  fi
  chroot "$target" "$generator" -o /boot/grub/grub.cfg || { umount -R "$target" 2>/dev/null || true; return 1; }
  umount -R "$target" 2>/dev/null || cleanup_rc=1
  ((cleanup_rc == 0)) || { printf 'Recovery completed, but cleanup failed; inspect mounts below %s.\n' "$target"; return 1; }
  printf 'GRUB reinstalled and configuration regenerated successfully.\n'
}

recovery_validate_backup() {
  local backup=$1
  [[ -f "$backup" && ! -L "$backup" ]] || { log_error "backup is not a regular file: $backup"; return 1; }
  devil_is_path_within "$backup" "$DEVIL_BACKUP_DIR" || { log_error "backup lies outside DEVIL backup directory"; return 1; }
}

recovery_rollback_grub() {
  local backup=$1 cfg
  if devil_target_root_is_offline; then
    printf '%s✗%s Restoring directly to mounted target %s is disabled.\n' "$C_RED" "$C_RESET" "$(devil_target_root)"
    return 1
  fi
  require_root
  recovery_validate_backup "$backup" || die "invalid backup selected"
  cfg=$(grub_config_path) || die 'no current GRUB configuration to restore'
  [[ -f "$cfg" ]] || die "GRUB configuration is not a regular file: $cfg"
  confirm "Restore $cfg from $(basename -- "$backup")?" || { printf 'Rollback cancelled.\n'; return 0; }
  # Back up the current state first so rollback itself is reversible.
  local pre_restore
  pre_restore=$(devil_safe_backup_file "$cfg" 'grub-before-rollback')
  log_info "saved pre-rollback GRUB configuration to $pre_restore"
  run_action "restore GRUB configuration from $(basename -- "$backup")" cp --preserve=mode,timestamps -- "$backup" "$cfg"
}

# Backwards-compatible public name retained for scripted users.
recovery_rollback() { recovery_rollback_grub "$@"; }
