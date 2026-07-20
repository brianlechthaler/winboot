# Boot to Windows

Set Windows as the one-time next boot target and reboot.

## Overview

`winboot` sets the UEFI `BootNext` variable to the Windows Boot Manager entry and
reboots. `BootNext` applies only to the next boot, so the persistent boot order is
untouched: after Windows shuts down or restarts, the machine returns to its normal
default (usually Linux).

## Usage

```bash
winboot
winboot --dry-run
```

The command must run as root; if it is not, it re-executes itself through `sudo`.
`--dry-run` reports the boot ID that would be used without writing config, setting
`BootNext`, or rebooting.

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| Config path | `/etc/winboot.conf` | Fixed path for the cached Windows boot entry ID |

## Troubleshooting

- **Nothing reboots into Windows:** the cached ID may be wrong. Remove the config
  file and re-run to force a fresh scan.
- **Permission errors:** ensure `sudo` is available, or run the command as root.

## Related

- [Entry discovery](entry-discovery.md)
- [Architecture](../architecture.md)
