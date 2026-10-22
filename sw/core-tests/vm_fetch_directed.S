// Instruction-fetch translation and precise fetch faults (#53 review:
// the FPGA_TIMING fetch page register holds the last OK translated
// fetch page and its context). Every fetch fault is checked for
// scause, stval and sepc, and for the instructions around it
// executing exactly once or not at all:
//  1:  sret to U at an address on the S page sret itself runs from:
//      the U fetch faults (12) at once.
//  2:  U code on a U page runs; S jumping to a U page faults even
//      with SUM set.
//  3-4: a 32-bit instruction straddling into an unmapped page and
//      into a readable but non-executable page: sepc = instruction,
//      stval = second page, the two RVC ops before it ran once.
//  5:  X taken away from a page (PTE + SFENCE.VMA) after running it.
//  6:  code that takes X away from its own page: the instruction
//      after its SFENCE.VMA faults.
//  7:  a taken jump/branch at the end of a page whose next page is
//      unmapped: no fault (the speculative fetch is squashed).
//  8:  running off the end of an X page into an unmapped page.
//  9:  one VA mapped to different code in ASID 1 and 2: csrw satp
//      (no SFENCE) then a call runs the new space's code.
//  10: fetch from an A=0 page sets A.
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
.equ FP_S,     0x200000         // pg_s       S, R X
.equ FP_U,     0x201000         // pg_u       U, R X
.equ FP_STR,   0x202000         // pg_str     next page unmapped
.equ FP_STR2,  0x204000         // pg_str2    next page R only
.equ FP_Q,     0x206000         // pg_q       X removed in test 5
.equ FP_Q2,    0x207000         // pg_q2      removes its own X
.equ FP_SPEC,  0x208000         // pg_spec    next page unmapped
.equ FP_SPEC2, 0x20A000         // pg_spec2   next page unmapped
.equ FP_RUN,   0x20C000         // pg_run     next page unmapped
.equ VA_CODE,  0x20E000         // A: code_v1, B: code_v2
.equ FP_A0,    0x20F000         // pg_a0      A=0
.equ SUM,      (1 << 18)

// PTE for the page at a label.
.macro PTEL tbl, idx, label, flags
    la t1, \label
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm
.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm
// Last S trap must be (cause, tval, epc), both given as constants.
.macro CHK_S cause, tval, epc
    la t1, s_cause
    ld t2, 0(t1)
    li t3, \cause
    bne t2, t3, fail_s
    ld t2, 8(t1)
    li t3, \tval
    bne t2, t3, fail_s
    ld t2, 16(t1)
    li t3, \epc
    bne t2, t3, fail_s
.endm
.macro RESUME label
    la t1, \label
    la t2, s_resume
    sd t1, 0(t2)
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
    li t1, ROOT_A
    li t2, ROOT_A + 0x6000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Flags: V1 R2 W4 X8 U16 G32 A64 D128.
    PTEW ROOT_A, 0, L1_A, 0x01
    PTEW L1_A, 0, 0x000000, 0xCF
    PTEW L1_A, 1, L0_A, 0x01
    PTEW ROOT_B, 0, L1_B, 0x01
    PTEW L1_B, 0, 0x000000, 0xCF
    PTEW L1_B, 1, L0_B, 0x01
    PTEL L0_A, 0, pg_s, 0x4B
    PTEL L0_A, 1, pg_u, 0x5B
    PTEL L0_A, 2, pg_str, 0x4B
    PTEL L0_A, 4, pg_str2, 0x4B
    PTEL L0_A, 5, pg_str2_next, 0x43
    PTEL L0_A, 6, pg_q, 0x4B
    PTEL L0_A, 7, pg_q2, 0x4B
    PTEL L0_A, 8, pg_spec, 0x4B
    PTEL L0_A, 10, pg_spec2, 0x4B
    PTEL L0_A, 12, pg_run, 0x4B
    PTEL L0_A, 14, code_v1, 0x4B
    PTEL L0_A, 15, pg_a0, 0x0B
    PTEL L0_B, 14, code_v2, 0x4B
    la t1, s_log
    la t2, s_log_ptr
    sd t1, 0(t2)
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
    la sp, main_stack_top
    // 1: sret to U on the S page sret runs from.
    li t0, 1
    li s3, 0
    li a1, FP_S
    jalr ra, a1, 0              // plain call into the page (ret)
    RESUME after1
    li a1, FP_S + 16
    csrw sepc, a1
    li a1, (1 << 8)
    csrc sstatus, a1            // SPP = U
    li a1, FP_S + 8
    jalr x0, a1, 0              // sret on FP_S -> U at FP_S + 16
    j fail_s
