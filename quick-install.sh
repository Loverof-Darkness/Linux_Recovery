#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DEVIL Quick Installer  —  NO GIT REQUIRED
#  One-line install from any terminal:
#
#    curl -fsSL https://raw.githubusercontent.com/Loverof-Darkness/Linux_Recovery/main/quick-install.sh | sudo bash
#
#  What this does:
#    1. Checks system requirements (Bash 5+, curl or wget)
#    2. Downloads the latest DEVIL tarball from GitHub (no git needed)
#    3. Installs to /opt/devil
#    4. Creates devil_recovery + devil commands system-wide
#    5. Cleans up temporary files
#
#  GitHub: https://github.com/Loverof-Darkness/Linux_Recovery
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -Eeuo pipefail
IFS=$' \t\n'

readonly REPO="Loverof-Darkness/Linux_Recovery"
readonly BRANCH="main"
readonly TARBALL_URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
readonly INSTALL_PREFIX="/opt/devil"
readonly LAUNCHER="/usr/local/bin/devil"
readonly LAUNCHER_DR="/usr/local/bin/devil_recovery"
readonly LAUNCHER_DR_CAP="/usr/local/bin/Devil_Recovery"

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

cleanup() { rm -rf "$TMPDIR_DL" 2>/dev/null || true; }
TMPDIR_DL=""
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

# ── Detect download tool ────────────────────────────────────────
fetch() {
    local url="$1" out="$2"
    if command -v curl &>/dev/null; then
        curl -fsSL -o "$out" "$url"
    elif command -v wget &>/dev/null; then
        wget -qO "$out" "$url"
    else
        fail "Neither curl nor wget found. Install one and try again."
    fi
}

# ── Preflight checks ───────────────────────────────────────────
preflight() {
    # Root check
    if [[ ${EUID:-999} -ne 0 ]]; then
        fail "This installer must be run as root.\n  Run: curl -fsSL https://raw.githubusercontent.com/$REPO/$BRANCH/quick-install.sh | sudo bash"
    fi

    # Bash version
    if [[ ${BASH_VERSINFO[0]} -lt 5 ]]; then
        fail "Bash 5 or newer is required (current: ${BASH_VERSION})"
    fi

    # Need curl or wget
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        warn "Neither curl nor wget found. Attempting to install curl..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq curl
        elif command -v dnf &>/dev/null; then
            dnf install -y -q curl
        elif command -v pacman &>/dev/null; then
            pacman -Sy --noconfirm curl
        elif command -v zypper &>/dev/null; then
            zypper install -y curl
        else
            fail "Cannot auto-install curl. Please install curl or wget manually and try again."
        fi
        command -v curl &>/dev/null || fail "curl installation failed"
        success "curl installed"
    fi

    # Need tar
    if ! command -v tar &>/dev/null; then
        fail "tar is required but not found. Install it and try again."
    fi

    success "All prerequisites satisfied"
}

# ── Download ────────────────────────────────────────────────────
download() {
    info "Downloading DEVIL from GitHub..."
    TMPDIR_DL=$(mktemp -d "${TMPDIR:-/tmp}/devil-install.XXXXXX") || fail "Cannot create temp directory"

    local tarball="$TMPDIR_DL/devil.tar.gz"
    if ! fetch "$TARBALL_URL" "$tarball"; then
        fail "Failed to download from GitHub. Check your internet connection."
    fi
    success "Download complete"

    info "Extracting..."
    tar -xzf "$tarball" -C "$TMPDIR_DL" || fail "Failed to extract archive"

    local extracted="$TMPDIR_DL/Linux_Recovery-$BRANCH"
    [[ -d "$extracted" ]] || fail "Extracted directory not found"

    success "Extraction complete"
}

# ── Install ─────────────────────────────────────────────────────
do_install() {
    local extracted="$TMPDIR_DL/Linux_Recovery-$BRANCH"

    # Check if install.sh exists and use it, otherwise do manual install
    if [[ -f "$extracted/install.sh" ]]; then
        info "Running DEVIL installer..."
        bash "$extracted/install.sh" --yes
    else
        # Manual install fallback
        info "Installing DEVIL to $INSTALL_PREFIX..."

        if [[ -d "$INSTALL_PREFIX" ]]; then
            local backup="${INSTALL_PREFIX}.backup-$(date +%Y%m%d-%H%M%S)"
            warn "Existing installation found, backing up to $backup"
            mv "$INSTALL_PREFIX" "$backup"
        fi

        mkdir -p /opt
        mv "$extracted" "$INSTALL_PREFIX"

        chown -R root:root "$INSTALL_PREFIX" 2>/dev/null || true
        find "$INSTALL_PREFIX" -type d -exec chmod 0755 {} + 2>/dev/null || true
        find "$INSTALL_PREFIX" -type f \( -name '*.sh' -o -name 'devil' -o -name 'Devil_Recovery' -o -name 'devil_recovery' \) \
            -exec chmod 0755 {} + 2>/dev/null || true
    fi

    # Install the devil_recovery fetch-and-run launcher
    if [[ -f "$INSTALL_PREFIX/devil_recovery" ]]; then
        command install -m755 "$INSTALL_PREFIX/devil_recovery" "$LAUNCHER_DR"
        success "Installed command: devil_recovery"
    fi

    # Install the Devil_Recovery smart launcher (backward compat)
    if [[ -f "$INSTALL_PREFIX/Devil_Recovery" ]]; then
        command install -m755 "$INSTALL_PREFIX/Devil_Recovery" "$LAUNCHER_DR_CAP"
        success "Installed command: Devil_Recovery"
    fi

    # Ensure devil command exists
    if [[ ! -f "$LAUNCHER" ]]; then
        cat > "$LAUNCHER" << 'WRAPPER'
#!/usr/bin/env bash
exec /opt/devil/run.sh "$@"
WRAPPER
        chmod 0755 "$LAUNCHER"
        success "Installed command: devil"
    fi

    success "Installation complete!"
}

# ── Post-install summary ───────────────────────────────────────
summary() {
    cat << EOF

${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}
  ${C_GREEN}✓${C_RESET} ${C_BOLD}DEVIL Successfully Installed!${C_RESET}
${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}

  ${C_CYAN}Commands available (from any terminal):${C_RESET}
    ${C_BOLD}devil_recovery${C_RESET}            Launch DEVIL
    ${C_BOLD}devil_recovery --update${C_RESET}   Update to latest version
    ${C_BOLD}devil${C_RESET}                     Direct launcher
    ${C_BOLD}devil --help${C_RESET}              Show all options

  ${C_CYAN}Quick start:${C_RESET}
    ${C_DIM}\$${C_RESET} devil_recovery
    ${C_DIM}\$${C_RESET} sudo devil --diagnose
    ${C_DIM}\$${C_RESET} sudo devil --report

  ${C_CYAN}To uninstall:${C_RESET}
    ${C_DIM}\$${C_RESET} devil_recovery --uninstall

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
