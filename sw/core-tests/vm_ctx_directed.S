// Translation context and precise page faults (#53 review: the
// FPGA_TIMING data translation is looked up in EX and registered).
// Each change of the data-translation context is followed at once
// by an access that depends on it, and every fault is checked for
// cause, tval and epc, with the faulting access writing nothing and
// the instructions after it not executed:
//  1-3: csrw satp between two address spaces (ASID 1 and 2, so no
//       SFENCE is needed): the very next load/store uses the new
//       table, a VA mapped only in the other space faults (13/15),
//       and a switch before every load alternates correctly.
//  4-5: SUM and MXR set or cleared right before a load or store.
//  6-7: load then store, AMO and LR/SC on a D=0 page (A/D update
//       walk); store to an A=0 page.
//  8-9: a faulting store/load followed by a register write, a store,
//       an fflags write, an I/O read and an AMO: none happens (the
//       I/O read counter shows it), sepc/stval exact; also with an
//       older TLB-missing load right in front of the faulting one.
//  10-11: M-mode MPRV and MPP toggled right before loads; an MPRV
//       load faulting to M (mcause/mtval/mepc).
//  12: a PMP change right before an MPRV load: access fault 5.
// M builds the tables; 1-9 run in S with page faults delegated.
// t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start

.equ EXIT,     0x10000000
.equ ROOT_A,   0x100000
.equ L1_A,     0x101000
.equ L0_A,     0x102000
.equ ROOT_B,   0x103000
.equ L1_B,     0x104000
.equ L0_B,     0x105000
.equ VA_X,     0x200000         // A: PA 0x180000 RW   B: PA 0x188000 RW
.equ VA_RO,    0x201000         // PA 0x181000 R
.equ VA_XO,    0x202000         // PA 0x182000 X only
.equ VA_U,     0x203000         // PA 0x183000 RW U
.equ VA_D0,    0x204000         // PA 0x184000 RW, A=1 D=0
.equ VA_A0,    0x205000         // PA 0x185000 RW, A=0 D=0
.equ VA_OA,    0x206000         // A only: PA 0x186000 RW
.equ VA_OB,    0x207000         // B only: PA 0x187000 RW
.equ VA_DEV,   0x208000         // PA 0x20000000 (I/O read counter)
.equ SUM,      (1 << 18)
.equ MXR,      (1 << 19)
.equ MPRV,     (1 << 17)

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm

// Last S trap must be (cause, tval register, epc label).
.macro CHK_S cause, tvalreg, epc
    la t1, s_cause
    ld t2, 0(t1)
    li t3, \cause
    bne t2, t3, fail_s
    ld t2, 8(t1)
    bne t2, \tvalreg, fail_s
    ld t2, 16(t1)
    la t3, \epc
    bne t2, t3, fail_s
.endm

