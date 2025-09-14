## **`home_encryption_guide.md` (version with /var/log encryption support)**

## **Guide to Encrypting /home with LUKS and Auto-Decrypting with an SD Card Key on Debian/Linux**

### **1. Purpose**

This guide aims to strongly encrypt the `/home` directory using LUKS on a PC with Debian GNU/Linux installed (especially devices like Windows tablets), achieving the following goals:

*   **Security:** Personal data within `/home` is encrypted, preventing information leakage in case the PC is stolen, lost, or disposed of.
*   **Convenience:** For daily use, you can automatically log in without entering a passphrase, simply by having the SD card with the key file inserted.
*   **Robustness:** If the SD card is lost or forgotten, you can switch to a CUI (Command-Line Interface) and manually recover by entering a passphrase.

### **2. Prerequisites**

Before starting this procedure, the following preparations must be completed.

*   **Debian GNU/Linux Installation:**
    Debian must be installed on the PC. It is **essential** that during installation, you created `/home` on its own dedicated partition, separate from the root (`/`) partition.

*   **Creation of a LUKS Encrypted Partition for /home:**
    Initialize the partition for `/home` (e.g., `/dev/mmcblk0p4`) as a LUKS container. This operation is performed only once.

    **[WARNING] This command will completely erase all data on the partition.**
    ```bash
    # First, unmount /home
    sudo umount /home

    # Create the LUKS container
    sudo cryptsetup luksFormat /dev/mmcblk0p4 # Replace with your actual partition name
    ```
    After running the command, type `YES` and set a **strong recovery passphrase** for when the SD card is lost. Store this passphrase securely and never forget it.

### **3. Creating and Registering the Encryption Key**

Refer to this section when creating a key for the first time or when **recreating** it after losing or damaging the SD card.

1.  **Find the UUIDs:**
    To specify devices reliably in the upcoming configurations, find the UUID of each partition.
    ```bash
    sudo blkid
    ```
    From the output of this command, note down the following two UUIDs:
    *   **LUKS Partition UUID:** (e.g., `xxxxxxxx-xxxx-...`)
    *   **SD Card Partition UUID:** (e.g., `yyyyyyyy-yyyy-...`)

2.  **Create a Key File and Save it to the SD Card:**
    ```bash
    # Format the SD card (all data will be erased)
    sudo mkfs.ext4 /dev/mmcblkp1 # SD card's partition name

    # Temporarily mount the SD card
    sudo mkdir -p /mnt/sdkey
    sudo mount /dev/mmcblkp1 /mnt/sdkey

    # Create a 4096-byte random key file
    sudo dd if=/dev/urandom of=/mnt/sdkey/home.key bs=4096 count=1

    # Protect the key file's permissions
    sudo chmod 0400 /mnt/sdkey/home.key
    ```

3.  **Register the Created Key with the LUKS Partition:**
    ```bash
    # Register the new key with the LUKS container
    sudo cryptsetup luksAddKey /dev/mmcblk0p4 /mnt/sdkey/home.key
    ```
    You will be prompted to enter the **recovery passphrase** that you set during the prerequisite stage.

4.  **Clean Up:**
    ```bash
    sudo umount /mnt/sdkey
    ```

### **4. Automatic Startup Configuration**

#### **4.1. How the Startup Process Works**

Standard auto-decryption using `/etc/crypttab` runs very early in the boot process, which often fails because external devices like SD cards have not yet been recognized.

To solve this problem, we will adopt the following approach:

1.  After the main system starts booting and hardware detection has stabilized, a custom `systemd` service (`mount-home-crypt.service`) will be executed.
2.  This service attempts to decrypt and mount `/home` using the key from the SD card.
3.  If successful, the GUI starts normally.
4.  **If it fails (e.g., the SD card is not present)**, the system calls another rescue service (`fallback-to-cli.service`), which cancels the GUI startup and transitions to a **CUI login screen**.
5.  The user can then log in as `root` in the CUI and run a manual recovery script (`start-gui-manually.sh`) to decrypt and mount `/home` with the passphrase, and then start the GUI.

#### **4.2. Creating and Configuring Each File**

1.  **Create `mount-home-crypt.sh`**
This is the main script that attempts decryption and mounting using the SD card key.

    **Location:** `/usr/local/sbin/mount-home-crypt.sh`
    ```bash
    #!/bin/bash
    # --- Variable settings (edit the UUID to match your environment) ---
    LUKS_PART_UUID="7bab175e-9512-4d8a-85be-b1bdba07d51a"
    KEY_DEV_UUID="ad38ac5-db02-48aa-912a-bbfdb5b95ecf"
    MAPPER_NAME="home_crypt"
    MOUNT_POINT="/home"
    # --- End of variable settings, script continues below ---
    ```
2.  **After configuring, grant execute permissions:**
    ```bash
    sudo chmod +x /usr/local/sbin/mount-home-crypt.sh
    ```

---
3.  **Create `mount-home-crypt.service`**
    This service runs the above script before the GUI starts and calls the rescue service upon failure.
    **Location:** `/etc/systemd/system/mount-home-crypt.service`
    ```ini
    [Unit]
    Description=Mount encrypted /home partition
    DefaultDependencies=no
    After=local-fs-pre.target systemd-udev-settle.service
    Before=local-fs.target graphical.target
    OnFailure=fallback-to-cli.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/sbin/mount-home-crypt.sh

    [Install]
    WantedBy=graphical.target
    ```
    **After configuring, enable the service:** `sudo systemctl enable mount-home-crypt.service`

    ---
