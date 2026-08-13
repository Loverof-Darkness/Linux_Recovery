#!/usr/bin/env bash
# DEVIL Pitch-Black Theme
# Professional dark color scheme optimized for terminal readiness
# This theme is sourced after terminal capability detection in core/terminal.sh

DEVIL_THEME_NAME='Pitch Black'
DEVIL_THEME_PANEL_BORDER='crimson'
DEVIL_THEME_ACCENT='orange'
DEVIL_THEME_BACKGROUND='black'

# Extended palette for rich UI presentation
THEME_COLOR_BG_PRIMARY="$C_BLACK"
THEME_COLOR_FG_PRIMARY="$C_WHITE"
THEME_COLOR_ACCENT="$C_CRIMSON"
THEME_COLOR_HIGHLIGHT="$C_ORANGE"
THEME_COLOR_SUCCESS="$C_GREEN"
THEME_COLOR_WARNING="$C_ORANGE"
THEME_COLOR_DANGER="$C_RED"
THEME_COLOR_DISABLED="$C_GRAY"

# Character definitions
THEME_CHAR_BULLET='●'
THEME_CHAR_CHECK='✓'
THEME_CHAR_CROSS='✗'
THEME_CHAR_WARNING='⚠'
THEME_CHAR_ARROW_RIGHT='❯'
THEME_CHAR_ARROW_LEFT='❮'
THEME_CHAR_H_LINE='─'
THEME_CHAR_V_LINE='│'
THEME_CHAR_CORNER_TL='┌'
THEME_CHAR_CORNER_TR='┐'
THEME_CHAR_CORNER_BL='└'
THEME_CHAR_CORNER_BR='┘'
THEME_CHAR_TEE_T='┬'
THEME_CHAR_TEE_B='┴'
THEME_CHAR_TEE_L='├'
THEME_CHAR_TEE_R='┤'
THEME_CHAR_CROSS_LINES='┼'

theme_draw_header() {
  local title=$1
  local width=${2:-78}
  
  printf '%s' "$THEME_COLOR_ACCENT"
  printf '%s' "$THEME_CHAR_CORNER_TL"
  for ((i=0; i<width-2; i++)); do printf '%s' "$THEME_CHAR_H_LINE"; done
  printf '%s%s\n' "$THEME_CHAR_CORNER_TR" "$C_RESET"
  
  printf '%s│%s %s%-$((width-3))s %s│%s\n' \
    "$THEME_COLOR_ACCENT" "$C_RESET" "$THEME_COLOR_FG_PRIMARY" "$title" "$THEME_COLOR_ACCENT" "$C_RESET"
  
  printf '%s' "$THEME_COLOR_ACCENT"
  printf '%s' "$THEME_CHAR_CORNER_BL"
  for ((i=0; i<width-2; i++)); do printf '%s' "$THEME_CHAR_H_LINE"; done
  printf '%s%s\n' "$THEME_CHAR_CORNER_BR" "$C_RESET"
}

theme_draw_box() {
  local x=$1 y=$2 width=$3 height=$4 title=${5:-}
  
  # Top border
  printf '\e[%d;%dH%s%s' "$y" "$x" "$THEME_COLOR_ACCENT" "$THEME_CHAR_CORNER_TL"
  for ((i=0; i<width-2; i++)); do printf '%s' "$THEME_CHAR_H_LINE"; done
  printf '%s%s' "$THEME_CHAR_CORNER_TR" "$C_RESET"
  
  # Sides
  for ((i=1; i<height-1; i++)); do
    printf '\e[%d;%dH%s%s%*s%s%s' "$((y+i))" "$x" "$THEME_COLOR_ACCENT" "$THEME_CHAR_V_LINE" "$((width-2))" "" "$THEME_CHAR_V_LINE" "$C_RESET"
  done
  
  # Bottom border
  printf '\e[%d;%dH%s%s' "$((y+height-1))" "$x" "$THEME_COLOR_ACCENT" "$THEME_CHAR_CORNER_BL"
  for ((i=0; i<width-2; i++)); do printf '%s' "$THEME_CHAR_H_LINE"; done
  printf '%s%s' "$THEME_CHAR_CORNER_BR" "$C_RESET"
  
  # Title
  if [[ -n "$title" ]]; then
    printf '\e[%d;%dH%s %s %s' "$y" "$((x+2))" "$THEME_COLOR_FG_PRIMARY" "$title" "$C_RESET"
  fi
}

