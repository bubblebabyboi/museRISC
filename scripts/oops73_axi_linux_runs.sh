#!/bin/bash
# Linux on fpga_top_tb_f2 (F2 map, 512-bit AXI) with F2-like DDR4 timing
# and the adversarial AXI model (#73 AXI lens).
set -u
R=~/oops/axi/runs; mkdir -p $R
TB=~/oops/axi/sigil/build/sim/fpga_top_tb_f2
A=~/os-artifacts
ADV="--axi-rlat 36:72 --axi-blat 1:300 --axi-gap 2 --axi-ready 60 --axi-rw-race --axi-ooo"
F2LIKE="--axi-rlat 40:76 --axi-blat 20:60 --axi-gap 0 --axi-ready 90"
cd $R
run() { # name img max args...
  local n=$1 img=$2 max=$3; shift 3
  ( /usr/bin/time -v $TB $max "$@" --load 0x80000000=$A/fw_jump.bin --load 0x80200000=$img \
      --load 0x83000000=$A/sigil-sim.dtb --exit-string SIGIL_LINUX_BOOT_OK \
      --fail-string "Unable to handle" > $n.log 2>&1; echo "EXIT $?" >> $n.log ) &
}
run initramfs-adv1 $A/Image-initramfs 3000000000 $ADV --axi-seed 1
run initramfs-f2like $A/Image-initramfs 3000000000 $F2LIKE --axi-seed 7
run execstress-adv2 $A/stress/Image-execstress 40000000000 $ADV --axi-seed 2
run execstress-f2like $A/stress/Image-execstress 40000000000 $F2LIKE --axi-seed 9
wait
