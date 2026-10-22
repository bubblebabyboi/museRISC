// Fetch access fault right after a fetch guest-page fault (#53
// review): mtval2/htval of an access fault must be 0 (priv spec:
// only guest-page faults write a GPA), even when the previous
// fetch lookup was a guest-page fault.
// A VS guest (vsatp Bare, hgatp Sv39x4 identity) jumps to GPA 2^41
// (wider than Sv39x4: instruction guest-page fault, cause 20,
// delegated to HS). stvec points at a word PMP denies to S, so the
// first HS fetch takes an instruction access fault (cause 1) to M.
//  1: M sees mcause 1, mtval = the denied word, mtval2 = 0.
//  2: the HS trap state: scause 20, stval 2^41, htval 2^41 >> 2.
// t0 = test number, exit store 0 = pass.
    .option arch, +h
    .option norvc
    .text
    .globl _start

.equ GROOT, 0x110000           // hgatp root (16 KiB aligned)

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    li t0, 1
    csrr t1, misa
    li t2, (1 << 7)
    and t1, t1, t2
    beqz t1, fail                  // misa.H
    // PMP: entry 0 NA4 over hs_bad with no permissions (S denied),
    // entry 15 catch-all RWX.
    la t1, hs_bad
    srli t1, t1, 2
    csrw pmpaddr0, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x10                    // A = NA4, no R/W/X
    csrw pmpcfg0, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // G-stage: 1 GiB identity leaf, U RWX A D.
    li t1, GROOT
    li t2, GROOT + 0x4000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, GROOT
    li t2, 0xDF
    sd t2, 0(t1)
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, GROOT >> 12
    csrw 0x680, t1                 // hgatp Sv39x4
    csrw 0x280, x0                 // vsatp Bare
    csrw satp, x0
    hfence.gvma
    li t1, (1 << 20)               // instruction guest-page fault -> HS
    csrw medeleg, t1
    la t1, hs_bad
    csrw stvec, t1
    // Enter VS at guest_code.
    la t1, guest_code
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)               // MPP = S
    csrs mstatus, t1
    li t1, 1
    slli t1, t1, 39                // MPV = 1
    csrs mstatus, t1
    mret

guest_code:
    nop
    nop
    li a1, 1
    slli a1, a1, 41
    jr a1                          // cause 20 at GPA 2^41
1:  j 1b

    .balign 64
hs_bad:                            // never executes (PMP denies S)
    j hs_bad

    .balign 64
handler_m:
    csrr a2, mcause
    csrr a3, mtval
    csrr a4, 0x34B                 // mtval2
    li t0, 1
    li t1, 1
    bne a2, t1, fail
    la t1, hs_bad
    bne a3, t1, fail
    bnez a4, fail
    li t0, 2
    csrr a2, scause
    li t1, 20
    bne a2, t1, fail
    csrr a2, stval
    li t1, 1
    slli t1, t1, 41
    bne a2, t1, fail
    csrr a2, 0x643                 // htval
    srli t1, t1, 2
    bne a2, t1, fail
pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    la t1, dbg_regs                // a2/a3/a4 at the failure (debug)
    sd a2, 0(t1)
    sd a3, 8(t1)
    sd a4, 16(t1)
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .align 3
dbg_regs:   .quad 0, 0, 0
    .align 4
main_stack:  .skip 1024
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
