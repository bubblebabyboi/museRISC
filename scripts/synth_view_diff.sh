#!/usr/bin/env bash
# Synthesis-view equivalence of two revisions (issue #56): preprocesses
# every RTL file (rtl/core, crypto, soc, fpga) of each revision with
# each synthesis flow's defines and compares the outputs byte for byte.
# Identical preprocessed RTL means identical netlists: a change that is
# confined to `ifndef SYNTHESIS blocks (simulation-only checks, the
# performance counters) cannot reach any flow. The simulation view
# (no defines) is printed for contrast and is expected to differ.
#
#   scripts/synth_view_diff.sh <rev-A> <rev-B>     e.g. origin/main HEAD
#
# Exit status: 0 every synthesis view identical, 1 a synthesis view
# differs, 2 usage/preprocessing error. Needs git and verilator.
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 <rev-A> <rev-B>" >&2; exit 2; }
root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/synview.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
hash() { if command -v sha256sum >/dev/null; then sha256sum | cut -c1-16; else shasum -a 256 | cut -c1-16; fi; }

for side in A B; do
  rev=$1; [ $side = B ] && rev=$2
  mkdir -p "$tmp/$side"
  git -C "$root" archive "$rev" rtl | tar -x -C "$tmp/$side"
  echo "$side = $rev ($(git -C "$root" rev-parse --short "$rev"))"
done
verilator --version

rc=0
# ORFS nangate45 / sky130hd, Yosys/sv2v unit flows, the FPGA build (#53)
# and the SRAM_OREG simulation family; then no defines (simulation).
for defs in "SYNTHESIS" "SYNTHESIS SIGIL_SRAM_FAKERAM45" "SYNTHESIS SIGIL_SRAM_SKY130" \
            "SYNTHESIS SIGIL_SRAM_OREG" "SYNTHESIS SIGIL_VRF_OREG" ""; do
  D=(); for d in $defs; do D+=("+define+$d"); done
  for side in A B; do
    (cd "$tmp/$side/rtl" && ls core/*.sv crypto/*.sv soc/*.sv fpga/*.sv > files.txt &&
     verilator -E -P ${D[@]+"${D[@]}"} -Icore $(cat files.txt)) > "$tmp/$side.pp" 2> "$tmp/$side.err" ||
      { echo "preprocessing $side failed:" >&2; head "$tmp/$side.err" >&2; exit 2; }
  done
  ha=$(hash < "$tmp/A.pp"); hb=$(hash < "$tmp/B.pp")
  if cmp -s "$tmp/A.pp" "$tmp/B.pp"; then
    r=IDENTICAL
  else
    r="DIFFERENT ($(diff "$tmp/A.pp" "$tmp/B.pp" | grep -c '^[<>]' || true) lines)"
    [ -n "$defs" ] && rc=1
  fi
  echo "defines=[${defs:-none, simulation view}] lines=$(wc -l < "$tmp/B.pp" | tr -d ' ') A=$ha B=$hb $r"
done
[ $rc -eq 0 ] && echo "SYNTHESIS VIEWS IDENTICAL" || echo "SYNTHESIS VIEWS DIFFER"
exit $rc
