#!/usr/bin/env bash
# #53 ASIC invariance (docs/FPGA_TIMING_53.md): each module that has
# FPGA_TIMING structures, elaborated with its default parameters
# (FPGA_TIMING = 0, the default / sky130 / nangate45 configurations),
# is proven equivalent to the REF (default origin/main) version with
# Yosys: equiv_make, equiv_struct, equiv_simple, equiv_induct.
# SystemVerilog is converted with sv2v (SV2V=/path/to/sv2v).
#   scripts/fpga_timing_equiv.sh [module ...]   (default: sigil_csr sigil_mmu)
# Logs: build/fpga_timing_equiv/<module>/eq.log. sigil_mmu takes ~45 min.
set -euo pipefail
cd "$(dirname "$0")/.."
SV2V=${SV2V:-sv2v}
REF=${REF:-origin/main}
mods=("$@")
[ ${#mods[@]} -gt 0 ] || mods=(sigil_csr sigil_mmu)
# Ports only this branch has, read only with FPGA_TIMING: internal wires
# (undriven, unused) for the proof.
declare -A extra_ports=([sigil_csr]="wr_intent_i"
  [sigil_mmu]="dl_va_i dl_write_i dl_exec_i dl_priv_i dl_virt_i dl_satp_i dl_sum_i dl_mxr_i dl_ld_i dl_vld_i")
rc=0
for mod in "${mods[@]}"; do
  d=build/fpga_timing_equiv/$mod
  rm -rf "$d"; mkdir -p "$d"
  git show "$REF:rtl/core/$mod.sv" > "$d/gold.sv"
  cp "rtl/core/$mod.sv" "$d/gate.sv"
  "$SV2V" -DSYNTHESIS "$d/gold.sv" > "$d/gold.v"
  "$SV2V" -DSYNTHESIS "$d/gate.sv" > "$d/gate.v"
  # Yosys rejects the unpacked arrays sv2v lists in sensitivity lists.
  perl -pi -e 's/always \@\((?!posedge|negedge)[^)]*\)/always \@*/' "$d/gold.v" "$d/gate.v"
  {
    echo "read_verilog -mem2reg $d/gold.v"
    echo "rename $mod gold"
    echo "read_verilog -mem2reg $d/gate.v"
    echo "rename $mod gate"
    for p in ${extra_ports[$mod]:-}; do echo "delete -port gate/w:$p"; done
    echo "hierarchy -check; proc; opt -purge; async2sync"
    echo "equiv_make gold gate equiv; hierarchy -top equiv"
    echo "equiv_struct; equiv_simple; equiv_induct; equiv_status -assert"
  } > "$d/eq.ys"
  t0=$(date +%s)
  if yosys -q -l "$d/eq.log" "$d/eq.ys" > /dev/null 2>&1; then r=EQUIVALENT; else r=FAILED; rc=1; fi
  echo "$mod vs $REF ($(git rev-parse --short "$REF")), FPGA_TIMING=0: $r," \
       "$(grep -oE '[0-9]+ are proven and [0-9]+ are unproven' "$d/eq.log" | tail -1)," \
       "$(( $(date +%s) - t0 )) s"
done
exit $rc
