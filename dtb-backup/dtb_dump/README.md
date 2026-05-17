# Jetson Nano (cface-desktop) Device Tree Backup

Captured: $(date -u +%FT%TZ) UTC
Host: cface-desktop (114.32.210.136:8222)
Board: NVIDIA Jetson Nano Developer Kit, p3449-0000-b00 + p3448-0002-b00 (eMMC)
L4T: R32.7.1 (JetPack 4.6.1)
DTB build time (embedded): Jan 4 2023 10:02:03 (custom build)

## Files

### Partition images (full 1 MiB, with Tegra wrapper at offset 0x000-0x3FF)
- `slotA_full.bin` — exact byte-for-byte dump of /dev/mmcblk0p2 (DTB partition)
- `slotB_full.bin` — exact byte-for-byte dump of /dev/mmcblk0p6 (DTB-1 backup slot)

These can be `dd`'d straight back into the same partitions to bit-exactly
restore the bootloader's DTB. Both slots are identical (`cmp -s slotA_full.bin slotB_full.bin`).

### Raw FDT binaries (just the device-tree content, what flash.sh / dtc expect)
- `slotA.dtb` — extracted from slotA at offset 0x400, truncated to FDT totalsize
- `slotB.dtb` — same for slotB (identical to slotA)
- `original.dtb` — factory `/boot/dtb/kernel_tegra210-p3448-0002-p3449-0000-b00.dtb`
                  for diff reference

### Decompiled (.dts) for inspection
- `slotA.dts`, `slotB.dts`, `original.dts`

### Live snapshot (from /proc/device-tree, kernel-loaded)
- `live.dtb`, `live.dts` — what the running kernel sees; equals slotA + cboot-injected
  fields (MAC address, EEPROM data, serial, etc.). Don't flash this back as-is to a
  new board — the injected values are board-specific.

## How to use on a fresh L4T image

For `flash.sh` workflow on a host PC running JetPack:

```
cp slotA.dtb \
   Linux_for_Tegra/kernel/dtb/tegra210-p3448-0002-p3449-0000-b00.dtb
# Then flash normally:
sudo ./flash.sh jetson-nano-emmc mmcblk0p1
```

flash.sh will wrap the DTB with the Tegra boot header and write it to the
DTB partitions (slot A + slot B). Do NOT use `*_full.bin` here — flash.sh
adds its own header.

For in-place upgrade on a running unit (skip flash, just replace DTB):

```
sudo dd if=slotA_full.bin of=/dev/mmcblk0p2 bs=1M
sudo dd if=slotA_full.bin of=/dev/mmcblk0p6 bs=1M
sync && sudo reboot
```

⚠️ This is the destructive path — keep current.bin backups first.

## Known customizations vs factory DTB

Compared to `/boot/dtb/kernel_tegra210-p3448-0002-p3449-0000-b00.dtb`,
this DTB enables dual-HDMI:
- `gpio-225` labelled `hdmi2.0_hpd` (the second HDMI's hot-plug detect)
- Both head0+SOR1 and head1+SOR0 active at boot
- See `original.dts` vs `slotA.dts` for line-by-line diff

