#!/usr/bin/env bash
# Collect a single, portable record of all safe DEVIL recovery checks.
# This script deliberately does not open the interactive recovery UI or write
# to disks/EFI variables.  The recovery section is a dry-run only.
set -uo pipefail
IFS=$' \t\n'

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNNER="$PROJECT_DIR/run.sh"
REPORT_DIR="$PROJECT_DIR/reports"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$REPORT_DIR/full-recovery-report-$STAMP.txt"

if [[ ! -f "$RUNNER" ]]; then
  printf 'DEVIL report capture: run.sh is missing from %s\n' "$PROJECT_DIR" >&2
  exit 1
fi

mkdir -p "$REPORT_DIR" || {
  printf 'DEVIL report capture: cannot create %s\n' "$REPORT_DIR" >&2
  exit 1
}

if (( EUID != 0 )); then
  printf 'Run this with sudo so storage, EFI, and boot checks are complete:\n  sudo bash scripts/capture-recovery-report.sh\n' >&2
  exit 1
fi

exec > >(tee "$REPORT_FILE") 2>&1

printf 'DEVIL full recovery assessment\n'
printf 'Generated: %s\n' "$(date -Is)"
printf 'Project: %s\n' "$PROJECT_DIR"
printf 'Safety: all commands below are read-only or dry-run; no bootloader changes are made.\n'

run_check() {
  local title=$1
  shift
  printf '\n================================================================\n'
  printf '%s\n' "$title"
  printf 'Command: bash run.sh'
  printf ' %q' "$@"
  printf '\n----------------------------------------------------------------\n'
  if (cd "$PROJECT_DIR" && bash "$RUNNER" "$@"); then
    printf '\nResult: PASS\n'
  else
    printf '\nResult: FAILED (exit code %s); output above is the diagnostic evidence.\n' "$?"
  fi
}

run_check '1. Dependency availability' --dependencies
run_check '2. Built-in safe self-test' --self-test
run_check '3. Full system diagnostics' --diagnose
run_check '4. GRUB configuration check' --grub-check
run_check '5. EFI entries and BootOrder' --efi-list
run_check '6. Installed operating-system scan' --multiboot
run_check '7. Automatic-recovery assessment (dry-run, no changes)' --recovery-plan --dry-run
run_check '8. Test-mode recovery assessment (simulation, no changes)' --recovery-plan --test

printf '\n================================================================\n'
printf 'Assessment complete.\nSaved report: %s\n' "$REPORT_FILE"

# A sudo capture inherits root's restrictive umask. The assessment is an
# operator-facing artifact, so leave it readable rather than marked locked.
chmod 0644 -- "$REPORT_FILE" 2>/dev/null || true
