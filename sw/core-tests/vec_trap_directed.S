// Vector trap / interrupt directed test (element-serial vector
// unit, issue #32). Run with --irq-timer-after 2000.
//  1-2: an M-timer interrupt that arrives while a long vector op
//       (vmacc e64 m8, ~0.5k cycles each) holds EX is taken at the
//       next instruction boundary (mepc = the instruction after
//       the vmacc) and the op is neither cut short nor replayed:
//       the non-idempotent vmacc accumulates exactly 20 times.
//  3:   indexed load with a misaligned element 2: elements 0-1
//       commit, element 2+ untouched, vstart = 2, tval = address.
//  4-5: unit-stride segment load whose element 2 field 1 is
//       denied by PMP (MPRV=1, MPP=U): no partial segment is
//       written, vstart = 2; then the handler widens PMP and
//       returns to the load, which resumes at vstart = 2 and
//       completes; a csrr vstart right after reads 0.
//  6:   fault-only-first segment load over the same boundary
//       trims vl to 2 without trapping; csrr vl and a vsetvli
//       x0,x0 issued back-to-back observe the trimmed vl.
//  7:   arithmetic with vstart = 3 leaves prestart elements and
//       resets vstart to 0 on completion.
//  8:   strided store faulting at element 2: elements 0-1 are
//       stored, element 2 is not, vstart = 2.
//  9:   fault-only-first with element 0 masked off and a fault
//       on element 1 trims vl to 1 without trapping.
//  10-12: vstart > 0 honored by vl1re32.v, vs1r.v and vmv1r.v.
//  13:  vl1re64.v PMP fault inside element 2 (byte 20): vstart =
//       2 (EEW=64 elements), mtval = pbuf+20; resume completes.
//  14:  vs1r.v PMP fault at byte 20 (EEW=8): vstart = 20, bytes
//       0-19 stored, 20+ not.
//  15:  fault-only-first with vstart=1, element 1 faults: vl
//       trimmed to 1, no trap, vstart reads 0.
//  16:  fault-only-first, unmasked element 0 faults: trap, vl
//       unchanged. (13-16 contributed by the round-2 reviewer.)
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it
    .text
    .globl _start
_start:
    la sp, stack_top
    la t1, handler
    csrw mtvec, t1
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    li t1, (1 << 9)                  // VS = Initial
    csrs mstatus, t1

    // ---- 1-2: interrupt during long vector ops ----
    li t0, 1
    li a1, 64
    vsetvli x0, a1, e64, m8, tu, mu
    vmv.v.i v16, 0
    vmv.v.i v8, 1
    vmv.v.i v24, 1
    li t1, (1 << 7)                  // mie.MTIE
    csrs mie, t1
    csrsi mstatus, 8                 // mstatus.MIE
    li s2, 20
