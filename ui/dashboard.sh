#!/usr/bin/env bash
# Full-screen keyboard UI; uses ANSI escape sequences only, no dialog dependency.

declare -a UI_ITEMS=(
  "Dashboard"
  "Read Only Diagnostics"
  "Automatic Recovery"
  "Installed System Selector"
  "Advanced Recovery"
  "EFI Manager"
  "GRUB Manager"
  "BootOrder Manager"
  "Filesystem Manager"
  "Multi-Boot Manager"
  "Logs"
  "Reports"
  "Settings"
  "Help"
  "About"
  "Exit"
)

ui_menu_color() {
  case $(( $1 % 5 )) in
    0) printf '%s' "$C_CYAN" ;;
    1) printf '%s' "$C_GREEN" ;;
    2) printf '%s' "$C_ORANGE" ;;
    3) printf '%s' "$C_PURPLE" ;;
    *) printf '%s' "$C_RED" ;;
  esac
}

ui_menu_option() {
  local number=$1 label=$2 detail=${3:-}
  printf '  %s[%s]%s %s%-26s%s %s%s%s\n' \
    "$C_PURPLE" "$number" "$C_RESET" "$C_WHITE" "$label" "$C_RESET" "$C_GRAY" "$detail" "$C_RESET"
}

ui_status_marker() {
  # Sets a semantic marker for output that has an actual success, warning, or
  # failure state.  Keep unknown/read-only informational output unmarked.
  local state=$1
  case "$state" in
    ok)       UI_STATUS_MARK='✓'; UI_STATUS_COLOR=$C_GREEN ;;
    warning)  UI_STATUS_MARK='⚠'; UI_STATUS_COLOR=$C_ORANGE ;;
    critical) UI_STATUS_MARK='✗'; UI_STATUS_COLOR=$C_RED ;;
    *)        UI_STATUS_MARK='•'; UI_STATUS_COLOR=$C_GRAY ;;
  esac
}

ui_status_line() {
  local state=$1 label=$2 detail=$3
  ui_status_marker "$state"
  printf '%s%s%s %s%s%s — %s\n' "$UI_STATUS_COLOR" "$UI_STATUS_MARK" "$C_RESET" "$C_WHITE" "$label" "$C_RESET" "$detail"
}

ui_screen_header() {
  local title=$1 subtitle=${2:-}
  printf '\e[2J\e[H'
  terminal_devil_large_wordmark_at 1 2
  terminal_move_to 8 2
  printf '%sDEVIL v%s%s  %sEmergency Verification & Intelligent Linux Recovery%s' \
    "$C_BOLD$C_CYAN" "${DEVIL_VERSION:-unknown}" "$C_RESET" "$C_CYAN" "$C_RESET"
  terminal_move_to 9 2
  printf '%s────────────────────────────────────────────────────────────────────────────%s' "$C_PURPLE" "$C_RESET"
  terminal_move_to 11 2
  printf '%s%s%s' "$C_BOLD$C_WHITE" "$title" "$C_RESET"
  [[ -z "$subtitle" ]] || printf '  %s%s%s' "$C_GRAY" "$subtitle" "$C_RESET"
  printf '\n\n'
}

