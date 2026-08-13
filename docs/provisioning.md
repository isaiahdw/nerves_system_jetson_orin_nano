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

## Writing a new device

1. QSPI: a stock JetPack-6-generation firmware (36.x) works as-is. No
   reflash needed for name-swap A/B.
2. Disk: `fwup -a -t complete -i <fw> -d <disk>` (USB stick or NVMe).
   The image is self-contained: ESP + L4TLauncher included.
3. Never leave two disks written from this image attached at once — they
   carry identical PARTUUIDs and `root=` resolution races.

## Slot switching today (redundancy off)

L4TLauncher boots the partition GPT-named `APP`, always. After a fwup
`upgrade` or `revert`, run `/usr/sbin/nerves-uefi-sync` before rebooting:
it swaps the `APP`/`APP_b` names on p2/p3 to match `nerves_fw_active`.
A bad slot does NOT fail over automatically — recovery from a
non-booting slot means the UEFI menu or reflashing. This is interim
until firmware redundancy is enabled.

## Enabling firmware rootfs A/B (future)

- The documented NVIDIA path: reflash with `ROOTFS_AB=1
  ROOTFS_RETRY_COUNT_MAX=3` using NVIDIA's flash tools from recovery
  mode (x86 Linux host required).
- The UEFI 36.4.3 setup menu has **no** redundancy toggle (checked:
  Device Manager → NVIDIA Configuration → Boot Configuration).
- `RootfsRedundancyLevel` exists as a **volatile** UEFI variable;
  rewriting it non-volatile from Linux requires deleting it first
  (`chattr -i` + `rm` on efivarfs, then create with NV attrs) and it is
  unverified whether the firmware honors the override at next boot.
  Experiment before relying on it.
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
