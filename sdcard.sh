#!/bin/bash
#
# sdcard.sh - Prepare an SD card for Emu68 (PiStorm32-Lite)
#
# Usage: sudo ./sdcard.sh /dev/sdX [kick.rom]
#
# - Creates an MBR with a 200MB FAT32 boot partition (bootable)
# - Creates a second partition (type 0x76) using the remaining space
# - Extracts the pistorm32-lite release zip onto the boot partition
# - If a kickstart ROM is provided, copies it and adds initramfs to config.txt
#
set -euo pipefail

BOOT_SIZE_MB=200

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "Usage: sudo $0 /dev/sdX [kick.rom]"

DEVICE="$1"
ROM="${2:-}"
RELEASE="$PWD/release/pistorm32-lite.zip"

[ "$(id -u)" = "0" ] || die "must be run as root"
for tool in sfdisk parted mkfs.vfat unzip mount; do
    command -v "$tool" >/dev/null || die "required tool not found: $tool"
done
[ -b "$DEVICE" ] || die "$DEVICE is not a block device"
[ -f "$RELEASE" ] || die "release archive not found: $RELEASE"

# refuse to wipe partitions
case "$DEVICE" in
  *p*) die "$DEVICE looks like a partition, expected a whole disk (e.g. /dev/sdX)";;
esac
grep -q " $DEVICE " /proc/mounts && die "$DEVICE is mounted, unmount it first"

SIZE=$(blockdev --getsize64 "$DEVICE")
echo "WARNING: this will DESTROY ALL DATA on $DEVICE ($((SIZE / 1024 / 1024)) MB)."
read -r -p "Type YES to continue: " ANSWER
[ "$ANSWER" = "YES" ] || die "aborted"

# partition layout: p1 = 200MB FAT32 (type 0x0C, bootable), p2 = rest (type 0x76)
printf 'label: dos\n2048, %s, 0C\n, , 76\n' "$((BOOT_SIZE_MB * 2048))" | sfdisk -f "$DEVICE"
parted -s "$DEVICE" set 1 boot on

# format boot partition
mkfs.vfat -F 32 "$DEVICE"1

# copy release contents
MNT=$(mktemp -d)
mount "$DEVICE"1 "$MNT"
trap 'umount "$MNT" 2>/dev/null; rmdir "$MNT"' EXIT
unzip -o "$RELEASE" -d "$MNT"
sync

# optional kickstart ROM
if [ -n "$ROM" ]; then
    [ -f "$ROM" ] || die "ROM not found: $ROM"
    cp "$ROM" "$MNT/kick.rom"
    grep -q '^initramfs kick.rom' "$MNT/config.txt" || echo "initramfs kick.rom" >> "$MNT/config.txt"
elif grep -qE '^[[:space:]]*initramfs[[:space:]]+[^,[:space:]]+\.rom' "$MNT/config.txt"; then
    echo "WARNING: config.txt requests an initramfs ROM but none was copied to the card; boot will fail. Re-run with: $0 $DEVICE /path/to/kickstart.rom"
fi

umount "$MNT"
rmdir "$MNT"
trap - EXIT

echo "Done. $DEVICE is ready for the PiStorm."
