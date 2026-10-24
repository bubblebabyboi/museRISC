// PMP checks of vector element accesses (#53 review round 3, memory
// lens): with FPGA_TIMING the element PA comes from the registered
// D-TLB lookup taken in VLS_RD/RW and the verdict from the parallel
// PMP form (pmp_check_par). Regions are whole-element aligned (no
// partial matches), so the verdicts are the same before and after
// the #78 partial-match rule. PMP map (S/U unless locked):
//   0/1 TOR [0x181010, 0x181040) no access
//   2   NA4  0x182008             no access
//   3   NAPOT 64B 0x183040        R only
//   4   NAPOT 4K  0x184000        X only
//   5   TOR [pmpaddr4 (a NAPOT encoding: 0x1847FC), 0x185100) R X
//   6   (test 15) locked NAPOT 64B 0x186000 R only
//   15  NAPOT everything RWX
// Sigil does not delegate access faults (medeleg bits 5/7 are
// read-only 0): they trap to M, which logs them like S does.
// S-mode, Bare (1-13): unit-stride, strided (negative stride),
// indexed, segment, whole-register, fault-only-first (trim, element
// 0), masked elements, byte stores: cause 5/7, stval, sepc, vstart,
// elements before the fault written, none after.
// S-mode, Sv39 (16-19): the same verdicts on translated elements,
// with TLB misses inside the sequence (SFENCE.VMA before).
// M-mode with MPRV=1, MPP=S (14): pmpcfg0/pmpaddr1 written directly
// before a vector load that the write allows or denies.
// M-mode (15): a locked R-only entry denies an M vector store at its
// element; M vector loads of it pass; the locked entry ignores writes.
// t0 = test number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start

.equ EXIT,  0x10000000
.equ ROOT,  0x100000
.equ L1,    0x101000
.equ L0,    0x102000
.equ CFG0,  0x0D1C19100800      // cfg1 TOR -, cfg2 NA4 -, cfg3 NAPOT R, cfg4 NAPOT X, cfg5 TOR RX
.equ CFG0A, 0x0D1C19100900      // the same with cfg1 TOR R
.equ MPRV,  (1 << 17)

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm
// Last S trap: cause, tval (constant), epc (label), vstart.
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
.macro CHK_M cause, tval, epc, vst
    la t1, tr
    ld t2, 0(t1)
    li t3, \cause
    bne t2, t3, fail
    ld t2, 8(t1)
    li t3, \tval
    bne t2, t3, fail
    ld t2, 16(t1)
    la t3, \epc
    bne t2, t3, fail
    ld t2, 24(t1)
    li t3, \vst
    bne t2, t3, fail
.endm
.macro RESUME label
    la t1, \label
    la t2, tr_resume
    sd t1, 0(t2)
.endm
.macro M_RESUME label
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
.macro DUMP32 vr
    vsetivli x0, 16, e32, m1, tu, mu
    csrw vstart, x0
    la t1, chk
    vse32.v \vr, (t1)
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
.macro CHKMD off, val            // M-mode variant (fails to `fail`)
    la t1, chk
    ld t2, \off(t1)
    li t3, \val
    bne t2, t3, fail
.endm
.macro MEMD addr, val            // 64-bit memory word check (S)
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
.macro MTRAPS n
    la t1, tr_count
    ld t2, 0(t1)
    sub t2, t2, s9
    li t3, \n
    bne t2, t3, fail
.endm
.macro MMARK
    la t1, tr_count
    ld s9, 0(t1)
.endm
.macro FILL77 vr
    vsetivli x0, 8, e64, m1, tu, mu
    csrw vstart, x0
    li t1, 0x77
    vmv.v.x \vr, t1
.endm
.macro MPRV_S
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, MPRV | (1 << 11)
    csrs mstatus, t1
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
    li t1, (1 << 9)             // VS = Initial
    csrs mstatus, t1
    // PMP
    li t1, 0x181010 >> 2
    csrw pmpaddr0, t1
    li t1, 0x181040 >> 2
    csrw pmpaddr1, t1
    li t1, 0x182008 >> 2
    csrw pmpaddr2, t1
    li t1, 0x60C17
    csrw pmpaddr3, t1
    li t1, 0x611FF
    csrw pmpaddr4, t1
    li t1, 0x185100 >> 2
    csrw pmpaddr5, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, CFG0
    csrw pmpcfg0, t1
    // Data: every doubleword of PA 0x180000..0x187000 holds its address.
    li t1, 0x180000
    li t2, 0x187000
1:  sd t1, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Sv39 tables (used from test 16): VA 0..2M identity (2M leaf);
    // VA 0x200000 -> 0x181000, 0x201000 -> 0x183000,
    // 0x202000 -> 0x184000, 0x203000 -> 0x185000 (all RW, A, D).
    li t1, ROOT
    li t2, ROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    PTEW ROOT, 0, L1, 0x01
    PTEW L1, 0, 0x000000, 0xCF
    PTEW L1, 1, L0, 0x01
    PTEW L0, 0, 0x181000, 0xC7
    PTEW L0, 1, 0x183000, 0xC7
    PTEW L0, 2, 0x184000, 0xC7
    PTEW L0, 3, 0x185000, 0xC7
    li t1, 0xB0F2               // access, page, misaligned faults to S
    csrw medeleg, t1
    csrw satp, x0
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

s_main:
    // 1: unit-stride load into the TOR no-access region: element 2.
    li t0, 1
    MARK
    FILL77 v8
    RESUME after1
    li a1, 0x181000
f1: vle64.v v8, (a1)
    j fail_s
after1:
    CHK_S 5, 0x181010, f1, 2
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x181000
    CHKD 8, 0x181008
    CHKD 16, 0x77
    CHKD 56, 0x77

    // 2: unit-stride store into the R-only NAPOT: element 2; loads
    //    of the same NAPOT pass.
    li t0, 2
    MARK
    vsetivli x0, 4, e64, m1, tu, mu
    vid.v v8
    vadd.vi v8, v8, 10
    RESUME after2
    li a1, 0x183030
f2: vse64.v v8, (a1)
    j fail_s
after2:
    CHK_S 7, 0x183040, f2, 2
    TRAPS 1
    MEMD 0x183030, 10
    MEMD 0x183038, 11
    MEMD 0x183040, 0x183040
    MEMD 0x183048, 0x183048
    csrw vstart, x0
    vsetivli x0, 8, e64, m1, tu, mu
    li a1, 0x183040
    vle64.v v8, (a1)
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x183040
    CHKD 56, 0x183078

    // 3: EEW=32 unit-stride load over the NA4 word: element 2.
    li t0, 3
    MARK
    vsetivli x0, 16, e32, m1, tu, mu
    csrw vstart, x0
    li a2, 0x77
    vmv.v.x v8, a2
    vsetivli x0, 4, e32, m1, tu, mu
    RESUME after3
    li a1, 0x182000
f3: vle32.v v8, (a1)
    j fail_s
after3:
    CHK_S 5, 0x182008, f3, 2
    TRAPS 1
    DUMP32 v8
    CHKW 0, 0x182000
    CHKW 4, 0
    CHKW 8, 0x77
    CHKW 12, 0x77
    // the word after the NA4 word loads
    vsetivli x0, 1, e32, m1, tu, mu
    li a1, 0x18200C
    vle32.v v8, (a1)
    TRAPS 1

    // 4: negative-stride load leaving TOR5 (R) into NAPOT4 (X only).
    li t0, 4
    MARK
    FILL77 v8
    vsetivli x0, 4, e64, m1, tu, mu
    RESUME after4
    li a1, 0x185010
    li a2, -8
f4: vlse64.v v8, (a1), a2
    j fail_s
