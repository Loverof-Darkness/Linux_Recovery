# DEVIL v1.0

**Devil Emergency Verification & Intelligent Linux Recovery** — A comprehensive, Bash-native Linux boot recovery utility providing read-only diagnostics and safe, reversible repairs for GRUB, EFI, and boot configuration issues.

DEVIL is designed as a professional desktop application running entirely within your terminal, with no external UI library dependencies.

## Features

- 🔍 **Read-Only Diagnostics** - Safe system inspection without any modifications
- 🛠️ **Conservative Recovery** - Only repairs damaged components, never reinstalls unnecessarily
- 🔐 **Explicit Confirmation** - Every change requires user approval and creates backups
- 🔄 **Reversible Operations** - Automatic backups enable restoration if needed
- 🎨 **Professional UI** - Full-screen terminal interface with keyboard navigation
- 🖼️ **Image Rendering** - Support for Kitty, iTerm2, SIXEL, and ANSI artwork
- 💾 **Multi-Boot Detection** - Identifies all installed operating systems
- 💿 **Filesystem Support** - Ext4, Btrfs, XFS, F2FS, LUKS, LVM, RAID
- 📊 **Comprehensive Reporting** - JSON, TXT, and compressed archives
- 🚀 **Portable** - Standard Bash with minimal external dependencies

## Quick Start

### ⚡ One-Line Install (from any terminal)
```bash
curl -sL loverof-darkness.github.io/Linux_Recovery/go | sudo bash
```
### Or 

```bash
curl -fsSL https://raw.githubusercontent.com/Loverof-Darkness/Linux_Recovery/main/quick-install.sh | sudo bash
```

After install, just type `Devil_Recovery` or `devil` from **any terminal** — it works system-wide.

### Devil_Recovery Command

```bash
# Launch DEVIL (auto-installs if not present)
Devil_Recovery

# Force update to latest version from GitHub
Devil_Recovery --update

# Uninstall cleanly
Devil_Recovery --uninstall

# All devil flags work too
Devil_Recovery --diagnose
Devil_Recovery --report
Devil_Recovery --test
```

### Run from Source

```bash
# Interactive dashboard
bash run.sh

# Read-only diagnostics
bash run.sh --diagnose

# Generate reports
bash run.sh --report

# Simulate recovery (test mode)
bash run.sh --test

# Help and options
bash run.sh --help
```

### Install Globally (manual)

```bash
# Review the source
cat install.sh

# Install to /opt/devil with system launcher
sudo bash install.sh

# Run from anywhere
devil
Devil_Recovery
devil --diagnose
devil --report
```

## Safety Controls

DEVIL provides multiple safety modes:

- **`--test`** - Full simulation mode (read-only system)
- **`--dry-run`** - Show recovery commands without executing
- **`--safe`** - Simulate recovery while keeping diagnostics real
- **`--debug`** - Detailed logging of all operations

All diagnostics are completely read-only. Recovery operations:
1. Create automatic backups
2. Display what will change
3. Ask for explicit confirmation
4. Log all actions
5. Support rollback

## Supported Distributions

- Arch Linux / Garuda
- Debian / Ubuntu / Linux Mint
- Fedora / RHEL
- openSUSE
- Manjaro / EndeavourOS
- Pop!_OS
- Generic Linux with Bash 5+

DEVIL works best when run from a Live ISO booted in the same firmware mode (UEFI/BIOS) as your installed system.

## Command Reference

### Diagnostic Commands

```bash
devil --diagnose      # Collect and print system diagnostics
devil --report        # Generate JSON, text, and compressed reports
devil --self-test     # Validate installation and dependencies
devil --dependencies  # Show command availability
devil --debug         # Enable verbose logging
```

### Recovery-Related

```bash
devil --recovery-plan     # Show health assessment
devil --dry-run           # Show recovery commands without executing
devil --test              # Full test/simulation mode
devil --backups           # List backup inventory
```

### Full Live-USB Assessment Report

To save all non-destructive checks to the project `reports/` directory, run
this from the project folder. It includes diagnostics, dependencies, GRUB,
EFI, multi-boot detection, and automatic-recovery dry-run/test assessments;
it does not change disks, EFI variables, or bootloader files.

```bash
sudo bash scripts/capture-recovery-report.sh
```

The output ends with the exact saved report path, for example
`reports/full-recovery-report-YYYYMMDD-HHMMSS.txt`.

### Specific Inspections

```bash
devil --grub-check      # Validate GRUB configuration only
devil --efi-list        # List EFI boot entries
devil --multiboot       # Detect installed operating systems

# Validate an installed system already mounted at /mnt
devil --target-root /mnt --grub-check
```

### Inspecting a Mounted Installation from a Live USB

