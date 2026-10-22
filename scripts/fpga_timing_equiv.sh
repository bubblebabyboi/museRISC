#!/usr/bin/env bash
# #53 ASIC invariance (docs/FPGA_TIMING_53.md): each module that has
# FPGA_TIMING structures, elaborated with its default parameters
# (FPGA_TIMING = 0, the default / sky130 / nangate45 configurations),
# is proven equivalent to the REF (default origin/main) version with
# Yosys: equiv_make, equiv_struct, equiv_simple, equiv_induct.
# SystemVerilog is converted with sv2v (SV2V=/path/to/sv2v); YOSYS
# picks the Yosys binary.
#   scripts/fpga_timing_equiv.sh [module ...]
#   (default: sigil_csr sigil_mmu sigil_dcache sigil_icache sigil_core)
#   REF=origin/73-oops-fix scripts/fpga_timing_equiv.sh
# REF is the branch the FPGA_TIMING=0 logic must equal (a branch that
# merges #53 onto another base, e.g. 53-100mhz-afi on 73-oops-fix,
# proves against that base). Runs under macOS /bin/bash 3.2.
# Logs: build/fpga_timing_equiv/<module>/eq*.log. sigil_mmu takes ~45-70 min;
# sigil_dcache / sigil_icache read sigil_cache_pkg from the same side.
# sigil_core is proven in the default and SIGIL_SRAM_OREG configurations.
set -euo pipefail
cd "$(dirname "$0")/.."
SV2V=${SV2V:-sv2v}
YOSYS=${YOSYS:-yosys}
REF=${REF:-origin/main}
# Newer Yosys (0.69) stops equiv_simple / equiv_induct at a cell with no
# SAT model (the sigil_core proof's black boxes) unless told to ignore
# it; 0.33 only warns. Either way the paired black box's outputs are
# free signals shared by both sides.
IGN=""
if "$YOSYS" -h equiv_induct 2>/dev/null | grep -e -ignore-unknown-cells > /dev/null; then
  IGN=" -ignore-unknown-cells"
