#!/bin/bash
# linux_boot.sh <tree> : build soc_rtl_tb (sim/Makefile, Verilator from deps/env.sh)
# and boot OpenSBI + Linux 6.12 Image-initramfs to SIGIL_LINUX_BOOT_OK.
# Log in <tree>/build/linuxboot/.
t=$1; cd "$t" || exit 1
source deps/env.sh >/dev/null 2>&1
o=build/linuxboot; mkdir -p $o
I=~/wt/dvfix-os
{
echo "host $(hostname) $(date -u +%FT%TZ) tree $t sha $(cat GIT_SHA) $(verilator --version)"
t0=$(date +%s)
make -C sim ../build/sim/soc_rtl_tb VJOBS=4 > $o/build.log 2>&1 || { echo BUILD FAILED; exit 1; }
echo "build $(( $(date +%s)-t0 ))s"
sha256sum $I/fw_jump.bin $I/Image-initramfs $I/sigil-sim.dtb
t1=$(date +%s)
/usr/bin/time -f "wall %E (user %U s), max RSS %M KiB, exit status %x" \
  build/sim/soc_rtl_tb 6000000000 --load 0x80000000=$I/fw_jump.bin --load 0x80200000=$I/Image-initramfs \
  --load 0x83000000=$I/sigil-sim.dtb --uart-log $o/linux-boot-uart.log --exit-string SIGIL_LINUX_BOOT_OK \
  > $o/linux_boot.log 2>&1
echo "boot rc=$? $(( $(date +%s)-t1 ))s"
tail -3 $o/linux_boot.log
echo "uart sha256 $(sha256sum < $o/linux-boot-uart.log | cut -c1-64) lines $(wc -l < $o/linux-boot-uart.log)"
echo "bad lines: $(grep -cE 'Oops|BUG:|Unable to handle|WARNING:|Kernel panic' $o/linux-boot-uart.log)"
echo DONE
} > $o/summary.txt 2>&1
