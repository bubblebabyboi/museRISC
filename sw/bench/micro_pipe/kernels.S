/* micro_pipe kernels: fetch/ALU, branches and jumps, L1 load/store
 * hits, load-use, CSR access (../micro_common/README.md).
 * Convention: ../micro_common/micro_asm.h. U operations per loop trip
 * unless a kernel says otherwise; one operation = one instruction
 * unless a kernel says otherwise. */
#include "micro_asm.h"

#define U 256

	.option norvc

/* Region overhead: call, li a0, 0 and return. */
MICRO_FUNC(k_empty)
	li	a0, 0
	ret
MICRO_ENDF(k_empty)

/* op = one trip of the bare loop: addi + taken bnez. */
MICRO_FUNC(k_loop)
1:	addi	a0, a0, -1
	bnez	a0, 1b
	ret
MICRO_ENDF(k_loop)

/* Dependent 32-bit ALU chain: a1 += 3, U per trip. Returns a1. */
MICRO_FUNC(k_alu32_dep)
	li	t1, 3
1:
	.rept U
	add	a1, a1, t1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	ret
MICRO_ENDF(k_alu32_dep)

/* Independent 32-bit ALU ops (no operand comes from the previous
 * instruction). Returns 4 * (a1 + 3). */
MICRO_FUNC(k_alu32_indep)
	li	t1, 3
1:
	.rept U / 4
	add	t2, a1, t1
	add	t3, a1, t1
	add	t4, a1, t1
	add	t5, a1, t1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	add	a0, t2, t3
	add	a0, a0, t4
	add	a0, a0, t5
	ret
MICRO_ENDF(k_alu32_indep)

/* Dependent 16-bit ALU chain (c.add, two per fetch word): a1 += 3. The
 * loop head is word-aligned. Returns a1. */
MICRO_FUNC(k_alu16_dep)
	li	t1, 3
1:
	.option push
	.option rvc
	.rept U
	c.add	a1, t1
	.endr
	.option pop
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	ret
MICRO_ENDF(k_alu16_dep)

/* Dependent 32-bit ALU chain with every instruction at an address
 * = 2 mod 4, so each one straddles two fetch words (a c.nop before the
 * loop shifts the loop head by 2 bytes). Returns a1 + 3 * ops. */
MICRO_FUNC(k_alu32_straddle)
	li	t1, 3
	.option push
	.option rvc
	c.nop
	.option pop
1:
	.rept U
	add	a1, a1, t1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	ret
MICRO_ENDF(k_alu32_straddle)

/* Not-taken conditional branches. Returns 0 (-1 if one was taken). */
MICRO_FUNC(k_br_nt)
1:
	.rept U
	bne	a1, a1, 9f
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	li	a0, 0
	ret
9:	li	a0, -1
	ret
MICRO_ENDF(k_br_nt)

/* Taken conditional branches, each skipping one instruction (the
 * wrong-path addi). Returns the number of skipped addi that ran: 0. */
MICRO_FUNC(k_br_taken)
	li	a2, 0
1:
	.rept U
	beq	a1, a1, 2f
	addi	a2, a2, 1
2:
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a2
	ret
MICRO_ENDF(k_br_taken)

/* Unconditional jal x0 (j), each skipping one instruction. Returns 0. */
MICRO_FUNC(k_jal)
	li	a2, 0
1:
	.rept U
	j	2f
	addi	a2, a2, 1
2:
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a2
	ret
MICRO_ENDF(k_jal)

/* op = call + return: jal ra to a callee that is `addi a2, a2, 1; ret`
 * (jalr x0, ra). Returns the call count (ops). */
MICRO_FUNC(k_call_ret)
	mv	t6, ra
	li	a2, 0
1:
	.rept U
	jal	ra, micro_callee_inc
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a2
	jr	t6
MICRO_ENDF(k_call_ret)

/* As k_call_ret with an indirect call: jalr ra, 0(t5). */
MICRO_FUNC(k_jalr_call_ret)
	mv	t6, ra
	la	t5, micro_callee_inc
	li	a2, 0
1:
	.rept U
	jalr	ra, 0(t5)
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a2
	jr	t6
MICRO_ENDF(k_jalr_call_ret)

MICRO_FUNC(micro_callee_inc)
	addi	a2, a2, 1
	ret
MICRO_ENDF(micro_callee_inc)

/* Data-dependent branch pattern. a1 = pattern bytes (0 = taken,
 * 1 = not taken), 64 per trip. Each beqz targets the next instruction,
 * so both outcomes run the same instructions and differ only in the
 * redirect. op = andi + srli + add (counts not-taken, branch-free) +
 * beqz, plus 1/8 of ld + addi (one pattern word per 8 branches) and
 * 1/64 of the loop. Returns the not-taken count. */
MICRO_FUNC(k_brpat)
	li	a2, 0
1:
	.rept 8
	ld	t1, 0(a1)
	addi	a1, a1, 8
	.rept 8
	andi	t0, t1, 1
	srli	t1, t1, 8
	add	a2, a2, t0
	beqz	t0, 2f
2:
	.endr
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a2
	ret
MICRO_ENDF(k_brpat)

/* Dependent loads that hit: a1 points to a doubleword holding its own
 * address (load-to-use latency of an L1 hit). Returns a1. */
MICRO_FUNC(k_ld_dep)
1:
	.rept U
	ld	a1, 0(a1)
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	ret
MICRO_ENDF(k_ld_dep)

/* Independent loads that hit (eight words of one line, no consumer).
 * Returns the xor of the eight words. */
MICRO_FUNC(k_ld_indep)
1:
	.rept U / 8
	ld	t1, 0(a1)
	ld	t2, 8(a1)
	ld	t3, 16(a1)
	ld	t4, 24(a1)
	ld	t5, 32(a1)
	ld	t6, 40(a1)
	ld	a4, 48(a1)
	ld	a5, 56(a1)
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	xor	a0, t1, t2
	xor	a0, a0, t3
	xor	a0, a0, t4
	xor	a0, a0, t5
	xor	a0, a0, t6
	xor	a0, a0, a4
	xor	a0, a0, a5
	ret
MICRO_ENDF(k_ld_indep)

/* op = load + add. Distance 1: the add uses the load right before it
 * (load-use interlock). a1 = two words w0, w1. Returns the sum of
 * every loaded word = ops / 2 * (w0 + w1). */
MICRO_FUNC(k_ld_use1)
	li	a2, 0
1:
	.rept U / 2
	ld	t1, 0(a1)
	add	a2, a2, t1
	ld	t3, 8(a1)
	add	a2, a2, t3
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a2
	ret
MICRO_ENDF(k_ld_use1)

/* As k_ld_use1, but each add uses the load two instructions before it
 * (no interlock); t3 is preloaded so the sum is the same. */
MICRO_FUNC(k_ld_use2)
	li	a2, 0
	ld	t3, 8(a1)
1:
	.rept U / 2
	ld	t1, 0(a1)
	add	a2, a2, t3
	ld	t3, 8(a1)
	add	a2, a2, t1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a2
	ret
MICRO_ENDF(k_ld_use2)

/* Stores that hit: a2 to the eight words of the line at a1. */
MICRO_FUNC(k_st)
1:
	.rept U / 8
	sd	a2, 0(a1)
	sd	a2, 8(a1)
	sd	a2, 16(a1)
	sd	a2, 24(a1)
	sd	a2, 32(a1)
	sd	a2, 40(a1)
	sd	a2, 48(a1)
	sd	a2, 56(a1)
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	li	a0, 0
	ret
MICRO_ENDF(k_st)

/* rdcycle (csrr cycle). Returns last - first read. */
MICRO_FUNC(k_rdcycle)
	rdcycle	t2
1:
	.rept U
	rdcycle	t1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	sub	a0, t1, t2
	ret
MICRO_ENDF(k_rdcycle)

/* rdtime (csrr time = CLINT mtime). Returns last - first read. */
MICRO_FUNC(k_rdtime)
	rdtime	t2
1:
	.rept U
	rdtime	t1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	sub	a0, t1, t2
	ret
MICRO_ENDF(k_rdtime)

/* csrr of a plain M-mode CSR. Returns mscratch. */
MICRO_FUNC(k_csrr)
	li	t1, 0
1:
	.rept U
	csrr	t1, mscratch
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, t1
	ret
MICRO_ENDF(k_csrr)

/* csrw mscratch, a1. */
MICRO_FUNC(k_csrw)
1:
	.rept U
	csrw	mscratch, a1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	li	a0, 0
	ret
MICRO_ENDF(k_csrw)

/* csrrw a1, mscratch, a1 (swap; U is even, so a1 and mscratch end as
 * they started). Returns a1. */
MICRO_FUNC(k_csrrw)
1:
	.rept U
	csrrw	a1, mscratch, a1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	ret
MICRO_ENDF(k_csrrw)

/* fence (iorw, iorw). */
MICRO_FUNC(k_fence)
1:
	.rept U
	fence
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	li	a0, 0
	ret
MICRO_ENDF(k_fence)
