#!/usr/bin/env bash
# Multi-boot detection and validation without modification or unmounting.
# Detects major Linux distributions, Windows, and other operating systems.

declare -A MULTIBOOT_SYSTEMS=()
declare -a MULTIBOOT_ORDER=()
MULTIBOOT_WINDOWS_BOOT_MANAGER=0

multiboot_scan_partitions() {
  local dev fstype label
  local old_ifs=$IFS
  IFS=$' \t\n'

  unset MULTIBOOT_SYSTEMS MULTIBOOT_ORDER 2>/dev/null || true
  declare -gA MULTIBOOT_SYSTEMS=()
  declare -ga MULTIBOOT_ORDER=()
  MULTIBOOT_WINDOWS_BOOT_MANAGER=0

  while IFS=$'\t' read -r dev fstype label; do
    [[ -n "$dev" && -b "$dev" ]] || continue
    case "$fstype" in
      ext2|ext3|ext4)
        multiboot_probe_linux_ext "$dev" "$label"
        ;;
      btrfs)
        multiboot_probe_linux_btrfs "$dev" "$label"
        ;;
      xfs)
        multiboot_probe_linux_xfs "$dev" "$label"
        ;;
      f2fs)
        multiboot_probe_linux_f2fs "$dev" "$label"
        ;;
      ntfs)
        multiboot_probe_windows "$dev" "$label"
        ;;
      vfat)
        multiboot_probe_efi_or_boot "$dev" "$label"
        ;;
    esac
  done < <(devil_parse_lsblk_entries)
  if multiboot_windows_boot_manager_present >/dev/null 2>&1; then
    MULTIBOOT_WINDOWS_BOOT_MANAGER=1
  fi
  IFS=$old_ifs
}

multiboot_probe_linux_ext() {
  local device=$1 label=${2:-Unknown}
  local mount_point os_name version
  
  mount_point=$(mktemp -d) || return 1
  if mount -r "$device" "$mount_point" 2>/dev/null; then
    if [[ -f "$mount_point/etc/os-release" ]]; then
      os_name=$(grep '^NAME=' "$mount_point/etc/os-release" | cut -d'=' -f2 | tr -d '"')
      version=$(grep '^VERSION_ID=' "$mount_point/etc/os-release" | cut -d'=' -f2 | tr -d '"')
      MULTIBOOT_SYSTEMS["$device"]="$os_name ${version:-} on $label"
      MULTIBOOT_ORDER+=("$device")
    fi
    umount "$mount_point" 2>/dev/null || true
  fi
  rmdir "$mount_point" 2>/dev/null || true
}

multiboot_probe_linux_btrfs() {
  local device=$1 label=${2:-Unknown}
  local mount_point os_name version
  
  mount_point=$(mktemp -d) || return 1
  if mount -r -t btrfs "$device" "$mount_point" 2>/dev/null; then
    if [[ -f "$mount_point/etc/os-release" ]]; then
      os_name=$(grep '^NAME=' "$mount_point/etc/os-release" | cut -d'=' -f2 | tr -d '"')
      version=$(grep '^VERSION_ID=' "$mount_point/etc/os-release" | cut -d'=' -f2 | tr -d '"')
      MULTIBOOT_SYSTEMS["$device"]="$os_name ${version:-} (Btrfs) on $label"
      MULTIBOOT_ORDER+=("$device")
    fi
    umount "$mount_point" 2>/dev/null || true
  fi
  rmdir "$mount_point" 2>/dev/null || true
}

multiboot_probe_linux_xfs() {
  local device=$1 label=${2:-Unknown}
  local mount_point os_name version
  
  mount_point=$(mktemp -d) || return 1
  if mount -r -t xfs "$device" "$mount_point" 2>/dev/null; then
    if [[ -f "$mount_point/etc/os-release" ]]; then
      os_name=$(grep '^NAME=' "$mount_point/etc/os-release" | cut -d'=' -f2 | tr -d '"')
      version=$(grep '^VERSION_ID=' "$mount_point/etc/os-release" | cut -d'=' -f2 | tr -d '"')
      MULTIBOOT_SYSTEMS["$device"]="$os_name ${version:-} (XFS) on $label"
      MULTIBOOT_ORDER+=("$device")
    fi
    umount "$mount_point" 2>/dev/null || true
  fi
  rmdir "$mount_point" 2>/dev/null || true
}

