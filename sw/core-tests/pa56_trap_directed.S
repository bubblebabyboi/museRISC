// Physical addresses at or above 2^56 (#53 review, trap state with
// FPGA_TIMING: MEM's access-fault check reads the registered D
// translation's PA, which for an untranslated access is the EX AGU
// value). Every access below runs in M (or M with MPRV, satp Bare)
// and must take an access fault with the exact cause, mtval, mepc and
// vstart, write nothing and leave its destination unchanged; the M
// handler logs and skips the instruction (or returns to ra for the
// fetch cases).
//  1: ld 2^56 -> 5.   2: sd 2^56+8 -> 7.   3: amoadd.d 2^56 -> 7, rd kept.
//  4: lr.d 2^56 -> 5, then sc.d to a normal address fails (rd != 0).
//  5: vle64 base 2^56-16, vl 4 -> 5 at element 2 (vstart 2, tval 2^56),
//     elements 0-1 loaded, 2-3 untouched.
//  6: vse64 base 2^56-16 -> 7 at element 2; elements 0-1 stored.
//  7: vle64ff base 2^56-16 -> no trap, vl 2.
//  8: MPRV = 1, MPP = S, satp Bare: ld 2^56 -> 5.
//  9: HLV.D 2^56 (vsatp, hgatp Bare) -> 5, mtval 2^56, mtval2 0,
//     mstatus.GVA = 1.
// 10: a 32-bit instruction at 2^56-2 (second parcel at 2^56) -> 1,
//     mtval 2^56, mepc 2^56-2.
// 11: jump to 2^56 -> 1, mtval = mepc = 2^56.
// Exit value: bit i set = case i failed (0 = pass); 99 = unexpected trap.
    .option arch, +v, +h
    .text
    .globl _start
.equ EXIT, 0x10000000

.macro FAILIF br, ra, rb, bit
    \br \ra, \rb, 1f
    j 2f
1:  li t4, 1 << \bit
    or s11, s11, t4
2:
.endm
.macro LOGCLR
    la t2, tcount
    sd x0, 0(t2)
.endm
// Exactly one trap: cause \c, mtval register \tv, vstart \vs.
.macro LOG1 c, tv, vs, bit
    la t2, tcount
    ld t1, 0(t2)
    li t3, 1
    FAILIF bne, t1, t3, \bit
    la t2, tlog
    ld t1, 0(t2)
    li t3, \c
    FAILIF bne, t1, t3, \bit
    ld t1, 8(t2)
    FAILIF bne, t1, \tv, \bit
    ld t1, 16(t2)
    li t3, \vs
    FAILIF bne, t1, t3, \bit
.endm

    .option norvc
