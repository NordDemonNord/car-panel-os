# Car Dashboard

A dual-screen automotive dashboard: a bare-metal instrument cluster on an STM32H743IIT6 and an infotainment system on a Raspberry Pi 4 running a custom Linux distribution built with Yocto.

This is a learning project. The priority is working through industry-standard embedded practices rather than reaching a result quickly.

---

## Architecture

Two compute nodes, each driving its own 10.1" display — like the two screens in a car's dashboard.

```
   [PC: CAN simulator]
            │  UART (virtual COM port)
            ▼
   ┌──────────────────────┐         ┌──────────────────────┐
   │  STM32H743IIT6       │  UART   │  Raspberry Pi 4      │
   │  bare-metal          │────────▶│  Yocto Linux         │
   │                      │         │  Qt                  │
   │  instrument cluster  │         │  infotainment        │
   └──────────┬───────────┘         └──────────┬───────────┘
              │ LTDC (RGB24)                   │ RGB LCD HAT
              ▼                                ▼
      ┌───────────────┐                ┌───────────────┐
      │ EP1103J-55-DCT│                │ EP1103J-55-DCT│
      │ 10.1" 1024×600│                │ 10.1" 1024×600│
      └───────────────┘                └───────────────┘
```

**STM32H743IIT6 (bare-metal)** drives the instrument cluster: speed, RPM, indicator lights. It receives vehicle data over CAN, acts as the system CPU, and forwards control packets to the Raspberry Pi over UART.

**Raspberry Pi 4 (Yocto Linux + Qt)** runs the infotainment system and handles the heavy work — UI and media. It receives control packets from the STM32.

**CAN simulation.** During development, CAN packets are emulated on a PC and fed to the STM32 through a virtual COM port.

## Hardware

| Component | Model | Notes |
|---|---|---|
| MCU | STM32H743IIT6 | bare-metal, display driven via LTDC |
| SBC | Raspberry Pi 4 Model B | Yocto Linux |
| Displays | EP1103J-55-DCT ×2 | 10.1", 1024×600, RGB24, GT9271 capacitive touch |
| Display adapter | Waveshare RGB LCD HAT + RGB 50P TO 40/50P | connects the panel to the Raspberry Pi |

Key display parameters: 24-bit parallel RGB (50 pin), DCLK 51.2 MHz typical, GT9271 touch over I²C, backlight 18–20 V / 140 mA driven by a boost converter on the HAT.

## Software stack

- **Yocto Project 5.0 LTS (scarthgap)** — custom Linux distribution for the Raspberry Pi
- **Qt** — infotainment user interface
- **Build host** — Ubuntu 24.04 LTS

Yocto was chosen over a stripped-down Ubuntu deliberately: real automotive platforms (COVESA / Automotive Grade Linux) are built on Yocto. It gives hands-on experience with BitBake, layers, recipes, and assembling a rootfs from scratch.

## Repository layout

```
configs/     Yocto build configuration and the Pi's boot config
docs/        documentation and solved problems
scripts/     environment setup and build automation
```

Yocto layers (poky, meta-raspberrypi, meta-openembedded) and build artefacts are not tracked — they are provisioned by the setup script.

## Quick start

```bash
git clone <repo-url>
cd car-panel-OS
./scripts/setup-yocto.sh          # installs dependencies and clones the layers
```

Then build and flash in one step:

```bash
./scripts/build-and-flash.sh
```

The script builds the image, lists removable devices, requires the target device name to be typed out in full as confirmation, unmounts its partitions, and writes the image. Use `--build-only` to skip flashing or `--flash-only` to write an already-built image.

The first build takes several hours; subsequent ones are minutes.

## Connecting to the board

The Raspberry Pi needs an Ethernet connection to pick up a DHCP lease.

```bash
sudo nmap -sn 192.168.1.0/24      # locate the board
ssh root@<ip>                      # no password (debug-tweaks)
```

Reserve the address in the router's DHCP settings to avoid rescanning after every reboot.

## Display configuration

DPI timings and output format are set through `RPI_EXTRA_CONFIG` in `configs/local.conf`, so they are written into `config.txt` at build time and survive reflashing. The `vc4graphics` machine feature is dropped because legacy DPI is firmware-driven and incompatible with full KMS.

Details and the derivation of the timings are in
[docs/troubleshooting.md](docs/troubleshooting.md#11-bringing-up-the-dpi-display).
The generated `config.txt` is kept in `configs/` for reference.

## Status

- [x] Yocto (scarthgap) environment provisioned for Raspberry Pi 4
- [x] `core-image-minimal` built and booted on hardware
- [x] SSH access, nano and i2c-tools added to the image
- [x] Build and flash automated in a single script
- [x] DPI display driven at 1024×600 through the RGB LCD HAT
- [x] Display configuration baked into the image via `RPI_EXTRA_CONFIG`
- [ ] GT9271 touch panel over I²C
- [ ] Qt layer integrated, image built with a graphics stack
- [ ] Project-specific layer and image recipe
- [ ] STM32 ↔ Raspberry Pi UART protocol
- [ ] STM32 firmware: LTDC, instrument cluster rendering
- [ ] CAN reception on the STM32, CAN packet simulator on the PC