multiboot_probe_linux_f2fs() {
  local device=$1 label=${2:-Unknown}
  local mount_point os_name version
  
  mount_point=$(mktemp -d) || return 1
  if mount -r -t f2fs "$device" "$mount_point" 2>/dev/null; then
    if [[ -f "$mount_point/etc/os-release" ]]; then
      os_name=$(grep '^NAME=' "$mount_point/etc/os-release" | cut -d'=' -f2 | tr -d '"')
      version=$(grep '^VERSION_ID=' "$mount_point/etc/os-release" | cut -d'=' -f2 | tr -d '"')
      MULTIBOOT_SYSTEMS["$device"]="$os_name ${version:-} (F2FS) on $label"
      MULTIBOOT_ORDER+=("$device")
    fi
    umount "$mount_point" 2>/dev/null || true
  fi
  rmdir "$mount_point" 2>/dev/null || true
}

multiboot_probe_windows() {
  local device=$1 label=${2:-Unknown}
  local description="NTFS_DATA on $label"
  local label_value

  # The firmware entry is deliberately not consulted here.  An NTFS volume is
  # data unless this particular filesystem contains Windows evidence.
  if have ntfsls && ntfsls "$device" Windows/System32 2>/dev/null | grep -q .; then
    description="CONFIRMED_WINDOWS_INSTALLATION on $label"
  else
    label_value=$label
    [[ -n "$label_value" ]] || label_value=$(lsblk -no LABEL "$device" 2>/dev/null || true)
    if [[ -n "$label_value" && "$label_value" =~ [Ww]indows|[Mm]icrosoft|[Ss]ystem|[Bb]oot|[Rr]ecovery ]]; then
      description="POSSIBLE_WINDOWS_INSTALLATION on $label"
    fi
  fi

  MULTIBOOT_SYSTEMS["$device"]="$description"
  MULTIBOOT_ORDER+=("$device")
}

multiboot_windows_boot_manager_present() {
  if have efibootmgr && efibootmgr -v 2>/dev/null | grep -qi 'Windows Boot Manager'; then
    printf '%s' 'WINDOWS_BOOT_MANAGER'
    return 0
  fi
  return 1
}

multiboot_print_windows_boot_manager() {
  (( MULTIBOOT_WINDOWS_BOOT_MANAGER )) || return 0
  printf 'WINDOWS_BOOT_MANAGER: detected from EFI firmware entry\n'
}

multiboot_probe_efi_or_boot() {
  local device=$1 label=${2:-Unknown}
  # Typically EFI or boot partition, skip detailed inspection
  [[ "$label" =~ -[Ee][Ff][Ii]- ]] && MULTIBOOT_SYSTEMS["$device"]="EFI System Partition" || true
}

multiboot_validate_grub_menu() {
  local cfg
  cfg=$(grub_config_path 2>/dev/null) || return 1
  [[ -f "$cfg" && -s "$cfg" ]] || return 1
  [[ -r "$cfg" ]] || return 3
  
  # Check for valid menuentry definitions
  grep -q 'menuentry' "$cfg" || return 1
}

multiboot_validate_linux_kernel() {
  local device=$1
  local mount_point kernel_found=0
  
  mount_point=$(mktemp -d) || return 1
  if mount -r "$device" "$mount_point" 2>/dev/null; then
    if [[ -n "$(find "$mount_point/boot" -maxdepth 1 -name 'vmlinuz*' -o -name 'bzImage' 2>/dev/null)" ]]; then
      kernel_found=1
    fi
    umount "$mount_point" 2>/dev/null || true
  fi
  rmdir "$mount_point" 2>/dev/null || true
  return $((1 - kernel_found))
}

multiboot_detect_boot_entry() {
  local device=$1
  # Attempt to find boot configuration
  if efi_available 2>/dev/null; then
    efibootmgr -v 2>/dev/null | grep -qi "$device"
  fi
}

