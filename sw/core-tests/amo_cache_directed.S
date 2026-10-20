// Directed atomics-through-the-caches tests: AMOs and LR/SC on
// cacheable lines under eviction pressure (lines aliasing one
// D$ set, so the AMO read and write phases hit, miss, write
// back and refill), on dirty lines, and on uncached memory
// (single-beat bus read + write). The LR reservation is a
// physical-address reservation in the core: it survives the
// line being evicted, and dies on an intervening store.
// t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start

.equ D_WAY_BYTES, 4096       // D$ way size (64 sets x 64 B)
.equ NC_BASE, 0x20008000     // uncached RAM in core_tb's map

_start:
    // 1: 8 counters aliasing one set, 4 rounds of AMOADD.D each
    //    (every AMO misses after the first round), then check.
    li t0, 1
    la s0, alias_base
    li s1, 4                   // rounds
1:  li s2, 0                   // counter index
2:  li t1, D_WAY_BYTES
    mul t1, t1, s2
    add t1, t1, s0
    addi t2, s2, 1             // add (index + 1)
    amoadd.d x0, t2, (t1)
    addi s2, s2, 1
    li t3, 8
    blt s2, t3, 2b
    addi s1, s1, -1
    bnez s1, 1b
    li s2, 0
3:  li t1, D_WAY_BYTES
    mul t1, t1, s2
    add t1, t1, s0
    ld t2, 0(t1)
    addi t3, s2, 1
    slli t3, t3, 2             // 4 * (index + 1)
    bne t2, t3, fail
    addi s2, s2, 1
    li t3, 8
    blt s2, t3, 3b

    // 2: AMO on a dirty line returns the stored value.
    li t0, 2
    la t1, scratch
    li t2, 0x1122334455667788
    sd t2, 0(t1)
    li t3, 0x0101010101010101
    amoadd.d t4, t3, (t1)
    bne t4, t2, fail
    ld t5, 0(t1)
    add t2, t2, t3
    bne t5, t2, fail
    // .W form on the upper half of the same dirty word.
    li t2, -5
    sw t2, 4(t1)
    li t3, 3
    addi t6, t1, 4
    amomax.w t4, t3, (t6)        // max(-5, 3) = 3, returns -5
    li t2, -5
    bne t4, t2, fail
    lw t5, 4(t1)
    bne t5, t3, fail

    // 3: LR, evict the reserved line (8 aliasing stores), SC
    //    still succeeds (reservation is by PA, not by line).
    li t0, 3
    la t1, scratch
    li t2, 77
    sd t2, 0(t1)
    lr.d t3, (t1)
    bne t3, t2, fail
    li t4, 8
    mv t5, t1
4:  li t6, D_WAY_BYTES
    add t5, t5, t6
    sd t4, 0(t5)
    addi t4, t4, -1
    bnez t4, 4b
    li t2, 78
    sc.d t3, t2, (t1)
    bnez t3, fail
    ld t3, 0(t1)
    bne t3, t2, fail

    // 4: LR, store to the reserved word, SC fails and writes nothing.
    li t0, 4
    lr.d t3, (t1)
    li t2, 99
    sd t2, 0(t1)
    li t4, 100
    sc.d t3, t4, (t1)
    beqz t3, fail
    ld t3, 0(t1)
    bne t3, t2, fail

    // 5: uncached memory: AMOSWAP/AMOADD.W/AMOMINU and LR/SC.
    li t0, 5
    li t1, NC_BASE
    li t2, 0x0123456789abcdef
    sd t2, 0(t1)
    li t3, 42
    amoswap.d t4, t3, (t1)
    bne t4, t2, fail
    ld t4, 0(t1)
    bne t4, t3, fail
    li t2, 0x7fffffff
    sw t2, 8(t1)
    li t3, 1
    addi t6, t1, 8
    amoadd.w t4, t3, (t6)        // wraps to 0x80000000
    bne t4, t2, fail
    lw t4, 8(t1)
    li t5, 0xffffffff80000000
    bne t4, t5, fail
    li t3, 5
    amominu.w t4, t3, (t6)       // minu(0x80000000, 5) = 5
    bne t4, t5, fail
    lwu t4, 8(t1)
    bne t4, t3, fail
    lr.w t4, (t6)
    li t3, 6
    sc.w t5, t3, (t6)
    bnez t5, fail
    lw t4, 8(t1)
    bne t4, t3, fail

    // 6: AMO result forwarded straight into a dependent AMO
    //    address (load-use through the port).
    li t0, 6
    la t1, scratch
    la t2, scratch2
    sd t2, 0(t1)                 // scratch holds &scratch2
    li t3, 0
    amoadd.d t4, t3, (t1)        // t4 = &scratch2
    li t3, 9
    sd x0, 0(t2)
    amoadd.d x0, t3, (t4)
    ld t5, 0(t2)
    bne t5, t3, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .balign 64
scratch:  .dword 0, 0
scratch2: .dword 0
    .balign 4096
alias_base:
    .skip 8
