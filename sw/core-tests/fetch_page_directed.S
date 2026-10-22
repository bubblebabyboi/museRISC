// Translated instruction fetch across 4K pages (#53 review): S runs
// from identity-mapped 4K code pages, so every page change is a
// fetch-translation change (with FPGA_TIMING, an it_q reload).
//  1-2: 32-bit instructions straddling a page boundary into a mapped
//       page, an unmapped page (12, stval = second half) and a
//       non-executable page (12).
//  3:   the same VA executed under two ASIDs and under Bare, the
//       call right after the satp write (non-global code pages).
//  4:   the executing page remapped to an identical copy; SFENCE.VMA
//       on that VA, execution continues from the copy.
// t0 = test number; exit store 0 = pass.
    .option norelax
    .text
    .globl _start
.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000          // identity 4K pages for VA 0..2M (global)
.equ PGROOT2, 0x103000         // ASID 2 root (shares PGL1's globals)
.equ PGL1_2, 0x104000
.equ PGL0X,  0x105000          // non-global code page table (VA 0x200000..)
.equ PGL0X2, 0x106000          // ditto, ASID 2
.equ VX,     0x200000          // non-global code VA
.equ EXIT,   0x10000000
    .option norvc
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
    li t2, PGROOT + 0x7000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t2, PGROOT
    li t1, (PGL1 >> 2) | 1
    sd t1, 0(t2)
    li t2, PGROOT2
    li t1, (PGL1_2 >> 2) | 1
    sd t1, 0(t2)
    li t2, PGL1
    li t1, (PGL0 >> 2) | 1
    sd t1, 0(t2)
    li t1, (PGL0X >> 2) | 1
    sd t1, 8(t2)
    li t1, (EXIT >> 2) | 0xE7
    sd t1, 128 * 8(t2)
    li t2, PGL1_2
    li t1, (PGL0 >> 2) | 1
    sd t1, 0(t2)
    li t1, (PGL0X2 >> 2) | 1
    sd t1, 8(t2)
    li t1, (EXIT >> 2) | 0xE7
    sd t1, 128 * 8(t2)
    // identity 4K pages, V R W X G A D
    li t1, 0xEF
    li t2, PGL0
    li a0, 512
1:  sd t1, 0(t2)
    li a1, (0x1000 >> 2)
    add t1, t1, a1
    addi t2, t2, 8
    addi a0, a0, -1
    bnez a0, 1b
    // straddle targets: page after sx_un unmapped, after sx_nx R only
    la a0, sx_un_next
    srli a0, a0, 12
    slli a0, a0, 3
    li a1, PGL0
    add a0, a0, a1
    sd x0, 0(a0)
    la a0, sx_nx_next
    srli a0, a0, 12
    slli a0, a0, 3
    add a0, a0, a1
    la a2, sx_nx_next
    srli a2, a2, 2
    ori a2, a2, 0xE3              // V R G A D, no X
    sd a2, 0(a0)
    // VX: ASID 1 -> fn1 page, ASID 2 -> fn2 page (V R X A, not G);
    // under Bare VX is PA 0x200000: put fn3 there.
    la a2, fn1
    srli a2, a2, 2
    ori a2, a2, 0x4B
    li a0, PGL0X
    sd a2, 0(a0)
    la a2, fn2
    srli a2, a2, 2
    ori a2, a2, 0x4B
    li a0, PGL0X2
    sd a2, 0(a0)
    la a0, fn3
    li a1, VX
    lw a2, 0(a0)
    sw a2, 0(a1)
    lw a2, 4(a0)
    sw a2, 4(a1)
    // remap target for test 4: copy rm_page to PA 0x1E0000
    la a0, rm_page
    li a1, 0x1E0000
    li a2, 0x1000
1:  ld a3, 0(a0)
    sd a3, 0(a1)
    addi a0, a0, 8
    addi a1, a1, 8
    addi a2, a2, -8
    bnez a2, 1b
    fence.i
    li t1, (1 << 12)
    csrw medeleg, t1
    li t1, 7
    csrw mcounteren, t1         // S reads cycle/time/instret
    la t1, satp1
    ld t1, 0(t1)
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
    // 1: straddle into a mapped page (completes), twice.
    li t0, 1
    li a5, 0
    jal sx_ok
    jal sx_ok
    li t1, 2
    bne a5, t1, fail
    // 2: straddle into an unmapped page and a non-X page: 12 with
    //    sepc = the instruction, stval = the second half.
    li t0, 2
    la t1, sx_un_back
    la t2, s_resume
    sd t1, 0(t2)
    j sx_un
