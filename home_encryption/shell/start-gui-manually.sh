#!/bin/bash

# --- Variables (edit the UUID to match your environment) ---
LUKS_PART_UUID="7bab175e-9512-4d8a-85be-b1bdba07d51a"
MAPPER_NAME="home_crypt"
MOUNT_POINT="/home"
# --- End of variables ---

# Color definitions
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
NC='\e[0m' # No Color

MAPPER_DEVICE="/dev/mapper/$MAPPER_NAME"
LUKS_DEVICE="/dev/disk/by-uuid/$LUKS_PART_UUID"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root.${NC}"
    exit 1
fi

# Check if /home is already mounted
if mountpoint -q "$MOUNT_POINT"; then
    echo -e "${YELLOW}/home is already mounted.${NC}"
    echo "Starting GUI..."
    systemctl isolate graphical.target
    exit 0
fi

echo "Starting decryption of the /home partition."

# Open the LUKS container (will prompt for passphrase)
if ! cryptsetup open "$LUKS_DEVICE" "$MAPPER_NAME"; then
    echo -e "${RED}Error: Decryption failed. The passphrase may be incorrect.${NC}"
    exit 1
fi

echo -e "${GREEN}Decryption successful.${NC}"
echo "Mounting /home..."

# Mount the unlocked device to /home
if ! mount "$MAPPER_DEVICE" "$MOUNT_POINT"; then
    echo -e "${RED}Error: Failed to mount /home.${NC}"
    # Clean up by closing the LUKS container on failure
    cryptsetup close "$MAPPER_NAME"
    exit 1
fi

echo -e "${GREEN}Successfully mounted /home.${NC}"
echo "----------------------------------------"
echo -e "${YELLOW}Starting GUI...${NC}"

# Start the GUI (graphical.target)
systemctl isolate graphical.target

exit 0


