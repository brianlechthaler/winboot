# Getting started

## Requirements

- Linux booted in UEFI mode. Check with `[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS`.
- `efibootmgr` installed (`apt install efibootmgr`, `dnf install efibootmgr`, etc.).
- `systemd` for the reboot step.
- A Windows install that appears as "Windows Boot Manager" in `efibootmgr` output
  (preferably with path `\EFI\Microsoft\Boot\bootmgfw.efi`).

## Install

Copy the script somewhere on your `PATH`:

```bash
sudo install -m 0755 winboot.sh /usr/local/bin/winboot
```

You can also run it in place without installing:

```bash
./winboot.sh
```

## First run

The first run scans the UEFI boot entries for the Windows Boot Manager.

- **One Windows entry found:** it is selected automatically.
- **Multiple entries found:** you are prompted to pick one.
- **No entry found:** the script reports the problem and exits without rebooting.

The chosen entry ID is written to `/etc/winboot.conf` so later runs skip the scan.
After selecting the entry, the machine reboots into Windows once, then returns to
your normal boot order.

Preview without rebooting:

```bash
winboot --dry-run
```

## Configuration file

The selected boot entry ID is cached at `/etc/winboot.conf` (mode `0644`, regular
file only). The path is fixed; there is no environment override.

To force a re-scan (for example after reinstalling Windows), delete the config
file:

```bash
sudo rm /etc/winboot.conf
```

## Uninstall

```bash
sudo rm /usr/local/bin/winboot /etc/winboot.conf
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Unable to read UEFI boot entries" | System booted in legacy BIOS mode, or `efibootmgr` missing | Boot in UEFI mode; install `efibootmgr` |
| "Windows Boot Manager was not found" | Windows entry named differently or absent | Confirm with `efibootmgr`; the entry label must contain "Windows Boot Manager" |
| "Invalid boot entry ID" / insecure permissions / symlink | Cached config is corrupt or unsafe | `sudo rm /etc/winboot.conf` and re-run |
| Reboots into Linux again | Wrong cached entry | `sudo rm /etc/winboot.conf` and re-run to re-scan |
