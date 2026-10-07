# Car Dashboard

A dual-screen automotive dashboard: a bare-metal instrument cluster on an STM32H743IIT6 and an infotainment system on a Raspberry Pi 4 running a custom Linux distribution built with Yocto.

This is a learning project. The priority is working through industry-standard embedded practices rather than reaching a result quickly.

---

## Architecture

Two compute nodes, each driving its own 10.1" display — like the two screens in a car's dashboard.

```
   [PC + CANable]  or  [ESP32 signal simulator]
            │  CAN bus (classic CAN 2.0)
            ▼
   ┌──────────────────────┐   UART    ┌──────────────────────┐
   │  STM32H743IIT6       │  (USB-    │  Raspberry Pi 4      │
   │  bare-metal          │──UART────▶│  Yocto Linux         │
   │                      │  bridge)  │  Qt 6                │
   │  instrument cluster  │           │  infotainment        │
   └──────────┬───────────┘           └──────────┬───────────┘
              │ LTDC                             │ RGB LCD HAT (DPI)
              ▼                                  ▼
      ┌───────────────┐                  ┌───────────────┐
      │ EP1103J-55-DCT│                  │ EP1103J-55-DCT│
      │ 10.1" 1024×600│                  │ 10.1" 1024×600│
      └───────────────┘                  └───────────────┘
```

**STM32H743IIT6 (bare-metal)** drives the instrument cluster: speed, RPM, indicator lights. It receives vehicle data over CAN (FDCAN2 in classic CAN mode) and forwards the data the infotainment needs to the Raspberry Pi over UART.

**Raspberry Pi 4 (Yocto Linux + Qt)** runs the infotainment system and handles the heavy work — UI and media. All Pi GPIOs are taken by the display HAT, so the STM32 link goes through a USB-UART bridge (CP2102 → `/dev/ttyUSB0`).

**CAN source.** During bring-up a PC with a CANable adapter (SocketCAN, `can-utils`) acts as a known-good CAN node. Later an ESP32 replaces it as the signal simulator, and the CANable stays on the bus as a sniffer.

The STM32 firmware lives in a separate repository; this repository covers the Raspberry Pi side.

## Hardware

| Component | Model | Notes |
|---|---|---|
| MCU | STM32H743IIT6 (core board with SDRAM) | bare-metal, display driven via LTDC |
| SBC | Raspberry Pi 4 Model B | Yocto Linux |
| Displays | EP1103J-55-DCT ×2 | 10.1", 1024×600, parallel RGB, GT9271 capacitive touch |
| Display adapter | Waveshare RGB LCD HAT + RGB 50P TO 40/50P | connects the panel to the Raspberry Pi |
| CAN transceiver | HW-021 (TJA1050) | 5 V supply, on the STM32 side |
| CAN adapter | CANable | PC ↔ CAN bus, built-in transceiver and terminator |
| USB-UART bridge | CP2102 | STM32 ↔ Raspberry Pi link, 3.3 V logic |

Key display parameters: parallel RGB (50 pin), DCLK 51.2 MHz typical, GT9271 touch over I²C, backlight 18–20 V / 140 mA driven by a boost converter on the HAT.

## Software stack

- **Yocto Project 5.0 LTS (scarthgap)** — custom distribution `carpanel` (poky-based, systemd)
- **Qt 6.8** (meta-qt6) — `eglfs_kms` backend, hardware-accelerated OpenGL ES on the V3D GPU, no compositor
- **Build host** — Ubuntu 24.04 LTS

Yocto was chosen over a stripped-down Ubuntu deliberately: real automotive platforms (COVESA / Automotive Grade Linux) are built on Yocto. It gives hands-on experience with BitBake, layers, recipes, and assembling a rootfs from scratch.

## Repository layout

```
configs/        Yocto build configuration and the Pi's boot config
docs/           documentation, measurements and solved problems
meta-carpanel/  project-specific Yocto layer: distro, image, recipes, kernel config
scripts/        environment setup and build automation
```

Yocto layers (poky, meta-raspberrypi, meta-openembedded, meta-qt6) and build artefacts are not tracked — they are provisioned by the setup script.

## Quick start

```bash
git clone <repo-url>
cd car-panel-OS
./scripts/setup-yocto.sh          # installs dependencies and clones the layers
```

> Known gap: the setup script does not clone meta-qt6 yet. Clone it into
> `~/yocto/meta-qt6` and check out commit `00c3bd95` until the script is fixed.

Open a build shell — always pass the build directory, otherwise
`oe-init-build-env` silently creates a fresh default build directory in the
current one (see [troubleshooting §17](docs/troubleshooting.md)):

