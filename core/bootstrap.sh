#!/usr/bin/env bash
# Application bootstrap and command-line dispatch.
[[ -n "${DEVIL_BOOTSTRAPPED:-}" ]] && return 0
readonly DEVIL_BOOTSTRAPPED=1
readonly DEVIL_VERSION="1.0.0"
DEVIL_DATA_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devil"
DEVIL_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devil"
DEVIL_LOG_DIR="$DEVIL_DATA_DIR/logs"
# Reports and human-readable recovery audits belong beside the checkout so a
# Live-USB operator can find them immediately after a repair.  Callers may
# override this for a portable or read-only deployment.
DEVIL_REPORT_DIR="${DEVIL_REPORT_DIR:-$DEVIL_ROOT/reports}"
DEVIL_REPORT_WRITABLE=1
DEVIL_BACKUP_DIR="$DEVIL_DATA_DIR/backups"
DEVIL_DEBUG="${DEVIL_DEBUG:-0}"; DEVIL_DRY_RUN=0; DEVIL_SAFE=0; DEVIL_TEST=0
DEVIL_RENDERER="ansi"; DEVIL_TERM="${TERM:-unknown}"; DEVIL_DISTRO="Unknown"; DEVIL_ARCH="$(uname -m)"
DEVIL_TARGET_ROOT_REQUESTED="${DEVIL_TARGET_ROOT:-}"
DEVIL_TARGET_ROOT=/; DEVIL_TARGET_ROOT_SOURCE=current
DEVIL_RECOVERY_ROOT_SPEC=""
declare -a DEVIL_TARGET_ROOT_CANDIDATES=()
declare -a DEVIL_WARNINGS=() DEVIL_ACTIONS=()
DEVIL_SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"

# shellcheck source=core/common.sh
source "$DEVIL_ROOT/core/common.sh"
# shellcheck source=core/config.sh
source "$DEVIL_ROOT/core/config.sh"
# shellcheck source=core/dependencies.sh
source "$DEVIL_ROOT/core/dependencies.sh"
# shellcheck source=core/logging.sh
source "$DEVIL_ROOT/core/logging.sh"
# shellcheck source=core/terminal.sh
source "$DEVIL_ROOT/core/terminal.sh"
# shellcheck source=modules/diagnostics.sh
source "$DEVIL_ROOT/modules/diagnostics.sh"
# shellcheck source=modules/recovery.sh
source "$DEVIL_ROOT/modules/recovery.sh"
# shellcheck source=modules/efi.sh
source "$DEVIL_ROOT/modules/efi.sh"
# shellcheck source=modules/grub.sh
source "$DEVIL_ROOT/modules/grub.sh"
# shellcheck source=modules/filesystems.sh
source "$DEVIL_ROOT/modules/filesystems.sh"
# shellcheck source=modules/multiboot.sh
[[ -f "$DEVIL_ROOT/modules/multiboot.sh" ]] && source "$DEVIL_ROOT/modules/multiboot.sh"
# shellcheck source=ui/dashboard.sh
source "$DEVIL_ROOT/ui/dashboard.sh"

devil_usage() { cat <<'EOF'
Usage: bash run.sh [--diagnose] [--report] [--self-test] [--dependencies]
                   [--grub-check] [--efi-list] [--multiboot] [--recovery-plan] [--backups]
                   [--target-root PATH] [--ui|--dashboard] [--dry-run] [--safe] [--test] [--debug] [--version] [--help]
  --diagnose   Collect read-only diagnostics and print a report.
  --report     Save a JSON and text diagnostics report.
  --self-test  Validate dependencies, module loading and safe probes.
  --dependencies  Display required and optional command availability.
  --grub-check  Validate the selected system's GRUB configuration without writing.
  --efi-list    Display EFI entries and BootOrder without writing.
  --multiboot   Detect installed operating systems without mounting or writing.
  --target-root PATH  Inspect a Linux system already mounted at PATH (for example, /mnt).
  --recovery-plan  Explain whether conservative automatic recovery is appropriate.
  --backups     List DEVIL backups in the current state directory.
  --ui, --dashboard  Start the interactive terminal UI.
  --dry-run    Show recovery commands without running them.
  --safe       Simulate all recovery writes (diagnostics remain real).
  --test       Simulate operations; never touch the host system.
  --debug      Record and print diagnostic probe progress.
EOF
}

