#!/usr/bin/env bash
set -euxo pipefail
source core/common.sh
source modules/filesystems.sh
TMPBTRFS=$(mktemp -d)
cat >"$TMPBTRFS/btrfs" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "subvolume" && "$2" == "list" ]]; then
  printf "ID 256 gen 1 top level 5 path @\nID 257 gen 2 top level 5 path @home\n"
  exit 0
fi
exit 0
EOF
chmod +x "$TMPBTRFS/btrfs"
PATH="$TMPBTRFS:$PATH"
findmnt() {
  if [[ "$*" == "-rn -t btrfs -o SOURCE" ]]; then
    printf "/dev/sda2\n"
  elif [[ "$*" == "-rn -t btrfs -o TARGET" ]]; then
    printf "/mnt/btrfs\n"
  else
    command findmnt "$@"
  fi
}
filesystem_summary_output=$(filesystem_summary)
echo "---OUTPUT---"
echo "$filesystem_summary_output"
if printf '%s\n' "$filesystem_summary_output" | grep -q 'Subvolumes/snapshots visible: 2'; then
  echo GREP_EXIT=0
else
  echo GREP_EXIT=1
fi
rm -rf "$TMPBTRFS"
