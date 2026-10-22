// Translation-context changes back to back with memory accesses
// (#53 review): every CSR write or xRET that changes the data
// translation context (sstatus.SUM/MXR, satp ASID/root/MODE,
// mstatus.MPRV/MPP) is immediately followed by the access that
// depends on it, and every access immediately followed by the
// write that would change its verdict. Also: address operands
// forwarded into the access (EX/MEM, MEM/WB, load-use), LR/SC and
// AMOs across TLB refills, A/D updates, and SFENCE adjacency.
// With FPGA_TIMING the data TLB lookup happens in EX with EX's
// context, so these are the cases where a stale context would show.
// M builds the tables; S runs the tests with page faults delegated
// (the S handler records cause/tval and skips the instruction).
// t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start

.equ PGROOT,  0x100000          // ASID 1 root
.equ PGL1,    0x101000
.equ PGL0,    0x102000
.equ PGROOT2, 0x103000          // ASID 2 root
.equ PGL1_2,  0x104000
.equ PGL0_2,  0x105000
.equ VA_A,    0x200000          // -> 0x180000 RW
.equ VA_U,    0x201000          // -> 0x181000 RWX U
.equ VA_X,    0x202000          // -> 0x182000 X only
.equ VA_RO,   0x203000          // -> 0x183000 R only
.equ VA_AD,   0x204000          // -> 0x184000 RW, A/D clear
.equ VA_S,    0x205000          // ASID1 -> 0x185000, ASID2 -> 0x186000 (non-global)
.equ VA_ALS,  0x206000          // -> 0x180000 RW (alias of VA_A)
.equ VA_EV,   0x210000          // 48 eviction pages -> 0x190000..
.equ EXIT,    0x10000000
.equ SUM,     (1 << 18)
.equ MXR,     (1 << 19)
.equ MPRV,    (1 << 17)

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm
// Check the last delegated trap (and clear it).
.macro CHK_CAUSE c
    la t2, s_cause
    ld t1, 0(t2)
    li t3, \c
    bne t1, t3, fail
    sd x0, 0(t2)
.endm
.macro CHK_TVAL v
    la t2, s_tval
    ld t1, 0(t2)
    li t3, \v
    bne t1, t3, fail
.endm
.macro CHK_NOTRAP
    la t2, s_cause
    ld t1, 0(t2)
    bnez t1, fail
.endm
.macro CHK reg, v
    li t3, \v
    bne \reg, t3, fail
.endm

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw sscratch, t1
    la t1, mtrap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_s
    csrw stvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // Zero the six table pages.
    li t1, PGROOT
    li t2, PGROOT + 0x6000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Flags: V1 R2 W4 X8 U16 G32 A64 D128.
    // ASID 1: identity 2M RWX global (code, data, tables), exit
    // device page, and the 4K test pages.
    PTEW PGROOT, 0, PGL1, 0x01
    PTEW PGL1, 0, 0x000000, 0xEF
    PTEW PGL1, 1, PGL0, 0x01
    PTEW PGL1, 128, EXIT, 0xE7
    PTEW PGL0, 0, 0x180000, 0xC7
    PTEW PGL0, 1, 0x181000, 0xDF
    PTEW PGL0, 2, 0x182000, 0xC9
    PTEW PGL0, 3, 0x183000, 0xC3
    PTEW PGL0, 4, 0x184000, 0x07
    PTEW PGL0, 5, 0x185000, 0xC7
    PTEW PGL0, 6, 0x180000, 0xC7
    // ASID 2: same globals, VA_S -> 0x186000, VA_A unmapped.
    PTEW PGROOT2, 0, PGL1_2, 0x01
    PTEW PGL1_2, 0, 0x000000, 0xEF
    PTEW PGL1_2, 1, PGL0_2, 0x01
    PTEW PGL1_2, 128, EXIT, 0xE7
    PTEW PGL0_2, 5, 0x186000, 0xC7
    PTEW PGL0_2, 1, 0x181000, 0xDF
    // Eviction pages: VA_EV + i*4K -> 0x190000 + i*4K, value i+1.
    li a0, 0
    li a1, PGL0 + 16 * 8
    li a2, (0x190000 >> 2) | 0xC7
    li a3, 0x190000
