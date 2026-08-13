#!/usr/bin/env bash
# A deliberately tiny, non-executable key=value configuration format.
DEVIL_SETTINGS_FILE=""
declare -A DEVIL_SETTINGS=([theme]=pitch-black [mouse]=auto [report_detail]=standard)

config_load() {
  local line key value
  DEVIL_SETTINGS_FILE="$DEVIL_CONFIG_DIR/settings.conf"
  [[ -r "$DEVIL_SETTINGS_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || { log_warn "ignored malformed settings line"; continue; }
    key=${line%%=*}; value=${line#*=}
    case "$key" in theme|mouse|report_detail) DEVIL_SETTINGS["$key"]=$value;; *) log_warn "ignored unknown setting: $key";; esac
  done <"$DEVIL_SETTINGS_FILE"
}

config_save() {
  local temporary
  DEVIL_SETTINGS_FILE="$DEVIL_CONFIG_DIR/settings.conf"
  temporary="$DEVIL_CONFIG_DIR/.settings.$$"
  umask 077
  {
    printf '# DEVIL settings — generated safely; do not source as shell code.\n'
    printf 'theme=%s\nmouse=%s\nreport_detail=%s\n' "${DEVIL_SETTINGS[theme]}" "${DEVIL_SETTINGS[mouse]}" "${DEVIL_SETTINGS[report_detail]}"
  } >"$temporary"
  mv -f -- "$temporary" "$DEVIL_SETTINGS_FILE"
}

config_set() {
  local key=$1 value=$2
  case "$key" in theme) [[ "$value" == pitch-black ]] || die "unsupported theme: $value";; mouse) [[ "$value" =~ ^(auto|off)$ ]] || die "mouse must be auto or off";; report_detail) [[ "$value" =~ ^(standard|verbose)$ ]] || die "report detail must be standard or verbose";; *) die "unknown setting: $key";; esac
  DEVIL_SETTINGS["$key"]=$value; config_save; log_info "setting updated: $key"
}
