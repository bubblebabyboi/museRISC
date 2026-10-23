#!/usr/bin/env bash
# Compile the Sigil device trees (issue #68) from the one source
# sw/linux/dts/sigil.dtsi:
#   build/linux/sigil-f2.dtb    AWS F2: 48 GiB DDR4 (node 0) + 16 GiB pmem
#                               disk + 16 GiB HBM (node 1), 62.5 MHz timebase
#                               (AFIs with the B1 core clock)
#   build/linux/sigil-f2-100.dtb  the same F2 board with the 100 MHz
#                               timebase (AFIs with the B5 core clock, #53)
#   build/linux/sigil-qemu.dtb  QEMU virt reference (same map, 10 MHz)
#   build/linux/sigil-sim.dtb   Verilator: 128 MiB, embedded initramfs
#   build/linux/sigil.dtb       sw/linux/sigil.dts = sigil-sim (historic name)
# Needs dtc (apt install device-tree-compiler). The blobs carry 4 KiB of
# padding for OpenSBI's in-place fixups.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/linux
for b in f2 f2-100 qemu sim; do  # sw/linux/sigil.dts == sigil-sim.dts
  dtc -q -I dts -O dtb -p 4096 -o "build/linux/sigil-$b.dtb" "sw/linux/dts/sigil-$b.dts"
done
dtc -q -I dts -O dtb -p 4096 -o build/linux/sigil.dtb sw/linux/sigil.dts
cmp -s build/linux/sigil.dtb build/linux/sigil-sim.dtb
( cd build/linux && sha256sum sigil-f2.dtb sigil-f2-100.dtb sigil-qemu.dtb sigil-sim.dtb > dtb.sha256 && cat dtb.sha256 )
