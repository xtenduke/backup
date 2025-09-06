#!/bin/bash
set -euo pipefail

read -rp "Enter server address (e.g. fileserver.local): " SERVER
read -rp "Enter share name (e.g. array/backups/kiowa-partclone): " SHARE
read -rp "Enter username: " USERNAME
read -rsp "Enter password: " PASSWORD
echo
read -rp "Enter disk to restore to (e.g. /dev/nvme0n1): " DISK

MOUNTPOINT="/mnt/partclone_recover"
sudo mkdir -p "$MOUNTPOINT"

echo "Mounting //$SERVER/$SHARE to $MOUNTPOINT ..."
sudo mount -t cifs "//$SERVER/$SHARE" "$MOUNTPOINT" \
    -o username="$USERNAME",password="$PASSWORD",vers=3.0,iocharset=utf8

echo "Available backup files:"
FILES=("$MOUNTPOINT"/*)
for i in "${!FILES[@]}"; do
    echo "$i) $(basename "${FILES[$i]}")"
done

while true; do
    read -rp "Enter the number of the backup to restore: " SEL
    if [[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL >= 0 && SEL < ${#FILES[@]} )); then
        BACKUP_PATH="${FILES[$SEL]}"
        echo "Selected: $BACKUP_PATH"
        break
    else
        echo "Invalid selection. Try again."
    fi
done

echo "Restoring $BACKUP_PATH to $DISK"
read -rp "Are you sure? ALL DATA ON $DISK WILL BE LOST! (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Restore cancelled."
    sudo umount "$MOUNTPOINT"
    exit 1
fi

echo "Starting restore..."
zstd -d < "$BACKUP_PATH" | sudo partclone.dd -s - -o "$DISK"

## The following is all untested bs
## Just trying to repair fstab, rebuild initramfs, and grub because the uuids have probably changed

PART_ROOT=$(lsblk -lnpo NAME "$DISK" | tail -n1)
sudo mount "$PART_ROOT" /mnt

for dir in /dev /proc /sys /run; do sudo mount --bind $dir /mnt$dir; done
sudo chroot /mnt bash -c '
> /etc/fstab
for part in $(lsblk -lnpo NAME,UUID,FSTYPE,MOUNTPOINT | grep -E "ext4|btrfs|xfs"); do
    dev=$(echo $part | awk "{print \$1}")
    uuid=$(echo $part | awk "{print \$2}")
    fstype=$(echo $part | awk "{print \$3}")
    mountpoint=$(echo $part | awk "{print \$4}")
    [ -n "$mountpoint" ] && echo "UUID=$uuid $mountpoint $fstype defaults 0 1" >> /etc/fstab
done
mount -a || true
dracut --force
if [ -d /sys/firmware/efi ]; then
    grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
else
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi
'
for dir in /dev /proc /sys /run; do sudo umount /mnt$dir; done
sudo umount /mnt
sudo umount "$MOUNTPOINT"

echo "Done."