1:  sd a2, 0(a1)
    addi a4, a0, 1
    sd a4, 0(a3)
    addi a0, a0, 1
    addi a1, a1, 8
    li a4, (0x1000 >> 2)
    add a2, a2, a4
    li a4, 0x1000
    add a3, a3, a4
    li a4, 48
    blt a0, a4, 1b
    // Payload values.
    li t1, 0x180000
    li t2, 0xA001
    sd t2, 0(t1)
    li t2, VA_U + 0x10
    sd t2, 8(t1)
    li t2, VA_S
    sd t2, 16(t1)
    li t1, 0x181000
    li t2, 0x0001
    sd t2, 0(t1)
    li t2, 0xB0B0
    sd t2, 0x10(t1)
    li t2, VA_A
    sd t2, 0x18(t1)
    li t1, 0x182000
    li t2, 0x00008067           // ret
    sw t2, 0(t1)
    li t1, 0x183000
    li t2, 0xC0C0
    sd t2, 0(t1)
    li t1, 0x185000
    li t2, 0x1111
    sd t2, 0(t1)
    li t1, 0x186000
    li t2, 0x2222
    sd t2, 0(t1)
    // Delegate page faults and U ecalls to S; Sv39 ASID 1.
    li t1, (1 << 8) | (1 << 12) | (1 << 13) | (1 << 15)
    csrw medeleg, t1
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

// ---- S-mode tests ----------------------------------------------
s_main:
    // 1: SUM set then immediate U-page load/store; clear then fault.
    li t0, 1
    li a1, VA_U
    li a4, SUM
    csrs sstatus, a4
    ld a3, 0(a1)
    CHK_NOTRAP
    CHK a3, 1
    csrc sstatus, a4
    ld a3, 0(a1)
    CHK_CAUSE 13
    CHK_TVAL VA_U
    csrs sstatus, a4
    sd a4, 8(a1)
    CHK_NOTRAP
    csrc sstatus, a4
    sd a4, 8(a1)
    CHK_CAUSE 15
    CHK_TVAL VA_U + 8
    // 2: the access just before the CSR write keeps the old context.
    li t0, 2
    csrs sstatus, a4
    nop
    nop
    li a3, 0
    ld a3, 0(a1)
    csrc sstatus, a4
    CHK_NOTRAP
    CHK a3, 1
    ld a3, 0(a1)
    CHK_CAUSE 13
    // 3: same with a TLB miss on the older access (it parks in
    //    MEM while the CSR write waits in EX).
    li t0, 3
    csrs sstatus, a4
    sfence.vma
    li a3, 0
    ld a3, 0(a1)
    csrc sstatus, a4
    ld a5, 0(a1)
    CHK_CAUSE 13
    CHK a3, 1
    sfence.vma
    csrs sstatus, a4
    li a3, 0
    ld a3, 0(a1)                // miss, SUM=1
    csrc sstatus, a4            // waits for the parked load
    li a2, VA_A
    ld a5, 0(a2)                // S page: fine either way
    CHK_NOTRAP
    CHK a3, 1
    CHK a5, 0xA001
    // 4: MXR adjacency on an X-only page.
    li t0, 4
    li a1, VA_X
    li a4, MXR
    csrs sstatus, a4
    lw a3, 0(a1)
    CHK_NOTRAP
    CHK a3, 0x00008067
    csrc sstatus, a4
    lw a3, 0(a1)
    CHK_CAUSE 13
    sfence.vma
    csrs sstatus, a4
    lw a3, 0(a1)                // miss + walk with MXR=1
    csrc sstatus, a4
    lw a5, 0(a1)                // TLB hit with MXR=0: faults
    CHK_CAUSE 13
    CHK a3, 0x00008067
    // 5: satp ASID switch: the same VA in two address spaces, the
    //    access right after the write.
    li t0, 5
    li a1, VA_S
    la a6, satp1
    ld a6, 0(a6)
    la a7, satp2
    ld a7, 0(a7)
    ld a3, 0(a1)
    CHK a3, 0x1111
    csrw satp, a7
    ld a3, 0(a1)
    CHK a3, 0x2222
    csrw satp, a6
    ld a3, 0(a1)
    CHK a3, 0x1111
    csrw satp, a7
    li a2, 0x2233
    sd a2, 0(a1)
    csrw satp, a6
    ld a3, 0(a1)
    CHK a3, 0x1111
    csrw satp, a7
    ld a3, 0(a1)
    CHK a3, 0x2233
    // VA_A is unmapped in ASID 2.
    li a2, VA_A
    ld a3, 0(a2)
    CHK_CAUSE 13
    csrw satp, a6
    ld a3, 0(a2)
    CHK_NOTRAP
    CHK a3, 0xA001
    // older access with a miss, then the switch
    csrw satp, a7
    sfence.vma
    ld a3, 0(a1)                // miss in ASID 2
    csrw satp, a6
    ld a5, 0(a1)                // ASID 1
    CHK a3, 0x2233
    CHK a5, 0x1111
    // 6: satp MODE switch (Sv39 <-> Bare) with the access adjacent.
    li t0, 6
    li a1, VA_S
    csrw satp, x0
    ld a3, 0(a1)                // Bare: PA 0x205000 (zero)
    csrw satp, a6
    ld a5, 0(a1)
    CHK a3, 0
    CHK a5, 0x1111
    li a2, 0x185000
    csrw satp, x0
    ld a3, 0(a2)
    CHK a3, 0x1111
    csrw satp, a6
    sfence.vma
    // 7: address operands forwarded into the access, across pages.
    li t0, 7
    li a1, VA_A
    addi a1, a1, 8
    ld a2, 0(a1)                // EX/MEM forward: pointer VA_U+0x10
    li a4, SUM
    csrs sstatus, a4
    ld a3, 0(a2)                // load-use into the address
    CHK a3, 0xB0B0
    ld a3, 8(a2)                // (VA_U + 0x18) -> VA_A
    nop
    ld a5, 0(a3)                // MEM/WB forward into the address
    CHK a5, 0xA001
    sfence.vma
    li a1, VA_A
    ld a2, 8(a1)                // miss
    ld a3, 0(a2)                // miss, load-use address
    ld a5, 8(a2)                // hit
    ld a5, 0(a5)                // load-use back to VA_A
    CHK a3, 0xB0B0
    CHK a5, 0xA001
    // store whose address is a load result
    ld a2, 8(a1)
    li a3, 0x5150
    sd a3, 0x20(a2)
    ld a5, 0x20(a2)
    CHK a5, 0x5150
    // AMO whose address is just computed
    li a2, VA_U
    addi a2, a2, 0x28
    sd x0, 0(a2)
    li a3, 7
    addi a2, a2, 0
    amoadd.d a5, a3, (a2)
    amoadd.d a5, a3, (a2)
    ld a3, 0(a2)
    CHK a3, 14
    CHK a5, 7
    csrc sstatus, a4
    // 8: LR/SC and AMO across a TLB refill and an alias VA.
    li t0, 8
    // (an interrupt between LR and SC may fail the SC: retry)
    li a1, VA_A