.macro CHK_M cause, tvalreg, epc
    la t1, m_cause
    ld t2, 0(t1)
    li t3, \cause
    bne t2, t3, fail
    ld t2, 8(t1)
    bne t2, \tvalreg, fail
    ld t2, 16(t1)
    la t3, \epc
    bne t2, t3, fail
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
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, (1 << 13)            // FS = Initial (fflags in test 8)
    csrs mstatus, t1
    // Zero the six table pages.
    li t1, ROOT_A
    li t2, ROOT_A + 0x6000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Flags: V1 R2 W4 X8 U16 G32 A64 D128.
    PTEW ROOT_A, 0, L1_A, 0x01
    PTEW L1_A, 0, 0x000000, 0xCF        // 2M identity RWX
    PTEW L1_A, 1, L0_A, 0x01
    PTEW ROOT_B, 0, L1_B, 0x01
    PTEW L1_B, 0, 0x000000, 0xCF
    PTEW L1_B, 1, L0_B, 0x01
    PTEW L0_A, 0, 0x180000, 0xC7
    PTEW L0_A, 1, 0x181000, 0x43
    PTEW L0_A, 2, 0x182000, 0x49
    PTEW L0_A, 3, 0x183000, 0xD7
    PTEW L0_A, 4, 0x184000, 0x47
    PTEW L0_A, 5, 0x185000, 0x07
    PTEW L0_A, 6, 0x186000, 0xC7
    PTEW L0_A, 8, 0x20000000, 0xC7
    PTEW L0_B, 0, 0x188000, 0xC7
    PTEW L0_B, 7, 0x187000, 0xC7
    PTEW L0_B, 8, 0x20000000, 0xC7
    // Page contents.
    li t1, 0x180000
    li t2, 0xA0A0
    sd t2, 0(t1)
    sd x0, 8(t1)
    li t1, 0x188000
    li t2, 0xB0B0
    sd t2, 0(t1)
    sd x0, 8(t1)
    li t1, 0x181000
    li t2, 0x4040
    sd t2, 0(t1)
    li t1, 0x182000
    li t2, 0x1234
    sd t2, 0(t1)
    li t1, 0x183000
    li t2, 0xD0D0
    sd t2, 0(t1)
    li t1, 0x186000
    li t2, 0xAAAA
    sd t2, 0(t1)
    li t1, 0x187000
    li t2, 0xBBBB
    sd t2, 0(t1)
    li t1, 0x200000             // untranslated PA behind VA_X
    li t2, 0xCCCC
    sd t2, 0(t1)
    la t1, s_log
    la t2, s_log_ptr
    sd t1, 0(t2)
    la t1, m_log
    la t2, m_log_ptr
    sd t1, 0(t2)
    // Delegate page faults and U ecalls to S; satp = A.
    li t1, 0xB100
    csrw medeleg, t1
    li t1, 8
    slli t1, t1, 60
    li t2, 1
    slli t2, t2, 44
    or t1, t1, t2
    ori t1, t1, ROOT_A >> 12
    la t2, satp_a
    sd t1, 0(t2)
    li t1, 8
    slli t1, t1, 60
    li t2, 2
    slli t2, t2, 44
    or t1, t1, t2
    ori t1, t1, ROOT_B >> 12
    la t2, satp_b
    sd t1, 0(t2)
    la t2, satp_a
    ld t1, 0(t2)
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

// ---- S-mode body ------------------------------------------------
s_main:
    la t1, satp_a
    ld s4, 0(t1)
    la t1, satp_b
    ld s5, 0(t1)
    // 1: switch, then an immediate load and store.
    li t0, 1
    li a1, VA_X
    ld a3, 0(a1)                // warm the ASID 1 entry
    li a2, 0xA0A0
    bne a3, a2, fail_s
    csrw satp, s5
    ld a3, 0(a1)
    li a2, 0xB0B0
    bne a3, a2, fail_s
    csrw satp, s4
    ld a3, 0(a1)
    li a2, 0xA0A0
    bne a3, a2, fail_s
    csrw satp, s5
    sd s5, 8(a1)                // B's page
    csrw satp, s4
    ld a3, 8(a1)                // A's page still 0
    bnez a3, fail_s
    li a1, 0x188008             // identity alias of B's page
    ld a3, 0(a1)
    bne a3, s5, fail_s
    li a1, 0x180008
    ld a3, 0(a1)
    bnez a3, fail_s

    // 2: a VA mapped only in the other space faults right after
    //    the switch; rd keeps its value.
    li t0, 2
    li a1, VA_OA
    li a3, 0x5555
    csrw satp, s5
f2a: ld a3, 0(a1)
    csrw satp, s4
    li a2, 0x5555
    bne a3, a2, fail_s
    CHK_S 13, a1, f2a
    ld a3, 0(a1)                // fine in A
    li a2, 0xAAAA
    bne a3, a2, fail_s
    li a1, VA_OB
    li a2, 0x7777
