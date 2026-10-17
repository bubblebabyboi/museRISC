#!/usr/bin/env bash
# Block-level synthesis + STA of one RTL unit on Nangate45, in the
# openroad/orfs image: Yosys (synth -flatten -booth, abc -D 10000)
# then OpenSTA (OpenROAD) at a 10 ns clock with zero input/output
# delays. A unit without clk_i is timed as pure combinational logic
# (input -> output). No placement, buffering or wire load: the
# numbers compare logic depth and cell area between designs, they are
# not a closure result.
#
# Usage: scripts/synth_unit_nangate45.sh <top> <file.sv>... [-- PARAM=VAL...]
#   e.g. scripts/synth_unit_nangate45.sh muserisc_muldiv_mc \
#          rtl/core/muserisc_muldiv.sv rtl/core/muserisc_muldiv_mc.sv
# Output: build/synth/<top>[_PARAMS]/{stat.txt,sta.log,net.v,yosys.log}
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -ge 2 ] || { sed -n 2,15p "$0"; exit 1; }
top=$1; shift
files=(); params=()
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; params=("$@"); break; fi
  files+=("$1"); shift
done
tag=$top
chparam=""
for p in "${params[@]+"${params[@]}"}"; do
  tag="${tag}_${p//=/}"
  chparam="$chparam chparam -set ${p%%=*} ${p#*=} $top;"
done
out=build/synth/$tag
mkdir -p "$out"
srcs=""
for f in "${files[@]}"; do srcs="$srcs /w/$f"; done

cat > "$out/sta.tcl" <<TCL
set P /OpenROAD-flow-scripts/flow/platforms/nangate45
read_lef \$P/lef/NangateOpenCellLibrary.tech.lef
read_lef \$P/lef/NangateOpenCellLibrary.macro.mod.lef
read_liberty \$P/lib/NangateOpenCellLibrary_typical.lib
read_verilog net.v
link_design $top
if {[llength [get_ports -quiet clk_i]]} {
  create_clock -name clk -period 10 [get_ports clk_i]
  set_input_delay 0 -clock clk [delete_from_list [all_inputs] [get_ports clk_i]]
} else {
  create_clock -name clk -period 10
  set_input_delay 0 -clock clk [all_inputs]
}
set_output_delay 0 -clock clk [all_outputs]
puts "== worst setup path"
report_checks -path_delay max -format full -digits 3
if {[llength [all_registers]]} {
  puts "== in -> reg"
  report_checks -path_delay max -from [all_inputs] -to [all_registers -data_pins] -digits 3 -format end
  puts "== reg -> reg"
  report_checks -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins] -digits 3 -format end
  puts "== reg -> out"
  report_checks -path_delay max -from [all_registers -clock_pins] -to [all_outputs] -digits 3 -format end
}
puts "== in -> out"
report_checks -path_delay max -from [all_inputs] -to [all_outputs] -digits 3 -format end
report_worst_slack -max -digits 3
TCL

start=$(date +%s)
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/w" -w "/w/$out" openroad/orfs:latest bash -c "
  set -e
  P=/OpenROAD-flow-scripts/flow/platforms/nangate45
  LIB=\$P/lib/NangateOpenCellLibrary_typical.lib
  /OpenROAD-flow-scripts/tools/install/yosys/bin/yosys -q -l yosys.log -p \"
    read_verilog -sv -DSYNTHESIS $srcs; $chparam
    synth -top $top -flatten -booth; dfflibmap -liberty \$LIB;
    abc -D 10000 -liberty \$LIB; opt_clean -purge; setundef -zero;
    hilomap -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z;
    tee -o stat.txt stat -liberty \$LIB; write_verilog -noattr net.v\"
  sed -i 's/wire signed/wire/' net.v   # OpenSTA's reader rejects it
  /OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad -no_init -exit sta.tcl > sta.log 2>&1
"
echo "$tag: $(grep 'Chip area' "$out/stat.txt" | awk '{print $NF}') um^2," \
     "worst setup slack $(grep 'worst slack' "$out/sta.log" | awk '{print $NF}') ns @ 10 ns" \
     "($(( $(date +%s) - start )) s)"
