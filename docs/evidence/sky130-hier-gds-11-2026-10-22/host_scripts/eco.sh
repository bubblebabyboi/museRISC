#!/bin/bash
# sigil-sky130: post-route ECO (drt_eco_repair.tcl) of a routed top-level
# variant whose results were copied (cp -a) from t2, then make finish.
# usage: eco.sh <variant> <cores>   (t2 floorplan, snapshot a27e98feae5d)
set -uo pipefail
V=$1; C=$2
F=/OpenROAD-flow-scripts/flow
B="SIGIL_CPU_VARIANT=s116d SIGIL_CRYPTO_VARIANT=w34m"
FP='DIE_AREA="0 0 3715 4260" CORE_AREA="2 2 3713 4258" SIGIL_CPU_XY="305 10" SIGIL_CRYPTO_XY="305 3470"'
export SNAP=a27e98feae5d
~/sb/run.sh sigil_hier/config.mk top-$V-eco run $C FLOW_VARIANT=$V $B $FP RUN_SCRIPT=$F/designs/sky130hd/sigil_hier/drt_eco_repair.tcl RUN_LOG_NAME_STEM=5_2_route_eco SIGIL_ECO_SPEF=$F/results/sky130hd/sigil_hier/$V/6_final.spef SIGIL_NET_MAX_LEN=150 SIGIL_ECO_ROUNDS=3
grep -q "END top-$V-eco .* rc=0 " ~/sb/STATUS || exit 1
~/sb/run.sh sigil_hier/config.mk top-$V finish $C FLOW_VARIANT=$V $B $FP