fi
mods=("$@")
[ ${#mods[@]} -gt 0 ] || mods=(sigil_csr sigil_mmu sigil_dcache sigil_icache sigil_core)
# Ports only this branch has, read only with FPGA_TIMING: internal wires
# (undriven, unused) for the proof.
extra_ports() {
  case $1 in
    sigil_csr) echo "wr_intent_i" ;;
    sigil_mmu) echo "dl_va_i dl_write_i dl_exec_i dl_priv_i dl_virt_i dl_satp_i dl_sum_i dl_mxr_i dl_ld_i dl_vld_i" ;;
  esac
}
rc=0
# sigil_core: the core's own logic. Its submodule instances are black
# boxes that equiv_make pairs (inputs proven equal, outputs merged):
# sigil_csr and sigil_mmu, proven on their own, and the leaves, whose
# sources must be unchanged. The gate's FPGA_TIMING-only connections and
# parameter overrides go, as those ports do in the module proofs.
core_eq() {
  local d=build/fpga_timing_equiv/sigil_core changed srcs cfg r t0
  rm -rf "$d"; mkdir -p "$d/gold"
  changed=$(git diff --name-only "$REF" -- rtl/core |
            grep -vE '/sigil_(cache_pkg|core|csr|mmu|dcache|icache)\.sv$' || true)
  if [ -n "$changed" ]; then
    echo "sigil_core: black-boxed sources differ from $REF:" $changed; rc=1; return
  fi
  git archive "$REF" rtl/core | tar x -C "$d/gold"
  srcs=$(sed -n '/^SIGIL_SOC_RTL/,/^$/p' rtl/sigil_soc_files.mk | grep -oE 'core/[a-z_0-9]+\.sv' |
         grep -vE 'sram_sp|icache|dcache|bus_arb|sigil_cpu')
  for cfg in default SIGIL_SRAM_OREG; do
    local def=(); [ $cfg = default ] || def=("-D$cfg")
    # shellcheck disable=SC2046
    "$SV2V" -DSYNTHESIS ${def[@]+"${def[@]}"} -I"$d/gold/rtl/core" $(sed "s|^|$d/gold/rtl/|" <<< "$srcs") > "$d/gold.v"
    # shellcheck disable=SC2046
    "$SV2V" -DSYNTHESIS ${def[@]+"${def[@]}"} -Irtl/core $(sed 's|^|rtl/|' <<< "$srcs") > "$d/gate.v"
    perl -pi -e 's/always \@\((?!posedge|negedge)[^)]*\)/always \@*/' "$d/gold.v" "$d/gate.v"
    perl -ni -e 's/sigil_(csr|mmu) #\(\.FPGA_TIMING\([^)]*\)\) u_/sigil_$1 u_/;
                 print unless /^\s*\.(wr_intent_i|dl_[a-z]+_i)\(/' "$d/gate.v"
    {
      for side in gold gate; do
        echo "read_verilog -mem2reg $d/$side.v"
        echo "hierarchy -check -top sigil_core"
        echo "blackbox *sigil_regfile* *sigil_fpregfile* *sigil_alu* *sigil_muldiv* *sigil_fpu*" \
             "*sigil_bext* *sigil_vregfile* *sigil_vec* *sigil_rvc* *sigil_decoder* sigil_csr sigil_mmu"
        echo "proc; flatten; memory -nomap; memory_map; opt_clean"
        echo "rename sigil_core $side; design -stash $side"
      done
      echo "design -load gold; design -copy-from gate -as gate gate"
      echo "opt -purge gold gate; async2sync gold gate"
      echo "equiv_make gold gate equiv; hierarchy -top equiv"
      echo "equiv_struct; equiv_simple$IGN; equiv_induct$IGN; equiv_status -assert"
    } > "$d/eq_$cfg.ys"
    t0=$(date +%s)
    if "$YOSYS" -q -l "$d/eq_$cfg.log" "$d/eq_$cfg.ys" > /dev/null 2>&1; then r=EQUIVALENT; else r=FAILED; rc=1; fi
    echo "sigil_core ($cfg) vs $REF ($(git rev-parse --short "$REF")), FPGA_TIMING=0: $r," \
         "$(grep -c 'Presumably equivalent cells' "$d/eq_$cfg.log") paired submodules," \
         "$(grep -oE '[0-9]+ are proven and [0-9]+ are unproven' "$d/eq_$cfg.log" | tail -1)," \
         "$(( $(date +%s) - t0 )) s"
  done
}
for mod in "${mods[@]}"; do
  if [ "$mod" = sigil_core ]; then core_eq; continue; fi
  d=build/fpga_timing_equiv/$mod
  rm -rf "$d"; mkdir -p "$d"
  git show "$REF:rtl/core/$mod.sv" > "$d/gold.sv"
  cp "rtl/core/$mod.sv" "$d/gate.sv"
  # Modules that import sigil_cache_pkg (the caches) read it from the
  # same side, with SIGIL_FPGA_TIMING undefined; their (unchanged)
  # sigil_sram_sp arrays are black boxes, so the proof covers every
  # array port.
  gold_pkg=(); gate_pkg=(); lib=""
  if grep -q "sigil_cache_pkg" "$d/gate.sv"; then
    git show "$REF:rtl/core/sigil_cache_pkg.sv" > "$d/gold_pkg.sv"
    cp rtl/core/sigil_cache_pkg.sv "$d/gate_pkg.sv"
    gold_pkg=("$d/gold_pkg.sv"); gate_pkg=("$d/gate_pkg.sv")
  fi
  if grep -q "sigil_sram_sp" "$d/gate.sv"; then
    "$SV2V" -DSYNTHESIS rtl/core/sigil_cache_pkg.sv rtl/core/sigil_sram_sp.sv > "$d/sram.v"
    lib="$d/sram.v"
  fi
  "$SV2V" -DSYNTHESIS ${gold_pkg[@]+"${gold_pkg[@]}"} "$d/gold.sv" > "$d/gold.v"
  "$SV2V" -DSYNTHESIS ${gate_pkg[@]+"${gate_pkg[@]}"} "$d/gate.sv" > "$d/gate.v"
  # Yosys rejects the unpacked arrays sv2v lists in sensitivity lists.
  perl -pi -e 's/always \@\((?!posedge|negedge)[^)]*\)/always \@*/' "$d/gold.v" "$d/gate.v"
  {
    [ -z "$lib" ] || echo "read_verilog -lib $lib"
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
