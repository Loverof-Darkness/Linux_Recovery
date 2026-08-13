# Recovery flow

1. Boot a compatible Live ISO, mount the installed Linux root (and any separate `/boot` or ESP beneath it), then run `bash run.sh --target-root /mnt --diagnose`.
2. Review the selected target, candidate installations, boot mounts, EFI state and GRUB validation. If one mounted Linux root is visible, DEVIL selects it automatically; otherwise supply `--target-root PATH`.
3. Save a report with `--report`.
4. Use `--dry-run` to review a planned GRUB regeneration.
5. Confirm the operation only after DEVIL creates a timestamped backup.
6. For a missing GRUB configuration, use the guided reinstall: DEVIL probes the Linux root and EFI partition, displays both, then mounts and runs `grub-install`/`grub-mkconfig` in a chroot.
7. If needed, restore a backup using `recovery_rollback` from a reviewed shell session.

DEVIL deliberately does not write Windows BCD. Mounted targets are diagnostic-only: GRUB installation is available only through the explicit, reviewed live-ISO workflow, and ambiguous or locked storage is refused.
