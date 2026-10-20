#!/usr/bin/env bash
# Synthesis check for the multi-cycle FPU (and optionally another
# core module) on Nangate45 with the Yosys + OpenSTA (openroad)
# bundled in the openroad/orfs image.
#
#   SV2V=/path/to/sv2v ./scripts/synth_fpu.sh [top] [period_ns]
#
# top defaults to muserisc_fpu, period to 2.0 ns. sv2v (v0.0.13)
# converts the SystemVerilog (packages, packed structs, `include)
# to Verilog-2005 with SYNTHESIS defined (drops the simulation
# cross-check); Yosys maps to the Nangate45 typical liberty with
# ABC delay-driven mapping at the target period; OpenSTA reports
# the worst register-to-register path after OpenROAD buffering /
# gate sizing (repair_design, repair_timing; ideal clock, no wire
# parasitics, inputs/outputs unconstrained). Outputs land in build/synth/<top>/.
set -euo pipefail
cd "$(dirname "$0")/.."
TOP="${1:-muserisc_fpu}"
PERIOD="${2:-2.0}"
SV2V="${SV2V:-sv2v}"
# ADDER=ripple (default, Yosys carry chains: conservative and fast)
# or ks (Kogge-Stone; ABC runtime grows to hours); ABC_DELAY=1 maps with ABC -D <period> (slow on large
# designs), 0 maps for area and leaves timing to OpenROAD
# repair_design/repair_timing (default).
ADDER="${ADDER:-ripple}"
ABC_DELAY="${ABC_DELAY:-0}"
OUT="build/synth/$TOP${OUT_TAG:-}"
mkdir -p "$OUT"

RTL="${RTL_DIR:-rtl/core}"
case "$TOP" in
  muserisc_fpu) SRCS="$RTL/muserisc_fpu_pkg.sv $RTL/muserisc_fpu.sv" ;;
  *) SRCS="$RTL/muserisc_pkg.sv $RTL/muserisc_regfile.sv \
       $RTL/muserisc_fpregfile.sv $RTL/muserisc_alu.sv $RTL/muserisc_muldiv.sv \
       $RTL/muserisc_fpu_pkg.sv $RTL/muserisc_fpu.sv $RTL/muserisc_bext_pkg.sv \
       $RTL/muserisc_bext.sv $RTL/muserisc_vregfile.sv $RTL/muserisc_vec_pkg.sv \
       $RTL/muserisc_vec.sv $RTL/muserisc_rvc.sv $RTL/muserisc_decoder.sv \
       $RTL/muserisc_csr.sv $RTL/muserisc_mmu.sv $RTL/muserisc_core.sv" ;;
esac
# SKIP_SYNTH=1 re-runs only the STA on the existing netlist;
# SV2V_FLAGS passes extra defines (e.g. -DMUSERISC_FPU_DS_BITS=1).
# shellcheck disable=SC2086
[ -n "${SKIP_SYNTH:-}" ] || "$SV2V" ${SV2V_FLAGS:-} -DSYNTHESIS -I"$RTL" --top="$TOP" $SRCS -w "$OUT/$TOP.v"
# sv2v turns elaboration-time $error (e.g. the FPU's div/sqrt
# configuration guard) into an initial $display; fail here instead.
if grep -q 'Error \[elaboration\]' "$OUT/$TOP.v"; then
  grep 'Error \[elaboration\]' "$OUT/$TOP.v"; echo "elaboration check failed"; exit 1
fi

LIB=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
PS=$(python3 -c "print(int(float('$PERIOD') * 1000))")
ABCD=""; [ "$ABC_DELAY" = 1 ] && ABCD="-D $PS"
# parallel-prefix (Kogge-Stone) carry logic instead of Yosys's
# default ripple \$lcu, as a production adder generator would give
KS=""; [ "$ADDER" = ks ] && KS="techmap -map +/techmap.v -map +/choices/kogge-stone.v"
cat > "$OUT/synth.ys" <<EOF
read_verilog -sv /work/$OUT/$TOP.v
synth -top $TOP -flatten -run :fine
$KS
synth -top $TOP -flatten -run fine: -noabc
opt_clean -purge
dfflibmap -liberty $LIB
abc $ABCD -liberty $LIB
opt_clean -purge
hilomap -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z
tee -o /work/$OUT/stat.txt stat -liberty $LIB
write_verilog -noattr /work/$OUT/${TOP}_net.v
EOF
LEF=/OpenROAD-flow-scripts/flow/platforms/nangate45/lef
cat > "$OUT/sta.tcl" <<EOF
read_lef $LEF/NangateOpenCellLibrary.tech.lef
read_lef $LEF/NangateOpenCellLibrary.macro.mod.lef
read_liberty $LIB
read_verilog /work/$OUT/${TOP}_net.v
link_design $TOP
create_clock -name clk -period $PERIOD [get_ports clk_i]
source /OpenROAD-flow-scripts/flow/platforms/nangate45/setRC.tcl
# Unplaced netlist: buffer high-fanout nets (state decode, stage
# enables) and size gates so the path delays are meaningful; wire
# parasitics are not modelled.
repair_design
repair_timing -setup
report_checks -path_delay max -group_path_count 3 -format full -fields {net fanout} -digits 3
report_tns
report_wns
report_clock_min_period
report_design_area
exit
EOF
docker run --rm -e SKIP_SYNTH="${SKIP_SYNTH:-}" -v "$PWD:/work" -w /work openroad/orfs:latest bash -lc "
  export PATH=/OpenROAD-flow-scripts/tools/install/yosys/bin:/OpenROAD-flow-scripts/tools/install/OpenROAD/bin:\$PATH
  { [ -n \"\${SKIP_SYNTH:-}\" ] || yosys -q -l /work/$OUT/yosys.log /work/$OUT/synth.ys; } &&
  openroad -exit -no_init /work/$OUT/sta.tcl > /work/$OUT/sta.txt 2>&1"
grep -E "Chip area|cells$" "$OUT/stat.txt" | head -5
grep -E "^(wns|tns)|period|slack" "$OUT/sta.txt" | head -8
echo "Results: $OUT/"