1:  lr.d a3, (a1)
    CHK a3, 0xA001
    jal evict
    li a2, 0xA002
    sc.d a5, a2, (a1)
    bnez a5, 1b
    ld a3, 0(a1)
    CHK a3, 0xA002
    li a1, VA_A
1:  lr.d a3, (a1)
    li a2, VA_ALS               // same PA, other VA (and TLB entry)
    li a3, 0xA001
    sc.d a5, a3, (a2)
    bnez a5, 1b
    ld a3, 0(a1)
    CHK a3, 0xA001
    // SC/AMO to a read-only page fault (15); LR is a read.
    li a1, VA_RO
    lr.d a3, (a1)
    CHK_NOTRAP
    CHK a3, 0xC0C0
    sc.d a5, a3, (a1)
    CHK_CAUSE 15
    CHK_TVAL VA_RO
    amoswap.d a5, a3, (a1)
    CHK_CAUSE 15
    sfence.vma
    amoor.d a5, a3, (a1)        // miss, then fault
    CHK_CAUSE 15
    ld a3, 0(a1)
    CHK a3, 0xC0C0
    // 9: A/D updates: a store sets A and D, then a load after a
    //    cleared PTE sets A only, then a store re-walks for D.
    li t0, 9
    li a1, VA_AD
    li a2, 0xAD01
    sd a2, 0(a1)
    li a5, PGL0 + 4 * 8
    ld a3, 0(a5)
    andi a3, a3, 0xC0
    CHK a3, 0xC0
    ld a3, 0(a5)
    andi a3, a3, -193
    sd a3, 0(a5)
    sfence.vma
    ld a3, 0(a1)
    CHK a3, 0xAD01
    ld a3, 0(a5)
    andi a3, a3, 0xC0
    CHK a3, 0x40
    li a2, 0xAD02
    sd a2, 0(a1)                // D=0 in the TLB: re-walk for D
    ld a3, 0(a5)
    andi a3, a3, 0xC0
    CHK a3, 0xC0
    ld a3, 0(a1)
    CHK a3, 0xAD02
    // AMO on a page with D clear sets D
    ld a3, 0(a5)
    andi a3, a3, -129
    sd a3, 0(a5)
    sfence.vma
    li a2, 1
    amoadd.d a3, a2, (a1)
    CHK a3, 0xAD02
    ld a3, 0(a5)
    andi a3, a3, 0xC0
    CHK a3, 0xC0
    // 10: SFENCE adjacency: remap VA_S, stale until the SFENCE,
    //     the access right after it sees the new PTE.
    li t0, 10
    li a1, VA_S
    ld a3, 0(a1)
    CHK a3, 0x1111
    li a5, PGL0 + 5 * 8
    li a2, (0x186000 >> 2) | 0xC7
    sd a2, 0(a5)
    ld a3, 0(a1)
    CHK a3, 0x1111              // stale
    sfence.vma
    ld a3, 0(a1)
    CHK a3, 0x2233
    li a2, (0x185000 >> 2) | 0xC7
    sd a2, 0(a5)
    sfence.vma a1, x0
    ld a3, 0(a1)
    CHK a3, 0x1111
    // 11: back-to-back misses to different pages (walk after walk,
    //     each fill landing while the next access waits).
    li t0, 11
    sfence.vma
    li a1, VA_EV
    li a2, VA_EV + 0x1000
    li a5, VA_EV + 0x2000
    li a6, VA_EV + 0x3000
    ld a3, 0(a1)
    ld a4, 0(a2)
    ld a7, 0(a5)
    ld s2, 0(a6)
    add a3, a3, a4
    add a3, a3, a7
    add a3, a3, s2
    CHK a3, 10
    sd a3, 8(a6)
    sd a3, 8(a5)
    ld a4, 8(a6)
    ld a7, 8(a5)
    add a4, a4, a7
    CHK a4, 20
    // 12: non-canonical and unmapped VAs right after a fill.
    li t0, 12
    sfence.vma
    li a1, VA_A
    li a2, 1
    slli a2, a2, 39
    ld a3, 0(a1)                // miss + fill
    ld a5, 0(a2)                // non-canonical: 13
    CHK_CAUSE 13
    CHK_TVAL 0x8000000000
    li a2, 0x40000000
    sd a3, 0(a2)                // unmapped: 15
    CHK_CAUSE 15
    CHK_TVAL 0x40000000
    // 13: SRET to U whose first instruction accesses an S page
    //     (fault) and then a U page (fine); the U code ecalls back.
    li t0, 13
    la a1, s_after_u
    la a2, s_resume
    sd a1, 0(a2)
    li a1, VA_U + 0x800
    la a2, u_code
    la a5, u_code_end
    li a6, 0x181800
