// Multi-cycle FPU EX-stall interactions (fpu-multicycle):
// traps and flushes around an in-flight FP op, an FP op that
// completes while an older vector load holds MEM (mem_stall),
// operand forwarding across a held EX (ex_hold), precise
// commit of the older op when a younger one traps, and FS
// dirtying. Arithmetic bit-exactness is the FPU unit TB's job.
// Convention: t0 = test number, exit store 0 = pass.
// The trap handler snapshots mcause (s8), fflags (s9) and ft5
// (s10), counts traps (s11), clears vstart and skips the
// trapping instruction.
    .option arch, +v
    .option norvc  // norvc last: gas .option arch resets it
    .text
    .globl _start
_start:
    la t1, handler
    csrw mtvec, t1
    li t1, (1 << 13) | (1 << 9)   // FS=Initial, VS=Initial
    csrs mstatus, t1
    li a0, 0x3FF0000000000000     // 1.0
    fmv.d.x fs0, a0
    li a0, 0x4008000000000000     // 3.0
    fmv.d.x fs1, a0
    fmv.d.x fs2, zero             // +0.0
    li a0, 0xBFF0000000000000     // -1.0
    fmv.d.x fs3, a0
    li a0, 0x401C000000000000     // 7.0
    fmv.d.x fs4, a0
    li s5, 0x123456789ABCDEF0     // sentinel
    li s6, 0x3FD5555555555555     // 1/3 (RNE)

    // ---- 1: an older misaligned load traps while fdiv is in
    //      flight: the fdiv is squashed (no fd / fflags write)
    //      and replays after mret.
    li t0, 1
    fmv.d.x ft5, s5
    fsflags zero
    li s11, 0
    la a3, buf
    ld a1, 1(a3)                  // cause 4 at WB
    fdiv.d ft5, fs0, fs1          // 1/3, killed by the trap, replayed
    li a2, 1
    bne s11, a2, fail
    li a2, 4
    bne s8, a2, fail
    bnez s9, fail                 // nothing accrued before the trap
    bne s10, s5, fail             // ft5 untouched at the trap
    fmv.x.d a1, ft5
    bne a1, s6, fail
    frflags a1
    li a2, 1                      // NX from the replayed fdiv only
    bne a1, a2, fail

    // ---- 2: an older vector load sequences in MEM (mem_stall)
    //      and then faults while fdiv computes behind it.
    li t0, 2
    fmv.d.x ft5, s5
    fsflags zero
    li s11, 0
    li a1, 8
    vsetvli a0, a1, e64, m1, ta, ma
    li a3, 0x00FFFFFFFFFFFFE0     // elements 4..7 are at PA >= 2^56
    vle64.v v1, (a3)              // 4 elements, then access fault
    fdiv.d ft5, fs0, fs1          // killed mid-computation, replayed
    li a2, 1
    bne s11, a2, fail
    li a2, 5                      // load access fault
    bne s8, a2, fail
    bnez s9, fail
    bne s10, s5, fail
    fmv.x.d a1, ft5
    bne a1, s6, fail
    frflags a1
    li a2, 1
    bne a1, a2, fail

    // ---- 3: FP ops complete while an older 64-element vector
    //      load holds MEM (mem_stall): the FPU parks the result in
    //      HOLD until EX can advance. The load targets v16: its rd
    //      must not alias an FP source index (the load-use check
    //      compares the vector rd with scalar rs1/rs2), or the FP op
    //      would wait in ID instead of EX. Sub-cases:
    //      forwarded to a dependent op; fflags
    //      accrued exactly once; int result feeding an int
    //      consumer; a fast op (fsgnjn) parked from IDLE.
    li t0, 3
    li a1, 64
    vsetvli a0, a1, e64, m8, ta, ma
    la a3, vbuf
    fsflags zero
    vle64.v v16, (a3)
    fadd.d ft6, fs0, fs1          // 4.0, done during the stall
    fmul.d ft7, ft6, fs1          // 12.0
    fmv.x.d a1, ft7
    li a2, 0x4028000000000000
    bne a1, a2, fail
    frflags a1
    bnez a1, fail
    vmv.x.s a1, v16
    li a2, 0x1111
    bne a1, a2, fail
    li t0, 10
    fsflags zero
    vle64.v v16, (a3)
    fdiv.d ft8, fs4, fs1          // 7/3, NX, parked
    frflags a1
    li a2, 1
    bne a1, a2, fail
    fmv.x.d a1, ft8
    li a2, 0x4002AAAAAAAAAAAB
    bne a1, a2, fail
    li t0, 11
    vle64.v v16, (a3)
    fcvt.w.d a4, fs4              // 7, parked
    addi a5, a4, 1
    li a2, 8
    bne a5, a2, fail
    li t0, 12
    vle64.v v16, (a3)
    fneg.d ft9, fs1               // fast op, parked from IDLE
    fmv.x.d a1, ft9
    li a2, 0xC008000000000000
    bne a1, a2, fail

    // ---- 4: operands of an instruction held in EX by
    //      ex_hold (here vec_ex_stall) stay correct after their producer
    //      retires (held-EX operand refresh).
    li t0, 4
    li a1, 1
    vsetvli a0, a1, e64, m1, ta, ma
    la a3, vbuf
    li t3, 5
    addi t3, t3, 37               // 42, in MEM while vadd.vx is in ID
    vle64.v v1, (a3)
    vadd.vx v2, v1, t3            // 0x1111 + 42
    vmv.x.s a1, v2
    li a2, 0x1111 + 42
    bne a1, a2, fail
    // same with an FP scalar produced by a multi-cycle op
    li t0, 9
    la a3, vbuf2
    fadd.d fa5, fs0, fs1          // 4.0 (FP scalar producer)
    vle64.v v1, (a3)              // 2.0
    vfadd.vf v3, v1, fa5          // 6.0
    vmv.x.s a1, v3
    li a2, 0x4018000000000000
    bne a1, a2, fail

    // ---- 5: FP ops in a taken branch / jump shadow never
    //      execute; FP results feed branches; FP op as target.
    li t0, 5
    fmv.d.x ft8, s5
    fsflags zero
    li a1, 1
    bnez a1, 1f
    fdiv.d ft8, fs0, fs2          // shadow (would raise DZ)
    fsqrt.d ft8, fs3              // shadow (would raise NV)