ui_draw() {
  local selected=$1 offset=${2:-0}
  local i item menu_start term_height term_width visible end box_width box_inside box_line row
  
  # Get terminal dimensions
  term_height=$(tput lines 2>/dev/null || echo 24)
  term_width=$(tput cols 2>/dev/null || echo 80)
  
  # Clear screen and draw header
  printf '\e[2J\e[H'
  
  if ((term_width >= 112 && term_height >= 32)); then
    # Mirror the startup splash: a large 24-bit ANSI DEVIL banner followed by
    # its subtitle, then leave enough vertical room for every main-menu item.
    terminal_devil_large_wordmark_at 1 2
    terminal_move_to 8 2
    printf '%sDEVIL v%s%s  %sEmergency Verification & Intelligent Linux Recovery%s' \
      "$C_BOLD$C_CYAN" "$DEVIL_VERSION" "$C_RESET" "$C_CYAN" "$C_RESET"
    terminal_move_to 9 2
    printf '%s────────────────────────────────────────────────────────────────────────────%s' "$C_PURPLE" "$C_RESET"
    menu_start=11
    terminal_move_to "$menu_start" 1
  else
    # Compact layout for short or narrow terminals.
    printf '%s╔%s═══════════════════════════════════════════════════════════════════════════%s╗%s\n' "$C_RED" "$C_PURPLE" "$C_CYAN" "$C_RESET"
    printf '%s║%s ' "$C_RED" "$C_RESET"
    terminal_devil_wordmark
    printf ' %sv%s%s  %sEmergency Verification & Intelligent Linux Recovery%s          %s║%s\n' "$C_BOLD$C_CYAN" "$DEVIL_VERSION" "$C_RESET" "$C_GRAY" "$C_RESET" "$C_RED" "$C_RESET"
    printf '%s╚%s═══════════════════════════════════════════════════════════════════════════%s╝%s\n\n' "$C_RED" "$C_PURPLE" "$C_CYAN" "$C_RESET"
    menu_start=5
  fi
  box_width=$((term_width - 2))
  ((box_width > 79)) && box_width=79
  ((box_width < 42)) && box_width=42
  box_inside=$((box_width - 2))
  printf -v box_line '%*s' "$box_inside" ''
  box_line=${box_line// /═}

  # Reserve a complete frame around the selectable rows and a complete footer
  # below it.  The former layout printed only a left edge for the main menu.
  visible=$((term_height - menu_start - 6))
  ((visible < 3)) && visible=3
  end=$((offset + visible))
  ((end > ${#UI_ITEMS[@]})) && end=${#UI_ITEMS[@]}
  UI_MENU_START_ROW=$((menu_start + 1))
  UI_MENU_VISIBLE=$visible
  UI_MENU_OFFSET=$offset
  
  printf '%s╔%s╗%s\n' "$C_PURPLE" "$box_line" "$C_RESET"
  # Draw the visible part of the menu.  The viewport keeps small terminals
  # usable and can be moved with arrow keys, Page Up/Down, or the mouse wheel.
  for ((i=offset; i<end; i++)); do
    row=$((UI_MENU_START_ROW + i - offset))
    terminal_move_to "$row" 1
    item=${UI_ITEMS[i]}
    if ((i == selected)); then
      printf '%s║%s>  %-*s%s' \
        "$C_PURPLE" "$C_REVERSE$C_ORANGE$C_BOLD" "$((box_inside - 3))" "$item" "$C_RESET"
    else
      printf '%s║%s%s.  %-*s%s' \
        "$C_PURPLE" "$C_RESET" "$(ui_menu_color "$i")" "$((box_inside - 3))" "$item" "$C_RESET"
    fi
    # Keep this edge outside the selected-row colour/reverse sequence.
    terminal_move_to "$row" "$box_width"
    printf '%s║%s' "$C_PURPLE" "$C_RESET"
  done
  terminal_move_to "$((UI_MENU_START_ROW + end - offset))" 1
  printf '%s╚%s╝%s\n' "$C_PURPLE" "$box_line" "$C_RESET"
  
  # Draw footer
  printf '\n%s┌%s┐%s\n' "$C_CYAN" "$box_line" "$C_RESET"
  # Render this row sequentially. Cursor repositioning here caused terminal
  # dependent gaps and detached borders when image protocols were active.
  local footer_text="[$DEVIL_RENDERER]  ${DEVIL_DISTRO:0:18}  ↑/↓ scroll  Enter select  q/Esc exit"
  # Use exactly the same inside width as the frame's top and bottom edges.
  # Keep the padding inside the field width, otherwise the right edge shifts.
  printf '%s│%s%-*s%s│%s\n' "$C_CYAN" "$C_RESET" "$box_inside" "$footer_text" "$C_CYAN" "$C_RESET"
  printf '%s└%s┘%s\n' "$C_CYAN" "$box_line" "$C_RESET"
}

ui_message() {
  local title=$1
  shift
  
  # Clear and draw message
  printf '\e[2J\e[H'
  printf '%s%s%s\n' "$C_WHITE" "$title" "$C_RESET"
  printf '%s' "$(printf '=%.0s' {1..60})"
  printf '\n\n'
  printf '%s\n' "$*"
  printf '\n'
  printf '%sPress Enter to return.%s' "$C_DIM" "$C_RESET"
  devil_pause '' >/dev/null 2>&1 || true
}

ui_prompt() {
  local prompt=$1
  printf '%s%s%s ' "$C_WHITE" "$prompt" "$C_RESET"
  read -r answer
  printf '%s\n' "$answer"
}

ui_select() {
  local n=${#UI_ITEMS[@]} selected=0 offset=0 term_height button x y action clicked
  term_height=$(tput lines 2>/dev/null || echo 24)

  if ! terminal_is_interactive; then
    printf 'Interactive UI requires a terminal; use --diagnose, --report, or --recovery-plan.\n'
    return 0
  fi

  terminal_mouse_init

  while :; do
    ui_draw "$selected" "$offset"
    terminal_read_key || return 1

    case "$DEVIL_KEY" in
      arrow_up)
        ((selected = (selected + n - 1) % n))
        ;;
      arrow_down|arrow_right)
        ((selected = (selected + 1) % n))
        ;;
      arrow_left)
        ((selected = (selected + n - 1) % n))
        ;;
      home)
        selected=0
        ;;
      end)
        selected=$((n - 1))
        ;;
      page_up)
        ((selected -= UI_MENU_VISIBLE))
        ((selected < 0)) && selected=0
        ;;
      page_down)
        ((selected += UI_MENU_VISIBLE))
        ((selected >= n)) && selected=$((n - 1))
        ;;
      enter|space)
        ui_action "$selected" || return 1
        ;;
      mouse:*)
        IFS=: read -r _ button x y action <<<"$DEVIL_KEY"
        case "$button:$action" in
          64:M) ((selected -= 3)); ((selected < 0)) && selected=0 ;;
          65:M) ((selected += 3)); ((selected >= n)) && selected=$((n - 1)) ;;
          0:M)
            if ((y >= UI_MENU_START_ROW && y < UI_MENU_START_ROW + UI_MENU_VISIBLE)); then
              clicked=$((offset + y - UI_MENU_START_ROW))
              if ((clicked < n)); then
                selected=$clicked
                ui_action "$selected" || return 1
              fi
            fi
            ;;
        esac
        ;;
      q|Q|escape)
        return 1
        ;;
    esac
    if ((selected < offset)); then offset=$selected; fi
    if ((selected >= offset + UI_MENU_VISIBLE)); then offset=$((selected - UI_MENU_VISIBLE + 1)); fi
  done
}

ui_action() {
  audit_note "Main menu selection: ${UI_ITEMS[$1]:-unknown}"
  case "$1" in
    0)  ui_dashboard;;
    1)  ui_diagnostics;;
    2)  ui_automatic_recovery;;
    3)  ui_installed_system_selector;;
    4)  ui_advanced_recovery;;
    5)  ui_efi_manager;;
    6)  ui_grub_manager;;
    7)  ui_bootorder_manager;;
    8)  ui_filesystem_manager;;
    9)  ui_multiboot_manager;;
    10) ui_logs;;
    11) ui_reports;;
    12) ui_settings;;
    13) ui_help;;
    14) ui_about;;
    15) return 1;;
  esac
}

ui_dashboard() {
  ui_menu_loading 'DEVIL Dashboard' 'Preparing your recovery workspace' \
    'Loading recovery profile' 'Checking repair permissions' 'Preparing dashboard status'
  ui_scrollable_view 'DEVIL Dashboard' 'Safe boot recovery, diagnostics, and recovery planning' "$(ui_dashboard_output)"
}

ui_dashboard_output() {
  printf '%sThis is a professional Linux boot recovery environment.%s\n\n' "$C_GRAY" "$C_RESET"
  printf '%sKey features:%s\n' "$C_WHITE" "$C_RESET"
  printf '  %s• Read-only diagnostics%s — Safe system inspection\n' "$C_GREEN" "$C_RESET"
  printf '  %s• Automatic recovery%s — Conservative bootloader repair\n' "$C_CYAN" "$C_RESET"
  printf '  %s• EFI management%s — Boot entry manipulation\n' "$C_PURPLE" "$C_RESET"
  printf '  %s• GRUB repair%s — Configuration regeneration\n' "$C_ORANGE" "$C_RESET"
  printf '  %s• Multi-boot detection%s — Identify all OSes\n' "$C_RED" "$C_RESET"
  printf '  %s• Filesystem support%s — Ext4, Btrfs, XFS, etc.\n' "$C_GREEN" "$C_RESET"
  printf '\n%sSafety:%s Diagnostics never modify the system.\n' "$C_CYAN" "$C_RESET"
  printf '%sConfirmation:%s Recovery only happens after explicit approval.\n' "$C_ORANGE" "$C_RESET"
  printf '\n%sSystem status:%s\n' "$C_WHITE" "$C_RESET"
  ui_status_line ok 'Read-only diagnostics' 'available without changing the system'
  if [[ ${EUID:-999} -eq 0 ]]; then
    ui_status_line ok 'Repair permissions' 'root access is available'
  else
    ui_status_line warning 'Repair permissions' 'root is required for changes; diagnostics remain available'
  fi
  if efi_available 2>/dev/null; then
    ui_status_line ok 'EFI access' 'firmware boot entries can be inspected'
  elif [[ -d /sys/firmware/efi ]]; then
    ui_status_line warning 'EFI access' 'UEFI is present, but EFI variables cannot be read'
  else
    ui_status_line warning 'EFI access' 'system is not currently booted in UEFI mode'
  fi
  printf '\n%sMode:%s %s\n' "$C_PURPLE" "$C_RESET" "$(recovery_mode_label)"
  printf '%sRead-only:%s %s\n' "$C_GREEN" "$C_RESET" "$([[ ${DEVIL_DRY_RUN} -eq 1 || ${DEVIL_TEST} -eq 1 ]] && echo Yes || echo No)"
}

ui_diagnostics() {
  local output
  ui_menu_loading 'Read-Only Diagnostics' 'Preparing safe system inspection' \
    'Reading system information' 'Inspecting boot configuration' 'Preparing diagnostics report'
  diagnostics_collect
  output=$(printf '%sDiagnostics Report%s\n\n' "$C_PURPLE" "$C_RESET"; ui_colorize_diagnostics 0)
  ui_scrollable_view 'Read-Only Diagnostics' 'Use arrows, Page Up/Down, or mouse wheel to review results' "$output"
}

