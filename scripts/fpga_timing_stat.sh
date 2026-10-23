#!/usr/bin/env bash
# #53 ASIC invariance, cell counts (docs/FPGA_TIMING_53.md): one Yosys
# flow on REF (default origin/main) and on this tree, SIGIL_FPGA_TIMING
# undefined, for the ASIC configurations:
#   core-default, core-oreg     sigil_core (default, SIGIL_SRAM_OREG)
#   soc-default, soc-oreg       sigil_soc_top (default, SIGIL_SRAM_OREG)
#   soc-fakeram45, soc-sky130   sigil_soc_top as the nangate45 and sky130
#                               flows build it, SRAM macro models as
#                               black boxes
# Per side: sv2v -DSYNTHESIS of the rtl/sigil_soc_files.mk list; Yosys
# read_verilog, hierarchy, proc, flatten, opt_clean -purge, memory_collect;
# scripts/netlist_canon.py; then synth -flatten (generic cells; -run :fine
# for "coarse") and stat -width on the canonical netlist. Yosys 0.33 counts
# from the source text depend on identifier order (the same RTL read after
# an unrelated module counts differently), so the comparison is made on
# the canonical netlists: identical files are the same elaborated logic
# up to names, and their stat must then match too.
#   SV2V=/path/to/sv2v scripts/fpga_timing_stat.sh [-v full|coarse|none] [config ...]
# Output: build/fpga_timing_stat/ (OUT=dir to run several at once); exit 1
# on any difference. On one,
#   python3 scripts/netlist_canon.py <ref|head>-<cfg>.raw.json x.json --rounds 2 <side>.rounds
#   python3 scripts/netlist_canon.py diff ref.rounds head.rounds
# names the source of the first differing cells.
set -euo pipefail
cd "$(dirname "$0")/.."
SV2V=${SV2V:-sv2v}
REF=${REF:-origin/main}
var=full
if [ "${1:-}" = -v ]; then var=$2; shift 2; fi
cfgs=("$@")
[ ${#cfgs[@]} -gt 0 ] || cfgs=(core-default core-oreg soc-default soc-oreg soc-fakeram45 soc-sky130)
O=${OUT:-build/fpga_timing_stat}
rm -rf "$O/ref"; mkdir -p "$O/ref"
git archive "$REF" rtl flow/designs | tar x -C "$O/ref"
rc=0

side_run() { # side(ref|head) root cfg top
  local root=$2 cfg=$3 top=$4 o=$O/$1-$3 srcs libs="" l s
  srcs=$(sed -n '/^SIGIL_SOC_RTL/,/^$/p' "$root/rtl/sigil_soc_files.mk" |
         grep -oE '[a-z_0-9]+/[a-z_0-9]+\.sv' | sed "s|^|$root/rtl/|")
  # shellcheck disable=SC2086
  "$SV2V" -DSYNTHESIS "${defs[@]}" -I"$root/rtl/core" $srcs > "$o.v"
  # Yosys rejects the unpacked arrays sv2v lists in sensitivity lists.
  perl -pi -e 's/always \@\((?!posedge|negedge)[^)]*\)/always \@*/' "$o.v"
  for l in "${macros[@]}"; do libs="$libs $root/flow/designs/$l"; done
  yosys -q -l "$o.elab.log" -p "${libs:+read_verilog -sv -lib$libs; }read_verilog $o.v; hierarchy -check -top $top $chparam; proc; flatten; opt_clean -purge; memory_collect; write_json $o.raw.json" \
    > /dev/null 2>&1 || { echo "yosys failed, see $o.elab.log" >&2; return 1; }
  python3 scripts/netlist_canon.py "$o.raw.json" "$o.canon.json" --labels "$o.labels.tsv" 2> "$o.canon.log"
  [ "$var" != none ] || return 0
  s="synth -flatten -top $top"; [ "$var" = coarse ] && s="$s -run :fine"
  yosys -q -l "$o.$var.log" -p "read_json $o.canon.json; hierarchy -check -top $top; $s; tee -q -o $o.$var.stat stat -width" \
    > /dev/null 2>&1 || { echo "yosys failed, see $o.$var.log" >&2; return 1; }
}

for cfg in "${cfgs[@]}"; do
  top=sigil_soc_top; defs=(); macros=(); chparam=""
  case $cfg in core-*) top=sigil_core ;; esac
  case $cfg in
    *-default) ;;
    *-oreg) defs=(-DSIGIL_SRAM_OREG) ;;
    soc-fakeram45)
      defs=(-DSIGIL_SRAM_FAKERAM45)
      macros=(nangate45/sigil_soc/sram/fakeram45_256x64_1r1w.v nangate45/sigil_soc/sram/fakeram45_512x64.v
              nangate45/sigil_soc/sram/fakeram45_64x44.v) ;;
    soc-sky130)
      defs=(-DSIGIL_SRAM_SKY130)
      macros=(sky130hd/sigil_soc/sram/sky130_sram_1rw1r_64x256_8.v sky130hd/sigil_soc/sram/sky130_sram_1rw1r_128x256_8.v
              sky130hd/sigil_soc/sram/sky130_sram_1rw1r_44x64_8.v)
      chparam=$(sed -n 's/^SIGIL_SOC_PARAMS_SKY130 = //p' rtl/sigil_soc_files.mk |
                sed -E 's/([A-Z_]+)=([^ ]+)/-chparam \1 \2/g') ;;
    *) echo "unknown config $cfg" >&2; exit 2 ;;
  esac
  t0=$(date +%s)
  side_run ref "$O/ref" "$cfg" "$top" & p=$!
  side_run head . "$cfg" "$top"
  wait $p
  a=$(sha256sum < "$O/ref-$cfg.canon.json" | cut -c1-16)
  b=$(sha256sum < "$O/head-$cfg.canon.json" | cut -c1-16)
  if [ "$a" = "$b" ]; then r="netlists IDENTICAL ($a)"; else r="netlists DIFFER (ref $a, head $b)"; rc=1; fi
  if [ "$var" != none ]; then
    na=$(grep -m1 'Number of cells' "$O/ref-$cfg.$var.stat" | awk '{print $NF}')
    nb=$(grep -m1 'Number of cells' "$O/head-$cfg.$var.stat" | awk '{print $NF}')
    if diff <(sed '1,/Printing/d' "$O/ref-$cfg.$var.stat") <(sed '1,/Printing/d' "$O/head-$cfg.$var.stat") > "$O/$cfg.$var.diff"; then
      r="$r, $var stat IDENTICAL ($na cells)"
    else r="$r, $var stat DIFFERS (ref $na, head $nb cells; $O/$cfg.$var.diff)"; rc=1; fi
  fi
  echo "$cfg ($top) vs $REF ($(git rev-parse --short "$REF")), FPGA_TIMING=0: $r, $(( $(date +%s) - t0 )) s"
done
exit $rc
