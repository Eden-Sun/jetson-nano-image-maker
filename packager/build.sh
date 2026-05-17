#!/bin/sh
# Runs inside the packager container. Produces the eMMC mass-flash bundle
# with the cface dual-HDMI DTB. FAB=300 selects dtbfab=b00 in
# Linux_for_Tegra/p3448-0000.conf.common.
set -e

mkdir -p /tmp/rootfs
tar -xf /host/rootfs.tar -C /tmp/rootfs

ROOTFS_DIR=/tmp/rootfs \
BOARDID=3448 BOARDSKU=0002 FAB=300 FUSELEVEL=fuselevel_production \
    ./nvmassflashgen.sh --no-root-check jetson-nano-emmc mmcblk0p1

mv mfi_jetson-nano-emmc.tbz2 "/host/$(date +%m%d%H%M)-emmc.tbz2"
echo "==> wrote /host/$(date +%m%d%H%M)-emmc.tbz2"
