# Provisioning and boot-chain state

## Current provisioning state (the reference device)

- QSPI firmware: UEFI 36.4.3 (JetPack 6 generation), stock — never
  reflashed by this project.
- `RootfsRedundancyLevel` = 0: firmware-level rootfs A/B is **disabled**.
  Slot switching uses the GPT name swap (`nerves-uefi-sync`); there is no
  firmware failover on a bad boot.
- The NVMe carries the Nerves image (the stock JetPack install was lost
  during bring-up; restore, if ever wanted, via Waveshare's wiki image +
  SDK Manager recovery-mode flash).

## Writing a new device — the two supported procedures

These are the only supported ways to put this firmware on an internal
disk. Do not improvise transports (device-side staging on unknown
media, ad-hoc network copies): multi-gigabyte payloads must be
verifiable at every hop, and both procedures below are.

### Procedure A: offline media provisioning (factory path)

The provisioning media carries both the bootable system and the payload.

1. On the host: write a USB drive with the provisioner task —
   `fwup -a -t complete-provisioner -i <fw> -d /dev/rdiskN`. Identical
   to `complete` except the data partition becomes a FAT32 "STAGING"
   volume the host can write.
2. The STAGING volume mounts automatically; copy the target's `.fw`
   onto it and verify: `shasum -a 256` of the copy must match the
   original before ejecting.
3. Boot the device from the drive (UEFI Boot Manager or shell if the
   internal disk still outranks it; a direct EFI-stub launch with
   `root=/dev/sda4` avoids PARTUUID ambiguity when the internal disk
   carries the same image).
4. On the device: `umount /root` if mounted, then
   `fwup -a -t complete -i /path/to/staged.fw -d /dev/nvme0n1
   --enable-trim`. Local file, no network.
5. Power off, remove the drive, boot. Never leave the drive attached
   afterwards — it shares PARTUUIDs with the internal disk.

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
- Never stage payloads on device-formatted partitions of unknown media
  (silent flash corruption cost this project an evening).
- Layout-changing firmware must never ship via `mix upload` — the
  upgrade task would write at the old offsets.

## Slot switching today (redundancy off)

L4TLauncher boots the partition GPT-named `APP`, always. After a fwup
`upgrade` or `revert`, run `/usr/sbin/nerves-uefi-sync` before rebooting:
it swaps the `APP`/`APP_b` names on p2/p3 to match `nerves_fw_active`.
A bad slot does NOT fail over automatically — recovery from a
non-booting slot means the UEFI menu or reflashing. This is interim
until firmware redundancy is enabled.

## Enabling firmware rootfs A/B (procedure)

Order matters; the software half ships FIRST (it is dual-mode and safe
under redundancy-off):

1. In the image you will boot: dual-mode `nerves-uefi-sync`
   (name-swap at level 0, `nvbootctrl -t rootfs set-active-boot-slot`
   with canonical names when redundancy is on), health-gated
   `nerves-validate` wired into the application, and a factory task
   that populates BOTH slots (never enable redundancy with an empty
   APP_b - failover into it loops through recovery).
2. Reflash QSPI from an x86 Linux host in recovery mode:
   `sudo ROOTFS_AB=1 ROOTFS_RETRY_COUNT_MAX=3 ./flash.sh ...` (or the
   l4t_initrd_flash equivalent). The UEFI menu has no redundancy
   toggle and runtime variable rewrites are unproven - reflash is the
   real path.
3. Confirm: `nvbootctrl -t rootfs dump-slots-info` shows redundancy
   on, both slots normal, retries 3.
4. From then on GPT names stay canonical (p2=APP, p3=APP_b, no more
   swapping); L4TLauncher picks the slot from UEFI state.

Rules once redundancy is on:
- Never verify early in boot (nerves-boot-success refuses; verify
  lives only in nerves-validate, after application health checks) -
  early verify marks a bad image good and kills failover.
- Never hand-edit slot variables in the UEFI menu except for recovery.
- Bench acceptance: corrupt the active slot -> ~3 failed boots ->
  firmware boots the other slot; good upgrade -> sync -> reboot ->
  validate; unhealthy-but-booting upgrade -> no validate -> retries
  exhaust -> failover (or explicit revert).

## Background: why reflash is the enable path

- The documented NVIDIA path: reflash with `ROOTFS_AB=1
  ROOTFS_RETRY_COUNT_MAX=3` using NVIDIA's flash tools from recovery
  mode (x86 Linux host required).
- The UEFI 36.4.3 setup menu has **no** redundancy toggle (checked:
  Device Manager → NVIDIA Configuration → Boot Configuration).
- Runtime enablement is **proven impossible on UEFI 36.4.3** (tested
  2026-08-13, three ways): efivarfs delete/create from Linux fails
  (`einval`/`erofs`, firmware variable policy), the UEFI Shell's
  `setvar` fails the same way ("Unable to set" for both delete and
  NV-create; contrast the Rootfs status variables, which are writable),
  and files staged in the ESP at `EFI/NVDA/Variables/` are consumed by
  the firmware at boot but not honored for this variable. The QSPI
  reflash is the only path.
- Once enabled: slot selection moves to RootfsStatusSlotA/B (GUID
  781e084c-a330-417c-b678-38e696380cb9) + retry counters in a Tegra
  scratch register; `nerves-uefi-sync` refuses the name swap in that
  state, and the nvbootctrl-based path (set-active + verify) must be
  implemented first. Also populate slot B before enabling: a factory
  image has an empty `APP_b`, and firmware failover into an empty slot
  loops through recovery.

## Boot-chain gotchas (hardware-verified)

- Every bootable disk needs the ESP with L4TLauncher at
  `EFI/BOOT/BOOTAA64.efi` — see `uefi/README.md`. L4TLauncher instances
  search only the device they were launched from.
- After repeated boot failures the firmware latches **OS chain A
  status = Unbootable** (NV variable) and every subsequent launch skips
  Direct Boot and attempts Recovery Boot. Reset it in the UEFI menu:
  ESC at boot → Device Manager → NVIDIA Configuration → L4T
  Configuration → OS chain A status → Normal → F10 → Y (discard the
  unrelated "Grace Configuration" form with D if it blocks the save).
- The UEFI menu is fully drivable over the debug UART (ttyTCU0,
  115200): ESC to enter, arrow keys + Enter, F10 = ESC[21~.
