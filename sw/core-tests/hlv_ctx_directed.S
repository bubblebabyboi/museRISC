// HLV/HSV/HLVX translation context and trap state (#53 review: the
// FPGA_TIMING data lookup runs in EX with HLV's own context: vsatp,
// hgatp, hstatus.SPVP, vsstatus.SUM/MXR, HS MXR). HS code at VA_X
// sees PA 0x180000; a guest (vsatp Sv39 + hgatp Sv39x4) sees VA_X at
// GPA 0x300000 -> PA 0x183000. Every trap goes to M, which logs
// (mcause, mtval, mtval2, mepc, mstatus.GVA) and skips.
//  1: HS loads and HLVs of the same VA, alternating every instruction.
//  2: HSV then HS load and HLV read-back.
//  3: hstatus.SPVP and vsstatus.SUM toggled right before HLVs of a
//     VS U page (13, gva, mtval2 = 0 when denied).
//  4: vsatp switched between two VS tables right before HLVs.
//  5: HLVX of a VS execute-only page; HLV.W of it faults until
//     vsstatus.MXR or HS sstatus.MXR is set right before.
//  6: G-stage-unmapped GPA: HLV faults 21 (mtval VA, mtval2 GPA>>2,
//     GVA), an HS load of the same VA right after succeeds; HSV 23.
//  7: vle64ff trimmed at P (HS walk fault), then HSV/HLVX of P.
// t0 = test number; exit store 0 = pass.
    .option arch, +v
    .option arch, +h
    .option norvc
    .text
    .globl _start

.equ EXIT,   0x10000000
.equ ROOT,   0x100000           // HS satp
.equ L1,     0x101000
.equ L0,     0x102000
.equ VS1R,   0x103000           // VS table 1 (GPA = PA, G identity)
.equ VS1L1,  0x104000
.equ VS1L0,  0x105000
.equ VS2R,   0x106000           // VS table 2
.equ VS2L1,  0x107000
.equ VS2L0,  0x108000
.equ VA_X,   0x200000
.equ SPVP,   (1 << 8)
.equ SUM,    (1 << 18)
.equ MXR,    (1 << 19)

.macro PTEW addr, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \addr
    sd t1, 0(t2)
.endm
// Last M trap: cause, tval, tval2, epc label, gva.
.macro CHK cause, tval, tval2, epc, gva
    la t1, m_last
    ld t2, 0(t1)
    li t3, \cause
    bne t2, t3, fail
    ld t2, 8(t1)
    li t3, \tval
    bne t2, t3, fail
    ld t2, 16(t1)
    li t3, \tval2
    bne t2, t3, fail
    ld t2, 24(t1)
    la t3, \epc
    bne t2, t3, fail
    ld t2, 32(t1)
    li t3, \gva
    bne t2, t3, fail
.endm
.macro MARK
    la t1, m_count
    ld s9, 0(t1)
.endm
.macro TRAPS n
    la t1, m_count
    ld t2, 0(t1)
    sub t2, t2, s9
    li t3, \n
    bne t2, t3, fail
.endm

_start:
    la sp, stack_top
    la t1, m_trap
    csrw mtvec, t1
    la t1, m_stack_top
    csrw mscratch, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, (1 << 9)
    csrs mstatus, t1
    li t1, ROOT
    li t2, VS2L0 + 0x1000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Data: PA 0x180000.. each page filled with a tag.
    li t1, 0x180000
    li t2, 0xAAAA
    li t3, 0x181000
1:  sd t2, 0(t1)
    addi t1, t1, 8
    blt t1, t3, 1b
    li t1, 0x183000
    li t2, 0xBBBB
    sd t2, 0(t1)
    li t1, 0x184000
    li t2, 0xCCCC
    sd t2, 0(t1)
    li t1, 0x185000
    li t2, 0xDDDD
    sd t2, 0(t1)
    li t1, 0x186000
    li t2, 0xEEEE
    sd t2, 0(t1)
    // HS: 2M identity; VA_X -> 0x180000; VA_X+3000 -> 0x186000;
    // VA_X+0x5000 unmapped (P for test 7).
    PTEW ROOT, L1, 0x01
    PTEW L1, 0, 0xCF
    PTEW L1 + 8, L0, 0x01
    PTEW L0, 0x180000, 0xC7
    PTEW L0 + 3 * 8, 0x186000, 0xC7
    // VS table 1: 2M identity; VA_X -> GPA 0x300000 (S RW),
    // +1000 -> 0x301000 (U RW), +2000 -> 0x302000 (X only),
    // +3000 -> 0x380000 (G-unmapped), +5000 -> 0x300000 (S RW).
    PTEW VS1R, VS1L1, 0x01
    PTEW VS1L1, 0, 0xCF
    PTEW VS1L1 + 8, VS1L0, 0x01
    PTEW VS1L0, 0x300000, 0xC7
    PTEW VS1L0 + 8, 0x301000, 0xD7
    PTEW VS1L0 + 16, 0x302000, 0xC9
    PTEW VS1L0 + 24, 0x380000, 0xC7
    PTEW VS1L0 + 40, 0x302000, 0xCF
    // VS table 2: VA_X -> GPA 0x301000 (S RW).
    PTEW VS2R, VS2L1, 0x01
    PTEW VS2L1, 0, 0xCF
    PTEW VS2L1 + 8, VS2L0, 0x01
    PTEW VS2L0, 0x301000, 0xC7
    // G-stage: GPA 0..2M identity, 0x300000/1/2 -> 0x183/4/5000.
    la t1, g_root
    la t2, g_l1
    srli t2, t2, 2
    ori t2, t2, 1
    sd t2, 0(t1)
    la t1, g_l1
    li t2, 0xDF
    sd t2, 0(t1)
    la t2, g_l0
    srli t2, t2, 2
    ori t2, t2, 1
    sd t2, 8(t1)
    la t1, g_l0
    li t2, (0x183000 >> 2) | 0xDF
    li t3, 0x100 * 8
    add t3, t3, t1
    sd t2, 0(t3)
    li t2, (0x184000 >> 2) | 0xDF
    sd t2, 8(t3)
    li t2, (0x185000 >> 2) | 0xDF
    sd t2, 16(t3)
    la t1, g_root
    srli t1, t1, 12
    li t2, 0x8001000000000000
    or t1, t1, t2
    csrw hgatp, t1
    li t1, 8
    slli t1, t1, 60
    li t2, 1
    slli t2, t2, 44
    or t1, t1, t2
    ori s4, t1, VS1R >> 12      // vsatp 1 (ASID 1)
    li t1, 8
    slli t1, t1, 60
    li t2, 2
    slli t2, t2, 44
    or t1, t1, t2
    ori s5, t1, VS2R >> 12      // vsatp 2 (ASID 2)
    csrw vsatp, s4
    li t1, SPVP
    csrs hstatus, t1
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, ROOT >> 12
    csrw satp, t1
    sfence.vma
    hfence.gvma
    hfence.vvma
    la t1, hs_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

hs_main:
    li s1, VA_X
    // 1: alternate HS and guest views of VA_X.
    li t0, 1
    MARK
    ld a0, 0(s1)
    hlv.d a1, (s1)
    ld a2, 0(s1)
    hlv.d a3, (s1)
    TRAPS 0
    li t1, 0xAAAA
    bne a0, t1, fail
    bne a2, t1, fail
    li t1, 0xBBBB
    bne a1, t1, fail
    bne a3, t1, fail

    // 2: HSV, then HS load and HLV.
    li t0, 2
    li a4, 0x1234
    hsv.d a4, (s1)
    ld a0, 0(s1)
    hlv.d a1, (s1)
    li t1, 0xAAAA
    bne a0, t1, fail
    bne a1, a4, fail
    li t1, 0x183000
    ld a2, 0(t1)
    bne a2, a4, fail

    // 3: SPVP / vsstatus.SUM right before HLVs of a VS U page.
    li t0, 3
    li s2, VA_X + 0x1000
    li a5, SPVP
    li a6, SUM
    MARK
    csrc hstatus, a5            // HLV as VU
    hlv.d a0, (s2)
    csrs hstatus, a5            // HLV as VS, SUM=0
    li a1, 0x5555