1:  jal x0, 2f
    fdiv.d ft8, fs0, fs2          // shadow of jal
2:  fmv.x.d a1, ft8
    bne a1, s5, fail
    frflags a1
    bnez a1, fail
    feq.d a1, fs0, fs0
    beqz a1, fail
    fcvt.w.d a1, fs1
    li a2, 3
    bne a1, a2, fail
    j 3f
3:  fdiv.d ft8, fs1, fs1          // branch target: 1.0
    fmv.x.d a1, ft8
    li a2, 0x3FF0000000000000
    bne a1, a2, fail

    // ---- 6: ecall right behind a long op: the older op is
    //      fully committed when the younger one traps.
    li t0, 6
    fsflags zero
    li s11, 0
    fdiv.d ft5, fs0, fs1
    ecall
    li a2, 11
    bne s8, a2, fail
    bne s10, s6, fail
    li a2, 1
    bne s9, a2, fail

    // ---- 7: illegal FP op (reserved dynamic frm) right behind
    //      a long op with a static rm: precise trap.
    li t0, 7
    fsflags zero
    li s11, 0
    li a0, 5
    fsrm a0                       // reserved frm
    fdiv.d ft5, fs4, fs1, rne     // static: legal, 7/3
    fadd.d ft6, fs0, fs0          // dyn: illegal instruction
    fsrm zero
    li a2, 1
    bne s11, a2, fail
    li a2, 2
    bne s8, a2, fail
    li a2, 0x4002AAAAAAAAAAAB
    bne s10, a2, fail
    li a2, 1
    bne s9, a2, fail

    // ---- 8: a multi-cycle op dirties FS (Clean -> Dirty).
    li t0, 8
    li a0, (3 << 13)
    csrc mstatus, a0
    li a0, (2 << 13)              // FS = Clean
    csrs mstatus, a0
    fdiv.d ft5, fs0, fs1
    csrr a1, mstatus
    srli a1, a1, 13
    andi a1, a1, 3
    li a2, 3
    bne a1, a2, fail

    // ---- 13: vector ops interleaved with multi-cycle FP ops:
    //      a vector op waits in ID while fdiv.d holds EX, then
    //      consumes its result (.vf scalar); the next fdiv.d
    //      waits while the element-serial vector unit holds EX.
    li t0, 13
    li a1, 8
    vsetvli a0, a1, e64, m1, ta, ma
    la a3, vbuf2                  // {2.0, 0, ...}
    vle64.v v4, (a3)
    fdiv.d fa6, fs4, fs1          // 7/3
    vfadd.vf v5, v4, fa6          // {2+7/3, 7/3, ...}
    fdiv.d fa7, fa6, fs1          // 7/9
    vfmul.vf v6, v5, fa7
    vadd.vi v7, v4, 1             // integer vector op between FP ops
    fsqrt.d ft9, fs4              // and an FP op right behind it
    vfmv.f.s fa0, v6
    fmv.x.d a1, fa0
    li a2, 0x400AF684BDA12F69
    bne a1, a2, fail
    vslidedown.vi v8, v6, 1
    vfmv.f.s fa0, v8
    fmv.x.d a1, fa0
    li a2, 0x3FFD097B425ED098
    bne a1, a2, fail
    fmv.x.d a1, fa7
    li a2, 0x3FE8E38E38E38E39
    bne a1, a2, fail
    vmv.x.s a1, v7
    li a2, 0x4000000000000001
    bne a1, a2, fail
    fmv.x.d a1, ft9
    li a2, 0x40052A7FA9D2F8EA     // sqrt(7)
    bne a1, a2, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

handler:
    csrr s8, mcause
    csrr s9, fflags
    fmv.x.d s10, ft5
    addi s11, s11, 1
    csrw vstart, zero
    csrr s7, mepc
    addi s7, s7, 4
    csrw mepc, s7
    mret

    .data
    .balign 8
buf:    .dword 0, 0
vbuf:   .dword 0x1111
        .skip 1024
vbuf2:  .dword 0x4000000000000000  // 2.0
        .skip 504