after4:
    CHK_S 5, 0x184FF8, f4, 3
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x185010
    CHKD 8, 0x185008
    CHKD 16, 0x185000
    CHKD 24, 0x77

    // 5: indexed load, element 2 indexes NAPOT4.
    li t0, 5
    MARK
    FILL77 v8
    vsetivli x0, 4, e64, m1, tu, mu
    la a1, idx5
    vle64.v v4, (a1)
    RESUME after5
    li a1, 0x185000
f5: vluxei64.v v8, (a1), v4
    j fail_s
after5:
    CHK_S 5, 0x184010, f5, 2
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x185000
    CHKD 8, 0x185018
    CHKD 16, 0x77
    CHKD 24, 0x77

    // 6: negative-stride EEW=32 store crossing TOR5's upper bound
    //    downward: 0x185104, 0x185100 pass, 0x1850FC (no W) faults.
    li t0, 6
    MARK
    vsetivli x0, 4, e32, m1, tu, mu
    vid.v v8
    li a2, 0xA0
    vadd.vx v8, v8, a2
    RESUME after6
    li a1, 0x185104
    li a2, -4
f6: vsse32.v v8, (a1), a2
    j fail_s
after6:
    CHK_S 7, 0x1850FC, f6, 2
    TRAPS 1
    li a1, 0x185100
    lwu a2, 4(a1)
    li a3, 0xA0
    bne a2, a3, fail_s
    lwu a2, 0(a1)
    li a3, 0xA1
    bne a2, a3, fail_s
    lwu a2, -4(a1)
    bnez a2, fail_s
    lwu a2, -8(a1)
    li a3, 0x1850F8
    bne a2, a3, fail_s

    // 7: segment load, element 1 field 0 in the TOR region.
    li t0, 7
    MARK
    FILL77 v8
    FILL77 v9
    vsetivli x0, 2, e64, m1, tu, mu
    RESUME after7
    li a1, 0x181000
f7: vlseg2e64.v v8, (a1)
    j fail_s
after7:
    CHK_S 5, 0x181010, f7, 1
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x181000
    CHKD 8, 0x77
    DUMP64 v9
    CHKD 0, 0x181008
    CHKD 8, 0x77

    // 8: whole-register vl2re64: element 9 is the first in the region.
    li t0, 8
    MARK
    FILL77 v8
    FILL77 v9
    csrw vstart, x0
    RESUME after8
    li a1, 0x180FC8
f8: vl2re64.v v8, (a1)
    j fail_s
after8:
    CHK_S 5, 0x181010, f8, 9
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x180FC8
    CHKD 56, 0x181000
    DUMP64 v9
    CHKD 0, 0x181008
    CHKD 8, 0x77

    // 9: fault-only-first trims vl at element 2, no trap.
    li t0, 9
    MARK
    FILL77 v8
    vsetivli x0, 8, e64, m1, tu, mu
    li a1, 0x181000
    vle64ff.v v8, (a1)
    csrr a3, vl
    li a2, 2
    bne a3, a2, fail_s
    TRAPS 0
    DUMP64 v8
    CHKD 0, 0x181000
    CHKD 8, 0x181008
    CHKD 16, 0x77

    // 10: fault-only-first, element 0 faults: trap, vl kept.
    li t0, 10
    MARK
    vsetivli x0, 8, e64, m1, tu, mu
    RESUME after10
    li a1, 0x181010
f10: vle64ff.v v8, (a1)
    j fail_s
after10:
    CHK_S 5, 0x181010, f10, 0
    TRAPS 1
    csrr a3, vl
    li a2, 8
    bne a3, a2, fail_s

    // 11: masked-off elements in the region do not fault; an active
    //     one (element 3) does.
    li t0, 11
    MARK
    FILL77 v8
    li a2, 0x03
    vmv.s.x v0, a2
    li a1, 0x181000
    vle64.v v8, (a1), v0.t
    TRAPS 0
    DUMP64 v8
    CHKD 0, 0x181000
    CHKD 8, 0x181008
    CHKD 16, 0x77
    CHKD 24, 0x77
    vsetivli x0, 8, e64, m1, tu, mu
    li a2, 0x0B
    vmv.s.x v0, a2
    RESUME after11
