# Directed misaligned-access probe

`probe.S` verifies the ACT DUT declaration `MISALIGNED_LDST:
false` (`sw/act4-cva6/sigil-cv64a6.yaml`) on the scalar
CVA6 model: all misaligned scalar loads/stores, FP
loads/stores, LR and AMOs must trap with the expected
mcause (4 = load misaligned, 6 = store/AMO misaligned; LR
is store-class on CVA6), trapping stores must not modify
memory, and aligned controls must not trap. 53 cases; HTIF
`tohost` halt like `riscv-tests` (pass 1; fail encodes the
case index; 2002+i = memory-integrity failure at byte i;
3002 = case-count mismatch).

This settles an inherited-config conflict: the upstream
CVA6+Ara ACT config notes (discrepancy D13) that misaligned
accesses silently corrupt on that build, while this scalar
build's LSU raises misaligned exceptions. The ACT
`Misalign` suite requires `MISALIGNED_LDST: true`
(non-trapping implementations), so it correctly generates
zero ELFs for this DUT; this probe is the stored evidence
for the trapping behavior instead (issue #20).

Build and run:

```sh
riscv64-elf-gcc -nostdlib -nostartfiles -march=rv64imafdc \
  -mabi=lp64d -T sw/misalign/link.ld sw/misalign/probe.S \
  -o third_party/cva6/directed-elfs/misalign-probe
ELF_SUBDIR=directed-elfs TEST_LISTS=none TESTS=misalign-probe \
  RUN_NAME=misalign-probe ./scripts/cva6_docker.sh regression
```
