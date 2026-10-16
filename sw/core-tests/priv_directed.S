// Directed privileged-architecture tests (issue #18 stage 3a):
// CSR semantics, precise trap entry/return, delegation, S/U
// privilege drops, PMP, and a timer interrupt (the harness asserts
// irq_m_timer_i once via --irq-timer-after). Runs in handled mode
// (trap_halt_i=0): handlers record cause/epc/tval and skip the
// trapping instruction; the main flow asserts in line.
// Convention as before: t0 = test number, exit store 0 = pass.
    .option norvc
    .text
    .globl _start
_start:
    // Trap scaffolding: handler stacks + vectors.
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    csrw sscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_s
    csrw stvec, t1
    // PMP entry 15: catch-all RWX NAPOT so S/U have a default-allow
    // region (with no matching entry the spec defaults S/U to deny).
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56                // entry15 is pmpcfg2 byte 7
    csrw pmpcfg2, t1

    // 1: CSR write/read/set/clear and immediate forms
    li t0, 1
    li a0, 0x12345000
    csrw mscratch, a0
    csrr a1, mscratch
    bne a1, a0, fail
    li a1, 0xf0f
    csrs mscratch, a1
    csrr a1, mscratch
    li a2, 0x12345f0f
    bne a1, a2, fail
    li a1, 0x00f
    csrc mscratch, a1
    csrr a1, mscratch
    li a2, 0x12345f00
    bne a1, a2, fail
    csrwi mscratch, 7
    csrr a1, mscratch
    li a2, 7
    bne a1, a2, fail
    csrsi mscratch, 0x10
    csrci mscratch, 0x03
    csrr a1, mscratch              // (7 | 0x10) & ~3 = 0x14
    li a2, 0x14
    bne a1, a2, fail
    // CSRRW returns the OLD value
    li a0, 0x99
    csrrw a1, mscratch, a0
    li a2, 0x14
    bne a1, a2, fail
    csrr a1, mscratch
    li a2, 0x99
    bne a1, a2, fail
    // CSRRS with rs1=x0 must not write
    csrrs a1, mscratch, x0
    csrr a2, mscratch
    bne a1, a2, fail
    // restore the trap stack pointer clobbered above
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    csrw sscratch, t1

    // 2: identity CSRs
    li t0, 2
    csrr a1, misa
    li a2, 0x80000000003411AF      // MXL=2, I M A B C F D H V S U
    bne a1, a2, fail
    csrr a1, mhartid
    bne a1, x0, fail
    csrr a1, mvendorid
    bne a1, x0, fail

    // 3: counters advance; minstret counts retired instructions
    li t0, 3
    csrr a0, mcycle
    csrr a1, mcycle
    bgeu a0, a1, fail              // second read strictly later
    csrr a0, minstret
    nop
    nop
    nop
    csrr a1, minstret
    sub a1, a1, a0
    li a2, 2                       // at least the nops retired between reads
    bltu a1, a2, fail
    // cycle aliases mcycle: an mcycle read bracketed by two cycle
    // reads lies between them. No fixed skew bound, so the check
    // holds however long the fetches in between take (uncached
    // fetch under heavy bus backpressure).
    csrr a0, cycle
    csrr a1, mcycle
    csrr a2, cycle
    bltu a1, a0, fail
    bltu a2, a1, fail
    bgeu a0, a2, fail              // and the counter advanced

    // 4: ECALL traps to M with precise epc/cause, handler resumes
    li t0, 4
    la a0, handled_count
    sd x0, 0(a0)
ec4:
    ecall
    la a0, saved_cause
    ld a1, 0(a0)
    li a2, 11
    bne a1, a2, fail
    la a0, saved_epc
    ld a1, 0(a0)
    la a2, ec4
    bne a1, a2, fail
    la a0, handled_count
    ld a1, 0(a0)
    li a2, 1
    bne a1, a2, fail

    // 5: illegal CSR access traps with cause 2
    li t0, 5
    la a0, handled_count
    sd x0, 0(a0)
    .word 0x7c002573               // csrrs a0, 0x7c0, x0 (no such CSR)
    la a0, saved_cause
    ld a1, 0(a0)
    li a2, 2
    bne a1, a2, fail

    // 6: misaligned load: cause 4, mtval = faulting address
    li t0, 6
    la a0, scratch
    ld a1, 3(a0)
    la a0, saved_cause
    ld a1, 0(a0)
    li a2, 4
    bne a1, a2, fail
    la a0, saved_tval
    ld a1, 0(a0)
    la a2, scratch
    addi a2, a2, 3
    bne a1, a2, fail

    // 7: mstatus fields survive an ecall round trip (MPIE/MPP/etc):
    //    set MIE, ecall (clears MIE, sets MPIE), handler mrets
    //    (restores MIE from MPIE).
    li t0, 7
    csrsi mstatus, 0x8             // MIE = 1
    ecall
    csrr a0, mstatus
    andi a0, a0, 0x8
    li a1, 0x8
    bne a0, a1, fail
    csrci mstatus, 0x8

    // 8: drop to S-mode: S code runs, U-ecall-level check via scause
    //    delegated ecall-from-S handled by the S handler.
    li t0, 8
    // medeleg: ecall-from-U (8) and ecall-from-S (9) to S
    li a0, (1 << 8) | (1 << 9)
    csrw medeleg, a0
    la a0, s_handled
    sd x0, 0(a0)
    la a0, s_cause
    sd x0, 0(a0)
    // arrange return to M: S code ends with an illegal instruction
    // (not delegated) whose M handler redirects to resume_m via
    // the resume_addr cell.
    la a0, resume_m
    la a1, resume_addr
    sd a0, 0(a1)
    la a0, s_code
    csrw mepc, a0
    li a0, (1 << 11)               // MPP = S (01 in bits 12:11)
    csrs mstatus, a0
    mret
resume_m:
    csrw medeleg, x0
    la a0, s_handled
    ld a1, 0(a0)
    li a2, 1
    bne a1, a2, fail
    la a0, s_cause
    ld a1, 0(a0)
    li a2, 9                       // ecall from S
    bne a1, a2, fail
    la a0, s_flag
    ld a1, 0(a0)
    li a2, 0x500d
    bne a1, a2, fail
    // SPP after SRET return path: S entered handler from S-mode
    // so SPP was 1 on entry; sstatus read from M shows it cleared
    // by SRET.
    csrr a0, sstatus
    li a1, (1 << 8)
    and a0, a0, a1
    bne a0, x0, fail

    // 9: U-mode: plain compute works; CSR access from U traps.
    li t0, 9
    la a0, resume_m2
    la a1, resume_addr
    sd a0, 0(a1)
    la a0, handled_count
    sd x0, 0(a0)
    la a0, u_code
    csrw mepc, a0
    li a0, (3 << 11)
    csrc mstatus, a0               // MPP = U (00)
    mret
resume_m2:
    la a0, u_flag
    ld a1, 0(a0)
    li a2, 0x600d
    bne a1, a2, fail
    la a0, saved_cause
    ld a1, 0(a0)
    li a2, 2                       // illegal (privilege) from U
    bne a1, a2, fail

    // 10: PMP: NAPOT deny-all 4 KiB region. M bypasses (L=0),
    //     S-mode load takes a load access fault (cause 5).
    li t0, 10
    la a0, pmp_region
    srli a0, a0, 2
    ori a0, a0, 0x1ff              // NAPOT 4 KiB
    csrw pmpaddr0, a0
    // cfg0 byte0: A=NAPOT(3<<3), R=W=X=0. Also check W-clear WARL:
    // write R=0,W=1 first and read back W cleared.
    li a0, (3 << 3) | (1 << 1)
    csrw pmpcfg0, a0
    csrr a1, pmpcfg0
    andi a1, a1, 0xff
    li a2, (3 << 3)
    bne a1, a2, fail
    la a0, pmp_region
    li a1, 0xabcdef
    sd a1, 0(a0)                   // M store: allowed despite deny
    ld a2, 0(a0)
    bne a2, a1, fail
    // drop to S to attempt the load; resume via resume_addr
    la a0, resume_m3
    la a1, resume_addr
    sd a0, 0(a1)
    la a0, handled_count
    sd x0, 0(a0)
    la a0, s_pmp_code
    csrw mepc, a0
    li a0, (1 << 11)
    csrs mstatus, a0               // MPP = S
    mret