f11: vle64.v v8, (a1), v0.t
    j fail_s
after11:
    CHK_S 5, 0x181018, f11, 3
    TRAPS 1

    // 13: byte stores, stride -1, into TOR5 (no W) at element 3.
    li t0, 13
    MARK
    vsetivli x0, 4, e8, m1, tu, mu
    csrw vstart, x0
    vid.v v8
    li a2, 0x50
    vadd.vx v8, v8, a2
    RESUME after13
    li a1, 0x185102
    li a2, -1
f13: vsse8.v v8, (a1), a2
    j fail_s
after13:
    CHK_S 7, 0x1850FF, f13, 3
    TRAPS 1
    li a1, 0x185100
    lbu a2, 2(a1)
    li a3, 0x50
    bne a2, a3, fail_s
    lbu a2, 1(a1)
    li a3, 0x51
    bne a2, a3, fail_s
    lbu a2, 0(a1)
    li a3, 0x52
    bne a2, a3, fail_s
    lbu a2, -1(a1)
    bnez a2, fail_s

    // ---- Sv39 ----
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, ROOT >> 12
    csrw satp, t1
    sfence.vma
    // 16: translated unit-stride load: element 2 (PA 0x181010).
    li t0, 16
    MARK
    FILL77 v8
    RESUME after16
    li a1, 0x200000
f16: vle64.v v8, (a1)
    j fail_s
after16:
    CHK_S 5, 0x200010, f16, 2
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x181000
    CHKD 8, 0x181008
    CHKD 16, 0x77

    // 17: translated store into the R-only NAPOT: element 2.
    li t0, 17
    MARK
    vsetivli x0, 4, e64, m1, tu, mu
    csrw vstart, x0
    vid.v v8
    vadd.vi v8, v8, 15
    vadd.vi v8, v8, 5
    RESUME after17
    li a1, 0x201030
f17: vse64.v v8, (a1)
    j fail_s
after17:
    CHK_S 7, 0x201040, f17, 2
    TRAPS 1
    MEMD 0x201030, 20
    MEMD 0x201038, 21
    MEMD 0x201040, 0x183040

    // 18: TLB-cold page crossing: element 2 is the first element on
    //     VA 0x202000 (PA 0x184000, X only).
    li t0, 18
    MARK
    FILL77 v8
    vsetivli x0, 4, e64, m1, tu, mu
    sfence.vma
    RESUME after18
    li a1, 0x201FF0
f18: vle64.v v8, (a1)
    j fail_s
after18:
    CHK_S 5, 0x202000, f18, 2
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x183FF0
    CHKD 8, 0x183FF8
    CHKD 16, 0x77

    // 19: TLB-cold indexed load over three pages: element 2 lands on
    //     VA 0x202020 (PA 0x184020, X only).
    li t0, 19
    MARK
    FILL77 v8
    vsetivli x0, 4, e64, m1, tu, mu
    la a1, idx19
    vle64.v v4, (a1)
    sfence.vma
    RESUME after19
    li a1, 0x203000
f19: vluxei64.v v8, (a1), v4
    j fail_s
after19:
    CHK_S 5, 0x202020, f19, 2
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x185010
    CHKD 8, 0x183FF8
    CHKD 16, 0x77

    // to M for tests 14-15
    la a1, m_part
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
    j fail_s

m_part:
    // 14: M with MPRV=1, MPP=S under Sv39 (VA 0x200000 -> 0x181000).
    li t0, 14
    MMARK
    MPRV_S
    vsetivli x0, 8, e64, m1, tu, mu
    csrw vstart, x0
    li a2, 0x77
    vmv.v.x v8, a2
    // 14a: cfg1 TOR gains R right before the load: all 8 load.
    li a3, CFG0A
    li a1, 0x200000
    csrw pmpcfg0, a3
    vle64.v v8, (a1)
    MTRAPS 0
    la t1, chk                  // (MPRV store: identity 2M page)
    vse64.v v8, (t1)
    CHKMD 0, 0x181000
    CHKMD 56, 0x181038
    // 14b: R removed again right before the load: element 2.
    li t0, 141
    li a2, 0x77
    vmv.v.x v8, a2
    li a3, CFG0
    M_RESUME after14b
    csrw pmpcfg0, a3
