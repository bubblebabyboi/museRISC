#!/bin/bash
# sigil-sky130: per-corner signoff STA of the routed top level
# (corner_sta.tcl of the branch + the blocks' per-corner timing models).
# usage: [STAGE=..] tsta.sh <top variant> <out dir> "<corners>"
set -uo pipefail
V=$1; O=$2; CS=$3
mkdir -p $O
IMG=openroad/orfs@sha256:63981d1ac8990a9bee8bf874c95ee2c1ee3fe7b99f57d459282ab8c31a8ed663
BL="/sta/cpu-s116d/sigil_cpu_%c.lib /sta/crypto-w34m/sigil_crypto_top_%c.lib"
for c in $CS; do
  docker run --rm -v ~/sb/build/results/sky130hd/sigil_hier/$V:/res:ro -v ~/sb/pdklib:/pdk:ro -v $O:/out \
    -v ~/sb/top/corner_sta.tcl:/corner_sta.tcl:ro -v ~/sb/sta:/sta:ro \
    -e RES=/res -e CORNER=$c -e OUT=/out -e PDKLIB=/pdk -e MODEL=0 -e STAGE=${STAGE:-} -e BLOCK_LIBS="$BL" \
    $IMG bash -lc "source ./env.sh >/dev/null && openroad -exit -no_init /corner_sta.tcl" > $O/sta_$c.log 2>&1 &
done
wait
cat $O/sta_*.summary