devil_parse_args() {
  while (($#)); do case "$1" in
    --diagnose) DEVIL_MODE=diagnose;; --report) DEVIL_MODE=report;; --self-test) DEVIL_MODE=selftest;; --dependencies) DEVIL_MODE=dependencies;;
    --grub-check) DEVIL_MODE=grubcheck;; --efi-list) DEVIL_MODE=efilist;; --multiboot) DEVIL_MODE=multiboot;; --recovery-plan) DEVIL_MODE=recoveryplan;; --backups) DEVIL_MODE=backups;; --ui|--dashboard) DEVIL_MODE=ui;;
    --target-root)
      shift
      [[ $# -gt 0 ]] || die '--target-root requires an already mounted Linux root path'
      DEVIL_TARGET_ROOT_REQUESTED=$1
      ;;
    --target-root=*) DEVIL_TARGET_ROOT_REQUESTED=${1#*=};;
    --dry-run) DEVIL_DRY_RUN=1;; --safe) DEVIL_SAFE=1;; --test) DEVIL_TEST=1;; --debug) DEVIL_DEBUG=1;;
    --version) printf 'DEVIL %s\n' "$DEVIL_VERSION"; exit 0;; -h|--help) devil_usage; exit 0;; *) die "unknown option: $1 (try --help)";; esac; shift; done
}

devil_main() {
  DEVIL_MODE=ui; devil_parse_args "$@"; devil_init_dirs; devil_detect_environment; log_init
  devil_select_target_root "${DEVIL_TARGET_ROOT_REQUESTED:-}" || die "target root must contain etc/os-release and boot: ${DEVIL_TARGET_ROOT_REQUESTED:-unknown}"
  if [[ "${DEVIL_TARGET_ROOT_SOURCE:-current}" == auto ]]; then
    log_info "auto-selected mounted Linux root: $DEVIL_TARGET_ROOT"
  elif [[ "${DEVIL_TARGET_ROOT_SOURCE:-current}" == ambiguous ]]; then
    log_warn "multiple mounted Linux roots found; use --target-root to choose one"
  fi
  config_load
  terminal_color_init
  terminal_load_theme
  trap 'devil_cleanup' EXIT; trap 'devil_interrupt' INT TERM
  dependencies_verify
  case "$DEVIL_MODE" in
    diagnose) diagnostics_collect; diagnostics_print;;
    report) diagnostics_collect; report_write;;
    dependencies) dependencies_report;;
    grubcheck) grub_validate;;
    efilist) efi_list;;
    multiboot)
      if [[ -f "$DEVIL_ROOT/modules/multiboot.sh" ]]; then
        source "$DEVIL_ROOT/modules/multiboot.sh"
        multiboot_scan_partitions
        multiboot_report
      else
        printf 'Multi-boot module is unavailable.\n'
      fi
      ;;
    recoveryplan) recovery_plan;;
    backups) recovery_list_backups;;
    selftest) devil_self_test;;
    *) ui_start;;
  esac
}

devil_self_test() {
  local failed=0 module shellcheck_status=not-installed
  for module in "$DEVIL_ROOT"/devil "$DEVIL_ROOT"/run.sh "$DEVIL_ROOT"/{core,modules,ui}/*.sh; do
    [[ -f "$module" ]] && bash -n "$module" || failed=1
  done
  if have shellcheck; then
    if shellcheck "$DEVIL_ROOT"/devil "$DEVIL_ROOT"/run.sh "$DEVIL_ROOT"/{core,modules,ui}/*.sh; then shellcheck_status=passed; else shellcheck_status=failed; failed=1; fi
  fi
  diagnostics_collect || failed=1
  printf 'DEVIL self-test: %s (ShellCheck: %s)\n' "$([[ $failed == 0 ]] && echo PASS || echo FAIL)" "$shellcheck_status"
  [[ $failed == 0 ]] || return 1
}

devil_cleanup() { terminal_restore; [[ -n "${DEVIL_LOG_FILE:-}" ]] && log_info "session ended" || true; }
devil_interrupt() { terminal_restore; printf 'DEVIL: interrupted\n' >&2; exit 130; }
