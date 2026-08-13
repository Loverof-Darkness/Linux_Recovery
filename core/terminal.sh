#!/usr/bin/env bash
# Terminal capability detection, presentation helpers, and keyboard input.
# This module deliberately uses ANSI escape sequences rather than dialog,
# whiptail, ncurses, or a terminal-specific UI framework.

DEVIL_COLOR_LEVEL=${DEVIL_COLOR_LEVEL:-0}
DEVIL_RENDERER_STATUS=${DEVIL_RENDERER_STATUS:-"not selected"}
DEVIL_MOUSE_ENABLED=${DEVIL_MOUSE_ENABLED:-0}
DEVIL_CURSOR_HIDDEN=${DEVIL_CURSOR_HIDDEN:-0}
DEVIL_KEY=${DEVIL_KEY:-}
DEVIL_MOUSE_BUTTON=${DEVIL_MOUSE_BUTTON:-}
DEVIL_MOUSE_X=${DEVIL_MOUSE_X:-}
DEVIL_MOUSE_Y=${DEVIL_MOUSE_Y:-}

terminal_is_interactive() {
  [[ -t 0 && -t 1 && "${TERM:-dumb}" != "dumb" ]]
}

terminal_color_init() {
  local color_term=${COLORTERM,,}

  if [[ "${DEVIL_FORCE_COLOR:-0}" != 1 && ( -n "${NO_COLOR+x}" || "${TERM:-dumb}" == "dumb" || ! -t 1 ) ]]; then
    DEVIL_COLOR_LEVEL=0
    C_RED='' C_CRIMSON='' C_ORANGE='' C_GREEN='' C_CYAN='' C_PURPLE='' C_GRAY='' C_WHITE='' C_BLACK=''
    C_DIM='' C_BOLD='' C_REVERSE='' C_RESET='' C_CLEAR=''
    return 0
  fi

  C_DIM=$'\e[2m'
  C_BOLD=$'\e[1m'
  C_REVERSE=$'\e[7m'
  C_RESET=$'\e[0m'
  C_CLEAR=$'\e[2J\e[H'
  C_BLACK=$'\e[38;5;16m'

  if [[ "$color_term" == *truecolor* || "$color_term" == *24bit* || "${TERM:-}" == *-direct ]]; then
    DEVIL_COLOR_LEVEL=16777216
    C_RED=$'\e[38;2;214;30;30m'
    C_CRIMSON=$'\e[38;2;150;15;28m'
    C_ORANGE=$'\e[38;2;255;112;18m'
    C_GREEN=$'\e[38;2;92;187;92m'
    C_CYAN=$'\e[38;2;70;190;210m'
    C_PURPLE=$'\e[38;2;183;82;255m'
    C_GRAY=$'\e[38;2;150;150;150m'
    C_WHITE=$'\e[38;2;242;242;242m'
  elif [[ "${TERM:-}" == *256color* || "${TERM:-}" == screen* || "${TERM:-}" == tmux* ]]; then
    DEVIL_COLOR_LEVEL=256
    C_RED=$'\e[38;5;196m'
    C_CRIMSON=$'\e[38;5;88m'
    C_ORANGE=$'\e[38;5;208m'
    C_GREEN=$'\e[38;5;118m'
    C_CYAN=$'\e[38;5;45m'
    C_PURPLE=$'\e[38;5;135m'
    C_GRAY=$'\e[38;5;245m'
    C_WHITE=$'\e[38;5;255m'
  else
    DEVIL_COLOR_LEVEL=16
    C_RED=$'\e[31m'
    C_CRIMSON=$'\e[31m'
    C_ORANGE=$'\e[33m'
    C_GREEN=$'\e[32m'
    C_CYAN=$'\e[36m'
    C_PURPLE=$'\e[35m'
    C_GRAY=$'\e[37m'
    C_WHITE=$'\e[97m'
  fi
}

terminal_load_theme() {
  # Themes are selected from the validated configuration, not sourced directly
  # from arbitrary user input.
  local theme=pitch-black
  if declare -p DEVIL_SETTINGS >/dev/null 2>&1; then
    theme=${DEVIL_SETTINGS[theme]:-$theme}
  fi

  case "$theme" in
    pitch-black)
      # shellcheck source=themes/pitch-black.sh
      source "$DEVIL_ROOT/themes/pitch-black.sh"
      ;;
    *)
      debug "unknown theme requested: $theme; using pitch-black"
      # shellcheck source=themes/pitch-black.sh
      source "$DEVIL_ROOT/themes/pitch-black.sh"
      ;;
  esac
}

terminal_detect_name() {
  if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
    printf 'Kitty'
  elif [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
    printf 'iTerm2'
  elif [[ -n "${KONSOLE_VERSION:-}" ]]; then
    printf 'Konsole'
  elif [[ -n "${WEZTERM_EXECUTABLE:-}" || "${TERM_PROGRAM:-}" == "WezTerm" ]]; then
    printf 'WezTerm'
  elif [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
    printf 'Apple Terminal'
  elif [[ -n "${VTE_VERSION:-}" ]]; then
    printf 'VTE (%s)' "${TERM:-terminal}"
  elif [[ "${TERM:-}" == foot* ]]; then
    printf 'foot'
  elif [[ "${TERM:-}" == linux ]]; then
    printf 'Linux TTY'
  elif [[ -n "${TERM:-}" ]]; then
    printf '%s' "$TERM"
  else
    printf 'unknown terminal'
  fi
}

terminal_image_file() {
  local image
  if [[ -n "${DEVIL_BRANDING_IMAGE:-}" ]]; then
    image="$DEVIL_BRANDING_IMAGE"
  else
    local root=${DEVIL_ROOT:-}
    if [[ -z "$root" ]]; then
      root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
    fi
    image="$root/assets/devil.png"
  fi

  [[ -r "$image" && -f "$image" ]] || return 1
  printf '%s' "$image"
}

terminal_can_kitty_graphics() {
  [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == *kitty* ]] && have kitty
}

terminal_can_kitten_icat() {
  [[ -n "${KITTY_WINDOW_ID:-}" || "${TERM:-}" == *kitty* ]] && have kitten
}

terminal_can_iterm2() {
  # Konsole supports the iTerm2 image protocol, but sudo commonly removes its
  # KONSOLE_VERSION variable. Detect the terminal process as a fallback.
  local konsole=0 parent
  [[ -n "${KONSOLE_VERSION:-}" ]] && konsole=1
  parent=$PPID
  for _ in 1 2 3 4; do
    if ps -p "$parent" -o comm= 2>/dev/null | grep -qi '^konsole$'; then konsole=1; break; fi
    parent=$(ps -p "$parent" -o ppid= 2>/dev/null | tr -d ' ') || break
  done
  { [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]] || (( konsole )); } && have base64
}

