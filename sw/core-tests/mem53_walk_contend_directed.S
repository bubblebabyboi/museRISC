// Fetch and data page walks competing for the data port (#53
// review: registered data translation with replay, walker held off
// while MEM owns the port payload). S-mode under Sv39 with 4 KiB
// identity pages, so every page touched after an SFENCE.VMA walks.
// The loop body straddles a code-page boundary and chases pointers
// through eight data pages; per node it loads a value, AMOADDs a
// counter, tries an SC with no reservation (fails, no access) and an
// LR/SC pair on its own word (succeeds). Four passes, each after an
// SFENCE.VMA.
//  1: sum of node values = 4 * 36.
//  2: every node counter = 4 (AMOs), every SC word = 4 (LR/SC).
//  3: 32 failed SCs, 32 successful ones.
// Traps go to M and fail the test. t0 = test number, exit 0 = pass.
    .option norvc
    .text
    .globl _start

.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000          // 512 identity 4K leaves, VA 0..2M
.equ NODES,  0x180000          // node k at NODES + k*0x1000 + k*0x48

_start:
    la sp, main_stack_top
    la t1, handler_m
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, PGROOT
    li t2, PGROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, (PGL1 >> 2) | 0x01
    li t2, PGROOT
    sd t1, 0(t2)
    li t1, (PGL0 >> 2) | 0x01
    li t2, PGL1
    sd t1, 0(t2)
    // L0[i] = identity page i, RWX A D.
    li t1, PGL0
    li t2, 0xCF
    li a0, 512
    li a1, (1 << 10)               // one PPN step
1:  sd t2, 0(t1)
    add t2, t2, a1
    addi t1, t1, 8
    addi a0, a0, -1
    bnez a0, 1b
    // Nodes: [0] next VA, [8] value k+1, [16] AMO counter, [24] SC word.
    li a0, 0
    li a2, 8
1:  li t1, 0x1048
    mul t1, t1, a0
    li t2, NODES
    add t1, t1, t2                 // node k
    addi a3, a0, 1
    li t2, 0x1048
    mul t2, t2, a3
    li a4, NODES
    add t2, t2, a4                 // node k+1
    bne a3, a2, 2f
    li t2, 0                       // last node: next = 0
2:  sd t2, 0(t1)
    sd a3, 8(t1)
    sd x0, 16(t1)
    sd x0, 24(t1)
    mv a0, a3
    blt a0, a2, 1b
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, PGROOT >> 12
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
    li s1, 4                       // passes
    li s2, 0                       // sum
    li s3, 0                       // failed SCs
    li s4, 0                       // successful SCs
    li s5, 1
    la s6, chase                   // straddles a page boundary
pass_loop:
    sfence.vma
    li a0, NODES
    jr s6

    .balign 4096
    .skip 4096 - 28
chase:                             // 7 words before the boundary
    ld a1, 8(a0)
    add s2, s2, a1
    addi a6, a0, 16
    amoadd.d x0, s5, (a6)
    addi a2, a0, 24
    sc.d a3, s5, (a2)              // no reservation: fails
    add s3, s3, a3
    // --- page boundary ---
    lr.d a4, (a2)
    addi a4, a4, 1
    sc.d a5, a4, (a2)
    seqz a5, a5
    add s4, s4, a5
    ld a0, 0(a0)                   // next node (load-use below)
    bnez a0, chase
    addi s1, s1, -1
    bnez s1, pass_loop
    j check

check:
    li t0, 1
    li a1, 4 * 36
    bne s2, a1, fail_s
    li t0, 2
    li a0, NODES
    li a2, 4
1:  ld a1, 16(a0)
    bne a1, a2, fail_s
    ld a1, 24(a0)
    bne a1, a2, fail_s
    ld a0, 0(a0)
    bnez a0, 1b
    li t0, 3
    li a1, 32
    bne s3, a1, fail_s
    bne s4, a1, fail_s
    li a0, 0
    ecall
1:  j 1b
fail_s:
    li a0, 1
    ecall
1:  j 1b

handler_m:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, 2f                 // any trap but the final ECALL fails
    li t1, 0x10000000
    bnez a0, 2f
    sd x0, 0(t1)
1:  j 1b
2:  li t1, 0x10000000
    beqz t0, 3f
    sd t0, 0(t1)
1:  j 1b
3:  li t0, 99
    sd t0, 0(t1)
1:  j 1b

    .data
    .align 4
main_stack:  .skip 512
main_stack_top:
