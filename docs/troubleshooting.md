# Troubleshooting

Problems encountered while provisioning Yocto, building the first image, and bringing up the DPI display on the Raspberry Pi 4.

Environment: Ubuntu 24.04 LTS (noble) build host, Yocto 5.0 LTS (scarthgap), Raspberry Pi 4 Model B, Waveshare RGB LCD HAT with an EP1103J-55-DCT 10.1" panel.

---

## 1. Package `libegl1-mesa` not found

**Symptom**
```
E: Unable to locate package libegl1-mesa
```

**Cause**
The package was renamed starting with Ubuntu 24.04. Official Yocto documentation still lists the old name.

**Fix**
Use `libegl1` instead of `libegl1-mesa` in the dependency list.

---

## 2. `git clone` hangs over the `git://` protocol

**Symptom**
`git clone -b scarthgap git://git.yoctoproject.org/poky` hangs with no output and no object counter.

**Cause**
The `git://` protocol uses port 9418, which is frequently blocked by ISPs and corporate firewalls.

**Fix**
Clone over HTTPS (port 443):
```bash
git clone -b scarthgap https://git.yoctoproject.org/git/poky
git clone -b scarthgap https://git.yoctoproject.org/git/meta-raspberrypi
git clone -b scarthgap https://git.openembedded.org/meta-openembedded
```

---

## 3. BitBake fails to start: missing `en_US.UTF-8` locale

**Symptom**
```
ERROR: Unable to start bitbake server (None)
ERROR: Server didn't start, last 60 loglines (.../bitbake-cookerdaemon.log):
Please make sure locale 'en_US.UTF-8' is available on your system
```

**Cause**
BitBake requires the `en_US.UTF-8` locale. On systems installed in a non-English language it is often not generated.

**Fix**
```bash
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8
locale -a | grep en_US    # verify: should print en_US.utf8
```
Restart the terminal afterwards and re-run `source oe-init-build-env`.

---

## 4. BitBake fails: user namespaces blocked by AppArmor

**Symptom**
```
ERROR: User namespaces are not usable by BitBake, possibly due to AppArmor.
```

**Cause**
Since Ubuntu 23.10, AppArmor restricts unprivileged user namespaces by default. BitBake uses them to isolate build tasks.

**Fix**
Create an AppArmor profile. Check the Python path with `readlink -f $(command -v python3)`.

```bash
sudo nano /etc/apparmor.d/bitbake
```

Contents (substitute the actual python3 path):
```
abi <abi/4.0>,
include <tunables/global>

profile bitbake /usr/bin/python3.12 flags=(unconfined) {
  userns,

  include if exists <local/bitbake>
}
```

Apply:
```bash
sudo apparmor_parser -r /etc/apparmor.d/bitbake
```

---

## 5. `do_fetch: Failed to fetch URL ...` warnings during the build

**Symptom**
Dozens of warnings such as:
```
WARNING: gcc-source-13.4.0-r0 do_fetch: Failed to fetch URL https://ftpmirror.gnu.org/..., attempting MIRRORS if available
```

**Cause**
Primary upstream mirrors (ftpmirror.gnu.org, download.savannah.gnu.org) are unreachable or slow.

**Fix**
No action needed. BitBake automatically falls back to PREMIRRORS — the Yocto Project's own mirrors. What matters is the final line:
```
NOTE: Tasks Summary: Attempted 3729 tasks of which 0 didn't need to be rerun and all succeeded.
```
A `WARNING` is not an error; the build succeeded.

---

## 6. Raspberry Pi won't boot: image copied file-by-file

**Symptom**
The card was formatted manually and image files were copied into the partitions. On power-up the green LED goes dark and the system does not boot.

**Cause**
A `.wic` file is a full disk image **including the partition table**, not an archive of files. It must not be unpacked and copied manually. Manual copying loses the `.dtb` (device tree) files and the `overlays/` directory — without a device tree the kernel will not start.

**Fix**
Write the image byte-for-byte with `dd`. There is no need to format or partition the card beforehand — `dd` overwrites the partition table.

