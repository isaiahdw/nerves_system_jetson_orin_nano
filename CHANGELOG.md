# Changelog

## v0.1.0 (unreleased)

Initial system: Jetson Linux r39.2 kernel (6.8.12), UEFI/L4TLauncher boot
from NVMe with an ESP carrying L4TLauncher and per-slot FAT boot
partitions (`APP`/`APP_b`), fwup A/B layout, RTL8822CE WiFi (rtw88),
RTL8168 ethernet, ttyTCU0 console. Hardware-verified on the Orin Nano
4GB / Waveshare JETSON-ORIN-IO-BASE: boots standalone from NVMe to IEx,
ethernet and WiFi up, watchdog armed, data partition auto-formats.
