// Executing page remapped without SFENCE (#53 review): S runs on a
// page whose PTE (D=0) is changed to an identical copy of the page;
// a store to the same page then re-walks for D, so the TLB now maps
// the page to the copy while execution continues on it. Until the
// SFENCE.VMA either translation may be used for the fetch (the old
// one may stay cached), and the store must land in the copy (its
// walk read the new PTE). The test passes with either fetch choice.
// t0 = test number; exit store 0 = pass.
    .option norvc
    .option norelax
    .text
    .globl _start
.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000          // identity 4K pages for VA 0..2M (global)
.equ COPY,   0x1E0000
.equ EXIT,   0x10000000
_start:
    la sp, stack_top
    la t1, mtrap_stack_top
    csrw mscratch, t1
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
    li t2, PGROOT
    li t1, (PGL1 >> 2) | 1
    sd t1, 0(t2)
    li t2, PGL1
    li t1, (PGL0 >> 2) | 1
    sd t1, 0(t2)
    li t1, (EXIT >> 2) | 0xE7
    sd t1, 128 * 8(t2)
    li t1, 0xEF                    // V R W X G A D
    li t2, PGL0
    li a0, 512
1:  sd t1, 0(t2)
    li a1, (0x1000 >> 2)
    add t1, t1, a1
    addi t2, t2, 8
    addi a0, a0, -1
    bnez a0, 1b
    la a0, stale_pg                // the page under test: D = 0
    srli a1, a0, 12
    slli a1, a1, 3
    li a2, PGL0
    add a1, a1, a2
    srli a2, a0, 2
    ori a2, a2, 0x6F               // V R W X G A
    sd a2, 0(a1)
    li a1, COPY                    // identical copy of the page
    li a2, 0x1000
1:  ld a3, 0(a0)
    sd a3, 0(a1)
    addi a0, a0, 8
    addi a1, a1, 8
    addi a2, a2, -8
    bnez a2, 1b
    fence.i
    li t1, (8 << 60) | (PGROOT >> 12)
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    li t1, (1 << 7)
    csrs mie, t1                // MTIE: lower modes take M timer IRQs
    mret
s_main:
    li t0, 1
    li s2, 3
1:  jal stale_pg
    addi s2, s2, -1
    bnez s2, 1b
pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b
handler_m:
    csrrw sp, mscratch, sp      // M timer interrupts (--irq-timer-after)
    sd t1, -40(sp)              // just return; anything else falls
    csrr t1, mcause             // through to the handler below
    bgez t1, 9f
    ld t1, -40(sp)
    csrrw sp, mscratch, sp
    mret
9:  ld t1, -40(sp)
    csrrw sp, mscratch, sp      // no other trap is expected
    csrr t1, mcause
    slli t1, t1, 16
    or t0, t0, t1
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

    .p2align 12
stale_pg:
    la a1, stale_pg
    srli a2, a1, 12
    slli a2, a2, 3
    li a3, PGL0
    add a2, a2, a3                 // &PTE(stale_pg)
    li a3, (COPY >> 2) | 0x6F      // -> the copy, still D = 0
    sd a3, 0(a2)
    la a4, st_data
    li a5, 0x5EED
    sd a5, 0(a4)                   // D = 0: re-walk reads the new PTE
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    // the store went through the new translation: into the copy
    la a4, st_data
    sub a4, a4, a1
    li a3, COPY
    add a3, a3, a4
    ld a5, 0(a3)
    li a3, 0x5EED
    bne a5, a3, fail
    // and the walk set D in the new PTE
    ld a3, 0(a2)
    andi a3, a3, 0x80
    beqz a3, fail
    // restore: identity, D = 0, then SFENCE; clear the copy's word
    srli a3, a1, 2
    ori a3, a3, 0x6F
    sd a3, 0(a2)
    sfence.vma
    li a3, COPY
    add a3, a3, a4
    sd x0, 0(a3)
    ret
    .p2align 3
st_data:
    .quad 0

    .data
    .align 4
stack: .skip 1024
stack_top:
mtrap_stack: .skip 256
mtrap_stack_top:
