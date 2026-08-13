#!/usr/bin/env bash
# Read-only system inventory. All probes tolerate Live ISO restrictions.
declare -A DIAG=()

devil_parse_lsblk_entries() {
  if [ ! -t 0 ]; then
    cat
  else
    lsblk -rpn -o PATH,FSTYPE,LABEL 2>/dev/null
  fi | awk '
    {
      path=$1
      fstype=$2
      label=$0
      sub(/^[^[:space:]]+[[:space:]]*/, "", label)
      sub(/^[^[:space:]]+[[:space:]]*/, "", label)
      sub(/^[[:space:]]+/, "", label)
      printf "%s\t%s\t%s\n", path, fstype, label
    }
  '
}

diagnostics_collect() {
  local target_root target_boot target_efi
  local -a boot_targets
  DIAG=()
  DIAG[time]=$(date -Is)
  DIAG[kernel]=$(uname -r)
  DIAG[firmware]=$([[ -d /sys/firmware/efi ]] && echo UEFI || echo BIOS)
  DIAG[root]=$(findmnt -n -o SOURCE / 2>/dev/null || echo unknown)
  target_root=$(devil_target_root)
  target_boot=$(devil_target_path /boot) || target_boot=/boot
  target_efi=$(devil_target_path /boot/efi) || target_efi=/boot/efi
  DIAG[target_root]="$target_root"
  DIAG[target_source]="${DEVIL_TARGET_ROOT_SOURCE:-current}"
  DIAG[target_description]=$(devil_target_description)
  DIAG[target_distro]=$(devil_target_os_release_value PRETTY_NAME 2>/dev/null || echo unknown)
  DIAG[distro]="$DEVIL_DISTRO"
  DIAG[arch]=$(uname -m)
  DIAG[hostname]=$(hostname 2>/dev/null || echo unknown)
  
  # Secure Boot status
  if have mokutil; then
    DIAG[secure_boot]=$(mokutil --sb-state 2>/dev/null | head -1 || echo "unavailable")
  else
    DIAG[secure_boot]="unavailable"
  fi
  
  # Block devices and storage
  DIAG[block]=$(lsblk -J -o NAME,PATH,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS 2>/dev/null || echo '{}')
  DIAG[mounts]=$(findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS 2>/dev/null || true)
  
  # EFI information
  if efi_available 2>/dev/null; then
    if output=$(efi_summary 2>&1); then
      DIAG[efi]="$output"
    else
      DIAG[efi]='EFI variables unavailable'
    fi
    DIAG[boot_target]=$(efi_boot_target_summary 2>&1 || true)
  elif [[ -d /sys/firmware/efi/efivars ]]; then
    DIAG[efi]='EFI variables accessible but efibootmgr is unavailable'
    DIAG[boot_target]='EFI variables present but efibootmgr unavailable'
  else
    DIAG[efi]='Not in UEFI mode or EFI variables not accessible'
    DIAG[boot_target]='EFI unavailable'
  fi
  
  # Boot partitions
  if [[ "${DEVIL_TARGET_ROOT_SOURCE:-current}" == ambiguous ]]; then
    DIAG[boot]='Not checked: select a mounted Linux root with --target-root PATH'
  else
    boot_targets=("$target_boot")
    [[ -d "$target_efi" ]] && boot_targets+=("$target_efi")
    DIAG[boot]=$(findmnt -rn -o SOURCE,TARGET,FSTYPE "${boot_targets[@]}" 2>/dev/null || echo "No boot mounts found for selected target")
  fi
  
  # Installed systems
  DIAG[installations]=$(diagnostics_installations)
  
  # Storage layout
  DIAG[storage]=$(filesystem_summary)
  
  # GRUB validation
  # Run GRUB validation and record structured status
  local _gv_output _gv_rc
  if _gv_output=$(grub_validate 2>&1); then
    _gv_rc=0
    DIAG[grub]="${_gv_output}"
  else
    _gv_rc=$?
    DIAG[grub]="${_gv_output}"
  fi
  DIAG[grub_rc]="${_gv_rc}"
  case "${_gv_rc}" in
    0) DIAG[grub_status]="${GRUB_STATUS_OK:-GRUB_OK}" ;; 
    1) DIAG[grub_status]="${GRUB_STATUS_MISSING:-GRUB_MISSING}" ;; 
    4) DIAG[grub_status]="${GRUB_STATUS_EMPTY:-GRUB_EMPTY}" ;; 
    3) DIAG[grub_status]="${GRUB_STATUS_PRIVILEGE_REQUIRED:-GRUB_PRIVILEGE_REQUIRED}" ;; 
    5) DIAG[grub_status]="${GRUB_STATUS_INACCESSIBLE:-GRUB_INACCESSIBLE}" ;; 
    2) DIAG[grub_status]="${GRUB_STATUS_INVALID:-GRUB_INVALID}" ;; 
    6) DIAG[grub_status]="${GRUB_STATUS_TARGET_REQUIRED:-GRUB_TARGET_ROOT_REQUIRED}" ;; 
    *) DIAG[grub_status]="GRUB_UNKNOWN" ;; 
  esac
  
  # TPM status
  if have systemd-analyze; then
    local tpm_probe
    tpm_probe=$(systemd-analyze has-tpm2 2>/dev/null || true)
    case "${tpm_probe%%$'\n'*}" in
      yes) DIAG[tpm]='available' ;;
      partial) DIAG[tpm]='partial TPM 2.0 support' ;;
      no|unavailable|'') DIAG[tpm]='unavailable' ;;
      *) DIAG[tpm]='unknown' ;;
    esac
  else
    DIAG[tpm]="unavailable (systemd-analyze not found)"
  fi
  
  # BitLocker detection
  DIAG[bitlocker]=$(diagnostics_detect_bitlocker)
  
  # LUKS/encrypted volumes
  DIAG[luks]=$(diagnostics_detect_luks)
  
  # LVM volumes
  DIAG[lvm]=$(diagnostics_detect_lvm)
  
  # RAID arrays
  DIAG[raid]=$(diagnostics_detect_raid)
  
  # Kernel command line
  DIAG[cmdline]=$(cat /proc/cmdline 2>/dev/null || echo "unavailable")
  
  # Initramfs status
  if [[ "${DEVIL_TARGET_ROOT_SOURCE:-current}" == ambiguous ]]; then
    DIAG[initramfs]='Not checked: select a mounted Linux root with --target-root PATH'
  else
    DIAG[initramfs]=$(diagnostics_check_initramfs)
  fi
  
  log_info "read-only diagnostics collected"
}

