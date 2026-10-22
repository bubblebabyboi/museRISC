// Vector loads/stores under Sv39 translation (#53 review). With
// FPGA_TIMING every element's translation comes from the registered
// D-TLB lookup (taken in VLS_RD/RW, replayed for indexed elements
// and after any TLB update), so page crossings, TLB misses inside a
// sequence, page faults mid-sequence (vstart, stval), fault-only-
// first trims, masked elements on unmapped pages and SUM are run in
// S-mode with page faults delegated to S. Results are checked
// element by element against scalar loads of the same VAs.
// Data: VA 0x200000 + i*4K -> PA 0x180000 + i*4K, 64-bit word j of
// page i = (i << 16) | j. Pages 0-11 and 13 RW, 12 unmapped (mapped
// on demand by the handler in mode 1), 14 R only, 15 RW U.
// t0 = test number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start
.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000
.equ VA0,    0x200000
.equ PA0,    0x180000
.equ EXIT,   0x10000000
.equ SUM,    (1 << 18)
.macro VA reg, page, off
    li \reg, VA0 + \page * 0x1000 + \off
.endm
.macro CHK reg, v
    li t3, \v
    bne \reg, t3, fail
.endm
.macro CHK_TRAP cause, tval, vst
    la t2, s_cause
    ld t1, 0(t2)
    li t3, \cause
    bne t1, t3, fail
    sd x0, 0(t2)
    ld t1, 8(t2)
    li t3, \tval
    bne t1, t3, fail
    ld t1, 16(t2)
    li t3, \vst
    bne t1, t3, fail
.endm
.macro CHK_NOTRAP
    la t2, s_cause
    ld t1, 0(t2)
    bnez t1, fail
.endm

_start:
    la sp, stack_top
    la t1, trap_stack_top
    csrw mscratch, t1
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
    li t1, PGROOT
    li t2, PGROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t2, PGROOT
    li t1, (PGL1 >> 2) | 1
    sd t1, 0(t2)
    li t2, PGL1
    li t1, 0xEF                  // VA 0..2M identity RWX G A D
    sd t1, 0(t2)
    li t1, (PGL0 >> 2) | 1
    sd t1, 8(t2)
    li t1, (EXIT >> 2) | 0xE7
    sd t1, 128 * 8(t2)
    // data pages
    li a0, 0                     // page i
1:  li a1, 0x1000
    mul a2, a0, a1
    li a3, PA0
    add a2, a2, a3               // PA of page i
    srli a4, a2, 2
    ori a4, a4, 0xC7             // V RW A D
    li a5, 12
    beq a0, a5, 3f               // page 12 unmapped
    li a5, 14
    bne a0, a5, 2f
    xori a4, a4, 0x4             // page 14: no W
2:  li a5, 15
    bne a0, a5, 2f
    ori a4, a4, 0x10             // page 15: U
2:  slli a5, a0, 3
    li a6, PGL0
    add a5, a5, a6
    sd a4, 0(a5)
3:  li a5, 0                     // fill words
    slli a6, a0, 16
4:  or a7, a6, a5
    slli t1, a5, 3
    add t1, t1, a2
    sd a7, 0(t1)
    addi a5, a5, 1
    li t1, 512
    blt a5, t1, 4b
    addi a0, a0, 1
    li a5, 16
    blt a0, a5, 1b
    li t1, (1 << 4) | (1 << 13) | (1 << 15)
    csrw medeleg, t1
    li t1, (8 << 60) | (PGROOT >> 12)
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11) | (1 << 9)  // MPP = S, VS = Initial
    csrs mstatus, t1
    li t1, (1 << 7)
    csrs mie, t1                // MTIE: lower modes take M timer IRQs
    mret

