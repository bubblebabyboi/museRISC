// Long-latency EX ops followed by straight-line code under I$
// misses: fdiv.d / fsqrt.d (multi-cycle FPU) and full-width
// 64/32-bit divides and remainders (multi-cycle M unit), which
// hold EX (ex_hold) whose results feed the next instructions,
// with the following code spread over separate I$ lines and
// the I$ invalidated (FENCE.I) before each pass, so fetches
// miss while EX is busy. Any fetch word consumed while EX is
// held would drop or duplicate an instruction and break the
// running checksum. t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start

_start:
    li t1, (1 << 13)               // FS = Initial
    csrs mstatus, t1
    li s0, 0                       // checksum
    li s1, 3                       // passes
pass_loop:
    fence.i                        // cold I$ for every pass
    // 1: fdiv.d result used immediately, then a new line.
    li t0, 1
    li t1, 0x4024000000000000      // 10.0
    fmv.d.x f1, t1
    li t1, 0x4004000000000000      // 2.5
    fmv.d.x f2, t1
    fdiv.d f3, f1, f2              // 4.0
    fcvt.l.d t2, f3, rtz
    add s0, s0, t2
    addi s0, s0, 1
    j 1f
    .balign 64
1:  addi s0, s0, 2
    addi s0, s0, 3
    // 2: fsqrt.d then dependent integer op on another line.
    li t0, 2
    li t1, 0x4031000000000000      // 17.0
    fmv.d.x f4, t1
    fsqrt.d f5, f4                 // 4.123...
    fcvt.l.d t2, f5, rtz           // 4
    add s0, s0, t2
    j 2f
    .balign 64
2:  addi s0, s0, 5
    // 3: back-to-back long ops with a store/load between.
    li t0, 3
    fdiv.d f6, f1, f3              // 2.5
    fdiv.d f7, f6, f2              // 1.0
    la t3, scratch
    fsd f7, 0(t3)
    ld t4, 0(t3)
    li t5, 0x3ff0000000000000
    bne t4, t5, fail
    li t6, 1000
    li t5, 7
    div t2, t6, t5                 // 142
    add s0, s0, t2
    j 3f
    .balign 64
3:  addi s0, s0, 7
    // 4: longest 64-bit divides/remainders (full-width operands:
    //    the most iterations of the multi-cycle divider), each
    //    result consumed by the next instruction, then cold lines.
    li t0, 4
    li t1, -1                      // 0xffff_ffff_ffff_ffff
    li t2, 3
    divu t3, t1, t2                // 0x5555_5555_5555_5555
    li t4, 0x5555555555555555
    bne t3, t4, fail
    remu t5, t1, t2                // 0
    add s0, s0, t5
    j 4f
    .balign 64
4:  li t1, 0x7fffffffffffffff
    li t2, -7
    div t3, t1, t2                 // -1317624576693539401
    li t4, -1317624576693539401
    bne t3, t4, fail
    rem t5, t1, t2                 // 0
    add s0, s0, t5
    divuw t6, t1, t2               // 0xffffffff / 0xfffffff9 = 1
    add s0, s0, t6
    j 5f
    .balign 64
5:  addi s0, s0, 11
    addi s1, s1, -1
    bnez s1, pass_loop
    // per pass: 4+1+2+3+4+5+142+7+0+0+1+11 = 180; 3 passes = 540
    li t0, 5
    li t1, 540
    bne s0, t1, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .balign 8
scratch: .dword 0
