# DEVIL Changelog

All notable changes to DEVIL (Devil Emergency Verification & Intelligent Linux Recovery) are documented in this file.

## [Unreleased]

### Fixed
- Live-USB diagnostics now inspect a mounted Linux target instead of always reading the live environment's `/boot` and `grub.cfg`.
- Added automatic selection of one mounted Linux root, including Garuda Btrfs `@` subvolumes, plus explicit `--target-root PATH` selection when needed.
- Blocked direct GRUB regeneration and rollback against mounted targets so live-environment tools cannot run with the wrong runtime context.

## [1.0.0] - 2026-01-15

### Added - Initial Release

#### Core Infrastructure
- Comprehensive launcher (`run.sh`) with path resolution
- Application bootstrap with module loading orchestration
- Safe file operations with automatic backup functionality
- Timestamped audit logging (human-readable and JSONL)
- Session tracking and action recording

#### Terminal & UI System
- Full-screen ANSI terminal interface (no ncurses dependency)
- Terminal capability detection (TrueColor, 256-color, ANSI)
- Image renderer support:
  - Kitty Graphics Protocol
  - Kitten icat
  - iTerm2 graphics
  - SIXEL protocol
  - Chafa (Unicode/ANSI art)
  - viu (TUI image viewer)
  - ANSI logo fallback
- Professional theming system (Pitch-Black theme)
- Keyboard navigation (arrows, Home/End, Page Up/Down)
- Optional mouse support
- Color system with RGB and 256-color palettes

#### Diagnostics Engine
- Read-only system inspection
- Firmware detection (UEFI vs BIOS)
- Boot configuration analysis
- Filesystem enumeration (Ext4, Btrfs, XFS, F2FS, NTFS)
- LUKS, LVM, RAID detection
- Kernel and initramfs validation
- Secure Boot status inspection
- TPM detection and reporting
- BitLocker volume detection (detection-only)
- Installation discovery across partitions
- Report generation (JSON, TXT, compressed archives)

#### Recovery Modules
- **GRUB Manager**
  - Configuration validation with syntax checking
  - Menu entry inspection
  - os-prober status verification
  - Distribution-aware config generation
  - Automatic backup and restore functionality
  - Rollback support

- **EFI Manager**
  - Boot entry listing and inspection
  - BootOrder manipulation
  - Entry creation and deletion
  - Secure Boot status checking
  - EFI backup functionality
  - Boot entry validation

- **Multi-Boot Manager**
  - Multi-OS detection without mounting
  - Linux distribution identification
  - Windows installation detection
  - Boot configuration inventory
  - Bootloader validation

- **Filesystem Manager**
  - Storage layout discovery
  - Filesystem type detection
  - Mount information retrieval
  - Disk space analysis
  - Encryption and RAID status
  - Detailed filesystem inspection

#### Recovery Engine
- Automatic damage detection
- Conservative repair policies
- Health assessment functionality
- Backup management
- Dry-run and simulation support
- Test mode for safe rehearsal
- Rollback capability

#### Dashboard & UI
- Main menu with 15 core operations
- Interactive navigation
- Dashboard overview
- Diagnostics viewer
- Automatic recovery workflow
- Advanced recovery tools menu
- Settings configuration
- Help and documentation
- About information
- Logs and reports viewing

#### Safety Features
- Read-only diagnostic mode
- Explicit confirmation for all mutations
- Automatic backups before changes
- Simulation modes (--test, --dry-run, --safe)
- Dry-run preview
- Rollback support
- Permission verification
- State protection (readonly media fallback)

#### Installation & Integration
- System installation script with staging
- Desktop entry creation
- System launcher (`devil` command)
- Man page generation
- Uninstallation with state preservation
- Backup of existing installations

#### Documentation
- Comprehensive README with examples
- Architecture documentation
- Recovery flow documentation
- Developer guide
- Contributing guidelines
- Man page
- Inline code documentation

#### Testing
- Self-test functionality
- Syntax validation
- Module loading verification
- Basic functionality checks
- Dry-run simulation
- Test mode support

#### Configuration
- XDG-compliant state directory
- Configuration file support
- Theme selection
- Mouse input toggle
- Report detail level
- Debug logging option

#### Logging & Reporting
- Timestamped session logs
- JSON-formatted logs
- Structured action recording
- Report generation with metadata
- Compressed archive creation
- Environment information capture

### Features

#### Supported Distributions
- Arch Linux
- Garuda Linux
- Manjaro
- EndeavourOS
- Ubuntu
- Debian
- Linux Mint
- Fedora
- RHEL
- openSUSE
- Pop!_OS
- Any Linux with Bash 5+

#### Supported Terminal Emulators
- Kitty
- Konsole
- GNOME Terminal
- Alacritty
- WezTerm
- Foot
- XTerm
- Linux TTY

#### Filesystem Support
- Ext2, Ext3, Ext4
- Btrfs (with subvolume detection)
- XFS
- F2FS
- NTFS (detection and warning)
- LUKS encryption
- LVM volumes
- MD RAID arrays
- Nested subvolumes

#### Storage Configurations
- Separate /boot partitions
- Separate EFI partitions
- Multiple boot entries
- Complex RAID layouts
- Encrypted root filesystems
- LVM logical volumes

### Safety & Design
- Never modifies system without confirmation
- Creates automatic backups before changes
- Respects simulation modes
- Preserves user state on uninstall
- Secure file operations
- Proper permission handling
- No credential management

### Limitations (Documented)
- Requires Bash 5+
- Linux-only
- Some operations require root
- EFI operations need UEFI + writable efivars
- Large terminal recommended (80+ columns)
- No automatic partition mounting
- RAID/LVM not automatically unlocked
- Encrypted volumes not automatically decrypted
- Secure Boot not modified

### Dependencies
#### Required
- bash (5.0+)
- awk
- sed
- grep
- find
- findmnt
- lsblk

#### Optional
- efibootmgr (EFI operations)
- grub-mkconfig or grub2-mkconfig (GRUB repair)
- cryptsetup (LUKS detection)
- lvs, pvs, vgs (LVM support)
- btrfs (Btrfs support)
- mokutil (Secure Boot)
- systemd-analyze (TPM detection)
- os-prober (Multi-boot detection)
- Image renderers (Kitty, Chafa, viu, etc.)

### Known Issues
- None documented for v1.0.0

### Future Considerations
- GUI variant (optional)
- Windows Boot Manager repair
- MacOS boot detection
- RAID recovery automation
- LVM management tools
- Additional filesystem support
- Performance optimization

---

## Format

This changelog follows [Keep a Changelog](https://keepachangelog.com/) conventions.

### Categories
- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for vulnerability fixes

### Versioning

DEVIL uses [Semantic Versioning](https://semver.org/):
- MAJOR: Breaking changes or major features
- MINOR: New features, backward compatible
- PATCH: Bug fixes, backward compatible

---

## Guidelines for Contributors

When documenting changes:
1. Add entry under appropriate version heading
2. Use category headings
3. Write clear, concise descriptions
4. Include issue/PR references
5. Update version at top of document

Example:
```markdown
### Fixed
- GRUB detection now works with Fedora 34+ (#123)
```

---

**Last Updated:** 2026-01-15  
**Release Manager:** DEVIL Contributors  
**License:** GPL-2.0
