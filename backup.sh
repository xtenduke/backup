#!/bin/bash
set -euo pipefail

read -rp "Enter server address (e.g. 192.168.1.1): " SERVER
read -rp "Enter backup path (e.g. disk/backuppath/backupname): " SHARE
read -rp "Enter SMB username: " USERNAME
read -rsp "Enter SMB password: " PASSWORD
echo
read -rp "Enter disk to back up (e.g. /dev/nvme0n1): " DISK

MOUNTPOINT="/mnt/partclone_backup"
sudo mkdir -p "$MOUNTPOINT"

echo "Mounting //$SERVER/$SHARE to $MOUNTPOINT ..."
sudo mount -t cifs "//$SERVER/$SHARE" "$MOUNTPOINT" \
    -o username="$USERNAME",password="$PASSWORD",vers=3.0,iocharset=utf8

DATE=$(date +"%Y-%m-%d_%H-%M")
BACKUP_FILE="$MOUNTPOINT/linux-${DATE}.img.zst"

echo "Starting backup of $DISK to $BACKUP_FILE ..."
sudo partclone.dd -s "$DISK" -o - | zstd -T0 -19 -o "$BACKUP_FILE"

echo "Backup completed: $BACKUP_FILE"
sudo umount "$MOUNTPOINT"