terminal_is_konsole() {
  [[ -n "${KONSOLE_VERSION:-}" ]] && return 0
  local parent=$PPID
  for _ in 1 2 3 4; do
    ps -p "$parent" -o comm= 2>/dev/null | grep -qi '^konsole$' && return 0
    parent=$(ps -p "$parent" -o ppid= 2>/dev/null | tr -d ' ') || break
  done
  return 1
}

terminal_can_sixel() {
  [[ -n "${TERM:-}" ]] && grep -qi sixel <(infocmp -L2 2>/dev/null || echo "") && have base64
}

terminal_can_chafa() {
  have chafa
}

terminal_can_viu() {
  have viu
}

# libcaca is commonly present on rescue/live images even when chafa/viu are
# not.  img2txt emits ANSI true-colour text and works over sudo without any
# user-session graphics environment.
terminal_can_img2txt() {
  have img2txt
}

terminal_can_ueberzugpp() {
  [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" && "${TERM:-dumb}" != "dumb" ]] && have ueberzugpp
}

terminal_select_renderer() {
  local image
  image=$(terminal_image_file) || { DEVIL_RENDERER=ansi; return 0; }

  if terminal_can_kitty_graphics; then
    DEVIL_RENDERER=kitty-graphics
  elif terminal_can_kitten_icat; then
    DEVIL_RENDERER=kitten-icat
  elif terminal_can_iterm2; then
    DEVIL_RENDERER=iterm
  elif terminal_can_sixel; then
    DEVIL_RENDERER=sixel
  elif terminal_can_chafa; then
    DEVIL_RENDERER=chafa
  elif terminal_can_viu; then
    DEVIL_RENDERER=viu
  elif terminal_can_img2txt; then
    DEVIL_RENDERER=img2txt
  elif terminal_can_ueberzugpp; then
    DEVIL_RENDERER=ueberzugpp
  else
    DEVIL_RENDERER=ansi
  fi
  return 0
}

terminal_mouse_init() {
  if [[ "${DEVIL_SETTINGS[mouse]}" == "auto" ]]; then
    printf '\e[?1000;1006;1015h'
    DEVIL_MOUSE_ENABLED=1
  fi
}

terminal_wait_for_input() {
  local timeout=${1:-0}
  if ! terminal_is_interactive; then
    return 1
  fi
  if [[ "$timeout" -gt 0 ]]; then
    read -r -t "$timeout" _ || return 1
  else
    read -r _ || return 1
  fi
}

terminal_draw_box() {
  local x=$1 y=$2 width=$3 height=$4 title=${5:-} color=${6:-$C_WHITE}
  local i

  printf '\e[%d;%dH%s┌' "$y" "$x" "$color"
  for ((i=0; i<width-2; i++)); do printf '─'; done
  printf '┐%s' "$C_RESET"

  for ((i=1; i<height-1; i++)); do
    printf '\e[%d;%dH%s│%*s│%s' "$((y+i))" "$x" "$color" "$((width-2))" "" "$C_RESET"
  done

  printf '\e[%d;%dH%s└' "$((y+height-1))" "$x" "$color"
  for ((i=0; i<width-2; i++)); do printf '─'; done
  printf '┘%s' "$C_RESET"

  if [[ -n "$title" ]]; then
    printf '\e[%d;%dH%s %s %s' "$y" "$((x+2))" "$color" "$title" "$C_RESET"
  fi
}

terminal_draw_progress_bar() {
  local percent=$1 width=${2:-40} color=${3:-$C_ORANGE}
  local filled=$((percent * width / 100))
  local empty=$((width - filled))

  printf '%s[' "$color"
  for ((i=0; i<filled; i++)); do printf '█'; done
  for ((i=0; i<empty; i++)); do printf '░'; done
  printf '] %3d%%%s' "$percent" "$C_RESET"
}

terminal_startup_loading() {
  local -a stages=('Loading terminal palette' 'Checking recovery modules' 'Reading system profile' 'Preparing dashboard')
  local index total=${#stages[@]} percent
  terminal_clear
  terminal_move_to 4 4
  printf '%s%sDEVIL%s  %sPreparing your recovery workspace%s' "$C_RED" "$C_BOLD" "$C_RESET" "$C_GRAY" "$C_RESET"
  terminal_move_to 6 4
  for index in "${!stages[@]}"; do
    percent=$(( (index + 1) * 100 / total ))
    printf '\r\e[2K%s◆%s %-30s ' "$C_CYAN" "$C_RESET" "${stages[index]}"
    terminal_draw_progress_bar "$percent" 28 "$C_PURPLE"
    sleep 0.12
  done
  printf '\n%s✓%s Dashboard ready.\n' "$C_GREEN" "$C_RESET"
  sleep 0.18
}

terminal_select_menu() {
  # Interactive, keyboard-navigable submenu.  The result is written to
  # DEVIL_MENU_SELECTION so the screen output is not captured by callers.
  local title=$1
  shift
  local -a options=("$@")
  local count=${#options[@]} selected=0 offset=0 index visible end button x y action clicked
  local box_width box_inside box_rule number label_width
  DEVIL_MENU_SELECTION=-1

  if ! terminal_is_interactive; then
    printf '%s\n' "$title"
    for index in "${!options[@]}"; do
      printf '  %d. %s\n' "$((index + 1))" "${options[index]}"
    done
    printf 'Select an option: '
    read -r index || return 1
    [[ "$index" =~ ^[1-9][0-9]*$ && "$index" -le "$count" ]] || return 1
    DEVIL_MENU_SELECTION=$((index - 1))
    declare -F audit_note >/dev/null && audit_note "Menu selection: $title — ${options[DEVIL_MENU_SELECTION]}"
    return 0
  fi

  terminal_mouse_init

  while :; do
    terminal_clear
    # All selectable submenus share the same full DEVIL ANSI masthead as the
    # dashboard, Help, and About screens.
    terminal_devil_large_wordmark_at 1 2
    terminal_move_to 8 2
    printf '%sDEVIL v%s%s  %sEmergency Verification & Intelligent Linux Recovery%s' \
      "$C_BOLD$C_CYAN" "${DEVIL_VERSION:-unknown}" "$C_RESET" "$C_CYAN" "$C_RESET"
    terminal_move_to 9 2
    printf '%s────────────────────────────────────────────────────────────────────────────%s' "$C_PURPLE" "$C_RESET"
    terminal_move_to 11 2
    printf '%s%s%s\n\n' "$C_BOLD$C_WHITE" "$title" "$C_RESET"
    terminal_dimensions
    box_width=$((DEVIL_TERM_COLS - 3))
    ((box_width > 78)) && box_width=78
    ((box_width < 42)) && box_width=42
    box_inside=$((box_width - 2))
    printf -v box_rule '%*s' "$box_inside" ''
    box_rule=${box_rule// /─}
    visible=$((DEVIL_TERM_ROWS - 17))
    ((visible < 2)) && visible=2
    ((selected < offset)) && offset=$selected
    ((selected >= offset + visible)) && offset=$((selected - visible + 1))
    end=$((offset + visible))
    ((end > count)) && end=$count
    terminal_move_to 13 2
    printf '%s┌%s┐%s\n' "$C_PURPLE" "$box_rule" "$C_RESET"
    for ((index=offset; index<end; index++)); do
      terminal_move_to "$((14 + index - offset))" 2
      number=$((index + 1))
      if ((index == selected)); then
        label_width=$((box_inside - 5 - ${#number}))
        printf '%s│%s> [%d] ' "$C_PURPLE" "$C_REVERSE$C_ORANGE$C_BOLD" "$number"
        terminal_print_padded_text "${options[index]}" "$label_width"
        printf '%s│%s\n' "$C_RESET$C_PURPLE" "$C_RESET"
      else
        label_width=$((box_inside - 4 - ${#number}))
        printf '%s│%s  %d. ' "$C_PURPLE" "$(case $((index % 3)) in 0) printf '%s' "$C_CYAN";; 1) printf '%s' "$C_GREEN";; *) printf '%s' "$C_PURPLE";; esac)" "$number"
        terminal_print_padded_text "${options[index]}" "$label_width"
        printf '%s│%s\n' "$C_RESET$C_PURPLE" "$C_RESET"
      fi
    done
    terminal_move_to "$((14 + end - offset))" 2
    printf '%s└%s┘%s\n' "$C_PURPLE" "$box_rule" "$C_RESET"
    printf '\n%s↑/↓/wheel%s scroll  %sEnter/click%s select  %s1-%d%s quick select  %sq/Esc%s back' \
      "$C_GREEN" "$C_RESET" "$C_PURPLE" "$C_RESET" "$C_CYAN" "$count" "$C_RESET" "$C_RED" "$C_RESET"

    terminal_read_key || return 1
    case "$DEVIL_KEY" in
      arrow_up|arrow_left) selected=$(( (selected + count - 1) % count )) ;;
      arrow_down|arrow_right) selected=$(( (selected + 1) % count )) ;;
      home) selected=0 ;;
      end) selected=$((count - 1)) ;;
      page_up)
        ((selected -= visible))
        ((selected < 0)) && selected=0
        ;;
      page_down)
        ((selected += visible))
        ((selected >= count)) && selected=$((count - 1))
        ;;
      enter|space)
        DEVIL_MENU_SELECTION=$selected
        declare -F audit_note >/dev/null && audit_note "Menu selection: $title — ${options[selected]}"
        return 0
        ;;
      q|Q|escape) return 1 ;;
      [1-9])
        if ((DEVIL_KEY <= count)); then
          DEVIL_MENU_SELECTION=$((DEVIL_KEY - 1))
          declare -F audit_note >/dev/null && audit_note "Menu selection: $title — ${options[DEVIL_MENU_SELECTION]}"
          return 0
        fi
        ;;
      mouse:*)
        IFS=: read -r _ button x y action <<<"$DEVIL_KEY"
        case "$button:$action" in
          64:M) ((selected -= 3)); ((selected < 0)) && selected=0 ;;
          65:M) ((selected += 3)); ((selected >= count)) && selected=$((count - 1)) ;;
          0:M)
            # Option rows begin below the submenu's top border.
            if ((y >= 14 && y < 14 + visible)); then
              clicked=$((offset + y - 14))
              if ((clicked < count)); then
                DEVIL_MENU_SELECTION=$clicked
                declare -F audit_note >/dev/null && audit_note "Menu selection: $title — ${options[clicked]}"
                return 0
              fi
            fi
            ;;
        esac
        ;;
    esac
  done
}

