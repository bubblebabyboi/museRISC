// Misaligned vector elements under Sv39 (#53 review round 3, memory
// lens): fault priority and vstart when the misaligned element's
// translation is a TLB hit, a TLB miss or an A/D re-walk. With
// FPGA_TIMING a misaligned element in VLS_ACC holds the sequencer
// until its registered translation resolves (g_vls_end), where main
// restarts the sequence at element 0. Sigil raises the misaligned
// exception for any misaligned element (cause 4/6, above the
// element's page/access faults); whole-register transfers move bytes
// and never fault as misaligned. S-mode, faults delegated to S.
//  1: vle16 at an odd VA, TLB warm, then cold: 4, vstart 0.
//  2: vlse32, element 1 misaligned on a mapped cold page: 4, vstart 1,
//     element 0 loaded.
//  5: vle32ff at a misaligned base: element 0 traps (4), vl kept.
//  6: vluxei64 (SEW 32), element 2 misaligned: 4, vstart 2.
//  7: vlseg2e32 at base + 2: 4, vstart 0, nothing written.
//  8: vl1re32 at base + 2 across a page: no fault, bytes loaded.
//  9: vsse64, element 1 misaligned on a cold D=0 page: 6, vstart 1;
//     then an aligned store there works.
// (mem53r_vmisal_fault_directed: misaligned elements whose translation
// faults; mem53r_vmisal_dbit_directed: the D bit after test 9.)
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
    // 1: element 0 misaligned, TLB warm then cold.
    li t0, 1
    MARK
    li a1, 0x200000
    ld a2, 0(a1)                // warm
    vsetivli x0, 4, e16, m1, tu, mu
    li a1, 0x200001
    RESUME after1a
f1a: vle16.v v8, (a1)
    j fail_s
after1a:
    CHK_S 4, 0x200001, f1a, 0
    csrw vstart, x0
    sfence.vma
    RESUME after1b
f1b: vle16.v v8, (a1)
    j fail_s
after1b:
    CHK_S 4, 0x200001, f1b, 0
    TRAPS 2

    // 2: element 1 misaligned on a mapped, TLB-cold page.
    li t0, 2
    MARK
    FILL77W v8
    vsetivli x0, 4, e32, m1, tu, mu
    sfence.vma
    li a1, 0x200000
    li a2, 0x1002
    RESUME after2
f2: vlse32.v v8, (a1), a2
    j fail_s
after2:
    CHK_S 4, 0x201002, f2, 1
    TRAPS 1
    DUMP64 v8
    CHKW 0, 0x180000
    CHKW 4, 0x77

    // 5: fault-only-first at a misaligned base (EEW 32: every
    //    element shares the misalignment): element 0 traps, vl kept.
    li t0, 5
    MARK
    vsetivli x0, 8, e32, m1, tu, mu
    sfence.vma
    li a1, 0x200002
    RESUME after5
f5: vle32ff.v v8, (a1)
    j fail_s
after5:
    CHK_S 4, 0x200002, f5, 0
    csrr a3, vl
    li a2, 8
    bne a3, a2, fail_s
    TRAPS 1

    // 6: indexed, SEW 32, element 2 misaligned; element 3 on an
    //    unmapped page.
    li t0, 6
    MARK
    FILL77W v8
    vsetivli x0, 4, e64, m1, tu, mu
    la t1, idx6
    vle64.v v4, (t1)
    vsetivli x0, 4, e32, m1, tu, mu
    sfence.vma
    li a1, 0x200000
    RESUME after6
f6: vluxei64.v v8, (a1), v4
    j fail_s
after6:
    CHK_S 4, 0x201006, f6, 2
    TRAPS 1
    DUMP64 v8
    CHKW 0, 0x180010
    CHKW 4, 0x181010
    CHKW 8, 0x77

    // 7: segment load at base + 2: element 0 field 0.
    li t0, 7
    MARK
    FILL77 v8
    FILL77 v9
    vsetivli x0, 2, e32, m1, tu, mu
    li a1, 0x204002
    RESUME after7
f7: vlseg2e32.v v8, (a1)
    j fail_s
after7:
    CHK_S 4, 0x204002, f7, 0
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x77
    DUMP64 v9
    CHKD 0, 0x77

    // 8: whole-register load at base + 2: bytes, no fault.
    li t0, 8
    MARK
    FILL77 v8
    csrw vstart, x0
    sfence.vma
    li a1, 0x200FE2             // crosses into VA 0x201000
    vl1re32.v v8, (a1)
    TRAPS 0
    DUMP64 v8
    CHKD 0, 0xfe8000000000018
    CHKD 56, 0x1020000000000018

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