resume_m3:
    la a0, saved_cause
    ld a1, 0(a0)
    li a2, 5                       // load access fault
    bne a1, a2, fail
    csrw pmpcfg0, x0               // tear down for later tests
    csrw pmpaddr0, x0

    // 11: timer interrupt taken precisely between instructions;
    //     the interrupted loop resumes and exits once the handler
    //     has set irq_flag (200k iterations is only the timeout,
    //     so the test is short at any bus latency).
    li t0, 11
    la a0, irq_flag
    sd x0, 0(a0)
    la a0, handled_count
    sd x0, 0(a0)
    li a0, (1 << 7)                // MTIE
    csrs mie, a0
    csrsi mstatus, 0x8             // MIE
    li a0, 0
    li a1, 200000                  // timeout bound for the IRQ
    la a3, irq_flag
1:  addi a0, a0, 1
    ld a2, 0(a3)
    bnez a2, 2f                    // IRQ taken and handled
    bltu a0, a1, 1b
2:  csrci mstatus, 0x8
    csrw mie, x0
    la a0, irq_flag
    ld a1, 0(a0)
    li a2, 1
    bne a1, a2, fail
    la a0, saved_cause
    ld a1, 0(a0)
    li a2, 0x8000000000000007      // interrupt | machine timer
    bne a1, a2, fail

    // 12: WFI executes (as NOP here), SFENCE.VMA executes.
    li t0, 12
    wfi
    sfence.vma
    li a0, 5
    li a1, 5
    bne a0, a1, fail

    // 13: PMP execute-deny page: S-mode fetch there faults (cause 1)
    li t0, 13
    la a0, nox_fn
    srli a0, a0, 2
    ori a0, a0, 0x1ff              // NAPOT 4 KiB
    csrw pmpaddr1, a0
    li a0, ((3 << 3) | 1)          // NAPOT, R only (no X)
    slli a0, a0, 8                 // entry 1 is pmpcfg0 byte 1
    csrw pmpcfg0, a0
    la a0, resume_m4
    la a1, resume_addr
    sd a0, 0(a1)
    la a0, handled_count
    sd x0, 0(a0)
    la a0, s_fetch_code
    csrw mepc, a0
    li a0, (1 << 11)
    csrs mstatus, a0               // MPP = S
    mret
resume_m4:
    la a0, saved_cause
    ld a1, 0(a0)
    li a2, 1                       // instruction access fault
    bne a1, a2, fail
    la a0, saved_tval
    ld a1, 0(a0)
    la a2, nox_fn
    bne a1, a2, fail
    csrw pmpcfg0, x0
    csrw pmpaddr1, x0

    // 14: delegated supervisor timer interrupt, taken in S-mode
    li t0, 14
    li a0, (1 << 5)
    csrw mideleg, a0               // delegate STI
    csrs mie, a0                   // STIE
    csrs mip, a0                   // raise STIP (software bit)
    la a0, s_irq_flag
    sd x0, 0(a0)
    la a0, s_handled
    sd x0, 0(a0)
    la a0, resume_m5
    la a1, resume_addr
    sd a0, 0(a1)
    csrsi mstatus, 0x2             // SIE=1 so S takes it after mret
    la a0, s_irq_code
    csrw mepc, a0
    li a0, (1 << 11)
    csrs mstatus, a0               // MPP = S
    mret
resume_m5:
    csrci mstatus, 0x2
    csrw mideleg, x0
    csrw mie, x0
    li a0, (1 << 5)
    csrc mip, a0                   // clear software STIP
    la a0, s_irq_flag
    ld a1, 0(a0)
    li a2, 1
    bne a1, a2, fail
    la a0, s_cause
    ld a1, 0(a0)
    li a2, 0x8000000000000005      // interrupt | supervisor timer
    bne a1, a2, fail
    la a0, s_flag
    ld a1, 0(a0)
    li a2, 0x500e                  // S code completed after the IRQ
    bne a1, a2, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

