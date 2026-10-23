#!/bin/bash
# sigil-linux device-tree choice (#53): run after run_tests.sh (same fakes).
set -uo pipefail
T=/home/ubuntu/mhz100-sw/sltest
export PATH=$T/bin:$PATH SIGIL=$T/sigil SIGIL_LINUX_CACHE=$T/cache SIGIL_DISK=$T/disk/d.ext4
export SIGIL_AGFI=agfi-0c8aa56fde1a48495
SL=$T/src/sigil-linux
ctl() { printf 'rc=%s\naction=%s\n' "$1" "$2" > "$T/fake/ctl"; }
pass=0; fail=0
ok() { if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }
C=$T/cache
run() {  # NAME TAG URLDIR
  ctl 0 write:$1.txt
  SIGIL_LINUX_URL=file://$T/$3 $SL --tag "$2" < /dev/null > "$T/out-$1" 2>&1; rc=$?
  cat "$T/out-$1"; echo "rc=$rc"
}

echo "== d1. release with sigil-f2-100.dtb, 62.5 MHz AFI -> sigil-f2.dtb (100 MHz DTB downloaded, verified)"
echo 62500 > $T/fake/khz
run d1 rel100-tag rel100
ok "rc 0" '[ $rc = 0 ]'
ok "downloaded the 100 MHz DTB" 'grep -q "downloading sigil-f2-100.dtb" $T/out-d1 && cmp -s $C/rel100-tag/sigil-f2-100.dtb $T/rel100/sigil-f2-100.dtb'
ok "dtb sigil-f2.dtb" 'grep -q -- "--dtb $C/rel100-tag/sigil-f2.dtb " $T/fake/last-args'
ok "says the clock" 'grep -q "core clock 62500 kHz: device tree sigil-f2.dtb" $T/out-d1'

echo "== d2. same release, 100 MHz AFI -> sigil-f2-100.dtb"
echo 100000 > $T/fake/khz
run d2 rel100-tag rel100
ok "rc 0" '[ $rc = 0 ]'
ok "no download" '! grep -q downloading $T/out-d2'
ok "dtb sigil-f2-100.dtb" 'grep -q -- "--dtb $C/rel100-tag/sigil-f2-100.dtb " $T/fake/last-args'
ok "says the clock" 'grep -q "core clock 100000 kHz: device tree sigil-f2-100.dtb" $T/out-d2'

echo "== d3. release without sigil-f2-100.dtb (sigil-linux-f2-2026-10-22), 100 MHz AFI -> sigil-f2.dtb + note"
run d3 sigil-linux-f2-2026-10-22 rel
ok "rc 0" '[ $rc = 0 ]'
ok "no 100 MHz DTB download" '! grep -q "downloading sigil-f2-100.dtb" $T/out-d3 && [ ! -e $C/sigil-linux-f2-2026-10-22/sigil-f2-100.dtb ]'
ok "dtb sigil-f2.dtb" 'grep -q -- "--dtb $C/sigil-linux-f2-2026-10-22/sigil-f2.dtb " $T/fake/last-args'
ok "note" 'grep -q "has no sigil-f2-100.dtb: booting sigil-f2.dtb, sigil_host sets its timebase" $T/out-d3'

echo "== d4. --info fails (no clock) -> sigil-f2.dtb, boot still attempted"
rm -f $T/fake/khz
run d4 rel100-tag rel100
ok "rc 0" '[ $rc = 0 ]'
ok "dtb sigil-f2.dtb" 'grep -q -- "--dtb $C/rel100-tag/sigil-f2.dtb " $T/fake/last-args'
ok "unknown clock" 'grep -q "core clock ? kHz: device tree sigil-f2.dtb" $T/out-d4'

echo "== d5. corrupted cached 100 MHz DTB is downloaded again"
echo 100000 > $T/fake/khz
printf 'x' >> $C/rel100-tag/sigil-f2-100.dtb
run d5 rel100-tag rel100
ok "rc 0" '[ $rc = 0 ]'
ok "redownloaded" 'grep -q "downloading sigil-f2-100.dtb" $T/out-d5 && cmp -s $C/rel100-tag/sigil-f2-100.dtb $T/rel100/sigil-f2-100.dtb'

echo "== d6. a sigil_host without --info is refused before anything runs"
touch $T/fake/oldhost
run d6 rel100-tag rel100
rm -f $T/fake/oldhost
ok "rc 1" '[ $rc = 1 ]'
ok "too old" 'grep -q "too old for Sigil Linux" $T/out-d6'

echo "DTB RESULT: $pass passed, $fail failed"
