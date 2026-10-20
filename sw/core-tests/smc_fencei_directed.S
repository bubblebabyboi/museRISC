// Directed self-modifying-code tests for the L1 caches: stores
// rewrite instructions that are already in the I$ (and whose
// lines are dirty in the write-back D$), FENCE.I makes the new
// code visible. Covers: a called function patched in place, the
// instruction right after the FENCE.I, a 16-bit (RVC) parcel,
// fresh code written to a buffer whose dirty lines are evicted
// from the D$ by conflict before the FENCE.I, and repeated
// patch/execute cycles of the same line. Without FENCE.I the
// old code may legally run, so nothing checks that case.
// t0 = test number; exit store 0 = pass.
    .text
    .globl _start
    .option norvc

.equ D_WAY_BYTES, 4096       // D$ way size (64 sets x 64 B)

_start:
    // 1: function already executed (in the I$) is patched.
    li t0, 1
    call patch_fn
    li a1, 1
    bne a0, a1, fail
    la t1, patch_fn
    li t2, 0x00200513          // addi a0, x0, 2
    sw t2, 0(t1)
    fence.i
    call patch_fn
    li a1, 2
    bne a0, a1, fail

    // 2: the instruction right after FENCE.I is the patched one
    //    (it was fetched before the store reached memory).
    li t0, 2
    la t1, inline_tgt
    li t2, 0x00300513          // addi a0, x0, 3
    sw t2, 0(t1)
    fence.i
inline_tgt:
    addi a0, x0, 0x77
    li a1, 3
    bne a0, a1, fail

    // 3: 16-bit parcel patch (c.li a0, 5 -> c.li a0, 4).
    li t0, 3
    call rvc_fn
    li a1, 5
    bne a0, a1, fail
    la t1, rvc_fn
    li t2, 0x4511              // c.li a0, 4
    sh t2, 0(t1)
    fence.i
    call rvc_fn
    li a1, 4
    bne a0, a1, fail

    // 4: build a function in a buffer, then evict its dirty
    //    lines from the D$ by storing to 9 aliasing lines (twice
    //    the ways plus one), so the new code reaches memory by
    //    write-back eviction rather than by the FENCE.I clean.
    li t0, 4
    la t1, code_buf
    li t2, 0x02a00513          // addi a0, x0, 42
    sw t2, 0(t1)
    li t2, 0x00008067          // ret
    sw t2, 4(t1)
    li t3, 9
    mv t4, t1
1:  li t5, D_WAY_BYTES
    add t4, t4, t5
    sd t3, 0(t4)
    addi t3, t3, -1
    bnez t3, 1b
    fence.i
    jalr ra, 0(t1)
    li a1, 42
    bne a0, a1, fail

    // 5: patch/execute the same line 16 times with changing
    //    immediates (each FENCE.I must drop the previous copy).
    li t0, 5
    li s1, 0
    la s2, loop_fn
2:  slli t2, s1, 20            // addi a0, x0, s1
    li t3, 0x00000513
    or t2, t2, t3
    sw t2, 0(s2)
    fence.i
    jalr ra, 0(s2)
    bne a0, s1, fail
    addi s1, s1, 1
    li t3, 16
    blt s1, t3, 2b

    // 6: FENCE.I with nothing dirty (clean scan only) still
    //    leaves execution correct; FENCE (non-.I) is a no-op.
    li t0, 6
    fence.i
    fence rw, rw
    call patch_fn
    li a1, 2
    bne a0, a1, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .balign 64
patch_fn:
    addi a0, x0, 1
    ret
    .balign 64
loop_fn:
    addi a0, x0, 0x7ff
    ret
    .balign 64
    .option push
    .option rvc
rvc_fn:
    c.li a0, 5
    c.jr ra
    .option pop
    .balign 4

    .data
    .balign 64
code_buf:
    .skip 64
