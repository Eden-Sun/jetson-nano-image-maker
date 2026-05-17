# Chowface Edge Device — Agent Runbook

Operational know-how for the Chowface face-recognition Jetson Nano deployed in the field.

## Host

| Field | Value |
|---|---|
| Hostname | `cface-desktop` |
| Public IP / Port | `114.32.210.136` : `8222` (NAT'd to internal 22) |
| Reverse DNS | `114-32-210-136.HINET-IP.hinet.net` (Chunghwa HiNet, Taiwan) |
| Internal IP | `192.168.5.15/24` on `eth0`, gw `192.168.5.254` |
| Login | user `nvidia`, password — see `~/.chowface/cface-desktop.pw` (not in repo) |
| Hardware | NVIDIA Jetson Nano Developer Kit (Tegra210 / t210ref, Cortex-A57 ×4 @ 1479 MHz, 4 GB RAM, 14 GB eMMC) |
| OS | Ubuntu 18.04.6 LTS (EOL) — L4T R32.7.1 — kernel 4.9.253-tegra (aarch64) |
| CUDA | 10.2 at `/usr/local/cuda` |
| Timezone | `Asia/Taipei` (UTC+8), NTP-synced via `systemd-timesyncd` |

## SSH

Interactive:

```
ssh -p 8222 nvidia@114.32.210.136
```

Non-interactive (no `sshpass` on macOS by default, use `expect`):

```bash
PW="$(cat ~/.chowface/cface-desktop.pw)"
expect <<EOF
set timeout 60
spawn ssh -p 8222 -o StrictHostKeyChecking=no nvidia@114.32.210.136 "<remote command>"
expect {
    -re "(P|p)assword:" { send -- "$PW\r"; exp_continue }
    eof
}
EOF
```

Store the password locally at `~/.chowface/cface-desktop.pw` (chmod 600). For multi-step work, write a `*.sh` locally, `scp -P 8222` it to `/tmp/`, then run it via the expect pattern above. Note the heredoc uses `<<EOF` (unquoted) so `$PW` is interpolated; if the password contains shell-special chars, the surrounding `expect` block treats it safely after substitution.

The server host key fingerprint (ED25519): `SHA256:w+S81RCzCJh5SB6oHwKrOJmwxr8dSrhm24ja1jzFaHQ`.

## Privilege Model

- `nvidia` is in groups `sudo`, `gpio`, `i2c`, `video`, `audio`, `gdm`, `lightdm`, `jetson_stats`, `weston-launch`, `sambashare`.
- `/etc/sudoers` has `%sudo ALL=NOPASSWD:ALL` → any sudo invocation by `nvidia` is passwordless. Cron jobs can therefore call `sudo <cmd>` without a TTY.
- No custom `/etc/sudoers.d/` entries.
- `root` itself has no crontab.

## Chowface Application

Lives under `/home/nvidia/Chowface_backend/` (~2.5 GB). Four systemd services drive the app, all `enabled`:

| Service | Purpose |
|---|---|
| `chowface.service` | Main face-recognition engine (FaceMeSDKCameraSampleTool) |
| `chowface_io.service` | GPIO bridge (binary at `Chowface_backend/Others/gpioService/bin/chowio`) |
| `chowface_record_handler.service` | Record handling |
| `chowface_web_server.service` | Django backend on port 80 (`manage.py runserver --noreload 0.0.0.0:80`) |

Other process anchors:
- `FaceMeSDKCameraSampleTool recognizeVideos 200 201 --capture-width=800 --capture-height=600 --max-cameras=2 --thread-number=16 --far=1e-5` — runs as root, ~100% of one core + ~40% RAM, GPU GR3D ~99%.
- MySQL 5.7 on `127.0.0.1:3306` (local-only, ~6% RAM).
- `sqlService` C++ binary under `Chowface_backend/Others/sqlService/build/`.

Public listening ports on the host: `22` (SSH), `80` (HTTP, Django), `111` (rpcbind — would close if hardening), `5353` (mDNS), `5355` (LLMNR). MySQL is local-only.

Service control:

```bash
sudo systemctl status chowface chowface_io chowface_record_handler chowface_web_server
sudo systemctl restart chowface_web_server
sudo journalctl -u chowface -n 200 --no-pager
```

## Scheduled Jobs (`nvidia` crontab)

```
0 5  * * *   sudo /sbin/shutdown -r now
0 0  * * *   /usr/bin/python3 /home/nvidia/Chowface_backend/backend/delete_CyberLink_log.py
01 00 * * *  /usr/bin/python3 /home/nvidia/Chowface_backend/backend/manage.py crontab run 8f3b619b861469b3ba90de62556ecc84
```

### Daily reboot — known fix (2026-05-16)

Original entry was `0 5 * * * /sbin/shutdown -r now`. Cron triggered every day but `shutdown` calls systemd-logind over D-Bus, which requires PolicyKit auth — a non-root cron job can't authenticate, so the call failed silently. Uptime had grown to 75 days before the fix.

Fix: prepended `sudo`. Works because `%sudo ALL=NOPASSWD:ALL` and `nvidia` is in `sudo`.

Diagnostic signature in `/var/log/syslog` if it ever regresses:

```
CRON[xxxx]: (nvidia) CMD (/sbin/shutdown -r now)
# but no "system going down" message follows
```

Reboot-permission self-test (run as `nvidia`, doesn't actually reboot — schedules and immediately cancels):

```bash
sudo -n /sbin/shutdown +60 'permission test'
sudo -n /sbin/shutdown -c
# Verify no pending shutdown:
ls /run/systemd/shutdown/
# Should be empty (no 'scheduled' file). /run/nologin should not exist.
```

Backup of pre-fix crontab on host: `/home/nvidia/.crontab.backup.20260516_164002`.

Rollback: `crontab /home/nvidia/.crontab.backup.20260516_164002`.

## Health Watchpoints

- **Disk** — root fs is 14 GB, currently at 90%. Heaviest dirs: `/home/nvidia` (2.5 G), `/var/lib/mysql` (220 M), `/var/lib/apt` (174 M). MySQL or app logs likely to be culprits when it fills.
- **Memory** — 4 GB total, no swap. FaceMe SDK alone is ~40% RAM, Django ~7.6%, MySQL ~6%. Free RAM hovers around 200 MB; an OOM is plausible if anything new is loaded.
- **No fan PWM** — `PWM=0`; passive cooling only. Temps were fine (~40-50 °C) but watch in summer.
- **NV Power Mode** — `MAXN` (no throttling).
- **Ubuntu 18.04 + kernel 4.9 are EOL** — no security updates without ESM. Jetson Nano never got JetPack 5/6.
- **Django dev server in production** — `manage.py runserver` on 0.0.0.0:80, not gunicorn/nginx. Not robust, but is how the deployment works today.
- **rpcbind on 0.0.0.0:111** — unused by the app as far as we can tell; safe to disable if hardening (`sudo systemctl disable --now rpcbind rpcbind.socket`).

## Quick Health Check Snippet

```bash
ssh -p 8222 nvidia@114.32.210.136 '
  echo "uptime:"; uptime
  echo "disk:";   df -h /
  echo "mem:";    free -h
  echo "temp:";   for z in /sys/class/thermal/thermal_zone*/type; do
                    t=$(cat $z); v=$(cat ${z%/type}/temp);
                    printf "  %-18s %s mC\n" "$t" "$v";
                  done
  echo "gpu:";    timeout 1 tegrastats --interval 500 2>/dev/null | head -1
  echo "svc:";    systemctl is-active chowface chowface_io chowface_record_handler chowface_web_server
'
```

## Hardware Customization — Dual HDMI

The carrier was modified from the stock DP+HDMI to **dual HDMI**. A matching custom device tree is flashed and supports both outputs. The original DP connector now drives the second HDMI via SOR0; the stock HDMI connector continues to drive SOR1.

Evidence in the running system:
- `tegradc tegradc.0: disp0 connected to head0->/host1x/sor1` and `tegradc tegradc.1: disp1 connected to head1->/host1x/sor` — both display controllers initialize at boot.
- `/sys/kernel/debug/gpio` shows `gpio-225 (...|hdmi2.0_hpd)` — kernel label for the second HDMI's HPD line.
- Decompiled DTB contains two `hdmi-display { compatible = "hdmi,display"; }` nodes, one under `/host1x/sor` and one under `/host1x/sor1`.

Two harmless boot warnings for head1/SOR0 — ignore unless second HDMI stops working:
```
tegradc tegradc.1: No hpd-gpio in DT
tegradc tegradc.1: dpd enable lookup fail:-19
```

### xrandr output naming is misleading

NVIDIA's proprietary X driver labels the two outputs `DP-0` and `HDMI-0`, but both are physically HDMI. The labels come from kernel-DT-advertised connector type, not the actual TMDS protocol. Xorg log confirms the connected display runs over `External TMDS` (= HDMI) even when xrandr calls it `DP-0`.

Mapping:

| xrandr | NVIDIA internal | head | SOR | Physical HDMI port |
|---|---|---|---|---|
| `DP-0` | DFP-1 | head0 | SOR1 | First HDMI (original HDMI connector) |
| `HDMI-0` | DFP-0 | head1 | SOR0 | Second HDMI (ex-DP connector slot) |

### Verifying second HDMI on hot-plug

```bash
sudo dmesg -W | grep -iE "hpd|hdmi|tegradc|edid"
# Plug in the second HDMI; expect head1 HPD transitions + EDID read,
# then xrandr will show HDMI-0 as connected.
```

### DTB Backup

The dual-HDMI device tree is backed up at `dtb-backup/dtb_dump/` in this repo. Captured 2026-05-16 from the live host.

| File | sha256 (first 16 chars) | Purpose |
|---|---|---|
| `slotA.dtb` | `fd0d4179c7ec1168…` | **The DTB to use** — extracted from `/dev/mmcblk0p2` offset 0x400, truncated to FDT totalsize (219257 bytes). For flash.sh. |
| `slotB.dtb` | identical to slotA | Same DTB from `/dev/mmcblk0p6` (backup slot). Binary-identical, kept for paranoia. |
| `slotA_full.bin` / `slotB_full.bin` | — | Full 1 MiB raw partition images (with the Tegra wrapper header at offset 0x000–0x3FF). Use only for in-place `dd` restore on this exact unit. |
| `live.dtb` / `live.dts` | `61725cd3dca77256…` | Dump of `/proc/device-tree` — what the kernel sees. Includes cboot-injected per-board data (`serial-number = "1422721082109"`, ethernet MAC, EEPROM blob). **Do not reflash this to a new board**; the injected identity will collide. |
| `original.dtb` / `original.dts` | identical to slotA | Copy of `/boot/dtb/kernel_tegra210-p3448-0002-p3449-0000-b00.dtb`. Labelled "original" but is actually the as-flashed customized version — `/boot/dtb/` got overwritten by `flash.sh` during the custom flash. There is no untouched factory DTB on the host. |

Embedded DTB build time: `Jan 4 2023 10:02:03` (the integrator's custom build).

### Reusing on a fresh L4T image

Two paths, pick whichever fits the situation:

**(A) Via this repo's image-maker pipeline (recommended for batch)**

The same `slotA.dtb` is already pinned at `packager/custom-dtb/tegra210-p3448-0002-p3449-0000-b00.dtb` and wired into `packager/Dockerfile`. Just run:

```bash
./make-image.sh
# → MMDDHHMM-emmc.tbz2 (mass-flash bundle) appears in repo root
```

See `Readme.md → Fork — what's different from upstream` for details and `BOOT-TEST.md` for non-destructive verification on a spare unit.

**(B) Direct flash.sh on a JetPack 4.6.1 workstation (ad-hoc / single board)**

```bash
# Drop the customized DTB into the BSP
cp dtb-backup/dtb_dump/slotA.dtb \
   Linux_for_Tegra/kernel/dtb/kernel_tegra210-p3448-0002-p3449-0000-b00.dtb

cd Linux_for_Tegra
sudo ./flash.sh jetson-nano-emmc mmcblk0p1
```

`flash.sh` re-wraps with the Tegra header and writes to both DTB slot A and slot B. Don't use `slotA_full.bin` — it already has a wrapper and `flash.sh` would double-wrap.

### In-place DTB restore (same board only, destructive)

If a future change ever bricks the DTB on this same unit, restore from the full partition image:

```bash
# Copy backup to the host first, then:
sudo dd if=slotA_full.bin of=/dev/mmcblk0p2 bs=1M conv=fsync
sudo dd if=slotA_full.bin of=/dev/mmcblk0p6 bs=1M conv=fsync
sync && sudo reboot
```

This bit-exactly puts the partitions back to the 2026-05-16 state. Only safe on this same board because the cboot wrapper may include board-tied checksums; do not run on a different unit.

## Other Operators

Active SSH session observed from `118.163.56.149` (HiNet) during 2026-05-16 work. Coordinate before disruptive changes — they may be debugging concurrently.
