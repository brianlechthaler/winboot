# winboot

Reboot a Linux machine straight into Windows on a dual-boot UEFI system. `winboot`
finds the Windows Boot Manager in your UEFI entries, sets it as the one-time next
boot target, and reboots. Your default boot order is left unchanged, so the next
boot after Windows returns to Linux.

## Quick start

```bash
sudo install -m 0755 winboot.sh /usr/local/bin/winboot
winboot
```

The first run scans UEFI boot entries and caches the Windows entry ID. Every run
after that reuses the cached ID and reboots immediately. See
[Getting started](docs/getting-started.md) for install options and first-run
behavior.

## Documentation

- [Getting started](docs/getting-started.md) — install, first run, uninstall
- [Architecture](docs/architecture.md) — how the script works, boot flow
- [Features](docs/features/) — per-feature behavior and configuration

## Requirements

- Linux with a UEFI firmware (not legacy BIOS)
- `efibootmgr`
- `systemd` (for `systemctl reboot`)
- Root privileges (the script re-runs itself with `sudo` when needed)

## License

MIT — see [LICENSE](LICENSE).
