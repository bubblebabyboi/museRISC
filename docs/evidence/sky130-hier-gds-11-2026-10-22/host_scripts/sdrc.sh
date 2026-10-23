#!/bin/bash
# sigil-sky130: KLayout DRC with the sigil copy of the ORFS sky130hd deck
# (~/sb/top/drc2/sky130hd_sigil.lydrc).
# usage: sdrc.sh <name> <gds path inside the container> [-rd key=value ...]
#   GDS paths: /results/... (= ~/sb/build/results) or the image's
#   /OpenROAD-flow-scripts/flow/platforms/...
# Writes ~/sb/drc/<name>/{drc.lyrdb,drc.log}; START/END lines in ~/sb/STATUS.
set -uo pipefail
N=$1; G=$2; shift 2; X="$*"
O=~/sb/drc/$N; mkdir -p $O
IMG=openroad/orfs@sha256:63981d1ac8990a9bee8bf874c95ee2c1ee3fe7b99f57d459282ab8c31a8ed663
echo "$(date -u +%FT%TZ) START drc-$N gds=$G args=[$X]" >> ~/sb/STATUS
s=$(date +%s)
docker run --rm --name sky-drc-$N -v ~/sb/build/results:/results:ro -v ~/sb/drc:/drc -v ~/sb/top/drc2:/d:ro \
  $IMG bash -lc "source ./env.sh >/dev/null; klayout -v; /usr/bin/time -v klayout -b -rd in_gds=$G -rd report_file=/drc/$N/drc.lyrdb $X -r /d/sky130hd_sigil.lydrc" > $O/drc.log 2>&1
rc=$?
echo "$(date -u +%FT%TZ) END drc-$N rc=$rc wall=$(( $(date +%s)-s ))s markers=$(grep -c '<item>' $O/drc.lyrdb 2>/dev/null)" >> ~/sb/STATUS
