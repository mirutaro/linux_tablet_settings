### **Fixing Sound Issues on NEC PC-VK24VTAMJ (ThinkPad 10) with Debian 12**

This document outlines the cause of and solution to the sound output problem that occurs when installing Debian 12 on an NEC PC-VK24VTAMJ tablet (which has hardware identical to the Lenovo ThinkPad 10).

#### **1. Target System and the Problem**

*   **Model:** NEC PC-VK24VTAMJ
*   **CPU:** Intel Atom Z3795 (Bay Trail generation)
*   **OS:** Debian 12 (Bookworm) i386 (32-bit)

##### **Symptoms**

After a clean installation of Debian 12, there is no audio output from the internal speakers or the headphone jack. The `aplay -l` command only recognizes the `Intel HDMI/DP LPE Audio` device, and the expected internal audio codec is not found.

##### **Kernel Errors Observed During Diagnosis**

During the investigation, the following key kernel errors were identified:

1.  `devm_snd_soc_register_card failed -517 (EPROBE_DEFER)`
    *   This indicates that the sound card registration failed. The process is being repeatedly deferred because other dependent devices (like the codec) are not yet ready.

2.  `ASoC: CODEC DAI rt5640-aif1 not registered`
    *   This is the direct cause of the above error. The sound card cannot find the audio codec (`rt5640`) it needs to interface with.

3.  **`rt5640 i2c-10EC5640:00: Device with ID register 0x6271 is not rt5640/39`**
    *   **This is the core of the problem.** The system's ACPI table (the hardware blueprint) is **incorrectly reporting** to the kernel that the sound chip is `"10EC5640"` (an RT5640). Believing this report, the `rt5640` driver probes the device, but the device responds, "My real ID is `0x6271`" (an RT5651). Because the IDs do not match, the driver aborts the process.

#### **2. The Core of the Solution: Patching the Kernel Based on DMI Information**

The root cause of the problem is that the system's ACPI table reports incorrect information about the audio codec.

Initially, a solution involving directly modifying the ID tables of the `rt5640` and `rt5651` drivers to handle the incorrect ACPI ID (`10EC5640`) was considered. However, further investigation revealed that a more fundamental and correct solution for this tablet's hardware configuration (Intel Bay Trail platform + audio codec) is to **apply a quirk intended for the `rt5672` driver**.

Therefore, instead of fixing the ACPI ID issue directly, we will use the system's more reliable hardware information, the **DMI** (manufacturer name `NEC` and product name `PC-VK24VTAMJ`), to instruct the kernel to forcibly load the special configuration for the `rt5672`. This will override the incorrect ACPI information and allow the audio device to be initialized correctly.

---

#### **3. Custom Kernel Cross-Compilation Steps**

**Build Environment:** An amd64 architecture Linux PC
**Target Environment:** NEC PC-VK24VTAMJ Tablet (Debian i386)

##### **Step 1: Prepare the Cross-Compilation Environment (on the build PC)**

```bash
sudo apt-get update
sudo apt-get install build-essential linux-source bc kmod cpio flex libncurses-dev libelf-dev libssl-dev dwarves bison gcc-i686-linux-gnu binutils-i686-linux-gnu libc6-dev-i386-cross
```

##### **Step 2: Extract the Kernel Source (on the build PC)**

Extract the source for the target kernel version. The standard kernel for Debian 12 is the `6.1` series.

```bash
cd /usr/src/
# Adjust X.X to match your target version
sudo tar -xvf linux-source-6.1.tar.xz 
cd linux-source-6.1
```

##### **Step 3: Modify the Source Code (on the build PC)**

Open the following file with a text editor:

*   `sound/soc/intel/common/soc-acpi-intel-byt-match.c`

Find the `dmi_system_id` array named `byt_table[]` and add the following block just before the final `{}` in the array. This will ensure that when the DMI information matches your NEC tablet, the callback function `byt_rt5672_quirk_cb` is called to enable the aforementioned `rt5672` quirk.

```c
        {
                /* Quirk for NEC PC-VK24VTAMJ */
                .callback = byt_rt5672_quirk_cb,
                .matches = {
                        DMI_MATCH(DMI_SYS_VENDOR, "NEC"),
                        DMI_MATCH(DMI_PRODUCT_NAME, "PC-VK24VTAMJ"),
                },
        },
```
*(Note: It is best to verify the `DMI_MATCH` strings by running `sudo dmidecode -t system` on the target tablet to ensure they are exact.)*

##### **Step 4: Prepare the Kernel Configuration (on the build PC)**

1.  Copy the `/boot/config-$(uname -r)` file from the target tablet to the kernel source directory (`/usr/src/linux-source-X.X/`) on the build PC and rename it to `.config`.

2.  Update the configuration file by running the following command (press Enter for all questions to accept the defaults).
    ```bash
    make ARCH=i386 CROSS_COMPILE=i686-linux-gnu- oldconfig
    ```

3.  Clear the signing key configuration.
    ```bash
    ARCH=i386 CROSS_COMPILE=i686-linux-gnu- scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
    ```

##### **Step 5: Run the Cross-Compilation (on the build PC)**

```bash
make -j$(nproc) ARCH=i386 CROSS_COMPILE=i686-linux-gnu- bindeb-pkg
```

##### **Step 6: Install the New Kernel (on the target tablet)**

1.  Transfer the `.deb` files (`linux-image-...._i386.deb` and `linux-headers-...._i386.deb`) generated in the `/usr/src/` directory of the build PC to the target tablet.

2.  Install them using the `dpkg` command.
    ```bash
    sudo dpkg -i linux-image-...._i386.deb linux-headers-...._i386.deb
    ```

3.  Reboot the tablet.

**Result:**
With these steps, the kernel will now correctly recognize the hardware, and you will get **sound output from the internal speakers** in modern applications like web browsers.

---

#### **4. Scripts for Manually Switching Audio Output**

Even after the kernel fix, the OS still has an issue where it cannot automatically detect when headphones are plugged in or unplugged. Therefore, you need to manually switch the audio output destination (speakers/headphones) by directly controlling the ALSA mixer switches.

**Prerequisite:**
First, confirm that the card number for your sound card (`cht-bsw-rt5672`) is `1` by running the `aplay -l` command.

##### **Script 1: Switch to Headphones (`switch-to-headphones.sh`)**

```bash
#!/bin/bash
# NEC PC-VK24VTAMJ Audio Switcher: Headphones
# Card number should be verified with 'aplay -l'

CARD_NUM=1

# Turn Headphone output ON
amixer -c ${CARD_NUM} cset numid=170 on

# Turn External Speaker output OFF
amixer -c ${CARD_NUM} cset numid=173 off

echo "Audio output switched to Headphones."
```

##### **Script 2: Switch to Speakers (`switch-to-speakers.sh`)**

```bash
#!/bin/bash
# NEC PC-VK24VTAMJ Audio Switcher: Speakers
# Card number should be verified with 'aplay -l'

CARD_NUM=1

# Turn Headphone output OFF
amixer -c ${CARD_NUM} cset numid=170 off

# Turn External Speaker output ON
amixer -c ${CARD_NUM} cset numid=173 on

echo "Audio output switched to Speakers."
```

##### **How to Use the Scripts**

1.  Create files named `switch-to-headphones.sh` and `switch-to-speakers.sh` (e.g., on your desktop) with the content above.
2.  Make both files executable with the following command:
    ```bash
    chmod +x switch-to-headphones.sh
    chmod +x switch-to-speakers.sh
    ```
3.  You can now switch the audio output instantly by double-clicking these files or by running them from the terminal (e.g., `./switch-to-headphones.sh`).
