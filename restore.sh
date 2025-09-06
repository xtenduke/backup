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

sudo umount "$MOUNTPOINT"

## The following is all untested bs
## Just trying to repair fstab, rebuild initramfs, and grub because the uuids have probably changed

echo "Attempting to unlock restored disk ..."
LUKS_PART=$(lsblk -lnpo NAME,FSTYPE "$DISK" | awk '$2=="crypto_LUKS"{print $1; exit}')
if [ -n "$LUKS_PART" ]; then
    sudo cryptsetup luksOpen "$LUKS_PART" cryptroot
    sudo vgscan
    sudo vgchange -ay

    ROOT_LV=$(lsblk -lnpo NAME,FSTYPE | awk '$2=="btrfs"{print $1; exit}')
    if [ -n "$ROOT_LV" ]; then
        sudo mkdir -p /mnt/restored
        sudo mount -o subvolid=5 "$ROOT_LV" /mnt/restored
        SUBVOL=$(btrfs subvolume list /mnt/restored | awk '/ path @($|\/)/{print $9; exit}')
        [ -z "$SUBVOL" ] && SUBVOL=$(btrfs subvolume list /mnt/restored | awk 'NR==1{print $9}')
        sudo umount /mnt/restored
        sudo mount -o subvol="$SUBVOL" "$ROOT_LV" /mnt/restored
        echo "Restored system mounted at /mnt/restored"
        echo "Next steps: bind-mount /dev,/proc,/sys,/run and chroot to regenerate fstab/initramfs/grub"
    else
        echo "No Btrfs LV found after restore."
    fi
else
    echo "No LUKS partition detected — restore may be plain ext4/Btrfs."
fi
