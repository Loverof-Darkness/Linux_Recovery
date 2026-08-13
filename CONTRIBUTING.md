# Contributing to DEVIL

We appreciate your interest in contributing to DEVIL - Devil Emergency Verification & Intelligent Linux Recovery. This document provides guidelines for developing, testing, and submitting contributions.

## Code of Conduct

- Be respectful and professional
- Provide constructive feedback
- Test your changes thoroughly
- Document your modifications

## Getting Started

### Prerequisites

- Bash 5.0 or newer
- Standard Linux utilities (awk, sed, grep, find)
- Git for version control
- ShellCheck for code quality checks (optional but recommended)

### Development Environment

```bash
# Test your changes
bash run.sh --self-test

# Validate syntax
bash -n devil
for f in core/*.sh modules/*.sh ui/*.sh; do bash -n "$f"; done
```

## Code Standards

### Bash Style

We follow these standards:

**1. Options**
```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
```

**2. Variables**
- Use `readonly` for constants: `readonly CONSTANT="value"`
- Use `local` for function variables: `local variable="value"`
- Quote all variables: `"$variable"` not `$variable`

**3. Functions**
- Prefix functions with module name: `grub_validate_config`
- Prefix internal functions with underscore: `_internal_function`
- Document complex functions

**4. Error Handling**
```bash
command || return 1
trap 'cleanup' EXIT INT TERM
if some_command; then
  success_handler
else
  error_handler
fi
```

### File Organization

Each module should:
- Have single responsibility
- Keep related functions together
- Be ~200-400 lines
- Include header comments

## Module Development

### Creating a New Module

1. Create `modules/newfeature.sh`
2. Source in `core/bootstrap.sh`
3. Implement `newfeature_*` functions
4. Add UI menu item to `ui/dashboard.sh`
5. Test with `--self-test`

## Testing

### Running Tests

```bash
# Syntax validation
bash -n devil
bash run.sh --self-test

# Diagnostics
bash run.sh --diagnose

# Simulation mode
bash run.sh --test
bash run.sh --dry-run

# Debug mode
DEVIL_DEBUG=1 bash run.sh --diagnose
```

### Testing Checklist

- [ ] Code follows bash style guide
- [ ] All functions have documentation
- [ ] No unquoted variables
- [ ] Proper error handling
- [ ] No hardcoded paths
- [ ] Works in simulation modes
- [ ] Backups created before changes
- [ ] Changes properly logged
- [ ] Read-only operations verified
- [ ] Works with minimal dependencies

## Quality Assurance

### ShellCheck

```bash
shellcheck devil run.sh core/*.sh modules/*.sh ui/*.sh
```

### Common Issues

1. **Unquoted Variables**
   ```bash
   # BAD: grep $pattern $file
   # GOOD: grep "$pattern" "$file"
   ```

2. **Missing Error Handling**
   ```bash
   # BAD: config=$(find /boot -name "grub.cfg")
   # GOOD: config=$(find /boot -name "grub.cfg") || return 1
   ```

3. **Hardcoded Paths**
   ```bash
   # BAD: cp /boot/grub.cfg /tmp/backup
   # GOOD: cp "$grub_cfg" "$DEVIL_BACKUP_DIR/"
   ```

## Submitting Changes

### Commit Message Format

```
Module: Brief description

Detailed explanation of changes and rationale.
Include issue references if applicable.

Fixes: #123
```

### Pull Request Checklist

- [ ] Tests pass: `bash run.sh --self-test`
- [ ] Syntax valid: `bash -n <files>`
- [ ] Documented changes
- [ ] No new warnings from ShellCheck
- [ ] Works in simulation mode
- [ ] Tested on multiple distributions if applicable

## Documentation

Update relevant documentation for:
- New features (add to README.md)
- Architecture changes (update ARCHITECTURE.md)
- New modules (document in RECOVERY-FLOW.md)
- Examples (add to README.md examples)

## Distribution Support

Test on:
- Arch/Arch-based (Garuda, Manjaro, EndeavourOS)
- Debian-based (Ubuntu, Mint)
- Fedora/RHEL
- openSUSE

Document distribution-specific behavior.

## Performance

- Avoid unnecessary process spawning
- Use bash built-ins when possible
- Minimize file I/O
- Don't fork processes in loops

## Security

All contributions must:
- Handle input safely
- Avoid shell injection
- Quote variables properly
- Use safe file operations
- Respect permissions
- Log security-relevant actions

## Questions?

- Open an issue for discussion
- Review existing code for patterns
- Check `docs/ARCHITECTURE.md`
- Read module examples

Thank you for contributing to DEVIL!