diagnostics_installations() {
  local dev opts name fstype label out=''
  # A filesystem type alone is not an installed system. Probe candidate roots
  # read-only so Btrfs @ installations are shown by name and are selectable.
  if declare -F recovery_discover_linux_roots >/dev/null; then
    while IFS=$'\t' read -r dev opts name; do
      [[ -n "$dev" ]] || continue
      out+="Linux: $name — $dev ($opts)"$'\n'
    done < <(recovery_discover_linux_roots)
  fi
  while IFS=$'\t' read -r dev fstype label; do
    [[ -n "$dev" ]] || continue
    [[ "$fstype" =~ ^(ext[234]|btrfs|xfs|f2fs|ntfs|vfat)$ ]] || continue
    [[ "$out" == *" — $dev ("* ]] && continue
    out+="$dev ($fstype${label:+, label=$label})"$'\n'
  done < <(devil_parse_lsblk_entries)
  printf '%s' "${out:-No candidate installations visible}"
}

diagnostics_detect_bitlocker() {
  local ntfs_count label_info
  ntfs_count=$(lsblk -rn -o FSTYPE 2>/dev/null | grep -c '^ntfs$' || echo 0)
  if [[ $ntfs_count -eq 0 ]]; then
    echo "Not detected"
    return 0
  fi

  label_info=$(lsblk -rn -o PATH,LABEL,FSTYPE 2>/dev/null | grep -i 'ntfs' | grep -Ei 'windows|microsoft|boot|system' || true)
  if [[ -n "$label_info" ]]; then
    echo "Possible Windows/BitLocker volume detected based on NTFS and label evidence"
  elif have efibootmgr && efibootmgr -v 2>/dev/null | grep -qi 'Windows Boot Manager'; then
    echo "Windows Boot Manager detected via EFI; Windows installation partition not determined"
  else
    echo "NTFS volume(s) detected; Windows/BitLocker cannot be confirmed without additional evidence"
  fi
}

