#!/usr/bin/env bash
# #13 invariance (docs/SOC_AREA.md, MPW section): with SIGIL_NO_VECTOR
# undefined (sigil_pkg::HAS_VECTOR = 1) every configuration elaborates
# to the same logic as REF (default origin/main). Adapted from the #53
# ASIC-invariance proof (scripts/fpga_timing_equiv.sh on
# 53-mem-stage-pipeline).
#   static   - the RTL this branch changes is sigil_pkg (one localparam
#              added, nothing removed), sigil_decoder, sigil_csr and
#              sigil_core; every other RTL source is byte-identical to
#              REF; HAS_VECTOR is read only by those three modules.
#   sigil_decoder, sigil_csr - module proofs (Yosys equiv_make,
#              equiv_struct, equiv_simple, equiv_induct) against REF:
#              the decoder with REF's / this branch's sigil_pkg, the CSR
#              file with its default HAS_VECTOR = 1 (what sigil_core
#              passes from sigil_pkg in these configurations).
#   sigil_core - the core's own logic in each configuration of
#              CORE_CFGS, its submodule instances black boxes that
#              equiv_make pairs (inputs proven equal, outputs merged):
#              sigil_decoder and sigil_csr, proven above, and the
#              unchanged leaves (sigil_vregfile, sigil_vec, sigil_mmu,
#              ...; also when a parameter override derives them, as
#              FPGA_TIMING does on #53). Two renames, no logic: the VRF and vector-unit
#              instances sit in the g_vec generate block
#              (g_vec.u_vregfile / g_vec.u_vec) and sigil_csr's
#              HAS_VECTOR override (= its default, 1) is dropped.
#   flow     - the sky130hd and nangate45 sigil_soc ORFS configs (with
#              rtl/sigil_soc_files.mk) give the same SYNTH_SLANG_ARGS,
#              VERILOG_FILES and macro LEF/LIB/GDS lists as REF's
#              (whitespace-normalized); the SIGIL_NO_VECTOR=1 values
#              are printed for the record.
# EXTRA_DEFS (e.g. SIGIL_FPGA_TIMING) is added to every sv2v run;
# MOD_CHPARAM ("NAME=VALUE ...", e.g. FPGA_TIMING=1) sets parameters of
# the module proofs on both sides (as the core would pass them).
# SystemVerilog is converted with sv2v (SV2V=/path/to/sv2v).
#   scripts/novec_equiv.sh [static|sigil_decoder|sigil_csr|sigil_core|flow ...]
#   (default: all five). Logs: build/novec_equiv/<step>/.
set -euo pipefail
cd "$(dirname "$0")/.."
SV2V=${SV2V:-sv2v}
REF=${REF:-origin/main}
MOD_CHPARAM=${MOD_CHPARAM:-}
CORE_CFGS=${CORE_CFGS:-"default SIGIL_SRAM_OREG SIGIL_SRAM_SKY130 SIGIL_SRAM_FAKERAM45 SIGIL_VRF_OREG SIGIL_MULDIV_COMB"}
EXTRA_DEFS=${EXTRA_DEFS:-}
OUT=build/novec_equiv
steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(static sigil_decoder sigil_csr sigil_core flow)
refsha=$(git rev-parse --short "$REF")
xdefs=(); for d in $EXTRA_DEFS; do xdefs+=("-D$d"); done
rc=0