theme_draw_progress() {
  local percent=$1 width=${2:-40}
  local filled=$((percent * width / 100))
  local empty=$((width - filled))
  
  printf '%s[' "$THEME_COLOR_HIGHLIGHT"
  for ((i=0; i<filled; i++)); do printf '█'; done
  for ((i=0; i<empty; i++)); do printf '░'; done
  printf '] %3d%%%s' "$percent" "$C_RESET"
}

theme_draw_status() {
  local status=$1 message=$2
  
  case "$status" in
    success)
      printf '%s%s%s %s' "$THEME_COLOR_SUCCESS" "$THEME_CHAR_CHECK" "$C_RESET" "$message"
      ;;
    warning)
      printf '%s%s%s %s' "$THEME_COLOR_WARNING" "$THEME_CHAR_WARNING" "$C_RESET" "$message"
      ;;
    error)
      printf '%s%s%s %s' "$THEME_COLOR_DANGER" "$THEME_CHAR_CROSS" "$C_RESET" "$message"
      ;;
    info)
      printf '%s%s%s %s' "$THEME_COLOR_ACCENT" "$THEME_CHAR_BULLET" "$C_RESET" "$message"
      ;;
    *)
      printf '%s%s' "$message" "$C_RESET"
      ;;
  esac
}

theme_draw_bullet_list() {
  local -a items=("$@")
  local item
  for item in "${items[@]}"; do
    printf '%s%s%s %s\n' "$THEME_COLOR_ACCENT" "$THEME_CHAR_BULLET" "$C_RESET" "$item"
  done
}

theme_draw_menu_item() {
  local selected=$1 text=$2
  if ((selected)); then
    printf '%s%s %s%s\n' "$THEME_COLOR_HIGHLIGHT" "$THEME_CHAR_ARROW_RIGHT" "$text" "$C_RESET"
  else
    printf '  %s\n' "$text"
  fi
}

theme_draw_table_header() {
  local -a columns=("$@")
  local col
  printf '%s' "$THEME_COLOR_ACCENT"
  for col in "${columns[@]}"; do
    printf '%-20s ' "$col"
  done
  printf '%s\n' "$C_RESET"
  
  printf '%s' "$THEME_COLOR_DISABLED"
  for col in "${columns[@]}"; do
    printf '%s' "$(printf '─%.0s' $(seq 1 20)) "
  done
  printf '%s\n' "$C_RESET"
}

theme_draw_separator() {
  local width=${1:-78}
  printf '%s' "$THEME_COLOR_DISABLED"
  printf '%s' "$(printf '%s%.0s' "$THEME_CHAR_H_LINE" $(seq 1 width))"
  printf '%s\n' "$C_RESET"
}

theme_init() {
  # Initialize theme colors based on detected terminal capabilities
  if ((DEVIL_COLOR_LEVEL == 0)); then
    # Honour NO_COLOR and non-interactive output.  A loaded theme must never
    # reintroduce escape sequences after terminal_color_init disabled them.
    THEME_COLOR_BG_PRIMARY=''
    THEME_COLOR_FG_PRIMARY=''
    THEME_COLOR_ACCENT=''
    THEME_COLOR_HIGHLIGHT=''
    THEME_COLOR_SUCCESS=''
    THEME_COLOR_WARNING=''
    THEME_COLOR_DANGER=''
    THEME_COLOR_DISABLED=''
  elif ((DEVIL_COLOR_LEVEL < 256)); then
    # Fallback to basic ANSI colors for limited terminals
    THEME_COLOR_BG_PRIMARY=$'\e[40m'
    THEME_COLOR_ACCENT=$'\e[31m'
    THEME_COLOR_HIGHLIGHT=$'\e[33m'
    THEME_COLOR_SUCCESS=$'\e[32m'
    THEME_COLOR_WARNING=$'\e[33m'
    THEME_COLOR_DANGER=$'\e[31m'
    THEME_COLOR_DISABLED=$'\e[37m'
  fi
}

# Apply theme initialization when sourced
theme_init
