#!/usr/bin/env bash
# Yosys synthesis check of the L1 caches + bus arbiter on
# Nangate45 (OpenROAD-flow-scripts Docker image). The tag/data
# arrays (muserisc_sram_sp) are black boxes: they become SRAM
# macros (or FPGA BRAM), so the reported cell area is the
# cache control/datapath logic only; array sizes are listed
# separately from the elaborated black-box parameters.
#
# SystemVerilog is converted with sv2v (SV2V=/path/to/sv2v).
# Output: build/synth/caches.log (+ per-top stat reports).
set -euo pipefail
cd "$(dirname "$0")/.."
SV2V=${SV2V:-sv2v}
IMAGE=${ORFS_IMAGE:-openroad/orfs:latest}
OUT=build/synth
mkdir -p "$OUT"
"$SV2V" -DSYNTHESIS rtl/core/muserisc_cache_pkg.sv rtl/core/muserisc_icache.sv \
  rtl/core/muserisc_dcache.sv rtl/core/muserisc_bus_arb.sv > "$OUT/caches.v"
cat > "$OUT/sram_bb.v" <<'EOF'
(* blackbox *)
module muserisc_sram_sp #(parameter WIDTH = 64, parameter DEPTH = 64,
                          parameter LANES = 8) (
  input clk_i, input en_i, input [LANES-1:0] we_i,
  input [((DEPTH > 1) ? $clog2(DEPTH) : 1)-1:0] addr_i,
  input [WIDTH-1:0] wdata_i, output [WIDTH-1:0] rdata_o);
endmodule
EOF
cat > "$OUT/synth.ys" <<'EOF'
read_verilog -lib /work/build/synth/sram_bb.v
read_verilog -sv /work/build/synth/caches.v
EOF
for top in muserisc_icache muserisc_dcache muserisc_bus_arb; do
  cat >> "$OUT/synth.ys" <<EOF
design -save base
hierarchy -top $top
synth -flatten -top $top
dfflibmap -liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
abc -liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
opt_clean
tee -o /work/build/synth/stat_$top.txt stat -liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
design -load base
EOF
done
docker run --rm -v "$PWD:/work" -w /work "$IMAGE" bash -c \
  'PATH=/OpenROAD-flow-scripts/tools/install/yosys/bin:$PATH yosys -q -l /work/build/synth/caches.log /work/build/synth/synth.ys'
for top in muserisc_icache muserisc_dcache muserisc_bus_arb; do
  echo "== $top"
  grep -E "Chip area|Number of cells|muserisc_sram_sp" "$OUT/stat_$top.txt" || true
done
