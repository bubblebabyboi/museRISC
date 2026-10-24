// Translation faults that need no walk: Sv39 non-canonical VAs and
// Sv39x4 GPAs of 2^41 and up (#53 review, trap state with FPGA_TIMING:
// these verdicts come from the registered D lookup / fetch record,
// also for a vector element or a fetch parcel that crosses into them).
// Traps go to M, which logs (mcause, mtval, mtval2, mstatus, mepc,
// vstart) and skips the instruction (fetch faults return to ra).
// S (V=0), satp Sv39; top 4K page of the lower canonical half
// (VA 0x3F_FFFF_F000) mapped RWX to PA 0x190000:
//  1: ld 0x40_0000_0000 -> 13, mtval = VA, rd kept.
//  2: sd -> 15.   3: amoswap.d -> 15, rd kept.
//  4: vle64 base 0x3F_FFFF_FFF0, vl 4 -> 13 at element 2 (vstart 2,
//     mtval 0x40_0000_0000), elements 0-1 loaded.
//  5: vle64ff the same -> no trap, vl 2.
//  6: jump to 0x40_0000_0000 -> 12, mtval = mepc = VA.
//  7: a 32-bit instruction at 0x3F_FFFF_FFFE -> 12, mtval =
//     0x40_0000_0000, mepc = 0x3F_FFFF_FFFE.
// VS (V=1), vsatp Bare, hgatp Sv39x4 (GPA 0..1G identity, the 1 GiB
// below 2^41 -> PA 0..1G):
//  8: ld GPA 2^41 -> 21, mtval 2^41, mtval2 2^41 >> 2, GVA = 1.
//  9: vle64 base 2^41 - 16, vl 4 -> 21 at element 2 (vstart 2), mtval
//     2^41, mtval2 2^41 >> 2.
// 10: sd GPA 2^41 + 8 -> 23, mtval2 (2^41 + 8) >> 2.
// Exit value: bit i set = case i failed (0 = pass); 1000 + mcause =
// an unexpected trap.
    .option arch, +v, +h
    .text
    .globl _start
.equ EXIT,   0x10000000
.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL1T,  0x102000          // L1 for VA 0x3FC000_0000.. (root 255)
.equ PGL0T,  0x103000          // L0 for VA 0x3F_FFE0_0000..
.equ GROOT,  0x110000          // hgatp root (16 KiB)
.equ PA_T,   0x190000
.equ VA_T,   0x3FFFFFF000
.equ VA_NC,  0x4000000000

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
// Exactly one trap: cause \c, mtval reg \tv, vstart \vs.
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
    ld t1, 40(t2)
    li t3, \vs
    FAILIF bne, t1, t3, \bit
.endm
// mtval2 of the logged trap = register \g.
.macro LOGG g, bit
    la t2, tlog
    ld t1, 16(t2)
    FAILIF bne, t1, \g, \bit
.endm

    .option norvc
_start:
    la sp, stack_top
    la t1, handler
    csrw mtvec, t1
    csrw medeleg, x0
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, PGROOT
    li t2, PGROOT + 0x4000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t2, PGROOT
    li t1, (PGL1 >> 2) | 1
    sd t1, 0(t2)
    li t1, (PGL1T >> 2) | 1
    sd t1, 255 * 8(t2)
    li t2, PGL1
    li t1, 0xEF                  // VA 0..2M identity RWX G A D
    sd t1, 0(t2)
    li t1, (EXIT >> 2) | 0xE7
    sd t1, 128 * 8(t2)
    li t2, PGL1T + 511 * 8
    li t1, (PGL0T >> 2) | 1
    sd t1, 0(t2)
    li t2, PGL0T + 511 * 8
    li t1, (PA_T >> 2) | 0xCF    // R W X A D
    sd t1, 0(t2)
    li t2, PA_T + 0xFF0          // data at VA_T + 0xFF0
    li t1, 0x1111
    sd t1, 0(t2)
    li t1, 0x2222
    sd t1, 8(t2)
    // 32-bit addi a0, a0, 0x50 low parcel at VA_T + 0xFFE (case 7)
    li t2, PA_T + 0xFFE
    li t1, 0x0513
    sh t1, 0(t2)
    li t1, (8 << 60) | (PGROOT >> 12)
    csrw satp, t1
    sfence.vma
    fence.i
    li t1, (1 << 9) | (1 << 13)  // VS, FS Initial
    csrs mstatus, t1
    la t1, s_code
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    li s11, 0
    mret

s_code:
    li s1, VA_NC
    li s2, VA_T + 0xFF0
    // 1: ld
    LOGCLR
    li a0, 0x77
    ld a0, 0(s1)
    LOG1 13, s1, 0, 1
    li t3, 0x77
    FAILIF bne, a0, t3, 1
    // 2: sd
    LOGCLR
    sd a0, 0(s1)
    LOG1 15, s1, 0, 2
    // 3: amoswap.d
    LOGCLR
    li a0, 0x77
    amoswap.d a0, a0, (s1)
    LOG1 15, s1, 0, 3
    li t3, 0x77
    FAILIF bne, a0, t3, 3
    // 4: vle64 crossing into non-canonical
    LOGCLR
    vsetivli x0, 4, e64, m1, tu, mu
    vmv.v.i v1, 7
    sfence.vma
    vle64.v v1, (s2)
    csrr a5, vstart
    csrw vstart, x0
    LOG1 13, s1, 2, 4
    vmv.x.s a0, v1
    li t3, 0x1111
    FAILIF bne, a0, t3, 4
    vslidedown.vi v2, v1, 1
    vmv.x.s a0, v2
    li t3, 0x0513000000002222    // (case 7's parcel is in its top bytes)
    FAILIF bne, a0, t3, 4
    vslidedown.vi v2, v1, 2
    vmv.x.s a0, v2
    li t3, 7
    FAILIF bne, a0, t3, 4
    // 5: vle64ff
    LOGCLR
    vsetivli x0, 4, e64, m1, tu, mu
    sfence.vma
    vle64ff.v v3, (s2)
    csrr a5, vl
    la t2, tcount
    ld t1, 0(t2)
    FAILIF bne, t1, x0, 5
    li t3, 2
    FAILIF bne, a5, t3, 5
    // 6: jump to non-canonical
    LOGCLR
    la ra, 1f
    jr s1
