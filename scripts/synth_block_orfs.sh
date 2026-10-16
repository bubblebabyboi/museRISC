#!/usr/bin/env bash
# Per-block synthesis with the same ORFS Yosys flow as a full-SoC
# run (slang frontend, ORFS synth.tcl/abc script, Nangate45), in the
# openroad/orfs image, then OpenSTA on the unrepaired netlist (liberty
# wire-load model, no placement or timing repair: the same view as
# a post-synthesis SoC report) at a 10 ns clock with zero I/O
# delays. Reports the worst reg->reg, in->reg, reg->out and in->out
# paths and the synthesized area.
#
# Usage: scripts/synth_block_orfs.sh <tag> <src-root> <top> <file>...
#   <tag>       output name: letters, digits, '_', '.', '-' only
#   <src-root>  tree holding rtl/ (the repo, or e.g. a `git archive`
#               of another revision for a before/after comparison);
#               a relative path is taken from the caller's directory
#   <file>...   sources relative to <src-root>, packages first
#   e.g. scripts/synth_block_orfs.sh plic . muserisc_plic rtl/soc/muserisc_plic.sv
# Output: build/orfs-blk/<tag>/ in this repo (reports/sta_unrepaired.txt,
#   reports/nangate45/<tag>/base/synth_stat.txt, logs/).
# Image: openroad/orfs pinned by digest (ORFS_IMAGE overrides).
set -euo pipefail
SELF=$(readlink -f "$0")
[ $# -ge 4 ] || { sed -n 2,22p "$SELF"; exit 1; }
TAG=$1; TOP=$3
# The tag names a directory that is deleted and recreated below.
if ! [[ $TAG =~ ^[A-Za-z0-9_.-]+$ ]] || [ "$TAG" = . ] || [ "$TAG" = .. ]; then
  echo "bad tag '$TAG' (allowed: [A-Za-z0-9_.-]+, not . or ..)" >&2; exit 1
fi
[[ $TOP =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "bad top '$TOP'" >&2; exit 1; }
SRC=$(readlink -f "$2")   # before the cd: relative to the caller
[ -d "$SRC" ] || { echo "no src-root $2" >&2; exit 1; }
shift 3
FILES=""
for f in "$@"; do
  case "$f" in /*|../*|*/../*|*/..) echo "source '$f' must be relative to <src-root>, without .." >&2; exit 1 ;; esac
  [ -f "$SRC/$f" ] || { echo "no file $SRC/$f" >&2; exit 1; }
  FILES="$FILES \$(DESIGN_HOME)/src/blk/$f"
done
IMAGE=${ORFS_IMAGE:-openroad/orfs@sha256:63981d1ac8990a9bee8bf874c95ee2c1ee3fe7b99f57d459282ab8c31a8ed663}
cd "$(dirname "$SELF")/.."
B=$PWD/build/orfs-blk/$TAG
rm -rf "$B"; mkdir -p "$B"/{design,results,logs,reports,objects}
cat > "$B/design/config.mk" <<EOF
export DESIGN_NAME = $TOP
export DESIGN_NICKNAME = $TAG
export PLATFORM    = nangate45
export SYNTH_HDL_FRONTEND = slang
export SYNTH_SLANG_ARGS = --unroll-limit=200000 -DSYNTHESIS
export VERILOG_FILES = $FILES
export VERILOG_INCLUDE_DIRS = \$(DESIGN_HOME)/src/blk/rtl/core
export SDC_FILE = \$(DESIGN_HOME)/nangate45/blk/constraint.sdc
export CLOCK_PERIOD = 10
export CORE_UTILIZATION = 20
EOF
cat > "$B/design/constraint.sdc" <<'EOF'
create_clock [get_ports clk_i] -period 10.0 -name core_clock
set_input_delay  0 -clock core_clock [delete_from_list [all_inputs] [get_ports clk_i]]
set_output_delay 0 -clock core_clock [all_outputs]
EOF
cat > "$B/design/sta.tcl" <<'EOF'
read_liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
read_db $::env(ODB)
read_sdc /OpenROAD-flow-scripts/flow/designs/nangate45/blk/constraint.sdc
# Data inputs: the async reset is not a timing path.
set din [delete_from_list [all_inputs] [get_ports -quiet {clk_i rst_ni}]]
puts "==== reg->reg"
report_checks -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins] -format full -digits 3
puts "==== in->reg"
report_checks -path_delay max -from $din -to [all_registers -data_pins] -format full -digits 3
puts "==== reg->out"
report_checks -path_delay max -from [all_registers -clock_pins] -to [all_outputs] -format end -digits 3
puts "==== in->out"
report_checks -path_delay max -from $din -to [all_outputs] -format end -digits 3
puts "==== summary"
report_wns -digits 3
EOF
start=$(date +%s)
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$B/design:/OpenROAD-flow-scripts/flow/designs/nangate45/blk" \
  -v "$SRC:/OpenROAD-flow-scripts/flow/designs/src/blk:ro" \
  -v "$B/results:/OpenROAD-flow-scripts/flow/results" \
  -v "$B/logs:/OpenROAD-flow-scripts/flow/logs" \
  -v "$B/reports:/OpenROAD-flow-scripts/flow/reports" \
  -v "$B/objects:/OpenROAD-flow-scripts/flow/objects" \
  "$IMAGE" bash -lc "source ./env.sh >/dev/null && cd flow && \
    make DESIGN_CONFIG=designs/nangate45/blk/config.mk synth > logs/make_synth.log 2>&1 && \
    ODB=\$(ls results/nangate45/$TAG/base/1_synth.odb 2>/dev/null || ls results/nangate45/$TAG/base/1_2_yosys.odb) && \
    ODB=\$ODB openroad -exit -no_init designs/nangate45/blk/sta.tcl > reports/sta_unrepaired.txt 2>&1"
echo "$TAG ($TOP): $(( $(date +%s) - start )) s wall"
grep -h "Chip area" "$B/reports/nangate45/$TAG/base/synth_stat.txt" | tail -1
grep -E "^====|data arrival|^Startpoint|^Endpoint|\((MET|VIOLATED)\)|^wns" "$B/reports/sta_unrepaired.txt" |
  grep -v -e "-.*data arrival" -e "slack"