terminal_detect_distro() {
  if [[ -f /etc/os-release ]]; then
    DEVIL_DISTRO=$(grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  elif [[ -f /etc/lsb-release ]]; then
    DEVIL_DISTRO=$(grep '^DISTRIB_ID=' /etc/lsb-release | cut -d'=' -f2)
  elif [[ -f /etc/system-release ]]; then
    DEVIL_DISTRO=$(head -1 /etc/system-release)
  else
    DEVIL_DISTRO="Generic Linux"
  fi
}

terminal_detect_capabilities() {
  terminal_color_init
  DEVIL_TERM=$(terminal_detect_name)
  terminal_detect_distro
  terminal_detect_renderer
}

terminal_renderer_available() {
  case "$1" in
    kitty-graphics) terminal_can_kitty_graphics ;;
    kitten-icat) terminal_can_kitten_icat ;;
    iterm|iterm2) terminal_can_iterm2 ;;
    sixel) terminal_can_sixel ;;
    chafa|viu|img2txt) have "$1" ;;
    ueberzugpp) terminal_can_ueberzugpp ;;
    ansi) return 0 ;;
    *) return 1 ;;
  esac
}

terminal_detect_renderer() {
  local requested=${DEVIL_RENDERER_REQUEST:-auto}

  if [[ "$requested" != auto ]]; then
    if terminal_renderer_available "$requested"; then
      DEVIL_RENDERER=$requested
      DEVIL_RENDERER_STATUS="forced by DEVIL_RENDERER_REQUEST"
    else
      DEVIL_RENDERER=ansi
      DEVIL_RENDERER_STATUS="requested renderer '$requested' is unavailable; using ANSI"
    fi
    return 0
  fi

  if terminal_can_kitty_graphics; then
    DEVIL_RENDERER=kitty-graphics
  elif terminal_can_kitten_icat; then
    DEVIL_RENDERER=kitten-icat
  elif terminal_can_iterm2; then
    DEVIL_RENDERER=iterm
  elif terminal_can_sixel; then
    DEVIL_RENDERER=sixel
  elif terminal_can_chafa; then
    DEVIL_RENDERER=chafa
  elif terminal_can_viu; then
    DEVIL_RENDERER=viu
  elif terminal_can_img2txt; then
    DEVIL_RENDERER=img2txt
  elif terminal_can_ueberzugpp; then
    DEVIL_RENDERER=ueberzugpp
  else
    DEVIL_RENDERER=ansi
  fi
  DEVIL_RENDERER_STATUS="automatically selected"
}