1:  vmacc.vv v16, v8, v24
irq_after_vmacc:
    addi s2, s2, -1
    bnez s2, 1b
    csrci mstatus, 8
    la a1, irq_count
    ld a2, 0(a1)
    li a3, 1
    bne a2, a3, fail                 // exactly one interrupt taken
    la a1, irq_epc
    ld a2, 0(a1)
    la a3, irq_after_vmacc
    bne a2, a3, fail                 // ... right after a vmacc
    li t0, 2
    li a1, 20
    vmseq.vx v1, v16, a1
    vcpop.m a2, v1
    li a3, 64
    bne a2, a3, fail                 // every element exactly 20

    // ---- 3: misaligned indexed element, partial commit ----
    li t0, 3
    vsetivli x0, 4, e32, m1, tu, mu
    la a1, idx
    vle32.v v1, (a1)                 // byte offsets 0, 4, 9, 12
    li a2, 0x77
    vmv.v.x v2, a2
    la a1, trap_cause
    sd x0, 0(a1)
    la a1, ldata
    vluxei32.v v2, (a1), v1
    la a1, trap_cause
    ld a2, 0(a1)
    li a3, 4                         // load address misaligned
    bne a2, a3, fail
    ld a2, 16(a1)                    // vstart seen by the handler
    li a3, 2
    bne a2, a3, fail
    ld a2, 8(a1)                     // mtval = element address
    la a3, ldata
    addi a3, a3, 9
    bne a2, a3, fail
    csrr a2, vstart
    li a3, 2
    bne a2, a3, fail
    csrw vstart, x0
    vmv.x.s a2, v2
    li a3, 0x11111111
    bne a2, a3, fail
    vslidedown.vi v3, v2, 1
    vmv.x.s a2, v3
    li a3, 0x22222222
    bne a2, a3, fail
    vslidedown.vi v3, v2, 2
    vmv.x.s a2, v3
    li a3, 0x77
    bne a2, a3, fail

    // ---- 4-5: segment load, PMP fault on a field, resume ----
    li t0, 4
    la t1, pbuf
    addi t1, t1, 20
    srli t1, t1, 2
    csrw pmpaddr0, t1                // TOR [0, pbuf+20)
    li t1, 0x0f                      // TOR, RWX, unlocked
    csrw pmpcfg0, t1
    vsetivli x0, 3, e32, m1, tu, mu
    li a2, 0x5a5a5a5a
    vmv.v.x v4, a2
    vmv.v.x v5, a2
    la a1, trap_cause
    sd x0, 0(a1)
    li t1, (3 << 11)
    csrc mstatus, t1                 // MPP = U
    li t1, (1 << 17)
    csrs mstatus, t1                 // MPRV: data accesses as U
    la a1, pbuf
    vlseg2e32.v v4, (a1)             // element 2 field 1 faults
    li t1, (1 << 17)
    csrc mstatus, t1
    la a1, trap_cause
    ld a2, 0(a1)
    li a3, 5                         // load access fault
    bne a2, a3, fail
    ld a2, 16(a1)
    li a3, 2
    bne a2, a3, fail
    ld a2, 8(a1)
    la a3, pbuf
    addi a3, a3, 20
    bne a2, a3, fail
    csrw vstart, x0
    vslidedown.vi v6, v4, 1
    vmv.x.s a2, v6
    li a3, 0x20
    bne a2, a3, fail
    vslidedown.vi v6, v5, 1
    vmv.x.s a2, v6
    li a3, 0x21
    bne a2, a3, fail
    vslidedown.vi v6, v4, 2          // field 0 of the faulting
    vmv.x.s a2, v6                   // segment was not written
    li a3, 0x5a5a5a5a
    bne a2, a3, fail
    // 5: resume: the handler widens PMP and returns to the load.
    li t0, 5
    la a1, fixup
    li a2, 2
    sd a2, 0(a1)
    la a1, trap_cause
    sd x0, 0(a1)
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    vlseg2e32.v v4, (a1)             // faults, then resumes at 2
    csrr a4, vstart                  // back-to-back: must read 0
    li t1, (1 << 17)
    csrc mstatus, t1
    bnez a4, fail
    la a1, trap_cause
    ld a2, 16(a1)
    li a3, 2
    bne a2, a3, fail                 // it did fault at element 2
    vslidedown.vi v6, v4, 2
    vmv.x.s a2, v6
    li a3, 0x30
    bne a2, a3, fail
    vslidedown.vi v6, v5, 2
    vmv.x.s a2, v6
    li a3, 0x31
    bne a2, a3, fail

    // ---- 6: fault-only-first segment load trims vl ----
    li t0, 6
    la t1, pbuf
    addi t1, t1, 20
    srli t1, t1, 2
    csrw pmpaddr0, t1
    vsetivli x0, 3, e32, m1, tu, mu
    li a2, 0x5a5a5a5a
    vmv.v.x v8, a2
    vmv.v.x v9, a2
    la a1, trap_cause
    sd x0, 0(a1)
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    vlseg2e32ff.v v8, (a1)
    csrr a4, vl                      // back-to-back with the trim
    li t1, (1 << 17)
    csrc mstatus, t1
    li a3, 2
    bne a4, a3, fail
    la a1, trap_cause
    ld a2, 0(a1)
    bnez a2, fail                    // no trap
    vsetivli x0, 3, e32, m1, tu, mu
    vslidedown.vi v6, v8, 2
    vmv.x.s a2, v6
    li a3, 0x5a5a5a5a
    bne a2, a3, fail
    vslidedown.vi v6, v9, 1
    vmv.x.s a2, v6
    li a3, 0x21
    bne a2, a3, fail
    vsetivli x0, 3, e32, m1, tu, mu
    la a1, pbuf
    li t1, (1 << 17)
    csrs mstatus, t1
    vlseg2e32ff.v v8, (a1)
    vsetvli x0, x0, e32, m1, tu, mu  // keeps the trimmed vl
    csrr a4, vl
    li t1, (1 << 17)
    csrc mstatus, t1
    li a3, 2
    bne a4, a3, fail

    // ---- 7: vstart > 0 arithmetic ----
    li t0, 7
    vsetivli x0, 8, e32, m1, tu, mu
    vid.v v10
    vmv.v.i v11, 0
    csrwi vstart, 3
    vadd.vi v11, v10, 1
    csrr a2, vstart
    bnez a2, fail
    vmv.x.s a2, v11
    bnez a2, fail                    // prestart element 0 kept
    vslidedown.vi v12, v11, 2
    vmv.x.s a2, v12
    bnez a2, fail                    // prestart element 2 kept
    vslidedown.vi v12, v11, 3
    vmv.x.s a2, v12
    li a3, 4
    bne a2, a3, fail                 // element 3 = 3 + 1

    // ---- 8: strided store fault ----
    li t0, 8
    la t1, pbuf
    addi t1, t1, 16
    srli t1, t1, 2
    csrw pmpaddr0, t1                // TOR [0, pbuf+16)
    vsetivli x0, 4, e32, m1, tu, mu
    vid.v v13
    vadd.vi v13, v13, 1              // 1, 2, 3, 4
    la a1, pbuf
    sd x0, 0(a1)
    sd x0, 8(a1)
    la a1, trap_cause
    sd x0, 0(a1)
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    li a2, 8
    vsse32.v v13, (a1), a2           // element 2 at pbuf+16 faults
    li t1, (1 << 17)
    csrc mstatus, t1
    la a1, trap_cause
    ld a2, 0(a1)
    li a3, 7                         // store access fault
    bne a2, a3, fail
    ld a2, 16(a1)
    li a3, 2
    bne a2, a3, fail
    la a1, pbuf
    lw a2, 0(a1)
    li a3, 1
    bne a2, a3, fail
    lw a2, 8(a1)
    li a3, 2
    bne a2, a3, fail
    lw a2, 16(a1)
    li a3, 0x30                      // untouched segment data
    bne a2, a3, fail
    csrw vstart, x0

    // ---- 9: fault-only-first with element 0 masked off: a
    // fault on element 1 trims vl to 1 (RVV 7.7), no trap ----
    li t0, 9
    la t1, pbuf
    addi t1, t1, 4
    srli t1, t1, 2
    csrw pmpaddr0, t1                // TOR [0, pbuf+4)
    vsetivli x0, 3, e32, m1, tu, mu
    li a2, 0x5a5a5a5a
    vmv.v.x v8, a2
    vmv.v.i v0, 2                    // element 0 off, 1 on
    la a1, trap_cause
    sd x0, 0(a1)
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    vle32ff.v v8, (a1), v0.t         // element 1 faults
    csrr a4, vl
    li t1, (1 << 17)
    csrc mstatus, t1
    li a3, 1
    bne a4, a3, fail
    la a1, trap_cause
    ld a2, 0(a1)
    bnez a2, fail                    // no trap
    vmv.x.s a2, v8
    li a3, 0x5a5a5a5a
    bne a2, a3, fail                 // masked element 0 kept

    // ---- 10: whole-register load honors vstart (EEW=32) ----
    li t0, 10
    vsetivli x0, 4, e32, m1, tu, mu
    vmv.v.i v12, 7
    csrwi vstart, 2
    la a1, ldata
    vl1re32.v v12, (a1)
    csrr a2, vstart
    bnez a2, fail
    vmv.x.s a2, v12
    li a3, 7
    bne a2, a3, fail                 // element 0 kept
    vslidedown.vi v6, v12, 1
    vmv.x.s a2, v6
    bne a2, a3, fail                 // element 1 kept
    vslidedown.vi v6, v12, 2
    vmv.x.s a2, v6
    li a3, 0x33333333
    bne a2, a3, fail                 // element 2 loaded

    // ---- 11: whole-register store honors vstart (EEW=8) ----
    li t0, 11
    la a1, pbuf
    li a2, -1
    sd a2, 0(a1)
    sd a2, 8(a1)
    li t1, (1 << 17)                 // (PMP off for M: MPRV clear)
    vmv.v.i v13, 0
    csrwi vstart, 4
    vs1r.v v13, (a1)
    ld a2, 0(a1)
    li a3, 0x00000000ffffffff
    bne a2, a3, fail                 // bytes 0-3 untouched
    ld a2, 8(a1)
    bnez a2, fail

    // ---- 12: vmv1r.v honors vstart (EEW=SEW=16) ----
    li t0, 12
    vsetivli x0, 8, e16, m1, tu, mu
    vid.v v14
    vmv.v.i v15, -1
    csrwi vstart, 3
    vmv1r.v v15, v14
    csrr a2, vstart
    bnez a2, fail
    vslidedown.vi v6, v15, 2
    vmv.x.s a2, v6
    li a3, -1
    bne a2, a3, fail                 // element 2 kept (sext -1)
    vslidedown.vi v6, v15, 3
    vmv.x.s a2, v6
    li a3, 3
    bne a2, a3, fail                 // element 3 copied

    // ---- 13: vl1re64.v PMP fault inside element 2
    // (byte 20): vstart = 2, mtval = pbuf+20; resume completes ----
    li t0, 13
    la a1, pbuf
    li a2, 0x0000003100000030
    sd a2, 16(a1)
    li a2, 0x0000004100000040
    sd a2, 24(a1)
    la t1, pbuf
    addi t1, t1, 20
    srli t1, t1, 2
    csrw pmpaddr0, t1                // TOR [0, pbuf+20)
    vsetivli x0, 2, e64, m1, tu, mu
    li a2, 0x5a5a5a5a
    vmv.v.x v16, a2
    la a1, trap_cause
    sd x0, 0(a1)
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    vl1re64.v v16, (a1)
    li t1, (1 << 17)
    csrc mstatus, t1
    la a1, trap_cause
    ld a2, 0(a1)
    li a3, 5
    bne a2, a3, fail
    li t0, 131
    ld a2, 16(a1)
    li a3, 2
    bne a2, a3, fail                 // vstart in EEW=64 elements
    li t0, 132
    ld a2, 8(a1)
    la a3, pbuf
    addi a3, a3, 20
    bne a2, a3, fail
    li t0, 133
    csrr a2, vstart
    li a3, 2
    bne a2, a3, fail
    // resume with fixup
    li t0, 134
    la a1, fixup
    li a2, 2
    sd a2, 0(a1)
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    vl1re64.v v16, (a1)
    csrr a4, vstart
    li t1, (1 << 17)
    csrc mstatus, t1
    bnez a4, fail
    vsetivli x0, 8, e64, m1, tu, mu
    vslidedown.vi v6, v16, 2
    vmv.x.s a2, v6
    li a3, 0x0000003100000030
    li t0, 135
    bne a2, a3, fail
    vslidedown.vi v6, v16, 3
    vmv.x.s a2, v6
    li a3, 0x0000004100000040
    li t0, 136
    bne a2, a3, fail

    // ---- 14: vs1r.v PMP fault at byte 20 (EEW=8):
    // vstart = 20, bytes 0-19 stored ----
    li t0, 14
    la t1, pbuf
    addi t1, t1, 20
    srli t1, t1, 2
    csrw pmpaddr0, t1
    vmv.v.i v17, 0
    la a1, trap_cause
    sd x0, 0(a1)
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    vs1r.v v17, (a1)
    li t1, (1 << 17)
    csrc mstatus, t1
    la a1, trap_cause
    ld a2, 0(a1)
    li a3, 7                         // store access fault
    bne a2, a3, fail
    li t0, 141
    ld a2, 16(a1)
    li a3, 20
    bne a2, a3, fail
    csrw vstart, x0
    li t0, 142
    la a1, pbuf
    lw a2, 16(a1)
    bnez a2, fail                    // byte 16-19 stored (zero)
    lw a2, 20(a1)
    li t0, 143
    beqz a2, fail                    // byte 20+ not stored

    // ---- 15: FOF with vstart=1, element 1 faults:
    // trim vl to 1, no trap ----
    li t0, 15
    la t1, pbuf
    addi t1, t1, 4
    srli t1, t1, 2
    csrw pmpaddr0, t1                // TOR [0, pbuf+4)
    vsetivli x0, 3, e32, m1, tu, mu
    la a1, trap_cause
    sd x0, 0(a1)
    csrwi vstart, 1
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    vle32ff.v v18, (a1)
    csrr a4, vl
    csrr a5, vstart
    li t1, (1 << 17)
    csrc mstatus, t1
    la a1, trap_cause
    ld a2, 0(a1)
    bnez a2, fail
    li t0, 151
    li a3, 1
    bne a4, a3, fail
    li t0, 152
    bnez a5, fail

    // ---- 16: FOF unmasked element 0 faults: trap,
    // vl unchanged ----
    li t0, 16
    la t1, pbuf
    srli t1, t1, 2
    csrw pmpaddr0, t1                // TOR [0, pbuf)
    vsetivli x0, 3, e32, m1, tu, mu
    la a1, trap_cause
    sd x0, 0(a1)
    li t1, (1 << 17)
    csrs mstatus, t1
    la a1, pbuf
    vle32ff.v v18, (a1)
    csrr a4, vl
    li t1, (1 << 17)
    csrc mstatus, t1
    la a1, trap_cause
    ld a2, 0(a1)
    li a3, 5
    bne a2, a3, fail
    li t0, 161
    li a3, 3
    bne a4, a3, fail
    csrw vstart, x0
    la t1, pbuf
    addi t1, t1, 64
    srli t1, t1, 2
    csrw pmpaddr0, t1
    j pass

