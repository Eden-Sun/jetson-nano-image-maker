# Booting the built image without flashing eMMC

The mass-flash bundle this repo produces (`MMDDHHMM-emmc.tbz2`) is normally written to a Jetson's eMMC permanently. To **test a build without touching any unit's eMMC**, boot it via **RCM (Recovery Mode)**: the host PC loads the kernel + DTB over USB into the Jetson's RAM, the Jetson runs from RAM, power-cycle returns to whatever was already on eMMC.

## What you need

- A Jetson Nano eMMC board (ideally a cface-class spare — same dual-HDMI carrier as production). A stock unmodified Nano eMMC works too, but only one HDMI is wired so dual-HDMI cannot be fully observed there.
- micro-USB cable from the Jetson's micro-USB port to a Linux host. The L4T `flash.sh` and its bundled binaries (`tegrarcm`, `tegradevflash`, …) are Linux ELF executables — they do not run natively on macOS. See [§ macOS host via OrbStack](#macos-host-via-orbstack) below for the Apple-Silicon-friendly workaround.
- A jumper or jumper wire to short FRC pin (J50 pin 9) to GND (J50 pin 10) on the Nano carrier **before** applying power. Some carriers expose this as a button.
- A 5 V PSU for the Jetson.

## Step 1 — get the L4T BSP onto the Linux host

Use the BSP that's already inside our `jetson-nano-builder` image (saves a 1.5 GB re-download and guarantees the same dual-HDMI DTB is present):

```bash
# On the Linux host, with Docker running:
docker create --name extract-bsp jetson-nano-builder
docker cp extract-bsp:/tmp/Linux_for_Tegra ./Linux_for_Tegra
docker rm extract-bsp
```

If the builder image isn't on the host, rebuild it (`docker buildx build --platform linux/arm64 -t jetson-nano-builder ./packager`) or fetch the BSP fresh from NVIDIA:

```bash
wget https://developer.nvidia.com/downloads/embedded/l4t/r32_release_v7.4/t210/jetson-210_linux_r32.7.4_aarch64.tbz2
tar -xjf jetson-210_linux_r32.7.4_aarch64.tbz2
# Then inject the DTB manually:
cp packager/custom-dtb/tegra210-p3448-0002-p3449-0000-b00.dtb Linux_for_Tegra/kernel/dtb/
cp Linux_for_Tegra/kernel/dtb/tegra210-p3448-0002-p3449-0000-b00.dtb \
   Linux_for_Tegra/kernel/dtb/kernel_tegra210-p3448-0002-p3449-0000-b00.dtb
```

## Step 2 — verify the BSP has the dual-HDMI DTB

```bash
sha256sum Linux_for_Tegra/kernel/dtb/tegra210-p3448-0002-p3449-0000-b00.dtb
# Should print: fd0d4179c7ec11686ab85d440c09ea4371db08c6aec419e10565b709f54c8849
```

## Step 3 — put the Jetson in Force-Recovery mode

1. Power off the Jetson.
2. Short J50 pin 9 (FRC) to pin 10 (GND).
3. Plug micro-USB cable from Jetson to the Linux host.
4. Apply 5 V power to the Jetson.
5. On the Linux host, confirm the device is seen:

   ```bash
   lsusb | grep -i nvidia
   # Expected: NVIDIA Corp. APX  (USB ID 0955:7f21)
   ```

