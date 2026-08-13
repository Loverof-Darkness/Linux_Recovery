#!/usr/bin/env bash
# EFI inspection and narrowly scoped BootOrder operations.

efi_available() {
  [[ -d /sys/firmware/efi/efivars ]] && have efibootmgr
}

efi_check_writeable() {
  [[ -w /sys/firmware/efi/efivars ]] || return 1
}

efi_boot_target_from_output() {
  local output=$1 current entry line
  output=${output//$'\r'/}
  current=$(printf '%s\n' "$output" | awk '/^BootCurrent:/ {print $2; exit}')
  [[ -n "$current" ]] || { printf 'unknown'; return 0; }
  entry=$(printf '%s\n' "$output" | while IFS= read -r line; do
    if [[ "$line" == Boot${current}* ]]; then
      line=${line#Boot${current}}
      line=${line#\*}
      line=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/ HD(.*$//')
      if [[ -n "$line" ]]; then
        printf '%s\n' "$line"
        break
      fi
    fi
  done)
  [[ -n "$entry" ]] || entry='unknown'
  printf '%s' "$entry"
}

efi_summary_from_output() {
  local output=$1 line color entry_index=0
  local -a entry_colors=("${C_GREEN:-}" "${C_CYAN:-}" "${C_PURPLE:-}" "${C_ORANGE:-}" "${C_RED:-}")
  output=${output//$'\r'/}
  while IFS= read -r line; do
    case "$line" in
      '  BootCurrent:'*)
        printf '%s%s%s\n' "${C_CYAN:-}" "$line" "${C_RESET:-}"
        ;;
      '  Timeout:'*)
        printf '%s%s%s\n' "${C_GRAY:-}" "$line" "${C_RESET:-}"
        ;;
      '  BootOrder:'*)
        printf '%s%s%s\n' "${C_ORANGE:-}" "$line" "${C_RESET:-}"
        ;;
      '  '[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]:*)
        color=${entry_colors[entry_index % ${#entry_colors[@]}]}
        printf '%s%s%s\n' "$color" "$line" "${C_RESET:-}"
        ((entry_index += 1))
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < <(printf '%s\n' "$output" | awk '
    /^BootCurrent:/ { print "  BootCurrent: " $2; next }
    /^Timeout:/ { print "  Timeout: " $2 " " $3; next }
    /^BootOrder:/ { print "  BootOrder: " $2; next }
    /^Boot[0-9A-Fa-f]+\\*/ {
      entry=$1
      sub(/^Boot/, "", entry)
      sub(/\*$/, "", entry)
      line=$0
      sub(/^Boot[0-9A-Fa-f]+\*?[[:space:]]*/, "", line)
      sub(/[[:space:]]+HD.*/, "", line)
      gsub(/[[:space:]]+/, " ", line)
      sub(/^ +/, "", line)
      if (line != "") print "  " entry ": " line
      next
    }
    /^Boot[0-9A-Fa-f]+/ {
      entry=$1
      sub(/^Boot/, "", entry)
      line=$0
      sub(/^Boot[0-9A-Fa-f]+[[:space:]]*/, "", line)
      sub(/[[:space:]]+HD.*/, "", line)
      gsub(/[[:space:]]+/, " ", line)
      sub(/^ +/, "", line)
      if (line != "") print "  " entry ": " line
    }
  ' | head -n 12)
}

efi_summary() {
  if ! efi_available; then
    printf '%sEFI summary unavailable%s\n' "$C_ORANGE" "$C_RESET"
    return 0
  fi

  printf '%sEFI Summary%s\n' "$C_WHITE" "$C_RESET"
  printf '===========\n'
  local output
  output=$(efibootmgr -v 2>/dev/null || true)
  efi_summary_from_output "$output"
}

efi_boot_target_summary() {
  local output target
  if ! efi_available; then
    printf 'EFI unavailable'
    return 0
  fi
  output=$(efibootmgr -v 2>/dev/null || true)
  target=$(efi_boot_target_from_output "$output")
  if [[ -z "$target" || "$target" == "unknown" ]]; then
    printf 'No active EFI target detected'
  else
    printf 'Active EFI target: %s' "$target"
  fi
}

efi_list() {
  local output

  if ! efi_available; then
    printf '%sEFI management unavailable%s\n' "$C_ORANGE" "$C_RESET"
    printf '(requires UEFI boot and efibootmgr)\n'
    return 0
  fi

  printf '%sEFI Boot Entries%s\n' "$C_WHITE" "$C_RESET"
  printf '================\n'

  if ! output=$(efibootmgr -v 2>/dev/null); then
    printf '%s✗%s Failed to read EFI variables%s\n' "$C_RED" "$C_RESET" ""
    return 0
  fi

  efi_print_colored_entries "$output"
}

efi_print_colored_entries() {
  # Keep firmware metadata easy to scan, then colour each individual boot
  # entry.  The palette repeats so a long list remains readable.
  local output=$1 line color index=0 entries_started=0
  local -a entry_colors=("$C_GREEN" "$C_CYAN" "$C_PURPLE" "$C_ORANGE" "$C_RED")

  while IFS= read -r line; do
    case "$line" in
      BootCurrent:*) printf '%sCurrent boot:%s %s\n' "$C_CYAN" "$C_RESET" "${line#BootCurrent: }" ;;
      BootNext:*)    printf '%sNext boot:%s    %s\n' "$C_CYAN" "$C_RESET" "${line#BootNext: }" ;;
      Timeout:*)     printf '%sTimeout:%s      %s\n' "$C_GRAY" "$C_RESET" "${line#Timeout: }" ;;
      BootOrder:*)   printf '%sBoot order:%s   %s\n' "$C_ORANGE" "$C_RESET" "${line#BootOrder: }" ;;
      Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]*)
        if ((entries_started == 0)); then
          printf '\n%sBoot entries (each entry has its own colour):%s\n' "$C_WHITE" "$C_RESET"
          entries_started=1
        fi
        color=${entry_colors[index % ${#entry_colors[@]}]}
        printf '%s  %s%s\n' "$color" "$line" "$C_RESET"
        ((index += 1))
        ;;
      *) [[ -n "$line" ]] && printf '%s%s%s\n' "$C_GRAY" "$line" "$C_RESET" ;;
    esac
  done <<<"$output"
}

efi_list_entries() {
  if ! efi_available; then return 0; fi
  efibootmgr -v 2>/dev/null | grep -E '^Boot[0-9A-F]{4}' | awk '{print $1}' | sed 's/*$//' || true
}

efi_get_bootorder() {
  if ! efi_available; then return 0; fi
  efibootmgr -v 2>/dev/null | grep '^BootOrder:' | awk '{print $2}' || true
}

# Return EFI IDs whose firmware description points at a Linux/GRUB loader.
# This is deliberately based on efibootmgr's label/path, never on entry number
# or position, since firmware is free to allocate either differently.
efi_grub_entry_ids() {
  efi_available || return 0
  efibootmgr -v 2>/dev/null | awk '
    /^Boot[0-9A-Fa-f]{4}/ {
      id=$1; sub(/^Boot/, "", id); sub(/\*$/, "", id)
      line=tolower($0)
      if (line ~ /(grub|garuda|fedora|ubuntu|debian|arch|opensuse|linux boot manager|\\\\efi\\\\linux)/)
        print id
    }'
}

# Construct a safe order: detected Linux entries first, followed by every
# existing BootOrder entry exactly once. This preserves Windows and recovery
# entries instead of replacing the firmware's list.
efi_recommended_bootorder() {
  local current linux id result seen
  current=$(efi_get_bootorder)
  [[ -n "$current" ]] || return 1
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    [[ ",${result}," == *",${id},"* ]] || result="${result:+$result,}$id"
  done < <(efi_grub_entry_ids)
  IFS=',' read -ra _efi_ids <<< "$current"
  for id in "${_efi_ids[@]}"; do
    [[ -n "$id" ]] || continue
    [[ ",${result}," == *",${id},"* ]] || result="${result:+$result,}$id"
  done
  printf '%s' "$result"
}

efi_repair_bootorder() {
  local confirmed=0 current recommended
  [[ "${1:-}" == --confirmed ]] && confirmed=1
  require_root
  efi_available || { printf '%sEFI variables are unavailable%s\n' "${C_RED:-}" "${C_RESET:-}"; return 1; }
  current=$(efi_get_bootorder)
  recommended=$(efi_recommended_bootorder) || return 1
  [[ -n "$recommended" ]] || return 1
  if [[ "$current" == "$recommended" ]]; then
    printf '%sBootOrder already prioritizes a Linux/GRUB entry.%s\n' "${C_GREEN:-}" "${C_RESET:-}"
    return 0
  fi
  printf 'Current BootOrder: %s\nRecommended order: %s\n' "$current" "$recommended"
  (( confirmed )) || confirm 'Back up EFI state and set GRUB/Linux first?' || return 1
  efi_backup >/dev/null || return 1
  run_action 'set EFI BootOrder with GRUB/Linux first' efibootmgr -o "$recommended"
}

efi_validate_entry() {
  local entry=$1
  [[ "$entry" =~ ^[0-9A-Fa-f]{4}$ ]] || return 0
  efibootmgr -v 2>/dev/null | grep -q "^Boot${entry}" || return 0
}

efi_set_order() {
  local order=$1
  require_root
  
  if ! efi_available; then
    printf '%s✗%s EFI variables are unavailable%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
  
  [[ "$order" =~ ^[0-9A-Fa-f]{4}(,[0-9A-Fa-f]{4})*$ ]] || {
    printf '%s✗%s BootOrder must be comma-separated four-digit hex IDs%s\n' "$C_RED" "$C_RESET" ""
    return 1
  }
  
  printf 'Current BootOrder: %s\n' "$(efi_get_bootorder)"
  printf 'New BootOrder:     %s\n\n' "$order"
  
  confirm "Set BootOrder to $order?" || return 1
  
  if run_action "set EFI BootOrder to $order" efibootmgr -o "$order"; then
    printf '%s✓%s BootOrder updated successfully.%s\n' "$C_GREEN" "$C_RESET" ""
    log_info "EFI BootOrder changed to $order"
    return 0
  else
    printf '%s✗%s Failed to update BootOrder%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
}

efi_create_entry() {
  local label=$1 loader=$2 disk=$3 partition=$4
  require_root
  
  if ! efi_available; then
    printf '%s✗%s EFI variables are unavailable%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
  
  printf '%sCreating EFI boot entry%s\n' "$C_WHITE" "$C_RESET"
  printf 'Label:     %s\n' "$label"
  printf 'Loader:    %s\n' "$loader"
  printf 'Disk:      %s\n' "$disk"
  printf 'Partition: %s\n\n' "$partition"
  
  confirm "Create this boot entry?" || return 1
  
  if run_action "create EFI entry" efibootmgr -c -L "$label" -l "$loader" -d "$disk" -p "$partition"; then
    printf '%s✓%s Boot entry created successfully.%s\n' "$C_GREEN" "$C_RESET" ""
    log_info "EFI boot entry created: $label"
    return 0
  else
    printf '%s✗%s Failed to create boot entry%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
}

efi_delete() {
  local id=$1
  require_root
  
  if ! efi_available; then
    printf '%s✗%s EFI variables are unavailable%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
  
  [[ "$id" =~ ^[0-9A-Fa-f]{4}$ ]] || {
    printf '%s✗%s Invalid boot number (must be 4-digit hex)%s\n' "$C_RED" "$C_RESET" ""
    return 1
  }
  
  if ! efi_validate_entry "$id"; then
    printf '%s✗%s Boot entry does not exist: %s%s\n' "$C_RED" "$C_RESET" "$id" ""
    return 1
  fi
  
  printf '%sDeleting EFI boot entry%s\n' "$C_WHITE" "$C_RESET"
  efibootmgr -v 2>/dev/null | grep "^Boot${id}"
  printf '\n'
  
  confirm "Delete EFI entry $id?" || return 1
  
  if run_action "delete EFI entry $id" efibootmgr -b "$id" -B; then
    printf '%s✓%s Boot entry deleted.%s\n' "$C_GREEN" "$C_RESET" ""
    log_info "EFI boot entry deleted: $id"
    return 0
  else
    printf '%s✗%s Failed to delete boot entry%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
}

efi_set_as_next_boot() {
  local id=$1
  require_root
  
  if ! efi_available; then
    printf '%s✗%s EFI variables are unavailable%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
  
  [[ "$id" =~ ^[0-9A-Fa-f]{4}$ ]] || {
    printf '%s✗%s Invalid boot number%s\n' "$C_RED" "$C_RESET" ""
    return 1
  }

  if ! efi_validate_entry "$id"; then
    printf '%s✗%s Boot entry does not exist: %s%s\n' "$C_RED" "$C_RESET" "$id" ""
    return 1
  fi
  
  printf 'Setting Boot${id} as next boot option...\n'
  confirm "Proceed?" || return 1
  
  if run_action "set EFI Boot${id} as next boot" efibootmgr -n "$id"; then
    printf '%s✓%s Next boot set to $id.%s\n' "$C_GREEN" "$C_RESET" ""
    log_info "Next boot set to $id"
    return 0
  else
    printf '%s✗%s Failed to set next boot%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
}

efi_backup() {
  require_root
  
  if ! efi_available; then
    printf '%s✗%s EFI variables are unavailable%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
  
  local dest backup_base
  backup_base="$DEVIL_BACKUP_DIR/efi-$(date +%Y%m%d-%H%M%S)"
  
  # Backup efibootmgr output
  dest="${backup_base}.txt"
  efi_list >"$dest" 2>&1
  printf '%s✓%s EFI backup created: %s%s\n' "$C_GREEN" "$C_RESET" "$(basename "$dest")" ""
  printf '%s\n' "$dest"
}

efi_restore() {
  printf '%sEFI Restore from Backup%s\n' "$C_WHITE" "$C_RESET"
  printf '======================\n'
  printf 'Available EFI backups:\n'
  
  find "$DEVIL_BACKUP_DIR" -maxdepth 1 -name 'efi-*.txt' -type f | sort | while read -r backup; do
    printf '  • %s (%s bytes)\n' "$(basename "$backup")" "$(wc -c <"$backup")"
  done
  
  printf '\nWarning: EFI restoration is complex and risky.\n'
  printf 'Manual review of the backup is strongly recommended.\n'
}

efi_diagnose() {
  printf '%sEFI Diagnostics%s\n' "$C_WHITE" "$C_RESET"
  printf '===============\n'
  
  if [[ -d /sys/firmware/efi ]]; then
    printf '%s✓%s System is in UEFI mode%s\n' "$C_GREEN" "$C_RESET" ""
  else
    printf '%s✗%s System is not in UEFI mode%s\n' "$C_RED" "$C_RESET" ""
    return 1
  fi
  
  if [[ -d /sys/firmware/efi/efivars ]]; then
    printf '%s✓%s EFI variables accessible%s\n' "$C_GREEN" "$C_RESET" ""
  else
    printf '%s✗%s EFI variables not accessible%s\n' "$C_RED" "$C_RESET" ""
  fi
  
  if have efibootmgr; then
    printf '%s✓%s efibootmgr installed%s\n' "$C_GREEN" "$C_RESET" ""
  else
    printf '%s✗%s efibootmgr not installed%s\n' "$C_RED" "$C_RESET" ""
  fi
  
  if efi_check_writeable; then
    printf '%s✓%s EFI variables are writeable%s\n' "$C_GREEN" "$C_RESET" ""
  else
    printf '%s⚠%s EFI variables are read-only (running as non-root)%s\n' "$C_ORANGE" "$C_RESET" ""
  fi
}

efi_check_secure_boot() {
  if have mokutil; then
    printf '%sSecure Boot Status%s\n' "$C_WHITE" "$C_RESET"
    printf '==================\n'
    mokutil --sb-state 2>/dev/null || printf '%s✗%s Secure Boot status unavailable%s\n' "$C_RED" "$C_RESET" ""
  else
    printf '%sSecure Boot: mokutil not installed%s\n' "$C_GRAY" "$C_RESET"
  fi
}
