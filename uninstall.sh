#!/usr/bin/env bash
# DEVIL v1.0 Uninstallation Script
# Removes DEVIL while preserving user state (logs, reports, backups)

set -Eeuo pipefail
IFS=$' \t\n'

readonly PREFIX=/opt/devil
readonly LAUNCHER=/usr/local/bin/devil
readonly LAUNCHER_ALT=/usr/local/bin/Devil_Recovery
readonly DESKTOP_FILE=/usr/share/applications/devil.desktop
readonly ICON_FILE=/usr/share/pixmaps/devil.png
readonly MAN_FILE=/usr/share/man/man1/devil.1.gz

# Color output
C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'

fail() { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
success() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '%s●%s %s\n' "$C_BOLD" "$C_RESET" "$*"; }

# Verify root
[[ ${EUID:-999} -eq 0 ]] || fail "Uninstallation requires root privileges. Run: sudo bash $0"

# Check if DEVIL is installed
if [[ ! -e "$PREFIX" ]]; then
  info "DEVIL is not installed at $PREFIX"
  exit 0
fi

if [[ ! -f "$PREFIX/.devil-install" ]]; then
  printf '%sWARNING:%s This may not be a DEVIL installation.\n' "$C_YELLOW" "$C_RESET"
fi

# Display information
cat << 'MESSAGE'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  DEVIL v1.0 - Uninstallation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This script will remove DEVIL system files while PRESERVING:
  • ~/.local/state/devil/logs/
  • ~/.local/state/devil/reports/
  • ~/.local/state/devil/backups/
  • ~/.config/devil/

These files will be removed:
  • /opt/devil/
  • /usr/local/bin/devil
  • /usr/local/bin/Devil_Recovery
  • /usr/share/applications/devil.desktop
  • /usr/share/pixmaps/devil.png
  • /usr/share/man/man1/devil.1.gz

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MESSAGE

# Confirm uninstallation
printf 'Proceed with uninstallation? [y/N] '
read -r reply || reply=""
[[ "$reply" =~ ^([Yy]|[Yy][Ee][Ss])$ ]] || {
  info "Uninstallation cancelled"
  exit 0
}

# Perform uninstallation
info "Removing DEVIL installation..."

rm -f -- "$LAUNCHER" && success "Removed launcher: $LAUNCHER"
rm -f -- "$LAUNCHER_ALT" && success "Removed launcher: $LAUNCHER_ALT" || true
rm -f -- "$DESKTOP_FILE" && success "Removed desktop entry" || true
rm -f -- "$ICON_FILE" && success "Removed icon" || true
rm -f -- "$MAN_FILE" && success "Removed man page" || true
rm -rf -- "$PREFIX" && success "Removed installation: $PREFIX"

# Display completion message
cat << 'MESSAGE'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ DEVIL Uninstallation Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Preserved user state:
  • ~/.local/state/devil/  (logs, reports, backups)
  • ~/.config/devil/       (configuration)

To remove user state as well:
  rm -rf ~/.local/state/devil ~/.config/devil

To reinstall DEVIL:
  sudo bash /path/to/devil/install.sh

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MESSAGE