sx_un_back:
    la t2, s_cause
    ld t1, 0(t2)
    li t3, 12
    bne t1, t3, fail
    la t2, s_tval
    ld t1, 0(t2)
    la t3, sx_un_next
    addi t3, t3, -2             // the page boundary (second half)
    bne t1, t3, fail
    la t2, s_epc
    ld t1, 0(t2)
    addi t3, t3, -2
    bne t1, t3, fail
    la t1, sx_nx_back
    la t2, s_resume
    sd t1, 0(t2)
    j sx_nx
sx_nx_back:
    la t2, s_cause
    ld t1, 0(t2)
    li t3, 12
    bne t1, t3, fail
    la t2, s_tval
    ld t1, 0(t2)
    la t3, sx_nx_next
    addi t3, t3, -2
    bne t1, t3, fail
    // 3: one VA, two ASIDs and Bare, called right after satp writes.
    li t0, 3
    la a6, satp1
    ld a6, 0(a6)
    la a7, satp2
    ld a7, 0(a7)
    li s2, VX
    jalr s2
    li t1, 1
    bne a0, t1, fail
    csrw satp, a7
    jalr s2
    li t1, 2
    bne a0, t1, fail
    csrw satp, a6
    jalr s2
    li t1, 1
    bne a0, t1, fail
    csrw satp, x0
    jalr s2
    li t1, 3
    bne a0, t1, fail
    csrw satp, a7
    jalr s2
    li t1, 2
    bne a0, t1, fail
    csrw satp, a6
    jalr s2
    li t1, 1
    bne a0, t1, fail
    // 4: remap the executing page to an identical copy at 0x1E0000.
    li t0, 4
    jal rm_page
    li t1, 0x1E0000
    bne a0, t1, fail             // ran (and stored) through the copy
    sfence.vma
    j pass

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
    csrr t1, scause
    la t2, s_cause
    sd t1, 0(t2)
    csrr t1, stval
    la t2, s_tval
    sd t1, 0(t2)
    csrr t1, sepc
    la t2, s_epc
    sd t1, 0(t2)
    la t2, s_resume
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw sepc, t1
1:  ld t1, -8(sp)
    ld t2, -16(sp)
    csrrw sp, sscratch, sp
    sret

// ---- page-aligned blocks -------------------------------------------
    .p2align 12
fn1:                            // VX in ASID 1
    li a0, 1
    ret
    .p2align 12
fn2:                            // VX in ASID 2
    li a0, 2
    ret
fn3:                            // copied to PA VX (Bare)
    li a0, 3
    ret

// test 1: addi a5, a5, 1 straddling into the next (mapped) page
    .p2align 12
sx_ok_pg:
    .skip 4096 - 8, 0
sx_ok:
    nop
    .option rvc
    c.nop
    .4byte 0x00178793           // addi a5, a5, 1 (straddles)
    .option norvc
    ret

// test 2a: straddle into an unmapped page
    .p2align 12
sx_un_pg:
    .skip 4096 - 8, 0
sx_un:
    nop
    .option rvc
    c.nop
    .4byte 0x00178793
    .option norvc
sx_un_next:
    j fail
    .p2align 12
// test 2b: straddle into a non-executable page
sx_nx_pg:
    .skip 4096 - 8, 0
sx_nx:
    nop
    .option rvc
    c.nop
    .4byte 0x00178793
    .option norvc
sx_nx_next:
    j fail
    .p2align 12

// test 4: executes on its own page; remaps it (VA -> copy at
// 0x1E0000), SFENCEs the VA, stores through the new mapping and
// returns the PA it read back through the identity alias.
rm_page:
    la a1, rm_page
    srli a2, a1, 12
    slli a2, a2, 3
    li a3, PGL0
    add a2, a2, a3              // &PTE(rm_page)
    li a3, (0x1E0000 >> 2) | 0xEF
    sd a3, 0(a2)
    sfence.vma a1, x0
    la a4, rm_data
    li a3, 0x1E0000
    sd a3, 0(a4)                // lands in the copy's rm_data
    nop
    nop
    la a4, rm_data
    sub a4, a4, a1
    li a3, 0x1E0000
    add a4, a4, a3
    ld a0, 0(a4)                // via the identity alias of the copy
    // restore the identity mapping for this page
    srli a3, a1, 2
    ori a3, a3, 0xEF
    sd a3, 0(a2)
    sfence.vma a1, x0
    ret
    .p2align 3
rm_data:
    .quad 0

    .data
    .align 4
satp1:    .quad (8 << 60) | (1 << 44) | (PGROOT >> 12)
satp2:    .quad (8 << 60) | (2 << 44) | (PGROOT2 >> 12)
s_cause:  .quad 0
s_tval:   .quad 0
s_epc:    .quad 0
s_resume: .quad 0
stack:    .skip 1024
stack_top:
trap_stack: .skip 1024
trap_stack_top:
