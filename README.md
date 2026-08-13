# Nerves System: NVIDIA Jetson Orin Nano

Nerves system for the NVIDIA Jetson Orin Nano. Boots via the module's
QSPI UEFI firmware from NVMe.

| Hardware | Identity |
|---|---|
| Module | NVIDIA Jetson Orin Nano 4GB, p3767-0004 |
| Carrier | Waveshare JETSON-ORIN-IO-BASE (standard, single RTL8168 ethernet) |
| Flashed/boots as | NVIDIA devkit carrier (p3768) — the Waveshare board is devkit-compatible |
| Boot spec (module EEPROM) | `3767-301-0004-H.1-1-1-jetson-orin-nano-devkit-super` |

Portability: nothing load-bearing is Waveshare-specific. The system
targets the Orin Nano module on devkit-compatible carriers (it boots the
NVIDIA p3768 carrier device tree) and should run on the official devkit
with an NVMe unmodified, except `rootfs_overlay/etc/nv_boot_control.conf`
whose TNSPEC is hard-coded for the 4GB module SKU (p3767-0004) - an 8GB
module (p3767-0003) needs that line adjusted. Hardware verification has
only been done on the Waveshare carrier.

**Status: boots on hardware.** Verified 2026-08-12 on an Orin Nano 4GB
on the Waveshare JETSON-ORIN-IO-BASE carrier: standalone boot from NVMe
to IEx in ~8 s, no removable media.

| Feature | Status |
|---|---|
| Boot to IEx (ttyTCU0 console) | working (USB and NVMe, hardware-verified) |
| Ethernet (RTL8168, `r8169`) | working, DHCP via VintageNet |
| WiFi (RTL8822CE, `rtw88`) | working, WPA2 association + DHCP |
| USB audio (ALSA) | card registers; playback untested |
| Watchdog + heart | armed (`/dev/watchdog0`) |
| App data partition (f2fs, auto-format/expand) | working |
| A/B updates (upgrade + revert, both directions) | working, hardware-verified — **no automatic failover**, see below |
| Per-boot firmware handshake (`nvbootctrl verify`) | working (`nerves-boot-success` via erlinit) |
| efivarfs | mounted by erlinit |
| Bluetooth (btusb/btrtl) | working — hci0 registers, firmware loads (kernel patch un-ignores 0bda:c822) |
| cpufreq + thermal | working (tegra cpufreq, tj-thermal; schedutil default governor) |
| 40-pin header UART | exposed as `ttyS*`/`ttyAMA0` under the upstream DT; mapping unverified (M3) |
| USB camera (UVC) | modules ready; untested, no camera attached yet (M3) |
| GPU (CUDA/TensorRT) | not started (M4) |

## A/B updates: what works and what doesn't

Firmware rootfs redundancy is deliberately **off** (`RootfsRedundancyLevel=0`,
matching the QSPI as shipped), so L4TLauncher always boots the partition
GPT-named `APP`. Slot switching is a name swap done by
`/usr/sbin/nerves-uefi-sync` after fwup runs. Verified on hardware:
upgrade A→B and B→A over ssh, revert in both directions, and per-boot
success marking (without which the firmware latches the chain
`Unbootable` after ~3 boots — recovery procedure in
`docs/provisioning.md`).

**No automatic failover exists in this mode.** A slot that passes the
name swap but fails to boot stays selected until manual intervention
(UEFI menu or reflash). That is the accepted interim trade-off until
firmware redundancy (`ROOTFS_AB=1`) is provisioned; treat "A/B works" as
"updates and reverts work", not "bad firmware self-heals".

**Application contract:** the update flow must run `nerves-uefi-sync`
after fwup succeeds and only reboot when it exits 0. The ssh update path
is `ssh_subsystem_fwup` (what `nerves_ssh`/`mix upload` use), which reads
its own application environment:

```elixir
config :ssh_subsystem_fwup,
  success_callback: {MyApp.Firmware, :finish_update, []}
# finish_update/0: run /usr/sbin/nerves-uefi-sync; reboot only on exit 0.
```

Skipping the hook reboots into the old slot while the Nerves metadata
claims the new one.

Bring-up notes: the boot chain requires the ESP (see `uefi/README.md`);
`docs/provisioning.md` is the authoritative boot-chain reference,
including the `Unbootable`-latch recovery walkthrough.

## Boot architecture

Nothing bootloader-shaped ships in this image. The NVIDIA boot chain
(BootROM → MB1/MB2 → UEFI/L4TLauncher) lives in the module's QSPI-NOR
flash and is provisioned once with NVIDIA's tools. L4TLauncher picks a
boot partition by GPT *name* — `APP` (slot A) or `APP_b` (slot B), fixed
names — and reads `boot/extlinux/extlinux.conf` from it. The kernel boots
via its EFI stub.

Disk layout (`fwup_include/fwup-common.conf`):

| Partition | Name | FS | Contents |
|---|---|---|---|
| — | (raw @512 KB) | U-Boot env format | Nerves metadata (no U-Boot involved) |
| p1 | `esp` | FAT32 | `EFI/BOOT/BOOTAA64.efi` = L4TLauncher (see `uefi/README.md`) |
| p2 | `APP` | FAT32 | slot A: `boot/Image`, DTB, `boot/extlinux/extlinux.conf` |
| p3 | `APP_b` | FAT32 | slot B: same |
| p4 | `rootfs_a` | squashfs | Nerves rootfs A |
| p5 | `rootfs_b` | squashfs | Nerves rootfs B |
| p6 | `data` | f2fs | application data, expands to fill disk |

With firmware redundancy off (the current state), L4TLauncher boots the
partition GPT-named `APP`; `/usr/sbin/nerves-uefi-sync` swaps the
`APP`/`APP_b` names to match `nerves_fw_active` after fwup runs, and
`/usr/sbin/nerves-boot-success` (`nvbootctrl verify`) marks every boot
good so the firmware's retry counters reset. Firmware-level failover
arrives only with `ROOTFS_AB=1` provisioning — see
`docs/provisioning.md`.

## Kernel

NVIDIA's Jetson Linux r39.2 kernel (JetPack 7.2): the Ubuntu noble tree
with Tegra patches, 6.8.12, pinned to the same commit meta-tegra master
uses. Config = arm64 defconfig + `linux/nerves.config`. The DT is the
in-tree devkit DT (`tegra234-p3768-0000+p3767-0005`); each extlinux
config also has a `nerves-fwdt` entry that boots on the UEFI-provided DT
instead. The NVIDIA out-of-tree modules (nvgpu etc.) are not integrated
yet.

## Building

Same workflow as the other systems in this family:

```sh
mix deps.get
mix compile
```

On an Apple Silicon host the build runs in Apple's `container` runtime
automatically. The build volume is pinned by
`.nerves/artifacts/<name>/.container_id` — do not delete it, or the next
build starts from scratch (~hours). `tools/prune-build-volume.sh` reclaims
space inside the volume.

## Writing an image

Bring-up (USB stick; UEFI prefers removable media by default):

```sh
fwup -a -t complete -i <firmware>.fw -d /dev/diskN   # macOS: diskutil unmountDisk first
```

The same `complete` task writes the NVMe at provisioning time. QSPI
state, slot-switching mechanics, and boot-chain gotchas are in
`docs/provisioning.md`.

## Console

`ttyTCU0` (Tegra Combined UART) @ 115200 on the carrier's debug UART
header, shared with the boot firmware. The ESP32 driver board is on
`ttyTHS1` — never attach a console there.
