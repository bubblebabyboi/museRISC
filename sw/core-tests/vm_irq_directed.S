// Interrupts between instructions under Sv39 with every access
// walking (#53 review: FPGA_TIMING replays a data access after its
// walk and registers the fetch page). Run with --irq-timer-after N
// over a window (the loop runs from about cycle 1.5k to 5.5k with
// the default harness timing): the M-timer interrupt lands anywhere in a loop of
// SFENCE.VMA, TLB-missing loads/stores, I/O reads (a read counter),
// AMOs, a page-crossing vector load and a delegated page fault.
// Checks: one interrupt at most, its mepc on an instruction of the
// loop, every I/O read executed exactly once and in order (the
// logged counter values are consecutive and the device saw no extra
// read), the AMO counter equals the register count, and every page
// fault (13, stval, sepc) is the expected one.
// t0 = check number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start

.equ EXIT,     0x10000000
.equ ROOT_A,   0x100000
.equ L1_A,     0x101000
.equ L0_A,     0x102000
.equ V_X,      0x200000         // PA 0x180000 RW
.equ V_Y,      0x201000         // PA 0x181000 RW
.equ V_Z,      0x202000         // PA 0x182000 RW
.equ V_N,      0x203000         // unmapped
.equ VA_DEV,   0x208000         // PA 0x20000000 (I/O read counter)
.equ ITER,     12

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    la t1, s_trap_stack_top
    addi t1, t1, -64
    csrw sscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_s
    csrw stvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, (1 << 9)
    csrs mstatus, t1
    // (core_tb memory starts zeroed: the tables need no clearing,
    // which keeps the setup short for the IRQ offset sweep.)
    li t1, 0x180FF0             // the words the loop reads
    li t2, 0x181020
1:  sd t1, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, 0x180000
    sd t1, 0(t1)
    li t1, 0x181000
    sd x0, 0(t1)                // AMO counter
    PTEW ROOT_A, 0, L1_A, 0x01
    PTEW L1_A, 0, 0x000000, 0xCF
    PTEW L1_A, 1, L0_A, 0x01
    PTEW L0_A, 0, 0x180000, 0xC7
    PTEW L0_A, 1, 0x181000, 0xC7
    PTEW L0_A, 2, 0x182000, 0xC7
    PTEW L0_A, 8, 0x20000000, 0xC7
    li t1, 0xB100
    csrw medeleg, t1
    li t1, (1 << 7)             // mie.MTIE (taken in S regardless)
    csrs mie, t1
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, ROOT_A >> 12
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

s_main:
    li s0, VA_DEV
    la s1, rlog
    li s2, 0                    // I/O reads done
    li s3, 0                    // AMOs done
    li s4, V_Y
    li s5, V_N
    li s6, ITER
    li a2, 1
    vsetivli x0, 4, e64, m1, tu, mu
    ld s7, 0(s0)                // first counter value
    addi s2, s2, 1
    sd s7, 0(s1)
    addi s1, s1, 8
loop_start:
    sfence.vma
    ld a0, 0(s0)
    sd a0, 0(s1)
    addi s1, s1, 8
    addi s2, s2, 1
    li a1, V_X
    ld a3, 0(a1)
    amoadd.d x0, a2, (s4)
    addi s3, s3, 1
    li a1, V_X + 0xFF0
    vle64.v v8, (a1)            // X then Y
pf_load:
    ld a4, 0(s5)                // page fault, S skips it
    ld a0, 0(s0)
    sd a0, 0(s1)
    addi s1, s1, 8
    addi s2, s2, 1
    li a1, V_Z
    sd a3, 8(a1)
    sfence.vma
    amoadd.d a5, a2, (s4)
    addi s3, s3, 1
    ld a0, 0(s0)
    sd a0, 0(s1)
    addi s1, s1, 8
    addi s2, s2, 1
    addi s6, s6, -1
    bnez s6, loop_start
loop_end:
    // 1: I/O reads consecutive, no extra read.
    li t0, 1
    la a1, rlog
    mv a3, s7
1:  ld a4, 0(a1)
    bne a4, a3, fail_s
    addi a3, a3, 1
    addi a1, a1, 8
    bne a1, s1, 1b
    ld a4, 0(s0)
    bne a4, a3, fail_s
    // 2: AMO counter.
    li t0, 2
    ld a4, 0(s4)
    bne a4, s3, fail_s
    // 3: page faults: ITER of them, all at pf_load on V_N.
    li t0, 3
    la a1, s_count
    ld a4, 0(a1)
    li a3, ITER
    bne a4, a3, fail_s
    la a1, s_bad
    ld a4, 0(a1)
    bnez a4, fail_s
    // 4: at most one interrupt, mepc on S code.
    li t0, 4
    la a1, irq_count
    ld a4, 0(a1)
    li a3, 1
    bgtu a4, a3, fail_s
    beqz a4, 2f
    la a1, irq_epc
    ld a4, 0(a1)
    la a3, s_main
    bltu a4, a3, fail_s
    la a3, handler_s_end        // S code or the S handler
    bgeu a4, a3, fail_s
2:
    la a1, pass
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
    j fail_s

pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail_s:
    mv s11, t0
    la a1, m_fail
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
1:  j 1b
m_fail:
    mv t0, s11
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

// M: interrupts are counted and return; an S ecall with
// resume_addr set lands there in M; anything else fails (98).
handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    csrr t1, mcause
    bgez t1, 3f
    la t2, irq_count
    ld t1, 0(t2)
    addi t1, t1, 1
    sd t1, 0(t2)
    csrr t1, mepc
    la t2, irq_epc
    sd t1, 0(t2)
    j 2f
3:  la t2, resume_addr
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw mepc, t1
    li t1, (3 << 11)
    csrs mstatus, t1
    j 2f
1:  li t1, EXIT
    li t2, 98
    sd t2, 0(t1)
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

// S: a page fault must be the load at pf_load on V_N; skip it.
handler_s:
    csrrw sp, sscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    sd t3, 16(sp)
    la t1, s_count
    ld t2, 0(t1)
    addi t2, t2, 1
    sd t2, 0(t1)
    csrr t2, scause
    li t3, 13
    bne t2, t3, 1f
    csrr t2, stval
    li t3, V_N
    bne t2, t3, 1f
    csrr t2, sepc
    la t3, pf_load
    beq t2, t3, 2f
1:  la t1, s_bad
    li t2, 1
    sd t2, 0(t1)
2:  csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    ld t1, 0(sp)
    ld t2, 8(sp)
    ld t3, 16(sp)
    csrrw sp, sscratch, sp
    sret
handler_s_end:

    .data
    .align 3
resume_addr: .quad 0
s_count:     .quad 0
s_bad:       .quad 0
irq_count:   .quad 0
irq_epc:     .quad 0
    .align 4
rlog:        .skip 8 * (3 * ITER + 4)
main_stack:  .skip 1024
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
s_trap_stack: .skip 1024
s_trap_stack_top:
