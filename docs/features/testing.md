# Testing

Run the script against stubbed system binaries without touching real firmware.

## Overview

`winboot_test.sh` is a self-contained Bash test harness. It creates temporary stub
versions of `efibootmgr`, `systemctl`, `id`, and `sudo`, then installs a rewritten
copy of `winboot.sh` whose absolute binary and config paths point into that temp
directory. Each stub logs the commands it receives; the tests assert on that log
instead of changing the host or rebooting.

## Usage

```bash
./winboot_test.sh
```

Exit code is `0` when all assertions pass, non-zero otherwise. The final line
reports the pass/fail count.

## Covered scenarios

| Test | What it verifies |
|------|------------------|
| Happy path via sudo | Non-root run elevates, scans, saves ID, sets `--bootnext`, reboots |
| First run saves ID | The detected `0000` ID is written to the config |
| Later run uses saved ID | Second run skips the scan and reuses the cached ID |
| Missing Windows entry | Exits 1 with a clear message, writes no config, does not reboot |
| UEFI read failure | `efibootmgr` failure is reported, no reboot |
| Multiple entries | Interactive selection saves and uses the chosen ID; invalid input re-prompts |
| Already root | Skips `sudo` entirely |
| Invalid / insecure / symlink config | Refuses unsafe cached IDs without rebooting |
| Label-only fallback | Warns and still boots when the Microsoft EFI path is absent |
| `--dry-run` | Scans or reads cache without writing config, BootNext, or reboot |

## How the stubs work

Each stub is a small script written into a temp directory. `id` reports a
configurable UID so both the root and non-root paths can be exercised. The `sudo`
stub rewrites `id` to report root, then re-execs the target, emulating privilege
elevation. Absolute paths inside the installed script copy are rewritten to those
stubs so production code never trusts `PATH` or `WINBOOT_*` environment overrides.
Temp directories are cleaned up on exit.

## Related

- [Architecture](../architecture.md)