4.  **Create `fallback-to-cli.service`**
    A simple rescue service that only switches to the CUI login mode upon decryption failure.
    **Location:** `/etc/systemd/system/fallback-to-cli.service`
    ```ini
    [Unit]
    Description=Fall back to multi-user target (CLI)

    [Service]
    Type=oneshot
    ExecStart=/bin/systemctl isolate multi-user.target
    ```
    **Note:** This service does not need to be `enabled`.

    ---
5.  **Create `start-gui-manually.sh`**
    A manual recovery script to be run as `root` after transitioning to the CUI.
    **Location:** `/usr/local/sbin/start-gui-manually.sh`
    ```bash
    #!/bin/bash
    # --- Variables (edit the UUID to match your environment) ---
    LUKS_PART_UUID="7bab175e-9512-4d8a-85be-b1bdba07d51a"
    MAPPER_NAME="home_crypt"
    MOUNT_POINT="/home"
    # --- End of variables, script continues below ---
    ```
6.  **After configuring, grant execute permissions:** 
    ```bash
    sudo chmod +x /usr/local/sbin/start-gui-manually.sh
    ```

    ---
7.  **Configure `root`'s `.bash_profile`**
    Displays a help message like the one below when logging in as `root` in the CUI.
    **Location:** `/root/.bash_profile`
    ```text
    ###################################################################
    #  Welcome, root! The /home partition is not currently mounted.   #
    #  To decrypt /home and start the GUI, please run the command:    #
    #                                                                 #
    #          start-gui-manually.sh                                  #
    #                                                                 #
    ###################################################################
    ```

---
#### **4.3. Regarding Standard Configuration Files**

*   **/etc/crypttab:**
    The system's standard decryption mechanism will conflict with our custom service and should not be used. **Do not add** any entries related to `/home` in this file (comment them out if they exist).
    ```
    # <name>               <device>                         <password> <options>
    #home_crypt  UUID=7bab175e-9512-4d8a-85be-b1bdba07d51a   none  luks,no-fail
    ```

*   **/etc/fstab:**
    Since our custom script handles mounting `/home`, automatic mounting at boot is not needed in this file. **Do not add** any entries related to `/home` in this file (comment them out if they exist).
    ```
    # <file system>             <mount point>  <type>  <options>  <dump>  <pass>
    #/dev/mapper/home_crypt                    /home          ext4    defaults,noatime,discard 0 2
    ```

---

### **5. Advanced Setup: Protecting /var/log and /tmp**

In addition to encrypting `/home`, you can further enhance security by protecting system logs (`/var/log`) and temporary files (`/tmp`). These directories can contain privacy-sensitive information or details about system behavior.

The approach here is as follows:
1.  **On Boot:** Mount `/var/log` as a RAM disk (`tmpfs`), so logs during the boot sequence are temporarily stored in RAM.
2.  **After /home is Mounted:** Immediately after `/home` is successfully decrypted and mounted, **append** the logs from RAM to a persistent location inside the encrypted `/home`. Then, configure the system so that subsequent logs are written directly to this encrypted area.

#### **5.1. Mounting /var/log as tmpfs on Boot**
Edit the `/etc/fstab` file and add a line to mount `/var/log` as `tmpfs`.
**Location:** `/etc/fstab`
```ini
# Add this line for volatile /var/log on boot
tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=100M 0 0
```
*Adjust `size=100M` according to your system's RAM capacity. Logs cannot be recorded if this size is exceeded.*

#### **5.2. Creating the Log Persistence Script**
Create a script that appends the boot-time logs to a directory within `/home` and then switches the mount point.
**Location:** `/usr/local/sbin/secure-log-sync.sh`
```bash
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
# --- End of settings, script continues below ---
```
**After configuring, grant execute permissions:** 
```bash
sudo chmod +x /usr/local/sbin/secure-log-sync.sh
```
**Create the persistent log directory:**
```bash
mkdir -p /home/username/secure_logs/var_log  #replace 'username' with your actual username
```

---

#### **5.3. Configuring Automatic Execution for Log Persistence**

Create a `systemd` service that detects when `/home` has been mounted and automatically runs the log persistence script (`secure-log-sync.sh`). This ensures that the log synchronization process runs reliably whenever `/home` is successfully decrypted (whether automatically or manually).

1.  **Create `secure-log-sync.service`:**
    Create a new service file that will run after `/home` is mounted.
    **Location:** `/etc/systemd/system/secure-log-sync.service`

    ```ini
    [Unit]
    Description=Sync tmpfs /var/log to persistent storage and bind mount
    After=network.target home.mount
    Requires=home.mount

    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/secure-log-sync.sh

    [Install]
    WantedBy=graphical.target
    ```

    **Explanation:**
    *   `Requires=home.mount` defines a dependency: "run this service only after the `/home` mount process has succeeded." This prevents the service from running if the `/home` mount fails.
    *   `After=home.mount` ensures it runs after `/home` is available.

2.  **Enable the Service:**
    Register the new service with `systemd` and enable it to run on boot.

    ```bash
    sudo systemctl enable secure-log-sync.service
    ```

