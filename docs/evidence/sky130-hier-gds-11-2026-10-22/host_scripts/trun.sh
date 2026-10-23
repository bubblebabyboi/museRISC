#!/bin/bash
# sigil-sky130: top-level (sigil_soc_top) flow with the hardened blocks.
# usage: trun.sh <variant> <snap sha> <cores> [extra make args...]
# synth against the block stubs (SIGIL_TOP_SYNTH=1), then floorplan .. finish.
set -uo pipefail
V=$1; SN=$2; C=$3; shift 3; X="$*"
B="SIGIL_CPU_VARIANT=s116d SIGIL_CRYPTO_VARIANT=w34m"
export SNAP=$SN
~/sb/run.sh sigil_hier/config.mk top-$V-syn synth 4 FLOW_VARIANT=$V SIGIL_TOP_SYNTH=1 $B $X || exit 1
grep -q "END top-$V-syn .* rc=0 " ~/sb/STATUS || exit 1
~/sb/run.sh sigil_hier/config.mk top-$V finish $C FLOW_VARIANT=$V $B $X
