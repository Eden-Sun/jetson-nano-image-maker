#! /bin/sh
tar -xvf /host/rootfs.tar -C /tmp/rootfs
ROOTFS_DIR=/tmp/rootfs BOARDID=3448 BOARDSKU=0002 FAB=200 FUSELEVEL=fuselevel_production  ./nvmassflashgen.sh --no-root-check jetson-nano-emmc mmcblk0p1
mv mfi_jetson-nano-emmc.tbz2 /host/$(date +"%m%d%H%M").tbz2