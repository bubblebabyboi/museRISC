#!/usr/bin/env bash
# #53 ASIC invariance (docs/FPGA_TIMING_53.md): each module that has
# FPGA_TIMING structures, elaborated with its default parameters
# (FPGA_TIMING = 0, the default / sky130 / nangate45 configurations),
# is proven equivalent to the REF (default origin/main) version with
# Yosys: equiv_make, equiv_struct, equiv_simple, equiv_induct.
# SystemVerilog is converted with sv2v (SV2V=/path/to/sv2v); YOSYS
# picks the Yosys binary.
#   scripts/fpga_timing_equiv.sh [module ...]   (default: sigil_csr sigil_mmu sigil_dcache sigil_icache)
#   REF=origin/73-oops-fix scripts/fpga_timing_equiv.sh sigil_core sigil_mmu ...
# REF is the branch the FPGA_TIMING=0 logic must equal (a branch that
# merges #53 onto another base, e.g. 53-100mhz-afi on 73-oops-fix,
# proves against that base).
# Logs: build/fpga_timing_equiv/<module>/eq.log. sigil_mmu takes ~45 min;
# sigil_dcache / sigil_icache read sigil_cache_pkg from the same side.
# sigil_core (not in the default list): its submodules are black boxes
# with the REF port lists, and the packages come from the same side.
# Its sigil_csr / sigil_mmu instances drop the FPGA_TIMING override and
# the FPGA-only ports (wr_intent_i, dl_*_i) before conversion; the
# sigil_csr / sigil_mmu proofs show those ports are unread with
# FPGA_TIMING=0 (they are free wires there), so this is sound only
# together with those two proofs.
set -euo pipefail
cd "$(dirname "$0")/.."
SV2V=${SV2V:-sv2v}
YOSYS=${YOSYS:-yosys}
REF=${REF:-origin/main}
mods=("$@")
[ ${#mods[@]} -gt 0 ] || mods=(sigil_csr sigil_mmu sigil_dcache sigil_icache)
# Ports only this branch has, read only with FPGA_TIMING: internal wires
# (undriven, unused) for the proof.
extra_ports() {
  case $1 in
    sigil_csr) echo "wr_intent_i" ;;
    sigil_mmu) echo "dl_va_i dl_write_i dl_exec_i dl_priv_i dl_virt_i dl_satp_i dl_sum_i dl_mxr_i dl_ld_i dl_vld_i" ;;
  esac
}
CORE_PKGS="sigil_pkg sigil_cache_pkg sigil_fpu_pkg sigil_bext_pkg sigil_vec_pkg"
CORE_SUBS="sigil_rvc sigil_decoder sigil_regfile sigil_fpregfile sigil_alu sigil_fpu
           sigil_vregfile sigil_vec sigil_bext sigil_muldiv sigil_muldiv_mc sigil_csr sigil_mmu"