s_main:
    // 1: unit-stride e32 across a page boundary, both pages missing.
    li t0, 1
    vsetivli x0, 16, e32, m1, ta, ma
    VA a1, 1, 4096 - 32
    sfence.vma
    vle32.v v1, (a1)
    CHK_NOTRAP
    la a4, vbuf
    vse32.v v1, (a4)
    li a2, 4
    li a3, 16
    jal chk32
    // 2: e64 m8 (64 elements, 512 B) across a boundary.
    li t0, 2
    li a5, 64
    vsetvli x0, a5, e64, m8, ta, ma
    VA a1, 3, 4096 - 256
    sfence.vma
    vle64.v v8, (a1)
    la a4, vbuf
    vse64.v v8, (a4)
    li a2, 8
    li a3, 64
    jal chk64
    // 3: strided e64, every element on another page (all misses).
    li t0, 3
    vsetivli x0, 8, e64, m1, ta, ma
    VA a1, 0, 8
    li a2, 4096 + 8
    sfence.vma
    vlse64.v v1, (a1), a2
    la a4, vbuf
    vse64.v v1, (a4)
    li a3, 8
    jal chk64
    // strided store back over the same elements, then reload
    vadd.vi v2, v1, 1
    sfence.vma
    vsse64.v v2, (a1), a2
    vlse64.v v3, (a1), a2
    vsub.vv v3, v3, v1
    li a5, 1
    vmv.v.x v4, a5
    vmsne.vv v5, v3, v4
    vcpop.m a5, v5
    bnez a5, fail
    // 4: indexed e64 over 8 pages in scrambled order (misses, each
    //    element's capture replayed), then an indexed store.
    li t0, 4
    vsetivli x0, 8, e64, m1, ta, ma
    la a5, idx8
    vle64.v v2, (a5)
    VA a1, 0, 0
    sfence.vma
    vluxei64.v v1, (a1), v2
    la a4, vbuf
    vse64.v v1, (a4)
    la a5, idx8
    li a3, 8
    jal chkidx64
    vid.v v3
    li a5, 0x3300
    vadd.vx v3, v3, a5
    sfence.vma
    vsuxei64.v v3, (a1), v2
    la a5, idx8
    li a6, 0
1:  ld a7, 0(a5)
    add a7, a7, a1
    ld a7, 0(a7)
    li s2, 0x3300
    add s2, s2, a6
    bne a7, s2, fail             // 0x3300 + k
    addi a5, a5, 8
    addi a6, a6, 1
    li a7, 8
    blt a6, a7, 1b
    // 5: unit-stride into the unmapped page 12: 13 at element 6
    //    (stval = page 12, vstart = 6), elements 0-5 written, 6+
    //    untouched; then the same with the handler mapping the page
    //    and returning to the load, which resumes and completes.
    li t0, 5
    vsetivli x0, 16, e32, m1, ta, mu
    li a5, 0x77
    vmv.v.x v1, a5
    VA a1, 11, 4096 - 24
    vle32.v v1, (a1)
    CHK_TRAP 13, VA0 + 12 * 0x1000, 6
    csrr a5, vstart
    CHK a5, 6
    csrw vstart, x0
    la a4, vbuf
    vse32.v v1, (a4)
    li a2, 4
    li a3, 6
    jal chk32
    la a4, vbuf + 24
    li a6, 10
