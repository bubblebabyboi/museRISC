#!/usr/bin/env bash
# Liberty-limit electrical signoff check for a finished ORFS run.
# The flow optimizes against a guardbanded SDC set_max_capacitance
# (repair target in flow/designs/nangate45/sigil_crypto/constraint.sdc),
# so the flow's own 6_finish.rpt counts pins over that guardband.
# This script re-checks the final routed database against liberty
# limits only (max cap / slew / fanout) plus timing, which is the
# signoff criterion used for the B3 evidence in docs/evidence/.
# Usage: [DESIGN=sigil_crypto|sigil_soc] \
#          ./scripts/orfs_liberty_check.sh [results-base-dir]
set -euo pipefail
cd "$(dirname "$0")/.."
DESIGN="${DESIGN:-sigil_crypto}"
BASE="${1:-build/orfs-results/nangate45/sigil_crypto_top/base}"
[ -f "$BASE/6_1_fill.odb" ] || { echo "no routed DB in $BASE (run make openroad first)"; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running"; exit 1; }

# SDC without the guardband line, so STA checks liberty limits only.
grep -v "set_max_capacitance" "flow/designs/nangate45/$DESIGN/constraint.sdc" > /tmp/orfs_signoff.sdc
cat > /tmp/orfs_liberty_signoff.tcl <<'EOF'
read_liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
read_db /results/6_1_fill.odb
read_sdc /signoff.sdc
read_spef /results/6_final.spef
puts "SIGNOFF max_capacitance violators (liberty limits):"
report_check_types -max_capacitance -violators
puts "SIGNOFF max_slew violators:"
report_check_types -max_slew -violators
puts "SIGNOFF max_fanout violators:"
report_check_types -max_fanout -violators
report_worst_slack -max
report_worst_slack -min
report_tns
report_power
EOF
docker run --rm --platform linux/amd64 \
  -v "$PWD/$BASE:/results" \
  -v /tmp/orfs_liberty_signoff.tcl:/signoff.tcl \
  -v /tmp/orfs_signoff.sdc:/signoff.sdc \
  openroad/orfs:latest \
  bash -lc 'source ./env.sh && openroad -no_init -exit /signoff.tcl'
