// PMP partial matches beyond M-mode scalar accesses (issue #8, review
// of 3ae351d): the lowest-numbered entry that matches any byte of an
// access decides, and if it does not match all of its bytes the access
// fails, whatever the privilege mode and L/R/W/X; no match fails S/U and
// passes M. With the 4-byte grain an NA4 entry or a TOR boundary splits
// an 8-byte access. pmp_partial_directed covers M-mode ld/sd/amoadd.d/
// fld; this test covers:
//   1-5:   S/U data accesses (M with MPRV, MPP = U): NA4 over word 1,
//          TOR ending or starting inside the dword, NAPOT 8 below an NA4
//          (priority), NA4 with no permission over a NAPOT, no match;
//          lw of each word alone passes; M with no matching entry passes
//   6-7:   AMO .d/.w, LR.d, SC.d with and without a reservation
//   8:     misaligned 8-byte accesses trap as misaligned, not as access
//          faults
//   9-12:  vector EEW=64 elements: unit-stride load and store, strided,
//          indexed, fault-only-first (vl trim), segment; EEW=32 passes
//   13-16: Sv39 walker PTE reads (8 bytes, checked as S): a data walk
//          (M with MPRV, MPP = S) and a fetch walk (S) whose leaf PTE an
//          NA4 entry or a TOR boundary splits fail with an access fault
//          of the original access type (tval = VA); controls pass
//   17-19: fetch (S, Bare): a 32-bit instruction straddling into a word
//          without X faults at its second parcel (mepc = pc, tval =
//          pc+2), also after a c.nop; a 16-bit parcel inside that word
//          faults at itself; the same fetches pass in M with L=0
//   20-21: locked entries (last, as L stays set): an M-mode dword
//          access split by a locked NA4 fails, its word alone passes;
//          an M-mode fetch straddling into a locked NA4 without X faults
// Every expected trap is what Spike and Sail give: the test passes on
// both when assembled with -DSPIKE_HTIF (tohost exit, link at
// 0x80000000; Sail with sw/act4-core/sail.json). On the RTL before
// 3ae351d it fails at test 1, and tests 6, 9-13, 15 and 20 each fail
// there when run on their own; the fetch tests (17-19, 21) pass on
// both, as fetches were and are checked one 4-byte word at a time.
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it

#ifdef SPIKE_HTIF
#define EXIT_PASS li t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#define EXIT_FAIL slli t1, t0, 1; ori t1, t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#else
#define EXIT_PASS li t1, 0x10000000; sd x0, 0(t1); 1: j 1b
#define EXIT_FAIL li t1, 0x10000000; sd t0, 0(t1); 1: j 1b
#endif

#define MPRV     (1 << 17)
#define MPP_MASK (3 << 11)
#define MPP_S    (1 << 11)
#define NA4      (2 << 3)
#define TOR      (1 << 3)
#define NAPOT    (3 << 3)
#define LOCK     0x80
#define VA_D     0x40000000           // data page (walker tests)
#define VA_X     0x40001000           // code page (fetch walk tests)
#define PTE_VRWAD 0xc7
#define PTE_VRXAD 0xcb

// Trap record: tr+0 count, +8 mcause, +16 mepc, +24 mtval, +32 vstart.
.macro CLR
    la a4, tr
    sd zero, 0(a4)
.endm
.macro EXP_NONE
    la a4, tr
    ld a5, 0(a4)
    bnez a5, fail
.endm
// Exactly one trap with cause \c and mtval = register \tv.
.macro EXP c, tv
    la a4, tr
    ld a5, 0(a4)
    li a6, 1
    bne a5, a6, fail
    ld a5, 8(a4)
    li a6, \c
    bne a5, a6, fail
    ld a5, 24(a4)
    bne a5, \tv, fail
.endm
.macro EXP_EPC r
    la a4, tr
    ld a5, 16(a4)
    bne a5, \r, fail
.endm
.macro EXP_VSTART n
    la a4, tr
    ld a5, 32(a4)
    li a6, \n
    bne a5, a6, fail
.endm
// pmpaddr\n = (address in register \r + \off) >> 2
.macro PADDR n, r, off
    addi t1, \r, \off
    srli t1, t1, 2
    csrw pmpaddr\n, t1
.endm
// M with MPRV: data accesses as U (s8) or S (s7); MPRV off (s9).
.macro AS_U
    csrc mstatus, s6
    csrs mstatus, s8
.endm
.macro AS_S
    csrc mstatus, s6
    csrs mstatus, s7
.endm
.macro AS_M
    csrc mstatus, s9
.endm

    .text
    .globl _start
_start:
    la t1, handler
    csrw mtvec, t1
    li t1, (1 << 13) | (1 << 9)    // FS = VS = Initial
    csrs mstatus, t1
    li s9, MPRV
    li s8, MPRV                    // MPP = U
    li s7, MPRV | MPP_S
    li s6, MPRV | MPP_MASK
    la s1, dw                      // D: the dword under test
    csrw pmpcfg0, zero             // (Spike resets entry 0 to NAPOT RWX)
    csrw pmpcfg2, zero
    // Entry 15: NAPOT over everything, RWX (opens memory to S/U).
    li t1, -1
    csrw pmpaddr15, t1
    li t1, (NAPOT | 7) << 56
    csrw pmpcfg2, t1

    // ---- 1: NA4 RWX over word 1 of D, entry 15 RWX elsewhere: as U,
    //      ld/sd/fld D fail (entry 0 decides and matches half), each
    //      word alone passes; in M the split still fails ----
    li t0, 1
    PADDR 0, s1, 4
    li t1, NA4 | 7
    csrw pmpcfg0, t1
    CLR
    AS_U
    ld a1, 0(s1)
    AS_M
    EXP 5, s1
    CLR
    AS_U
    sd zero, 0(s1)
    AS_M
    EXP 7, s1
    CLR
    AS_U
    fld f1, 0(s1)
    AS_M
    EXP 5, s1
    CLR
    AS_U
    lw a1, 0(s1)
    lw a1, 4(s1)
    sw zero, 4(s1)
    AS_M
    EXP_NONE
    CLR
    ld a1, 0(s1)
    EXP 5, s1

    // ---- 2: TOR [D-8, D+4) RW (entry 1): as U, ld D-8 passes, ld D
    //      fails; then entry 1 off and entry 2 TOR [D+4, D+64) R: as U
    //      sd D fails (entry 2 matches word 1 only), ld D+8 passes ----
    li t0, 2
    csrw pmpcfg0, zero
    PADDR 0, s1, -8
    PADDR 1, s1, 4
    li t1, (TOR | 3) << 8
    csrw pmpcfg0, t1
    CLR
    AS_U
    ld a1, -8(s1)
    AS_M
    EXP_NONE
    CLR
    AS_U
    ld a1, 0(s1)
    AS_M
    EXP 5, s1
    PADDR 2, s1, 64
    li t1, (TOR | 1) << 16
    csrw pmpcfg0, t1
    CLR
    AS_U
    sd zero, 0(s1)
    AS_M
    EXP 7, s1
    CLR
    AS_U
    ld a1, 8(s1)
    AS_M
    EXP_NONE

    // ---- 3: priority: entry 0 NAPOT 8 RW over D, entry 1 NA4 (no
    //      permission) over word 1: entry 0 decides, ld/sd D pass ----
    li t0, 3
    csrw pmpcfg0, zero
    PADDR 0, s1, 0                 // NAPOT 8: pmpaddr low bit 0
    PADDR 1, s1, 4
    li t1, (NAPOT | 3) | (NA4 << 8)
    csrw pmpcfg0, t1
    CLR
    AS_U
    ld a1, 0(s1)
    sd a1, 0(s1)
    AS_M
    EXP_NONE

    // ---- 4: entry 0 NA4 (no permission) over word 1, entry 1 NAPOT 64
    //      RWX over D's line: entry 0 decides: as U and in M ld D
    //      fails; lw of word 0 passes ----
    li t0, 4
    csrw pmpcfg0, zero
    PADDR 0, s1, 4
    andi t2, s1, -64
    srli t2, t2, 2
    ori t2, t2, 7                  // NAPOT 64 bytes
    csrw pmpaddr1, t2
    li t1, NA4 | ((NAPOT | 7) << 8)
    csrw pmpcfg0, t1
    CLR
    AS_U
    ld a1, 0(s1)
    AS_M
    EXP 5, s1
    CLR
    ld a1, 0(s1)
    EXP 5, s1
    CLR
    AS_U
    lw a1, 0(s1)
    AS_M
    EXP_NONE

    // ---- 5: no matching entry (entry 15 off, entry 0 NA4 elsewhere):
    //      M passes (ld, sd, vle64), U fails ----
    li t0, 5
    csrw pmpcfg0, zero
    csrw pmpcfg2, zero
    PADDR 0, s1, 128
    li t1, NA4
    csrw pmpcfg0, t1
    CLR
    ld a1, 0(s1)
    sd a1, 0(s1)
    vsetivli zero, 2, e64, m1, tu, mu
    vle64.v v1, (s1)
    EXP_NONE
    CLR
    AS_U
    ld a1, 0(s1)
    AS_M
    EXP 5, s1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, (NAPOT | 7) << 56
    csrw pmpcfg2, t1

    // ---- 6: NA4 RWX over word 1 (entry 0), M: AMO .d and LR.d on D
    //      fail (store/AMO 7, load 5); AMO .w on either word passes;
    //      a lone SC.d on D fails (cause 7) ----
    li t0, 6
    csrw pmpcfg0, zero
    PADDR 0, s1, 4
    li t1, NA4 | 7
    csrw pmpcfg0, t1
    li a2, 1
    CLR
    amoswap.d a1, a2, (s1)
    EXP 7, s1
    CLR
    amoadd.d a1, a2, (s1)
    EXP 7, s1
    CLR
    lr.d a1, (s1)
    EXP 5, s1
    CLR
    sc.d a1, a2, (s1)
    EXP 7, s1
    CLR
    amoadd.w a1, a2, (s1)
    addi t2, s1, 4
    amoadd.w a1, a2, (t2)
    EXP_NONE

    // ---- 7: LR/SC pairs where nothing is split succeed (as U) ----
    li t0, 7
    addi t2, s1, -8
    CLR
    AS_U
    lr.d a1, (t2)
    sc.d a3, a2, (t2)
    AS_M
    EXP_NONE
    bnez a3, fail
    addi t2, s1, 4
    CLR
    AS_U
    lr.w a1, (t2)
    sc.w a3, a2, (t2)
    AS_M
    EXP_NONE
    bnez a3, fail

    // ---- 8: misaligned 8-byte accesses at D+4 (also split by the NA4
    //      entry) trap as misaligned (4 / 6), as U and in M ----
    li t0, 8
    addi t2, s1, 4
    CLR
    AS_U
    ld a1, 0(t2)
    AS_M
    EXP 4, t2
    CLR
    sd a1, 0(t2)
    EXP 6, t2
    CLR
    fld f1, 0(t2)
    EXP 4, t2

    // ---- 9: vector EEW=64, M, NA4 over word 1 of D: vle64.v and
    //      vse64.v from D-8 (vl 2) fault on element 1 (tval D, vstart
    //      1); vle32.v over the same bytes passes ----
    li t0, 9
    addi t2, s1, -8
    vsetivli zero, 2, e64, m1, tu, mu
    CLR
    vle64.v v1, (t2)
    EXP 5, s1
    EXP_VSTART 1
    CLR
    vse64.v v1, (t2)
    EXP 7, s1
    EXP_VSTART 1
    vsetivli zero, 4, e32, m1, tu, mu
    CLR
    vle32.v v1, (t2)
    vse32.v v1, (t2)
    EXP_NONE

    // ---- 10: strided (stride 8) and indexed (offsets {0, 8}) EEW=64
    //      loads from D-8, as U: element 1 faults ----
    li t0, 10
    vsetivli zero, 2, e64, m1, tu, mu
    li t3, 8
    CLR
    AS_U
    vlse64.v v1, (t2), t3
    AS_M
    EXP 5, s1
    EXP_VSTART 1
    vid.v v2
    vsll.vi v2, v2, 3
    CLR
    AS_U
    vluxei64.v v1, (t2), v2
    AS_M
    EXP 5, s1
    EXP_VSTART 1

    // ---- 11: fault-only-first vle64ff.v from D-8 (vl 2), M: no trap,
    //      vl trimmed to 1 ----
    li t0, 11
    vsetivli zero, 2, e64, m1, tu, mu
    CLR
    vle64ff.v v1, (t2)
    csrr a1, vl
    EXP_NONE
    li a2, 1
    bne a1, a2, fail

    // ---- 12: segment load vlseg2e64.v from D-8 (vl 1): field 1 is
    //      D: trap, vstart 0 ----
    li t0, 12
    vsetivli zero, 1, e64, m1, tu, mu
    CLR
    vlseg2e64.v v4, (t2)
    EXP 5, s1
    EXP_VSTART 0
    csrw pmpcfg0, zero

    // ---- Sv39: root[code] identity 1 GiB leaf (no U), root[1] -> l1,
    //      l1[0] -> l0, l0[0] -> dpage (VA_D, RW), l0[1] -> xpage
    //      (VA_X, RX; holds an ECALL) ----
    la t1, _start
    srli t2, t1, 30                // VPN[2] of the code
    slli t3, t2, 28                // PPN of the 1 GiB leaf
    ori t3, t3, 0xcf               // V R W X A D
    la t4, pt_root
    slli t2, t2, 3
    add t2, t2, t4
    sd t3, 0(t2)
    la t3, pt_l1
    srli t3, t3, 12
    slli t3, t3, 10
    ori t3, t3, 1
    sd t3, 8(t4)                   // root[1] -> l1
    la t4, pt_l1
    la t3, pt_l0
    srli t3, t3, 12
    slli t3, t3, 10
    ori t3, t3, 1
    sd t3, 0(t4)                   // l1[0] -> l0
    la t4, pt_l0
    la t3, dpage
    srli t3, t3, 12
    slli t3, t3, 10
    ori t3, t3, PTE_VRWAD
    sd t3, 0(t4)                   // l0[0] -> dpage
    la t3, xpage
    srli t3, t3, 12
    slli t3, t3, 10
    ori t3, t3, PTE_VRXAD
    sd t3, 8(t4)                   // l0[1] -> xpage
    la t3, xpage
    li t1, 0x00000073              // ecall
    sw t1, 0(t3)
    fence.i
    la t1, pt_root
    srli t1, t1, 12
    li t2, 8
    slli t2, t2, 60
    or t1, t1, t2
    csrw satp, t1
    sfence.vma
    la s2, pt_l0
    li s3, VA_D
    li s4, VA_X

    // ---- 13: data walk as S (M with MPRV, MPP = S): NA4 RWX over
    //      word 1 of l0[0]: ld/sd VA_D fail (5 / 7, tval VA_D); the
    //      same entry over word 1 of l0[1] leaves VA_D alone ----
    li t0, 13
    PADDR 0, s2, 4
    li t1, NA4 | 7
    csrw pmpcfg0, t1
    sfence.vma
    CLR
    AS_S
    ld a1, 0(s3)
    AS_M
    EXP 5, s3
    CLR
    AS_S
    sd a1, 0(s3)
    AS_M
    EXP 7, s3
    csrw pmpcfg0, zero
    PADDR 0, s2, 12
    li t1, NA4 | 7
    csrw pmpcfg0, t1
    sfence.vma
    CLR
    AS_S
    ld a1, 0(s3)
    sd a1, 0(s3)
    AS_M
    EXP_NONE

    // ---- 14: TOR [l0, l0+4) RWX (entry 1, base pmpaddr0 = l0): splits
    //      l0[0]: ld VA_D fails as S ----
    li t0, 14
    csrw pmpcfg0, zero
    PADDR 0, s2, 0
    PADDR 1, s2, 4
    li t1, (TOR | 7) << 8
    csrw pmpcfg0, t1
    sfence.vma
    CLR
    AS_S
    ld a1, 0(s3)
    AS_M
    EXP 5, s3

    // ---- 15: fetch walk in S: NA4 RWX over word 1 of l0[1]: jumping
    //      to VA_X faults (cause 1, mepc = tval = VA_X) ----
    li t0, 15
    csrw pmpcfg0, zero
    PADDR 0, s2, 12
    li t1, NA4 | 7
    csrw pmpcfg0, t1
    sfence.vma
    CLR
    mv a0, s4
    call run_s
    EXP 1, s4
    EXP_EPC s4

    // ---- 16: control: entry 0 off, the same jump reaches the ECALL
    //      in xpage (cause 9, mepc VA_X) ----
    li t0, 16
    csrw pmpcfg0, zero
    sfence.vma
    CLR
    mv a0, s4
    call run_s
    li t2, 0
    EXP 9, t2
    EXP_EPC s4
    csrw satp, zero
    sfence.vma

    // ---- 17: fetch in S (Bare): NA4 R over word 1 of the code window
    //      C (no X): a 32-bit instruction at C+2 faults at its second
    //      parcel (mepc C+2, tval C+4), entered at C+2 or at the
    //      c.nop at C ----
    li t0, 17
    la s5, cwin
    PADDR 0, s5, 4
    li t1, NA4 | 1
    csrw pmpcfg0, t1
    addi t2, s5, 2
    addi t3, s5, 4
    CLR
    mv a0, t2
    call run_s
    EXP 1, t3
    EXP_EPC t2
    CLR
    mv a0, s5
    call run_s
    EXP 1, t3
    EXP_EPC t2

    // ---- 18: the c.nop at C+6 (inside word 1) faults at itself ----
    li t0, 18
    addi t2, s5, 6
    CLR
    mv a0, t2
    call run_s
    EXP 1, t2
    EXP_EPC t2

    // ---- 19: control: in M (L=0) the window runs: C+2 and C+6 ----
    li t0, 19
    CLR
    addi t2, s5, 2
    jalr ra, 0(t2)
    addi t2, s5, 6
    jalr ra, 0(t2)
    EXP_NONE
    csrw pmpcfg0, zero

    // ---- 20: locked NA4 RWX over word 1 of D (entry 13), M: ld D
    //      fails, lw D+4 passes ----
    li t0, 20
    PADDR 13, s1, 4
    li t1, (LOCK | NA4 | 7) << 40
    csrs pmpcfg2, t1
    CLR
    ld a1, 0(s1)
    EXP 5, s1
    CLR
    lw a1, 4(s1)
    EXP_NONE

    // ---- 21: locked NA4 R (no X) over word 1 of C (entry 14), M: a
    //      fetch of the 32-bit instruction at C+2 faults at C+4 ----
    li t0, 21
    PADDR 14, s5, 4
    li t1, (LOCK | NA4 | 1) << 48
    csrs pmpcfg2, t1
    la s10, after21
    CLR
    addi t2, s5, 2
    jalr ra, 0(t2)