terminal_clear() {
  terminal_is_interactive || return 0
  printf '\e[2J\e[H'
}

terminal_hide_cursor() {
  terminal_is_interactive || return 0
  printf '\e[?25l'
  DEVIL_CURSOR_HIDDEN=1
}

terminal_show_cursor() {
  [[ -t 1 ]] || return 0
  printf '\e[?25h'
  DEVIL_CURSOR_HIDDEN=0
}

terminal_enable_mouse() {
  terminal_is_interactive || return 0
  [[ "${DEVIL_MOUSE:-auto}" != off ]] || return 0
  printf '\e[?1000h\e[?1006h'
  DEVIL_MOUSE_ENABLED=1
}

terminal_disable_mouse() {
  [[ -t 1 ]] || return 0
  printf '\e[?1000l\e[?1006l'
  DEVIL_MOUSE_ENABLED=0
}

terminal_restore() {
  [[ -t 1 ]] || return 0
  terminal_disable_mouse
  printf '\e[0m\e[?25h'
  DEVIL_CURSOR_HIDDEN=0
}

terminal_dimensions() {
  local size rows cols
  rows=${LINES:-24}
  cols=${COLUMNS:-80}
  if terminal_is_interactive && size=$(stty size < /dev/tty 2>/dev/null); then
    rows=${size%% *}
    cols=${size##* }
  fi
  [[ "$rows" =~ ^[0-9]+$ && "$rows" -gt 0 ]] || rows=24
  [[ "$cols" =~ ^[0-9]+$ && "$cols" -gt 0 ]] || cols=80
  DEVIL_TERM_ROWS=$rows
  DEVIL_TERM_COLS=$cols
}

terminal_one_line() {
  local text=${1-}
  text=${text//$'\e'/}
  text=${text//$'
'/ }
  text=${text//$'
'/ }
  text=${text//$'	'/ }
  printf '%s' "$text"
}

terminal_print_padded_text() {
  # printf field widths count UTF-8 bytes.  Pad separately so a label that
  # contains a one-cell symbol such as an em dash keeps its border aligned.
  local text=${1-} width=${2:-0} padding
  padding=$((width - ${#text}))
  ((padding < 0)) && padding=0
  printf '%s%*s' "$text" "$padding" ''
}

terminal_ascii_logo() {
  terminal_color_init
  local row
  local -a d=('██████╗ ' '██╔══██╗' '██║  ██║' '██║  ██║' '██████╔╝' '╚═════╝ ')
  local -a e=('███████╗' '██╔════╝' '█████╗  ' '██╔══╝  ' '███████╗' '╚══════╝')
  local -a v=('██╗   ██╗' '██║   ██║' '██║   ██║' '╚██╗ ██╔╝' ' ╚████╔╝ ' '  ╚═══╝  ')
  local -a i=('██╗' '██║' '██║' '██║' '██║' '╚═╝')
  local -a l=('██╗     ' '██║     ' '██║     ' '██║     ' '███████╗' '╚══════╝')

  for row in "${!d[@]}"; do
    printf '  %s%s%s  %s%s%s  %s%s%s  %s%s%s  %s%s%s\n' \
      "$C_BOLD$C_RED" "${d[row]}" "$C_RESET" \
      "$C_BOLD$C_PURPLE" "${e[row]}" "$C_RESET" \
      "$C_BOLD$C_GREEN" "${v[row]}" "$C_RESET" \
      "$C_BOLD$C_ORANGE" "${i[row]}" "$C_RESET" \
      "$C_BOLD$C_CRIMSON" "${l[row]}" "$C_RESET"
  done
}

terminal_devil_wordmark() {
  # Compact wordmark for headers: D red, E dark purple, V green, I orange,
  # and L dark crimson/pink.
  printf '%sD%s%sE%s%sV%s%sI%s%sL%s' \
    "$C_BOLD$C_RED" "$C_RESET" \
    "$C_BOLD$C_PURPLE" "$C_RESET" \
    "$C_BOLD$C_GREEN" "$C_RESET" \
    "$C_BOLD$C_ORANGE" "$C_RESET" \
    "$C_BOLD$C_CRIMSON" "$C_RESET"
}

terminal_devil_large_wordmark_at() {
  local row=$1 column=$2 index
  local color_d=$C_RED color_e=$C_PURPLE color_v=$C_GREEN color_i=$C_ORANGE color_l=$C_CRIMSON
  local -a d=('██████╗ ' '██╔══██╗' '██║  ██║' '██║  ██║' '██████╔╝' '╚═════╝ ')
  local -a e=('███████╗' '██╔════╝' '█████╗  ' '██╔══╝  ' '███████╗' '╚══════╝')
  local -a v=('██╗   ██╗' '██║   ██║' '██║   ██║' '╚██╗ ██╔╝' ' ╚████╔╝ ' '  ╚═══╝  ')
  local -a i=('██╗' '██║' '██║' '██║' '██║' '╚═╝')
  local -a l=('██╗     ' '██║     ' '██║     ' '██║     ' '███████╗' '╚══════╝')

  # Use a richer fixed palette where the terminal supports 24-bit ANSI.
  if ((DEVIL_COLOR_LEVEL >= 16777216)); then
    color_d=$'\e[38;2;255;38;38m'    # vivid red D
    color_e=$'\e[38;2;116;62;170m'   # dark purple E
    color_v=$'\e[38;2;52;205;115m'   # green V
    color_i=$'\e[38;2;255;145;32m'   # warm amber I
    color_l=$'\e[38;2;190;35;105m'   # dark pink/crimson L
  fi

  for index in "${!d[@]}"; do
    terminal_move_to "$((row + index))" "$column"
    printf '%s%s%s  %s%s%s  %s%s%s  %s%s%s  %s%s%s' \
      "$C_BOLD$color_d" "${d[index]}" "$C_RESET" \
      "$C_BOLD$color_e" "${e[index]}" "$C_RESET" \
      "$C_BOLD$color_v" "${v[index]}" "$C_RESET" \
      "$C_BOLD$color_i" "${i[index]}" "$C_RESET" \
      "$C_BOLD$color_l" "${l[index]}" "$C_RESET"
  done
}

terminal_render_kitty_graphics() {
  local image=$1 width=${2:-70} height=${3:-35}
  kitty +kitten icat --align center --place "${width}x${height}@0x0" --preserve-aspect-ratio --scale-up -- "$image" 2>/dev/null
}

terminal_render_kitten_icat() {
  local image=$1 width=${2:-70} height=${3:-35}
  kitten icat --align center --place "${width}x${height}@0x0" --preserve-aspect-ratio --scale-up -- "$image" 2>/dev/null
}

terminal_render_iterm2() {
  local image=${1:-} encoded width=${2:-100} height=${3:-30}
  encoded=$(base64 < "$image" | tr -d '\n') || return 1

  if terminal_is_konsole; then
    local px_width=$((width * 14))
    local px_height=$((height * 12))
    printf '\e]1337;File=inline=1;width=%dpx;height=%dpx;preserveAspectRatio=1:%s\a' "$px_width" "$px_height" "$encoded"
  else
    printf '\e]1337;File=inline=1;width=%dch;height=%dline;preserveAspectRatio=1:%s\a' "$width" "$height" "$encoded"
  fi
}

terminal_render_sixel() {
  local image=${1:-} width=${2:-50} height=${3:-25}
  img2sixel -w "$width" -h "$height" "$image" 2>/dev/null
}

terminal_render_chafa() {
  local image=$1 width=${2:-50} height=${3:-25}
  chafa --format=symbols --size="${width}x${height}" -- "$image" 2>/dev/null
}

terminal_render_viu() {
  local image=$1 width=${2:-50} height=${3:-25}
  viu -w "$width" -h "$height" -- "$image" 2>/dev/null
}

terminal_render_img2txt() {
  local image=$1 width=${2:-50} height=${3:-25}
  # libcaca's utf8 mode can emit control sequences that some xterm/sudo
  # combinations print literally.  The ANSI formatter uses conventional SGR
  # escapes and renders reliably in xterm, Konsole, and Linux TTYs.
  img2txt -f ansi -W "$width" -H "$height" -- "$image" 2>/dev/null
}

terminal_render_ueberzugpp() {
  local image=$1 escaped
  escaped=${image//\/\\}
  escaped=${escaped//"/"}
  printf '{"action":"add","identifier":"devil-splash","x":0,"y":0,"width":42,"height":18,"path":"%s"}
' "$escaped" |
    ueberzugpp layer --parser json >/dev/null 2>&1
}

terminal_render_branding_image() {
  local image=${1:-} width=${2:-} height=${3:-}
  image=$(terminal_image_file) || return 1
  case "${DEVIL_RENDERER:-ansi}" in
    kitty-graphics|kitty_graphics) terminal_render_kitty_graphics "$image" "$width" "$height" ;;
    kitten-icat) terminal_render_kitten_icat "$image" "$width" "$height" ;;
    iterm|iterm2) terminal_render_iterm2 "$image" "$width" "$height" ;;
    sixel) terminal_render_sixel "$image" "$width" "$height" ;;
    chafa) terminal_render_chafa "$image" "$width" "$height" ;;
    viu) terminal_render_viu "$image" "$width" "$height" ;;
    img2txt) terminal_render_img2txt "$image" "$width" "$height" ;;
    ueberzugpp) terminal_render_ueberzugpp "$image" ;;
    *) return 1 ;;
  esac
}

terminal_move_to() {
  local row=$1 column=$2
  printf '\e[%d;%dH' "$row" "$column"
}

terminal_startup_line() {
  local row=$1 column=$2 label=$3 value=$4 color=${5:-$C_GREEN}
  terminal_move_to "$row" "$column"
  printf '%s%s%s %s\n' "$color" "$label" "$C_RESET" "$value"
}

terminal_startup_panel() {
  local column=$1 row=$2 large_wordmark=${3:-0} kernel firmware mode user_host packages desktop session cpu memory shell_name
  local title_offset=0
  kernel=$(uname -r 2>/dev/null || printf 'unknown')
  firmware=$([[ -d /sys/firmware/efi ]] && printf 'UEFI' || printf 'BIOS')
  user_host="${USER:-unknown}@$(hostname 2>/dev/null || printf 'unknown')"
  shell_name=$(basename -- "${SHELL:-unknown}")
  desktop=${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}
  session=${XDG_SESSION_TYPE:-unknown}
  if have pacman; then
    packages="$(pacman -Qq 2>/dev/null | wc -l) (pacman)"
  elif have dpkg-query; then
    packages="$(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l) (dpkg)"
  elif have rpm; then
    packages="$(rpm -qa 2>/dev/null | wc -l) (rpm)"
  else
    packages='unavailable'
  fi
  cpu=$(lscpu 2>/dev/null | awk -F: '/Model name:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
  cpu=${cpu:-unknown}
  if have free; then
    memory=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2; exit}')
  else
    memory='unavailable'
  fi
  memory=${memory:-unknown}
  mode='Read-only diagnostics by default'
  ((DEVIL_TEST)) && mode='Test simulation — no host changes'
  ((DEVIL_DRY_RUN)) && mode='Dry-run — changes are simulated'
  ((DEVIL_SAFE)) && mode='Safe simulation — writes are blocked'

  if ((large_wordmark)); then
    terminal_devil_large_wordmark_at "$row" "$column"
    title_offset=6
    terminal_move_to "$((row + title_offset))" "$column"
    printf '%sEmergency Verification & Intelligent Linux Recovery%s\n' "$C_CYAN" "$C_RESET"
  else
    terminal_move_to "$row" "$column"
    terminal_devil_wordmark
    printf '  %sEmergency Verification & Intelligent Linux Recovery%s\n' "$C_GRAY" "$C_RESET"
  fi
  terminal_move_to "$((row + title_offset + 1))" "$column"
  printf '%s────────────────────────────────────────────────────────%s\n' "$C_PURPLE" "$C_RESET"
  terminal_startup_line "$((row + title_offset + 3))" "$column" '◆ USER' "$user_host" "$C_CYAN"
  terminal_startup_line "$((row + title_offset + 4))" "$column" '◆ OS' "$DEVIL_DISTRO" "$C_GREEN"
  terminal_startup_line "$((row + title_offset + 5))" "$column" '◆ KERNEL' "$kernel" "$C_PURPLE"
  terminal_startup_line "$((row + title_offset + 6))" "$column" '◆ PACKAGES' "$packages" "$C_ORANGE"
  terminal_startup_line "$((row + title_offset + 7))" "$column" '◆ SHELL' "$shell_name" "$C_RED"
  terminal_startup_line "$((row + title_offset + 9))" "$column" '◆ DESKTOP' "$desktop ($session)" "$C_CYAN"
  terminal_startup_line "$((row + title_offset + 11))" "$column" '◆ FIRMWARE' "$firmware" "$C_GREEN"
  terminal_startup_line "$((row + title_offset + 12))" "$column" '◆ ARCH' "$DEVIL_ARCH" "$C_PURPLE"
  terminal_startup_line "$((row + title_offset + 13))" "$column" '◆ CPU' "$cpu" "$C_ORANGE"
  terminal_startup_line "$((row + title_offset + 14))" "$column" '◆ MEMORY' "$memory" "$C_RED"
  terminal_startup_line "$((row + title_offset + 16))" "$column" '◆ TOOL' "DEVIL v${DEVIL_VERSION}" "$C_CYAN"
  terminal_startup_line "$((row + title_offset + 17))" "$column" '◆ TERMINAL' "$DEVIL_TERM" "$C_GREEN"
  terminal_startup_line "$((row + title_offset + 18))" "$column" '◆ RENDERER' "$DEVIL_RENDERER" "$C_PURPLE"
  terminal_startup_line "$((row + title_offset + 19))" "$column" '◆ SAFETY' "$mode" "$C_ORANGE"
  terminal_move_to "$((row + title_offset + 21))" "$column"
  printf '%sEvery recovery action requires confirmation and a backup.%s' "$C_GRAY" "$C_RESET"
}

terminal_home_menu_draw() {
  # Redraw only the interactive rows.  Re-rendering the image and system
  # profile for every arrow key causes visible blinking in terminal emulators.
  local selected=${1:-0} row=${DEVIL_HOME_MENU_START_ROW:?} width inside line
  width=$((DEVIL_TERM_COLS - 4))
  ((width > 78)) && width=78
  ((width < 44)) && width=44
  inside=$((width - 2))
  printf -v line '%*s' "$inside" ''
  line=${line// /─}

  terminal_move_to "$row" 2
  printf '\e[2K%s╭%s╮%s\n' "$C_GREEN" "$line" "$C_RESET"
  if ((selected == 0)); then
    terminal_move_to "$((row + 1))" 2
    printf '\e[2K%s│%s%s>  %-*s%s%s│%s\n' \
      "$C_GREEN" "$C_RESET" "$C_REVERSE$C_ORANGE$C_BOLD" "$((inside - 3))" 'Continue to main menu' "$C_RESET$C_GREEN" "$C_RESET"
    terminal_move_to "$((row + 2))" 2
    printf '\e[2K%s│%s%-*s%s│%s\n' \
      "$C_GREEN" "$C_RESET" "$inside" '   Exit DEVIL' "$C_GREEN" "$C_RESET"
  else
    terminal_move_to "$((row + 1))" 2
    printf '\e[2K%s│%s%-*s%s│%s\n' \
      "$C_GREEN" "$C_RESET" "$inside" '   Continue to main menu' "$C_GREEN" "$C_RESET"
    terminal_move_to "$((row + 2))" 2
    printf '\e[2K%s│%s%s>  %-*s%s%s│%s\n' \
      "$C_GREEN" "$C_RESET" "$C_REVERSE$C_ORANGE$C_BOLD" "$((inside - 3))" 'Exit DEVIL' "$C_RESET$C_GREEN" "$C_RESET"
  fi
  terminal_move_to "$((row + 3))" 2
  printf '\e[2K%s╰%s╯%s\n' "$C_GREEN" "$line" "$C_RESET"
  terminal_move_to "$((row + 4))" 2
  printf '\e[2K%s↑/↓%s navigate  %sEnter/click%s select  %sq/Esc%s exit' \
    "$C_GREEN" "$C_RESET" "$C_PURPLE" "$C_RESET" "$C_RED" "$C_RESET"
}

terminal_branding() {
  # The home menu is rendered here so the startup profile remains visible
  # while the user chooses whether to open the dashboard or leave DEVIL.
  local selected=${1:-0}
  local image_rendered=0 image_width=38 image_height=20 panel_column=45 panel_row=2 prompt_row
  terminal_color_init
  terminal_detect_renderer
  terminal_dimensions
  terminal_clear

  # Use a larger image on roomy terminals while retaining a compact layout on
  # typical 90-column consoles.
  if ((DEVIL_TERM_COLS >= 112 && DEVIL_TERM_ROWS >= 32)); then
    # The branding image has dark padding around its artwork in several
    # renderers.  Keep the panel close to the visible artwork instead of the
    # image canvas edge, which removes the large empty gap on wide terminals.
    image_width=52; image_height=26; panel_column=44
  fi
  if [[ "$DEVIL_RENDERER" != ansi ]] && terminal_render_branding_image "$image_width" "$image_height"; then
    image_rendered=1
  else
    if [[ "$DEVIL_RENDERER_STATUS" == "automatically selected" ]]; then
      DEVIL_RENDERER_STATUS="image renderer failed; using ANSI branding"
    fi
    DEVIL_RENDERER=ansi
    terminal_ascii_logo
  fi

  if ((DEVIL_TERM_COLS >= 112 && DEVIL_TERM_ROWS >= 32)); then
    terminal_startup_panel "$panel_column" "$panel_row" 1
    prompt_row=31
    terminal_move_to "$prompt_row" 2
  elif ((DEVIL_TERM_COLS >= 90 && DEVIL_TERM_ROWS >= 27)); then
    terminal_startup_panel "$panel_column" "$panel_row"
    prompt_row=25
    terminal_move_to "$prompt_row" 2
  else
    # Keep small terminals readable instead of drawing an overlapping panel.
    printf '\n\n'
    terminal_startup_panel 2 10
    prompt_row=26
    terminal_move_to "$prompt_row" 2
  fi
  if ((image_rendered == 0)); then
    printf '%sANSI artwork is active; no compatible image renderer was available.%s\n' "$C_DIM" "$C_RESET"
    ((prompt_row += 1))
  fi
  DEVIL_HOME_MENU_START_ROW=$prompt_row
  terminal_home_menu_draw "$selected"
}

terminal_home_menu() {
  # Return success only when the user deliberately continues into the main
  # menu.  This keeps the Exit button and q/Esc on the startup screen local
  # to that screen rather than relying on the dashboard's exit handling.
  local selected=0 previous button x y action

  terminal_mouse_init
  terminal_branding "$selected"
  while :; do
    terminal_read_key || return 1
    previous=$selected

    case "$DEVIL_KEY" in
      arrow_up|arrow_down|arrow_left|arrow_right|tab) selected=$((1 - selected)) ;;
      home) selected=0 ;;
      end) selected=1 ;;
      enter|space) ((selected == 0)) && return 0 || return 1 ;;
      q|Q|escape) return 1 ;;
      mouse:*)
        IFS=: read -r _ button x y action <<<"$DEVIL_KEY"
        if [[ "$button:$action" == '0:M' ]] && ((y >= DEVIL_HOME_MENU_START_ROW + 1 && y <= DEVIL_HOME_MENU_START_ROW + 2)); then
          selected=$((y - DEVIL_HOME_MENU_START_ROW - 1))
          ((selected == 0)) && return 0 || return 1
        fi
        ;;
    esac

    # Navigation changes only the two option rows, leaving the branding and
    # startup profile intact for a smooth transition.
    ((selected == previous)) || terminal_home_menu_draw "$selected"
  done
}

