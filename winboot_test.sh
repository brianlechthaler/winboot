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

setup_bin() {
  local dir=$1 mode=$2 uid=$3
  mkdir -p "$dir"
  case $mode in
    windows)
      cat >"$dir/efibootmgr" <<'EOF'
#!/usr/bin/env bash
if (($#)); then printf 'efibootmgr %s\n' "$*" >>"$TEST_LOG"; else
  printf 'efibootmgr query\n' >>"$TEST_LOG"
  printf 'Boot0000* Windows Boot Manager\nBoot0001* Ubuntu\n'
fi
EOF
      ;;
    multiple)
      cat >"$dir/efibootmgr" <<'EOF'
#!/usr/bin/env bash
if (($#)); then printf 'efibootmgr %s\n' "$*" >>"$TEST_LOG"; else
  printf 'efibootmgr query\n' >>"$TEST_LOG"
  printf 'Boot0000* Windows Boot Manager\nBoot0002* Windows Boot Manager (backup)\n'
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
# re-run under a PATH where id reports root
bindir=$(dirname "$(command -v id)")
cat >"$bindir/id" <<'ID'
#!/usr/bin/env bash
[[ $1 == -u ]] && { echo 0; exit 0; }
command id "$@"
ID
chmod +x "$bindir/id"
exec "${args[@]}"
EOF
  chmod +x "$dir"/*
}

run() {
  local dir=$1
  shift
  PATH="$dir:$PATH" TEST_LOG="$dir/log" WINBOOT_CONFIG="$dir/config" "$@"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# happy path via sudo elevation
setup_bin "$tmp/ok" windows 1000
: >"$tmp/ok/log"
status=0
run "$tmp/ok" "$SCRIPT" || status=$?
assert_eq "happy path exit" 0 "$status"
assert_eq "first run detects Windows" $'efibootmgr query\nefibootmgr --bootnext 0000\nsystemctl reboot' "$(cat "$tmp/ok/log")"
assert_eq "first run saves boot ID" "0000" "$(<"$tmp/ok/config")"

# later runs use the saved boot ID without scanning again
: >"$tmp/ok/log"
run "$tmp/ok" "$SCRIPT"
assert_eq "later run uses saved ID" $'efibootmgr --bootnext 0000\nsystemctl reboot' "$(cat "$tmp/ok/log")"

# missing Windows entry
setup_bin "$tmp/miss" missing 0
: >"$tmp/miss/log"
status=0
err=$(run "$tmp/miss" "$SCRIPT" 2>&1) || status=$?
assert_eq "missing windows exit" 1 "$status"
assert_eq "missing windows message" $'First run: locating Windows in the UEFI boot entries...\nWindows Boot Manager was not found.' "$err"
assert_eq "missing windows only scans" "efibootmgr query" "$(cat "$tmp/miss/log")"
assert_eq "missing windows saves no config" "no" "$([[ -e $tmp/miss/config ]] && echo yes || echo no)"

# unreadable UEFI data reports a useful error instead of crashing
setup_bin "$tmp/error" error 0
: >"$tmp/error/log"
status=0
err=$(run "$tmp/error" "$SCRIPT" 2>&1) || status=$?
assert_eq "UEFI read failure exit" 1 "$status"
assert_eq "UEFI read failure message" $'First run: locating Windows in the UEFI boot entries...\nUnable to read UEFI boot entries. Check that this system uses UEFI and efibootmgr is installed.' "$err"
assert_eq "UEFI read failure does not reboot" "efibootmgr query" "$(cat "$tmp/error/log")"

# multiple Windows entries require an explicit choice
setup_bin "$tmp/multiple" multiple 0
: >"$tmp/multiple/log"
printf '9\n2\n' | run "$tmp/multiple" "$SCRIPT"
assert_eq "selected Windows ID saved" "0002" "$(<"$tmp/multiple/config")"
assert_eq "selected Windows ID used" $'efibootmgr query\nefibootmgr --bootnext 0002\nsystemctl reboot' "$(cat "$tmp/multiple/log")"

# already root skips sudo
setup_bin "$tmp/root" windows 0
: >"$tmp/root/log"
printf '0000\n' >"$tmp/root/config"
cat >"$tmp/root/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo should not be called" >&2
exit 99
EOF
chmod +x "$tmp/root/sudo"
status=0
run "$tmp/root" "$SCRIPT" || status=$?
assert_eq "root path exit" 0 "$status"
assert_eq "root path log" $'efibootmgr --bootnext 0000\nsystemctl reboot' "$(cat "$tmp/root/log")"

echo
echo "Results: $pass passed, $fail failed"
((fail == 0))
