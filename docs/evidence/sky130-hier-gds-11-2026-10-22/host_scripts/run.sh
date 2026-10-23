#!/bin/bash
# sigil-sky130: run ORFS (pinned image) for the sky130 hierarchical flow.
# usage: run.sh <config.mk under designs/sky130hd> <name> "<make targets>" <cores> [make args...]
# Each run mounts a snapshot of the sigil repo at commit $SNAP (default:
# ~/sigil HEAD) from ~/sb/src/<sha>, so later commits/pulls never change a
# running job's config. Resume a variant with the SNAP it started with
# (git archive mtimes = commit time; a newer snapshot re-triggers stages).
# All designs share ~/sb/build (the top reads the block results from it).
set -uo pipefail
CFG=$1; N=$2; T=$3; C=$4; shift 4; X="$*"
R=~/sigil; B=~/sb; O=$B/build
SNAP=${SNAP:-$(git -C $R rev-parse --short=12 HEAD)}
S=$B/src/$SNAP
if [ ! -d $S ]; then
  rm -rf $S.tmp; mkdir -p $S.tmp
  git -C $R archive $SNAP rtl flow/designs/sky130hd/sigil_soc flow/designs/sky130hd/sigil_hier | tar -x -C $S.tmp || exit 1
  mv $S.tmp $S
fi
mkdir -p $O/results $O/logs $O/reports $O/objects $B/runlogs
IMG=openroad/orfs@sha256:63981d1ac8990a9bee8bf874c95ee2c1ee3fe7b99f57d459282ab8c31a8ed663
F=/OpenROAD-flow-scripts/flow
s=$(date +%s)
echo "$(date -u +%FT%TZ) START $N snap=$SNAP cfg=$CFG target=[$T] extra=[$X] cores=$C" >> $B/STATUS
docker run --rm --name sky-$N \
  -v "$S/flow/designs/sky130hd/sigil_soc:$F/designs/sky130hd/sigil_soc" \
  -v "$S/flow/designs/sky130hd/sigil_hier:$F/designs/sky130hd/sigil_hier" \
  -v "$S/rtl:$F/designs/src/sigil_soc" \
  -v "$O/results:$F/results" -v "$O/logs:$F/logs" \
  -v "$O/reports:$F/reports" -v "$O/objects:$F/objects" \
  $IMG bash -lc "source ./env.sh && ${PRE:-} cd flow && make DESIGN_CONFIG=designs/sky130hd/$CFG NUM_CORES=$C $X $T" > $B/runlogs/$N.log 2>&1
rc=$?
echo "$(date -u +%FT%TZ) END $N snap=$SNAP cfg=$CFG target=[$T] extra=[$X] cores=$C rc=$rc wall=$(( $(date +%s)-s ))s" >> $B/STATUS
