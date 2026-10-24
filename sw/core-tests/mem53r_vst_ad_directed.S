// Vector element accesses that need an A/D update (#53 review round
// 3, memory lens). With FPGA_TIMING the element's translation is the
// registered lookup taken in VLS_RD/RW (indexed: replayed in ACC); an
// element whose TLB entry lacks A, or D for a store, misses, walks
// (leaf read, A/D write-back under the walker lock) and replays its
// lookup after the fill, while the element's VRF data/index read must
// still hold. Sixteen data pages start with A=0 and D=0, TLB cold
// before each test. S-mode, Sv39.
//  1: vsuxei64, 8 elements on 8 different pages in permuted order:
//     memory, and every touched PTE has A and D.
//  2: masked-off elements and elements below vstart on A=0 pages are
//     not accessed: their pages keep A=0 (exact A/D updates).
//  3: vlse64 over 4 pages: A set, D still clear; then vsse64 over the
//     same pages: D set.
//  4: vsseg2e64 whose fields straddle a page boundary (element 1:
//     field 0 on page 12, field 1 on page 13): both pages A and D.
//  5: vle64 then vse64 of the same 8 elements on a fresh page, then
//     scalar read-back.
// t0 = test number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start

.equ EXIT,  0x10000000
.equ ROOT,  0x100000
.equ L1,    0x101000
.equ L0,    0x102000            // VA 0x200000 + i*4K -> PA 0x180000 + i*4K
.equ DVA,   0x200000
.equ DPA,   0x180000

.macro PTEAD pg, want          // PTE of data page pg: (flags & 0xC0) == want
    li t1, L0 + \pg * 8
    ld t2, 0(t1)
    andi t2, t2, 0xC0
    li t3, \want
    bne t2, t3, fail_s
.endm
.macro MEMD addr, val
    li t1, \addr
    ld t2, 0(t1)
    li t3, \val
    bne t2, t3, fail_s
.endm

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    csrw mscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    li t1, (1 << 9)
    csrs mstatus, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, ROOT
    li t2, ROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, (L1 >> 2) | 1
    li t2, ROOT
    sd t1, 0(t2)
    li t1, 0xCF                 // L1[0]: VA 0..2M identity 2M leaf
    li t2, L1
    sd t1, 0(t2)
    li t1, (L0 >> 2) | 1
    sd t1, 8(t2)
    li t1, L0                   // 16 pages, R W, A=0 D=0
    li t2, (DPA >> 2) | 0x07
    li a0, 16
1:  sd t2, 0(t1)
    li a1, 1 << 10
    add t2, t2, a1
    addi t1, t1, 8
    addi a0, a0, -1
    bnez a0, 1b
    li t1, DPA                  // every dword holds its PA
    li t2, DPA + 16 * 0x1000
