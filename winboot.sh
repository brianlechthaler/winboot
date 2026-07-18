#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Administrator access is required to inspect and change UEFI boot settings."
  exec sudo -- "$0" "$@"
fi

config=${WINBOOT_CONFIG:-/etc/winboot.conf}

if [[ -s $config ]]; then
  boot_id=$(<"$config")
else
  echo "First run: locating Windows in the UEFI boot entries..."
  if ! efi_entries=$(efibootmgr 2>/dev/null); then
    echo "Unable to read UEFI boot entries. Check that this system uses UEFI and efibootmgr is installed." >&2
    exit 1
  fi

  mapfile -t windows < <(awk '/Windows Boot Manager/ {
    id = $1
    sub(/^Boot/, "", id)
    sub(/\*.*/, "", id)
    print id "|" $0
  }' <<<"$efi_entries")

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
      [[ -n $entry ]] && break
      echo "Invalid selection."
    done
  fi

  boot_id=${entry%%|*}
  printf '%s\n' "$boot_id" >"$config"
  echo "Saved Windows boot entry $boot_id in $config."
fi

efibootmgr --bootnext "$boot_id"
systemctl reboot
