// PMP: the lowest-numbered entry that matches any byte of an access
// decides, and if it does not match all of the access's bytes the
// access fails, whatever the privilege mode and the entry's L, R, W
// and X bits (priv. spec, "Priority and Matching Logic"). With a
// 4-byte grain an 8-byte access spans two PMP words, so an NA4 entry
// or a TOR boundary can split it. Found by the riscv-dv privileged
// program against Spike (issue #8): the core checked only the first
// word of the access. All accesses here are in M-mode with L=0, so
// they succeed exactly when no entry matches part of them.
// Convention: t0 = test number, exit store 0 = pass.
    .option norvc
    .text
    .globl _start
_start:
    la t1, handler_m
    csrw mtvec, t1
    li t1, (1 << 13)               // mstatus.FS = Initial (fld below)
    csrs mstatus, t1

    // 1: NA4 on word 1 of dword D: ld D fails (cause 5, tval D);
    //    lw of either word alone succeeds.
    li t0, 1
    la s1, dw
    addi a0, s1, 4
    srli a0, a0, 2
    csrw pmpaddr0, a0
    li a0, (2 << 3) | 7            // NA4, RWX
    csrw pmpcfg0, a0
    call clear
    ld a1, 0(s1)
    li a2, 5
    call expect_fault
    call clear
    lw a1, 0(s1)
    lw a1, 4(s1)
    call expect_none

    // 2: the same entry, sd D and amoadd.d D: store/AMO access fault
    //    (cause 7); sw to word 1 alone succeeds.
    li t0, 2
    call clear
    sd zero, 0(s1)
    li a2, 7
    call expect_fault
    call clear
    li a1, 1
    amoadd.d a3, a1, (s1)
    li a2, 7
    call expect_fault
    call clear
    sw zero, 4(s1)
    call expect_none

    // 3: NA4 on word 0: fld D fails (cause 5).
    li t0, 3
    srli a0, s1, 2
    csrw pmpaddr0, a0
    call clear
    fld f1, 0(s1)
    li a2, 5
    call expect_fault

    // 4: TOR [pmpaddr0, pmpaddr1) ending at D+4: ld D fails; a TOR
    //    entry starting at D+4 (entry 2, base pmpaddr1) also splits
    //    it, as entry 1 does not match D at all then.
    li t0, 4
    csrw pmpcfg0, zero
    csrw pmpaddr0, zero
    addi a0, s1, 4
    srli a0, a0, 2
    csrw pmpaddr1, a0
    li a0, ((1 << 3) | 7) << 8     // entry 1: TOR, RWX
    csrw pmpcfg0, a0
    call clear
    ld a1, 0(s1)
    li a2, 5
    call expect_fault
    call clear
    ld a1, -8(s1)                  // wholly below the top: fine
    call expect_none
    addi a0, s1, 64
    srli a0, a0, 2
    csrw pmpaddr2, a0
    li a0, ((1 << 3) | 7) << 16    // entry 2: TOR [D+4, D+64), RWX
    csrw pmpcfg0, a0
    call clear
    ld a1, 0(s1)
    li a2, 5
    call expect_fault

    // 5: an 8-byte NAPOT region covering D matches all of it: no
    //    fault; with entry 0 NA4 on word 1 above it, entry 0 decides.
    li t0, 5
    csrw pmpcfg0, zero
    srli a0, s1, 2                 // NAPOT 8 bytes: low bit 0
    csrw pmpaddr1, a0
    li a0, ((3 << 3) | 7) << 8     // entry 1: NAPOT, RWX
    csrw pmpcfg0, a0
    call clear
    ld a1, 0(s1)
    call expect_none
    addi a0, s1, 4
    srli a0, a0, 2
    csrw pmpaddr0, a0
    li a0, (((3 << 3) | 7) << 8) | ((2 << 3) | 7)
    csrw pmpcfg0, a0               // entry 0 NA4 word 1, entry 1 NAPOT
    call clear
    ld a1, 0(s1)
    li a2, 5
    call expect_fault

    csrw pmpcfg0, zero
pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

clear:
    la a4, n_traps
    sd zero, 0(a4)
    ret
// One trap with cause a2 and tval D (s1) since clear.
expect_fault:
    la a4, n_traps
    ld a5, 0(a4)
    li a6, 1
    bne a5, a6, fail
    ld a5, 8(a4)
    bne a5, a2, fail
    ld a5, 16(a4)
    bne a5, s1, fail
    ret
expect_none:
    la a4, n_traps
    ld a5, 0(a4)
    bnez a5, fail
    ret

// Records mcause/mtval, counts the trap, skips the instruction.
handler_m:
    csrw mscratch, a4
    la a4, n_traps
    sd a5, 24(a4)
    ld a5, 0(a4)
    addi a5, a5, 1
    sd a5, 0(a4)
    csrr a5, mcause
    sd a5, 8(a4)
    csrr a5, mtval
    sd a5, 16(a4)
    csrr a5, mepc
    addi a5, a5, 4
    csrw mepc, a5
    ld a5, 24(a4)
    csrr a4, mscratch
    mret

    .data
    .align 3
n_traps:  .dword 0, 0, 0, 0        // count, cause, tval, saved a5
    .align 6
    .dword 0x1111111111111111
dw: .dword 0x2222222222222222
    .skip 64
