#!/bin/bash
# sigil_host DTB helpers on the built DTBs (#53): run from a checkout
# (REPO) with build/linux/*.dtb (scripts/build_dtbs.sh) and the aws-fpga SDK.
#   fdt_tests.sh REPO SDK_DIR WORKDIR
set -u
R=$1 SDK=$2 W=$3
D=$(cd "$(dirname "$0")" && pwd)
L=$R/build/linux
mkdir -p "$W" && cd "$W" || exit 2
cp "$D/test_fdt.c" "$R/fpga/host/test_fdt.c"
gcc -I"$SDK/userspace/include" -O1 -g -std=gnu11 -Wall -Wextra -Werror -o test_fdt "$R/fpga/host/test_fdt.c" \
  -L"$SDK/userspace/lib" -lfpga_mgmt -lrt -lpthread || exit 2
rm -f "$R/fpga/host/test_fdt.c"
printf '/include/ "sigil-f2.dts"\n/ {\n\tchosen {\n\t\trng-seed = /bits/ 8 <%s>;\n\t};\n};\n&cpu0 {\n\ttimebase-frequency = <62500000>;\n};\n' \
  "$(printf '0 %.0s' $(seq 32) | sed 's/ $//')" > "$R/sw/linux/dts/zz-rng-test.dts"
dtc -q -I dts -O dtb -p 4096 -o rng.dtb "$R/sw/linux/dts/zz-rng-test.dts"; rm -f "$R/sw/linux/dts/zz-rng-test.dts"
pass=0 fail=0
ok() { if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }
T=./test_fdt
echo "== 1 sigil-f2.dtb on a 100 MHz CL"; $T 100000 1 $L/sigil-f2.dtb a.dtb 2>&1
ok "fixed copy == sigil-f2-100.dtb" 'cmp -s a.dtb $L/sigil-f2-100.dtb'
echo "== 2 sigil-f2-100.dtb on a 100 MHz CL"; $T 100000 1 $L/sigil-f2-100.dtb b.dtb 2>&1
ok "unchanged" 'cmp -s b.dtb $L/sigil-f2-100.dtb'
echo "== 3 sigil-f2-100.dtb on a 62.5 MHz CL"; $T 62500 1 $L/sigil-f2-100.dtb c.dtb 2>&1
ok "fixed copy == sigil-f2.dtb" 'cmp -s c.dtb $L/sigil-f2.dtb'
echo "== 4 sigil-f2.dtb on a 100 MHz CL, --keep-timebase"; $T 100000 0 $L/sigil-f2.dtb d.dtb 2>&1
ok "unchanged" 'cmp -s d.dtb $L/sigil-f2.dtb'
echo "== 5 /chosen/rng-seed (32 B) + a /cpus/cpu@0 timebase copy, 100 MHz"; $T 100000 1 rng.dtb e.dtb 2>&1
ok "rng-seed filled" '[ "$(fdtget -t x e.dtb /chosen rng-seed)" != "$(fdtget -t x rng.dtb /chosen rng-seed)" ]'
ok "both timebases 100 MHz" '[ "$(fdtget e.dtb /cpus timebase-frequency)" = 100000000 ] && [ "$(fdtget e.dtb /cpus/cpu@0 timebase-frequency)" = 100000000 ]'
ok "only those 40 bytes changed" '[ "$(cmp -l rng.dtb e.dtb | wc -l)" = 40 ]'
echo "== 6 core clock unknown (0): sigil-sim.dtb"; $T 0 1 $L/sigil-sim.dtb f.dtb 2>&1
ok "unchanged" 'cmp -s f.dtb $L/sigil-sim.dtb'
echo "== 7 not a DTB"; head -c 4096 /dev/urandom > g.bin; $T 100000 1 g.bin g2.bin 2>&1
ok "unchanged" 'cmp -s g.bin g2.bin'
echo "== 8 truncated DTB"; head -c 300 $L/sigil-f2.dtb > h.bin; $T 100000 1 h.bin h2.bin 2>&1
ok "unchanged" 'cmp -s h.bin h2.bin'
echo "== 9 sigil-qemu.dtb (10 MHz) on a 62.5 MHz CL"; $T 62500 1 $L/sigil-qemu.dtb q.dtb 2>&1
ok "timebase 62.5 MHz, 4 bytes changed" '[ "$(fdtget q.dtb /cpus timebase-frequency)" = 62500000 ] && [ "$(cmp -l $L/sigil-qemu.dtb q.dtb | wc -l)" -le 4 ]'
echo "FDT RESULT: $pass passed, $fail failed"