DEVIL never mounts storage during normal diagnostics. Mount the installed root
first, including any separate `/boot` and EFI partitions beneath it, then point
DEVIL at that root:

```bash
# Typical Garuda Btrfs root (adjust partition names for your system)
sudo mount -o subvol=@ /dev/nvme0n1p2 /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot/efi    # only when this is your ESP

# Read and validate the installed system, not the live USB
devil --target-root /mnt --diagnose
devil --target-root /mnt --grub-check
```

When exactly one mounted Linux root is visible from a Live ISO, DEVIL selects
it automatically. This includes a Btrfs top-level mount with a Garuda `@`
subvolume. If multiple mounted roots are found, it refuses to guess and asks
for `--target-root PATH`.

Mounted-target diagnostics are read-only. DEVIL will not run the live USB's
`grub-mkconfig` against the target; use the guided live-environment reinstall
for a reviewed chrooted repair.

### Guided Automatic Recovery from a Live USB

The recovery action is automatic only after you review and confirm the proposed
mapping. It does not silently choose a disk or install a bootloader.

When running the terminal UI from a Live USB, choose **Installed System
Selector** (or **Choose installed system to repair** in Automatic Recovery)
to select the Linux installation first. DEVIL probes candidates read-only,
including Btrfs `@` and `@root` subvolumes, and keeps the selection only for
the current session. The same named Linux installations are shown in
**Read Only Diagnostics** and `--recovery-plan`.

### Reports and audit trails

After **Continue to main menu**, DEVIL automatically runs a full read-only
assessment and saves one `full-recovery-report-*.txt` in the tool's `reports/`
directory. The audit trail is appended inside this same file, recording menu
choices, selected repair system, recovery transcripts, and the output/result
of actions performed through the recovery managers. Open
**Reports** at any time to create an additional current assessment.

1. Boot the Live USB in the same firmware mode as the installed system. For a
  UEFI installation, confirm that `/sys/firmware/efi` exists.
2. Ensure the Live USB has `mount`, `umount`, `chroot`, `lsblk`, `blkid`, and
  `efibootmgr`. The installed target must contain `grub-install` and
  `grub-mkconfig` (or `grub2-mkconfig`); DEVIL deliberately runs those tools
  from inside the target chroot.
3. Run a read-only assessment:

  ```bash
  sudo bash run.sh --diagnose
  sudo bash run.sh --recovery-plan
  ```

4. Start the dashboard and choose **Automatic Recovery**, or run:

  ```bash
  sudo bash run.sh
  ```

  Review the selected Linux root, separate `/boot` (when configured), EFI
  System Partition, firmware mode, and EFI loader ID before confirming.
5. Confirm the guided repair. DEVIL mounts the selected installation, binds
  `/dev`, `/proc`, `/sys`, and `/run`, runs `grub-install` and the target's
  GRUB generator inside a chroot, then unmounts the recovery tree.
6. Reboot only after the command reports successful cleanup. Remove the Live
  USB and select the repaired Linux entry in firmware if necessary.

DEVIL refuses to continue when the root, `/boot`, or EFI mapping is ambiguous,
when a separate `/boot` cannot be mounted, when required target tools are
missing, or when cleanup fails. These refusals are intentional: select or
mount the correct target manually and rerun the assessment rather than forcing
a repair against an uncertain disk.

### Meta

```bash
devil --version         # Show version information
devil --help            # Show help message
```

## Modes of Operation

### Interactive Dashboard

Run `devil` with no arguments for a full-screen menu interface with:
- Dashboard and system overview
- Read-only diagnostics
- Automatic recovery
- Advanced recovery tools (GRUB, EFI, BootOrder)
- Filesystem inspection
- Multi-boot detection
- Logs and report generation
- Settings management

### Batch Operations

Perfect for scripting or remote systems:

```bash
# Collect diagnostics and exit
devil --diagnose > system-report.txt

# Generate structured reports for analysis
devil --report

# Validate system health without modification
devil --test
```

### System Integration

After installation, DEVIL integrates with your desktop:
- Accessible from application menus
- Registered `devil` command available system-wide
- Man page available: `man devil`
- Desktop entry for launcher

## State Directories

DEVIL stores session logs, settings, and backups using XDG directories:

```
~/.local/state/devil/
  ├── logs/          # Session logs (human-readable and JSONL)
  └── backups/       # Automatic backups from recovery operations

~/.config/devil/
  └── settings.conf  # User preferences
```

After **Continue to main menu**, DEVIL runs its full read-only assessment
(dependencies, diagnostics, GRUB, EFI, installed-system scan, filesystems,
and dry-run recovery plan) and saves one `full-recovery-report-*.txt` in the
project folder's `reports/` directory. The same file receives the session's
audit trail. If the tool is running from a non-writable location, DEVIL does
not save reports elsewhere; it displays that no report was saved.

