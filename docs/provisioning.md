# Provisioning and boot state

The module's QSPI firmware stays stock (UEFI 36.4.3, JetPack 6
generation): the bootloader on disk is GRUB, so no NVIDIA firmware
feature (rootfs A/B, L4TLauncher) is used or needed, and no QSPI
reflash is ever required.

## Boot design

UEFI's per-device boot entry runs `EFI/BOOT/BOOTAA64.efi` from the
disk's ESP — GRUB, built by this system. GRUB's policy, in order:

1. **USB first**: if any attached drive carries `/nerves-usb-boot.cfg`
   (the provisioning stick does), source it and boot the stick.
2. **A/B**: boot the slot selected by `EFI/BOOT/grubenv` on the ESP.
   `next_entry` (set by an upgrade) wins exactly once and is cleared
   before the attempt, so a crash + watchdog reset falls back to
   `saved_entry` — that is the revert mechanism. Validation
   (`nerves-validate` → fwup ops `validate`) promotes the running slot
   to `saved_entry`.
3. **Degraded defaults**: a missing/corrupt grubenv boots slot A; a
   slot whose kernel fails to load falls back to the other slot
   (`fallback` in grub.cfg).

All grubenv writes are whole-1024-byte-file fwup resource writes
(upgrade tasks in fwup.conf, validate/revert in fwup-ops.conf). Nothing
else on the device mutates boot state; there are no UEFI variables,
retry counters, or partition renames involved.

The kernel DTB ships per-slot, padded with free space at build time
(post-createfs.sh): the UEFI firmware applies its device-tree overlays
into the blob GRUB installs and fails without room (`FDT_ERR_NOSPACE`),
which surfaces as "Invalid header detected on UEFI supplied FDT" and an
empty DTB.

## Writing a new device — the two supported procedures

These are the only supported ways to put this firmware on an internal
disk. Do not improvise transports (device-side staging on unknown
media, ad-hoc network copies): multi-gigabyte payloads must be
verifiable at every hop, and both procedures below are.

### Flashing a new board

A board that has never run this system (fresh from NVIDIA/Waveshare,
possibly with JetPack on its NVMe) is flashed with procedure A below,
plus one extra step: until the internal disk carries this system's
GRUB, nothing defers to the stick automatically, and a JetPack install
on the NVMe outranks it. On the first boot only, pick the USB drive by
hand: Esc at power-on -> Boot Manager -> the USB entry (drivable over
the debug UART, ttyTCU0 @ 115200). Every flash after that is
hands-off: the stick wins automatically whenever it is attached.

### Procedure A: offline media provisioning (factory path)

The provisioning media carries both the bootable system and the payload.

1. On the host: write a USB drive with the provisioner task —
   `fwup -a -t complete-provisioner -i <fw> -d /dev/rdiskN`. Identical
   to `complete` except: provisioner GPT names/labels (`prov_*`,
   `PROVA`), the stick boot config, and the data partition becomes a
   FAT32 "STAGING" volume the host can write.
2. The STAGING volume mounts automatically; copy the target's `.fw`
   onto it and verify: `shasum -a 256` of the copy must match the
   original before ejecting.
3. Boot the device with the drive attached. No menus: the internal
   disk's GRUB defers to the stick automatically (policy step 1), and
   if the internal disk has no working bootloader at all, UEFI's boot
   list falls through to the stick's own GRUB.
4. On the device: `umount /root` if mounted, then
   `fwup -a -t complete -i /path/to/staged.fw -d /dev/nvme0n1
   --enable-trim`. Local file, no network.
5. Power off, remove the drive, boot. (Leaving the drive attached is
   safe — provisioner partitions have distinct names and labels — but
   it will keep winning the boot, by design.)

### Procedure B: online full reflash (reachable device, no media)

The application exposes a second ssh_subsystem_fwup instance named
`fwup_provision` bound to the internal disk with the `complete` task:

    ssh -s nerves@<ip> fwup_provision < firmware.fw

SSH's transport integrity covers the stream; fwup verifies as it
applies. `require-unmounted-destination` makes the task refuse on a
system booted from the target disk — so this only works from a
media-booted system (procedure A's step 3) or another OS, by design.
Routine A/B upgrades continue to use `mix upload` (the standard `fwup`
subsystem); procedure B is only for layout changes and factory resets.

### Rules

- Verify a hash after every copy of a firmware archive; sizes lie.
- Never stage payloads on device-formatted partitions of unknown media.
- Layout-changing firmware must never ship via `mix upload` — the
  upgrade task would write at the old offsets. Use procedure A or B.

## Upgrade / revert lifecycle

1. `mix upload` → fwup `upgrade.a`/`upgrade.b` writes the inactive
   slot, refreshes the ESP's GRUB files, and writes `grubenv-next-*`
   as its final resource (an interrupted upgrade therefore still boots
   the old slot). The ssh subsystem reboots on success.
2. First boot of the new slot consumes `next_entry`. Until validation,
   any reboot or crash boots the old slot again.
3. The application health-checks, then runs `/usr/sbin/nerves-validate`
   → fwup ops `validate` sets `nerves_fw_validated=1` and promotes
   `saved_entry`.
4. Explicit rollback: fwup ops `revert` (flips both the Nerves
   metadata and `saved_entry`), then reboot.

Bench acceptance for any boot-path change: good upgrade → validate →
sticks; upgrade then power-pull mid-write → old slot boots; upgrade to
a crashing image → watchdog reset → old slot boots with no
intervention; unhealthy-but-booting upgrade → no validate → next
reboot returns to the old slot.

## Boot-chain gotchas

- Every bootable disk needs an ESP with GRUB at
  `EFI/BOOT/BOOTAA64.efi` plus `grub.cfg`; UEFI's auto-created disk
  entry runs only that default path.
- The DTB padding above is load-bearing. A stock (unpadded) DTB boots
  fine through loaders that expand it at runtime, and produces a
  hung, console-less kernel through any loader that installs it
  exactly-sized.
- The UEFI Shell (reachable via the boot menu, or `efibootmgr
  --bootnext 0007` from Linux — BDS variable writes work on this
  firmware) can chainload any EFI binary from any FAT for bring-up
  experiments: `FSn:\path\to\file.efi`.
- The UEFI menu and shell are fully drivable over the debug UART
  (ttyTCU0, 115200): ESC to enter the menu, arrow keys + Enter,
  F10 = ESC[21~. Serial input to the shell must be paced (~20 ms per
  character) or characters drop.
