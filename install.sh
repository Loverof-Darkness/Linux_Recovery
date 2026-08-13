#!/usr/bin/env bash
# DEVIL v1.0 Installation Script
# Installs DEVIL Emergency Verification & Intelligent Linux Recovery

set -Eeuo pipefail
IFS=$' \t\n'

readonly SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PREFIX=/opt/devil
readonly DESKTOP_FILE=/usr/share/applications/devil.desktop
readonly ICON_FILE=/usr/share/pixmaps/devil.png
readonly LAUNCHER=/usr/local/bin/devil
readonly MAN_FILE=/usr/share/man/man1/devil.1.gz

# Color output
C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'

fail() { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
success() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '%s●%s %s\n' "$C_BOLD" "$C_RESET" "$*"; }

# Verify root and source
[[ ${EUID:-999} -eq 0 ]] || fail "Installation requires root privileges. Run: sudo bash install.sh"
[[ -f "$SOURCE/devil" ]] || fail "Missing main executable: devil"
[[ -f "$SOURCE/run.sh" ]] || fail "Missing launcher: run.sh"
[[ -d "$SOURCE/core" ]] || fail "Missing core modules"
[[ -d "$SOURCE/modules" ]] || fail "Missing module files"

info "DEVIL v1.0 - Emergency Verification & Intelligent Linux Recovery"
info "Installing to: $PREFIX"

# Prompt for installation
if [[ -e "$PREFIX" ]]; then
  printf '%sInstallation exists at %s. Replace? [y/N]%s ' "$C_YELLOW" "$PREFIX" "$C_RESET"
  read -r reply || reply=""
else
  printf 'Install DEVIL to %s? [y/N] ' "$PREFIX"
  read -r reply || reply=""
fi
[[ "$reply" =~ ^([Yy]|[Yy][Ee][Ss])$ ]] || { echo 'Installation cancelled.'; exit 0; }

# Stage installation
mkdir -p -- /opt
stage=$(mktemp -d /opt/.devil-stage.XXXXXX) || fail "Cannot create staging directory"
cleanup() { rm -rf -- "$stage" 2>/dev/null || true; }
trap cleanup EXIT

info "Staging files..."
for item in devil run.sh README.md LICENSE CHANGELOG.md CONTRIBUTING.md assets config core modules themes ui docs tests scripts; do
  [[ -e "$SOURCE/$item" ]] && cp -a -- "$SOURCE/$item" "$stage/" || true
done

# Set permissions
chown -R root:root -- "$stage" 2>/dev/null || true
find "$stage" -type f \( -name '*.sh' -o -name devil \) -exec chmod 0755 {} + 2>/dev/null || true
find "$stage" -type f ! \( -name '*.sh' -o -name devil \) -exec chmod 0644 {} + 2>/dev/null || true

# Record installation metadata
printf 'DEVIL=%s\nINSTALLED_AT=%s\n' '1.0.0' "$(date -Is)" >"$stage/.devil-install"

# Install
success "Creating installation directory"
if [[ -e "$PREFIX" ]]; then
  backup="${PREFIX}.backup-$(date +%Y%m%d-%H%M%S)"
  info "Backing up existing installation to $backup"
  mv -- "$PREFIX" "$backup"
fi
mv -- "$stage" "$PREFIX"
trap - EXIT

# Create launcher
success "Installing system launcher"
ln -sfn -- "$PREFIX/run.sh" "$LAUNCHER"

# Install desktop resources
if [[ -f "$PREFIX/assets/devil.png" ]]; then
  success "Installing application icon"
  install -Dm644 -- "$PREFIX/assets/devil.png" "$ICON_FILE" 2>/dev/null || true
fi

if [[ -f "$PREFIX/config/devil.desktop" ]]; then
  success "Installing desktop entry"
  install -Dm644 -- "$PREFIX/config/devil.desktop" "$DESKTOP_FILE" 2>/dev/null || true
fi

# Create man page
if command -v gzip >/dev/null 2>&1; then
  info "Creating man page..."
  cat > /tmp/devil.1 << 'MANPAGE'
.TH DEVIL 1 "2026" "DEVIL v1.0" "System Administration"
.SH NAME
devil \- Emergency Verification & Intelligent Linux Recovery
.SH SYNOPSIS
.B devil
[\fIOPTION\fR]
.SH DESCRIPTION
DEVIL is a comprehensive Linux boot recovery utility providing read-only diagnostics and safe, reversible repairs for GRUB, EFI, and boot configuration issues.
.SH OPTIONS
.TP
.B \-\-diagnose
Collect and print system diagnostics (read-only)
.TP
.B \-\-report
Generate JSON, text, and compressed reports
.TP
.B \-\-self-test
Validate installation and dependencies
.TP
.B \-\-dry-run
Show recovery commands without executing
.TP
.B \-\-safe
Simulate all recovery operations
.TP
.B \-\-test
Full test mode (read-only system)
.TP
.B \-\-debug
Enable verbose logging
.TP
.B \-\-grub-check
Validate GRUB configuration only
.TP
.B \-\-efi-list
List EFI boot entries only
.TP
.B \-\-multiboot
Detect installed operating systems
.TP
.B \-\-recovery-plan
Show health assessment
.TP
.B \-\-backups
List backup inventory
.TP
.B \-\-dependencies
Show command availability
.TP
.B \-\-version
Show version information
.TP
.B \-\-help
Show help message
.SH EXAMPLES
.TP
Run interactive dashboard:
.B devil
.TP
Collect diagnostics:
.B devil --diagnose
.TP
Generate reports:
.B devil --report
.TP
Simulate recovery:
.B devil --test
.SH FILES
.TP
.I /opt/devil
Main installation directory
.TP
.I ~/.local/state/devil
Session logs, reports, and backups
.TP
.I ~/.config/devil
User settings and configuration
.SH ENVIRONMENT
.TP
.B DEVIL_DEBUG
Set to 1 to enable debug logging
.TP
.B NO_COLOR
Disable colored output
.TP
.B XDG_STATE_HOME
Override state directory (default: ~/.local/state)
.SH AUTHOR
DEVIL Contributors
.SH LICENSE
GPL-2.0
.SH SEE ALSO
.B grub-mkconfig(8)
.B efibootmgr(8)
.B bash(1)
MANPAGE
  gzip -f /tmp/devil.1 2>/dev/null || true
  install -Dm644 /tmp/devil.1.gz "$MAN_FILE" 2>/dev/null || true
  rm -f /tmp/devil.1 /tmp/devil.1.gz
  success "Man page installed"
fi

# Post-install message
cat << 'MESSAGE'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ DEVIL v1.0 Installation Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Installation Details:
  • Installed to:    /opt/devil
  • System launcher: devil (in /usr/local/bin)
  • Desktop entry:   Available in application menu
  • Man page:        man devil

Quick Start:
  • Run dashboard:     devil
  • Diagnostics:       devil --diagnose
  • Generate reports:  devil --report
  • Simulate repairs:  devil --test
  • Full help:         devil --help

State Directories:
  • Logs & Reports:  ~/.local/state/devil/
  • Configuration:   ~/.config/devil/
  • Backups:         ~/.local/state/devil/backups/

To uninstall:
  sudo /opt/devil/uninstall.sh

Documentation:
  • README:          /opt/devil/README.md
  • Architecture:    /opt/devil/docs/ARCHITECTURE.md
  • Recovery Flow:   /opt/devil/docs/RECOVERY-FLOW.md
  • Developer Guide: /opt/devil/docs/DEVELOPER-GUIDE.md

Support:
  All diagnostics are read-only. Recovery operations always
  require explicit confirmation before execution.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MESSAGE
