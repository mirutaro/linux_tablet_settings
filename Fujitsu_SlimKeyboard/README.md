### **Guide to Disabling a Specific Mouse/Touchpad While Typing in a Wayland Environment**

#### **1. Problem Overview and Solution**

**Target Device**
*   Devices like the FUJITSU Arrows Tab Slim Keyboard (FMK-NKB14), where the touchpad is recognized by the OS as a generic mouse.

**Problem**
*   While typing on the keyboard, your hand may unintentionally touch the touchpad area, causing accidental mouse clicks or cursor movement.
*   The standard OS setting "Disable touchpad while typing" does not work because the device is not recognized as a "touchpad."

**Solution**
*   Utilize `sysfs`, which allows direct manipulation of low-level device information, to disable the physical mouse device only while typing.
*   Create a shell script to automate this process and register it as a `systemd` service, so the feature is automatically enabled when the PC starts.
*   Incorporate a self-healing function into the script to automatically detect device unplugging and re-plugging (hot-plugging) and resume monitoring.

---

#### **2. Installation Procedure**

**Step 2.1: Prerequisites (Tool Installation)**

The script uses `libinput`'s debugging tools to monitor input from the keyboard. First, install the tools in your environment using the following command.

*   **Debian / Ubuntu-based:**
    ```bash
    sudo apt update && sudo apt install libinput-tools
    ```
*   **Fedora / RHEL-based:**
    ```bash
    sudo dnf install libinput-utils
    ```
*   **Arch Linux-based:**
    ```bash
    sudo pacman -S libinput
    ```

**Step 2.2: Identifying Device Information**

To configure the script, you need to find two pieces of information: **① the keyboard's stable path** and **② the mouse's (touchpad's) vendor & product ID**.

**① How to find the keyboard's stable path (`KEYBOARD_DEV`)**

Run the following command in the terminal:
```bash
ls -l /dev/input/by-id/
```
From the output list, find the line that includes your keyboard's name and ends with **`-event-kbd`**. The filename on that line is the stable path.

**Example Output:**
```
...
lrwxrwxrwx 1 root root 9 Sep 15 10:00 usb-04c5_148a-event-kbd -> ../event4
...
```
In this case, the stable path is `/dev/input/by-id/usb-04c5_148a-event-kbd`. Make a note of this value.

**② How to find the mouse's vendor & product ID**

Run the `lsusb` command in the terminal.
```bash
lsusb
```
A list of connected USB devices will be displayed. Find the line corresponding to the target keyboard (or its receiver).

**Example Output:**
```
Bus 001 Device 005: ID 04c5:148a Fujitsu Component Limited
```
The number in the `XXXX:YYYY` format displayed after `ID` is the vendor ID (`XXXX`) and the product ID (`YYYY`), respectively. In this example, the vendor ID is `04c5`, and the product ID is `148a`. Make a note of these values as well.

**Step 2.3: Creating the Shell Script**

Next, create the shell script that will perform the automation.

1.  Create a file in `/usr/local/bin/` and open it with an editor using the following command:
    ```bash
    sudo nano /usr/local/bin/disable-mouse-on-type.sh
    ```

2.  In the opened editor, **copy and paste the entire code** from `[disable-mouse-on-type.sh]`.

3.  Modify the configuration items at the beginning of the script with the **values you noted in Step 2.2**.
    ```bash
    # --- ▼▼▼ Configuration ▼▼▼ ---
    KEYBOARD_DEV="/dev/input/by-id/usb-04c5_148a-event-kbd" # ←★ Change this to the path you found in ①
    MOUSE_VENDOR_ID="04c5"                                # ←★ Change this to the vendor ID you found in ②
    MOUSE_PRODUCT_ID="148a"                               # ←★ Change this to the product ID you found in ②
    TIMEOUT=0.5
    # --- ▲▲▲ End of Configuration ▲▲▲ ---
    ```

4.  Save the file and exit the editor (in Nano, press `Ctrl+X` → `Y` → `Enter`).

5.  Grant execute permissions to the created script.
    ```bash
    sudo chmod +x /usr/local/bin/disable-mouse-on-type.sh
    ```

6.  Testing the Script

    You can also run the script directly in the terminal to test its functionality.
    ```bash
    sudo /usr/local/bin/disable-mouse-on-type.sh
    ```
    While the script is running, type something. You should see output in the terminal indicating that the mouse device has been disabled. After you stop typing for a moment, it will be re-enabled automatically.
    
    Press Ctrl+C to stop the script when you are finished testing.

**Step 2.4: Creating a `systemd` Service**

Finally, create a `systemd` service to run the script automatically when the PC starts.

1.  Create the service file and open it with an editor using the following command:
    ```bash
    sudo nano /etc/systemd/system/disable-mouse-on-type.service
    ``` 

2.  In the opened editor, **copy and paste the entire content** of `[disable-mouse-on-type.service]`.

3.  Save the file and exit the editor.

4.  Enable and start the service with the following commands:
    ```bash
    # Reload systemd to recognize the new service file
    sudo systemctl daemon-reload
    # Enable the service to start automatically on boot
    sudo systemctl enable disable-mouse-on-type.service
    # Start the service immediately
    sudo systemctl start disable-mouse-on-type.service
    ```

5.  As a final check, verify that the service is running correctly with the following command:
    ```bash
    systemctl status disable-mouse-on-type.service
    ```
    If you see `Active: active (running)` displayed in green, it was successful. The feature will now be enabled automatically even after restarting the PC.

--- 

