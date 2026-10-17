#!/usr/bin/env bash
# Run the vector TB and the cached core directed suite against the
# ORFS vendor OpenRAM Verilog models (sky130hd SRAM-macro build).
#
# Usage (repo root, after `source deps/env.sh`; needs docker and the
# openroad/orfs image): flow/designs/sky130hd/muserisc_soc/sram/vendor_model_check.sh [--as-shipped]
#
# The vendor models print on every access and, on every rising clock
# edge, drive dout with a *blocking* `dout = 'bx`. In a zero-delay
# simulation that races any flop that samples dout on the same edge
# (the capture register in the macro wrappers), so by default this
# script applies two edits: the per-access "Reading"/"Writing"
# `$display`s become empty statements (the vendor's same-address
# read/write WARNING is kept and counted: the design must never
# trigger it, so any occurrence fails the check), and the posedge
# `dout = 'bx` becomes non-blocking (`dout <= 'bx`),
# i.e. dout goes invalid just after the edge rather than at it. That
# is the signoff assumption stated in docs/SOC_AREA.md: the macro's
# dout stays valid for at least the hold time of every flop that
# samples it at the rising edge. --as-shipped skips the second edit
# and shows the race (the vector TB fails).
set -uo pipefail
cd "$(dirname "$0")/../../../../.."
SHIPPED=0
[ "${1:-}" = --as-shipped ] && SHIPPED=1
OUT=build/vendor-openram
mkdir -p "$OUT/models"
V=""
for m in sky130_sram_1rw1r_64x256_8 sky130_sram_1rw1r_128x256_8 sky130_sram_1rw1r_44x64_8; do
  docker run --rm --user "$(id -u):$(id -g)" openroad/orfs:latest \
    cat "flow/platforms/sky130ram/$m/$m.v" > "$OUT/models/$m.orig.v" || exit 1
  if [ $SHIPPED = 1 ]; then
    sed -e 's/^\(\s*\)\$display(\$time," \(Reading\|Writing\).*$/\1;/' \
        "$OUT/models/$m.orig.v" > "$OUT/models/$m.v"
  else
    sed -e 's/^\(\s*\)\$display(\$time," \(Reading\|Writing\).*$/\1;/' \
        -e "s/dout\([01]\) = \([0-9]*\)'bx;/dout\1 <= \2'bx;/" \
        "$OUT/models/$m.orig.v" > "$OUT/models/$m.v"
  fi
  grep -q 'WARNING: Writing and reading' "$OUT/models/$m.v" || { echo "vendor WARNING display not found in $m"; exit 1; }
  V="$V $OUT/models/$m.v"
done
R=rtl/core
VFL="--cc --exe --build -j 0 --coverage-line -Wno-fatal -Wno-lint -Wno-style --no-timing \
  --x-assign unique --x-initial unique -I$R -CFLAGS -std=c++17 -CFLAGS -O2 +define+MUSERISC_SRAM_SKY130"
verilator $VFL --Mdir "$OUT/obj_vec" --top-module muserisc_vec_harness -o "$(pwd)/$OUT/vec_tb_vendor" \
  $V $R/muserisc_pkg.sv $R/muserisc_vec_pkg.sv $R/muserisc_fpu_pkg.sv $R/muserisc_fpu.sv \
  $R/muserisc_vregfile.sv $R/muserisc_vec.sv tb/sv/muserisc_vec_harness.sv "$(pwd)/tb/cpp/vec_tb.cpp" \
  > "$OUT/build_vec.log" 2>&1 || { tail -20 "$OUT/build_vec.log"; exit 1; }
CPU="$R/muserisc_pkg.sv $R/muserisc_regfile.sv $R/muserisc_fpregfile.sv $R/muserisc_alu.sv \
  $R/muserisc_muldiv.sv $R/muserisc_muldiv_mc.sv $R/muserisc_fpu_pkg.sv $R/muserisc_fpu.sv \
  $R/muserisc_bext_pkg.sv $R/muserisc_bext.sv $R/muserisc_vregfile.sv $R/muserisc_vec_pkg.sv \
  $R/muserisc_vec.sv $R/muserisc_rvc.sv $R/muserisc_decoder.sv $R/muserisc_csr.sv $R/muserisc_mmu.sv \
  $R/muserisc_cache_pkg.sv $R/muserisc_core.sv $R/muserisc_sram_sp.sv $R/muserisc_icache.sv \
  $R/muserisc_dcache.sv $R/muserisc_bus_arb.sv $R/muserisc_cpu.sv"
verilator $VFL --Mdir "$OUT/obj_core" --top-module muserisc_cpu "-GC1_BASE=64'h0" "-GC1_SIZE=64'h10000000" \
  -CFLAGS "-I$(pwd)/tb/cpp" -o "$(pwd)/$OUT/core_tb_vendor" $V $CPU "$(pwd)/tb/cpp/core_tb.cpp" \
  > "$OUT/build_core.log" 2>&1 || { tail -20 "$OUT/build_core.log"; exit 1; }
make -s -C sim directed-bins >/dev/null || exit 1
rc=0
for seed in 1 2 3; do
  (cd build/sim && "../../$OUT/vec_tb_vendor" +verilator+seed+$seed) > "$OUT/vec_$seed.log" 2>&1
  r=$(tail -n 1 "$OUT/vec_$seed.log")
  echo "$r [vendor OpenRAM models, X seed $seed]"
  case "$r" in "VEC TB PASS"*) ;; *) rc=1 ;; esac
done
rm -f build/sim/md_irq_*_vendor.log build/sim/fp_irq_*_vendor.log
drc=0
CORE_TB="$(pwd)/$OUT/core_tb_vendor" COV_PREFIX=nocov bash sim/run_directed.sh vendor \
  --mem-lat 1:6 --mem-gap 2 --mem-ready 70 > "$OUT/directed.log" 2>&1 || drc=1
echo "run_directed exit $drc: $(grep -c 'CORE TB PASS' "$OUT/directed.log") PASS lines [vendor OpenRAM models]"
[ $drc = 0 ] || rc=1
# The vendor's same-address read/write WARNING must never appear.
nw=$(cat "$OUT"/vec_*.log "$OUT/directed.log" build/sim/md_irq_*_vendor.log \
       build/sim/fp_irq_*_vendor.log 2>/dev/null | grep -c 'WARNING: Writing and reading')
echo "vendor same-address read/write warnings: $nw"
[ "$nw" = 0 ] || rc=1
exit $rc