f14b: vle64.v v8, (a1)
    j fail
after14b:
    MPRV_S                      // (the trap's MRET left MPP = U)
    CHK_M 5, 0x200010, f14b, 2
    MTRAPS 1
    // 14c: pmpaddr1 lowered right before: [0x181010, 0x181020) only,
    //      so VA 0x200020.. (PA 0x181020..) loads.
    li t0, 142
    MMARK
    csrw vstart, x0
    li a3, 0x181020 >> 2
    li a1, 0x200020
    csrw pmpaddr1, a3
    vle64.v v8, (a1)
    MTRAPS 0
    // 14d: pmpaddr1 restored right before: element 0 faults.
    li t0, 143
    li a3, 0x181040 >> 2
    M_RESUME after14d
    csrw pmpaddr1, a3
f14d: vle64.v v8, (a1)
    j fail
after14d:
    li t1, MPRV
    csrc mstatus, t1
    CHK_M 5, 0x200020, f14d, 0
    MTRAPS 1
    csrw vstart, x0
    // check 14a's loaded values (M, Bare view of chk)
    li t0, 144
    vsetivli x0, 8, e64, m1, tu, mu
    li a1, 0x181000
    vle64.v v8, (a1)
    la t1, chk
    vse64.v v8, (t1)
    CHKMD 0, 0x181000
    CHKMD 56, 0x181038

    // 15: locked entry 6 (NAPOT 64B 0x186000, R only) denies an M
    //     vector store at its first element; M loads of it pass.
    li t0, 15
    MMARK
    li a3, 0x61807
    csrw pmpaddr6, a3
    li a3, CFG0 | (0x99 << 48)
    csrw pmpcfg0, a3
    vsetivli x0, 4, e64, m1, tu, mu
    vid.v v8
    li a1, 0x185FF0
    M_RESUME after15
f15: vse64.v v8, (a1)
    j fail
after15:
    CHK_M 7, 0x186000, f15, 2
    MTRAPS 1
    li a1, 0x185FF0
    ld a2, 0(a1)
    bnez a2, fail
    ld a2, 8(a1)
    li a3, 1
    bne a2, a3, fail
    ld a2, 16(a1)
    li a3, 0x186000
    bne a2, a3, fail
    csrw vstart, x0
    vsetivli x0, 8, e64, m1, tu, mu
    li a1, 0x186000
    vle64.v v8, (a1)
    MTRAPS 1
    la t1, chk
    vse64.v v8, (t1)
    CHKMD 56, 0x186038
    // the locked address ignores writes
    li a3, 0
    csrw pmpaddr6, a3
    csrr a4, pmpaddr6
    li a3, 0x61807
    bne a4, a3, fail
    j pass

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
    li t1, MPRV                 // (M part: the exit store untranslated)
    csrc mstatus, t1
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

// M: an ECALL from S with resume_addr set continues in M there
// (else fail 99). Any other trap (S access faults, which Sigil does
// not delegate, and M-mode traps) is logged in tr (cause, tval, epc,
// vstart), counted, and resumes at tr_resume or skips the
// instruction, in the mode it came from.
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
    li t1, MPRV
    csrc mstatus, t1
    li t1, EXIT
    li t2, 99
    sd t2, 0(t1)
5:  j 5b
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    ld t3, 16(sp)
    csrrw sp, mscratch, sp
    mret

// S: log (cause, tval, epc, vstart), count; resume at s_resume or
// skip the instruction.
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
idx5:        .quad 0, 0x18, -0xFF0, 8
idx19:       .quad 0x10, -0x1008, -0xFE0, 0x18
tr:          .quad 0, 0, 0, 0
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
