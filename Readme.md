# Jetson Nano Image (cface fork)

> **Fork purpose.** Bake the dual-HDMI device tree blob from the deployed `cface-desktop` Jetson Nano into a fresh L4T image so we can flash replacement / spare units without re-doing the hardware-matching DTB by hand.

Local Docker pipeline only — the upstream GitHub Actions / `create-image.sh` flow has been removed; everything runs from your machine via `./make-image.sh`.

## Fork — what's different from upstream

The hardware in the field is a Jetson Nano eMMC carrier modified from the stock DP+HDMI layout to **dual HDMI**. The matching customised device tree (built `Jan 4 2023 10:02:03`) lives on the unit's eMMC DTB partition; if a new image is flashed with stock L4T DTB, the second HDMI does not light up. This fork drops that customised DTB into the BSP at packaging time.

### Source of the DTB

Extracted from `cface-desktop` (`/dev/mmcblk0p2`, FDT offset `0x400`, 219 257 bytes) on 2026-05-16. See [`AGENT.md`](AGENT.md) for the full host runbook and [`dtb-backup/dtb_dump/README.md`](dtb-backup/dtb_dump/README.md) for the extraction details and slot-A/B verification.

- Pinned binary: `packager/custom-dtb/tegra210-p3448-0002-p3449-0000-b00.dtb`
- sha256: `fd0d4179c7ec11686ab85d440c09ea4371db08c6aec419e10565b709f54c8849`

### Approach

Inject the DTB at the point where the L4T BSP is unpacked, *before* `nvmassflashgen.sh` is invoked, inside `packager/Dockerfile`. Two filenames are overwritten because L4T scripts reference both with and without the `kernel_` prefix:

```
Linux_for_Tegra/kernel/dtb/tegra210-p3448-0002-p3449-0000-b00.dtb
Linux_for_Tegra/kernel/dtb/kernel_tegra210-p3448-0002-p3449-0000-b00.dtb
```

`packager/build.sh` runs `nvmassflashgen.sh` with `FAB=300`, which makes `process_board_version` in `p3448-0000.conf.common` pick `dtbfab=b00` — the file we overwrote — and produces an `mfi_jetson-nano-emmc.tbz2` whose DTB partition will boot with the dual-HDMI configuration.

The `target/Dockerfile` is **unchanged**. The custom DTB does not need to live in the rootfs because cboot on eMMC reads from the DTB partition, not `/boot/dtb/`. (If we later need a matching `/boot/dtb/` for OTA/debug parity, add a `COPY` there too.)

### Verifying the injection (no Jetson required)

```shell
docker buildx build --platform linux/arm64 --load -t jetson-nano-builder ./packager

docker run --rm --platform linux/arm64 jetson-nano-builder sh -c \
  'sha256sum /tmp/Linux_for_Tegra/kernel/dtb/tegra210-p3448-0002-p3449-0000-b00.dtb \
             /tmp/Linux_for_Tegra/kernel/dtb/kernel_tegra210-p3448-0002-p3449-0000-b00.dtb'
# Both should print fd0d4179c7ec11686ab85d440c09ea4371db08c6aec419e10565b709f54c8849
```

### Building the image end-to-end

```shell
./make-image.sh
# → MMDDHHMM-emmc.tbz2 (Jetson Nano eMMC mass-flash bundle with cface dual-HDMI DTB)
```

This:
1. builds the rootfs Docker image from `./target` (`Ubuntu 20.04 + nvidia-l4t-*` packages),
2. exports it to `rootfs.tar`,
3. builds the packager Docker image from `./packager` (downloads L4T R32.7.4 BSP, copies in the custom DTB),
4. runs the packager with `--privileged` mounting the repo root at `/host`, where `packager/build.sh` invokes `nvmassflashgen.sh` and writes the result back.

Validate the produced `.tbz2` on a spare Nano without touching any unit's eMMC: see [`BOOT-TEST.md`](BOOT-TEST.md). The flow uses NVIDIA's RCM mode to load kernel + DTB into the Jetson's RAM over USB — the eMMC is not written, power-cycle reverts to the previous contents. Includes an OrbStack recipe for Apple Silicon Macs.

### Updating the DTB

If the field hardware customisation changes again, re-extract slotA.dtb from the donor unit (see `AGENT.md → DTB Backup`) and overwrite `packager/custom-dtb/tegra210-p3448-0002-p3449-0000-b00.dtb`. The sha256 in this Readme should be updated to match.

### Default rootfs credentials

Inherited from the upstream `target/Dockerfile`:

```
user: jetson
pass: jetson
```

Change these in `target/Dockerfile` before flashing into production.

---

## Attribution

This repository is a fork of [Eden-Sun/jetson-nano-image-maker](https://github.com/Eden-Sun/jetson-nano-image-maker), itself built on [pythops/jetson-nano-image](https://github.com/pythops/jetson-nano-image) ([blog post](https://pythops.com/post/create-your-own-image-for-jetson-nano-board.html)).

### NVIDIA references

- <https://developer.nvidia.com/embedded/linux-tegra>
- <https://docs.nvidia.com/jetson/l4t/index.html#page/Tegra%20Linux%20Driver%20Package%20Development%20Guide/updating_jetson_and_host.html>
- <https://docs.nvidia.com/jetson/l4t/index.html#page/Tegra%20Linux%20Driver%20Package%20Development%20Guide/flashing.html#wwpID0E0CM0HA>

## License

MIT