1:  lw a5, 0(a4)
    CHK a5, 0x77
    addi a4, a4, 4
    addi a6, a6, -1
    bnez a6, 1b
    li a5, 1
    la a4, s_mode
    sd a5, 0(a4)                 // handler maps page 12 and retries
    sfence.vma
    vle32.v v1, (a1)
    CHK_TRAP 13, VA0 + 12 * 0x1000, 6
    csrr a5, vstart
    CHK a5, 0
    la a4, vbuf
    vse32.v v1, (a4)
    li a2, 4
    li a3, 16
    jal chk32
    jal unmap12
    // 6: fault-only-first over the same boundary trims vl to 6.
    li t0, 6
    vsetivli x0, 16, e32, m1, ta, ma
    vle32ff.v v1, (a1)
    CHK_NOTRAP
    csrr a5, vl
    CHK a5, 6
    la a4, vbuf
    vse32.v v1, (a4)
    li a2, 4
    li a3, 6
    jal chk32
    sfence.vma
    vsetivli x0, 16, e32, m1, ta, ma
    vle32ff.v v1, (a1)           // with misses
    csrr a5, vl
    CHK a5, 6
    // element 0 on the unmapped page: traps, vl unchanged
    vsetivli x0, 16, e32, m1, ta, ma
    VA a2, 12, 0
    vle32ff.v v1, (a2)
    CHK_TRAP 13, VA0 + 12 * 0x1000, 0
    csrr a5, vl
    CHK a5, 16
    // 7: indexed load whose element 3 is on page 12.
    li t0, 7
    vsetivli x0, 8, e64, m1, ta, mu
    la a5, idx_f
    vle64.v v2, (a5)
    li a5, 0x99
    vmv.v.x v1, a5
    VA a1, 0, 0
    sfence.vma
    vluxei64.v v1, (a1), v2
    CHK_TRAP 13, VA0 + 12 * 0x1000 + 0x18, 3
    csrw vstart, x0
    la a4, vbuf
    vse64.v v1, (a4)
    la a5, idx_f
    li a3, 3
    jal chkidx64
    la a4, vbuf + 24
    ld a5, 0(a4)
    CHK a5, 0x99
    ld a5, 32(a4)
    CHK a5, 0x99
    // 8: vector store into the read-only page 14 at element 4.
    li t0, 8
    vsetivli x0, 16, e32, m1, ta, ma
    vid.v v1
    li a5, 0x4400
    vadd.vx v1, v1, a5
    VA a1, 13, 4096 - 16
    sfence.vma
    vse32.v v1, (a1)
    CHK_TRAP 15, VA0 + 14 * 0x1000, 4
    csrw vstart, x0
    lw a5, 0(a1)
    CHK a5, 0x4400
    lw a5, 12(a1)
    CHK a5, 0x4403
    VA a2, 14, 0
    ld a5, 0(a2)
    CHK a5, (14 << 16)           // untouched
    // 9: segment load (nf=2, e32) across a boundary with misses.
    li t0, 9
    vsetivli x0, 8, e32, m1, ta, ma
    VA a1, 1, 4096 - 24
    sfence.vma
    vlseg2e32.v v4, (a1)
    CHK_NOTRAP
    la a4, vbuf
    vse32.v v4, (a4)
    li a2, 8
    li a3, 8
    jal chk32
    la a4, vbuf
    vse32.v v5, (a4)
    VA a1, 1, 4096 - 20
    li a2, 8
    li a3, 8
    jal chk32
    // 10: masked-off elements on the unmapped page never fault.
    li t0, 10
    vsetivli x0, 16, e32, m1, ta, mu
    li a5, 0x3f
    vmv.s.x v0, a5               // elements 0-5 only
    li a5, 0x55
    vmv.v.x v1, a5
    VA a1, 11, 4096 - 24
    sfence.vma
    vle32.v v1, (a1), v0.t
    CHK_NOTRAP
    la a4, vbuf
    vse32.v v1, (a4)
    li a2, 4
    li a3, 6
    jal chk32
    la a4, vbuf + 24
    lw a5, 0(a4)
    CHK a5, 0x55
    // 11: SUM adjacency for a vector load of the U page 15.
    li t0, 11
    vsetivli x0, 8, e64, m1, ta, ma
    VA a1, 15, 64
    li a6, SUM
    csrs sstatus, a6
    vle64.v v1, (a1)
    csrc sstatus, a6
    CHK_NOTRAP
    vle64.v v2, (a1)
    CHK_TRAP 13, VA0 + 15 * 0x1000 + 64, 0
    csrw vstart, x0
    vmv.x.s a5, v1
    CHK a5, (15 << 16) | 8
    // 12: whole-register load across a boundary with misses.
    li t0, 12
    VA a1, 5, 4096 - 32
    sfence.vma
    vl1re64.v v1, (a1)
    vsetivli x0, 8, e64, m1, ta, ma
    la a4, vbuf
    vse64.v v1, (a4)
    li a2, 8
    li a3, 8
    jal chk64
    // 13: indexed element misaligned on a mapped page after a
    //     flush (miss): 4 at element 2, vstart 2.
    li t0, 13
    vsetivli x0, 4, e32, m1, ta, mu
    la a5, idx_m
    vle32.v v2, (a5)
    VA a1, 7, 0
    sfence.vma
    vluxei32.v v1, (a1), v2
    CHK_TRAP 4, VA0 + 7 * 0x1000 + 0x2002, 2
    csrw vstart, x0
pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

// a1 = base VA, a2 = stride, a3 = count: vbuf (e32/e64) vs scalar
chk32:                           // (a1 preserved)
    la a4, vbuf
    mv s3, a1
1:  lw a6, 0(a4)
    lw a7, 0(s3)
    bne a6, a7, fail
    addi a4, a4, 4
    add s3, s3, a2
    addi a3, a3, -1
    bnez a3, 1b
    ret
chk64:                           // (a1 preserved)
    la a4, vbuf
    mv s3, a1
1:  ld a6, 0(a4)
    ld a7, 0(s3)
    bne a6, a7, fail
    addi a4, a4, 8
    add s3, s3, a2
    addi a3, a3, -1
    bnez a3, 1b
    ret
// a1 = base VA, a5 = index table (64-bit), a3 = count
chkidx64:
    la a4, vbuf
1:  ld a6, 0(a4)
    ld a7, 0(a5)
    add a7, a7, a1
    ld a7, 0(a7)
    bne a6, a7, fail
    addi a4, a4, 8
    addi a5, a5, 8
    addi a3, a3, -1
    bnez a3, 1b
    ret
unmap12:
    li a5, PGL0 + 12 * 8
    sd x0, 0(a5)
    sfence.vma
    la a5, s_mode
    sd x0, 0(a5)
    ret

handler_m:
    csrrw sp, mscratch, sp      // M timer interrupts (--irq-timer-after)
    sd t1, -40(sp)              // just return; anything else falls
    csrr t1, mcause             // through to the handler below
    bgez t1, 9f
    ld t1, -40(sp)
    csrrw sp, mscratch, sp
    mret
9:  ld t1, -40(sp)
    csrrw sp, mscratch, sp
    csrr t1, mcause
    slli t1, t1, 16
    or t0, t0, t1
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b
handler_s:
    csrrw sp, sscratch, sp
    sd t1, -8(sp)
    sd t2, -16(sp)
    la t2, s_cause
    csrr t1, scause
    sd t1, 0(t2)
    csrr t1, stval
    sd t1, 8(t2)
    csrr t1, vstart
    sd t1, 16(t2)
    la t2, s_mode
    ld t1, 0(t2)
    beqz t1, 1f
    li t1, ((PA0 + 12 * 0x1000) >> 2) | 0xC7
    li t2, PGL0 + 12 * 8
    sd t1, 0(t2)
    sfence.vma
    j 2f                         // retry the faulting instruction
1:  csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
2:  ld t1, -8(sp)
    ld t2, -16(sp)
    csrrw sp, sscratch, sp
    sret

    .data
    .align 6
vbuf:   .skip 1024
idx8:   .dword 0x7010, 0x1020, 0x5030, 0x0040, 0xB050, 0x3060, 0x9070, 0x2080
idx_f:  .dword 0x1008, 0x4010, 0x6000, 0xC018, 0x2020, 0x3028, 0x5030, 0x7038
idx_m:  .word 0x0, 0x1004, 0x2002, 0x3008
s_cause: .dword 0, 0, 0
s_mode:  .dword 0
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
