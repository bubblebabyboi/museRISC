#!/bin/bash
# Linux RTL boot (soc_rtl_tb, OpenSBI + Linux 6.12 Image-initramfs, the
# release artifacts) on ~/dv8boot (8-riscv-dv), as in
# docs/evidence/riscv-dv-8-2026-10-22/synth-equiv/tools/linux_boot.sh.
t=~/dv8boot; cd "$t" || exit 1
source deps/env.sh >/dev/null 2>&1
o=build/linuxboot; mkdir -p $o
I=~/os-artifacts
{
echo "host $(hostname) (sigil-fpga-build) $(date -u +%FT%TZ) tree $t sha $(git rev-parse HEAD) $(verilator --version)"
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
