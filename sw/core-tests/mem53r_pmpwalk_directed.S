// PMP on the page-table walker's implicit accesses (#53 review round
// 3, memory lens). With FPGA_TIMING a data walk starts from the
// registered D-TLB lookup, an implicit access PMP denial completes
// the walk at once (walk_skip, which the port-payload select does not
// gate) and the access replays its lookup to take the recorded fault;
// fetches take theirs from the registered I-port lookup. Sv39, S-mode:
//   L1[2] -> L0X at 0x10F000: PMP no access, so every PTE read of
//            VA 0x400000.. is denied (access fault of the original
//            access type, tval = VA);
//   L1[3] -> L0R at 0x10E000: PMP R only, so PTE reads pass and A/D
//            write-backs are denied (access fault, nothing written);
//   L0[2]: leaf PA 0x18F000 (PMP no access).
//  1-4: ld / sd / amoadd.d / lr.d / sc.d through L0X: 5,7,7,5,7.
//  5-7: vle64 / vle64ff / vse64 whose element 2 is the first on L0X:
//       5 vstart 2 / vl trimmed to 2 / 7 vstart 2.
//  8:   leaf PA denied: 5; a no-R leaf on that PA: page fault 13 first.
//  9:   A/D through L0R: load of an A=1 D=0 page passes and the store
//       faults 7; load of an A=0 page faults 5; vector load reaching
//       the A=0 page at element 2; vector store reaching a D=0 page
//       at element 2.
//  10:  fetch from an A=0 code page under L0R (A write denied): 1;
//       the same code through an A=1 PTE runs; fetch through L0X: 1.
//  11:  precise: hit load, denied-walk load, younger load: the
//       younger one does not run, the older one did.
//  12:  M with MPRV=1, MPP=S: data walk through L0X faults 5 in M;
//       pmpcfg0 then lets L0X be read (SFENCE.VMA) and the same load
//       passes right after; denied again and it faults again.
// Sigil does not delegate access faults (medeleg 5/7/1 read-only 0):
// they trap to M, which logs them; page faults go to S.
// t0 = test number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start

.equ EXIT,  0x10000000
.equ ROOT,  0x100000
.equ L1,    0x101000
.equ L0,    0x102000
.equ L0R,   0x10E000
.equ L0X,   0x10F000
.equ MPRV,  (1 << 17)
// pmpaddr: NAPOT 4K = (base >> 2) | 0x1FF
.equ PA_L0X, ((L0X >> 2) | 0x1FF)
.equ PA_L0R, ((L0R >> 2) | 0x1FF)
.equ PA_DNY, ((0x18F000 >> 2) | 0x1FF)
.equ CFG0,  0x181918            // e0 NAPOT -, e1 NAPOT R, e2 NAPOT -
.equ CFG0R, 0x181919            // e0 NAPOT R

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm
.macro PTEL tbl, idx, lbl, flags   // leaf for the PA of a label
    la t1, \lbl
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
.macro CHK_SV cause, tval, epcv, vst   // epc as a constant
    la t1, tr
    ld t2, 0(t1)
    li t3, \cause
    bne t2, t3, fail_s
    ld t2, 8(t1)
    li t3, \tval
    bne t2, t3, fail_s
    ld t2, 16(t1)
    li t3, \epcv
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
.macro MTRAPS n
    la t1, tr_count
    ld t2, 0(t1)
    sub t2, t2, s9
    li t3, \n
    bne t2, t3, fail
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
    // Data: every doubleword of PA 0x180000..0x190000 holds its address.
    li t1, 0x180000
    li t2, 0x190000
1:  sd t1, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Tables: clear ROOT, L1, L0, L0R, L0X.
    li t1, ROOT
    li t2, ROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, L0R
    li t2, L0X + 0x1000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    PTEW ROOT, 0, L1, 0x01
    PTEW L1, 0, 0x000000, 0xCF  // VA 0..2M identity, RWX A D
    PTEW L1, 1, L0, 0x01
    PTEW L1, 2, L0X, 0x01
    PTEW L1, 3, L0R, 0x01
    PTEW L0, 0, 0x180000, 0xC7
    PTEW L0, 1, 0x181000, 0xC7
    PTEW L0, 2, 0x18F000, 0xC7  // leaf PA denied
    PTEW L0, 3, 0x18F000, 0xC9  // X only, same PA
    PTEW L0, 511, 0x186000, 0xC7
    PTEW L0X, 0, 0x182000, 0xC7
    PTEL L0X, 1, fpage, 0x4B
    PTEW L0R, 0, 0x183000, 0x47 // A=1 D=0
    PTEW L0R, 1, 0x184000, 0x07 // A=0
    PTEW L0R, 2, 0x185000, 0xC7
    PTEL L0R, 3, fpage, 0x0B    // X R, A=0
    PTEL L0R, 4, fpage, 0x4B    // X R, A=1
    PTEW L0R, 5, 0x186000, 0xC7
    PTEW L0R, 6, 0x187000, 0x47 // A=1 D=0
    // PMP
    li t1, PA_L0X
    csrw pmpaddr0, t1
    li t1, PA_L0R
    csrw pmpaddr1, t1
    li t1, PA_DNY
    csrw pmpaddr2, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, CFG0
    csrw pmpcfg0, t1
    li t1, 0xB0F2               // page faults (access faults: WARL 0)
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
    // 1: scalar load and store through L0X.
    li t0, 1
    MARK
    li a1, 0x400000
    li a2, 0x5555
    RESUME after1a