```bash
lsblk                                    # identify the device (whole disk, not a partition!)
sudo umount /dev/sdX1 /dev/sdX2
cd ~/yocto/build/tmp/deploy/images/raspberrypi4-64/
bzcat core-image-minimal-raspberrypi4-64.rootfs.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

**Verifying a correct write:**
- `boot` partition — roughly 136 MB FAT, contains `bcm2711-rpi-4-b.dtb` and the `overlays/` directory
- `root` partition — roughly 49 MB ext4 (sized to the rootfs, not to the card)
- the remainder of the card — unallocated free space

---

## 7. No SSH access to the built image

**Cause**
`core-image-minimal` ships without an SSH server.

**Fix**
Add a single line to `build/conf/local.conf`:
```
EXTRA_IMAGE_FEATURES += "ssh-server-openssh debug-tweaks"
```

- `ssh-server-openssh` installs OpenSSH;
- `debug-tweaks` allows root login with an empty password (**development only** — remove for production).

Use `+=` rather than `?=`: `?=` only assigns when the variable is unset, which can silently drop other image features.

---

## 8. Adding packages to the image

`core-image-minimal` has no text editor, no diagnostic tools, and no package manager to add them at runtime. Anything needed on the target must go into the image at build time.

Add to `build/conf/local.conf`:
```
IMAGE_INSTALL:append = " nano i2c-tools"
```

**Note the leading space** inside the quotes. The `:append` operator concatenates without inserting a separator, unlike `+=`, so omitting the space glues the package name onto the previous value and breaks the build.

---

## 9. Raspberry Pi not visible on the network after boot

**Symptom**
`nmap -sn 192.168.1.0/24` finds nothing; `ping raspberrypi4-64.local` fails to resolve.

**Causes and fixes**

*Ping by hostname.* `core-image-minimal` has no mDNS daemon (avahi), so `.local` names do not resolve. This is expected and not a sign of trouble.

*Network scanning.* Run nmap under `sudo` — it then uses ARP requests instead of ICMP and finds hosts that do not answer pings:
```bash
sudo nmap -sn 192.168.1.0/24
```
The reliable way to identify the board is to diff the host list against a scan taken before the Pi was powered on. MAC-based identification is not dependable: while Raspberry Pi OUIs are `dc:a6:32`, `e4:5f:01` and `b8:27:eb`, some images generate a locally-administered address instead.

*LED diagnostics without a monitor.* The green ACT LED on the Pi 4 indicates SD card activity, not "system alive". Once booted the system idles, there is no card activity, and the LED goes dark — this is **normal behaviour**. An actual error is signalled by cyclically repeating flash groups of a fixed count (4 flashes — `start.elf` did not launch, 7 — kernel not found, 8 — SDRAM failure).

The **Ethernet port LEDs** are a far more reliable signal: if they are lit, the kernel booted, the NIC driver came up, and a physical link is established.

*Main recommendation.* Diagnosing boot problems blind wastes time. Connect a monitor over micro-HDMI (or a USB-UART adapter to the GPIO header) and read the full boot log. Doing this immediately would have saved roughly an hour of guesswork.

Once the address is known, reserve it in the router's DHCP settings so it survives reboots.

---

## 10. SSH host key verification failed after reflashing

**Symptom**
```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

**Cause**
Reflashing the card regenerates the SSH host keys. The client sees a different key for a known address and refuses to connect. Harmless in this case.

**Fix**
```bash
ssh-keygen -f ~/.ssh/known_hosts -R 192.168.1.18
```

To avoid this on every reflash, add to `~/.ssh/config` (**development boards only**):
```
Host 192.168.1.18
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

---

## 11. Bringing up the DPI display

The panel is an EP1103J-55-DCT (10.1", 1024×600, 24-bit parallel RGB) connected through a Waveshare RGB LCD HAT and an RGB 50P TO 40/50P adapter.

### Timings

Derived from the panel datasheet, DE mode (pin 8 `MODE` is pulled high by default, so synchronisation follows the DEN signal):

| Parameter | Value |
|---|---|
| Active area | 1024 × 600 |
| H front porch / sync / back porch | 160 / 20 / 140 (sums to 320 = HSYNC blanking) |
| V front porch / sync / back porch | 12 / 3 / 20 (sums to 35 = VSYNC blanking) |
| Total frame | 1344 × 635 |
| Pixel clock | 1344 × 635 × 60 = 51 206 400 Hz |

The computed clock matches the datasheet's typical DCLK of 51.2 MHz, which confirms the porch split.

### Configuration

Appended to `/boot/config.txt`:

```
#dtoverlay=vc4-kms-v3d

gpio=0-27=a2
enable_dpi_lcd=1
display_default_lcd=1
dpi_group=2
dpi_mode=87
dpi_output_format=0x6f005
dpi_timings=1024 0 160 20 140 600 0 12 3 20 0 0 0 60 0 51206400 6
```

Three things are worth calling out:

**`gpio=0-27=a2` replaces `dtoverlay=dpi24`.** meta-raspberrypi deploys only a subset of overlays and `dpi24.dtbo` is not among them — `ls /boot/overlays/ | grep -i dpi` comes back empty. The overlay's job is to switch GPIO 0–27 into ALT2 (DPI) mode, which the `gpio=` directive does directly. Waveshare uses the same approach for several of their panels.

**`vc4-kms-v3d` must be commented out.** Legacy DPI is handled by the firmware (`start4.elf`), not by the kernel, and is incompatible with full KMS. With KMS disabled the DRM driver no longer loads, so `dmesg | grep -i drm` returns nothing — that is expected, not a fault.

**`dpi_output_format=0x6f005` comes from the HAT, not the panel.** This value encodes the RGB bit ordering, which is a property of how the HAT is wired. It is taken from Waveshare's documented configuration for their 7inch DPI LCD, which uses the same HAT and the same 1024×600 resolution.

### Verification

```bash
cat /sys/class/graphics/fb0/virtual_size    # expect: 1024,600
```

If this reports the panel resolution, the firmware accepted the timings and DPI mode is active. A different value means the configuration did not take effect.

### The actual failure was mechanical

With the configuration correct and `virtual_size` reporting `1024,600`, the panel stayed dark — including its backlight. The FFC cable between the HAT and the adapter board was not seated correctly.

**The backlight is the signal to check first.** The panel's backlight (42 LEDs, 6 series × 7 parallel, 18–20 V at 140 mA) is driven by a boost converter on the HAT and is independent of the video signal. If the backlight is dark, nothing on the matrix is visible regardless of how correct the timings are — so there is no point tuning porches until it lights up.

Order of investigation for a dark panel:

1. Backlight switch on the HAT set to ON
2. Both FFC/FPC cables fully seated, contacts facing the correct way, latches closed on both sides
3. Panel connected to the correct socket on the adapter (this varies by panel size)
4. Voltage across LEDA/LEDK measured with a multimeter — expect 18–20 V
5. Only then: timings, output format, `virtual_size`

The `VCOM` trimmer on the HAT adjusts matrix contrast and is only worth touching once an image is actually visible.

### Baking the configuration into the image

`config.txt` lives on the boot partition, which `dd` overwrites in full on every reflash — so editing it by hand means losing the display after each new image. meta-raspberrypi generates the file from the `rpi-config` recipe, and `RPI_EXTRA_CONFIG` appends arbitrary lines to it.

Appending alone is not enough here: `dtoverlay=vc4-kms-v3d` is emitted by meta-raspberrypi itself, and `RPI_EXTRA_CONFIG` cannot remove an existing line (upstream issue #1328). The overlay comes from the `vc4graphics` machine feature, so that feature has to be dropped.

In `build/conf/local.conf`:

```
MACHINE_FEATURES:remove = "vc4graphics"

RPI_EXTRA_CONFIG = ' \n\
# Waveshare RGB LCD HAT + EP1103J-55-DCT 10.1 inch 1024x600 \n\
gpio=0-27=a2 \n\
enable_dpi_lcd=1 \n\
display_default_lcd=1 \n\
dpi_group=2 \n\
dpi_mode=87 \n\
dpi_output_format=0x6f005 \n\
dpi_timings=1024 0 160 20 140 600 0 12 3 20 0 0 0 60 0 51206400 6 \n\
'
```

Two syntax traps:

**No double quotes inside the value.** The recipe interpolates `RPI_EXTRA_CONFIG` into shell code inside a `printf "..."`, so a `"` in the text — for instance writing the panel size as `10.1"` — terminates the string early and the parse fails with:
```
ERROR: .../rpi-config_git.bb: Error during parse shell code
bb.pysh.pyshlex.NeedMore
```
Write `10.1 inch` instead, or escape the quote.

**Line continuation.** Each line ends with `\n\` — the `\n` becomes a newline in the generated file, the trailing backslash escapes the real newline in `local.conf`. Single quotes around the whole value.

The recipe also warns if any line in `config.txt` exceeds 80 characters, which the timings line stays under.

### Verifying

```bash
grep -c vc4 /boot/config.txt        # expect: 0
grep dpi_timings /boot/config.txt   # expect: the timings line
```

Both checks passing on a freshly flashed card means the configuration is reproducible and survives reflashing.

---

## 12. `set -u` conflicts with `oe-init-build-env`

**Symptom**
A build script using `set -euo pipefail` aborts with:
```
oe-init-build-env: line 29: BBSERVER: unbound variable
```

**Cause**
`set -u` (abort on undefined variable) applies to any script sourced afterwards. `oe-init-build-env` legitimately references variables such as `BBSERVER` that may be unset.

**Fix**
Disable the option around the call:
```bash
set +u
source oe-init-build-env "$BUILD_DIR" >/dev/null
set -u
```

## 13. DPI panel under full KMS: display dead, HDMI dead, no /dev/dri

**Symptom.** After switching the panel from legacy firmware DPI to
`vc4-kms-dpi-generic`, the board showed a console on HDMI for about a second
and then dropped to "no signal". The DPI panel showed backlight only. SSH did
not come up either. An earlier build did boot, and its log contained:

    platform panel: Fixed dependency cycle(s) with /soc/dpi@7e208000
    platform fe208000.dpi: Fixed dependency cycle(s) with /panel

with no `vc4` lines at all.

**Bisecting config.txt.** Commenting out the whole DPI block brought the HDMI
console back. Re-enabling a single line — `dtoverlay=vc4-kms-dpi-generic,rgb888`
— killed it again. This is the key observation: `vc4-kms-v3d` exposes one DRM
device for every output, so a broken DPI panel node takes HDMI down with it.

**Ruled out along the way.** The overlay on the boot partition was byte-identical
to the one built by `linux-raspberrypi` 6.6.63 (same md5), so it was not a
version mismatch. `config.txt` contained no I2C, SPI or UART parameters, so
there was no contention for GPIO 0-27. Dropping to `rgb666` and lowering the
pixel clock changed nothing.

**Root cause.** A build-order problem in the kernel config:

    CONFIG_DRM_VC4=y            # built in, probes before rootfs is mounted
    CONFIG_DRM_PANEL_SIMPLE=m   # a module in /lib/modules, not yet reachable

`vc4-kms-dpi-generic` creates a node with `compatible = "panel-dpi"`, which is
handled by `panel-simple`. Built as a module, that driver simply does not exist
at the time `vc4` probes. The probe defers forever, `vc4` never registers, and
no DRM device is created — hence no DPI, no HDMI, and a one-second flash as the
firmware framebuffer is torn down.

**What did not work.** Shipping a `.cfg` fragment through a `.bbappend` had no
effect: `linux-raspberrypi` in scarthgap does not inherit `kernel-yocto`, so
config fragments are fetched into WORKDIR and then ignored. Patching `.config`
directly did not work either — Kconfig refuses `=y` for a symbol whose
dependency is `=m`, and `oldconfig` silently reverted the change because
`CONFIG_BACKLIGHT_CLASS_DEVICE=m`.

**Fix.** Force the whole dependency chain builtin from `do_configure:append`:

    do_configure:append() {
        for s in BACKLIGHT_CLASS_DEVICE DRM_PANEL_SIMPLE; do
            sed -i "/^CONFIG_${s}=/d;/^# CONFIG_${s} is not set/d" ${B}/.config
            echo "CONFIG_${s}=y" >> ${B}/.config
        done
        yes '' | oe_runmake -C ${S} O=${B} oldconfig
    }

Also drop `MACHINE_FEATURES:remove = "vc4graphics"` from `local.conf`. It does
more than suppress the `vc4-kms-v3d` line in config.txt — it disables
`CONFIG_DRM_VC4` in the kernel entirely.

**Lessons.**

- sstate will happily serve a stale kernel config. After touching anything that
  affects `do_configure`, run `bitbake -c cleansstate virtual/kernel` and verify
  the resulting `.config` *before* building an image. Three build cycles were
  spent flashing a kernel that had never been reconfigured.
- Verify a hypothesis at its cheapest point. `grep` on `.config` takes a second;
  a build plus a flash plus a boot takes forty minutes.
- On the Pi, DRM is all-or-nothing. A dead HDMI is not a second failure to chase
  — it is evidence about the first one.
- A serial console is not optional. Every dead end here came from having no way
  to read the kernel log when the board would not boot.
