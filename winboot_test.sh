#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$ROOT/winboot.sh"
pass=0
fail=0

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    echo "PASS: $name"
    ((++pass))
  else
    echo "FAIL: $name"
    echo "  expected: $(printf %q "$expected")"
    echo "  actual:   $(printf %q "$actual")"
    ((++fail))
  fi
}

# Install a copy of winboot.sh with paths rewritten into $dir (no env overrides).
install_script() {
  local dir=$1
  sed \
    -e "s|/usr/bin/id|$dir/id|g" \
    -e "s|/usr/bin/sudo|$dir/sudo|g" \
    -e "s|/usr/bin/efibootmgr|$dir/efibootmgr|g" \
    -e "s|/usr/bin/systemctl|$dir/systemctl|g" \
    -e "s|/etc/winboot.conf|$dir/winboot.conf|g" \
    "$SCRIPT" >"$dir/winboot.sh"
  chmod +x "$dir/winboot.sh"
}

setup_bin() {
  local dir=$1 mode=$2 uid=$3
  mkdir -p "$dir"
  case $mode in
    windows)
      cat >"$dir/efibootmgr" <<'EOF'
#!/usr/bin/env bash
if (($#)); then printf 'efibootmgr %s\n' "$*" >>"$TEST_LOG"; else
  printf 'efibootmgr query\n' >>"$TEST_LOG"
  printf 'Boot0000* Windows Boot Manager\tHD(1,GPT,x)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\nBoot0001* Ubuntu\n'
fi
EOF
      ;;
    multiple)
      cat >"$dir/efibootmgr" <<'EOF'
#!/usr/bin/env bash
if (($#)); then printf 'efibootmgr %s\n' "$*" >>"$TEST_LOG"; else
  printf 'efibootmgr query\n' >>"$TEST_LOG"
  printf 'Boot0000* Windows Boot Manager\tHD(1,GPT,x)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\nBoot0002* Windows Boot Manager\tHD(2,GPT,y)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n'
fi
EOF
      ;;
    label_only)
      cat >"$dir/efibootmgr" <<'EOF'
#!/usr/bin/env bash
if (($#)); then printf 'efibootmgr %s\n' "$*" >>"$TEST_LOG"; else
  printf 'efibootmgr query\n' >>"$TEST_LOG"
  printf 'Boot0000* Windows Boot Manager\nBoot0001* Ubuntu\n'
fi
EOF
      ;;
    missing)
      cat >"$dir/efibootmgr" <<'EOF'
#!/usr/bin/env bash
if (($#)); then printf 'efibootmgr %s\n' "$*" >>"$TEST_LOG"; else
  printf 'efibootmgr query\n' >>"$TEST_LOG"
  printf 'Boot0001* Ubuntu\n'
fi
EOF
      ;;
    error)
      cat >"$dir/efibootmgr" <<'EOF'
#!/usr/bin/env bash
printf 'efibootmgr query\n' >>"$TEST_LOG"
echo "firmware unavailable" >&2
exit 2
EOF
      ;;
  esac
  cat >"$dir/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
EOF
  cat >"$dir/id" <<EOF
#!/usr/bin/env bash
[[ \$1 == -u ]] && { echo $uid; exit 0; }
command id "\$@"
EOF
  cat >"$dir/sudo" <<'EOF'
#!/usr/bin/env bash
args=("$@")
[[ ${args[0]} == -- ]] && args=("${args[@]:1}")
bindir=$(dirname "${args[0]}")
cat >"$bindir/id" <<'ID'
#!/usr/bin/env bash
[[ $1 == -u ]] && { echo 0; exit 0; }
command id "$@"
ID
chmod +x "$bindir/id"
exec "${args[@]}"
EOF
  chmod +x "$dir"/*
  install_script "$dir"
}

run() {
  local dir=$1
  shift
  TEST_LOG="$dir/log" "$@"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# happy path via sudo elevation
setup_bin "$tmp/ok" windows 1000
: >"$tmp/ok/log"
status=0
run "$tmp/ok" "$tmp/ok/winboot.sh" || status=$?
assert_eq "happy path exit" 0 "$status"
assert_eq "first run detects Windows" $'efibootmgr query\nefibootmgr --bootnext 0000\nsystemctl reboot' "$(cat "$tmp/ok/log")"
assert_eq "first run saves boot ID" "0000" "$(<"$tmp/ok/winboot.conf")"

# later runs use the saved boot ID without scanning again
: >"$tmp/ok/log"
run "$tmp/ok" "$tmp/ok/winboot.sh"
assert_eq "later run uses saved ID" $'efibootmgr --bootnext 0000\nsystemctl reboot' "$(cat "$tmp/ok/log")"

# missing Windows entry
setup_bin "$tmp/miss" missing 0
: >"$tmp/miss/log"
status=0
err=$(run "$tmp/miss" "$tmp/miss/winboot.sh" 2>&1) || status=$?
assert_eq "missing windows exit" 1 "$status"
assert_eq "missing windows message" $'First run: locating Windows in the UEFI boot entries...\nWindows Boot Manager was not found.' "$err"
assert_eq "missing windows only scans" "efibootmgr query" "$(cat "$tmp/miss/log")"
assert_eq "missing windows saves no config" "no" "$([[ -e $tmp/miss/winboot.conf ]] && echo yes || echo no)"

# unreadable UEFI data reports a useful error instead of crashing
setup_bin "$tmp/error" error 0
: >"$tmp/error/log"
status=0
err=$(run "$tmp/error" "$tmp/error/winboot.sh" 2>&1) || status=$?
assert_eq "UEFI read failure exit" 1 "$status"
assert_eq "UEFI read failure message" $'First run: locating Windows in the UEFI boot entries...\nUnable to read UEFI boot entries. Check that this system uses UEFI and efibootmgr is installed.' "$err"
assert_eq "UEFI read failure does not reboot" "efibootmgr query" "$(cat "$tmp/error/log")"

# multiple Windows entries require an explicit choice
setup_bin "$tmp/multiple" multiple 0
: >"$tmp/multiple/log"
printf '9\n2\n' | run "$tmp/multiple" "$tmp/multiple/winboot.sh"
assert_eq "selected Windows ID saved" "0002" "$(<"$tmp/multiple/winboot.conf")"
assert_eq "selected Windows ID used" $'efibootmgr query\nefibootmgr --bootnext 0002\nsystemctl reboot' "$(cat "$tmp/multiple/log")"

# already root skips sudo
setup_bin "$tmp/root" windows 0
: >"$tmp/root/log"
printf '0000\n' >"$tmp/root/winboot.conf"
chmod 644 "$tmp/root/winboot.conf"
cat >"$tmp/root/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo should not be called" >&2
exit 99
EOF
chmod +x "$tmp/root/sudo"
status=0
run "$tmp/root" "$tmp/root/winboot.sh" || status=$?
assert_eq "root path exit" 0 "$status"
assert_eq "root path log" $'efibootmgr --bootnext 0000\nsystemctl reboot' "$(cat "$tmp/root/log")"

# invalid cached boot ID is rejected
setup_bin "$tmp/badid" windows 0
printf 'not-a-boot-id\n' >"$tmp/badid/winboot.conf"
chmod 644 "$tmp/badid/winboot.conf"
: >"$tmp/badid/log"
status=0
err=$(run "$tmp/badid" "$tmp/badid/winboot.sh" 2>&1) || status=$?
assert_eq "invalid boot ID exit" 1 "$status"
assert_eq "invalid boot ID message" "Invalid boot entry ID in $tmp/badid/winboot.conf (expected four hex digits)." "$err"
assert_eq "invalid boot ID does not reboot" "" "$(cat "$tmp/badid/log")"

# group/world-writable config is rejected
setup_bin "$tmp/badperm" windows 0
printf '0000\n' >"$tmp/badperm/winboot.conf"
chmod 666 "$tmp/badperm/winboot.conf"
: >"$tmp/badperm/log"
status=0
err=$(run "$tmp/badperm" "$tmp/badperm/winboot.sh" 2>&1) || status=$?
assert_eq "insecure perms exit" 1 "$status"
assert_eq "insecure perms message" "Config $tmp/badperm/winboot.conf has insecure permissions (666); expected not group/world-writable." "$err"
assert_eq "insecure perms does not reboot" "" "$(cat "$tmp/badperm/log")"

# symlink config is rejected
setup_bin "$tmp/symlink" windows 0
printf '0000\n' >"$tmp/symlink/real.conf"
ln -s "$tmp/symlink/real.conf" "$tmp/symlink/winboot.conf"
: >"$tmp/symlink/log"
status=0
err=$(run "$tmp/symlink" "$tmp/symlink/winboot.sh" 2>&1) || status=$?
assert_eq "symlink config exit" 1 "$status"
assert_eq "symlink config message" "Refusing to use config symlink $tmp/symlink/winboot.conf." "$err"
assert_eq "symlink config does not reboot" "" "$(cat "$tmp/symlink/log")"

# label-only Windows entries still work via fallback
setup_bin "$tmp/label" label_only 0
: >"$tmp/label/log"
status=0
err=$(run "$tmp/label" "$tmp/label/winboot.sh" 2>&1) || status=$?
assert_eq "label-only fallback exit" 0 "$status"
assert_eq "label-only fallback warns" "yes" "$(grep -q 'falling back to label match' <<<"$err" && echo yes || echo no)"
assert_eq "label-only fallback boots" $'efibootmgr query\nefibootmgr --bootnext 0000\nsystemctl reboot' "$(cat "$tmp/label/log")"

# dry-run discovers but does not write config, set BootNext, or reboot
setup_bin "$tmp/dry" windows 0
: >"$tmp/dry/log"
status=0
out=$(run "$tmp/dry" "$tmp/dry/winboot.sh" --dry-run 2>&1) || status=$?
assert_eq "dry-run exit" 0 "$status"
assert_eq "dry-run message" $'First run: locating Windows in the UEFI boot entries...\nDry run: would set BootNext to 0000 and reboot.' "$out"
assert_eq "dry-run only scans" "efibootmgr query" "$(cat "$tmp/dry/log")"
assert_eq "dry-run saves no config" "no" "$([[ -e $tmp/dry/winboot.conf ]] && echo yes || echo no)"

# dry-run with cached ID skips mutation
setup_bin "$tmp/dry2" windows 0
printf '0000\n' >"$tmp/dry2/winboot.conf"
chmod 644 "$tmp/dry2/winboot.conf"
: >"$tmp/dry2/log"
out=$(run "$tmp/dry2" "$tmp/dry2/winboot.sh" --dry-run 2>&1)
assert_eq "dry-run cached message" "Dry run: would set BootNext to 0000 and reboot." "$out"
assert_eq "dry-run cached no mutation" "" "$(cat "$tmp/dry2/log")"

echo
echo "Results: $pass passed, $fail failed"
((fail == 0))
