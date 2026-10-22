#!/bin/bash
# Post-process the kernels result set into evidence files.
set -u
cd ~/wt/56-perf-kernels
source deps/env.sh
P=build/perf/kernels-default
python3 -I sw/bench/kernels/kernels_report.py $P --md $P/kernels-report.md --csv $P/kernels.csv
{ echo "\$ python3 -I sw/bench/kernels/kernels_model.py --check   # at $(git rev-parse --short HEAD), $(python3 --version)"
  python3 -I sw/bench/kernels/kernels_model.py --check; echo "exit $?"; } > $P/kat-check.log 2>&1
for v in scalar autovec; do
  cp $P/bin/kernels-$v/build.log $P/build-kernels-$v.log
  E=$P/bin/kernels-$v/kernels.elf
  {
    echo "# Kernel functions of kernels-$v (kernels.bin sha256 $(sha256sum $P/bin/kernels-$v/kernels.bin | cut -d' ' -f1))"
    echo "# $(riscv64-unknown-elf-objdump --version | head -1)"
    echo "# census: function, instructions (not counting the nop padding after it: every kernel is 64-byte aligned), vector instructions (mnemonic starting with v), distinct vector mnemonics"
    riscv64-unknown-elf-objdump -d --no-show-raw-insn $E | awk -F'\t' '
      /^[0-9a-f]+ <[a-z0-9_]+_(c|rvv|rvv8|ref)>:/ { fn = $0; sub(/.*</, "", fn); sub(/>:.*/, "", fn); order[++n] = fn; next }
      /^$/ { fn = "" }
      fn != "" && $1 ~ /^ *[0-9a-f]+:$/ && $2 !~ /^nop/ { ins[fn]++; if ($2 ~ /^v/) { vec[fn]++; split($2, a, " "); if (!((fn, a[1]) in seen)) { seen[fn, a[1]] = 1; m[fn] = m[fn] " " a[1] } } }
      END { for (i = 1; i <= n; i++) { f = order[i]; printf "%-14s %4d %4d %s\n", f, ins[f], vec[f] + 0, m[f] } }'
    echo
    riscv64-unknown-elf-objdump -d --no-show-raw-insn $E | awk '/^[0-9a-f]+ <[a-z0-9_]+_(c|rvv|rvv8|ref)>:/,/^$/'
  } > $P/disasm-kernels-$v.txt
done
cmp_out=$P/repeat-compare.log
{ echo "# r0 vs r1 of every run: SIGIL_PERF records byte-identical; UART logs identical except the command line (record path)"
  for f in $P/runs/*.r0.perf; do g=${f/.r0./.r1.}; cmp -s $f $g && echo "identical $(basename $f) $(basename $g)" || echo "DIFFERENT $(basename $f)"; done
  for f in $P/runs/*.r0.log; do g=${f/.r0./.r1.}; if diff <(tail -n +2 $f) <(tail -n +2 $g) >/dev/null; then echo "identical after line 1: $(basename $f) $(basename $g)"; else echo "DIFFERENT $(basename $f)"; fi; done
} > $cmp_out
cat $cmp_out
