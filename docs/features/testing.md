# Testing

Run the script against stubbed system binaries without touching real firmware.

## Overview

`winboot_test.sh` is a self-contained Bash test harness. It creates temporary stub
versions of `efibootmgr`, `systemctl`, `id`, and `sudo`, puts them first on `PATH`,
and runs `winboot.sh` against them. Each stub logs the commands it receives; the
tests assert on that log instead of changing the host or rebooting.

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

## How the stubs work

Each stub is a small script written into a temp directory. `id` reports a
configurable UID so both the root and non-root paths can be exercised. The `sudo`
stub rewrites `id` to report root, then re-execs the target, emulating privilege
elevation. `TEST_LOG` and `WINBOOT_CONFIG` are set per run so tests stay isolated
in `mktemp` directories that are cleaned up on exit.

## Related

- [Architecture](../architecture.md)