On read-only media, DEVIL falls back to `/tmp` only for internal state such as
logs and backups. It does not redirect reports: if the tool's own `reports/`
folder is not writable, no report is saved.

## Recovery Operations

DEVIL never modifies your system without explicit action and confirmation:

### Read-Only Inspection

- Hardware firmware detection (UEFI vs BIOS)
- Kernel and initramfs validation
- Boot configuration analysis
- Filesystem layout enumeration
- EFI boot entry inspection
- GRUB configuration examination
- Secure Boot and TPM status
- Encrypted volume detection
- RAID and LVM inventory

### Conservative Repairs

DEVIL can:
- ✅ Regenerate existing GRUB configurations (with backup and confirmation)
- ✅ Manage EFI boot entries (create, delete, modify BootOrder)
- ✅ Validate and repair BootOrder
- ✅ Guided GRUB reinstall from a live ISO (UEFI, including common Btrfs `@`/`@root` layouts)
- ✅ Generate multi-boot menu entries
- ✅ Create and restore backups

DEVIL will NOT:
- ❌ Guess or unlock encrypted roots; LUKS/LVM/RAID volumes must be opened by the operator first
- ❌ Modify Windows BCD
- ❌ Automatically mount or unlock encrypted volumes
- ❌ Change RAID/LVM configuration
- ❌ Modify Secure Boot settings

## Limitations

- Requires Linux with Bash 5+
- EFI operations need UEFI boot with writable EFI variables
- Some operations require root privileges (only at mutation point)
- Assumes reasonable terminal size (80+ columns recommended)
- Storage detected without mounting (encryption/RAID not unlocked automatically)
- Mounted-installation diagnostics require the root (and any separate boot partitions) to be mounted first
- Secure Boot and TPM are inspected only, not modified

## Installation

### System Installation

```bash
# Review what will be installed
cat install.sh

# Install with root privileges
sudo bash install.sh

# This installs to /opt/devil and creates:
# • /usr/local/bin/devil (launcher)
# • Desktop application entry
# • System man page
```

### Uninstallation

```bash
# Remove with root privileges
sudo bash uninstall.sh

# This preserves user state:
# • ~/.local/state/devil/  (logs and backups)
# • ~/.config/devil/       (configuration)
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - System design and module structure
- [Recovery Flow](docs/RECOVERY-FLOW.md) - Detailed recovery processes
- [Developer Guide](docs/DEVELOPER-GUIDE.md) - Extending and contributing

## Environment Variables

```bash
# Enable debug logging
export DEVIL_DEBUG=1

# Disable colored output
export NO_COLOR=1

# Override state directory
export XDG_STATE_HOME=/custom/state

# Test simulation mode
export DEVIL_TEST=1
```

## Examples

### Scenario: Broken GRUB After Update

```bash
# 1. Run read-only diagnostics first
sudo devil --diagnose

# 2. If repair is needed, simulate the fix
sudo devil --test

# 3. If simulation looks good, run actual recovery
devil
# Select: Automatic Recovery
# Review changes, confirm when prompted

# 4. Generate detailed report
devil --report
```

### Scenario: Missing EFI Boot Entry

```bash
# 1. List current boot entries
devil --efi-list

# 2. From dashboard, use: EFI Manager
devil
# Select: EFI Manager
# Options: Create entry, Set BootOrder, Restore from backup

# 3. Verify changes
devil --efi-list
```

### Scenario: Multi-OS Setup Inspection

```bash
# 1. Detect all installed systems
devil --multiboot

# 2. Get detailed diagnostic
devil --diagnose

# 3. Validate bootloader configuration
devil --grub-check
```

## Performance

- Minimal resource usage
- No UI library overhead
- Efficient module loading
- Streaming output (no large buffers)
- Suitable for Live ISO environments

## Security

- No network access
- No credential handling (sudo-only for operations)
- No external package dependencies
- Proper file permissions on state directories
- Safe JSON serialization
- No shell injection vectors
- Quoted variable expansion throughout

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Code style and standards
- Testing requirements
- Submission process
- Module development

## License

GPL-2.0 - See [LICENSE](LICENSE) for details

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes and version history

## Support

DEVIL is a professional-grade tool. When reporting issues, include:

```bash
# Collect diagnostics for issue report
devil --report --debug
# Archives and audit trails are available in the project's reports/ directory.
```

## Acknowledgments

DEVIL was built with principles of safety, reversibility, and user control as fundamental design requirements. Every design decision prioritizes user system safety over convenience.

---

**Remember:** Always keep firmware media available before making boot configuration changes. Test recovery procedures on non-critical systems first.
