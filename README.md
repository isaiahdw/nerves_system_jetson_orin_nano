# Nerves System: NVIDIA Jetson Orin Nano

Nerves system for the NVIDIA Jetson Orin Nano. Boots via the module's
QSPI UEFI firmware from NVMe, with GRUB as the on-disk boot manager. ** This is still a work in progress**

| Hardware | Identity |
|---|---|
| Module | NVIDIA Jetson Orin Nano 4GB, p3767-0004 |
| Carrier | Waveshare JETSON-ORIN-IO-BASE (standard, single RTL8168 ethernet) |
| Flashed/boots as | NVIDIA devkit carrier (p3768) — the Waveshare board is devkit-compatible |
| Boot spec (module EEPROM) | `3767-301-0004-H.1-1-1-jetson-orin-nano-devkit-super` |

Portability: nothing load-bearing is Waveshare-specific. The system
targets the Orin Nano module on devkit-compatible carriers (it boots the
NVIDIA p3768 carrier device tree) and should run on the official devkit
with an NVMe unmodified. Hardware verification has only been done on the
Waveshare carrier.

| Feature | Status |
|---|---|
| Boot to IEx (ttyTCU0 console) | working — NVMe via GRUB, ~10 s |
| A/B updates with automatic failover | working, hardware-verified (crash of an unvalidated slot falls back on its own) |
| USB-first provisioning boot | working — an attached provisioner stick boots with no menus |
| GPU (CUDA 13.2 / TensorRT 10.16, nvgpu OOT modules) | working — TensorRT engine build + inference verified on hardware |
| Ethernet (RTL8168, `r8169`) | working, DHCP via VintageNet |
| WiFi (RTL8822CE, `rtw88`) | working, WPA2 association + DHCP |
| Bluetooth (btusb/btrtl) | working — hci0 registers, firmware loads (kernel patch un-ignores 0bda:c822) |
| Watchdog + heart | armed (`/dev/watchdog0`) |
| App data partition (f2fs, auto-format/expand) | working |
| cpufreq + thermal | working (tegra cpufreq, tj-thermal; schedutil default governor) |
| USB audio (ALSA) | card registers; playback untested |
| 40-pin header UARTs (`ttyTHS1`/`ttyTHS2`) | exposed under the `-nv` DT |
| USB camera (UVC) | modules ready; untested |

## Boot architecture

The NVIDIA boot chain (BootROM → MB1/MB2 → UEFI) lives in the module's
QSPI-NOR flash and never changes. UEFI's disk boot entry runs
`EFI/BOOT/BOOTAA64.efi` from the ESP — GRUB (arm64-efi), built by this
system with `grub/early.cfg` embedded. GRUB's policy, in order:

1. **USB first** — an attached drive carrying `/nerves-usb-boot.cfg`
   (the provisioning stick) boots instead of the internal disk.
2. **A/B** — boot the slot selected by `EFI/BOOT/grubenv`. An upgrade
   sets GRUB's one-shot `next_entry`, which is cleared before the new
   slot is attempted: if it crashes, the watchdog reset boots the
   validated slot. Validation (fwup ops `validate`, keyed on the
   *running* slot) promotes `saved_entry`.
3. **Degraded defaults** — missing/corrupt grubenv boots slot A; a slot
   whose kernel fails to load falls back to the other slot.

All boot state is the 1 KB `grubenv` file, written exclusively by fwup
as whole-file resources (`fwup.conf` upgrades, `fwup-ops.conf`
validate/revert). There are no UEFI variables, retry counters, or
partition renames in the loop.

The kernel DTB ships per-slot and is padded with free space at build
time (`post-createfs.sh`): the UEFI firmware applies its device-tree
overlays into the installed blob and fails without room, which surfaces
as an empty DTB and a dead board.

Disk layout (`fwup_include/fwup-common.conf`):

| Partition | Name | FS | Contents |
|---|---|---|---|
| — | (raw @512 KB) | U-Boot env format | Nerves metadata (no U-Boot involved) |
| p1 | `esp` | FAT32 (ESP) | `EFI/BOOT/`: GRUB, `grub.cfg`, `grubenv` |
| p2 | `boot_a` | FAT32 (BOOTA) | slot A: `boot/Image`, padded DTB |
| p3 | `boot_b` | FAT32 (BOOTB) | slot B: same |
| p4 | `rootfs_a` | squashfs/erofs | Nerves rootfs A |
| p5 | `rootfs_b` | squashfs/erofs | Nerves rootfs B |
| p6 | `data` | f2fs | application data, expands to fill disk |

The provisioning stick uses the same offsets with `prov_*` partition
names, `PROV*` labels, and distinct GUIDs, so nothing on it can ever be
mistaken for the internal disk (or vice versa).

## Updates

`mix upload` → fwup `upgrade.a`/`upgrade.b` writes the inactive slot,
refreshes the ESP's GRUB files, and flips `grubenv` as its final
resource — an interrupted upgrade still boots the old slot. The
application must run `/usr/sbin/nerves-validate` only after real health
checks pass; until then any reboot or crash returns to the previous
slot. No success callback or post-fwup hook is needed.

Full lifecycle, provisioning procedures, and bench-acceptance tests:
`docs/provisioning.md`.

## Kernel

NVIDIA's Jetson Linux r39.2 kernel (JetPack 7.2): the Ubuntu noble tree
with Tegra patches, 6.8.12, pinned to the same commit meta-tegra master
uses. Config = arm64 defconfig + `linux/nerves.config` (squashfs and
EROFS roots both built in). The boot DT is NVIDIA's
`tegra234-p3768-0000+p3767-0004-nv.dtb` built by `package/nvidia-oot`
alongside the out-of-tree GPU modules (nvidia-oot, nvgpu, hwpm), so
kernel, modules, and DT are all r39.2. GPU userspace comes from
`package/tegra-libs` (BSP tarball) and `package/tensorrt-runtime`
(JetPack apt debs, pruned to the sm86 builder resource Orin uses).

## Building

Same workflow as the other systems in this family. With Nerves 2.0
tooling the system builds as an artifact:

```sh
mix nerves.artifact.build nerves_system_jetson_orin_nano
```

On an Apple Silicon host the build runs in Apple's `container` runtime
automatically, in a per-package volume. Host-side firmware assembly
(Nerves 2.0) needs `sqfstar`/`mkfs.erofs`; note that Homebrew's
mkfs.erofs multithreading is broken on macOS — use a
`--disable-multithreading` build.

## Writing an image

Two supported procedures only — offline provisioning stick or the
`fwup_provision` ssh subsystem — documented in `docs/provisioning.md`.

## Console

`ttyTCU0` (Tegra Combined UART) @ 115200 on the carrier's debug UART
header, shared with the boot firmware. The 40-pin header UARTs
(`ttyTHS1`/`ttyTHS2`) are left free for applications.
