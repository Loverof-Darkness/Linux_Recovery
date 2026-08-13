#!/usr/bin/env bash
# Timestamped human-readable and JSONL audit logging.
DEVIL_LOG_FILE=""
DEVIL_LOG_JSON_FILE=""
# During an interactive run this points at the one full report text file after
# startup assessment completes. Audit entries are appended there, not emitted
# as a second report-directory file.
DEVIL_AUDIT_FILE=""

log_init() {
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  DEVIL_LOG_FILE="$DEVIL_LOG_DIR/devil-$stamp.log"
  DEVIL_LOG_JSON_FILE="$DEVIL_LOG_DIR/devil-$stamp.jsonl"
  DEVIL_AUDIT_FILE=''
  umask 077
  : >"$DEVIL_LOG_FILE"; : >"$DEVIL_LOG_JSON_FILE"
  log_info "DEVIL $DEVIL_VERSION started; session=$DEVIL_SESSION_ID"
}

log_write() {
  local level=$1; shift
  local message=$* timestamp line
  timestamp=$(date -Is); line="$timestamp [$level] $message"
  [[ -n "$DEVIL_LOG_FILE" ]] && printf '%s\n' "$line" >>"$DEVIL_LOG_FILE"
  [[ -n "$DEVIL_AUDIT_FILE" ]] && printf '%s\n' "$line" >>"$DEVIL_AUDIT_FILE"
  [[ -n "$DEVIL_LOG_JSON_FILE" ]] && printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' "$(json_escape "$timestamp")" "$(json_escape "$level")" "$(json_escape "$message")" >>"$DEVIL_LOG_JSON_FILE"
  [[ "${DEVIL_DEBUG:-0}" == 1 ]] && printf '%s\n' "$line" >&2 || true
}

log_info() { log_write INFO "$*"; }
log_warn() { DEVIL_WARNINGS+=("$*"); log_write WARN "$*"; }
log_error() { log_write ERROR "$*"; }
log_debug() { log_write DEBUG "$*"; }

audit_note() {
  local message=$*
  [[ -n "$DEVIL_AUDIT_FILE" ]] && printf '%s [AUDIT] %s\n' "$(date -Is)" "$message" >>"$DEVIL_AUDIT_FILE"
  log_info "$message"
}

audit_capture() {
  # Preserve a command's exit code while showing its progress live and saving
  # the full terminal transcript as plain text in the session audit. Buffering
  # a recovery command until it exits leaves the interactive UI on an empty
  # "Repair in progress" screen, which looks like a hung repair.
  local label=$1 output status
  shift
  output=$(mktemp "${TMPDIR:-/tmp}/devil-audit.XXXXXX") || return 1
  audit_note "BEGIN: $label"
  if "$@" 2>&1 | tee "$output"; then
    status=${PIPESTATUS[0]}
  else
    status=${PIPESTATUS[0]}
  fi
  if [[ -n "$DEVIL_AUDIT_FILE" ]]; then
    printf '\n--- %s transcript ---\n' "$label" >>"$DEVIL_AUDIT_FILE"
    devil_strip_ansi <"$output" >>"$DEVIL_AUDIT_FILE"
    printf '\n--- end transcript (exit %s) ---\n' "$status" >>"$DEVIL_AUDIT_FILE"
  fi
  rm -f -- "$output"
  audit_note "END: $label (exit=$status)"
  return "$status"
}

log_action() {
  local action=$1 result=$2 exit_code=$3 duration_ms=$4
  log_write ACTION "action=$(json_escape "$action") result=$result exit_code=$exit_code duration_ms=$duration_ms"
  [[ -n "$DEVIL_LOG_JSON_FILE" ]] && printf '{"timestamp":"%s","type":"action","action":"%s","result":"%s","exit_code":%s,"duration_ms":%s}\n' "$(date -Is)" "$(json_escape "$action")" "$result" "$exit_code" "$duration_ms" >>"$DEVIL_LOG_JSON_FILE"
}

report_write() {
  full_report_write
}

full_report_run_check() {
  local title=$1; shift
  local status
  printf '\n================================================================\n%s\n----------------------------------------------------------------\n' "$title"
  if "$@"; then
    printf '\nResult: PASS\n'
  else
    status=$?
    printf '\nResult: FAILED (exit code %s); output above is the diagnostic evidence.\n' "$status"
  fi
  return 0
}

full_report_diagnostics() {
  diagnostics_collect
  diagnostics_print
}

full_report_recovery_plan() {
  local prior_dry_run=$DEVIL_DRY_RUN
  DEVIL_DRY_RUN=1
  recovery_plan
  DEVIL_DRY_RUN=$prior_dry_run
}

full_report_write() {
  local stamp report
  ((DEVIL_REPORT_WRITABLE)) || { printf 'Full report was not saved: the tool-local reports directory is not writable: %s\n' "$DEVIL_REPORT_DIR"; return 1; }
  stamp=$(date +%Y%m%d-%H%M%S)
  report="$DEVIL_REPORT_DIR/full-recovery-report-$stamp.txt"
  {
    printf 'DEVIL full recovery assessment\nGenerated: %s\nProject: %s\n' "$(date -Is)" "$DEVIL_ROOT"
    printf 'Safety: all commands below are read-only or dry-run; no bootloader changes are made.\n'
    full_report_run_check '1. Dependency availability' dependencies_report
    full_report_run_check '2. Built-in safe self-test' devil_self_test
    full_report_run_check '3. Full system diagnostics' full_report_diagnostics
    full_report_run_check '4. GRUB configuration check' grub_validate
    full_report_run_check '5. EFI entries and BootOrder' efi_list
    full_report_run_check '6. Installed operating-system scan' multiboot_report
    full_report_run_check '7. Filesystem and storage summary' filesystem_summary
    full_report_run_check '8. Automatic-recovery assessment (dry-run, no changes)' full_report_recovery_plan
    printf '\n================================================================\nAssessment complete.\nSaved report: %s\n' "$report"
  } >"$report" 2>&1
  DEVIL_AUDIT_FILE="$report"
  printf 'Full recovery report saved: %s\n' "$report"
  printf '\n================================================================\nAudit trail (same session)\n================================================================\n' >>"$report"
  audit_note "Full startup report saved: $report"
  # Session logging uses umask 077 for private state. Reports are deliberate
  # hand-off artifacts, so do not leave them marked private/locked in file
  # managers solely because they inherited that umask.
  chmod 0644 -- "$report" 2>/dev/null || true
}
