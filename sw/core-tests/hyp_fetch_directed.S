// Guest (VS) instruction fetch across 4K pages under two-stage
// translation (#53 review). The guest runs from VA 0x400000.. (VS
// 4K pages, VA = GPA) whose G-stage pages are filled in on demand:
//  - a sequential crossing into a page with no G-stage leaf: fetch
//    guest-page fault (20) with stval = VA, htval = GPA >> 2,
//    sepc = VA; HS maps it and resumes;
//  - a 32-bit instruction straddling into a page with no VS leaf:
//    fetch page fault (12) with stval = second half, sepc = first;
//    HS maps both stages and resumes, the instruction completes;
//  - guest ecall (10) ends it. Every guest instruction must run once.
// With FPGA_TIMING the fetch translation comes from the fetch page
// register and faults from the registered I-port lookup.
// t0 = test number; exit store 0 = pass.
    .option arch, +h
    .option norvc
    .option norelax
    .text
    .globl _start
.equ EXIT, 0x10000000
.equ GVA0, 0x400000              // guest code VA = GPA

.macro PTE dst, pa, flags
    srli \dst, \pa, 2
    ori \dst, \dst, \flags
.endm

_start:
    la sp, stack_top
    la t1, mtrap_stack_top
    csrw mscratch, t1
    la t1, trap_stack_top
    csrw sscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_hs
    csrw stvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // G stage: GPA 0..2M identity (2M leaf, U RWX); GPA 0x400000..
    // through g_l0 (filled in on demand, page 0 present).
    la a0, g_root
    la a1, g_l1
    PTE a2, a1, 0x01
    sd a2, 0(a0)
    li a2, 0xdf
    sd a2, 0(a1)
    la a3, g_l0
    PTE a2, a3, 0x01
    sd a2, 16(a1)
    la a4, gpage0
    PTE a2, a4, 0xdf
    sd a2, 0(a3)
    // VS: VA 0x400000.. -> GPA (same), pages 0 and 1 present
    la a0, vs_root
    la a1, vs_l1
    PTE a2, a1, 0x01
    sd a2, 0(a0)
    la a3, vs_l0
    PTE a2, a3, 0x01
    sd a2, 16(a1)
    li a4, GVA0
    PTE a2, a4, 0xcb             // V R X A D
    sd a2, 0(a3)
    li a4, GVA0 + 0x1000
    PTE a2, a4, 0xcb
    sd a2, 8(a3)
    la a0, vs_root
    srli a0, a0, 12
    li a1, (8 << 60) | (1 << 44)
    or a0, a0, a1
    csrw vsatp, a0
    la a0, g_root
    srli a0, a0, 12
    li a1, (8 << 60) | (1 << 44)
    or a0, a0, a1
    csrw hgatp, a0
    hfence.gvma zero, zero
    li t1, (1 << 10) | (1 << 12) | (1 << 20)
    csrw medeleg, t1
    la t1, hs_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    li t1, (1 << 7)
    csrs mie, t1                 // MTIE: lower modes take M timer IRQs
    mret

hs_main:
    li t0, 1
    li a5, 0
    li t1, (1 << 7)
    csrs hstatus, t1             // SPV = 1
    li t1, (1 << 8)
    csrs sstatus, t1             // SPP = S (VS)
    li t1, GVA0 + 4096 - 16
    csrw sepc, t1
    sret                         // -> guest, near the end of page 0

hs_done:
    li t0, 2
    li t1, 4
    bne a5, t1, fail             // every guest instruction once
    la a0, rec
    ld t1, 0(a0)
    li t2, 20
    bne t1, t2, fail
    ld t1, 8(a0)
    li t2, GVA0 + 0x1000
    bne t1, t2, fail
    ld t1, 16(a0)
    li t2, (GVA0 + 0x1000) >> 2
    bne t1, t2, fail
    ld t1, 24(a0)
    li t2, GVA0 + 0x1000
    bne t1, t2, fail
    li t0, 3
    ld t1, 32(a0)
    li t2, 12
    bne t1, t2, fail
    ld t1, 40(a0)
    li t2, GVA0 + 0x2000
    bne t1, t2, fail
    ld t1, 56(a0)
    li t2, GVA0 + 0x2000 - 2
    bne t1, t2, fail
    li t0, 4
    ld t1, 64(a0)
    li t2, 10
    bne t1, t2, fail
pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

handler_m:
    csrrw sp, mscratch, sp       // M timer interrupts: just return
    sd t1, -8(sp)
    csrr t1, mcause
    bgez t1, 9f
    ld t1, -8(sp)
    csrrw sp, mscratch, sp
    mret
9:  csrr t0, mcause              // anything else fails
    slli t0, t0, 16
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

// HS handler: record {scause, stval, htval, sepc}; map what the
// fault needs and retry; a guest ecall ends the test.
handler_hs:
    csrrw sp, sscratch, sp
    sd t1, -8(sp)
    sd t2, -16(sp)
    sd a0, -24(sp)
    sd a1, -32(sp)
    la t2, nrec
    ld t1, 0(t2)
    addi a0, t1, 1
    sd a0, 0(t2)
    slli t1, t1, 5
    la t2, rec
    add t2, t2, t1
    csrr t1, scause
    sd t1, 0(t2)
    csrr a0, stval
    sd a0, 8(t2)
    csrr a0, htval
    sd a0, 16(t2)
    csrr a0, sepc
    sd a0, 24(t2)
    li a0, 10
    beq t1, a0, 3f
    li a0, 20
    beq t1, a0, 1f
    li a0, 12
    beq t1, a0, 2f
    j fail
1:  la a0, g_l0                  // G leaf for GPA page 1
    la a1, gpage1
    PTE a1, a1, 0xdf
    sd a1, 8(a0)
    hfence.gvma zero, zero
    j 4f
2:  la a0, vs_l0                 // VS leaf for VA page 2, G leaf
    li a1, GVA0 + 0x2000
    PTE a1, a1, 0xcb
    sd a1, 16(a0)
    la a0, g_l0
    la a1, gpage2
    PTE a1, a1, 0xdf
    sd a1, 16(a0)
    hfence.vvma zero, zero
    hfence.gvma zero, zero
    j 4f
3:  la a0, hs_done               // guest ecall: back to HS
    csrw sepc, a0
    li a0, (1 << 7)
    csrc hstatus, a0             // SPV = 0
    li a0, (1 << 8)
    csrs sstatus, a0             // SPP = S
4:  ld t1, -8(sp)
    ld t2, -16(sp)
    ld a0, -24(sp)
    ld a1, -32(sp)
    csrrw sp, sscratch, sp
    sret

// ---- guest pages (GPA 0x400000 + i*4K -> host gpage_i) ------------
    .p2align 12
gpage0:
    .skip 4096 - 16, 0           // (never executed)
    nop
    nop
    nop
    addi a5, a5, 1               // last word of page 0
gpage1:                          // sequential crossing: G fault first
    addi a5, a5, 1
    j 1f
    .skip 4096 - 8 - 8, 0
1:  nop
    .option rvc
    c.nop
    .4byte 0x00178793            // addi a5, a5, 1, straddles into page 2
    .option norvc
    .set gpage2, gpage1 + 4096
gpage2_word1:
    addi a5, a5, 1
    ecall
1:  j 1b
    .p2align 12, 0

    .data
    .align 3
nrec: .dword 0
rec:  .skip 8 * 4 * 8
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
    .skip 256
mtrap_stack_top:
    .align 14
g_root: .skip 16384
    .align 12
g_l1:   .skip 4096
g_l0:   .skip 4096
vs_root: .skip 4096
vs_l1:  .skip 4096
vs_l0:  .skip 4096
