#!/usr/bin/env bash
# Vector-unit area / logic-depth snapshot (issue #32 timing
# work): Yosys + OpenSTA from the openroad/orfs image against
# the Nangate45 typical liberty (Kogge-Stone carry networks, ORFS abc_speed script with buffering/sizing,
# delay-driven ABC mapping at PERIOD ns, no wire load). FP (fp_eval / fp_estimate) is
# black-boxed via flow/vec-synth/fpu_stub_pkg.sv; VRF RAM
# banks (muserisc_vrf_bank) are black-boxed as SRAM macros.
#
# Usage: scripts/synth_vec.sh <rtl-dir> <out-dir> [top...]
#   <rtl-dir> holds muserisc_vec.sv and muserisc_vregfile.sv
#   (rtl/core for the current design, or a saved copy of an
#   older revision); tops default to muserisc_vec and
#   muserisc_vregfile. Needs sv2v on PATH (or SV2V=...) and
#   docker with openroad/orfs:latest.
set -euo pipefail
cd "$(dirname "$0")/.."
RTL=$(readlink -f "$1"); OUT=$2; shift 2
TOPS=${*:-muserisc_vec muserisc_vregfile}
SV2V=${SV2V:-sv2v}
PERIOD=${PERIOD:-10.0}
mkdir -p "$OUT"; OUT=$(readlink -f "$OUT")
# Pinned sv2v (results in docs/evidence were produced with v0.0.13;
# v0.0.12 reproduces within ~1%). Override with SV2V_VERSION=any.
SV2V_PIN=${SV2V_VERSION:-v0.0.13}
SV2V_HAVE=$("$SV2V" --version | awk '{print $2}')
if [ "$SV2V_PIN" != any ] && [ "$SV2V_HAVE" != "$SV2V_PIN" ]; then
  echo "sv2v $SV2V_HAVE found, $SV2V_PIN required (SV2V_VERSION=any to override)"; exit 1
fi
echo "sv2v $SV2V_HAVE" > "$OUT/tool-versions.txt"
LIB=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
"$SV2V" -DSYNTHESIS rtl/core/muserisc_pkg.sv rtl/core/muserisc_vec_pkg.sv \
  flow/vec-synth/fpu_stub_pkg.sv "$RTL/muserisc_vec.sv" > "$OUT/muserisc_vec.v"
"$SV2V" rtl/core/muserisc_pkg.sv "$RTL/muserisc_vregfile.sv" > "$OUT/muserisc_vregfile.v"
for top in $TOPS; do
  src=$OUT/$top.v
  cat > "$OUT/$top.ys" <<EOF
read_verilog /out/$top.v
hierarchy -top $top
$(grep -q 'module muserisc_vrf_bank' "$src" && echo "blackbox muserisc_vrf_bank")
synth -flatten -top $top -run begin:fine
techmap -map +/techmap.v -map +/choices/kogge-stone.v
synth -flatten -top $top -run fine:
tee -o /out/$top.ltp.txt ltp -noff
dfflibmap -liberty $LIB
abc -D $(awk "BEGIN{print int($PERIOD*1000)}") -script /OpenROAD-flow-scripts/flow/scripts/abc_speed.script -liberty $LIB
opt_clean -purge
tee -o /out/$top.stat.txt stat -liberty $LIB
autoname
write_verilog -noattr /out/$top.net.v
EOF
  cat > "$OUT/$top.sta.tcl" <<EOF
read_lef /OpenROAD-flow-scripts/flow/platforms/nangate45/lef/NangateOpenCellLibrary.tech.lef
read_lef /OpenROAD-flow-scripts/flow/platforms/nangate45/lef/NangateOpenCellLibrary.macro.lef
read_liberty $LIB
read_verilog /out/$top.net.v
link_design $top
create_clock -name clk -period $PERIOD [get_ports -quiet clk_i]
if {[llength [get_ports -quiet clk_i]] == 0} { create_clock -name clk -period $PERIOD }
set_input_delay 0 -clock clk [delete_from_list [all_inputs] [get_ports -quiet clk_i]]
set_output_delay 0 -clock clk [all_outputs]
set_false_path -from [get_ports -quiet rst_ni]
report_checks -path_delay max -group_path_count 5 -digits 3 -fields {fanout} > /out/$top.sta.txt
report_tns >> /out/$top.sta.txt
report_wns >> /out/$top.sta.txt
EOF
  echo "== $top: yosys"
  start=$(date +%s)
  docker run --rm -v "$OUT:/out" openroad/orfs:latest bash -lc \
    "/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys -q -l /out/$top.yosys.log /out/$top.ys" \
    || { echo "yosys failed for $top"; continue; }
  echo "   yosys $(( $(date +%s) - start ))s"
  # STA needs every instance to resolve to a liberty cell, so it
  # is skipped for netlists with black-boxed SRAM banks (the
  # VRF's own logic is the write bypass mux; see ltp depth).
  if ! grep -q 'module muserisc_vrf_bank' "$src"; then
    docker run --rm -v "$OUT:/out" openroad/orfs:latest bash -lc \
      "/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad -no_init -exit /out/$top.sta.tcl" \
      > "$OUT/$top.sta.log" 2>&1 || echo "sta failed for $top"
  fi
  grep -i 'chip area' "$OUT/$top.stat.txt" || true
  grep -i 'longest' "$OUT/$top.ltp.txt" || true
  [ -f "$OUT/$top.sta.txt" ] && grep -E 'wns|tns' "$OUT/$top.sta.txt" || true
done