```bash
source ~/yocto/poky/oe-init-build-env ~/yocto/build
```

Then build and flash in one step:

```bash
./scripts/build-and-flash.sh
```

The script builds `carpanel-image`, lists removable devices, requires the target device name to be typed out in full as confirmation, unmounts its partitions, and writes the image. Use `--build-only` to skip flashing or `--flash-only` to write an already-built image.

The first build takes several hours; subsequent ones are minutes.

## Connecting to the board

The Pi is connected to the build host directly with an Ethernet cable (USB-LAN
adapter on the host). NetworkManager's "Shared to other computers" mode runs a
DHCP server on that link, so the Pi gets an address in `10.42.0.0/24` and the
host is `10.42.0.1`.

```bash
sudo nmap -sn 10.42.0.0/24        # locate the board (sudo → ARP scan)
ssh pi                             # no password (debug-tweaks)
```

Reflashing the card regenerates the SSH host keys, so every new image trips
`REMOTE HOST IDENTIFICATION HAS CHANGED`. Scope the exception to this host in
`~/.ssh/config` rather than disabling host checking globally:

```
Host pi
    HostName 10.42.0.124
    User root
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
```

This trades away MITM protection for one address on a direct cable — acceptable
for a development board, not for anything else. `Host pi` only applies when you
type `ssh pi`; `ssh root@10.42.0.124` still goes through normal host-key checks.

## Display configuration

The panel runs under full KMS through the `vc4-kms-dpi-generic` overlay in
`rgb666` mode (`rgb888` gives wrong colours with this HAT). Timings are derived
from the panel datasheet and written into `config.txt` at build time via
`RPI_EXTRA_CONFIG` in `configs/local.conf`, so they survive reflashing.

Full KMS requires several DRM drivers to be built into the kernel rather than
shipped as modules — `linux-raspberrypi` defaults them to `=m`, which breaks the
probe order and leaves either the panel or the GPU dead. Both are forced builtin
from a `do_configure:append` hook in `meta-carpanel`.

With the V3D driver in place the kernel exposes a render node
(`/dev/dri/renderD128`), which is what Qt's `eglfs_kms` backend needs for
hardware-accelerated OpenGL ES. The connector is pinned to the panel by an
eglfs_kms JSON config shipped in the image (`eglfs-config` recipe).

Details, the timing derivation and the kernel config problems are in
[docs/troubleshooting.md](docs/troubleshooting.md).
The generated `config.txt` is kept in `configs/` for reference.

## Qt application

The UI lives in its own repository,
[qt-instrument-cluster](https://github.com/NordDemonNord/qt-instrument-cluster),
fetched by a recipe in `meta-carpanel` and pinned by `SRCREV`. It starts on boot
as a systemd service. Until the STM32 link is up it runs with
`VEHICLE_DATA_SOURCE=demo` (needles sweep, tell-tales blink).

The cluster on the Pi is a smoke test of the Qt stack only: in the final design
the cluster runs on the STM32 and the Pi hosts the infotainment UI.

## STM32 link

The STM32 talks to the Pi over UART through a CP2102 USB-UART bridge. The
`cp210x` driver is built as a kernel module and installed by `carpanel-image`;
udev loads it on plug-in and the port appears as `/dev/ttyUSB0`. For binary
data the port must be in raw mode (`stty -F /dev/ttyUSB0 115200 raw -echo`).

## Status

- [x] Yocto (scarthgap) environment provisioned for Raspberry Pi 4
- [x] Custom distro `carpanel` (systemd, trimmed DISTRO_FEATURES)
- [x] Build and flash automated in a single script
- [x] DPI display at 1024×600 under full KMS/DRM, configuration baked into the image
- [x] Custom layer `meta-carpanel` with kernel configuration overrides
- [x] V3D GPU driver built in, render node available
- [x] meta-qt6 integrated, Qt 6 with the `eglfs_kms` backend and GPU rendering
- [x] Project image recipe `carpanel-image`
- [x] `qt-instrument-cluster` packaged and started on boot (demo data)
- [x] Direct Ethernet link to the build host
- [x] USB-UART bridge (CP2102) supported in the image, loopback-tested
- [ ] STM32 firmware: clock, UART, FDCAN (register-level, CMSIS only)
- [ ] CAN path: PC + CANable → STM32
- [ ] STM32 ↔ Raspberry Pi UART protocol, serial data source in the Qt app
- [ ] ESP32 CAN signal simulator
- [ ] GT9271 touch panel over I²C
- [ ] Infotainment UI
- [ ] STM32 instrument cluster on LTDC
- [ ] Boot time and CPU optimisation
