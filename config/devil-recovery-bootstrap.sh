#!/usr/bin/env bash
# Devil_Recovery / devil_recovery Auto-Bootstrap
# Installed to /etc/profile.d/ — provides devil_recovery command system-wide.
# If the binary exists, this does nothing. If removed, it auto-reinstalls.

# Only define the function if the real binary is NOT installed
if ! command -v devil_recovery &>/dev/null 2>&1; then
    devil_recovery() {
        echo ""
        echo "  ██████╗ ███████╗██╗   ██╗██╗██╗"
        echo "  ██╔══██╗██╔════╝██║   ██║██║██║"
        echo "  ██║  ██║█████╗  ██║   ██║██║██║"
        echo "  ██║  ██║██╔══╝  ╚██╗ ██╔╝██║██║"
        echo "  ██████╔╝███████╗ ╚████╔╝ ██║███████╗"
        echo "  ╚═════╝ ╚══════╝  ╚═══╝  ╚═╝╚══════╝"
        echo "     Auto-Bootstrap"
        echo ""
        echo "  devil_recovery is not installed. Installing now..."
        echo ""

        # Download and install
        curl -fsSL https://raw.githubusercontent.com/Loverof-Darkness/Linux_Recovery/main/quick-install.sh | sudo bash

        # Unset this function so the real binary takes over
        unset -f devil_recovery 2>/dev/null || true

        # Run the newly installed command if it exists
        if command -v devil_recovery &>/dev/null 2>&1; then
            devil_recovery "$@"
        fi
    }
fi

# Backward compat: also define Devil_Recovery if not present
if ! command -v Devil_Recovery &>/dev/null 2>&1; then
    Devil_Recovery() {
        devil_recovery "$@"
    }
fi
