#!/bin/bash

# --- Variable settings (edit the UUID to match your environment) ---
LUKS_PART_UUID="7bab175e-9512-4d8a-85be-b1bdba07d51a"
KEY_DEV_UUID="ad38ac5-db02-48aa-912a-bbfdb5b95ecf"
MAPPER_NAME="home_crypt"
MOUNT_POINT="/home"
# --- Variable settings up to here ---

LUKS_DEVICE="/dev/disk/by-uuid/$LUKS_PART_UUID"
KEY_DEVICE="/dev/disk/by-uuid/$KEY_DEV_UUID"
MAPPER_DEVICE="/dev/mapper/$MAPPER_NAME"

# If already mounted/unlocked, exit
if mountpoint -q "$MOUNT_POINT" || [ -b "$MAPPER_DEVICE" ]; then
    exit 0
fi

# If there is a SD card, use its key file to unlock the luks drive.
if [ -b "$KEY_DEVICE" ]; then
    KEY_MOUNT_POINT=$(mktemp -d)
    mount "$KEY_DEVICE" "$KEY_MOUNT_POINT"
    
    if [ -f "$KEY_MOUNT_POINT/home.key" ]; then
        cryptsetup open "$LUKS_DEVICE" "$MAPPER_NAME" --key-file "$KEY_MOUNT_POINT/home.key"
    fi
    
    umount "$KEY_MOUNT_POINT"
    rmdir "$KEY_MOUNT_POINT"
fi

# If not already unlocked, prompt for passphrase
if [ ! -b "$MAPPER_DEVICE" ]; then
    # Suppress the bootsplash which  gets in the way of the prompt
    [ -x /usr/bin/plymouth ] && /usr/bin/plymouth quit
    
    # Show passphrase prompt
    systemd-tty-ask-password-agent --watch -- "Please enter passphrase for encrypted /home:" \
    cryptsetup open "$LUKS_DEVICE" "$MAPPER_NAME"
fi

# If unlocked successfully, mount it
if [ -b "$MAPPER_DEVICE" ]; then
    mount "$MAPPER_DEVICE" "$MOUNT_POINT"
else
    exit 1
fi

exit 0