1:  LOG1 12, s1, 0, 6
    la t2, tlog
    ld t1, 32(t2)
    FAILIF bne, t1, s1, 6
    // 7: straddling instruction into non-canonical
    LOGCLR
    li t5, VA_T + 0xFFE
    la ra, 1f
    jr t5
1:  LOG1 12, s1, 0, 7
    la t2, tlog
    ld t1, 32(t2)
    FAILIF bne, t1, t5, 7
    ecall                        // to M: enter VS for 8-10

    .balign 64
vs_code:
    li s1, 1
    slli s1, s1, 41              // GPA 2^41
    addi s2, s1, -16
    srli s3, s1, 2               // mtval2 expected
    // 8: ld
    LOGCLR
    li a0, 0x77
    ld a0, 0(s1)
    LOG1 21, s1, 0, 8
    LOGG s3, 8
    la t2, tlog
    ld t1, 24(t2)                // mstatus at entry
    srli t1, t1, 38
    andi t1, t1, 1               // GVA
    FAILIF beq, t1, x0, 8
    li t3, 0x77
    FAILIF bne, a0, t3, 8
    // 9: vle64 crossing into 2^41
    LOGCLR
    li t1, 0x3333
    sd t1, 0(s2)                 // (GPA 2^41-16 -> PA 1G-16)
    vsetivli x0, 4, e64, m1, tu, mu
    vmv.v.i v1, 7
    vle64.v v1, (s2)
    csrw vstart, x0
    LOG1 21, s1, 2, 9
    LOGG s3, 9
    vmv.x.s a0, v1
    li t3, 0x3333
    FAILIF bne, a0, t3, 9
    // 10: sd 2^41 + 8
    LOGCLR
    addi s4, s1, 8
    srli s5, s4, 2
    sd a0, 8(s1)
    LOG1 23, s4, 0, 10
    LOGG s5, 10
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
    li t2, 9                     // ecall from HS: enter VS
    beq t1, t2, enter_vs
    li t2, 12
    beq t1, t2, 4f
    li t2, 13
    beq t1, t2, 4f
    li t2, 15
    beq t1, t2, 4f
    li t2, 21
    beq t1, t2, 4f
    li t2, 23
    bne t1, t2, unexpected
4:  la t2, tcount
    ld t3, 0(t2)
    addi t3, t3, 1
    sd t3, 0(t2)
    la t2, tlog
    sd t1, 0(t2)
    csrr t3, mtval
    sd t3, 8(t2)
    csrr t3, 0x34B
    sd t3, 16(t2)
    csrr t3, mstatus
    sd t3, 24(t2)
    csrr t3, mepc
    sd t3, 32(t2)
    csrr t3, vstart
    sd t3, 40(t2)
    li t2, 12
    bne t1, t2, 5f
    csrw mepc, ra
    j 6f
5:  csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
6:  ld t1, -8(sp)
    ld t2, -16(sp)
    ld t3, -24(sp)
    csrrw sp, mscratch, sp
    mret
enter_vs:
    // hgatp Sv39x4: GPA 0..1G identity, GPA 2^41-1G..2^41 -> PA 0..1G
    li t1, GROOT
    li t2, GROOT + 0x4000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t2, GROOT
    li t1, 0xDF                  // V R W X U A D, PPN 0
    sd t1, 0(t2)
    li t1, 0xD7                  // V R W U A D, PPN 0
    li t2, GROOT + 2047 * 8
    sd t1, 0(t2)
    li t1, (8 << 60) | (GROOT >> 12)
    csrw 0x680, t1
    csrw 0x280, x0               // vsatp Bare
    li t1, (1 << 9)              // vsstatus.VS = Initial
    csrs 0x200, t1
    hfence.gvma
    csrw satp, x0
    sfence.vma
    la t1, vs_code
    csrw mepc, t1
    li t1, 1
    slli t1, t1, 39              // MPV
    csrs mstatus, t1
    li t1, (1 << 11)             // MPP = S (already)
    csrs mstatus, t1
    ld t1, -8(sp)
    ld t2, -16(sp)
    ld t3, -24(sp)
    csrrw sp, mscratch, sp
    mret
unexpected:
    csrr t2, mcause              // 1000 + cause, mepc in dbg
    addi t2, t2, 1000
    la t1, dbg
    csrr t3, mepc
    sd t3, 0(t1)
    csrr t3, mtval
    sd t3, 8(t1)
    li t1, EXIT
    sd t2, 0(t1)
1:  j 1b

    .data
    .align 6
tcount:  .dword 0
dbg:     .dword 0, 0
tlog:    .skip 64
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
