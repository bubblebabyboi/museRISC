// Translation context and memory ordering at instruction granularity
// (#53 review; the registered data translation looks an access up in
// EX). Every context write below is followed directly by the access
// it must affect. S-mode body under Sv39; traps go to M, which
// records mcause/mtval and skips the instruction (an ECALL from S
// ends the test: a0 = 0 pass, else fail with t0).
//  1: SUM: U-page load faults, csrs SUM + load passes, csrc SUM +
//     load (now a TLB hit) faults again.
//  2: MXR: X-only page load faults, csrs MXR + load passes, csrc
//     MXR + load faults.
//  3: store to an R-only page faults (15) and does not write; a load
//     right after it sees the old value.
//  4: store to a D=0 page, load of the same address right after it:
//     the store's re-walk sets D, the load returns the stored value.
//  5: satp ASID switch: two roots map VA_A to different pages; each
//     csrw satp is followed directly by a load of VA_A.
//  6: SFENCE.VMA after a PTE rewrite, load right after it.
//  7: LR/SC: LR then SC succeeds; LR, an aliasing store through the
//     identity map, SC fails; LR then SC to another page fails.
//  8: AMOADD on an A=0/D=0 page: A/D written, old value returned.
//  9: fault priority: misaligned load of an unmapped VA is cause 4,
//     misaligned store to an R-only page is cause 6.
// 10: (M, MPRV=1 MPP=S) a PMP write right before a translated load
//     takes effect for it: deny -> cause 5, allow -> loads. The entry
//     is NAPOT 8 bytes so it matches every byte of the ld (an NA4
//     entry matches half of it, and a partial match fails whatever
//     the permissions, #78).
    .option norvc
    .text
    .globl _start

.equ PGROOT,  0x100000
.equ PGL1,    0x101000
.equ PGL0,    0x102000
.equ PGROOT2, 0x103000
.equ PGL1B,   0x104000
.equ PGL0B,   0x105000
.equ VA_A,    0x200000          // PA 0x180000 RW   (root 2: PA 0x186000)
.equ VA_U,    0x201000          // PA 0x181000 RW U
.equ VA_X,    0x202000          // PA 0x182000 X
.equ VA_RO,   0x203000          // PA 0x183000 R
.equ VA_D0,   0x204000          // PA 0x184000 RW A=1 D=0
.equ VA_AD0,  0x205000          // PA 0x185000 RW A=0 D=0
.equ VA_P,    0x206000          // PA 0x187000 RW (PMP test)

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm
.macro WORD pa, val
    li t1, \pa
    li t2, \val
    sd t2, 0(t1)
.endm
.macro EXPECT_CAUSE c            // last trap cause == c, then clear
    la a6, trap_cause
    ld a5, 0(a6)
    li a7, \c
    bne a5, a7, fail_s
    sd x0, 0(a6)
.endm

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, PGROOT
    li t2, PGROOT + 0x6000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Flags: V1 R2 W4 X8 U16 G32 A64 D128.
    PTEW PGROOT, 0, PGL1, 0x01
    PTEW PGL1, 0, 0x000000, 0xCF
    PTEW PGL1, 1, PGL0, 0x01
    PTEW PGL0, 0, 0x180000, 0xC7
    PTEW PGL0, 1, 0x181000, 0xD7
    PTEW PGL0, 2, 0x182000, 0x49
    PTEW PGL0, 3, 0x183000, 0x43
    PTEW PGL0, 4, 0x184000, 0x47
    PTEW PGL0, 5, 0x185000, 0x07
    PTEW PGL0, 6, 0x187000, 0xC7
    PTEW PGROOT2, 0, PGL1B, 0x01
    PTEW PGL1B, 0, 0x000000, 0xCF
    PTEW PGL1B, 1, PGL0B, 0x01
    PTEW PGL0B, 0, 0x186000, 0xC7
    WORD 0x180000, 0xA1
    WORD 0x186000, 0xA2
    WORD 0x181000, 0x51
    WORD 0x182000, 0x52
    WORD 0x183000, 0x53
    WORD 0x185000, 0x55
    WORD 0x187000, 0x57
    li t1, (8 << 60) | (1 << 44) | (PGROOT >> 12)    // Sv39, ASID 1
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)               // MPP = S
    csrs mstatus, t1
    mret

// ---- S-mode body ----------------------------------------------
s_main:
    // 1: SUM.
    li t0, 1
    li a1, VA_U
    li t2, (1 << 18)
    li a3, 0
    ld a3, 0(a1)
    EXPECT_CAUSE 13
    csrs sstatus, t2
    ld a3, 0(a1)
    li a4, 0x51
    bne a3, a4, fail_s
    csrc sstatus, t2
    ld a3, 0(a1)                   // TLB hit, SUM=0 again
    EXPECT_CAUSE 13
    EXPECT_CAUSE 0

    // 2: MXR.
    li t0, 2
    li a1, VA_X
    li t2, (1 << 19)
    ld a3, 0(a1)
    EXPECT_CAUSE 13
    csrs sstatus, t2
    ld a3, 0(a1)
    li a4, 0x52
    bne a3, a4, fail_s
    csrc sstatus, t2
    li a3, 0
    ld a3, 0(a1)
    EXPECT_CAUSE 13
    bnez a3, fail_s

    // 3: store to R-only faults, does not write.
    li t0, 3
    li a1, VA_RO
    li a2, 0xBAD
    sd a2, 0(a1)
    ld a3, 0(a1)
    EXPECT_CAUSE 15
    li a4, 0x53
    bne a3, a4, fail_s

    // 4: D=0 store, then load of the same address.
    li t0, 4
    li a1, VA_D0
    li a2, 0xD0D0
    sd a2, 8(a1)
    ld a3, 8(a1)
    bne a3, a2, fail_s
    EXPECT_CAUSE 0
    li a1, PGL0 + 4 * 8
    ld a3, 0(a1)
    andi a3, a3, 0xC0
    li a4, 0xC0
    bne a3, a4, fail_s

    // 5: ASID switch, load directly after each satp write.
    li t0, 5
    li a1, VA_A
    li s2, (8 << 60) | (1 << 44) | (PGROOT >> 12)
    li s3, (8 << 60) | (2 << 44) | (PGROOT2 >> 12)
    ld a3, 0(a1)
    li a4, 0xA1
    bne a3, a4, fail_s
    csrw satp, s3
    ld a3, 0(a1)
    li a4, 0xA2
    bne a3, a4, fail_s
    csrw satp, s2
    ld a3, 0(a1)
    li a4, 0xA1
    bne a3, a4, fail_s
    csrw satp, s3
    ld a3, 0(a1)                   // both now TLB hits
    li a4, 0xA2
    bne a3, a4, fail_s
    csrw satp, s2
    EXPECT_CAUSE 0

    // 6: SFENCE after a PTE rewrite, load right after.
    li t0, 6
    li a1, VA_P
    ld a3, 0(a1)
    li a4, 0x57
    bne a3, a4, fail_s
    li a2, PGL0 + 6 * 8
    li a3, (0x180000 >> 2) | 0xC7
    sd a3, 0(a2)
    sfence.vma
    ld a3, 0(a1)
    li a4, 0xA1
    bne a3, a4, fail_s
    li a3, (0x187000 >> 2) | 0xC7
    sd a3, 0(a2)
    sfence.vma
    ld a3, 0(a1)
    li a4, 0x57
    bne a3, a4, fail_s

    // 7: LR/SC.
    li t0, 7
    li a1, VA_A + 0x40
    li a2, 0x180040                // identity alias of the same PA
    lr.d a3, (a1)
    li a4, 0x77
    sc.d a5, a4, (a1)
    bnez a5, fail_s
    ld a3, 0(a1)
    bne a3, a4, fail_s
    lr.d a3, (a1)
    sd x0, 0(a2)                   // aliasing store kills the reservation
    sc.d a5, a4, (a1)
    beqz a5, fail_s
    ld a3, 0(a1)
    bnez a3, fail_s
    lr.d a3, (a1)
    li a6, VA_D0 + 0x40
    sc.d a5, a4, (a6)              // other address: fails
    beqz a5, fail_s
    EXPECT_CAUSE 0

    // 8: AMO on an A=0/D=0 page.
    li t0, 8
    li a1, VA_AD0
    li a2, 5
    amoadd.d a3, a2, (a1)
    li a4, 0x55
    bne a3, a4, fail_s
    ld a3, 0(a1)
    li a4, 0x5A
    bne a3, a4, fail_s
    li a1, PGL0 + 5 * 8
    ld a3, 0(a1)
    andi a3, a3, 0xC0
    li a4, 0xC0
    bne a3, a4, fail_s
    EXPECT_CAUSE 0

    // 9: misaligned before page/access faults.
    li t0, 9
    li a1, 0x40000001              // unmapped and misaligned
    ld a3, 0(a1)
    EXPECT_CAUSE 4
    li a1, VA_RO + 4
    sd a2, 0(a1)                   // R-only and misaligned
    EXPECT_CAUSE 6

    // 10: PMP write right before a translated access (in M).
    li t0, 10
    li a0, 2
    ecall                          // a0 = 2: M runs test 10, returns
    EXPECT_CAUSE 0

    li a0, 0
    ecall