f1a: ld a2, 0(a1)
    j fail_s
after1a:
    CHK_S 5, 0x400000, f1a, 0
    li a3, 0x5555
    bne a2, a3, fail_s
    RESUME after1b
    li a1, 0x400008
f1b: sd a3, 0(a1)
    j fail_s
after1b:
    CHK_S 7, 0x400008, f1b, 0
    TRAPS 2
    MEMD 0x182008, 0x182008
    // 2: AMO.
    li t0, 2
    li a1, 0x400010
    li a2, 0x5555
    RESUME after2
f2: amoadd.d a2, a3, (a1)
    j fail_s
after2:
    CHK_S 7, 0x400010, f2, 0
    li a3, 0x5555
    bne a2, a3, fail_s
    MEMD 0x182010, 0x182010
    // 3: LR, SC.
    li t0, 3
    li a1, 0x400018
    RESUME after3a
f3a: lr.d a2, (a1)
    j fail_s
after3a:
    CHK_S 5, 0x400018, f3a, 0
    RESUME after3b
f3b: sc.d a2, a3, (a1)
    j fail_s
after3b:
    CHK_S 7, 0x400018, f3b, 0
    li a3, 0x5555
    bne a2, a3, fail_s
    TRAPS 5
    MEMD 0x182018, 0x182018

    // 5: vector load: element 2 is the first on L0X.
    li t0, 5
    MARK
    FILL77 v8
    vsetivli x0, 4, e64, m1, tu, mu
    li a1, 0x3FFFF0
    RESUME after5
f5: vle64.v v8, (a1)
    j fail_s
after5:
    CHK_S 5, 0x400000, f5, 2
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x186FF0
    CHKD 8, 0x186FF8
    CHKD 16, 0x77
    // 6: fault-only-first: trimmed to 2, no trap.
    li t0, 6
    MARK
    FILL77 v8
    vsetivli x0, 4, e64, m1, tu, mu
    vle64ff.v v8, (a1)
    csrr a3, vl
    li a2, 2
    bne a3, a2, fail_s
    TRAPS 0
    DUMP64 v8
    CHKD 8, 0x186FF8
    CHKD 16, 0x77
    // 7: vector store: element 2.
    li t0, 7
    MARK
    vsetivli x0, 4, e64, m1, tu, mu
    vid.v v8
    vadd.vi v8, v8, 1
    RESUME after7
f7: vse64.v v8, (a1)
    j fail_s
after7:
    CHK_S 7, 0x400000, f7, 2
    TRAPS 1
    csrw vstart, x0
    MEMD 0x186FF0, 1
    MEMD 0x186FF8, 2
    MEMD 0x182000, 0x182000

    // 8: leaf PA denied: access fault; X-only leaf there: page fault.
    li t0, 8
    MARK
    li a1, 0x202000
    RESUME after8a
f8a: ld a2, 0(a1)
    j fail_s
after8a:
    CHK_S 5, 0x202000, f8a, 0
    li a1, 0x203000
    RESUME after8b
f8b: ld a2, 0(a1)
    j fail_s
after8b:
    CHK_S 13, 0x203000, f8b, 0
    TRAPS 2

    // 9: A/D write-backs denied (L0R is read-only to the walker).
    li t0, 9
    MARK
    li a1, 0x600000
    ld a2, 8(a1)                // A=1: no write-back
    li a3, 0x183008
    bne a2, a3, fail_s
    li a3, 0x99
    RESUME after9a
f9a: sd a3, 8(a1)               // D=0: D write-back denied
    j fail_s
after9a:
    CHK_S 7, 0x600008, f9a, 0
    li a1, 0x601000
    RESUME after9b
f9b: ld a2, 0(a1)               // A=0: A write-back denied
    j fail_s
