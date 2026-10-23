#!/bin/bash
# sigil-sky130: CDL netlists of the hardened blocks for hierarchical LVS
# (~/sb/lvs/cdl): OpenRAM macro stubs (pins only, from the macros'
# .lvs.sp top subckt), write_cdl of the CPU block (s116d) and of the
# crypto block (w34m) against sky130hd.cdl (+ the macro stubs).
set -uo pipefail
O=~/sb/lvs/cdl; mkdir -p $O
IMG=openroad/orfs@sha256:63981d1ac8990a9bee8bf874c95ee2c1ee3fe7b99f57d459282ab8c31a8ed663
P=/OpenROAD-flow-scripts/flow/platforms
docker run --rm -v ~/sb/build/results:/results:ro -v $O:/o $IMG bash -lc "source ./env.sh >/dev/null
set -e
cd /o
: > sram_stubs.cdl
for m in sky130_sram_1rw1r_128x256_8 sky130_sram_1rw1r_44x64_8 sky130_sram_1rw1r_64x256_8; do
  awk -v m=\$m 'BEGIN{IGNORECASE=1} f && !/^\+/ {exit} f {print} tolower(\$1)==\".subckt\" && \$2==m {f=1; print}' $P/sky130ram/\$m/\$m.lvs.sp >> sram_stubs.cdl
  echo \".ENDS \$m\" >> sram_stubs.cdl
  echo >> sram_stubs.cdl
done
echo 'read_db /results/sky130hd/sigil_hier_sigil_cpu/s116d/6_final.odb
write_cdl -masters \"$P/sky130hd/cdl/sky130hd.cdl /o/sram_stubs.cdl\" /o/sigil_cpu.cdl' > wcdl_cpu.tcl
openroad -exit -no_init wcdl_cpu.tcl > wcdl_cpu.log 2>&1
echo 'read_db /results/sky130hd/sigil_hier_sigil_crypto_top/w34m/6_final.odb
write_cdl -masters $P/sky130hd/cdl/sky130hd.cdl /o/sigil_crypto_top.cdl' > wcdl_crypto.tcl
openroad -exit -no_init wcdl_crypto.tcl > wcdl_crypto.log 2>&1
"
ls -la $O; grep -c "^X" $O/sigil_cpu.cdl $O/sigil_crypto_top.cdl; grep -ci "^.subckt" $O/sram_stubs.cdl
