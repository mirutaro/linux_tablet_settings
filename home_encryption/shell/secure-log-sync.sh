#!/bin/bash

# --- Settings ---
# Replace 'username' with your own username
PERSISTENT_LOG_DIR="/home/username/secure_logs/var_log"
TMPFS_LOG_DIR="/var/log"

# Enum the log file names to which to "append" content
# Add or remove file names according to your system.
APPEND_LOGS=(
    "syslog"
    "auth.log"
    "kern.log"
    "daemon.log"
    "messages"
    "dpkg.log"
    "alternatives.log"
)
# --- Settings up to here ---

# Check if the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run with root privileges." 1>&2
   exit 1
fi

# Check if persistent log directory exists
if [ ! -d "$PERSISTENT_LOG_DIR" ]; then
    echo "Error: Persistent log directory not found: $PERSISTENT_LOG_DIR"
    exit 1
fi

# Check if it's already bind mounted
if mountpoint -q "$TMPFS_LOG_DIR" && grep -qs "$PERSISTENT_LOG_DIR" /proc/mounts; then
    echo "Already bind mounted, skipping."
    exit 0
fi

echo "Step 1: Append the text log to a persistent location..."
for logfile in "${APPEND_LOGS[@]}"; do
    TMPFS_FILE="$TMPFS_LOG_DIR/$logfile"
    PERSISTENT_FILE="$PERSISTENT_LOG_DIR/$logfile"

    # Process only if the log file exists on tmpfs and is not empty
    if [ -s "$TMPFS_FILE" ]; then
        # If the file does not exist at the destination, it will be created while maintaining permissions.
        if [ ! -f "$PERSISTENT_FILE" ]; then
            touch "$PERSISTENT_FILE"
            chmod --reference="$TMPFS_FILE" "$PERSISTENT_FILE"
            chown --reference="$TMPFS_FILE" "$PERSISTENT_FILE"
        fi
        
        # Append the contents of the log on tmpfs to a persistent file
        cat "$TMPFS_FILE" >> "$PERSISTENT_FILE"
        echo "  - Added the contents of a file ($logfile)"
    fi
done

echo "Step 2: Sync other files and directories..."
# Generate rsync exclude options
RSYNC_EXCLUDES=()
for logfile in "${APPEND_LOGS[@]}"; do
    RSYNC_EXCLUDES+=(--exclude="$logfile")
done

# Exclude the added files and synchronize the rest with rsync
# This ensures that new directories, binary logs, etc. are copied correctly.
rsync -avt "${RSYNC_EXCLUDES[@]}" "$TMPFS_LOG_DIR/" "$PERSISTENT_LOG_DIR/"

echo "Step 3: Bind mount the persistent log directory to /var/log..."
mount --bind "$PERSISTENT_LOG_DIR" "$TMPFS_LOG_DIR"

if [ $? -eq 0 ]; then
    echo "Processing completed successfully."
    # Restart systemd-journald so that it recognizes the new mount point
    # This allows journalctl to display persisted logs as well.
    systemctl restart systemd-journald
else
    echo "Error: Bind mount failed."
    exit 1
fi

exit 0