after1:
    CHK_S 12, FP_S + 16, FP_S + 16
    bnez s3, fail_s

    // 2: U code on the U page; S on the U page faults (SUM set).
    li t0, 2
    RESUME after2u
    li a1, FP_U
    csrw sepc, a1
    li a1, (1 << 8)
    csrc sstatus, a1
    sret
    j fail_s
after2u:
    li a1, 1
    bne s3, a1, fail_s
    la t1, s_cause
    ld t2, 0(t1)
    li t3, 8
    bne t2, t3, fail_s
    RESUME after2s
    li a1, SUM
    csrs sstatus, a1
    li a1, FP_U
    jalr ra, a1, 0
    j fail_s
after2s:
    li a1, SUM
    csrc sstatus, a1
    CHK_S 12, FP_U, FP_U
    li a1, 1
    bne s3, a1, fail_s

    // 3: straddle into an unmapped page.
    li t0, 3
    li s3, 0
    RESUME after3
    li a1, FP_STR + 0xFFA
    jalr ra, a1, 0
    j fail_s
after3:
    CHK_S 12, FP_STR + 0x1000, FP_STR + 0xFFE
    li a1, 2
    bne s3, a1, fail_s

    // 4: straddle into a readable, non-executable page.
    li t0, 4
    li s3, 0
    RESUME after4
    li a1, FP_STR2 + 0xFFA
    jalr ra, a1, 0
    j fail_s
after4:
    CHK_S 12, FP_STR2 + 0x1000, FP_STR2 + 0xFFE
    li a1, 2
    bne s3, a1, fail_s

    // 5: run a page, take its X away, run it again.
    li t0, 5
    li s3, 0
    li a1, FP_Q
    jalr ra, a1, 0
    li a1, 1
    bne s3, a1, fail_s
    la a2, pg_q
    srli a2, a2, 2
    ori a2, a2, 0x43
    li a1, L0_A + 6 * 8
    sd a2, 0(a1)
    sfence.vma
    RESUME after5
    li a1, FP_Q
    jalr ra, a1, 0
    j fail_s
after5:
    CHK_S 12, FP_Q, FP_Q
    li a1, 1
    bne s3, a1, fail_s

    // 6: a page that takes its own X away.
    li t0, 6
    li s3, 0
    la a2, pg_q2
    srli a2, a2, 2
    ori a2, a2, 0x43
    li a1, L0_A + 7 * 8
    RESUME after6
    li a3, FP_Q2
    jalr ra, a3, 0
    j fail_s
after6:
    CHK_S 12, FP_Q2 + 8, FP_Q2 + 8
    bnez s3, fail_s

    // 7: taken jump / branch at a page end before an unmapped page.
    li t0, 7
    la t1, s_count
    ld s9, 0(t1)
    li s3, 0
    li a1, FP_SPEC + 0xFF8
    jalr ra, a1, 0
    li a1, 0x11
    bne s3, a1, fail_s
    li s3, 0
    li a1, FP_SPEC2 + 0xFF8
    jalr ra, a1, 0
    li a1, 0x11
    bne s3, a1, fail_s
    la t1, s_count
    ld t2, 0(t1)
    bne t2, s9, fail_s

    // 8: run off the end of an X page.
    li t0, 8
    li s3, 0
    RESUME after8
    li a1, FP_RUN + 0xFF8
    jalr ra, a1, 0
    j fail_s
after8:
    CHK_S 12, FP_RUN + 0x1000, FP_RUN + 0x1000
    li a1, 2
    bne s3, a1, fail_s

    // 9: one VA, two address spaces.
    li t0, 9
    la t1, satp_a
    ld s4, 0(t1)
    la t1, satp_b
    ld s5, 0(t1)
    li a1, VA_CODE
    li a0, 0
    jalr ra, a1, 0
    li a2, 1
    bne a0, a2, fail_s
    csrw satp, s5
    jalr ra, a1, 0
    li a2, 2
    bne a0, a2, fail_s
    csrw satp, s4
    jalr ra, a1, 0
    li a2, 1
    bne a0, a2, fail_s
    csrw satp, s5
    jalr ra, a1, 0
    csrw satp, s4
    li a2, 2
    bne a0, a2, fail_s

    // 10: fetch from an A=0 page.
    li t0, 10
    li s3, 0
    li a1, FP_A0
    jalr ra, a1, 0
    li a1, 1
    bne s3, a1, fail_s
    li a1, L0_A + 15 * 8
    ld a2, 0(a1)
    andi a2, a2, 0x40
    beqz a2, fail_s

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
    la t2, resume_addr
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw mepc, t1
    li t1, (3 << 11)
    csrs mstatus, t1
    j 2f
1:  la t1, m_info             // unexpected M trap: record, fail 99
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
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

// S: log and count; resume in S at s_resume if set, else skip.
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
    li t1, (1 << 8)             // back to S
    csrs sstatus, t1
    j 2f
1:  csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    ld t3, 16(sp)
    csrrw sp, sscratch, sp
    sret

// ---- Code pages (reached through their VA aliases) ---------------
    .balign 4096
pg_s:
    ret                         // +0
    nop
    sret                        // +8
    nop
    addi s3, s3, 1              // +16 (U target: must fault)
    ret
    .balign 4096
pg_u:
    addi s3, s3, 1
    ecall
1:  j 1b
    .balign 4096
pg_str:
    .skip 0xFFA, 0
    .option push
    .option rvc
    c.addi s3, 1                // +0xFFA
    c.addi s3, 1                // +0xFFC
    .option pop
    addi s3, s3, 0x10           // +0xFFE: straddles into +0x1000
    ret
    .balign 4096
    .skip 4096                  // (PA after pg_str: never mapped)
pg_str2:
    .skip 0xFFA, 0
    .option push
    .option rvc
    c.addi s3, 1
    c.addi s3, 1
    .option pop
    addi s3, s3, 0x10
    ret
    .balign 4096
pg_str2_next = pg_str2 + 0x1000
    .skip 0x1000 - 0            // pg_str2_next body (R only)
pg_q:
    addi s3, s3, 1
    ret
    .balign 4096
pg_q2:
    sd a2, 0(a1)                // +0: own PTE, X cleared
    sfence.vma                  // +4
    addi s3, s3, 1              // +8: must fault
    ret
    .balign 4096
pg_spec:
    addi s3, s3, 0x10           // +0 (jump target)
    ret
    .skip 0xFF8 - 8, 0
    addi s3, s3, 1              // +0xFF8
    j pg_spec                   // +0xFFC: next page unmapped
    .balign 4096
    .skip 4096
pg_spec2:
    addi s3, s3, 0x10
    ret
    .skip 0xFF8 - 8, 0
    addi s3, s3, 1
    beq x0, x0, pg_spec2
    .balign 4096
    .skip 4096
pg_run:
    .skip 0xFF8, 0
    addi s3, s3, 1              // +0xFF8
    addi s3, s3, 1              // +0xFFC, then +0x1000 unmapped
    .balign 4096
    .skip 4096
code_v1:
    li a0, 1
    ret
    .balign 4096
code_v2:
    li a0, 2
    ret
    .balign 4096
pg_a0:
    addi s3, s3, 1
    ret
    .balign 4096

    .data
    .align 3
satp_a:      .quad 0
satp_b:      .quad 0
s_cause:     .quad 0, 0, 0
resume_addr: .quad 0
m_info:      .quad 0, 0, 0, 0
s_resume:    .quad 0
s_count:     .quad 0
s_log_ptr:   .quad 0
    .align 6
s_log:       .skip 24 * 64
    .align 4
main_stack:  .skip 2048
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
s_trap_stack: .skip 1024
s_trap_stack_top:
