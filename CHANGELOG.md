# Changelog

## v0.1.0 (unreleased)

Initial system for the Jetson Orin Nano 4GB (Waveshare
JETSON-ORIN-IO-BASE / NVIDIA devkit carriers). Jetson Linux r39.2
kernel (6.8.12) with NVIDIA's out-of-tree GPU modules and DT; GRUB
(arm64-efi) boot from NVMe with grubenv-based A/B, automatic fallback
for unvalidated slots, and USB-first provisioning; CUDA 13.2 /
TensorRT 10.16 userland; RTL8822CE WiFi (rtw88), Bluetooth, RTL8168
ethernet, ttyTCU0 console, f2fs data partition with auto-expand.
