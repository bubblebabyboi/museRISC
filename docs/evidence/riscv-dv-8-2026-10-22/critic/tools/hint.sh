#!/bin/bash
# hint.sh: try to generate riscv_hint_instr_test (upstream gen_opts +hint_instr_ratio=5)
# with the patched pygen, 4 seeds in parallel; log the outcome of each.
O=~/rdvcrit/hint; rm -rf $O; mkdir -p $O
cd ~/wt/8-riscv-dv/build/riscv-dv/gen || exit 1
PY=~/wt/8-riscv-dv/build/riscv-dv/venv/bin/python3
{ echo "# riscv_hint_instr_test generation, pygen at $(git -C ~/wt/8-riscv-dv rev-parse --short HEAD) (stamp $(cat .stamp)), $(date -u +%FT%TZ)"
  echo "# cmd: $PY pygen/pygen_src/test/riscv_instr_base_test.py --target=sigil --gen_test=riscv_instr_base_test --num_of_tests=1 --start_idx=0 --seed=<s> --instr_cnt=10000 --num_of_sub_program=0 --hint_instr_ratio=5 --asm_file_name=... --log_file_name=..."; } > $O/summary.txt
for s in 1 2 3 4; do
  ( t0=$(date +%s)
    timeout 1800 $PY pygen/pygen_src/test/riscv_instr_base_test.py --target=sigil --gen_test=riscv_instr_base_test \
      --num_of_tests=1 --start_idx=0 --seed=$s --instr_cnt=10000 --num_of_sub_program=0 --hint_instr_ratio=5 \
      --asm_file_name=$O/hint_$s --log_file_name=$O/hint_$s.log > $O/hint_$s.out 2>&1
    rc=$?
    echo "seed $s rc=$rc t=$(( $(date +%s) - t0 ))s asm=$(ls $O/hint_${s}_0.S 2>/dev/null || echo none) | $(grep -E -m2 'Error|error|fail|Fail|solve|Traceback' $O/hint_$s.out | tr '\n' ' ' | cut -c1-300)" >> $O/summary.txt ) &
done
wait
echo "# done $(date -u +%FT%TZ)" >> $O/summary.txt
