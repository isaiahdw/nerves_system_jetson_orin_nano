# UEFI boot application

`BOOTAA64.efi` is NVIDIA's **L4TLauncher**, the OS loader every Jetson
Orin boot path goes through. UEFI's per-device boot entries run
`EFI/BOOT/BOOTAA64.efi` from a disk's ESP; L4TLauncher then finds the
`APP`/`APP_b` boot partition and processes `boot/extlinux/extlinux.conf`.
A disk without an ESP carrying this binary is not bootable on its own —
the firmware's built-in boot entry only searches the device it is
associated with (observed on UEFI 36.4.3: a USB stick with a valid `APP`
partition is ignored by the NVMe's L4TLauncher instance).

Provenance: copied unmodified from a stock JetPack installation's `esp`
partition on the reference device (Orin Nano 4GB, L4T r36.4.3 firmware
generation, file dated 2024-05-16, sha256
`b14fa3623f4078d05573d9dcf2a0b46ea2ae07d6b75d9843f9da6ff24db13718`).
Built from NVIDIA's open-source edk2-nvidia (BSD-2-Clause-Patent):
https://github.com/NVIDIA/edk2-nvidia

When the QSPI firmware moves to the JetPack 7.2 generation (M2
provisioning), replace this with the r39.2 build from the L4T BSP and
update the hash here and in NOTICE.