diagnostics_detect_luks() {
  if have cryptsetup; then
    local count=0
    count=$(cryptsetup status 2>/dev/null | grep -c '^/' || echo 0) 2>/dev/null
    count=${count:-0}
    count=${count//[!0-9]/}
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    if [[ $count -gt 0 ]]; then
      echo "$count LUKS/encrypted volume(s) detected (locked)"
    else
      echo "None detected"
    fi
  else
    echo "cryptsetup unavailable"
  fi
}

diagnostics_detect_lvm() {
  if have lvs; then
    local count=0
    count=$(lvs --noheadings 2>/dev/null | grep -c . || echo 0) 2>/dev/null
    count=${count:-0}
    count=${count//[!0-9]/}
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    if [[ $count -gt 0 ]]; then
      echo "$count LVM logical volume(s) detected"
    else
      echo "None detected"
    fi
  else
    echo "LVM tools unavailable"
  fi
}

diagnostics_detect_raid() {
  if [[ -f /proc/mdstat ]]; then
    local count=0
    count=$(grep -c '^md[0-9]' /proc/mdstat 2>/dev/null || echo 0)
    count=${count:-0}
    count=${count//[!0-9]/}
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    if ((count > 0)); then
      echo "$count RAID array(s) detected"
      grep '^md' /proc/mdstat | sed 's/^/  /'
    else
      echo "None detected"
    fi
  else
    echo "No MD RAID detected"
  fi
}

diagnostics_check_initramfs() {
  local boot_dir found=0
  boot_dir=$(devil_target_path /boot) || boot_dir=/boot
  if [[ -d "$boot_dir" ]]; then
    if find "$boot_dir" -maxdepth 1 \( -name 'initramfs*' -o -name 'initrd*' -o -name 'initrd.img*' \) 2>/dev/null | grep -q .; then
      echo "Found: $(find "$boot_dir" -maxdepth 1 \( -name 'initramfs*' -o -name 'initrd*' -o -name 'initrd.img*' \) 2>/dev/null | xargs basename | tr '\n' ';')"
      found=1
    fi
  fi
  ((found)) || echo "No initramfs found in $boot_dir"
}

diagnostics_check_grub_entries() {
  local cfg
  cfg=$(grub_config_path 2>/dev/null) || return 1
  [[ -f "$cfg" ]] || return 1
  
  grep -c '^menuentry' "$cfg" 2>/dev/null || echo 0
}

diagnostics_findings() {
  local problems=0 boot_dir
  
  # Check if GRUB is present
  if ! grub_config_path >/dev/null 2>&1; then
    printf '%sWARNING: No GRUB configuration found%s\n' "$C_ORANGE" "$C_RESET"
    ((problems++))
  fi
  
  # Check EFI on UEFI systems
  if [[ "${DIAG[firmware]}" == "UEFI" ]]; then
    if ! efi_available 2>/dev/null; then
      printf '%sWARNING: System is UEFI but EFI variables are not accessible%s\n' "$C_ORANGE" "$C_RESET"
      ((problems++))
    fi
  fi
  
  # Check for missing kernel
  boot_dir=$(devil_target_path /boot) || boot_dir=/boot
  if ! find "$boot_dir" -maxdepth 1 \( -name 'vmlinuz*' -o -name 'bzImage' \) 2>/dev/null | grep -q .; then
    printf '%sWARNING: No kernel found in %s%s\n' "$C_ORANGE" "$boot_dir" "$C_RESET"
    ((problems++))
  fi
  
  return $problems
}

diagnostics_text() {
  cat <<EOF
DEVIL v$DEVIL_VERSION diagnostic report
Generated: ${DIAG[time]}

System overview
  Hostname: ${DIAG[hostname]}
  Distribution: ${DIAG[distro]}
  Architecture: ${DIAG[arch]}
  Kernel: ${DIAG[kernel]}
  Firmware: ${DIAG[firmware]}

Runtime state
  Root filesystem: ${DIAG[root]}
  Kernel command line: ${DIAG[cmdline]}

Inspection target
  Root: ${DIAG[target_root]}
  Selection: ${DIAG[target_description]}
  Distribution: ${DIAG[target_distro]}

Security posture
  Secure Boot: ${DIAG[secure_boot]}
  TPM: ${DIAG[tpm]}
  BitLocker: ${DIAG[bitlocker]}

Boot configuration
  GRUB status: ${DIAG[grub_status]:-GRUB_UNKNOWN}
  GRUB: ${DIAG[grub]}
  EFI/BootOrder: $(printf '%s' "${DIAG[efi]}" | grep -E 'BootCurrent|Timeout|BootOrder' | tr '\n' '; ' | sed 's/; $//; s/[[:space:]]\+/ /g')
  Boot partitions: $(printf '%s' "${DIAG[boot]}" | head -1)
  LUKS volumes: ${DIAG[luks]}
  LVM volumes: ${DIAG[lvm]}
  RAID arrays: $(printf '%s' "${DIAG[raid]}" | head -1)
  Initramfs: $(printf '%s' "${DIAG[initramfs]}" | head -1)

Detected installations
${DIAG[installations]}

Storage summary
${DIAG[storage]}

EFI/BootOrder details
${DIAG[efi]}
EOF
}

diagnostics_print() {
  diagnostics_text
}

diagnostics_json() {
  printf '{"timestamp":"%s","firmware":"%s","root":"%s","target_root":"%s","target_source":"%s","target_distro":"%s","kernel":"%s","distro":"%s","architecture":"%s","secure_boot":"%s","tpm":"%s","bitlocker":"%s","grub_status":"%s","grub_found":%s,"efi_accessible":%s}' \
    "$(json_escape "${DIAG[time]}")" \
    "$(json_escape "${DIAG[firmware]}")" \
    "$(json_escape "${DIAG[root]}")" \
    "$(json_escape "${DIAG[target_root]:-/}")" \
    "$(json_escape "${DIAG[target_source]:-current}")" \
    "$(json_escape "${DIAG[target_distro]:-unknown}")" \
    "$(json_escape "${DIAG[kernel]}")" \
    "$(json_escape "${DIAG[distro]}")" \
    "$(json_escape "${DIAG[arch]}")" \
    "$(json_escape "${DIAG[secure_boot]}")" \
    "$(json_escape "${DIAG[tpm]}")" \
    "$(json_escape "${DIAG[bitlocker]}")" \
    "$(json_escape "${DIAG[grub_status]:-}")" \
    "$(grub_config_path >/dev/null 2>&1 && echo true || echo false)" \
    "$(efi_available >/dev/null 2>&1 && echo true || echo false)"
}
