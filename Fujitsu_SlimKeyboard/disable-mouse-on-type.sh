#!/bin/bash

# --- ▼▼▼ Configuration Items ▼▼▼ ---
# A stable path for your keyboard, in the format /dev/input/by-id/..-event-kbd
KEYBOARD_DEV="/dev/input/by-id/usb-04c5_148a-event-kbd" # ←★ Please adjust this to match your environment

# Vendor ID and Product ID of the mouse to search for
MOUSE_VENDOR_ID="04c5"
MOUSE_PRODUCT_ID="148a"

# The number of seconds until the mouse is enabled after key input stops
TIMEOUT=0.5
# --- ▲▲▲ Configuration ends here ▲▲▲ ---


# --- Script Body: Infinite loop with a self-healing function ---
while true; do
    echo "--- Phase 1: Device Search ---"
    MOUSE_SYSFS_PATH=""

    # Loop to wait until both the keyboard and mouse are connected
    while true; do
        # Search for the mouse path
        for path in $(find /sys/devices -ipath "*${MOUSE_VENDOR_ID}:${MOUSE_PRODUCT_ID}*/input/input*" -type d 2>/dev/null); do
            if [ -f "$path/name" ] && grep -q -i "Mouse" "$path/name"; then
                MOUSE_SYSFS_PATH="$path"
                break
            fi
        done

        # Check if both the keyboard and mouse have been found
        if [ -e "$KEYBOARD_DEV" ] && [ -n "$MOUSE_SYSFS_PATH" ]; then
            echo "Keyboard and mouse found. Starting monitoring."
            break # Exit the waiting loop
        fi

        echo "Devices not connected. Retrying in 5 seconds..."
        sleep 5
    done


    echo "--- Phase 2: Start Monitoring ---"
    echo "Monitoring keyboard: $KEYBOARD_DEV"
    echo "Controlling mouse: $MOUSE_SYSFS_PATH"

    is_inhibited=false

    # [Change] Use process substitution (< <(...)) instead of a pipeline (|)
    while true; do

      # [Self-healing function] Check for the existence of the devices at the beginning of each loop
      if ! [ -e "$KEYBOARD_DEV" ] || ! [ -d "$MOUSE_SYSFS_PATH" ]; then
          echo "A device has been disconnected. Returning to the search phase."
          break # Exit the monitoring loop
      fi

      # Determine the presence of key input based on the success or failure of the read command
      if read -t $TIMEOUT line; then
        # [read success] => Key input occurred
        if ! $is_inhibited; then
          echo 1 | sudo tee "$MOUSE_SYSFS_PATH/inhibited" > /dev/null
          is_inhibited=true
          echo "Typing detected: Disabling mouse"
        fi
      else
        # [read failure] => Timed out (no key input)
        if $is_inhibited; then
          echo 0 | sudo tee "$MOUSE_SYSFS_PATH/inhibited" > /dev/null
          is_inhibited=false
          echo "Input stopped: Enabling mouse"
        fi
      fi
    done < <(sudo stdbuf -oL libinput debug-events --device "$KEYBOARD_DEV") # ← This is the change

    # --- Processing after the monitoring loop ends ---
    echo "--- Monitoring stopped ---"
    # Just in case, if the mouse still exists and is disabled, re-enable it
    if [ -d "$MOUSE_SYSFS_PATH" ] && $is_inhibited; then
        echo 0 | sudo tee "$MOUSE_SYSFS_PATH/inhibited" > /dev/null
        echo "Cleanup: Re-enabled the mouse."
    fi

    echo "Restarting device search in 5 seconds..."
    sleep 5

done
