#!/usr/bin/env bash
set -euo pipefail

ID=/usr/bin/id
SUDO=/usr/bin/sudo
EFIBOOTMGR=/usr/bin/efibootmgr
SYSTEMCTL=/usr/bin/systemctl
CONFIG=/etc/winboot.conf

dry_run=0
for arg in "$@"; do
  case $arg in
    --dry-run) dry_run=1 ;;
    -h | --help)
      echo "Usage: winboot [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: winboot [--dry-run]" >&2
      exit 2
      ;;
  esac
done

if [[ $($ID -u) -ne 0 ]]; then
  echo "Administrator access is required to inspect and change UEFI boot settings."
  exec "$SUDO" -- "$0" "$@"
fi

die() {
  echo "$1" >&2
  exit 1
}

valid_boot_id() {
  [[ $1 =~ ^[0-9A-Fa-f]{4}$ ]]
}

parse_windows_entries() {
  local require_path=$1
  awk -v require_path="$require_path" '
    /Windows Boot Manager/ {
      if (require_path && $0 !~ /\\EFI\\Microsoft\\Boot\\bootmgfw\.efi/) next
      id = $1
      sub(/^Boot/, "", id)
      sub(/\*.*/, "", id)
      print id "|" $0
    }
  '
}

if [[ -L "$CONFIG" ]]; then
  die "Refusing to use config symlink $CONFIG."
fi
if [[ -e "$CONFIG" ]]; then
  [[ -f "$CONFIG" ]] || die "Config $CONFIG is not a regular file."
  perms=$(stat -c %a -- "$CONFIG")
  if ((8#$perms & 022)); then
    die "Config $CONFIG has insecure permissions ($perms); expected not group/world-writable."
  fi
fi

if [[ -s "$CONFIG" ]]; then
  boot_id=$(head -n 1 -- "$CONFIG" | tr -d '[:space:]')
  valid_boot_id "$boot_id" || die "Invalid boot entry ID in $CONFIG (expected four hex digits)."
else
  echo "First run: locating Windows in the UEFI boot entries..."
  if ! efi_entries=$("$EFIBOOTMGR" 2>/dev/null); then
    echo "Unable to read UEFI boot entries. Check that this system uses UEFI and efibootmgr is installed." >&2
    exit 1
  fi

  mapfile -t windows < <(parse_windows_entries 1 <<<"$efi_entries")
  if ((${#windows[@]} == 0)); then
    mapfile -t windows < <(parse_windows_entries 0 <<<"$efi_entries")
    if ((${#windows[@]} > 0)); then
      printf '%s\n' "No Windows Boot Manager entry with \\EFI\\Microsoft\\Boot\\bootmgfw.efi was found; falling back to label match." >&2
    fi
  fi

  ((${#windows[@]})) || {
    echo "Windows Boot Manager was not found." >&2
    exit 1
  }
  if ((${#windows[@]} == 1)); then
    entry=${windows[0]}
  else
    echo "Multiple Windows boot entries were found:"
    PS3="Choose the Windows entry to use: "
    select entry in "${windows[@]}"; do
      [[ -n "$entry" ]] && break
      echo "Invalid selection."
    done
  fi

  boot_id=${entry%%|*}
  valid_boot_id "$boot_id" || die "Refusing invalid boot entry ID: $boot_id"

  if ((dry_run == 0)); then
    config_dir=$(dirname -- "$CONFIG")
    tmp=$(mktemp --tmpdir="$config_dir" winboot.conf.XXXXXX)
    printf '%s\n' "$boot_id" >"$tmp"
    chmod 644 -- "$tmp"
    mv -f -- "$tmp" "$CONFIG"
    echo "Saved Windows boot entry $boot_id in $CONFIG."
  fi
fi

if ((dry_run)); then
  echo "Dry run: would set BootNext to $boot_id and reboot."
  exit 0
fi

"$EFIBOOTMGR" --bootnext "$boot_id"
"$SYSTEMCTL" reboot
