#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$' \t\n'
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
for file in "$root"/devil "$root"/run.sh "$root"/{core,modules,ui}/*.sh; do bash -n "$file"; done
XDG_STATE_HOME="$(mktemp -d)" XDG_CONFIG_HOME="$(mktemp -d)" bash "$root/run.sh" --self-test
source "$root/core/common.sh"
source "$root/core/terminal.sh"
source "$root/modules/filesystems.sh"
source "$root/modules/efi.sh"
source "$root/modules/diagnostics.sh"
source "$root/modules/multiboot.sh"
source "$root/modules/grub.sh"
source "$root/modules/recovery.sh"
source "$root/ui/dashboard.sh"
if ! grep -Fq 'chroot "$target" sh -c '\''command -v grub-install'\''' "$root/modules/recovery.sh"; then
  echo 'Target grub-install chroot check regression failed'; exit 1
fi
if ! declare -F recovery_discover_linux_roots >/dev/null || ! grep -q 'Installed System Selector' "$root/ui/dashboard.sh"; then
  echo 'Installed Linux system selector regression failed'; exit 1
fi
if ! grep -Fq '"$box_inside" "$footer_text"' "$root/ui/dashboard.sh" || ! grep -q 'DEVIL_AUDIT_FILE' "$root/core/logging.sh" || ! grep -q 'full-recovery-report' "$root/core/logging.sh"; then
  echo 'Menu border or audit trail regression failed'; exit 1
fi
terminal_color_init
ui_help >/tmp/devil-help-smoke.log
DEVIL_ROOT="$root"
DEVIL_FORCE_COLOR=1
terminal_color_init
terminal_load_theme
if [[ "${DEVIL_THEME_NAME:-}" != 'Pitch Black' || -z "${THEME_COLOR_ACCENT:-}" ]]; then echo 'Theme loading regression failed'; exit 1; fi
grub_candidates=$(grub_reference_candidate_paths '/@/boot/vmlinuz-linux-zen' '/@')
if [[ "$grub_candidates" != *$'/boot/vmlinuz-linux-zen'* ]]; then echo 'Btrfs GRUB path resolution regression failed'; exit 1; fi
if grub_reference_token_is_path 'set root=(hd0,gpt1)'; then echo 'GRUB command-line parser regression failed'; exit 1; fi

TMPTARGETROOT="$(mktemp -d)"
mkdir -p "$TMPTARGETROOT/etc" "$TMPTARGETROOT/boot/grub"
printf '%s\n' 'PRETTY_NAME="Garuda Linux"' 'ID=garuda' >"$TMPTARGETROOT/etc/os-release"
: >"$TMPTARGETROOT/boot/vmlinuz-linux-zen"
: >"$TMPTARGETROOT/boot/initramfs-linux-zen.img"
cat >"$TMPTARGETROOT/boot/grub/grub.cfg" <<'EOF'
menuentry 'Garuda Linux' {
  linux /boot/vmlinuz-linux-zen root=UUID=test
  initrd /boot/initramfs-linux-zen.img
}
EOF
DEVIL_TARGET_ROOT="$TMPTARGETROOT"
DEVIL_TARGET_ROOT_SOURCE=explicit
if [[ "$(grub_config_path)" != "$TMPTARGETROOT/boot/grub/grub.cfg" ]]; then echo 'Mounted target GRUB path regression failed'; rm -rf "$TMPTARGETROOT"; exit 1; fi
target_grub_candidates=$(grub_reference_candidate_paths '/@/boot/vmlinuz-linux-zen' '/@')
if [[ "$target_grub_candidates" != *"$TMPTARGETROOT/boot/vmlinuz-linux-zen"* ]]; then echo 'Mounted target Btrfs GRUB path regression failed'; rm -rf "$TMPTARGETROOT"; exit 1; fi
target_grub_output=$(grub_validate)
if [[ "$target_grub_output" != *"Inspection target: $TMPTARGETROOT"* || "$target_grub_output" != *'VALID_REFERENCE [linux] /boot/vmlinuz-linux-zen'* ]]; then echo 'Mounted target GRUB validation regression failed'; rm -rf "$TMPTARGETROOT"; exit 1; fi
if [[ "$(diagnostics_check_initramfs)" != *'initramfs-linux-zen.img'* ]]; then echo 'Mounted target initramfs regression failed'; rm -rf "$TMPTARGETROOT"; exit 1; fi
rm -rf "$TMPTARGETROOT"
DEVIL_TARGET_ROOT=/
DEVIL_TARGET_ROOT_SOURCE=current

TMPMOUNTEDBTRFS="$(mktemp -d)"
mkdir -p "$TMPMOUNTEDBTRFS/@/etc" "$TMPMOUNTEDBTRFS/@/boot"
printf '%s\n' 'ID=garuda' >"$TMPMOUNTEDBTRFS/@/etc/os-release"
DEVIL_ENVIRONMENT_CLASS=LIVE_ISO
findmnt() {
  if [[ "$*" == '-rn -o TARGET,SOURCE,FSTYPE' ]]; then
    printf '%s /dev/nvme0n1p2 btrfs\n' "$TMPMOUNTEDBTRFS"
  elif [[ "$*" == "-n -o OPTIONS --target $TMPMOUNTEDBTRFS/@" ]]; then
    printf 'rw\n'
  elif [[ "$*" == "-n -o FSTYPE --target $TMPMOUNTEDBTRFS/@" ]]; then
    printf 'btrfs\n'
  elif [[ "$*" == "-n -o TARGET --target $TMPMOUNTEDBTRFS/@" ]]; then
    printf '%s\n' "$TMPMOUNTEDBTRFS"
  else
    command findmnt "$@"
  fi
}
devil_select_target_root
if [[ "$DEVIL_TARGET_ROOT_SOURCE" != auto || "$DEVIL_TARGET_ROOT" != "$TMPMOUNTEDBTRFS/@" ]]; then echo 'Mounted Btrfs target selection regression failed'; rm -rf "$TMPMOUNTEDBTRFS"; exit 1; fi
if [[ "$(grub_root_subvolume_path "$DEVIL_TARGET_ROOT")" != /@ ]]; then echo 'Mounted Btrfs subvolume regression failed'; rm -rf "$TMPMOUNTEDBTRFS"; exit 1; fi
unset -f findmnt
rm -rf "$TMPMOUNTEDBTRFS"
DEVIL_TARGET_ROOT=/
DEVIL_TARGET_ROOT_SOURCE=current
DEVIL_ENVIRONMENT_CLASS=UNKNOWN

sample_output=$(cat <<'EOF'
BootCurrent: 0008
Timeout: 0 seconds
BootOrder: 0008,0000,0001
Boot0000* Windows Boot Manager HD(1,GPT,...)/
Boot0008* Garuda HD(1,GPT,...)/
EOF
)
if [[ "$(efi_boot_target_from_output "$sample_output")" != "Garuda" ]]; then echo 'EFI boot-target parser regression failed'; exit 1; fi
sample_lsblk=$(cat <<'EOF'
/dev/sdb1 ntfs Jack Sparrow
/dev/sda5 btrfs
EOF
)
if ! printf '%s
' "$sample_lsblk" | devil_parse_lsblk_entries | grep -q $'\tntfs\tJack Sparrow'; then echo 'LSBLK parser regression failed'; exit 1; fi
TMPBIN="$(mktemp -d)"
cat >"$TMPBIN/efibootmgr" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$TMPBIN/strings" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMPBIN/efibootmgr" "$TMPBIN/strings"
PATH="$TMPBIN:$PATH"
unset MULTIBOOT_SYSTEMS MULTIBOOT_ORDER 2>/dev/null || true
declare -gA MULTIBOOT_SYSTEMS=()
declare -ga MULTIBOOT_ORDER=()
multiboot_probe_windows "/dev/fake" "NoEvidence"
if [[ "${MULTIBOOT_SYSTEMS["/dev/fake"]}" != "NTFS_DATA on NoEvidence" ]]; then echo 'Windows/NTFS classification regression failed'; rm -rf "$TMPBIN"; exit 1; fi
rm -rf "$TMPBIN"

# A Windows EFI entry is global evidence only: it must not promote unrelated
# NTFS filesystems to Windows installations.
TMPWIN="$(mktemp -d)"
cat >"$TMPWIN/efibootmgr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'Boot0001* Windows Boot Manager HD(1,GPT,...)'
EOF
cat >"$TMPWIN/ntfsls" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMPWIN/efibootmgr" "$TMPWIN/ntfsls"
PATH="$TMPWIN:$PATH"
MULTIBOOT_WINDOWS_BOOT_MANAGER=0
unset MULTIBOOT_SYSTEMS MULTIBOOT_ORDER 2>/dev/null || true
declare -gA MULTIBOOT_SYSTEMS=()
declare -ga MULTIBOOT_ORDER=()
for dev in /dev/fake-ntfs-a /dev/fake-ntfs-b /dev/fake-ntfs-c /dev/fake-ntfs-d; do
  multiboot_probe_windows "$dev" "NoEvidence"
done
multiboot_windows_boot_manager_present >/dev/null && MULTIBOOT_WINDOWS_BOOT_MANAGER=1
if [[ "$(multiboot_print_windows_boot_manager | grep -c '^WINDOWS_BOOT_MANAGER:')" -ne 1 ]]; then echo 'Windows EFI classification regression failed'; rm -rf "$TMPWIN"; exit 1; fi
if printf '%s\n' "${MULTIBOOT_SYSTEMS[@]}" | grep -q 'CONFIRMED_WINDOWS_INSTALLATION'; then echo 'Windows EFI false-positive regression failed'; rm -rf "$TMPWIN"; exit 1; fi
if [[ "$(printf '%s\n' "${MULTIBOOT_SYSTEMS[@]}" | grep -c '^NTFS_DATA on NoEvidence$')" -ne 4 ]]; then echo 'NTFS data classification regression failed'; rm -rf "$TMPWIN"; exit 1; fi
rm -rf "$TMPWIN"

# Add broader regression coverage for Btrfs counting, EFI entries, and environment classification.
TMPDEBUG="$(mktemp -d)"
OLDPATH="$PATH"

cat >"$TMPDEBUG/efibootmgr" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
BootCurrent: 0002
BootOrder: 0002,0001
Boot0001 Fedora
Boot0002* Garuda
OUT
EOF
chmod +x "$TMPDEBUG/efibootmgr"
PATH="$TMPDEBUG:$PATH"
if [[ "$(efi_list_entries)" != $'Boot0001\nBoot0002' ]]; then echo 'EFI entry parsing regression failed'; rm -rf "$TMPDEBUG"; exit 1; fi
rm -rf "$TMPDEBUG"
PATH="$OLDPATH"

TMPBTRFS="$(mktemp -d)"
cat >"$TMPBTRFS/btrfs" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "subvolume" && "$2" == "list" ]]; then
  printf 'ID 256 gen 1 top level 5 path @\nID 257 gen 2 top level 5 path @home\n'
  exit 0
fi
exit 0
EOF
chmod +x "$TMPBTRFS/btrfs"
PATH="$TMPBTRFS:$PATH"
findmnt() {
  if [[ "$*" == "-rn -t btrfs -o SOURCE" ]]; then
    printf '/dev/sda2\n'
  elif [[ "$*" == "-rn -t btrfs -o TARGET" ]]; then
    printf '/mnt/btrfs\n'
  else
    command findmnt "$@"
  fi
}
filesystem_output=$(filesystem_summary)
if [[ "$filesystem_output" != *'Subvolumes/snapshots visible: 2'* ]]; then echo 'Btrfs subvolume counting regression failed'; rm -rf "$TMPBTRFS"; exit 1; fi
rm -rf "$TMPBTRFS"
PATH="$OLDPATH"

TMPBTRFS_EMPTY="$(mktemp -d)"
cat >"$TMPBTRFS_EMPTY/btrfs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMPBTRFS_EMPTY/btrfs"
PATH="$TMPBTRFS_EMPTY:$PATH"
lsblk() {
  if [[ "$*" == "-nrpo PATH,FSTYPE" ]]; then
    return 0
  fi
  command lsblk "$@"
}
findmnt() {
  if [[ "$*" == "-rn -t btrfs -o SOURCE" || "$*" == "-rn -t btrfs -o TARGET" ]]; then
    return 0
  fi
  command findmnt "$@"
}
filesystem_output=$(filesystem_summary)
if [[ "$filesystem_output" != *'Btrfs filesystems: none'* ]]; then echo 'Empty Btrfs discovery regression failed'; rm -rf "$TMPBTRFS_EMPTY"; exit 1; fi
rm -rf "$TMPBTRFS_EMPTY"
unset -f lsblk
PATH="$OLDPATH"

TMPLOADER="$(mktemp -d)"
mkdir -p "$TMPLOADER/boot/efi/EFI/Ubuntu"
printf '%s\n' 'ID=ubuntu' >"$TMPLOADER/etc-os-release"
mkdir -p "$TMPLOADER/etc"
mv "$TMPLOADER/etc-os-release" "$TMPLOADER/etc/os-release"
if [[ "$(recovery_loader_id "$TMPLOADER")" != Ubuntu ]]; then echo 'Target EFI loader ID regression failed'; rm -rf "$TMPLOADER"; exit 1; fi
rm -rf "$TMPLOADER"

# Environment classification regression for installed, live ISO, and CHROOT.
findmnt() {
  printf '/dev/sda5[/@]\n'
}
stat() {
  # Mock stat to return a followed target for / and /proc/1/root.
  if [[ "$1" == "-Lc" && "$2" == "%d:%i" && "$3" == "/" ]]; then
    printf '100:1'
  elif [[ "$1" == "-Lc" && "$2" == "%d:%i" && "$3" == "/proc/1/root" ]]; then
    printf '100:1'
  else
    command stat "$@"
  fi
}
if [[ "$(devil_classify_environment)" != "INSTALLED_SYSTEM" ]]; then echo 'Installed environment classification regression failed'; exit 1; fi
findmnt() { printf '/dev/loop0\n'; }
if [[ "$(devil_classify_environment)" != "LIVE_ISO" ]]; then echo 'Live environment classification regression failed'; exit 1; fi
findmnt() { printf '/dev/sda5[/@]\n'; }
stat() {
  if [[ "$1" == "-Lc" && "$2" == "%d:%i" && "$3" == "/" ]]; then
    printf '100:1'
  elif [[ "$1" == "-Lc" && "$2" == "%d:%i" && "$3" == "/proc/1/root" ]]; then
    printf '200:1'
  else
    command stat "$@"
  fi
}
if [[ "$(devil_classify_environment)" != "CHROOT" ]]; then echo 'Environment classification regression failed'; exit 1; fi

# A GRUB restore must reject traversal and must not write in simulation mode.
TMPRESTORE="$(mktemp -d)"
DEVIL_BACKUP_DIR="$TMPRESTORE/backups"
mkdir -p "$DEVIL_BACKUP_DIR"
restore_target="$TMPRESTORE/grub.cfg"
printf 'current configuration\n' >"$restore_target"
printf 'backup configuration\n' >"$DEVIL_BACKUP_DIR/grub-safe"
printf 'outside configuration\n' >"$TMPRESTORE/outside"
log_info() { :; }
log_error() { :; }
log_action() { :; }
if recovery_validate_backup "$TMPRESTORE/outside"; then echo 'GRUB backup traversal regression failed'; rm -rf "$TMPRESTORE"; exit 1; fi
require_root() { :; }
confirm() { return 0; }
grub_config_path() { printf '%s' "$restore_target"; }
DEVIL_TEST=1
DEVIL_DRY_RUN=0
DEVIL_SAFE=0
DEVIL_ACTIONS=()
recovery_rollback_grub "$DEVIL_BACKUP_DIR/grub-safe" >/tmp/devil-restore-smoke.log
if [[ "$(<"$restore_target")" != 'current configuration' ]]; then echo 'Simulated GRUB rollback modified configuration regression failed'; rm -rf "$TMPRESTORE"; exit 1; fi
if ! grep -Eq 'SIMULATED:.*restore GRUB configuration' /tmp/devil-restore-smoke.log; then echo 'Simulated GRUB rollback did not use action guard regression failed'; rm -rf "$TMPRESTORE"; exit 1; fi
rm -rf "$TMPRESTORE"

# Selecting a privileged advanced-recovery action without root must return to
# the submenu instead of terminating DEVIL.
if ! printf '2\n\n' | recovery_advanced_grub >/tmp/devil-advanced-menu-smoke.log; then echo 'Advanced recovery non-root handling regression failed'; exit 1; fi
if ! grep -q 'Root privileges are required to: Regenerate GRUB configuration' /tmp/devil-advanced-menu-smoke.log; then echo 'Advanced recovery root warning regression failed'; exit 1; fi

XDG_STATE_HOME="$(mktemp -d)" XDG_CONFIG_HOME="$(mktemp -d)" bash "$root/run.sh" --ui >/tmp/devil-ui-smoke.log 2>&1 || { cat /tmp/devil-ui-smoke.log; exit 1; }
echo 'Smoke tests passed.'