f2b: sd a2, 0(a1)               // A: unmapped, 15
    CHK_S 15, a1, f2b
    csrw satp, s5
    ld a3, 0(a1)
    csrw satp, s4
    li a2, 0xBBBB
    bne a3, a2, fail_s          // the faulting store wrote nothing

    // 3: a switch before every load.
    li t0, 3
    li a1, VA_X
    csrw satp, s5
    ld a3, 0(a1)
    csrw satp, s4
    ld a4, 0(a1)
    csrw satp, s5
    ld a5, 0(a1)
    csrw satp, s4
    ld a6, 0(a1)
    li a2, 0xB0B0
    bne a3, a2, fail_s
    bne a5, a2, fail_s
    li a2, 0xA0A0
    bne a4, a2, fail_s
    bne a6, a2, fail_s

    // 4: SUM right before U-page accesses.
    li t0, 4
    li a1, VA_U
    li a4, SUM
    li a3, 0x5555
f4a: ld a3, 0(a1)
    li a2, 0x5555
    bne a3, a2, fail_s
    CHK_S 13, a1, f4a
    csrs sstatus, a4
    ld a3, 0(a1)
    li a2, 0xD0D0
    bne a3, a2, fail_s
    csrc sstatus, a4
    addi a5, a1, 8
f4b: sd a2, 8(a1)
    CHK_S 15, a5, f4b
    csrs sstatus, a4
    sd a2, 16(a1)
    csrc sstatus, a4
    addi a5, a1, 16
f4c: ld a3, 16(a1)
    CHK_S 13, a5, f4c
    csrr a5, sstatus
    or a6, a5, a4
    csrw sstatus, a6
    ld a3, 16(a1)
    csrw sstatus, a5
    li a2, 0xD0D0
    bne a3, a2, fail_s
f4d: ld a3, 8(a1)
    addi a5, a1, 8
    CHK_S 13, a5, f4d
    li a1, 0x183008             // the faulting store wrote nothing
    ld a3, 0(a1)
    bnez a3, fail_s

    // 5: MXR right before X-only page loads (stores still fault).
    li t0, 5
    li a1, VA_XO
    li a4, MXR
f5a: lw a3, 0(a1)
    CHK_S 13, a1, f5a
    csrs sstatus, a4
    lw a3, 0(a1)
    li a2, 0x1234
    bne a3, a2, fail_s
f5b: sw a2, 0(a1)
    CHK_S 15, a1, f5b
    csrc sstatus, a4
    li a3, 0x5555
f5c: lw a3, 0(a1)
    li a2, 0x5555
    bne a3, a2, fail_s
    CHK_S 13, a1, f5c

    // 6: D=0 page: load, then store / AMO / LR-SC right after.
    li t0, 6
    li a1, VA_D0
    li a5, L0_A + 4 * 8
    ld a3, 0(a1)
    li a2, 0xD00D
    sd a2, 0(a1)
    ld a3, 0(a1)
    bne a3, a2, fail_s
    ld a6, 0(a5)
    andi a6, a6, 0x80
    beqz a6, fail_s
    li a6, 0x184000
    ld a3, 0(a6)
    bne a3, a2, fail_s
    ld a6, 0(a5)                // D = 0 again
    andi a6, a6, -129
    sd a6, 0(a5)
    sfence.vma
    ld a3, 0(a1)                // TLB entry with D=0
    li a2, 5
    amoadd.d a3, a2, (a1)
    li a2, 0xD00D
    bne a3, a2, fail_s
    ld a3, 0(a1)
    li a2, 0xD012
    bne a3, a2, fail_s
    ld a6, 0(a5)
    andi a6, a6, 0x80
    beqz a6, fail_s
    ld a6, 0(a5)
    andi a6, a6, -129
    sd a6, 0(a5)
    sfence.vma
    lr.d a3, (a1)
    li a2, 0xD012
    bne a3, a2, fail_s
    li a2, 0x5C5C
    sc.d a4, a2, (a1)
    la a6, sc_result
    sd a4, 0(a6)
    ld a3, 0(a1)
    bnez a4, 1f
    bne a3, a2, fail_s          // SC succeeded: value stored, D set
    ld a6, 0(a5)
    andi a6, a6, 0x80
    beqz a6, fail_s
    j 2f