terminal_parse_sgr_mouse() {
  local sequence=$1 button x y action
  if [[ "$sequence" =~ ^\<([0-9]+)\;([0-9]+)\;([0-9]+)([Mm])$ ]]; then
    button=${BASH_REMATCH[1]}
    x=${BASH_REMATCH[2]}
    y=${BASH_REMATCH[3]}
    action=${BASH_REMATCH[4]}
    DEVIL_MOUSE_BUTTON=$button
    DEVIL_MOUSE_X=$x
    DEVIL_MOUSE_Y=$y
    DEVIL_KEY="mouse:${button}:${x}:${y}:${action}"
    return 0
  fi
  return 1
}

terminal_read_key() {
  local character sequence='' have_tty=0
  DEVIL_KEY=''

  if [[ -r /dev/tty ]]; then
    exec 9</dev/tty
    have_tty=1
    IFS= read -r -s -n 1 -u 9 character || { exec 9<&-; return 1; }
  else
    IFS= read -r -s -n 1 character || return 1
  fi

  if [[ -z "$character" ]]; then
    DEVIL_KEY=enter
  else
    case "$character" in
      $'
'|$'
') DEVIL_KEY=enter ;;
      $'	') DEVIL_KEY=tab ;;
      $'\003') terminal_restore; exit 130 ;;
      $''|$'') DEVIL_KEY=backspace ;;
      $'\e')
        if [[ "$have_tty" -eq 1 ]]; then
          if ! IFS= read -r -s -n 1 -t 0.1 -u 9 character; then
            DEVIL_KEY=escape
            exec 9<&-
            return 0
          fi
        else
          if ! IFS= read -r -s -n 1 -t 0.1 character; then
            DEVIL_KEY=escape
            return 0
          fi
        fi
        case "$character" in
          '[')
            while true; do
              if [[ "$have_tty" -eq 1 ]]; then
                IFS= read -r -s -n 1 -t 0.1 -u 9 character || break
              else
                IFS= read -r -s -n 1 -t 0.1 character || break
              fi
              sequence+=$character
              [[ "$character" =~ [A-Za-z~] ]] && break
            done
            case "$sequence" in
              A|1\;*A) DEVIL_KEY=arrow_up ;;
              B|1\;*B) DEVIL_KEY=arrow_down ;;
              C|1\;*C) DEVIL_KEY=arrow_right ;;
              D|1\;*D) DEVIL_KEY=arrow_left ;;
              H|1~|7~) DEVIL_KEY=home ;;
              F|4~|8~) DEVIL_KEY=end ;;
              5~) DEVIL_KEY=page_up ;;
              6~) DEVIL_KEY=page_down ;;
              \<*) terminal_parse_sgr_mouse "$sequence" || DEVIL_KEY=escape_sequence ;;
              *) DEVIL_KEY=escape_sequence ;;
            esac
            ;;
          O)
            if [[ "$have_tty" -eq 1 ]]; then
              IFS= read -r -s -n 1 -t 0.1 -u 9 character || character=''
            else
              IFS= read -r -s -n 1 -t 0.1 character || character=''
            fi
            case "$character" in H) DEVIL_KEY=home ;; F) DEVIL_KEY=end ;; *) DEVIL_KEY=escape_sequence ;; esac
            ;;
          *) DEVIL_KEY=escape_sequence ;;
        esac
        ;;
      *) DEVIL_KEY=$character ;;
    esac
  fi

  [[ "$have_tty" -eq 1 ]] && exec 9<&-
}