after21:
    addi t3, s5, 4
    EXP 1, t3
    EXP_EPC t2

pass:
    EXIT_PASS
fail:
    EXIT_FAIL

// Run a0 in S (MPRV clears on MRET to S). The code there ends in an
// ECALL (or faults); the handler resumes M at s10, which returns
// through s11 (ra is the S code's link register).
run_s:
    mv s11, ra
    la s10, 1f
    li t1, MPP_MASK
    csrc mstatus, t1
    li t1, MPP_S
    csrs mstatus, t1
    la t1, s_stub
    csrw mepc, t1
    mret
1:  jr s11
s_stub:
    jalr ra, 0(a0)
    ecall

// Records the trap; fetch faults and ECALLs resume M at s10, other
// traps skip the instruction (2 or 4 bytes).
    .align 4
handler:
    csrw mscratch, a4
    la a4, tr
    sd a5, 40(a4)
    sd a6, 48(a4)
    ld a5, 0(a4)
    addi a5, a5, 1
    sd a5, 0(a4)
    csrr a5, mcause
    sd a5, 8(a4)
    csrr a5, mepc
    sd a5, 16(a4)
    csrr a5, mtval
    sd a5, 24(a4)
    csrr a5, vstart
    sd a5, 32(a4)
    csrw vstart, zero
    csrr a5, mcause
    li a6, 1
    beq a5, a6, 2f
    li a6, 8
    beq a5, a6, 2f
    li a6, 9
    beq a5, a6, 2f
    csrr a5, mepc
    lhu a6, 0(a5)
    andi a6, a6, 3
    addi a5, a5, 2
    li a4, 3
    bne a6, a4, 1f
    addi a5, a5, 2
1:  csrw mepc, a5
    j 3f
2:  csrw mepc, s10
    li a5, MPP_MASK
    csrs mstatus, a5
3:  la a4, tr
    ld a5, 40(a4)
    ld a6, 48(a4)
    csrr a4, mscratch
    mret

// Code window C: c.nop | 32-bit NOP at C+2 (straddles into word 1) |
// c.nop at C+6 | ret.
    .align 4
cwin:
    .2byte 0x0001
    .4byte 0x00000013
    .2byte 0x0001
    .4byte 0x00008067

    .data
    .align 3
tr: .dword 0, 0, 0, 0, 0, 0, 0
    .align 6
    .dword 0x1111111111111111
dw: .dword 0x2222222222222222
    .dword 0x3333333333333333
    .skip 104
    .align 12
pt_root: .skip 4096
pt_l1:   .skip 4096
pt_l0:   .skip 4096
dpage:   .skip 4096
xpage:   .skip 4096
#ifdef SPIKE_HTIF
    .align 6
    .globl tohost
tohost: .dword 0
    .align 6
    .globl fromhost
fromhost: .dword 0
#endif