// ---- M-mode trap handler --------------------------------------
// Records mcause/mepc/mtval, bumps handled_count, sets irq_flag
// for interrupts, and resumes at mepc+4 -- except when the
// resume_addr cell is set, in which case it redirects there
// (used to return from S/U excursions). Preserves all regs.
handler_m:
    csrrw sp, mscratch, sp
    sd t0, 0(sp)
    sd t1, 8(sp)
    sd t2, 16(sp)
    sd a0, 24(sp)
    sd a1, 32(sp)
    csrr t1, mcause
    la t2, saved_cause
    sd t1, 0(t2)
    csrr t1, mepc
    la t2, saved_epc
    sd t1, 0(t2)
    csrr t1, mtval
    la t2, saved_tval
    sd t1, 0(t2)
    la t2, handled_count
    ld t1, 0(t2)
    addi t1, t1, 1
    sd t1, 0(t2)
    csrr t1, mcause
    bltz t1, 1f                    // interrupt: flag + resume at epc
    j 2f
1:  la t2, irq_flag
    li t1, 1
    sd t1, 0(t2)
    j 3f
2:  la t2, resume_addr             // synchronous: redirect or skip
    ld t1, 0(t2)
    beqz t1, 4f
    sd x0, 0(t2)
    csrw mepc, t1
    // returning to M code: force MPP=M so mret lands in M-mode
    li t1, (3 << 11)
    csrs mstatus, t1
    j 3f
4:  csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
3:  ld t0, 0(sp)
    ld t1, 8(sp)
    ld t2, 16(sp)
    ld a0, 24(sp)
    ld a1, 32(sp)
    csrrw sp, mscratch, sp
    mret

// ---- S-mode trap handler --------------------------------------
handler_s:
    csrrw sp, sscratch, sp
    sd t0, 0(sp)
    sd t1, 8(sp)
    sd t2, 16(sp)
    csrr t1, scause
    la t2, s_cause
    sd t1, 0(t2)
    la t2, s_handled
    li t1, 1
    sd t1, 0(t2)
    csrr t1, scause
    bltz t1, 1f                    // interrupt: do not advance sepc
    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    j 2f
1:  la t2, s_irq_flag
    li t1, 1
    sd t1, 0(t2)
    li t1, (1 << 5)                // mask STIE so S makes progress
    csrc sie, t1
2:  ld t0, 0(sp)
    ld t1, 8(sp)
    ld t2, 16(sp)
    csrrw sp, sscratch, sp
    sret

// ---- S-mode test code (entered via mret with MPP=S) -----------
s_code:
    li a0, 0x500d
    la a1, s_flag
    sd a0, 0(a1)
    ecall                          // delegated -> S handler (cause 9)
    .word 0x00000000               // illegal, not delegated -> M
1:  j 1b

u_code:
    li a0, 0x600d
    la a1, u_flag
    sd a0, 0(a1)
    csrr a0, mstatus               // illegal from U -> M (cause 2)
1:  j 1b

s_pmp_code:
    la a0, pmp_region
    ld a1, 0(a0)                   // PMP deny in S: access fault
1:  j 1b

s_fetch_code:
    la a0, nox_fn
    jalr x0, 0(a0)                 // fetch in X-deny page: cause 1
1:  j 1b

s_irq_code:
    li a0, 0x500e                  // first S instruction is the IRQ's epc
    la a1, s_flag
    sd a0, 0(a1)
    .word 0x00000000               // illegal, not delegated -> M
1:  j 1b

    .align 12
nox_fn:
    nop
    nop
    j fail

    .data
    .align 3
saved_cause:  .dword 0
saved_epc:    .dword 0
saved_tval:   .dword 0
handled_count:.dword 0
irq_flag:     .dword 0
resume_addr:  .dword 0
s_handled:    .dword 0
s_irq_flag:   .dword 0
s_cause:      .dword 0
s_flag:       .dword 0
u_flag:       .dword 0
scratch:      .dword 0x1122334455667788
    .align 12
pmp_region:   .dword 0
    .align 3
    .skip 512
main_stack_top:
    .skip 512
trap_stack_top:
