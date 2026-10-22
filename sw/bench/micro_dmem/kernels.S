/* micro_dmem kernels: data-side memory hierarchy, pointer chase and
 * streams (../micro_common/README.md). Convention:
 * ../micro_common/micro_asm.h. One operation = one load or store. */
#include "micro_asm.h"

	.option norvc

MICRO_FUNC(k_empty)
	li	a0, 0
	ret
MICRO_ENDF(k_empty)

/* Pointer chase: a1 = first node; each node's first doubleword holds
 * the next node's address. 64 dependent loads per trip. Returns the
 * node reached. */
MICRO_FUNC(k_chase)
1:
	.rept 64
	ld	a1, 0(a1)
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	ret
MICRO_ENDF(k_chase)

/* Load stream: a1 = position, [a2, a3) = buffer (a multiple of 512
 * bytes, a1 inside it, line-aligned). Each trip loads 8 consecutive
 * 64-byte lines, every doubleword of each (64 independent loads, no
 * consumer), wrapping from a3 to a2. Returns the xor of the last line's
 * eight words. */
MICRO_FUNC(k_stream_ld)
1:
	.rept 8
	ld	t1, 0(a1)
	ld	t2, 8(a1)
	ld	t3, 16(a1)
	ld	t4, 24(a1)
	ld	t5, 32(a1)
	ld	t6, 40(a1)
	ld	a4, 48(a1)
	ld	a5, 56(a1)
	addi	a1, a1, 64
	.endr
	beq	a1, a3, 3f
2:	addi	a0, a0, -1
	bnez	a0, 1b
	xor	a0, t1, t2
	xor	a0, a0, t3
	xor	a0, a0, t4
	xor	a0, a0, t5
	xor	a0, a0, t6
	xor	a0, a0, a4
	xor	a0, a0, a5
	ret
3:	mv	a1, a2
	j	2b
MICRO_ENDF(k_stream_ld)

/* Store stream: as k_stream_ld, storing a4 to every doubleword. */
MICRO_FUNC(k_stream_st)
1:
	.rept 8
	sd	a4, 0(a1)
	sd	a4, 8(a1)
	sd	a4, 16(a1)
	sd	a4, 24(a1)
	sd	a4, 32(a1)
	sd	a4, 40(a1)
	sd	a4, 48(a1)
	sd	a4, 56(a1)
	addi	a1, a1, 64
	.endr
	beq	a1, a3, 3f
2:	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	ret
3:	mv	a1, a2
	j	2b
MICRO_ENDF(k_stream_st)