rc=0
for mod in "${mods[@]}"; do
  d=build/fpga_timing_equiv/$mod
  rm -rf "$d"; mkdir -p "$d"
  git show "$REF:rtl/core/$mod.sv" > "$d/gold.sv"
  cp "rtl/core/$mod.sv" "$d/gate.sv"
  gold_pkg=(); gate_pkg=(); lib=""
  if [ "$mod" = sigil_core ]; then
    # Packages (and the FPU include) from each side; submodules as
    # REF black boxes.
    mkdir -p "$d/gold_inc" "$d/gate_inc"
    git show "$REF:rtl/core/sigil_fpu_ops.svh" > "$d/gold_inc/sigil_fpu_ops.svh"
    cp rtl/core/sigil_fpu_ops.svh "$d/gate_inc/sigil_fpu_ops.svh"
    for p in $CORE_PKGS; do
      git show "$REF:rtl/core/$p.sv" > "$d/gold_$p.sv"
      cp "rtl/core/$p.sv" "$d/gate_$p.sv"
      gold_pkg+=("$d/gold_$p.sv"); gate_pkg+=("$d/gate_$p.sv")
    done
    subs=()
    for s in $CORE_SUBS; do git show "$REF:rtl/core/$s.sv" > "$d/bb_$s.sv"; subs+=("$d/bb_$s.sv"); done
    "$SV2V" -DSYNTHESIS -I"$d/gold_inc" "${gold_pkg[@]}" "${subs[@]}" > "$d/bb.v"
    lib="$d/bb.v"
    n=$(grep -cE '^\s*\.(dl_[a-z]+_i|wr_intent_i)\s*\(' "$d/gate.sv" || true)
    m=$(grep -cE 'sigil_(csr|mmu) #\(\.FPGA_TIMING\(FPGA_TIMING\)\) u_(csr|mmu) \(' "$d/gate.sv" || true)
    [ "$n" = 11 ] && [ "$m" = 2 ] || { echo "$mod: expected 11 FPGA-only port connections and 2 overrides, found $n / $m"; exit 1; }
    perl -ni -e 'print unless /^\s*\.(dl_[a-z]+_i|wr_intent_i)\s*\(/' "$d/gate.sv"
    perl -pi -e 's/sigil_(csr|mmu) #\(\.FPGA_TIMING\(FPGA_TIMING\)\) u_/sigil_$1 u_/' "$d/gate.sv"
    inc_gold=(-I"$d/gold_inc"); inc_gate=(-I"$d/gate_inc")
  else
    # Modules that import sigil_cache_pkg (the caches) read it from the
    # same side, with SIGIL_FPGA_TIMING undefined; their (unchanged)
    # sigil_sram_sp arrays are black boxes, so the proof covers every
    # array port.
    if grep -q "sigil_cache_pkg" "$d/gate.sv"; then
      git show "$REF:rtl/core/sigil_cache_pkg.sv" > "$d/gold_pkg.sv"
      cp rtl/core/sigil_cache_pkg.sv "$d/gate_pkg.sv"
      gold_pkg=("$d/gold_pkg.sv"); gate_pkg=("$d/gate_pkg.sv")
    fi
    if grep -q "sigil_sram_sp" "$d/gate.sv"; then
      "$SV2V" -DSYNTHESIS rtl/core/sigil_cache_pkg.sv rtl/core/sigil_sram_sp.sv > "$d/sram.v"
      lib="$d/sram.v"
    fi
    inc_gold=(); inc_gate=()
  fi
  "$SV2V" -DSYNTHESIS ${inc_gold[@]+"${inc_gold[@]}"} ${gold_pkg[@]+"${gold_pkg[@]}"} "$d/gold.sv" > "$d/gold.v"
  "$SV2V" -DSYNTHESIS ${inc_gate[@]+"${inc_gate[@]}"} ${gate_pkg[@]+"${gate_pkg[@]}"} "$d/gate.sv" > "$d/gate.v"
  # Yosys rejects the unpacked arrays sv2v lists in sensitivity lists.
  perl -pi -e 's/always \@\((?!posedge|negedge)[^)]*\)/always \@*/' "$d/gold.v" "$d/gate.v" ${lib:+"$lib"}
  {
    [ -z "$lib" ] || echo "read_verilog -lib -mem2reg $lib"
    echo "read_verilog -mem2reg $d/gold.v"
    echo "rename $mod gold"
    echo "read_verilog -mem2reg $d/gate.v"
    echo "rename $mod gate"
    for p in $(extra_ports "$mod"); do echo "delete -port gate/w:$p"; done
    echo "hierarchy -check; proc; opt -purge; async2sync"
    echo "equiv_make gold gate equiv; hierarchy -top equiv"
    echo "equiv_struct; equiv_simple; equiv_induct; equiv_status -assert"
  } > "$d/eq.ys"
  t0=$(date +%s)
  if "$YOSYS" -q -l "$d/eq.log" "$d/eq.ys" > /dev/null 2>&1; then r=EQUIVALENT; else r=FAILED; rc=1; fi
  echo "$mod vs $REF ($(git rev-parse --short "$REF")), FPGA_TIMING=0: $r," \
       "$(grep -oE '[0-9]+ are proven and [0-9]+ are unproven' "$d/eq.log" | tail -1)," \
       "$(( $(date +%s) - t0 )) s"
done
exit $rc
