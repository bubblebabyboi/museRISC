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
#              rtl/sigil_soc_files.mk) define, with SIGIL_NO_VECTOR
#              unset, every variable REF's define with the same value
#              (all of them, not only the RTL / define / macro lists;
#              paths normalized); new helper variables are listed. The
#              SIGIL_NO_VECTOR=1 slang arguments and macro libs are
#              printed for the record.
#   synth    - (docker + the pinned ORFS image, IMG) elaborates
#              sigil_soc_top as the sky130hd and nangate45 ORFS flows
#              read it (read_slang with each config's VERILOG_FILES,
#              SYNTH_SLANG_ARGS and include dirs, the macro models
#              black-boxed), sigil_soc_top from SIGIL_SOC_RTL and
#              sigil_fpga_top, each with SIGIL_NO_VECTOR unset and set:
#              with it, no sigil_vec / sigil_vregfile module and 3 SRAM
#              macro instances fewer (the VRF banks; 7 -> 4 on sky130),
#              no VRF macro type, and no more Yosys `check` problems
#              than without it.
#   sw       - (not in the default list; RISC-V GCC) every
#              sw/core-tests program on REF builds to the same binary
#              on this tree (default configuration).
# EXTRA_DEFS (e.g. SIGIL_FPGA_TIMING) is added to every sv2v run;
# MOD_CHPARAM ("NAME=VALUE ...", e.g. FPGA_TIMING=1) sets parameters of
# the module proofs on both sides (as the core would pass them).
# SystemVerilog is converted with sv2v (SV2V=/path/to/sv2v).
# Merging this change with another branch: scripts/novec_merge_check.sh
# runs these steps on the merge commit against its other parent.
#   scripts/novec_equiv.sh [static|sigil_decoder|sigil_csr|sigil_core|flow|synth|sw ...]
#   (default: all but sw). Logs: build/novec_equiv/<step>/.
set -euo pipefail
cd "$(dirname "$0")/.."
SV2V=${SV2V:-sv2v}
REF=${REF:-origin/main}
MOD_CHPARAM=${MOD_CHPARAM:-}
CORE_CFGS=${CORE_CFGS:-"default SIGIL_SRAM_OREG SIGIL_SRAM_SKY130 SIGIL_SRAM_FAKERAM45 SIGIL_VRF_OREG SIGIL_MULDIV_COMB"}
EXTRA_DEFS=${EXTRA_DEFS:-}
OUT=build/novec_equiv
steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(static sigil_decoder sigil_csr sigil_core flow synth)
IMG=${IMG:-openroad/orfs@sha256:63981d1ac8990a9bee8bf874c95ee2c1ee3fe7b99f57d459282ab8c31a8ed663}
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
# every variable the config (with the files it includes) defines.
flow_chk() {
  local d=$OUT/flow plat side v new gone common ndiff
  rm -rf "$d"; mkdir -p "$d"
  cat > "$d/print.mk" <<'EOF'
FLOW_HOME = /F
DESIGN_HOME = /D
PLATFORM_DIR = /P
PRE := $(subst %,,$(.VARIABLES))
include $(CONFIG)
$(foreach v,$(sort $(filter-out $(PRE) PRE,$(.VARIABLES))),$(info $(v) = $(strip $($(v)))))
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
      make -s -f "$d/print.mk" CONFIG="$d/$side/designs/$plat/sigil_soc/config.mk" \
        | sed "s|$d/$side/|<root>/|g" > "$d/${plat}_$side.txt"
    done
    make -s -f "$d/print.mk" CONFIG="$d/gate/designs/$plat/sigil_soc/config.mk" SIGIL_NO_VECTOR=1 \
      | sed "s|$d/gate/|<root>/|g" > "$d/${plat}_novec.txt"
    new=$(comm -13 <(cut -d' ' -f1 "$d/${plat}_gold.txt" | sort) <(cut -d' ' -f1 "$d/${plat}_gate.txt" | sort) | tr '\n' ' ')
    gone=$(comm -23 <(cut -d' ' -f1 "$d/${plat}_gold.txt" | sort) <(cut -d' ' -f1 "$d/${plat}_gate.txt" | sort) | tr '\n' ' ')
    common=$(comm -12 <(cut -d' ' -f1 "$d/${plat}_gold.txt" | sort) <(cut -d' ' -f1 "$d/${plat}_gate.txt" | sort))
    ndiff=0
    for v in $common; do
      if [ "$(grep -E "^$v = " "$d/${plat}_gold.txt")" != "$(grep -E "^$v = " "$d/${plat}_gate.txt")" ]; then
        echo "  flow $plat: $v differs"; ndiff=$((ndiff + 1))
      fi
    done
    if [ $ndiff -eq 0 ] && [ -z "$gone" ]; then
      echo "flow $plat/sigil_soc vs $REF ($refsha): $(wc -w <<< "$common") variables, all identical; new: ${new:-none}"
    else
      echo "flow $plat/sigil_soc vs $REF ($refsha): DIFFERS ($ndiff variables differ; removed: ${gone:-none})"; rc=1
    fi
    echo "  SIGIL_NO_VECTOR=1: $(grep -E '^SYNTH_SLANG_ARGS' "$d/${plat}_novec.txt")"
    echo "  SIGIL_NO_VECTOR=1: $(grep -E '^ADDITIONAL_LIBS' "$d/${plat}_novec.txt" | sed 's|/[^ ]*/||g')"
  done
}

# Elaboration as synthesis reads it (ORFS Yosys + read_slang, in the
# pinned image), with SIGIL_NO_VECTOR unset and set.
synth_chk() {
  local d=$OUT/synth plat cfg nv v f bb files args incs pids=() names=()
  if ! command -v docker > /dev/null || ! docker image inspect "$IMG" > /dev/null 2>&1; then
    echo "synth: needs docker and $IMG"; rc=1; return
  fi
  rm -rf "$d"; mkdir -p "$d/designs/src"
  ln -s "$PWD/rtl" "$d/designs/src/sigil_soc"
  cat > "$d/print.mk" <<'EOF'
FLOW_HOME = /F
DESIGN_HOME = /D
PLATFORM_DIR = /P
include $(CONFIG)
$(foreach v,$(VARS),$(info $(strip $($(v)))))
all: ;
EOF
  local soc; soc=$(sed -n '/^SIGIL_SOC_RTL/,/^$/p' rtl/sigil_soc_files.mk | grep -oE '[a-z]+/[a-z_0-9]+\.sv' | sed 's|^|/D/src/sigil_soc/|' | tr '\n' ' ')
  local fpga; fpga=$(make -s -f - pv <<< $'include Makefile\npv: ; @echo $(FPGA_RTL)' | sed 's|rtl/|/D/src/sigil_soc/|g')
  local xd=""; for v in $EXTRA_DEFS; do xd+=" -D$v"; done
  for cfg in sky130hd nangate45 soc fpga; do
    for nv in 0 1; do
      f=$d/${cfg}_nv$nv; bb=""; incs="-I/D/src/sigil_soc/core"
      case $cfg in
        sky130hd|nangate45)
          mkdir -p "$d/designs/$cfg"; [ -e "$d/designs/$cfg/sigil_soc" ] || ln -s "$PWD/flow/designs/$cfg/sigil_soc" "$d/designs/$cfg/sigil_soc"
          { read -r files; read -r args; read -r v; } < <(make -s -f "$d/print.mk" CONFIG="$d/designs/$cfg/sigil_soc/config.mk" \
              VARS="VERILOG_FILES SYNTH_SLANG_ARGS VERILOG_INCLUDE_DIRS" $( [ $nv = 1 ] && echo SIGIL_NO_VECTOR=1 ))
          incs=$(for i in $v; do printf ' -I%s' "$i"; done)
          for m in $files; do case $m in */sram/*.v) bb+=" --blackboxed-module $(basename "$m" .v)" ;; esac; done
          top=sigil_soc_top ;;
        soc)  files=$soc; args="-DSYNTHESIS$( [ $nv = 1 ] && echo ' -DSIGIL_NO_VECTOR')"; top=sigil_soc_top ;;
        fpga) files="$soc $fpga"; args="-DSYNTHESIS$( [ $nv = 1 ] && echo ' -DSIGIL_NO_VECTOR')"; top=sigil_fpga_top ;;
      esac
      cat > "$f.ys" <<YS
read_slang -D SYNTHESIS --keep-hierarchy --compat=vcs --ignore-assertions --top $top $incs $files $bb $args$xd
hierarchy -check -top $top
tee -q -o /w/$f.mods.txt ls
proc
tee -q -o /w/$f.check.txt check
flatten
tee -q -o /w/$f.macros.txt select -list t:sky130_sram* t:fakeram45*
YS
      docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/w" -v "$PWD/rtl:/D/src/sigil_soc:ro" \
        -v "$PWD/flow/designs/sky130hd:/D/sky130hd:ro" -v "$PWD/flow/designs/nangate45:/D/nangate45:ro" \
        -w /w "$IMG" /OpenROAD-flow-scripts/tools/install/yosys/bin/yosys -q -l "/w/$f.log" -s "/w/$f.ys" \
        > /dev/null 2>&1 &
      pids+=($!); names+=("$f")
    done
  done
  local i st=() ok
  for i in "${!pids[@]}"; do if wait "${pids[$i]}"; then st[$i]=0; else st[$i]=1; fi; done
  i=0
  for cfg in sky130hd nangate45 soc fpga; do
    local nvec=() nmac=() nchk=() bad=0 vrf
    for nv in 0 1; do
      f=$d/${cfg}_nv$nv
      [ "${st[$i]}" = 0 ] || { echo "synth $cfg SIGIL_NO_VECTOR=$nv: Yosys failed (see $f.log)"; bad=1; }
      nvec[$nv]=$(grep -cE '^ *sigil_(vec|vregfile|vrf_bank)([$]|$)' "$f.mods.txt" 2>/dev/null || true)
      nmac[$nv]=$(grep -c / "$f.macros.txt" 2>/dev/null || true)
      nchk[$nv]=$(grep -oE 'Found and reported [0-9]+ problems' "$f.check.txt" 2>/dev/null | grep -oE '[0-9]+' || echo 0)
      i=$((i + 1))
    done
    vrf=$(grep -cE 'sky130_sram_1rw1r_64x256_8|fakeram45_256x64_1r1w' "$d/${cfg}_nv1.macros.txt" "$d/${cfg}_nv1.log" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
    ok=1
    [ $bad = 0 ] || ok=0
    [ "${nvec[0]:-0}" -gt 0 ] && [ "${nvec[1]:-1}" -eq 0 ] || ok=0
    case $cfg in
      sky130hd|nangate45) [ "${nmac[1]:-0}" -eq $(( ${nmac[0]:-0} - 3 )) ] && [ "$vrf" -eq 0 ] || ok=0 ;;
      *) [ "${nmac[0]:-1}" -eq 0 ] && [ "${nmac[1]:-1}" -eq 0 ] || ok=0 ;;
    esac
    [ "${nchk[1]:-1}" -le "${nchk[0]:-0}" ] || ok=0
    echo "synth $cfg${EXTRA_DEFS:+ + $EXTRA_DEFS}: vector modules ${nvec[0]} -> ${nvec[1]}," \
         "SRAM macro instances ${nmac[0]} -> ${nmac[1]}, VRF macro refs with SIGIL_NO_VECTOR $vrf," \
         "check problems ${nchk[0]} -> ${nchk[1]}: $( [ $ok = 1 ] && echo OK || echo FAILED)"
    [ $ok = 1 ] || rc=1
  done
}

# sw/core-tests binaries of the default configuration vs REF's.
sw_chk() {
  local d=$OUT/sw g=${RISCV_PREFIX:-riscv64-unknown-elf-} n=0 same=0 s b fl
  fl=$(make -s -C sim -f - pv <<< $'include Makefile\npv: ; @echo $(SWFLAGS)' 2> /dev/null | sed 's/ -T [^ ]*//') || true
  [ -n "$fl" ] || fl="-march=rv64imafdc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh_zicsr_zifencei -mabi=lp64 -nostdlib"
  rm -rf "$d"; mkdir -p "$d/ref" "$d/a" "$d/b"
  git archive "$REF" sw/core-tests | tar x -C "$d/ref"
  for s in "$d"/ref/sw/core-tests/*.S; do
    b=$(basename "$s" .S); n=$((n + 1))
    # shellcheck disable=SC2086
    ${g}gcc $fl -T "$d/ref/sw/core-tests/link.ld" -I"$d/ref/sw/core-tests" "$s" -o "$d/a/$b.elf" 2> /dev/null &&
      ${g}objcopy -O binary "$d/a/$b.elf" "$d/a/$b.bin"
    # shellcheck disable=SC2086
    ${g}gcc $fl -T sw/core-tests/link.ld -Isw/core-tests "sw/core-tests/$b.S" -o "$d/b/$b.elf" 2> /dev/null &&
      ${g}objcopy -O binary "$d/b/$b.elf" "$d/b/$b.bin"
    if [ -s "$d/a/$b.bin" ] && cmp -s "$d/a/$b.bin" "$d/b/$b.bin"; then same=$((same + 1)); else echo "  sw: $b differs"; fi
  done
  echo "sw/core-tests (default configuration) vs $REF ($refsha): $same / $n identical binaries"
  [ "$same" -eq "$n" ] || rc=1
}

for s in "${steps[@]}"; do
  case $s in
    static) static_chk ;;
    sigil_decoder) mod_eq sigil_decoder sigil_pkg ;;
    sigil_csr) mod_eq sigil_csr ;;
    sigil_core) core_eq ;;
    flow) flow_chk ;;
    synth) synth_chk ;;
    sw) sw_chk ;;
    *) echo "unknown step $s"; exit 2 ;;
  esac
done
exit $rc