f3a: hlv.d a1, (s2)
    csrs vsstatus, a6
    hlv.d a2, (s2)
    csrc vsstatus, a6
    TRAPS 1
    CHK 13, VA_X + 0x1000, 0, f3a, 1
    li t1, 0xCCCC
    bne a0, t1, fail
    bne a2, t1, fail
    li t1, 0x5555
    bne a1, t1, fail

    // 4: vsatp switched right before HLVs.
    li t0, 4
    csrw vsatp, s5
    hlv.d a0, (s1)
    csrw vsatp, s4
    hlv.d a1, (s1)
    csrw vsatp, s5
    hlv.d a2, (s1)
    csrw vsatp, s4
    li t1, 0xCCCC
    bne a0, t1, fail
    bne a2, t1, fail
    li t1, 0x1234
    bne a1, t1, fail

    // 5: HLVX of an execute-only VS page; HLV.W needs MXR.
    li t0, 5
    li s3, VA_X + 0x2000
    li a6, MXR
    MARK
    hlvx.wu a0, (s3)
    li a1, 0x5555
f5a: hlv.w a1, (s3)
    csrs vsstatus, a6
    hlv.w a2, (s3)
    csrc vsstatus, a6
    csrs sstatus, a6
    hlv.w a3, (s3)
    csrc sstatus, a6
    li a4, 0x5555
f5b: hlv.w a4, (s3)
    TRAPS 2
    CHK 13, VA_X + 0x2000, 0, f5b, 1
    li t1, 0xDDDD
    bne a0, t1, fail
    bne a2, t1, fail
    bne a3, t1, fail
    li t1, 0x5555
    bne a1, t1, fail
    bne a4, t1, fail

    // 6: guest-page fault, then an HS load of the same VA.
    li t0, 6
    li s6, VA_X + 0x3000
    MARK
    li a0, 0x5555
f6a: hlv.d a0, (s6)
    ld a1, 0(s6)
    TRAPS 1
    CHK 21, VA_X + 0x3000, 0x380000 >> 2, f6a, 1
    li t1, 0x5555
    bne a0, t1, fail
    li t1, 0xEEEE
    bne a1, t1, fail
    MARK
f6b: hsv.d a0, (s6)
    TRAPS 1
    CHK 23, VA_X + 0x3000, 0x380000 >> 2, f6b, 1

    // 7: vle64ff trimmed at P = VA_X + 0x5000, then HSV / HLVX of P.
    li t0, 7
    li s7, VA_X + 0x4FF0
    li s8, VA_X + 0x5000
    li t1, VA_X + 0x4000        // HS: VA_X+0x4000 -> 0x180000
    PTEW L0 + 4 * 8, 0x180000, 0xC7
    sfence.vma
    MARK
    vsetivli x0, 4, e64, m1, tu, mu
    li a4, 0x4321
    vle64ff.v v8, (s7)
    hsv.d a4, (s8)
    vsetivli x0, 4, e64, m1, tu, mu
    vle64ff.v v8, (s7)
    hlvx.wu a5, (s8)
    TRAPS 0
    li t1, 0x185000
    ld a2, 0(t1)
    bne a2, a4, fail            // HSV landed on the guest page
    bne a5, a4, fail            // HLVX read it back

pass:
    li a7, 0
    ecall
1:  j 1b
fail:
    mv a7, t0
    ecall
1:  j 1b

// M: an HS ecall ends the test with a7 (0 = pass); anything else is
// logged in m_last and skipped.
m_trap:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    csrr t1, mcause
    li t2, 9
    bne t1, t2, 1f
    li t1, EXIT
    sd a7, 0(t1)
2:  j 2b
1:  la t2, m_last
    sd t1, 0(t2)
    csrr t1, mtval
    sd t1, 8(t2)
    csrr t1, 0x34B              // mtval2
    sd t1, 16(t2)
    csrr t1, mepc
    sd t1, 24(t2)
    csrr t1, mstatus
    srli t1, t1, 38             // GVA
    andi t1, t1, 1
    sd t1, 32(t2)
    la t2, m_count
    ld t1, 0(t2)
    addi t1, t1, 1
    sd t1, 0(t2)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

    .data
    .balign 64
m_last:  .quad 0, 0, 0, 0, 0
m_count: .quad 0
stack:   .skip 256
stack_top:
m_stack: .skip 256
m_stack_top:
    .balign 16384
g_root:  .skip 16384
g_l1:    .skip 4096
g_l0:    .skip 4096