1:  lw a3, 0(a2)
    sw a3, 0(a6)
    addi a2, a2, 4
    addi a6, a6, 4
    blt a2, a5, 1b
    fence.i
    csrw sepc, a1
    li a1, (1 << 8)
    csrc sstatus, a1
    li a2, VA_A
    li a1, VA_U
    sret
s_after_u:
    la t2, s_ucause
    ld t1, 0(t2)
    CHK t1, 13
    la t2, s_utval
    ld t1, 0(t2)
    CHK t1, VA_A
    CHK a3, 1
    // 14: M-mode MPRV/MPP adjacency.
    li t0, 14
    la a1, m_main
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
    j fail

u_code:
    ld a3, 0(a2)                // S page from U: 13
    ld a3, 0(a1)                // U page: 1
    ecall
1:  j 1b
u_code_end:

// Touch the 48 eviction pages (32-entry TLB), sum must be 1176.
evict:
    li a5, VA_EV
    li a6, 0
    li a7, 48
    li s2, 0
1:  ld s3, 0(a5)
    add s2, s2, s3
    li s3, 0x1000
    add a5, a5, s3
    addi a6, a6, 1
    blt a6, a7, 1b
    li s3, 1176
    bne s2, s3, fail
    ret

// ---- M-mode tests -------------------------------------------------
m_main:
    li t0, 14
    li a1, VA_A
    li a5, (3 << 11)
    csrc mstatus, a5
    li a5, (1 << 11)            // MPP = S
    csrs mstatus, a5
    li a4, MPRV
    csrs mstatus, a4
    ld a3, 0(a1)                // translated as S
    csrc mstatus, a4
    CHK a3, 0xA001
    li a2, 0x180000
    ld a3, 0(a2)                // untranslated
    CHK a3, 0xA001
    csrs mstatus, a4
    li a3, 0
    ld a3, 0(a1)                // the access before the clear
    csrc mstatus, a4
    ld a5, 0(a1)                // M, untranslated: PA 0x200000 (0)
    CHK a3, 0xA001
    CHK a5, 0
    // MPP change under MPRV=1: S -> U makes the S page fault.
    li t0, 15
    la t2, saved_cause
    sd x0, 0(t2)
    csrs mstatus, a4
    li a5, (1 << 11)
    csrc mstatus, a5            // MPP = U
    ld a3, 0(a1)                // U access to an S page: 13 (to M)
    csrc mstatus, a4            // MPRV off (MPP is U after the mret)
    la t2, saved_cause
    ld t1, 0(t2)
    CHK t1, 13
    la t2, saved_tval
    ld t1, 0(t2)
    CHK t1, VA_A
    li a5, (1 << 11)            // MPP = S again
    csrs mstatus, a5
    csrs mstatus, a4
    li a1, VA_U
    ld a3, 0(a1)                // S without SUM on a U page: 13
    csrc mstatus, a4
    la t2, saved_cause
    ld t1, 0(t2)
    CHK t1, 13
    sd x0, 0(t2)
    li a5, (3 << 11)
    csrc mstatus, a5            // MPP = U
    csrs mstatus, a4
    ld a3, 0(a1)                // U on a U page: fine
    csrc mstatus, a4
    la t2, saved_cause
    ld t1, 0(t2)
    CHK t1, 0
    CHK a3, 1

pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

// ---- Handlers ----------------------------------------------------
handler_m:
    csrrw sp, mscratch, sp
    sd t1, 8(sp)
    sd t2, 16(sp)
    csrr t1, mcause
    bltz t1, 2f                 // M timer interrupt: just return
    li t2, 9                    // ecall from S: resume in M
    beq t1, t2, 3f
    la t2, saved_cause
    sd t1, 0(t2)
    csrr t1, mtval
    la t2, saved_tval
    sd t1, 0(t2)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    j 2f
3:  la t2, resume_addr
    ld t1, 0(t2)
    beqz t1, fail
    csrw mepc, t1
    li t1, (3 << 11)
    csrs mstatus, t1
2:  ld t1, 8(sp)
    ld t2, 16(sp)
    csrrw sp, mscratch, sp
    mret

handler_s:
    csrrw sp, sscratch, sp
    sd t1, 8(sp)
    sd t2, 16(sp)
    csrr t1, scause
    li t2, 8
    beq t1, t2, 3f              // ecall from U: back to S
    csrr t2, sstatus
    andi t2, t2, 256
    beqz t2, 4f                 // U-mode fault: record separately
    la t2, s_cause
    sd t1, 0(t2)
    csrr t1, stval
    la t2, s_tval
    sd t1, 0(t2)
    j 1f
4:  la t2, s_ucause
    sd t1, 0(t2)
    csrr t1, stval
    la t2, s_utval
    sd t1, 0(t2)
1:  csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    j 2f
3:  la t2, s_resume
    ld t1, 0(t2)
    csrw sepc, t1
    li t1, (1 << 8)
    csrs sstatus, t1
2:  ld t1, 8(sp)
    ld t2, 16(sp)
    csrrw sp, sscratch, sp
    sret

    .data
    .align 3
satp1:       .quad (8 << 60) | (1 << 44) | (PGROOT >> 12)
satp2:       .quad (8 << 60) | (2 << 44) | (PGROOT2 >> 12)
saved_cause: .quad 0
saved_tval:  .quad 0
resume_addr: .quad 0
s_cause:     .quad 0
s_tval:      .quad 0
s_ucause:    .quad 0
s_utval:     .quad 0
s_resume:    .quad 0
    .align 4
main_stack:  .skip 4096
main_stack_top:
trap_stack:  .skip 4096
trap_stack_top:
mtrap_stack: .skip 1024
mtrap_stack_top:
