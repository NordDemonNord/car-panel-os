# Boot time baseline

Reference measurements taken before Qt integration.
Compare against this after adding the graphics stack.

## Configuration

| Item | Value |
|---|---|
| Date | 2026-09-05 |
| Image | carpanel-image |
| Distro | carpanel 1.0 (poky-based) |
| Init system | systemd 255.21 |
| Kernel | 6.6.63-v8 |
| Machine | raspberrypi4-64 |
| Display | KMS/DRM, vc4-kms-dpi-generic |
| Qt | not installed |

## Total

Startup finished in 1.589s (kernel) + 3.438s (userspace) = 5.027s
multi-user.target reached after 2.187s in userspace.


Note: firmware and bootloader stages are not covered by systemd-analyze.
The VideoCore stage (bootcode -> start4.elf -> kernel handoff) adds several
seconds that must be measured separately.

## Slowest units (systemd-analyze blame)

1.371s sshdgenkeys.service
824ms dev-mmcblk0p2.device
303ms systemd-udev-trigger.service
250ms ldconfig.service
195ms systemd-machine-id-commit.service
160ms systemd-journald.service
146ms systemd-sysusers.service
140ms systemd-fsck-root.service
139ms systemd-tmpfiles-setup.service
137ms systemd-resolved.service


`sshdgenkeys.service` is the slowest unit but does not appear in the critical
chain — it runs in parallel and does not block startup. It only runs on first
boot of a freshly flashed image, when no host keys exist in the rootfs.

## Critical chain

multi-user.target @2.187s
└─systemd-logind.service @2.061s +124ms
└─basic.target @2.025s
└─sockets.target @2.024s
└─sshd.socket @2.005s +17ms
└─sysinit.target @1.996s
└─systemd-resolved.service @1.856s +137ms
└─systemd-tmpfiles-setup.service @1.687s +139ms
└─local-fs.target @1.675s
└─boot.mount @1.658s +15ms
└─dev-mmcblk0p1.device @1.296s


The chain bottoms out at `dev-mmcblk0p1.device` — userspace spends its first
1.3 seconds waiting for the SD card partition to appear. This is hardware and
udev latency, not service configuration.

## Display pipeline (kernel log)

[ 1.033862] [drm] Initialized vc4 0.0.0 for gpu on minor 0
[ 1.147904] vc4-drm gpu: [drm] fb0: vc4drmfb frame buffer device
[ 1.180987] [drm] Initialized v3d 1.0.0 for fec00000.v3d on minor 1


Console framebuffer is available 1.15s after kernel start, with no deferred
probe retries. `/dev/dri/` contains card0 (vc4), card1 (v3d) and renderD128.

## Known issues

- No RTC on the Pi: system clock starts at epoch, journal timestamps are
  meaningless until timesyncd or an external time source kicks in.
- `busybox-syslog` and `busybox-klogd` run alongside `systemd-journald`.
  Two loggers writing the same data; leftover from the sysvinit setup.