multiboot_report() {
  local device description color index=0
  local color_green=${C_GREEN:-}
  local color_orange=${C_ORANGE:-}
  local color_reset=${C_RESET:-}
  local has_global_windows has_confirmed=0 confirmed_list=()
  local -a entry_colors=("${C_GREEN:-}" "${C_CYAN:-}" "${C_PURPLE:-}" "${C_ORANGE:-}" "${C_RED:-}")

  printf '%sMulti-boot System Scan%s\n' "${C_WHITE:-}" "$color_reset"
  printf '%s=====================%s\n\n' "${C_PURPLE:-}" "$color_reset"

  multiboot_scan_partitions
  has_global_windows=${MULTIBOOT_WINDOWS_BOOT_MANAGER:-0}

  # Keep the original complete report (systems, data partitions, and firmware
  # context) while colouring every discovered entry independently.
  multiboot_print_windows_boot_manager

  if [[ ${#MULTIBOOT_ORDER[@]} -eq 0 ]]; then
    printf 'No candidate installations detected.\n'
    if ((has_global_windows)); then
      printf 'Note: Windows Boot Manager detected; Windows installation partition not determined.\n'
    fi
    return 0
  fi

  for device in "${MULTIBOOT_ORDER[@]}"; do
    description=${MULTIBOOT_SYSTEMS[$device]:-Unknown system}
    color=${entry_colors[index % ${#entry_colors[@]}]}
    if [[ "$description" == CONFIRMED* ]]; then
      printf '%s✓%s %s%s:%s %s\n' "$color_green" "$color_reset" "$color" "$device" "$color_reset" "$description"
    elif [[ "$description" == POSSIBLE* ]]; then
      printf '%s⚠%s %s%s:%s %s\n' "$color_orange" "$color_reset" "$color" "$device" "$color_reset" "$description"
    elif [[ "$description" == NTFS_DATA* ]]; then
      printf '%s⚠%s %s%s:%s %s\n' "$color_orange" "$color_reset" "$color" "$device" "$color_reset" "$description"
    else
      printf '%s✓%s %s%s:%s %s\n' "$color_green" "$color_reset" "$color" "$device" "$color_reset" "$description"
    fi
    ((index += 1))
    if [[ "$description" == CONFIRMED* ]]; then
      has_confirmed=1
      confirmed_list+=("$device")
    fi
  done

  printf '\n'

  if ((has_global_windows)); then
    if ((has_confirmed)); then
      printf 'Note: firmware contains Windows Boot Manager; confirmed Windows installation(s) on: %s\n' "${confirmed_list[*]}"
    else
      printf 'Note: Windows Boot Manager detected; Windows installation partition not determined.\n'
    fi
  fi

  # Validate bootloader configuration
  local grub_menu_rc
  if multiboot_validate_grub_menu; then
    printf '%s✓%s %sGRUB:%s configuration present and valid\n' "$color_green" "$color_reset" "$color_green" "$color_reset"
  else
    grub_menu_rc=$?
    if [[ $grub_menu_rc -eq 3 ]]; then
      printf '%s⚠%s %sGRUB:%s configuration requires root privileges to validate\n' "$color_orange" "$color_reset" "$color_orange" "$color_reset"
    else
      printf '%s✗%s %sGRUB:%s configuration missing or invalid\n' "${C_RED:-}" "$color_reset" "${C_RED:-}" "$color_reset"
    fi
  fi

  # EFI information
  if efi_available 2>/dev/null; then
    printf '%s✓%s %sEFI:%s boot entries available\n' "$color_green" "$color_reset" "$color_green" "$color_reset"
    efi_summary | sed 's/^/  /'
  else
    printf '%s⚠%s %sEFI:%s Boot variables unavailable\n' "$color_orange" "$color_reset" "$color_orange" "$color_reset"
  fi
}

multiboot_list() {
  local device
  multiboot_scan_partitions
  for device in "${MULTIBOOT_ORDER[@]}"; do
    printf '%s\n' "$device"
  done
}

multiboot_count() {
  multiboot_scan_partitions
  printf '%d\n' "${#MULTIBOOT_ORDER[@]}"
}

multiboot_get_description() {
  local device=$1
  printf '%s\n' "${MULTIBOOT_SYSTEMS[$device]:-Unknown}"
}