1:  sd t1, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, ROOT >> 12
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
    // 1: indexed store over pages 3,0,7,1,6,2,5,4.
    li t0, 1
    vsetivli x0, 8, e64, m1, ta, mu
    la t1, idx1
    vle64.v v4, (t1)            // (identity: no data page touched)
    vid.v v8
    li t1, 0x100
    vadd.vx v8, v8, t1
    sfence.vma
    li a1, DVA
    vsuxei64.v v8, (a1), v4
    MEMD DPA + 3 * 0x1000 + 0x18, 0x100
    MEMD DPA + 0 * 0x1000 + 0x20, 0x101
    MEMD DPA + 7 * 0x1000 + 0x28, 0x102
    MEMD DPA + 1 * 0x1000 + 0x30, 0x103
    MEMD DPA + 6 * 0x1000 + 0x38, 0x104
    MEMD DPA + 2 * 0x1000 + 0x40, 0x105
    MEMD DPA + 5 * 0x1000 + 0x48, 0x106
    MEMD DPA + 4 * 0x1000 + 0x50, 0x107
    PTEAD 0, 0xC0
    PTEAD 3, 0xC0
    PTEAD 4, 0xC0
    PTEAD 7, 0xC0

    // 2: pages 8..11: elements 0 (below vstart), 1 (masked off),
    //    2 (active), 3 (masked off) of a strided store.
    li t0, 2
    vsetivli x0, 4, e64, m1, ta, mu
    li t1, 0x4
    vmv.s.x v0, t1              // only element 2 active
    vid.v v8
    li t1, 0x200
    vadd.vx v8, v8, t1
    sfence.vma
    li a1, DVA + 8 * 0x1000
    li a2, 0x1000
    li t1, 1
    csrw vstart, t1
    vsse64.v v8, (a1), a2, v0.t
    csrr t1, vstart
    bnez t1, fail_s
    MEMD DPA + 10 * 0x1000, 0x202
    MEMD DPA + 9 * 0x1000, DPA + 9 * 0x1000
    PTEAD 8, 0x00
    PTEAD 9, 0x00
    PTEAD 10, 0xC0
    PTEAD 11, 0x00
    // and an element-0-masked unit-stride load from page 11's end
    // into page 12 (element 1 active): page 11 untouched, 12 gets A
    li t1, 0x2
    vmv.s.x v0, t1
    sfence.vma
    vsetivli x0, 2, e64, m1, ta, mu
    li a1, DVA + 12 * 0x1000 - 8
    vle64.v v9, (a1), v0.t
    PTEAD 11, 0x00
    PTEAD 12, 0x40
    vsetivli x0, 2, e64, m1, ta, mu
    vslidedown.vi v10, v9, 1
    vmv.x.s t2, v10
    li t3, DPA + 12 * 0x1000
    bne t2, t3, fail_s

    // 3: strided load over pages 13, 14 (A only), then a store.
    li t0, 3
    vsetivli x0, 2, e64, m1, ta, mu
    sfence.vma
    li a1, DVA + 13 * 0x1000 + 0x80
    li a2, 0x1000
    vlse64.v v8, (a1), a2
    PTEAD 13, 0x40
    PTEAD 14, 0x40
    vmv.x.s t2, v8
    li t3, DPA + 13 * 0x1000 + 0x80
    bne t2, t3, fail_s
    vadd.vi v8, v8, 1
    sfence.vma
    vsse64.v v8, (a1), a2
    PTEAD 13, 0xC0
    PTEAD 14, 0xC0
    MEMD DPA + 14 * 0x1000 + 0x80, DPA + 14 * 0x1000 + 0x81

    // 4: segment store straddling pages 11 -> 12 (11 still A=0).
    li t0, 4
    vsetivli x0, 2, e64, m1, ta, mu
    vid.v v8
    vadd.vi v8, v8, 7           // field 0: 7, 8
    vid.v v9
    vadd.vi v9, v9, 12          // field 1: 12, 13
    sfence.vma
    li a1, DVA + 12 * 0x1000 - 24
    vsseg2e64.v v8, (a1)        // e0: -24, -16; e1: -8 (p11), +0 (p12)
    PTEAD 11, 0xC0
    PTEAD 12, 0xC0
    MEMD DPA + 12 * 0x1000 - 24, 7
    MEMD DPA + 12 * 0x1000 - 16, 12
    MEMD DPA + 12 * 0x1000 - 8, 8
    MEMD DPA + 12 * 0x1000, 13

    // 5: load then store 8 elements on page 15, scalar read-back.
    li t0, 5
    vsetivli x0, 8, e64, m1, ta, mu
    sfence.vma
    li a1, DVA + 15 * 0x1000 + 0x400
    vle64.v v8, (a1)
    PTEAD 15, 0x40
    vadd.vi v8, v8, 3
    vse64.v v8, (a1)
    PTEAD 15, 0xC0
    MEMD DPA + 15 * 0x1000 + 0x400, DPA + 15 * 0x1000 + 0x403
    MEMD DPA + 15 * 0x1000 + 0x438, DPA + 15 * 0x1000 + 0x43B
    li t1, DVA + 15 * 0x1000 + 0x438
    ld t2, 0(t1)
    li t3, DPA + 15 * 0x1000 + 0x43B
    bne t2, t3, fail_s

    li a0, 0
    ecall
1:  j 1b
fail_s:
    li a0, 1
    ecall
1:  j 1b

// M: the final ECALL ends the test (a0 = 0 pass); any other trap
// fails with (t0 | 0x80 | mcause << 8).
handler_m:
    csrrw sp, mscratch, sp
    csrr t1, mcause
    li t2, 9
    bne t1, t2, 2f
    li t1, EXIT
    bnez a0, 3f
    sd x0, 0(t1)
1:  j 1b
3:  sd t0, 0(t1)
1:  j 1b
2:  la t2, m_info
    sd t1, 0(t2)
    csrr t3, mepc
    sd t3, 8(t2)
    csrr t3, mtval
    sd t3, 16(t2)
    slli t1, t1, 8
    or t1, t1, t0
    ori t1, t1, 0x80
    li t2, EXIT
    sd t1, 0(t2)
1:  j 1b

    .data
    .align 3
idx1:        .quad 0x3018, 0x0020, 0x7028, 0x1030, 0x6038, 0x2040, 0x5048, 0x4050
m_info:      .quad 0, 0, 0
    .align 4
main_stack:  .skip 1024
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