static_chk() {
  local changed bad pkgdel users
  changed=$(git diff --name-only "$REF" -- rtl | sort)
  bad=$(grep -vE '^rtl/(core/sigil_(pkg|decoder|csr|core)\.sv|sigil_soc_files\.mk)$' <<< "$changed" || true)
  if [ -n "$bad" ]; then echo "static: RTL sources differ from $REF beyond the proven set:" $bad; rc=1; return; fi
  pkgdel=$(git diff -U0 "$REF" -- rtl/core/sigil_pkg.sv | grep -E '^-[^-]' || true)
  if [ -n "$pkgdel" ]; then echo "static: sigil_pkg.sv removes/changes lines:"; echo "$pkgdel"; rc=1; return; fi
  if ! diff <(git show "$REF:rtl/sigil_soc_files.mk" | sed -n '/^SIGIL_SOC_RTL/,/^$/p') \
            <(sed -n '/^SIGIL_SOC_RTL/,/^$/p' rtl/sigil_soc_files.mk) > /dev/null; then
    echo "static: SIGIL_SOC_RTL differs from $REF"; rc=1; return
  fi
  users=$(grep -rlw --include="*.sv" HAS_VECTOR rtl | sort | tr '\n' ' ')
  if [ "$users" != "rtl/core/sigil_core.sv rtl/core/sigil_csr.sv rtl/core/sigil_decoder.sv rtl/core/sigil_pkg.sv " ]; then
    echo "static: HAS_VECTOR read outside the proven modules: $users"; rc=1; return
  fi
  echo "static vs $REF ($refsha): changed RTL = $(tr '\n' ' ' <<< "$changed"); sigil_pkg only adds lines;" \
       "SIGIL_SOC_RTL unchanged; HAS_VECTOR used in: $users-> OK"
}

# Module proof: gold = REF sources, gate = this tree (pkg first if any).
mod_eq() { # module, pkg?
  local mod=$1 pkg=${2:-} d=$OUT/$1 t0 r gpk=() npk=()
  rm -rf "$d"; mkdir -p "$d"
  git show "$REF:rtl/core/$mod.sv" > "$d/gold.sv"
  cp "rtl/core/$mod.sv" "$d/gate.sv"
  if [ -n "$pkg" ]; then
    git show "$REF:rtl/core/$pkg.sv" > "$d/gold_pkg.sv"; cp "rtl/core/$pkg.sv" "$d/gate_pkg.sv"
    gpk=("$d/gold_pkg.sv"); npk=("$d/gate_pkg.sv")
  fi
  "$SV2V" -DSYNTHESIS ${xdefs[@]+"${xdefs[@]}"} ${gpk[@]+"${gpk[@]}"} "$d/gold.sv" > "$d/gold.v"
  "$SV2V" -DSYNTHESIS ${xdefs[@]+"${xdefs[@]}"} ${npk[@]+"${npk[@]}"} "$d/gate.sv" > "$d/gate.v"
  perl -pi -e 's/always \@\((?!posedge|negedge)[^)]*\)/always \@*/' "$d/gold.v" "$d/gate.v"
  {
    echo "read_verilog -mem2reg $d/gold.v"
    echo "rename $mod gold"
    echo "read_verilog -mem2reg $d/gate.v"
    echo "rename $mod gate"
    for kv in $MOD_CHPARAM; do
      if grep -qE "parameter[^;]*\b${kv%%=*}\b" "$d/gold.v"; then
        echo "chparam -set ${kv%%=*} ${kv#*=} gold gate"
      fi
    done
    echo "hierarchy -check; proc; memory; opt -purge; async2sync"
    echo "equiv_make gold gate equiv; hierarchy -top equiv"
    echo "equiv_struct; equiv_simple; equiv_induct; equiv_status -assert"
  } > "$d/eq.ys"
  t0=$(date +%s)
  if yosys -q -l "$d/eq.log" "$d/eq.ys" > /dev/null 2>&1; then r=EQUIVALENT; else r=FAILED; rc=1; fi
  echo "$mod vs $REF ($refsha)${EXTRA_DEFS:+ [$EXTRA_DEFS]}${MOD_CHPARAM:+ [$MOD_CHPARAM]}, HAS_VECTOR=1: $r," \
       "$(grep -oE '[0-9]+ are proven and [0-9]+ are unproven' "$d/eq.log" | tail -1)," \
       "$(( $(date +%s) - t0 )) s"
}

core_eq() {
  local d=$OUT/sigil_core changed srcs cfg r t0
  rm -rf "$d"; mkdir -p "$d/gold"
  changed=$(git diff --name-only "$REF" -- rtl/core |
            grep -vE '/sigil_(pkg|core|csr|decoder)\.sv$' || true)
  if [ -n "$changed" ]; then
    echo "sigil_core: black-boxed sources differ from $REF:" $changed; rc=1; return
  fi
  git archive "$REF" rtl/core | tar x -C "$d/gold"
  srcs=$(sed -n '/^SIGIL_SOC_RTL/,/^$/p' rtl/sigil_soc_files.mk | grep -oE 'core/[a-z_0-9]+\.sv' |
         grep -vE 'sram_sp|icache|dcache|bus_arb|sigil_cpu')
  for cfg in $CORE_CFGS; do
    local def=(); [ "$cfg" = default ] || def=("-D$cfg")
    # shellcheck disable=SC2046
    "$SV2V" -DSYNTHESIS ${def[@]+"${def[@]}"} ${xdefs[@]+"${xdefs[@]}"} -I"$d/gold/rtl/core" \
      $(sed "s|^|$d/gold/rtl/|" <<< "$srcs") > "$d/gold_$cfg.v"
    # shellcheck disable=SC2046
    "$SV2V" -DSYNTHESIS ${def[@]+"${def[@]}"} ${xdefs[@]+"${xdefs[@]}"} -Irtl/core \
      $(sed 's|^|rtl/|' <<< "$srcs") > "$d/gate_$cfg.v"
    perl -pi -e 's/always \@\((?!posedge|negedge)[^)]*\)/always \@*/' "$d/gold_$cfg.v" "$d/gate_$cfg.v"
    # sigil_csr's HAS_VECTOR override is its default value (1) here.
    perl -0pi -e 's/sigil_csr\s*#\(\s*\.HAS_VECTOR\([^()]*\)\s*\)\s*u_csr/sigil_csr u_csr/;
                  s/(sigil_csr\s*#\([^;]*?),\s*\.HAS_VECTOR\([^()]*\)(\s*\)\s*u_csr)/$1$2/' "$d/gate_$cfg.v"
    if grep -q 'HAS_VECTOR' "$d/gate_$cfg.v" && ! grep -qE 'HAS_VECTOR *= *1' "$d/gate_$cfg.v"; then
      echo "sigil_core ($cfg): HAS_VECTOR is not 1 in the gate"; rc=1; continue
    fi
    # SRAM-macro configurations: the macro models (unchanged files,
    # read as black boxes) satisfy the VRF banks' references.
    local lib=""
    case $cfg in
      SIGIL_SRAM_SKY130) lib="flow/designs/sky130hd/sigil_soc/sram/sky130_sram_1rw1r_*.v" ;;
      SIGIL_SRAM_FAKERAM45) lib="flow/designs/nangate45/sigil_soc/sram/fakeram45_*.v" ;;
    esac
    {
      for side in gold gate; do
        for f in $lib; do echo "read_verilog -sv -lib $f"; done
        echo "read_verilog -mem2reg $d/${side}_$cfg.v"
        echo "hierarchy -check -top sigil_core"
        echo "blackbox *sigil_regfile* *sigil_fpregfile* *sigil_alu* *sigil_muldiv* *sigil_fpu*" \
             "*sigil_bext* *sigil_vregfile* *sigil_vec* *sigil_rvc* *sigil_decoder* *sigil_csr* *sigil_mmu*"
        if grep -q 'begin : g_vec' "$d/${side}_$cfg.v"; then
          echo "cd sigil_core"
          echo "rename g_vec.u_vregfile u_vregfile"
          echo "rename g_vec.u_vec u_vec"
          echo "cd .."
        fi
        echo "proc; flatten; memory -nomap; memory_map; opt_clean"
        echo "rename sigil_core $side; design -stash $side"
      done
      echo "design -load gold; design -copy-from gate -as gate gate"
      echo "opt -purge gold gate; async2sync gold gate"
      echo "equiv_make gold gate equiv; hierarchy -top equiv"
      echo "equiv_struct; equiv_simple; equiv_induct; equiv_status -assert"
    } > "$d/eq_$cfg.ys"
    t0=$(date +%s)
    if yosys -q -l "$d/eq_$cfg.log" "$d/eq_$cfg.ys" > /dev/null 2>&1; then r=EQUIVALENT; else r=FAILED; rc=1; fi
    echo "sigil_core ($cfg${EXTRA_DEFS:+ + $EXTRA_DEFS}) vs $REF ($refsha), HAS_VECTOR=1: $r," \
         "$(grep -c 'Presumably equivalent cells' "$d/eq_$cfg.log" || true) paired submodules," \
         "$(grep -oE '[0-9]+ are proven and [0-9]+ are unproven' "$d/eq_$cfg.log" | tail -1)," \
         "$(( $(date +%s) - t0 )) s"
  done
}

# ORFS design configs: evaluate each with dummy ORFS paths and compare
# the variables that select RTL, defines and macros.
flow_chk() {
  local d=$OUT/flow plat side vars v
  rm -rf "$d"; mkdir -p "$d"
  vars="SYNTH_SLANG_ARGS VERILOG_FILES VERILOG_INCLUDE_DIRS ADDITIONAL_LEFS ADDITIONAL_LIBS ADDITIONAL_GDS"
  cat > "$d/print.mk" <<'EOF'
FLOW_HOME = /F
DESIGN_HOME = /D
PLATFORM_DIR = /P
include $(CONFIG)
$(foreach v,$(VARS),$(info $(v) = $(strip $($(v)))))
all: ;
EOF
  for side in gold gate; do
    mkdir -p "$d/$side/designs/src/sigil_soc"
    for plat in sky130hd nangate45; do mkdir -p "$d/$side/designs/$plat/sigil_soc"; done
  done
  git show "$REF:rtl/sigil_soc_files.mk" > "$d/gold/designs/src/sigil_soc/sigil_soc_files.mk"
  cp rtl/sigil_soc_files.mk "$d/gate/designs/src/sigil_soc/"
  for plat in sky130hd nangate45; do
    git show "$REF:flow/designs/$plat/sigil_soc/config.mk" > "$d/gold/designs/$plat/sigil_soc/config.mk"
    cp "flow/designs/$plat/sigil_soc/config.mk" "$d/gate/designs/$plat/sigil_soc/"
    for side in gold gate; do
      make -s -f "$d/print.mk" CONFIG="$d/$side/designs/$plat/sigil_soc/config.mk" VARS="$vars" \
        | sed "s|$d/$side/designs/$plat/sigil_soc/../../src|<src>|g" > "$d/${plat}_$side.txt"
    done
    make -s -f "$d/print.mk" CONFIG="$d/gate/designs/$plat/sigil_soc/config.mk" VARS="$vars" SIGIL_NO_VECTOR=1 \
      | sed "s|$d/gate/designs/$plat/sigil_soc/../../src|<src>|g" > "$d/${plat}_novec.txt"
    if diff "$d/${plat}_gold.txt" "$d/${plat}_gate.txt" > "$d/${plat}.diff"; then
      echo "flow $plat/sigil_soc vs $REF ($refsha): $vars identical"
    else
      echo "flow $plat/sigil_soc vs $REF ($refsha): DIFFERS (see $d/${plat}.diff)"; rc=1
    fi
    echo "  SIGIL_NO_VECTOR=1: $(grep -E '^SYNTH_SLANG_ARGS' "$d/${plat}_novec.txt")"
    echo "  SIGIL_NO_VECTOR=1: $(grep -E '^ADDITIONAL_LIBS' "$d/${plat}_novec.txt" | sed 's|/[^ ]*/||g')"
  done
}

for s in "${steps[@]}"; do
  case $s in
    static) static_chk ;;
    sigil_decoder) mod_eq sigil_decoder sigil_pkg ;;
    sigil_csr) mod_eq sigil_csr ;;
    sigil_core) core_eq ;;
    flow) flow_chk ;;
    *) echo "unknown step $s"; exit 2 ;;
  esac
done
exit $rc