ui_menu_loading() {
  local title=$1 subtitle=$2 index percent
  shift 2
  local -a stages=("$@")

  ui_screen_header "$title" "$subtitle"
  for index in "${!stages[@]}"; do
    percent=$(((index + 1) * 100 / ${#stages[@]}))
    printf '\r\e[2K%s◆%s %-42s ' "$C_CYAN" "$C_RESET" "${stages[index]}"
    terminal_draw_progress_bar "$percent" 28 "$C_PURPLE"
    sleep 0.14
  done
  printf '\n%s✓%s Ready.\n' "$C_GREEN" "$C_RESET"
  terminal_discard_pending_input
}

ui_colorize_diagnostics() {
  local limit=${1:-0} line label value index=0 printed=0 color state
  local -a colors=("$C_CYAN" "$C_GREEN" "$C_PURPLE" "$C_ORANGE" "$C_RED")
  while IFS= read -r line; do
    case "$line" in
      DEVIL\ v*) printf '%s%s%s\n' "$C_BOLD$C_WHITE" "$line" "$C_RESET" ;;
      Generated:*) printf '%s%s%s\n' "$C_GRAY" "$line" "$C_RESET" ;;
      'System overview'|'Runtime state'|'Security posture'|'Boot configuration'|'Detected installations'|'Storage summary'|'EFI/BootOrder details')
        color=${colors[index % ${#colors[@]}]}
        printf '\n%s%s%s\n' "$C_BOLD$color" "$line" "$C_RESET"
        ((index += 1))
        ;;
      '  '*:*)
        label=${line%%:*}
        value=${line#*:}
        color=${colors[index % ${#colors[@]}]}
        case "${line,,}" in
          *missing*|*invalid*|*unreadable*|*inaccessible*|*'errors detected'*|*'no kernel'*) state=critical ;;
          *unavailable*|*unknown*|*'requires root'*|*'not detected'*|*'no separate'*) state=warning ;;
          *) state=ok ;;
        esac
        ui_status_marker "$state"
        printf '%s%s%s %s%s:%s%s\n' "$UI_STATUS_COLOR" "$UI_STATUS_MARK" "$C_RESET" "$color" "$label" "$C_RESET" "$value"
        ((index += 1))
        ;;
      *) printf '%s\n' "$line" ;;
    esac
    ((printed += 1))
    if ((limit > 0 && printed >= limit)); then
      break
    fi
  done < <(diagnostics_text)
}

ui_automatic_recovery() {
  # Show the read-only assessment before offering the single repair action.
  # This gives the user the information needed to approve a change without
  # immediately starting recovery just because this main-menu item was opened.
  local overview selected=0 offset=0 visible end index button x y action
  local -a overview_lines=()
  ui_automatic_recovery_load_assessment
  overview=$UI_AUTOMATIC_RECOVERY_OVERVIEW
  mapfile -t overview_lines <<<"$overview"
  terminal_mouse_init

  while :; do
    ui_screen_header 'Automatic Recovery' 'Review the assessment before granting repair permission'
    terminal_dimensions
    visible=$((DEVIL_TERM_ROWS - 20))
    ((visible < 2)) && visible=2
    ((offset < 0)) && offset=0
    ((offset > ${#overview_lines[@]} - visible)) && offset=$((${#overview_lines[@]} - visible))
    ((offset < 0)) && offset=0
    end=$((offset + visible))
    ((end > ${#overview_lines[@]})) && end=${#overview_lines[@]}
    for ((index=offset; index<end; index++)); do
      printf '%s\n' "${overview_lines[index]}"
    done
    printf '%sShowing %d-%d of %d%s\n' "$C_GRAY" "$((offset + 1))" "$end" "${#overview_lines[@]}" "$C_RESET"
    printf '\n'
    ui_selectable_button_box "$selected" \
      'Choose installed system to repair (read-only scan)' \
      'Perform Automatic Recovery (requires root)' \
      'Exit to main menu'
    printf '\n%s↑/↓%s navigate  %sEnter%s select  %sq/Esc%s return to main menu' \
      "$C_GREEN" "$C_RESET" "$C_PURPLE" "$C_RESET" "$C_RED" "$C_RESET"

    terminal_read_key || return 0
    case "$DEVIL_KEY" in
      arrow_up|arrow_down|arrow_left|arrow_right) selected=$(((selected + 1) % 3)) ;;
      page_up) ((offset -= visible)) ;;
      page_down) ((offset += visible)) ;;
      home) offset=0 ;;
      end) offset=$((${#overview_lines[@]} - visible)) ;;
      enter|space)
        if ((selected == 2)); then
          return 0
        fi
        if ((selected == 0)); then
          ui_installed_system_selector
          ui_automatic_recovery_load_assessment
          overview=$UI_AUTOMATIC_RECOVERY_OVERVIEW
          mapfile -t overview_lines <<<"$overview"
          offset=0
          continue
        fi
        # Do not allow a key held while selecting this action to approve the
        # following Yes/No privilege prompt.
        terminal_discard_pending_input
        if ui_automatic_recovery_permission; then
          if [[ ${EUID:-999} -ne 0 ]]; then
            recovery_root_required 'Perform Automatic Recovery'
          else
            ui_screen_header 'Automatic Recovery' 'Repair in progress'
            audit_capture 'Automatic Recovery' recovery_automatic --skip-health --confirmed || true
          fi
          printf '\n%s[Press Enter to return to Automatic Recovery]%s' "$C_DIM" "$C_RESET"
          devil_pause '' >/dev/null 2>&1 || true
          ui_automatic_recovery_load_assessment
          overview=$UI_AUTOMATIC_RECOVERY_OVERVIEW
          mapfile -t overview_lines <<<"$overview"
          offset=0
        fi
        ;;
      mouse:*)
        IFS=: read -r _ button x y action <<<"$DEVIL_KEY"
        case "$button:$action" in
          64:M) ((offset -= 3)) ;;
          65:M) ((offset += 3)) ;;
        esac
        ;;
      q|Q|escape) return 0 ;;
    esac
  done
}

ui_automatic_recovery_load_assessment() {
  local index percent
  local -a stages=(
    'Reading system recovery state'
    'Checking boot configuration'
    'Preparing safe recovery assessment'
  )

  ui_screen_header 'Automatic Recovery' 'Preparing a read-only recovery assessment'
  for index in "${!stages[@]}"; do
    percent=$(((index + 1) * 100 / ${#stages[@]}))
    printf '\r\e[2K%s◆%s %-42s ' "$C_CYAN" "$C_RESET" "${stages[index]}"
    terminal_draw_progress_bar "$percent" 28 "$C_PURPLE"
    sleep 0.16
  done
  printf '\n%s✓%s Assessment ready.\n' "$C_GREEN" "$C_RESET"

  diagnostics_collect
  UI_AUTOMATIC_RECOVERY_OVERVIEW=$(ui_automatic_recovery_assessment_report)
  # Discard all keystrokes made while the progress indicator was visible.
  terminal_discard_pending_input
}

ui_automatic_recovery_assessment_report() {
  local grub_state recommendation_state recommendation config
  UI_AUTOMATIC_REPORT_COLOR_INDEX=0
  grub_state=${DIAG[grub_status]:-GRUB_UNKNOWN}
  config=$(grub_config_path 2>/dev/null || true)

  printf '%s%sAutomatic Recovery Assessment Report%s\n' "$C_BOLD$C_WHITE" "$C_CYAN" "$C_RESET"
  printf '%s────────────────────────────────────────────────────────────────────────────%s\n' "$C_PURPLE" "$C_RESET"
  ui_automatic_assessment_line ok 'Firmware' "${DIAG[firmware]:-unknown}"
  ui_automatic_assessment_line info 'Recovery environment' "$(recovery_mode_label)"
  ui_automatic_assessment_line info 'Inspection target' "${DIAG[target_description]:-$(devil_target_description)}"
  if [[ -n "${DEVIL_RECOVERY_ROOT_SPEC:-}" ]]; then
    ui_automatic_assessment_line ok 'Selected repair system' "${DEVIL_RECOVERY_ROOT_SPEC%%|*}"
  else
    ui_automatic_assessment_line warning 'Selected repair system' 'none; recovery will ask if multiple Linux systems are found'
  fi

  case "$grub_state" in
    "$GRUB_STATUS_OK")
      ui_automatic_assessment_line ok 'GRUB assessment' 'configuration is healthy'
      recommendation_state=ok
      recommendation='No automatic repair is recommended.'
      ;;
    "$GRUB_STATUS_EMPTY"|"$GRUB_STATUS_INVALID"|"$GRUB_STATUS_MISSING")
      ui_automatic_assessment_line critical 'GRUB assessment' "${grub_state#GRUB_} configuration issue detected"
      recommendation_state=critical
      if [[ -n "$config" ]]; then
        recommendation='Verified damage can be backed up and repaired automatically.'
      else
        recommendation='Automatic repair is unavailable; select Advanced Recovery for review.'
      fi
      ;;
    "$GRUB_STATUS_PRIVILEGE_REQUIRED"|"$GRUB_STATUS_UNREADABLE"|"$GRUB_STATUS_INACCESSIBLE")
      ui_automatic_assessment_line warning 'GRUB assessment' 'configuration cannot be safely verified with current access'
      recommendation_state=warning
      recommendation='Automatic repair is blocked until GRUB can be verified safely.'
      ;;
    "$GRUB_STATUS_TARGET_REQUIRED")
      ui_automatic_assessment_line warning 'GRUB assessment' 'select one mounted Linux root before validation'
      recommendation_state=warning
      recommendation='Run DEVIL with --target-root PATH to inspect the intended installation.'
      ;;
    *)
      ui_automatic_assessment_line warning 'GRUB assessment' "status: $grub_state"
      recommendation_state=warning
      recommendation='Automatic repair is not recommended until the assessment is conclusive.'
      ;;
  esac

  if devil_target_root_is_offline; then
    recommendation_state=warning
    recommendation='Mounted target is inspected read-only; use guided live-environment reinstall for repairs.'
  fi

  if [[ ${EUID:-999} -eq 0 ]]; then
    ui_automatic_assessment_line ok 'Repair permissions' 'root access is available'
  else
    ui_automatic_assessment_line warning 'Repair permissions' 'root access is required before a repair can run'
  fi
  if [[ "${DIAG[firmware]:-}" == UEFI ]]; then
    if efi_available 2>/dev/null; then
      ui_automatic_assessment_line ok 'EFI access' 'firmware boot entries are available for inspection'
    else
      ui_automatic_assessment_line warning 'EFI access' 'UEFI is active, but EFI variables are unavailable'
    fi
  else
    ui_automatic_assessment_line info 'EFI access' 'not applicable while booted in BIOS mode'
  fi
  ui_automatic_assessment_line "$recommendation_state" 'Recovery recommendation' "$recommendation"
}