1:  j 1b
fail_s:
    li a0, 1
    ecall
1:  j 1b

// ---- M ------------------------------------------------------------
handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    li t1, (1 << 17)
    csrc mstatus, t1               // MPRV off in the handler
    csrr t1, mcause
    li t2, 9
    beq t1, t2, m_ecall
    la t2, trap_cause
    sd t1, 0(t2)
    csrr t1, mtval
    sd t1, 8(t2)
    j m_skip
m_ecall:
    li t1, 2
    beq a0, t1, m_test10
    li t1, 0x10000000
    beqz a0, 1f
    sd t0, 0(t1)
2:  j 2b
1:  sd x0, 0(t1)
3:  j 3b
m_test10:
    // MPRV=1, MPP=S: M's data accesses translate as S. Entry 0 is
    // NAPOT 8 bytes over PA 0x187000 (VA_P) with no permissions when
    // denying. The nested trap overwrites mepc: keep the ECALL's.
    csrr s4, mepc
    li t1, 0x187000 >> 2           // NAPOT, 8 bytes (pmpaddr[0] = 0)
    csrw pmpaddr0, t1
    li a1, VA_P
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 17) | (1 << 11)
    csrs mstatus, t1
    li t2, 0x18                    // NAPOT, no R/W/X
    csrw pmpcfg0, t2
    ld a3, 0(a1)                   // access fault (5)
    li t1, (3 << 11)               // the trap left MPRV off, MPP = U
    csrc mstatus, t1
    li t1, (1 << 17) | (1 << 11)
    csrs mstatus, t1
    li t2, 0x1b                    // NAPOT, R W
    csrw pmpcfg0, t2
    ld a4, 0(a1)                   // loads
    li t1, (1 << 17)
    csrc mstatus, t1
    csrw pmpcfg0, x0
    li t1, (3 << 11)               // MRET back to S
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    la t2, trap_cause
    ld t1, 0(t2)
    li a5, 5
    bne t1, a5, m_fail10
    ld t1, 8(t2)
    bne t1, a1, m_fail10
    sd x0, 0(t2)
    li a5, 0x57
    bne a4, a5, m_fail10
    csrw mepc, s4
    j m_skip
m_fail10:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b
m_skip:
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

    .data
    .align 3
trap_cause: .quad 0
trap_tval:  .quad 0
    .align 4
main_stack:  .skip 1024
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