1:  li a2, 0xD012               // SC failed: nothing stored
    bne a3, a2, fail_s
2:
    // 7: store to an A=0 page sets A and D.
    li t0, 7
    li a1, VA_A0
    li a5, L0_A + 5 * 8
    li a2, 0xA00A
    sd a2, 0(a1)
    ld a3, 0(a1)
    bne a3, a2, fail_s
    ld a6, 0(a5)
    andi a6, a6, 0xC0
    li a3, 0xC0
    bne a6, a3, fail_s

    // 8: a faulting store; nothing after it happens.
    li t0, 8
    csrwi fflags, 0
    li s3, 0
    la a4, flag8
    sd x0, 0(a4)
    li s6, VA_DEV
    ld s7, 0(s6)                // I/O read counter (post-increment)
    la a5, after8
    la a6, s_resume
    sd a5, 0(a6)
    li a1, VA_RO
    li a2, 0x9999
f8: sd a2, 0(a1)
    addi s3, s3, 1
    sd s3, 0(a4)
    csrwi fflags, 0x1f
    ld s8, 0(s6)
    amoadd.d x0, a2, (a4)
    j fail_s
after8:
    CHK_S 15, a1, f8
    bnez s3, fail_s
    ld a3, 0(a4)
    bnez a3, fail_s
    csrr a3, fflags
    bnez a3, fail_s
    ld s8, 0(s6)
    addi s7, s7, 1
    bne s8, s7, fail_s          // exactly one read since
    li a1, 0x181000
    ld a3, 0(a1)
    li a2, 0x4040
    bne a3, a2, fail_s

    // 9: a faulting load (walk, then fault) after a TLB-missing
    //    load; the I/O read and store after it do not happen.
    li t0, 9
    sfence.vma
    la a5, after9
    la a6, s_resume
    sd a5, 0(a6)
    ld s7, 0(s6)
    li a1, VA_OB
    li a7, VA_X
    li a3, 0x5555
    ld a2, 0(a7)                // walks (TLB flushed)
f9: ld a3, 0(a1)                // walks, faults
    ld s8, 0(s6)
    sd s7, 0(a4)
    j fail_s
after9:
    CHK_S 13, a1, f9
    li a6, 0x5555
    bne a3, a6, fail_s
    li a6, 0xA0A0
    bne a2, a6, fail_s
    ld a3, 0(a4)
    bnez a3, fail_s
    ld s8, 0(s6)
    addi s7, s7, 1
    bne s8, s7, fail_s
    // 9b: two faulting loads to the same VA back to back; the
    //     second never runs (one trap only).
    la t1, s_count
    ld s9, 0(t1)
    la a5, after9b
    la a6, s_resume
    sd a5, 0(a6)
f9b: ld a3, 0(a1)
    ld a3, 0(a1)
    j fail_s
after9b:
    CHK_S 13, a1, f9b
    la t1, s_count
    ld t2, 0(t1)
    addi s9, s9, 1
    bne t2, s9, fail_s

    // Hand back to M.
    la a1, m_main
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
    j fail_s

// ---- M-mode MPRV / PMP ------------------------------------------
m_main:
    // 10: MPRV toggled right before loads (MPP = S, satp = A).
    li t0, 10
    li a1, VA_X
    li a4, MPRV
    li a2, (3 << 11)
    csrc mstatus, a2
    li a2, (1 << 11)
    csrs mstatus, a2
    csrs mstatus, a4
    ld a3, 0(a1)                // translated
    csrc mstatus, a4
    ld a5, 0(a1)                // physical
    csrs mstatus, a4
    ld a6, 0(a1)
    csrc mstatus, a4
    li a2, 0xA0A0
    bne a3, a2, fail
    bne a6, a2, fail
    li a2, 0xCCCC
    bne a5, a2, fail
    // 11: MPP changed under MPRV right before loads.
    li t0, 11
    li a2, (3 << 11)
    csrc mstatus, a2            // MPP = U
    csrs mstatus, a4
    li a3, 0x5555
