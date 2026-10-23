#!/bin/bash
# sigil-sky130: per-corner STA of a routed block with the branch's corner_sta.tcl
# (setup split into block outputs vs internal endpoints), no timing model.
# usage: bsta.sh <results dir under ~/sb/build/results> <out dir> "<corners>"
set -uo pipefail
R=$1; O=$2; CS=$3
mkdir -p $O
IMG=openroad/orfs@sha256:63981d1ac8990a9bee8bf874c95ee2c1ee3fe7b99f57d459282ab8c31a8ed663
for c in $CS; do
  docker run --rm -v ~/sb/build/results/$R:/res:ro -v ~/sb/pdklib:/pdk:ro -v $O:/out \
    -v ~/sb/top/corner_sta.tcl:/corner_sta.tcl:ro \
    -e RES=/res -e CORNER=$c -e OUT=/out -e PDKLIB=/pdk -e MODEL=0 \
    $IMG bash -lc "source ./env.sh >/dev/null && openroad -exit -no_init /corner_sta.tcl" > $O/sta_$c.log 2>&1 &
done
wait
cat $O/sta_*.summary
