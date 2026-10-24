// A/D exactness for a misaligned vector store element (#53 review
// round 2, memory lens). vsse64 whose element 1 is misaligned on a
// TLB-cold page with A=1, D=0 raises the misaligned store exception
// (6, vstart 1) and stores nothing on that page; the page-table walk
// started for the element's translation must then not have set the
// PTE's D bit (priv spec: A/D updates are exact, not speculative; a
// store that is not performed does not dirty its page). Before the
// #80 fix both FPGA_TIMING settings ran the walk with its D write-back
// while the misaligned element waited in VLS_ACC; a misaligned element
// now starts no walk (data_xlate).
//  9:  the trap (cause, stval, vstart) and memory.
//  10: L0[5].D still clear.
// t0 = test number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start

.equ EXIT,  0x10000000
.equ ROOT,  0x100000
.equ L1,    0x101000
.equ L0,    0x102000

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm
.macro CHK_S cause, tval, epc, vst
    la t1, tr
    ld t2, 0(t1)
    li t3, \cause
    bne t2, t3, fail_s
    ld t2, 8(t1)
    li t3, \tval
    bne t2, t3, fail_s
    ld t2, 16(t1)
    la t3, \epc
    bne t2, t3, fail_s
    ld t2, 24(t1)
    li t3, \vst
    bne t2, t3, fail_s
.endm
.macro RESUME label
    la t1, \label
    la t2, tr_resume
    sd t1, 0(t2)
.endm
.macro DUMP64 vr
    vsetivli x0, 8, e64, m1, tu, mu
    csrw vstart, x0
    la t1, chk
    vse64.v \vr, (t1)
.endm
.macro CHKD off, val
    la t1, chk
    ld t2, \off(t1)
    li t3, \val
    bne t2, t3, fail_s
.endm
.macro CHKW off, val
    la t1, chk
    lwu t2, \off(t1)
    li t3, \val
    bne t2, t3, fail_s
.endm
.macro MEMW addr, val
    li t1, \addr
    lwu t2, 0(t1)
    li t3, \val
    bne t2, t3, fail_s
.endm
.macro MEMD addr, val
    li t1, \addr
    ld t2, 0(t1)
    li t3, \val
    bne t2, t3, fail_s
.endm
.macro TRAPS n
    la t1, tr_count
    ld t2, 0(t1)
    sub t2, t2, s9
    li t3, \n
    bne t2, t3, fail_s
.endm
.macro MARK
    la t1, tr_count
    ld s9, 0(t1)
.endm
.macro FILL77 vr
    vsetivli x0, 8, e64, m1, tu, mu
    csrw vstart, x0
    li t1, 0x77
    vmv.v.x \vr, t1
.endm
.macro FILL77W vr
    vsetivli x0, 16, e32, m1, tu, mu
    csrw vstart, x0
    li t1, 0x77
    vmv.v.x \vr, t1
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
    li t1, (1 << 9)
    csrs mstatus, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, 0x180000
    li t2, 0x188000
1:  sd t1, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, ROOT
    li t2, ROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    PTEW ROOT, 0, L1, 0x01
    PTEW L1, 0, 0x000000, 0xCF
    PTEW L1, 1, L0, 0x01
    PTEW L0, 0, 0x180000, 0xC7  // VA 0x200000
    PTEW L0, 1, 0x181000, 0xC7  // VA 0x201000
                                // VA 0x202000 unmapped
    PTEW L0, 3, 0x183000, 0x43  // VA 0x203000 R only
    PTEW L0, 4, 0x184000, 0xC7  // VA 0x204000
    PTEW L0, 5, 0x185000, 0x47  // VA 0x205000 A=1 D=0
    li t1, 0xB0F2
    csrw medeleg, t1
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
    // 9: store, element 1 misaligned on a cold D=0 page.
    li t0, 9
    MARK
    vsetivli x0, 2, e64, m1, tu, mu
    csrw vstart, x0
    vid.v v8
    vadd.vi v8, v8, 7
    sfence.vma
    li a1, 0x204FF8
    li a2, 0x0FFC               // element 1: 0x205FF4
    RESUME after9
f9: vsse64.v v8, (a1), a2
    j fail_s
after9:
    CHK_S 6, 0x205FF4, f9, 1
    TRAPS 1
    MEMD 0x184FF8, 7
    MEMD 0x185FF0, 0x185FF0
    MEMD 0x185FF8, 0x185FF8
    li t1, L0 + 5 * 8
    ld t2, 0(t1)
    la t1, res
    sd t2, 0(t1)                // L0[5] after the misaligned store
    li t1, 0x205FF0
    li t2, 0x5A
    sd t2, 0(t1)
    MEMD 0x185FF0, 0x5A
    MEMD 0x205FF0, 0x5A
    // 10: the misaligned store (test 9) must not have set D on its
    //     page: the A/D update is exact (priv spec, Svadu/4.3.2).
    li t0, 10
    la t1, res
    ld t2, 0(t1)
    andi t2, t2, 0x80
    bnez t2, fail_s

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

handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    sd t3, 16(sp)
    csrr t1, mcause
    li t2, 9
    bne t1, t2, 3f
    la t2, resume_addr
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw mepc, t1
    li t1, (3 << 11)
    csrs mstatus, t1
    j 2f
3:  la t2, tr
    sd t1, 0(t2)
    csrr t3, mtval
    sd t3, 8(t2)
    csrr t3, mepc
    sd t3, 16(t2)
    csrr t3, vstart
    sd t3, 24(t2)
    la t2, tr_count
    ld t3, 0(t2)
    addi t3, t3, 1
    sd t3, 0(t2)
    la t2, tr_resume
    ld t1, 0(t2)
    beqz t1, 4f
    sd x0, 0(t2)
    csrw mepc, t1
    j 2f
4:  csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    j 2f
1:  la t1, m_info
    csrr t2, mcause
    sd t2, 0(t1)
    csrr t2, mepc
    sd t2, 8(t1)
    csrr t2, mtval
    sd t2, 16(t1)
    sd t0, 24(t1)
    li t1, EXIT
    li t2, 99
    sd t2, 0(t1)
5:  j 5b
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    ld t3, 16(sp)
    csrrw sp, mscratch, sp
    mret

handler_s:
    csrrw sp, sscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    sd t3, 16(sp)
    la t1, tr
    csrr t2, scause
    sd t2, 0(t1)
    csrr t3, stval
    sd t3, 8(t1)
    csrr t3, sepc
    sd t3, 16(t1)
    csrr t3, vstart
    sd t3, 24(t1)
    la t1, tr_count
    ld t2, 0(t1)
    addi t2, t2, 1
    sd t2, 0(t1)
    la t2, tr_resume
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw sepc, t1
    j 2f
1:  csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    ld t3, 16(sp)
    csrrw sp, sscratch, sp
    sret

    .data
    .align 3
idx6:        .quad 0x10, 0x1010, 0x1006, 0x2000
tr:          .quad 0, 0, 0, 0
res:         .quad 0, 0, 0, 0
resume_addr: .quad 0
m_info:      .quad 0, 0, 0, 0
tr_resume:   .quad 0
tr_count:    .quad 0
    .align 6
chk:         .skip 64
    .align 4
main_stack:  .skip 2048
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
s_trap_stack: .skip 1024
s_trap_stack_top:
