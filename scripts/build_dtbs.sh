#!/usr/bin/env bash
# Compile the Sigil device trees (issue #68) from the one source
# sw/linux/dts/sigil.dtsi:
#   build/linux/sigil-f2.dtb    AWS F2: 48 GiB DDR4 (node 0) + 16 GiB pmem
#                               disk + 16 GiB HBM (node 1), 62.5 MHz timebase
#   build/linux/sigil-qemu.dtb  QEMU virt reference (same map, 10 MHz)
#   build/linux/sigil-sim.dtb   Verilator: 128 MiB, embedded initramfs
#   build/linux/sigil.dtb       copy of sigil-sim.dtb (historic gate name)
# Needs dtc (apt install device-tree-compiler). The blobs carry 4 KiB of
# padding for OpenSBI's in-place fixups.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/linux
for b in f2 qemu sim; do
  dtc -q -I dts -O dtb -p 4096 -o "build/linux/sigil-$b.dtb" "sw/linux/dts/sigil-$b.dts"
done
cp build/linux/sigil-sim.dtb build/linux/sigil.dtb
( cd build/linux && sha256sum sigil-f2.dtb sigil-qemu.dtb sigil-sim.dtb > dtb.sha256 && cat dtb.sha256 )
