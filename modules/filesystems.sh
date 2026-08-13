#!/usr/bin/env bash
# Storage discovery; no mounting, formatting, or repairs occur here.

filesystem_summary() {
  local luks lvm raid btrfs filesystem_count mounted_count
  local color_reset=${C_RESET:-}
  local color_white=${C_WHITE:-}
  local color_green=${C_GREEN:-}
  local color_gray=${C_GRAY:-}
  local color_red=${C_RED:-}
  local color_orange=${C_ORANGE:-}
  
  printf '%sFilesystem Summary%s\n' "$color_white" "$color_reset"
  printf '==================\n'
  
  # LUKS volumes
  if have cryptsetup; then
    luks=$(cryptsetup status 2>/dev/null | grep -c '^/' || echo 0)
    luks=${luks:-0}
    luks=${luks//[!0-9]/}
    [[ "$luks" =~ ^[0-9]+$ ]] || luks=0
    if ((luks > 0)); then
      printf '%s✓%s LUKS mappings: %d%s\n' "$color_green" "$color_reset" "$luks" ""
    else
      printf '%s○%s LUKS mappings: none%s\n' "$color_gray" "$color_reset" ""
    fi
  else
    printf '%s✗%s LUKS: cryptsetup not installed%s\n' "$color_red" "$color_reset" ""
  fi
  
  # LVM volumes
  if have lvs; then
    lvm=$(lvs --noheadings 2>/dev/null | grep -c . || echo 0)
    lvm=${lvm:-0}
    lvm=${lvm//[!0-9]/}
    [[ "$lvm" =~ ^[0-9]+$ ]] || lvm=0
    if ((lvm > 0)); then
      printf '%s✓%s LVM logical volumes: %d%s\n' "$color_green" "$color_reset" "$lvm" ""
    else
      printf '%s○%s LVM logical volumes: none%s\n' "$color_gray" "$color_reset" ""
    fi
  else
    printf '%s✗%s LVM: tools not installed%s\n' "$color_red" "$color_reset" ""
  fi
  
  # RAID arrays
  if [[ -f /proc/mdstat ]]; then
    raid=$(grep -c '^md[0-9]' /proc/mdstat 2>/dev/null || echo 0)
    raid=${raid:-0}
    raid=${raid//[!0-9]/}
    [[ "$raid" =~ ^[0-9]+$ ]] || raid=0
    if ((raid > 0)); then
      printf '%s✓%s RAID arrays: %d%s\n' "$color_green" "$color_reset" "$raid" ""
    else
      printf '%s○%s RAID arrays: none%s\n' "$color_gray" "$color_reset" ""
    fi
  fi
  
  # Btrfs volumes
  if have btrfs; then
    local btrfs_devices btrfs_targets subvolume_count
    local -a btrfs_devices=() btrfs_targets=()
    mapfile -t btrfs_devices < <(findmnt -rn -t btrfs -o SOURCE 2>/dev/null | sort -u)
    mapfile -t btrfs_targets < <(findmnt -rn -t btrfs -o TARGET 2>/dev/null)
    if ((${#btrfs_devices[@]} == 0)); then
      mapfile -t btrfs_devices < <(lsblk -nrpo PATH,FSTYPE 2>/dev/null | awk '$2 == "btrfs" { print $1 }' | sort -u)
    fi
    btrfs=${#btrfs_devices[@]}

    if ((btrfs > 0)); then
      subvolume_count=0
      local -A seen_btrfs=()
      local source target idx
      for idx in "${!btrfs_devices[@]}"; do
        source=${btrfs_devices[$idx]}
        target=${btrfs_targets[$idx]:-}
        [[ -n "$source" && -n "$target" ]] || continue
        [[ -n "${seen_btrfs[$source]:-}" ]] && continue
        seen_btrfs[$source]=1
        if btrfs subvolume list "$target" >/dev/null 2>&1; then
          subvolume_count=$((subvolume_count + $(btrfs subvolume list "$target" 2>/dev/null | wc -l)))
        fi
      done

      printf '%s✓%s Btrfs filesystems: %d%s\n' "$color_green" "$color_reset" "$btrfs" ""
      if [[ $subvolume_count -gt 0 ]]; then
        printf '  Subvolumes/snapshots visible: %s\n' "$subvolume_count"
      fi
    else
      printf '%s○%s Btrfs filesystems: none%s\n' "$color_gray" "$color_reset" ""
    fi
  fi

  filesystem_count=$(lsblk -rn -o FSTYPE 2>/dev/null | awk 'NF { count++ } END { print count + 0 }')
  mounted_count=$(findmnt -rn -o TARGET 2>/dev/null | awk 'NF { count++ } END { print count + 0 }')
  printf '\n%sStorage overview%s\n' "$color_white" "$color_reset"
  printf '  Detected filesystem devices: %s\n' "$filesystem_count"
  printf '  Active mount points:          %s\n' "$mounted_count"
  if ((filesystem_count == 0)); then
    printf '%s○%s No block-device filesystems were detected. This can be normal in a container or restricted live environment.\n' "$color_gray" "$color_reset"
  fi
  
  printf '\n'
}

filesystem_validate_target() {
  local target=$1
  [[ -b "$target" ]] || { log_error "not a block device: $target"; return 1; }
  lsblk -no FSTYPE "$target" | grep -q . || { log_warn "$target has no detected filesystem"; return 1; }
}

filesystem_get_type() {
  local device=$1
  lsblk -rn -o FSTYPE "$device" 2>/dev/null | head -1
}

filesystem_get_label() {
  local device=$1
  lsblk -rn -o LABEL "$device" 2>/dev/null | head -1
}

filesystem_get_uuid() {
  local device=$1
  lsblk -rn -o UUID "$device" 2>/dev/null | head -1
}

filesystem_get_size() {
  local device=$1
  lsblk -rn -o SIZE "$device" 2>/dev/null | head -1
}

filesystem_is_mounted() {
  local device=$1
  findmnt -rn -o SOURCE "$device" >/dev/null 2>&1
}

filesystem_get_mount_point() {
  local device=$1
  findmnt -rn -o TARGET "$device" 2>/dev/null | head -1
}

filesystem_lsblk_value() {
  # lsblk --pairs keeps empty columns explicit (for example FSTYPE=""), unlike
  # whitespace-separated output where an empty type shifts the remaining data.
  local row=$1 field=$2 value
  value=${row#*"${field}=\""}
  value=${value%%\"*}
  printf '%s' "$value"
}

filesystem_detect_all() {
  local row path fstype size label count=0
  printf '%sDetected Filesystems%s\n' "$C_WHITE" "$C_RESET"
  printf '====================\n'

  while IFS= read -r row; do
    path=$(filesystem_lsblk_value "$row" PATH)
    fstype=$(filesystem_lsblk_value "$row" FSTYPE)
    size=$(filesystem_lsblk_value "$row" SIZE)
    label=$(filesystem_lsblk_value "$row" LABEL)
    [[ -n "$path" && -n "$fstype" ]] || continue
    printf '%s•%s %s%s%s (%s, %s)%s\n' "$C_CYAN" "$C_RESET" "$C_GREEN" "$path" "$C_RESET" "$fstype" "$size" "${label:+ - $label}"
    ((count += 1))
  done < <(lsblk -P -o PATH,FSTYPE,SIZE,LABEL 2>/dev/null)

  if ((count == 0)); then
    printf '%s○%s No filesystems detected by lsblk. This can be normal in a container or restricted live environment.\n' "$C_GRAY" "$C_RESET"
  fi
}

filesystem_list_ext4() {
  local row path fstype size label count=0
  printf '%sExt4 Filesystems%s\n' "$C_WHITE" "$C_RESET"
  printf '================\n'
  while IFS= read -r row; do
    path=$(filesystem_lsblk_value "$row" PATH)
    fstype=$(filesystem_lsblk_value "$row" FSTYPE)
    size=$(filesystem_lsblk_value "$row" SIZE)
    label=$(filesystem_lsblk_value "$row" LABEL)
    [[ "$fstype" == ext4 ]] || continue
    printf '%s•%s %s%s%s (%s)%s\n' "$C_GREEN" "$C_RESET" "$C_CYAN" "$path" "$C_RESET" "$size" "${label:+ - $label}"
    ((count += 1))
  done < <(lsblk -P -o PATH,FSTYPE,SIZE,LABEL 2>/dev/null)
  ((count > 0)) || printf '%s○%s No Ext4 filesystems detected.\n' "$C_GRAY" "$C_RESET"
}

filesystem_list_btrfs() {
  local target source uuid count=0
  printf '%sBtrfs Filesystems%s\n' "$C_WHITE" "$C_RESET"
  printf '=================\n'
  
  if ! have btrfs; then
    printf '  (btrfs-tools not installed)\n'
    return 1
  fi
  
  while read -r target source uuid; do
    [[ -n "$target" && -n "$source" ]] || continue
    printf '%s•%s %s%s%s at %s\n' "$C_PURPLE" "$C_RESET" "$C_CYAN" "$source" "$C_RESET" "$target"
    ((count += 1))
  done < <(findmnt -rn -t btrfs -o TARGET,SOURCE,UUID 2>/dev/null)
  ((count > 0)) || printf '%s○%s No mounted Btrfs filesystems detected.\n' "$C_GRAY" "$C_RESET"
}

filesystem_list_xfs() {
  printf '%sXFS Filesystems%s\n' "$C_WHITE" "$C_RESET"
  printf '===============\n'
  lsblk -rn -o PATH,FSTYPE,SIZE,LABEL 2>/dev/null | grep xfs | while read -r path fstype size label; do
    printf '  %s (%s)%s\n' "$path" "$size" "${label:+ - $label}"
  done
}

filesystem_list_luks() {
  printf '%sLUKS Encrypted Volumes%s\n' "$C_WHITE" "$C_RESET"
  printf '====================\n'
  
  if ! have cryptsetup; then
    printf '  (cryptsetup not installed)\n'
    return 1
  fi
  
  cryptsetup status 2>/dev/null | grep '^/' | while read -r line; do
    printf '  %s\n' "$line"
  done
}

filesystem_list_lvm() {
  printf '%sLVM Logical Volumes%s\n' "$C_WHITE" "$C_RESET"
  printf '==================\n'
  
  if ! have lvs; then
    printf '  (LVM tools not installed)\n'
    return 1
  fi
  
  lvs --noheadings 2>/dev/null | while read -r vg lv size; do
    printf '  %s/%s (%s)\n' "$vg" "$lv" "$size"
  done
}

filesystem_list_raid() {
  printf '%sRAID Arrays%s\n' "$C_WHITE" "$C_RESET"
  printf '===========\n'
  
  if [[ ! -f /proc/mdstat ]]; then
    printf '  (MD RAID not detected)\n'
    return 1
  fi
  
  grep '^md' /proc/mdstat | while read -r line; do
    printf '  %s\n' "$line"
  done
}

filesystem_get_mount_info() {
  local target source fstype count=0
  printf '%sMount Information%s\n' "$C_WHITE" "$C_RESET"
  printf '=================\n'

  printf '%s%-28s %-28s %s%s\n' "$C_PURPLE" 'MOUNT POINT' 'SOURCE' 'TYPE' "$C_RESET"
  while read -r target source fstype; do
    [[ -n "$target" && -n "$source" ]] || continue
    printf '%s%-28s%s %s%-28s%s %s%s%s\n' "$C_CYAN" "$target" "$C_RESET" "$C_GREEN" "$source" "$C_RESET" "$C_ORANGE" "$fstype" "$C_RESET"
    ((count += 1))
    ((count >= 20)) && break
  done < <(findmnt -rn -o TARGET,SOURCE,FSTYPE 2>/dev/null)
  if ((count == 0)); then
    printf '%s○%s No mount information is available in this environment.\n' "$C_GRAY" "$C_RESET"
  fi
}

filesystem_check_disk_space() {
  printf '%sDisk Space Usage%s\n' "$C_WHITE" "$C_RESET"
  printf '===============\n'
  
  df -h | head -10 | tail -n +2 | while read -r device size used avail percent mount; do
    local percent_num=${percent%%%}
    if [[ "$percent_num" =~ ^[0-9]+$ ]] || [[ "$percent_num" =~ ^[0-9]+\.[0-9]+$ ]]; then
      if (( percent_num > 90 )); then
        printf '%s✗%s %s %s/%s (%s) at %s%s\n' "$C_RED" "$C_RESET" "$device" "$used" "$size" "$percent" "$mount" ""
      elif (( percent_num > 70 )); then
        printf '%s⚠%s %s %s/%s (%s) at %s%s\n' "$C_ORANGE" "$C_RESET" "$device" "$used" "$size" "$percent" "$mount" ""
      else
        printf '%s✓%s %s %s/%s (%s) at %s%s\n' "$C_GREEN" "$C_RESET" "$device" "$used" "$size" "$percent" "$mount" ""
      fi
    else
      printf '%s○%s %s %s/%s (%s) at %s%s\n' "$C_GRAY" "$C_RESET" "$device" "$used" "$size" "$percent" "$mount" ""
    fi
  done
}

filesystem_validate_all() {
  printf '%sFilesystem Validation%s\n' "$C_WHITE" "$C_RESET"
  printf '====================\n'
  
  local all_valid=1
  
  # Check ext4
  lsblk -rn -o PATH,FSTYPE 2>/dev/null | grep ext4 | while read -r device fstype; do
    if have fsck.ext4; then
      if fsck.ext4 -n "$device" >/dev/null 2>&1; then
        printf '%s✓%s %s: valid%s\n' "$C_GREEN" "$C_RESET" "$device" ""
      else
        printf '%s✗%s %s: errors detected%s\n' "$C_RED" "$C_RESET" "$device" ""
        all_valid=0
      fi
    fi
  done
  
  return $((1 - all_valid))
}