after9b:
    CHK_S 5, 0x601000, f9b, 0
    li a1, 0x602000             // A=1 D=1: both pass
    ld a2, 16(a1)
    li a3, 0x185010
    bne a2, a3, fail_s
    li a3, 0x66
    sd a3, 16(a1)
    ld a2, 16(a1)
    bne a2, a3, fail_s
    TRAPS 2
    MEMD 0x183008, 0x183008
    li a1, L0R                  // PTEs unchanged
    ld a2, 0(a1)
    andi a2, a2, 0xFF
    li a3, 0x47
    bne a2, a3, fail_s
    ld a2, 8(a1)
    andi a2, a2, 0xFF
    li a3, 0x07
    bne a2, a3, fail_s
    // 9c: vector load from the A=1 D=0 page into the A=0 page.
    MARK
    FILL77 v8
    vsetivli x0, 4, e64, m1, tu, mu
    li a1, 0x600FF0
    RESUME after9c
f9c: vle64.v v8, (a1)
    j fail_s
after9c:
    CHK_S 5, 0x601000, f9c, 2
    DUMP64 v8
    CHKD 0, 0x183FF0
    CHKD 8, 0x183FF8
    CHKD 16, 0x77
    // 9d: vector store from an A/D page into a D=0 page.
    vsetivli x0, 4, e64, m1, tu, mu
    csrw vstart, x0
    vid.v v8
    vadd.vi v8, v8, 3
    li a1, 0x605FF0
    RESUME after9d
f9d: vse64.v v8, (a1)
    j fail_s
after9d:
    CHK_S 7, 0x606000, f9d, 2
    TRAPS 2
    csrw vstart, x0
    MEMD 0x186FF0, 3
    MEMD 0x186FF8, 4
    MEMD 0x187000, 0x187000

    // 10: fetches.
    li t0, 10
    MARK
    li a5, 0
    li a6, 0x604000             // A=1: runs
    jalr ra, 0(a6)
    li a3, 0x1234
    bne a5, a3, fail_s
    li a5, 0
    RESUME after10a
    li a6, 0x603000             // A=0, A write denied
    jalr ra, 0(a6)
    j fail_s
after10a:
    CHK_SV 1, 0x603000, 0x603000, 0
    bnez a5, fail_s
    RESUME after10b
    li a6, 0x401000             // PTE read denied
    jalr ra, 0(a6)
    j fail_s
after10b:
    CHK_SV 1, 0x401000, 0x401000, 0
    bnez a5, fail_s
    TRAPS 2

    // 11: precise: older hit load done, younger load not run.
    li t0, 11
    MARK
    li a1, 0x200008
    ld a2, 0(a1)                // warm
    li a4, 0x400020
    li a3, 0x5555
    RESUME after11
    ld a2, 8(a1)
f11: ld a3, 0(a4)
    ld a2, 16(a1)
    j fail_s
after11:
    CHK_S 5, 0x400020, f11, 0
    li a1, 0x5555
    bne a3, a1, fail_s
    li a1, 0x180010
    bne a2, a1, fail_s
    TRAPS 1

    // to M for test 12
    la a1, m_part
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
    j fail_s

m_part:
    // 12: M with MPRV=1, MPP=S.
    li t0, 12
    la t1, tr_count
    ld s9, 0(t1)
    MPRV_S
    li a1, 0x400028
    la t1, tr_resume
    la t2, after12a
    sd t2, 0(t1)
f12a: ld a2, 0(a1)
    j fail
after12a:
    MPRV_S
    CHK_M 5, 0x400028, f12a, 0
    MTRAPS 1
    li t0, 121
    li a3, CFG0R
    csrw pmpcfg0, a3
    sfence.vma
    ld a2, 0(a1)                // L0X readable: VA 0x400028 -> 0x182028
    li a3, 0x182028
    bne a2, a3, fail
    MTRAPS 1
    li t0, 122
    li a3, CFG0
    csrw pmpcfg0, a3
    sfence.vma
    la t1, tr_resume
    la t2, after12c
    sd t2, 0(t1)
f12c: ld a2, 8(a1)
    j fail
after12c:
    li t1, MPRV
    csrc mstatus, t1
    CHK_M 5, 0x400030, f12c, 0
    MTRAPS 2
    j pass

    .balign 4096
fpage:                          // reached through VA 0x603000/0x604000/0x401000
    li a5, 0x1234
    jalr x0, 0(ra)
    .balign 4096

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
    li t1, MPRV
    csrc mstatus, t1
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

// M: an ECALL from S with resume_addr set continues in M there
// (else fail 99). Any other trap is logged in tr (cause, tval, epc,
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
