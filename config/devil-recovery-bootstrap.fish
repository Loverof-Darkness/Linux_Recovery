# Devil_Recovery / devil_recovery Auto-Bootstrap for Fish Shell
# Installed to /etc/fish/conf.d/ — provides devil_recovery command system-wide.
# If the binary exists, this does nothing. If removed, it auto-reinstalls.

if not command -q devil_recovery
    function devil_recovery
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

        # Remove this function so the real binary takes over
        functions -e devil_recovery

        # Run the newly installed command
        if command -q devil_recovery
            command devil_recovery $argv
        end
    end
end

# Backward compat: also define Devil_Recovery if not present
if not command -q Devil_Recovery
    function Devil_Recovery
        devil_recovery $argv
    end
end
