#!/bin/bash
# Run every directed core test (sw/core-tests/) on build/sim/core_tb
# in one memory-system configuration. Called by `make -C sim core`
# once per configuration; each run writes its own coverage file
# cov_<test>_<TAG>.dat.
#
# Usage: [CORE_TB=./core_tb] [COV_PREFIX=cov] run_directed.sh TAG [core_tb options...]
# (the SRAM-macro and vendor-model runs use a COV_PREFIX the coverage
# merge skips)
#   e.g. run_directed.sh rand --mem-lat 1:6 --mem-gap 2 --mem-ready 70
#        run_directed.sh nocache --no-cache
#        CORE_TB=./core_tb_xinit run_directed.sh xinit1 +verilator+rand+reset+2 +verilator+seed+1
set -euo pipefail
TAG=$1; shift
EXTRA=("$@")
cd "$(dirname "$0")/../build/sim"
TB=${CORE_TB:-./core_tb}
COV_PREFIX=${COV_PREFIX:-cov}
seed=1
run() {
  local cov=$1; shift
  echo "[$TAG] core_tb $* ${EXTRA[*]} --mem-seed $seed"
  COV_FILE="${COV_PREFIX}_${cov}_${TAG}.dat" "$TB" "$@" "${EXTRA[@]}" --mem-seed "$seed"
  seed=$((seed + 1))
}
run rv64i rv64i_directed.bin
run rv64m rv64m_directed.bin
run md md_directed.bin
run mdkill md_kill_directed.bin
# Timer IRQ at every offset across a window wider than the
# longest M op (64-bit divide), as the pre-cache core target.
for o in $(seq 100 171); do
  echo "[$TAG] core_tb md_irq_directed.bin --irq-timer-after $o ${EXTRA[*]} --mem-seed $seed"
  COV_FILE="${COV_PREFIX}_mdirq_${o}_${TAG}.dat" "$TB" md_irq_directed.bin \
    --irq-timer-after "$o" "${EXTRA[@]}" --mem-seed "$seed" > "md_irq_${o}_${TAG}.log" 2>&1 ||
    { cat "md_irq_${o}_${TAG}.log"; exit 1; }
done
echo "CORE TB PASS md_irq_directed.bin [$TAG] (72/72 IRQ offsets 100..171)"
seed=$((seed + 1))
run amo amo_directed.bin
run fp fp_directed.bin
run fpstall fp_stall_directed.bin
# Timer IRQ at every offset across a window wider than the
# longest multi-cycle FP op (as the pre-cache core target).
for o in $(seq 100 147); do
  echo "[$TAG] core_tb fp_irq_directed.bin --irq-timer-after $o ${EXTRA[*]} --mem-seed $seed"
  COV_FILE="${COV_PREFIX}_fpirq_${o}_${TAG}.dat" "$TB" fp_irq_directed.bin \
    --irq-timer-after "$o" "${EXTRA[@]}" --mem-seed "$seed" > "fp_irq_${o}_${TAG}.log" 2>&1 ||
    { cat "fp_irq_${o}_${TAG}.log"; exit 1; }
done
echo "CORE TB PASS fp_irq_directed.bin [$TAG] (48/48 IRQ offsets 100..147)"
seed=$((seed + 1))
run bextsw bext_directed.bin
run rvcsw rvc_directed.bin
run pipeline pipeline_directed.bin
run priv priv_directed.bin 6000000 --irq-timer-after 2000
# Timer IRQ at every offset across a run of trapping misaligned
# loads: the interrupt must survive exceptions taken while it is
# pending (as the pre-cache core target).
for o in $(seq 20 120); do
  echo "[$TAG] core_tb irq_exc_race_directed.bin --irq-timer-after $o ${EXTRA[*]} --mem-seed $seed"
  COV_FILE="cov_irqexc_${o}_${TAG}.dat" "$TB" irq_exc_race_directed.bin \
    --irq-timer-after "$o" "${EXTRA[@]}" --mem-seed "$seed" > "irq_exc_${o}_${TAG}.log" 2>&1 ||
    { echo "offset $o:"; cat "irq_exc_${o}_${TAG}.log"; exit 1; }
done
echo "CORE TB PASS irq_exc_race_directed.bin [$TAG] (101/101 IRQ offsets 20..120)"
seed=$((seed + 1))
run vm vm_directed.bin
run trap_illegal trap_illegal.bin 100000 --expect-trap 2
run trap_misalign trap_misalign.bin 100000 --expect-trap 4
run trap_ecall trap_ecall.bin 100000 --expect-trap 11
run trap_ebreak trap_ebreak.bin 100000 --expect-trap 3
run trap_smisalign trap_store_misalign.bin 100000 --expect-trap 6
run trap_ystore trap_younger_store.bin 100000 --expect-trap 4
run trap_ycsr trap_younger_csr.bin
run counter_time counter_time_directed.bin
run hyp hyp_directed.bin
run vecsw vec_directed.bin 4000000
run fpvecsw fpvec_directed.bin 4000000
run vectrap vec_trap_directed.bin 4000000 --irq-timer-after 2000
run trap_pa_fetch trap_pa_fetch.bin 100000 --expect-trap 1
run trap_pa_load trap_pa_load.bin 100000 --expect-trap 5
# L1 cache / memory-interface directed tests
run smc_fencei smc_fencei_directed.bin
run amo_cache amo_cache_directed.bin
run mmio_bypass mmio_bypass_directed.bin
run vm_sfence_cache vm_sfence_cache_directed.bin
run fp_hold_cache fp_hold_cache_directed.bin
run ptw_drop ptw_drop_directed.bin
