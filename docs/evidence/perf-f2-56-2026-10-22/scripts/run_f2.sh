#!/bin/bash
# #56 benchmarks on the public Sigil AFI (agfi-035116450e0a0d093, 62.5 MHz)
# on an f2.6xlarge. Runs from ~/f2perf: bins/ (images, SHA256SUMS),
# host/ (fpga/host from 56-perf-harness), logs/ (output).
set -uo pipefail
cd ~/f2perf
AGFI=agfi-035116450e0a0d093
REPS=${REPS:-3}
mkdir -p logs
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a logs/run_f2.log; }
(cd bins && sha256sum -c SHA256SUMS) > logs/bins-sha256-check.log 2>&1 || { log "IMAGE CHECKSUM MISMATCH"; exit 3; }
# bench name for the exit marker: image name minus the variant suffix
bench_of() { case $1 in coremark*) echo coremark;; dhrystone*) echo dhrystone;; kernels*) echo kernels;;
  sha256chain_bulk*) echo sha256chain_bulk;; sha256chain*) echo sha256chain;; *) echo ${1%-default};; esac; }
run() { # image rep timeout
  local img=$1 rep=$2 to=$3 b; b=$(bench_of $img)
  local base=logs/$img.r$rep
  local t0; t0=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
  sudo ./host/sigil_host --ignore-mem-err --bin bins/$img.bin --timeout $to \
       --exit "SIGIL TEST PASS $b" --fail "SIGIL TEST FAIL" --log $base.uart > /dev/null 2> $base.host
  local rc=$?
  echo "start_utc $t0 rc $rc" >> $base.host
  log "$img r$rep rc=$rc $(grep -h 'result:' $base.host | sed 's/.*result: //')"
}
SHORT="dhrystone-scalar dhrystone-sdk coremark-scalar coremark-sdk coremark-validation kernels-scalar kernels-autovec
 micro_pipe-default micro_units-default micro_dmem-default micro_imem-default micro_vec-default sha256chain-sdk sha256chain_bulk-sdk"
log "start: $(sudo fpga-describe-local-image -S 0 -H | tail -1)"
for rep in $(seq 0 $((REPS-1))); do
  for img in $SHORT; do run $img $rep 60; done
done
for rep in 0 1; do
  for img in coremark-scalar-1000 coremark-validation-1000; do run $img $rep 120; done
done
log "done"
