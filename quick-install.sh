#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DEVIL Quick Installer
#  One-line install from any terminal:
#
#    curl -fsSL https://raw.githubusercontent.com/Loverof-Darkness/Linux_Recovery/main/quick-install.sh | sudo bash
#
#  What this does:
#    1. Checks system requirements (Bash 5+, git)
#    2. Clones the latest DEVIL from GitHub
#    3. Runs the installer non-interactively
#    4. Creates Devil_Recovery + devil commands
#    5. Cleans up temporary files
#
#  GitHub: https://github.com/Loverof-Darkness/Linux_Recovery
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -Eeuo pipefail
IFS=$' \t\n'

readonly REPO_URL="https://github.com/Loverof-Darkness/Linux_Recovery.git"
readonly CLONE_DIR="/tmp/devil-recovery-install"
readonly INSTALL_PREFIX="/opt/devil"

# ── Colors ──────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\e[31m'    C_GREEN=$'\e[32m'  C_YELLOW=$'\e[33m'
    C_CYAN=$'\e[36m'   C_BOLD=$'\e[1m'    C_DIM=$'\e[2m'
    C_RESET=$'\e[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_BOLD='' C_DIM='' C_RESET=''
fi

# ── Helpers ─────────────────────────────────────────────────────
fail()    { printf '%s✗ ERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
success() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info()    { printf '%s●%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
warn()    { printf '%s⚠ WARNING:%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }

cleanup() { rm -rf "$CLONE_DIR" 2>/dev/null || true; }
trap cleanup EXIT

banner() {
    printf '%s' "$C_BOLD$C_RED"
    cat << 'EOF'

    ██████╗ ███████╗██╗   ██╗██╗██╗
    ██╔══██╗██╔════╝██║   ██║██║██║
    ██║  ██║█████╗  ██║   ██║██║██║
    ██║  ██║██╔══╝  ╚██╗ ██╔╝██║██║
    ██████╔╝███████╗ ╚████╔╝ ██║███████╗
    ╚═════╝ ╚══════╝  ╚═══╝  ╚═╝╚══════╝
       Quick Installer

EOF
    printf '%s' "$C_RESET"
}

# ── Preflight checks ───────────────────────────────────────────
preflight() {
    # Root check
    if [[ ${EUID:-999} -ne 0 ]]; then
        fail "This installer must be run as root.\n  Run: curl -fsSL https://raw.githubusercontent.com/Loverof-Darkness/Linux_Recovery/main/quick-install.sh | sudo bash"
    fi

    # Bash version
    if [[ ${BASH_VERSINFO[0]} -lt 5 ]]; then
        fail "Bash 5 or newer is required (current: ${BASH_VERSION})"
    fi

    # git
    if ! command -v git &>/dev/null; then
        warn "git is not installed. Attempting to install..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq git
        elif command -v dnf &>/dev/null; then
            dnf install -y -q git
        elif command -v pacman &>/dev/null; then
            pacman -Sy --noconfirm git
        elif command -v zypper &>/dev/null; then
            zypper install -y git
        else
            fail "Cannot auto-install git. Please install git manually and try again."
        fi
        command -v git &>/dev/null || fail "git installation failed"
        success "git installed"
    fi

    success "All prerequisites satisfied"
}

# ── Download ────────────────────────────────────────────────────
download() {
    info "Downloading DEVIL from GitHub..."
    rm -rf "$CLONE_DIR" 2>/dev/null || true

    if ! git clone --depth 1 "$REPO_URL" "$CLONE_DIR" 2>&1; then
        fail "Failed to clone repository. Check your internet connection."
    fi
    success "Download complete"
}

# ── Install ─────────────────────────────────────────────────────
do_install() {
    [[ -f "$CLONE_DIR/install.sh" ]] || fail "install.sh not found in cloned repository"

    info "Running DEVIL installer..."
    bash "$CLONE_DIR/install.sh" --yes

    # Install the Devil_Recovery smart launcher
    if [[ -f "$CLONE_DIR/Devil_Recovery" ]]; then
        command install -m755 "$CLONE_DIR/Devil_Recovery" /usr/local/bin/Devil_Recovery
        success "Installed command: Devil_Recovery"
    else
        # Fallback: create a symlink to run.sh
        ln -sfn "$INSTALL_PREFIX/run.sh" /usr/local/bin/Devil_Recovery
        success "Created command: Devil_Recovery"
    fi

    success "Installation complete!"
}

# ── Post-install summary ───────────────────────────────────────
summary() {
    cat << EOF

${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}
  ${C_GREEN}✓${C_RESET} ${C_BOLD}DEVIL Successfully Installed!${C_RESET}
${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}

  ${C_CYAN}Commands available:${C_RESET}
    ${C_BOLD}Devil_Recovery${C_RESET}            Launch DEVIL (auto-updates supported)
    ${C_BOLD}Devil_Recovery --update${C_RESET}   Update to latest version
    ${C_BOLD}devil${C_RESET}                     Direct launcher
    ${C_BOLD}devil --help${C_RESET}              Show all options

  ${C_CYAN}Quick start:${C_RESET}
    ${C_DIM}\$${C_RESET} Devil_Recovery
    ${C_DIM}\$${C_RESET} sudo devil --diagnose
    ${C_DIM}\$${C_RESET} sudo devil --report

  ${C_CYAN}To uninstall:${C_RESET}
    ${C_DIM}\$${C_RESET} Devil_Recovery --uninstall

${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}

EOF
}

# ── Main ────────────────────────────────────────────────────────
main() {
    banner
    preflight
    download
    do_install
    summary
}

main "$@"
