#!/bin/bash
# Build a Jetson Nano eMMC mass-flash tarball with the cface dual-HDMI DTB baked in.
# Output: MMDDHHMM-emmc.tbz2 in the repo root.

set -e

image_name=jetson-nano-rootfs-image
docker build --platform linux/arm64 -t $image_name ./target

container_name=temp-container
docker export $(docker create --name $container_name $image_name) -o rootfs.tar
docker rm $container_name

builder_image_name=jetson-nano-builder
docker build --platform linux/arm64 -t $builder_image_name ./packager

docker run --rm -v "$(pwd):/host" --privileged $builder_image_name