ui_automatic_assessment_line() {
  # Status markers retain their semantic colour, while each report row cycles
  # through the DEVIL palette so the generated results are visibly multicolour.
  local state=$1 label=$2 detail=$3 color
  local -a colors=("$C_CYAN" "$C_GREEN" "$C_PURPLE" "$C_ORANGE" "$C_RED")
  color=${colors[UI_AUTOMATIC_REPORT_COLOR_INDEX % ${#colors[@]}]}
  ((UI_AUTOMATIC_REPORT_COLOR_INDEX += 1))
  ui_status_marker "$state"
  printf '%s%s%s %s%s%s %s—%s %s%s%s\n' \
    "$UI_STATUS_COLOR" "$UI_STATUS_MARK" "$C_RESET" \
    "$C_BOLD$color" "$label" "$C_RESET" \
    "$color" "$C_RESET" "$color" "$detail" "$C_RESET"
}

ui_automatic_recovery_permission() {
  local selection
  terminal_select_menu 'Automatic Recovery Permission' \
    'No — return without making changes' \
    'Yes — grant permission to back up and repair verified GRUB damage' || return 1
  selection=$DEVIL_MENU_SELECTION
  # No is deliberately highlighted first.  Yes requires deliberate navigation
  # and selection, so an extra Enter can never authorise a repair.
  [[ "$selection" -eq 1 ]]
}

ui_installed_system_selector() {
  local entry dev opts name selection
  local -a entries=() labels=()
  mapfile -t entries < <(recovery_discover_linux_roots)
  if ((${#entries[@]} == 0)); then
    ui_message 'Installed System Selector' 'No repairable Linux roots were found. Unlock encrypted storage first, then retry.'
    return 0
  fi
  for entry in "${entries[@]}"; do
    IFS=$'\t' read -r dev opts name <<<"$entry"
    labels+=("$name — $dev ($opts)")
  done
  labels+=('Clear selection (ask during recovery)' 'Exit to main menu')
  terminal_select_menu 'Installed System Selector' "${labels[@]}" || return 0
  selection=$DEVIL_MENU_SELECTION
  if ((selection < ${#entries[@]})); then
    IFS=$'\t' read -r dev opts name <<<"${entries[selection]}"
    DEVIL_RECOVERY_ROOT_SPEC="$dev|$opts"
    audit_note "Selected installed system for recovery: $name on $dev ($opts)"
    printf 'Selected %s on %s for guided recovery.\n' "$name" "$dev"
    devil_pause 'Press Enter to return to the main menu...'
  elif ((selection == ${#entries[@]})); then
    DEVIL_RECOVERY_ROOT_SPEC=''
    audit_note 'Cleared installed-system recovery selection'
  fi
}

ui_advanced_recovery() {
  printf '\e[2J\e[H'
  recovery_advanced_grub
}

ui_efi_manager() {
  printf '\e[2J\e[H'
  recovery_efi_manager
}

ui_efi_create_entry() {
  printf '\e[2J\e[H'
  printf '%sCreate EFI Boot Entry%s\n' "$C_WHITE" "$C_RESET"
  printf '===================\n\n'
  printf 'Label: '; read -r label
  printf 'Loader path (e.g. /EFI/Boot/bootx64.efi): '; read -r loader
  printf 'Disk (e.g. /dev/sda): '; read -r disk
  printf 'Partition (1-based number): '; read -r partition
  
  require_root
  efi_create_entry "$label" "$loader" "$disk" "$partition"
  devil_pause '' >/dev/null 2>&1 || true
}

ui_confirm_action() {
  local action=$1
  printf '\n%sSelected:%s %s\n' "$C_CYAN" "$C_RESET" "$action"
  confirm "Continue with this action?"
}

ui_grub_manager() {
  local selection
  while :; do
    terminal_select_menu 'GRUB Manager' \
      'Validate GRUB (read-only)' \
      'Regenerate GRUB (root required)' \
      'List GRUB menu entries (read-only)' \
      'Check os-prober (read-only)' \
      'Restore from backup (root required)' \
      'Exit to main menu' || return 0
    selection=$DEVIL_MENU_SELECTION

    case "$selection" in
      0) ui_confirm_action 'Validate GRUB' && grub_validate || true ;;
      1)
        if ! ui_confirm_action 'Regenerate GRUB'; then :
        elif [[ ${EUID:-999} -ne 0 ]]; then recovery_root_required 'Regenerate GRUB configuration'
        else grub_regenerate || true
        fi ;;
      2) ui_confirm_action 'List GRUB menu entries' && grub_list_entries || true ;;
      3) ui_confirm_action 'Check os-prober' && grub_check_os_prober || true ;;
      4)
        if ! ui_confirm_action 'Restore GRUB from backup'; then :
        elif [[ ${EUID:-999} -ne 0 ]]; then recovery_root_required 'Restore GRUB from backup'
        else grub_restore_from_backup || true
        fi ;;
      5) return 0 ;;
    esac
    devil_pause 'Press Enter to return to GRUB Manager...'
  done
}

ui_bootorder_manager() {
  local selection
  while :; do
    terminal_select_menu 'BootOrder Manager' \
      'Inspect BootOrder and firmware entries (read-only)' \
      'List colour-coded EFI boot entries (read-only)' \
      'Exit to main menu' || return 0
    selection=$DEVIL_MENU_SELECTION
    case "$selection" in
      0) ui_confirm_action 'Inspect BootOrder and firmware entries' && recovery_bootorder_repair || true ;;
      1) ui_confirm_action 'List colour-coded EFI boot entries' && efi_list || true ;;
      2) return 0 ;;
    esac
    devil_pause 'Press Enter to return to BootOrder Manager...'
  done
}

ui_filesystem_manager() {
  local selection
  while :; do
    terminal_select_menu 'Filesystem Manager' \
      'Summary (read-only)' \
      'List all filesystems (read-only)' \
      'List Ext4 filesystems (read-only)' \
      'List Btrfs filesystems (read-only)' \
      'Show mount information (read-only)' \
      'Show disk space usage (read-only)' \
      'Exit to main menu' || return 0
    selection=$DEVIL_MENU_SELECTION
    case "$selection" in
      0) ui_confirm_action 'Show filesystem summary' && filesystem_summary || true ;;
      1) ui_confirm_action 'List all filesystems' && filesystem_detect_all || true ;;
      2) ui_confirm_action 'List Ext4 filesystems' && filesystem_list_ext4 || true ;;
      3) ui_confirm_action 'List Btrfs filesystems' && filesystem_list_btrfs || true ;;
      4) ui_confirm_action 'Show mount information' && filesystem_get_mount_info || true ;;
      5) ui_confirm_action 'Show disk space usage' && filesystem_check_disk_space || true ;;
      6) return 0 ;;
    esac
    devil_pause 'Press Enter to return to Filesystem Manager...'
  done
}

ui_multiboot_manager() {
  local selection
  while :; do
    terminal_select_menu 'Multi-Boot Manager' \
      'Scan for installed operating systems (read-only)' \
      'Exit to main menu' || return 0
    selection=$DEVIL_MENU_SELECTION
    [[ "$selection" -eq 1 ]] && return 0
    if ui_confirm_action 'Scan for installed operating systems'; then
      if declare -F multiboot_report >/dev/null; then
        multiboot_report || true
      else
        printf '%sMulti-boot module is unavailable.%s\n' "$C_ORANGE" "$C_RESET"
      fi
    fi
    devil_pause 'Press Enter to return to Multi-Boot Manager...'
  done
}

ui_logs() {
  local output
  if [[ -n "${DEVIL_LOG_FILE:-}" && -f "${DEVIL_LOG_FILE}" ]]; then
    output=$(ui_colorize_log_output < <(tail -100 "${DEVIL_LOG_FILE}"))
  else
    output=$(printf '%s•%s %sNo session log file is available yet.%s' "$C_ORANGE" "$C_RESET" "$C_ORANGE" "$C_RESET")
  fi
  ui_scrollable_view 'Session Logs' 'Use arrows, Page Up/Down, or mouse wheel to review events' "$output"
}

ui_reports() {
  local report_output output
  ui_screen_header 'Generate Reports' 'Collecting diagnostics and writing report files'
  ui_report_progress 'Collecting read-only diagnostics' 15
  diagnostics_collect
  ui_report_progress 'Preparing text and JSON reports' 55
  ui_report_progress 'Writing report files and archive' 70
  report_output=$(report_write)
  ui_report_progress 'Finalising report output' 100
  printf '\n%s✓%s Reports are ready.\n' "$C_GREEN" "$C_RESET"
  terminal_discard_pending_input
  output=$(ui_colorize_report_output <<<"$report_output"; printf '%s✓%s %sReports generated in:%s %s%s%s\n' \
    "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_PURPLE" "$DEVIL_REPORT_DIR" "$C_RESET")
  ui_scrollable_view 'Generate Reports' 'Use arrows, Page Up/Down, or mouse wheel to review output' "$output"
}

ui_report_progress() {
  local stage=$1 percent=$2
  printf '\r\e[2K%s◆%s %-42s ' "$C_CYAN" "$C_RESET" "$stage"
  terminal_draw_progress_bar "$percent" 28 "$C_PURPLE"
}

ui_settings() {
  local output
  output=$(ui_settings_output)
  ui_scrollable_view 'Settings' 'Use arrows, Page Up/Down, or mouse wheel to review configuration' "$output"
}

ui_settings_output() {
  ui_settings_output_line "$C_CYAN" 'Theme' "${DEVIL_SETTINGS[theme]}"
  ui_settings_output_line "$C_GREEN" 'Mouse' "${DEVIL_SETTINGS[mouse]}"
  ui_settings_output_line "$C_PURPLE" 'Report detail' "${DEVIL_SETTINGS[report_detail]}"
  printf '\n%sFlags%s\n' "$C_BOLD$C_ORANGE" "$C_RESET"
  ui_settings_output_line "$C_ORANGE" 'Dry-run' "${DEVIL_DRY_RUN}"
  ui_settings_output_line "$C_RED" 'Safe mode' "${DEVIL_SAFE}"
  ui_settings_output_line "$C_CYAN" 'Test mode' "${DEVIL_TEST}"
  ui_settings_output_line "$C_GREEN" 'Debug mode' "${DEVIL_DEBUG}"
}

ui_colorize_log_output() {
  local line color
  while IFS= read -r line; do
    case "$line" in
      *'[ERROR]'*) color=$C_RED ;;
      *'[WARN]'*) color=$C_ORANGE ;;
      *'[ACTION]'*) color=$C_PURPLE ;;
      *'[DEBUG]'*) color=$C_GRAY ;;
      *'[INFO]'*) color=$C_CYAN ;;
      *) color=$C_WHITE ;;
    esac
    printf '%s%s%s\n' "$color" "$line" "$C_RESET"
  done
}

ui_colorize_report_output() {
  local line color
  while IFS= read -r line; do
    case "$line" in
      'Reports saved:'*) color="$C_BOLD$C_WHITE" ;;
      '  Text:'*) color=$C_CYAN ;;
      '  JSON:'*) color=$C_GREEN ;;
      '  Archive:'*) color=$C_PURPLE ;;
      *) color=$C_GRAY ;;
    esac
    printf '%s%s%s\n' "$color" "$line" "$C_RESET"
  done
}

ui_settings_output_line() {
  local color=$1 label=$2 value=$3
  printf '%s•%s %s%s:%s %s%s%s\n' \
    "$color" "$C_RESET" "$C_BOLD$color" "$label" "$C_RESET" "$color" "$value" "$C_RESET"
}

ui_selectable_button_box() {
  # Use one renderer for action buttons.  In particular, do not pad a string
  # with ASCII markers so terminals with differing Unicode-width rules keep
  # the right border in exactly the same column.
  local selected=$1 index label width inside rule
  shift
  terminal_dimensions
  width=$((DEVIL_TERM_COLS - 2))
  ((width > 78)) && width=78
  ((width < 42)) && width=42
  inside=$((width - 2))
  printf -v rule '%*s' "$inside" ''
  rule=${rule// /─}

  printf '%s╭%s╮%s\n' "$C_GREEN" "$rule" "$C_RESET"
  for index in "$@"; do
    label=$index
    if ((selected == 0)); then
      printf '%s│%s%s>  ' "$C_GREEN" "$C_RESET" "$C_REVERSE$C_ORANGE$C_BOLD"
      terminal_print_padded_text "$label" "$((inside - 3))"
      printf '%s%s│%s\n' "$C_RESET$C_GREEN" "$C_RESET"
    else
      printf '%s│%s   ' "$C_GREEN" "$C_RESET"
      terminal_print_padded_text "$label" "$((inside - 3))"
      printf '%s%s│%s\n' "$C_GREEN" "$C_RESET"
    fi
    selected=$((selected - 1))
  done
  printf '%s╰%s╯%s\n' "$C_GREEN" "$rule" "$C_RESET"
}

ui_exit_to_main_menu_button() {
  printf '\n'
  ui_selectable_button_box 0 'Exit to main menu'
  printf '\n%sEnter%s select  %sq/Esc%s return to main menu' "$C_PURPLE" "$C_RESET" "$C_RED" "$C_RESET"
  terminal_is_interactive || return 0
  while terminal_read_key; do
    case "$DEVIL_KEY" in
      enter|space|q|Q|escape|mouse:0:*:*:M) return 0 ;;
    esac
  done
}

ui_scrollable_view() {
  # A real viewport for generated terminal reports.  Unlike terminal
  # scrollback, it remains available after DEVIL redraws the screen.
  local title=$1 subtitle=$2 content=$3 line
  local offset=0 visible end start_row=13 button_row
  local button x y action
  local -a lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done <<<"$content"

  if ! terminal_is_interactive; then
    printf '%s\n' "$content"
    return 0
  fi
  terminal_mouse_init
  while :; do
    ui_screen_header "$title" "$subtitle"
    terminal_dimensions
    visible=$((DEVIL_TERM_ROWS - 18))
    ((visible < 2)) && visible=2
    ((offset < 0)) && offset=0
    ((offset > ${#lines[@]} - visible)) && offset=$((${#lines[@]} - visible))
    ((offset < 0)) && offset=0
    end=$((offset + visible))
    ((end > ${#lines[@]})) && end=${#lines[@]}
    for ((; offset < end; offset++)); do
      printf '%s\n' "${lines[offset]}"
    done
    # Restore the viewport start after using the loop index for printing.
    offset=$((end - visible))
    ((offset < 0)) && offset=0
    printf '%sShowing %d-%d of %d%s\n' "$C_GRAY" "$((offset + 1))" "$end" "${#lines[@]}" "$C_RESET"
    ui_selectable_button_box 0 'Exit to main menu'
    printf '%s↑/↓%s scroll  %sPgUp/PgDn%s page  %sWheel%s scroll  %sm%s mouse select  %sEnter/click%s exit' \
      "$C_GREEN" "$C_RESET" "$C_PURPLE" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_GRAY" "$C_RESET" "$C_ORANGE" "$C_RESET"

    terminal_read_key || return 0
    case "$DEVIL_KEY" in
      arrow_up) ((offset -= 1)) ;;
      arrow_down) ((offset += 1)) ;;
      page_up) ((offset -= visible)) ;;
      page_down) ((offset += visible)) ;;
      home) offset=0 ;;
      end) offset=$((${#lines[@]} - visible)) ;;
      m|M)
        if ((DEVIL_MOUSE_ENABLED)); then terminal_disable_mouse; else terminal_mouse_init; fi
        ;;
      enter|space|q|Q|escape) return 0 ;;
      mouse:*)
        IFS=: read -r _ button x y action <<<"$DEVIL_KEY"
        case "$button:$action" in
          64:M) ((offset -= 3)) ;;
          65:M) ((offset += 3)) ;;
          0:M)
            button_row=$((start_row + visible + 1))
            ((y >= button_row)) && return 0
            ;;
        esac
        ;;
    esac
  done
}

ui_help() {
  local output
  output=$(ui_help_output)
  ui_scrollable_view 'Help & Safety Guide' 'Use arrows, Page Up/Down, or mouse wheel to read' "$output"
}

ui_help_output() {
  printf '%sDIAGNOSTICS:%s Read-only system inspection with no modifications.\n' "$C_CYAN" "$C_RESET"
  printf '%sAUTOMATIC RECOVERY:%s Conservative repair of detected bootloader issues.\n' "$C_GREEN" "$C_RESET"
  printf '%sEFI MANAGER:%s View and modify EFI boot entries.\n' "$C_PURPLE" "$C_RESET"
  printf '%sGRUB MANAGER:%s Validate and regenerate GRUB configuration.\n' "$C_ORANGE" "$C_RESET"
  printf '%sFILESYSTEM MANAGER:%s Inspect storage layout and detect encrypted/RAID volumes.\n' "$C_RED" "$C_RESET"
  printf '\n%sSafety rule:%s All changes require explicit confirmation before execution.\n' "$C_ORANGE" "$C_RESET"
}

ui_about() {
  local output
  output=$(ui_about_output)
  ui_scrollable_view 'About DEVIL' 'Use arrows, Page Up/Down, or mouse wheel to read' "$output"
}

ui_about_output() {
  printf '%sA comprehensive, read-only-first Linux boot recovery utility.%s\n' "$C_GRAY" "$C_RESET"
  printf '\n%sFeatures:%s\n' "$C_WHITE" "$C_RESET"
  printf '  %s• Safe diagnostics%s\n' "$C_GREEN" "$C_RESET"
  printf '  %s• Conservative recovery%s\n' "$C_CYAN" "$C_RESET"
  printf '  %s• Multi-distribution support%s\n' "$C_PURPLE" "$C_RESET"
  printf '  %s• UEFI and BIOS support%s\n' "$C_ORANGE" "$C_RESET"
  printf '  %s• Professional terminal UI%s\n' "$C_RED" "$C_RESET"
  printf '\n%sSupported Distributions:%s\n' "$C_WHITE" "$C_RESET"
  printf '%s  Arch, Garuda, Debian, Ubuntu, Fedora, Manjaro, and more%s\n' "$C_CYAN" "$C_RESET"
  printf '\n%sAuthor:%s DEVIL Contributors\n' "$C_PURPLE" "$C_RESET"
  printf '%sLicense:%s GPL-2.0\n' "$C_GREEN" "$C_RESET"
}

ui_start() {
  if ! terminal_is_interactive; then
    printf 'Interactive UI requires a terminal; use --diagnose, --report, or --recovery-plan.\n'
    return 0
  fi
  
  terminal_detect_capabilities
  terminal_color_init
  terminal_home_menu || {
    terminal_restore
    return 0
  }
  terminal_startup_loading
  ui_startup_report
  
  ui_select || true
  terminal_restore
}

ui_startup_report() {
  ui_screen_header 'Startup Assessment' 'Collecting and saving a full read-only report'
  ui_report_progress 'Running all read-only module checks' 25
  ui_report_progress 'Collecting boot, storage, EFI, and recovery data' 60
  if full_report_write; then
    ui_report_progress 'Saving full report and session audit trail' 100
    printf '\n%s✓%s Full startup report saved in %s\n' "$C_GREEN" "$C_RESET" "$DEVIL_REPORT_DIR"
  else
    ui_report_progress 'Reports unavailable at this tool location' 100
    printf '\n%s⚠%s The tool-local reports folder is not writable; no startup report was saved.\n' "$C_ORANGE" "$C_RESET"
  fi
  sleep 0.7
}
