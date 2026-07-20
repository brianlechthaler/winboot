# Entry discovery and caching

Find the Windows Boot Manager in UEFI entries and remember it.

## Overview

On the first run (or whenever the config file is missing or empty), `winboot`
parses `efibootmgr` output for entries labeled "Windows Boot Manager" whose path
includes `\EFI\Microsoft\Boot\bootmgfw.efi`, and extracts their four-digit boot
IDs. If none match that path, it falls back to label-only matches with a warning.
The result is cached so later runs skip the scan.

## Behavior

| Windows entries found | Behavior |
|-----------------------|----------|
| 0 | Print "Windows Boot Manager was not found.", exit 1, no reboot |
| 1 | Use that entry automatically |
| 2 or more | Prompt with a numbered `select` menu; invalid input re-prompts |

If `efibootmgr` itself fails (for example on a legacy BIOS system), the script
prints "Unable to read UEFI boot entries..." and exits 1 without writing a config
or rebooting.

## Caching

The chosen ID is written to `/etc/winboot.conf` (atomic write, mode `0644`). The
file must remain a regular file that is not group/world-writable; symlinks and
invalid IDs are refused. Delete the file to re-scan:

```bash
sudo rm /etc/winboot.conf
```

## Related

- [Boot to Windows](boot-to-windows.md)
- [Getting started](../getting-started.md)