_start:
    la sp, stack_top
    la t1, handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, (1 << 9) | (1 << 13)  // VS, FS Initial
    csrs mstatus, t1
    li s11, 0
    li s1, 1
    slli s1, s1, 56              // 2^56
    addi s2, s1, -16             // 2^56 - 16
    addi s3, s1, 8

    // 1: ld
    LOGCLR
    li a0, 0x77
    ld a0, 0(s1)
    LOG1 5, s1, 0, 1
    li t3, 0x77
    FAILIF bne, a0, t3, 1
    // 2: sd
    LOGCLR
    sd a0, 8(s1)
    LOG1 7, s3, 0, 2
    // 3: amoadd.d
    LOGCLR
    li a0, 0x77
    li a1, 1
    amoadd.d a0, a1, (s1)
    LOG1 7, s1, 0, 3
    li t3, 0x77
    FAILIF bne, a0, t3, 3
    // 4: lr.d then sc.d elsewhere must fail
    LOGCLR
    lr.d a0, (s1)
    LOG1 5, s1, 0, 4
    la a2, scratch
    li a1, 5
    sc.d a3, a1, (a2)
    FAILIF beq, a3, x0, 4
    ld a4, 0(a2)
    FAILIF beq, a4, a1, 4
    // 5: vle64 element 2 at 2^56
    LOGCLR
    li t1, 0x1111
    sd t1, 0(s2)
    li t1, 0x2222
    sd t1, 8(s2)
    vsetivli x0, 4, e64, m1, tu, mu
    vmv.v.i v1, 7
    vle64.v v1, (s2)
    csrr a5, vstart
    csrw vstart, x0
    LOG1 5, s1, 2, 5
    li t3, 2
    FAILIF bne, a5, t3, 5
    vmv.x.s a0, v1
    li t3, 0x1111
    FAILIF bne, a0, t3, 5
    vslidedown.vi v2, v1, 1
    vmv.x.s a0, v2
    li t3, 0x2222
    FAILIF bne, a0, t3, 5
    vslidedown.vi v2, v1, 2
    vmv.x.s a0, v2
    li t3, 7
    FAILIF bne, a0, t3, 5
    // 6: vse64 element 2 at 2^56
    LOGCLR
    vmv.v.i v3, -2
    vse64.v v3, (s2)
    csrw vstart, x0
    LOG1 7, s1, 2, 6
    ld a0, 8(s2)
    li t3, -2
    FAILIF bne, a0, t3, 6
    // 7: vle64ff trims to 2
    LOGCLR
    vsetivli x0, 4, e64, m1, tu, mu
    vle64ff.v v4, (s2)
    csrr a5, vl
    la t2, tcount
    ld t1, 0(t2)
    FAILIF bne, t1, x0, 7
    li t3, 2
    FAILIF bne, a5, t3, 7
    // 8: MPRV, MPP = S, Bare
    LOGCLR
    csrw satp, x0
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 17) | (1 << 11)
    csrs mstatus, t1
    li a0, 0x77
    ld a0, 0(s1)
    li t1, (1 << 17)
    csrc mstatus, t1
    LOG1 5, s1, 0, 8
    li t3, 0x77
    FAILIF bne, a0, t3, 8
    // 9: HLV.D, vsatp and hgatp Bare
    LOGCLR
    csrw 0x280, x0
    csrw 0x680, x0
    li t1, (1 << 7)              // hstatus.SPVP = 1
    csrs 0x600, t1
    li a0, 0x77
    hlv.d a0, (s1)
    LOG1 5, s1, 0, 9
    li t3, 0x77
    FAILIF bne, a0, t3, 9
    la t2, tlog
    ld t1, 24(t2)                // mtval2
    FAILIF bne, t1, x0, 9
    ld t1, 32(t2)                // mstatus at entry
    srli t1, t1, 38
    andi t1, t1, 1               // GVA
    FAILIF beq, t1, x0, 9
    // 10: straddling fetch into 2^56
    LOGCLR
    li t1, 0x0505                // low parcel of addi a0, a0, 0x50 (0x05050513)
    addi t2, s1, -2
    li t1, 0x0513
    sh t1, 0(t2)                 // low parcel at 2^56 - 2
    fence.i
    la ra, 1f
    jr t2
1:  addi t2, s1, -2
    LOG1 1, s1, 0, 10
    la t2, tlog
    ld t1, 40(t2)                // mepc
    addi t3, s1, -2
    FAILIF bne, t1, t3, 10
    // 11: jump to 2^56
    LOGCLR
    la ra, 1f
    jr s1
1:  LOG1 1, s1, 0, 11
    la t2, tlog
    ld t1, 40(t2)
    FAILIF bne, t1, s1, 11
    li t1, EXIT
    sd s11, 0(t1)
1:  j 1b

    .balign 64
handler:
    csrrw sp, mscratch, sp
    la sp, trap_stack_top
    sd t1, -8(sp)
    sd t2, -16(sp)
    sd t3, -24(sp)
    csrr t1, mcause
    li t2, 1
    beq t1, t2, 4f
    li t2, 5
    beq t1, t2, 4f
    li t2, 7
    bne t1, t2, unexpected
4:  la t2, tcount
    ld t3, 0(t2)
    addi t3, t3, 1
    sd t3, 0(t2)
    la t2, tlog
    sd t1, 0(t2)
    csrr t3, mtval
    sd t3, 8(t2)
    csrr t3, vstart
    sd t3, 16(t2)
    csrr t3, 0x34B               // mtval2
    sd t3, 24(t2)
    csrr t3, mstatus
    sd t3, 32(t2)
    csrr t3, mepc
    sd t3, 40(t2)
    li t2, 1
    bne t1, t2, 5f
    csrw mepc, ra                // fetch fault: back to the caller
    j 6f
5:  addi t3, t3, 4
    csrw mepc, t3
6:  li t1, (3 << 11)             // stay in M
    csrs mstatus, t1
    ld t1, -8(sp)
    ld t2, -16(sp)
    ld t3, -24(sp)
    csrrw sp, mscratch, sp
    mret
unexpected:
    li t1, EXIT
    li t2, 99
    sd t2, 0(t1)
1:  j 1b

    .data
    .align 6
scratch: .dword 0
tcount:  .dword 0
tlog:    .skip 64
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