f11: ld a3, 0(a1)               // U on an S page: 13 to M
    li a2, (1 << 11)
    csrs mstatus, a2            // MPP = S (MPRV survived the trap)
    ld a5, 0(a1)
    csrc mstatus, a4
    CHK_M 13, a1, f11
    li a2, 0x5555
    bne a3, a2, fail
    li a2, 0xA0A0
    bne a5, a2, fail
    // 12: PMP denial set right before an MPRV load (access 5).
    li t0, 12
    li a2, (0x180000 >> 2) | 0x1ff     // NAPOT 4K at PA 0x180000
    csrw pmpaddr0, a2
    li a2, (3 << 11)
    csrc mstatus, a2
    li a2, (1 << 11)
    csrs mstatus, a2
    csrs mstatus, a4
    li a2, 0x18                 // entry 0 NAPOT, no permissions
    csrw pmpcfg0, a2
f12: ld a3, 0(a1)
    li a2, (1 << 11)
    csrs mstatus, a2            // MPP = S again (the trap's mret set U)
    csrw pmpcfg0, x0
    ld a5, 0(a1)
    csrc mstatus, a4
    CHK_M 5, a1, f12
    li a2, 0xA0A0
    bne a5, a2, fail

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

// ---- Handlers ---------------------------------------------------
// M: log (cause, tval, epc); an S ecall with resume_addr set lands
// there in M, anything else skips the trapping instruction.
handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    sd t3, 16(sp)
    la t1, m_cause
    csrr t2, mcause
    sd t2, 0(t1)
    csrr t3, mtval
    sd t3, 8(t1)
    csrr t3, mepc
    sd t3, 16(t1)
    la t1, m_log_ptr
    ld t3, 0(t1)
    sd t2, 0(t3)
    csrr t2, mtval
    sd t2, 8(t3)
    csrr t2, mepc
    sd t2, 16(t3)
    addi t3, t3, 24
    sd t3, 0(t1)
    la t2, resume_addr
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw mepc, t1
    li t1, (3 << 11)
    csrs mstatus, t1
    j 2f
1:  csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    ld t3, 16(sp)
    csrrw sp, mscratch, sp
    mret

// S: log, count, then resume at s_resume (if set) or skip.
handler_s:
    csrrw sp, sscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    sd t3, 16(sp)
    la t1, s_cause
    csrr t2, scause
    sd t2, 0(t1)
    csrr t3, stval
    sd t3, 8(t1)
    csrr t3, sepc
    sd t3, 16(t1)
    la t1, s_log_ptr
    ld t3, 0(t1)
    sd t2, 0(t3)
    csrr t2, stval
    sd t2, 8(t3)
    csrr t2, sepc
    sd t2, 16(t3)
    addi t3, t3, 24
    sd t3, 0(t1)
    la t1, s_count
    ld t2, 0(t1)
    addi t2, t2, 1
    sd t2, 0(t1)
    la t2, s_resume
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
satp_a:      .quad 0
satp_b:      .quad 0
m_cause:     .quad 0, 0, 0
s_cause:     .quad 0, 0, 0
resume_addr: .quad 0
s_resume:    .quad 0
s_count:     .quad 0
flag8:       .quad 0
sc_result:   .quad 0
s_log_ptr:   .quad 0
m_log_ptr:   .quad 0
    .align 6
s_log:       .skip 24 * 64
m_log:       .skip 24 * 16
    .align 4
main_stack:  .skip 2048
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
s_trap_stack: .skip 1024
s_trap_stack_top:
