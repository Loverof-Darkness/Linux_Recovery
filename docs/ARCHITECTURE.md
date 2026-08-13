# DEVIL Architecture

## Overview

DEVIL is a modular Bash-based boot recovery utility with a clear separation of concerns:

- **Core** (`core/`) - Lifecycle management, logging, terminal detection, and configuration
- **Modules** (`modules/`) - Read-only diagnostics and narrowly-scoped recovery operations
- **UI** (`ui/`) - Full-screen ANSI terminal interface with keyboard navigation
- **Themes** (`themes/`) - Color schemes and visual styling
- **Assets** (`assets/`) - Branding images and logos

## Design Principles

### 1. Read-Only First

All diagnostic operations are completely read-only. The system cannot be modified by diagnostics under any circumstances. This makes DEVIL safe to run without risk.

### 2. Explicit Confirmation

Every mutation (write operation) requires:
- Root privileges explicitly requested
- A backup created automatically
- User confirmation via interactive prompt
- Simulation mode support (--test, --dry-run, --safe)

### 3. Reversibility

All modifications are reversible:
- Automatic backups in `$DEVIL_DATA_DIR/backups/`
- Backup management in recovery module
- Ability to restore from saved state

### 4. Conservative Repair

Recovery never:
- Installs new bootloaders
- Modifies Windows BCD
- Automatically unlocks encrypted volumes
- Mounts filesystems without explicit action
- Changes RAID/LVM state

Recovery only:
- Regenerates existing GRUB configurations
- Modifies EFI boot entries
- Repairs BootOrder when explicitly requested

## Module Structure

### Core Modules (`core/`)

#### bootstrap.sh
- Application initialization
- Command-line argument parsing
- Module loading orchestration
- Main entry point dispatcher

#### common.sh
- Utility functions (error handling, file operations)
- JSON serialization
- Safe backup functionality
- Filesystem helpers

#### config.sh
- Settings file management
- Theme selection
- Mouse input configuration
- Report detail level

#### logging.sh
- Session logging (human-readable and JSONL)
- Action recording with duration/status
- Report generation (TXT, JSON, compressed archive)

#### terminal.sh
- Terminal capability detection
- Color system (TrueColor, 256-color, ANSI)
- Image rendering support (Kitty, iTerm2, SIXEL, Chafa, viu)
- Keyboard input handling
- Branding display

#### dependencies.sh
- Required and optional command verification
- Dependency reporting

### Recovery Modules (`modules/`)

#### diagnostics.sh
- System inspection
- Firmware detection (UEFI vs BIOS)
- Boot configuration analysis
- Filesystem enumeration
- LUKS, LVM, RAID detection
- Report generation

#### grub.sh
- GRUB configuration validation
- Distribution-aware config generation
- Menu entry inspection
- os-prober status checking
- Backup and restore functionality

#### efi.sh
- EFI boot entry management
- BootOrder manipulation
- Secure Boot status inspection
- EFI variable verification
- Entry creation/deletion

#### filesystems.sh
- Storage layout discovery
- Filesystem type detection
- Mount information retrieval
- Disk space analysis
- Encryption and RAID detection

#### recovery.sh
- Recovery policy enforcement
- Automatic repair coordination
- Backup inventory management
- Health assessment
- Simulation mode handling

#### multiboot.sh
- Multi-OS detection
- Boot configuration validation
- Windows detection
- Bootloader inspection

### UI Modules (`ui/`)

#### dashboard.sh
- Full-screen terminal interface
- Menu navigation
- Action delegation
- Interactive recovery workflows
- Professional presentation

## Data Flow

```
run.sh (launcher)
    ↓
devil (main executable)
    ↓
core/bootstrap.sh (initialization)
    ├→ core/common.sh (utilities)
    ├→ core/logging.sh (logging)
    ├→ core/terminal.sh (UI framework)
    ├→ core/dependencies.sh (validation)
    ├→ core/config.sh (settings)
    └→ All module files
    ↓
devil_main()
    ├→ (diagnostics mode) → modules/diagnostics.sh
    ├→ (recovery mode) → modules/recovery.sh
    ├→ (ui mode) → ui/dashboard.sh
    └→ (interactive) → full menu system
    ↓
Output: logs, reports, system modifications
```

## Execution Modes

### Diagnostic Modes (Read-Only)

- `--diagnose` - Collect and print diagnostics
- `--report` - Generate JSON, TXT, and compressed reports
- `--self-test` - Validate syntax and basic functionality
- `--dependencies` - Check command availability
- `--grub-check` - GRUB validation only
- `--efi-list` - EFI entry display
- `--multiboot` - Detect installed systems
- `--recovery-plan` - Show health assessment

### Interactive Mode

- (no arguments) - Launch full-screen dashboard

### Simulation Modes

- `--test` - Simulate all operations (read-only system)
- `--dry-run` - Show commands without executing
- `--safe` - Simulate recovery operations only

### Debug Mode

- `--debug` - Enable detailed logging

## State Management

### Configuration Files

```
~/.config/devil/settings.conf
  theme=pitch-black
  mouse=auto
  report_detail=standard
```

### Log Files

```
~/.local/state/devil/logs/devil-TIMESTAMP.log      (human-readable)
~/.local/state/devil/logs/devil-TIMESTAMP.jsonl    (structured)
```

### Reports

```
~/.local/state/devil/reports/devil-report-TIMESTAMP.txt
~/.local/state/devil/reports/devil-report-TIMESTAMP.json
~/.local/state/devil/reports/devil-report-TIMESTAMP.tar.gz
```

### Backups

```
~/.local/state/devil/backups/
  grub.cfg-TIMESTAMP-$$
  efi-TIMESTAMP-$$.txt
  etc.
```

## Terminal UI Architecture

### Rendering

- ANSI escape sequences (no ncurses/dialog dependency)
- Keyboard-driven navigation
- Optional mouse support
- Full-screen redrawing per input

### Color System

**TrueColor (24-bit):**
- RGB color definition
- 16.7 million colors
- Best quality, modern terminals

**256-Color:**
- ANSI color palette
- Limited but adequate colors
- Good compatibility

**ANSI (16-color):**
- Basic terminal colors
- Lowest common denominator
- Always available

**Fallback:**
- No color (NO_COLOR env, non-TTY)
- Suitable for logging and piping

### Keyboard Input

- Arrow keys (↑↓←→) for navigation
- Enter to select
- Home/End for menu extremes
- Page Up/Down for scrolling
- 'q' to quit
- Mouse support (optional, configurable)

## Image Rendering

Priority order (best → worst):

1. **Kitty Graphics** - Native protocol, highest quality
2. **Kitten icat** - Kitty's image tool
3. **iTerm2 Graphics** - iTunes Terminal support
4. **SIXEL** - Terminal graphics protocol
5. **Chafa** - Unicode/ANSI art conversion
6. **viu** - TUI image viewer
7. **ANSI Logo** - Fallback text-based logo

## Error Handling

### Traps

```bash
trap 'devil_cleanup' EXIT
trap 'die "interrupted"' INT TERM
```

### Cleanup

- Terminal restoration (show cursor, reset colors)
- Log file finalization
- Temporary directory cleanup

### Error Propagation

- `die()` - Fatal error, exit with message
- `log_error()` - Log error, continue
- `confirm()` - Ask before destructive action

## Safety Mechanisms

### 1. Pre-Action Validation

```bash
run_action "description" command args
# Records start, duration, exit code
# Respects simulation modes
# Automatic logging
```

### 2. Automatic Backups

```bash
backup=$(devil_safe_backup_file "$source" "$label")
# Creates timestamped, mode-preserved backups
# Fails safely if backup not possible
```

### 3. Mode Verification

```bash
((DEVIL_TEST || DEVIL_DRY_RUN || DEVIL_SAFE)) && {
  # Simulation mode active - don't modify system
}
```

### 4. Permission Checking

```bash
require_root
# Exits if not running as root
# Required only at mutation point
```

## Performance Considerations

- No unnecessary mountpoints
- Minimal process spawning
- Efficient string processing with bash built-ins
- Streaming output (no large buffers)
- Lazy loading of optional modules

## Extensibility

### Adding a New Recovery Module

1. Create `modules/newfeature.sh`
2. Implement functions starting with `newfeature_`
3. Source in `core/bootstrap.sh`
4. Add menu item to `ui/dashboard.sh`
5. Call appropriate functions from UI

### Adding CLI Mode

1. Add case to `devil_parse_args()`
2. Set `DEVIL_MODE` appropriately
3. Implement handler in `devil_main()`

### Custom Theme

1. Create `themes/mytheme.sh`
2. Define color variables
3. Update `config.sh` allowed values
4. Set via settings file

## Security Considerations

- No credential handling (sudo-only for operations)
- No network access
- No external dependencies (standard Linux tools only)
- Proper file permissions on state directories (700)
- Safe JSON serialization (escaping)
- No shell injection vectors
- Quoted variable expansion

## Limitations

- Requires Linux (Bash 5+)
- EFI operations need UEFI boot + writable efivars
- Some operations need root
- Large terminal preferred (80+ columns recommended)
- Live ISO environment recommended for safety