6. Remove the FRC jumper after power-on (it's only needed at boot).

## Step 4 — boot kernel + DTB from RAM (no eMMC writes)

```bash
cd Linux_for_Tegra
sudo BOARDID=3448 BOARDSKU=0002 FAB=300 FUSELEVEL=fuselevel_production \
    ./flash.sh --rcm-boot jetson-nano-emmc mmcblk0p1
```

flash.sh prints progress; after a few seconds the Jetson boots into the just-loaded image. eMMC remains untouched.

If your `flash.sh` does not advertise `--rcm-boot`:

```bash
./flash.sh --help 2>&1 | grep -i rcm
```

Fall back to the older `-k DTB` form which writes only the DTB partition (still less destructive than a full flash; sufficient to test the DTB change but eMMC's DTB slot does get overwritten):

```bash
sudo BOARDID=3448 BOARDSKU=0002 FAB=300 FUSELEVEL=fuselevel_production \
    ./flash.sh -k DTB jetson-nano-emmc mmcblk0p1
```

⚠️ This *does* write to eMMC. Use only if `--rcm-boot` isn't available and you accept overwriting the spare unit's DTB partition.

## Step 5 — verify dual-HDMI is live on the booted unit

Connect via serial UART (`/dev/ttyUSB0` 115200 8N1) or wait for the X session and SSH in (default upstream creds: `jetson` / `jetson`). Run:

```bash
# Both display heads should be probed:
dmesg | grep -E "tegradc.0|tegradc.1"
# Expected:
#   tegradc tegradc.0: disp0 connected to head0->/host1x/sor1
#   tegradc tegradc.1: disp1 connected to head1->/host1x/sor

# Custom GPIO label only exists with the dual-HDMI DTB:
sudo cat /sys/kernel/debug/gpio | grep hdmi
# Expected: gpio-225 (...|hdmi2.0_hpd) in  hi IRQ

# DTB build-time stamp confirms our customised dtb is in use:
strings /proc/device-tree/nvidia,dtbbuildtime 2>/dev/null || \
  cat /proc/device-tree/nvidia,dtbbuildtime
# Expected: Jan  4 2023  10:02:03
```

Plug a second HDMI cable into the second port; within 1 s `dmesg` should show new HPD/EDID activity from `tegradc.1` and `xrandr` should now list both outputs as connected.

## Cleanup

Power off the Jetson. If you used `--rcm-boot`, the unit is unchanged — next normal boot returns to whatever was on eMMC before.

## macOS host via OrbStack

If your dev machine is an Apple-Silicon Mac, run a small Ubuntu Linux machine inside [OrbStack](https://orbstack.dev/) and pass the Jetson's USB device into it. `flash.sh` then runs natively (the L4T BSP binaries are `aarch64` Linux ELFs — they run at full speed on M1/M2/M3 via OrbStack without Rosetta).

**1. Create an aarch64 Ubuntu machine**

```bash
orb create -a arm64 ubuntu:22.04 jetson-flash
orb -m jetson-flash sudo apt update
orb -m jetson-flash sudo apt install -y libxml2-utils lbzip2 python3 bzip2 wget usbutils sudo
```

**2. Copy the BSP (with the dual-HDMI DTB) into the machine**

OrbStack auto-mounts your Mac home as `/Users/<you>` inside the machine. Easiest is to extract from the already-built builder image on the Mac side, then `cp` into the machine.

On the Mac:

```bash
cd /Users/m1pro/witsper-projects/chowface
docker create --name extract-bsp jetson-nano-builder
docker cp extract-bsp:/tmp/Linux_for_Tegra ./Linux_for_Tegra
docker rm extract-bsp
```

Then in the OrbStack machine:

```bash
orb -m jetson-flash
# (or `ssh jetson-flash` once OrbStack adds the SSH alias)
cp -a /Users/m1pro/witsper-projects/chowface/Linux_for_Tegra ~/
cd ~/Linux_for_Tegra
sha256sum kernel/dtb/tegra210-p3448-0002-p3449-0000-b00.dtb
# Expect: fd0d4179c7ec11686ab85d440c09ea4371db08c6aec419e10565b709f54c8849
```

**3. Power the Jetson in Force-Recovery and attach the USB device to the Linux machine**

Same physical prep as the generic flow above (FRC pin shorted, micro-USB to Mac, power on).

Then expose the USB device to the OrbStack machine. Two ways:

- GUI: open OrbStack → Machines → `jetson-flash` → the USB devices panel → tick the NVIDIA APX device (VID `0955`, PID `7f21`).
- CLI: `orb usb attach 0955:7f21 jetson-flash` (exact subcommand may differ between OrbStack versions — run `orb usb --help`).

Confirm inside the machine:

```bash
orb -m jetson-flash lsusb | grep -i nvidia
# Expect: ID 0955:7f21 NVIDIA Corp. APX
```

**4. RCM boot from inside the Linux machine**

```bash
orb -m jetson-flash
cd ~/Linux_for_Tegra
sudo BOARDID=3448 BOARDSKU=0002 FAB=300 FUSELEVEL=fuselevel_production \
    ./flash.sh --rcm-boot jetson-nano-emmc mmcblk0p1
```

After flash.sh reports completion, the Jetson boots from RAM. Connect via serial (USB-UART adapter to J44 on the carrier) or, once networking comes up, SSH from the Mac directly to the Jetson's IP.

**Caveats / known gotchas**

- OrbStack USB pass-through requires macOS Ventura+. On Apple-Silicon-only OrbStack builds, raw USB pass-through is supported; if your version says "not supported", upgrade OrbStack to a recent release.
- Some older OrbStack versions only let one client (Mac or machine) hold a USB device at a time — detach it from Finder/macOS apps before attaching.
- If `orb usb attach` is missing, fall back to UTM or VMware Fusion — both have reliable USB-to-Linux pass-through on Apple Silicon.

## What this does NOT validate

- That `nvmflash.sh` (the mass-flash script bundled in the tbz2) writes correctly. To test that, you need a sacrificial unit you're willing to flash.
- The bootloader / `cboot` paths — RCM boot bypasses cboot.
- Recovery partition, A/B slot switching, OTA paths.

If you also need to validate the mass-flash flow itself, do it on a sacrificial spare unit, not the production cface-desktop.