terminal_discard_pending_input() {
  # Menus must never treat key repeats typed during a loading screen as a new
  # approval.  Wait for a short quiet interval so an active key repeat is
  # fully released before a confirmation menu is displayed.
  local character
  if [[ -r /dev/tty ]]; then
    exec 9</dev/tty
    while IFS= read -r -s -n 1 -t 0.18 -u 9 character; do :; done
    exec 9<&-
  elif [[ -t 0 ]]; then
    while IFS= read -r -s -n 1 -t 0.18 character; do :; done
  fi
}

devil_classify_environment() {
  local root_source
  root_source=$(findmnt -n -o SOURCE / 2>/dev/null || echo unknown)
  # Compare the *targets* only when both can be followed.  On hardened systems
  # /proc/1/root is often an unreadable magic link; statting that link itself
  # compares procfs metadata with / and falsely identifies an installed system
  # as a chroot.
  local stat_root stat_proc1
  stat_root=$(stat -Lc '%d:%i' / 2>/dev/null || true)
  stat_proc1=$(stat -Lc '%d:%i' /proc/1/root 2>/dev/null || true)

  if [[ -n "$stat_root" && -n "$stat_proc1" && "$stat_root" != "$stat_proc1" ]]; then
    printf 'CHROOT'
    return
  fi

  case "$root_source" in
    /dev/loop*|*squashfs*|overlay|overlayfs|none|tmpfs|rootfs)
      printf 'LIVE_ISO'
      return
      ;;
    /dev/*|/dev/mapper/*|/dev/nvme*|/dev/disk/by-*/*)
      printf 'INSTALLED_SYSTEM'
      return
      ;;
    *)
      printf 'UNKNOWN'
      return
      ;;
  esac
}

devil_detect_environment() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    DEVIL_DISTRO=${PRETTY_NAME:-${NAME:-Unknown}}
  fi
  DEVIL_TERM=$(terminal_detect_name)
  terminal_detect_renderer
  DEVIL_ENVIRONMENT_CLASS=$(devil_classify_environment)
  debug "terminal=$DEVIL_TERM renderer=$DEVIL_RENDERER distro=${DEVIL_DISTRO:-Unknown} environment=$DEVIL_ENVIRONMENT_CLASS"
}