// Exceptions: record mcause/mtval/vstart, then either skip the
// instruction or (one-shot fixup 2) widen PMP and re-execute it.
// Interrupts: count, record mepc, mask MTIE, resume.
handler:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    sd t3, 16(sp)
    csrr t1, mcause
    bltz t1, handler_irq
    la t2, trap_cause
    sd t1, 0(t2)
    csrr t1, mtval
    sd t1, 8(t2)
    csrr t1, vstart
    sd t1, 16(t2)
    la t2, fixup
    ld t1, 0(t2)
    beqz t1, handler_skip
    sd x0, 0(t2)
    la t1, pbuf
    addi t1, t1, 64
    srli t1, t1, 2
    csrw pmpaddr0, t1
    j handler_ret
handler_skip:
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    j handler_ret
handler_irq:
    la t2, irq_count
    ld t3, 0(t2)
    addi t3, t3, 1
    sd t3, 0(t2)
    csrr t1, mepc
    la t2, irq_epc
    sd t1, 0(t2)
    li t1, (1 << 7)
    csrc mie, t1
handler_ret:
    ld t1, 0(sp)
    ld t2, 8(sp)
    ld t3, 16(sp)
    csrrw sp, mscratch, sp
    mret

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .align 3
trap_cause: .dword 0, 0, 0           // mcause, mtval, vstart
fixup:      .dword 0
irq_count:  .dword 0
irq_epc:    .dword 0
idx:        .word 0, 4, 9, 12
ldata:      .word 0x11111111, 0x22222222, 0x33333333, 0x44444444
            .word 0x55555555, 0x66666666
    .align 4
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
    // PMP test buffer: must stay last (TOR boundaries inside it).
    .align 6
pbuf:       .word 0x10, 0x11, 0x20, 0x21, 0x30, 0x31, 0x40, 0x41
            .skip 64
