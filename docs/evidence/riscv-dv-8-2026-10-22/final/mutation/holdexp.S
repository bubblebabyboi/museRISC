// Experiment: put a vstart-0-class op in EX while a vector load that
// consumes vstart != 0 is in MEM. Exit: number of traps (0 = none).
    .option arch, +v
    .option norvc
.macro SEQ pre:vararg
    li t3, 3
    csrw vstart, t3
    \pre
    vle8.v v12, (a2)
    vredsum.vs v8, v16, v24
.endm
    .text
    .globl _start
_start:
    la t1, trap
    csrw mtvec, t1
    li t1, (3 << 13) | (3 << 9)
    csrs mstatus, t1
    li s1, 0
    li a1, 16
    vsetvli x0, a1, e8, m1, tu, mu
    la a2, buf
    li t6, 3
    li a5, 7
    li a6, 3
loop:
    SEQ nop
    SEQ div a4, a5, a6
    SEQ ld a4, 0(a2)
    SEQ divu a4, a5, a6
    .align 6
    SEQ nop
    .align 6
    nop
    SEQ div a4, a5, a6
    .align 6
    nop
    nop
    SEQ div a4, a5, a6
    .align 6
    nop
    nop
    nop
    SEQ div a4, a5, a6
    .align 6
    SEQ fdiv.d f1, f2, f3
    addi t6, t6, -1
    bnez t6, loop
    li t1, 0x10000000
    sd s1, 0(t1)
1:  j 1b
    .align 2
trap:
    addi s1, s1, 1
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    mret
    .data
    .align 6
buf: .zero 64
