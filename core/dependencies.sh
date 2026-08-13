#!/usr/bin/env bash
# Dependency inspection is advisory: live environments legitimately omit tools.
declare -a DEVIL_REQUIRED_COMMANDS=(bash awk sed grep findmnt lsblk)
declare -a DEVIL_OPTIONAL_COMMANDS=(mount umount chroot blkid efibootmgr grub-install grub-mkconfig grub2-mkconfig mokutil cryptsetup lvs pvs vgs btrfs mdadm os-prober gzip tar chafa viu img2txt kitty)

dependencies_missing_required() {
  local command missing=()
  for command in "${DEVIL_REQUIRED_COMMANDS[@]}"; do have "$command" || missing+=("$command"); done
  printf '%s\n' "${missing[@]}"
}

dependencies_verify() {
  local missing; missing=$(dependencies_missing_required)
  [[ -z "$missing" ]] || die "missing required command(s): ${missing//$'\n'/, }"
}

dependencies_report() {
  local command state
  for command in "${DEVIL_REQUIRED_COMMANDS[@]}" "${DEVIL_OPTIONAL_COMMANDS[@]}"; do
    state=missing; have "$command" && state=available
    printf '%-18s %s\n' "$command" "$state"
  done
}
