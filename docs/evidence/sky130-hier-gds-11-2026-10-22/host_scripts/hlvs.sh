#!/bin/bash
# sigil-sky130 (hlvs.sh = lvs.sh with the -masters list braced): KLayout LVS (ORFS sky130hd.lylvs, sigil copy: threads, optional
# black boxes) of a routed GDS against a hierarchical CDL netlist.
# usage: lvs.sh <name> <results dir under ~/sb/build/results> <top cell> <threads> [extra cdl ...]
#   env BLANK="pat1,pat2"  circuits to black-box (contents removed in both netlists)
#   env FLATTEN="pat1,pat2"  layout-netlist circuits flattened before align/simplify
#   env GDS=<path in the container>  layout to check (default /results/<results dir>/6_final.gds,
#       e.g. /lvs/gds/<name>.gds written by flatvia.rb)
# Writes ~/sb/lvs/<name>/: <top>.cdl (write_cdl of 6_final.odb), concat.cdl,
# concat_lvs.cdl (concat.cdl without instances of device-less cells,
# cdl_drop_empty.py; drop_empty.log),
# lvs.lvsdb, extracted.cir, lvs.log
set -uo pipefail
N=$1; R=$2; T=$3; TH=$4; shift 4
O=~/sb/lvs/$N; mkdir -p $O
IMG=openroad/orfs@sha256:63981d1ac8990a9bee8bf874c95ee2c1ee3fe7b99f57d459282ab8c31a8ed663
P=/OpenROAD-flow-scripts/flow/platforms
EXTRA=""; for f in "$@"; do EXTRA="$EXTRA $f"; done
echo "$(date -u +%FT%TZ) START lvs-$N res=$R gds=${GDS:-6_final.gds} top=$T threads=$TH blank=${BLANK:-} flatten=${FLATTEN:-} extra=[$EXTRA]" >> ~/sb/STATUS
s=$(date +%s)
docker run --rm --name sky-lvs-$N -v ~/sb/build/results:/results:ro -v ~/sb/lvs:/lvs -v ~/sb/top/lvs:/t:ro \
  $IMG bash -lc "source ./env.sh >/dev/null
    set -e
    cd /lvs/$N
    echo 'read_db /results/$R/6_final.odb
write_cdl -masters {$P/sky130hd/cdl/sky130hd.cdl $EXTRA} /lvs/$N/$T.cdl' > wcdl.tcl
    openroad -exit -no_init wcdl.tcl > wcdl.log 2>&1
    cat $T.cdl $EXTRA $P/sky130hd/cdl/sky130hd.cdl > concat.cdl
    python3 /t/cdl_drop_empty.py concat.cdl concat_lvs.cdl > drop_empty.log
    sed 's/^threads(4)/threads($TH)/' /t/sky130hd_sigil.lylvs > deck.lylvs
    klayout -b -rd in_gds=${GDS:-/results/$R/6_final.gds} -rd cdl_file=/lvs/$N/concat_lvs.cdl \
      -rd top_cell=$T -rd report_file=/lvs/$N/lvs.lvsdb -rd target_netlist=/lvs/$N/extracted.cir \
      -rd blank='${BLANK:-}' -rd flatten='${FLATTEN:-}' -r deck.lylvs" > $O/lvs.log 2>&1
rc=$?
echo "$(date -u +%FT%TZ) END lvs-$N rc=$rc wall=$(( $(date +%s)-s ))s result=[$(grep -E 'Netlists match|Netlists don.t match' $O/lvs.log | tail -1)]" >> ~/sb/STATUS
