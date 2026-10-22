/* micro_imem kernels: instruction-side footprint sweep
 * (../micro_common/README.md). Convention: ../micro_common/micro_asm.h.
 * One operation = one 32-bit addi of the straight-line block. */
#include "micro_asm.h"

#define BLOCK_BYTES (32 * 1024)

	.option norvc

MICRO_FUNC(k_empty)
	li	a0, 0
	ret
MICRO_ENDF(k_empty)

/* Calls a2 (an entry point into k_block) trips times; a1 counts the
 * executed addi. Returns a1. */
MICRO_FUNC(k_ifoot)
	mv	t6, ra
1:	jalr	ra, 0(a2)
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	jr	t6
MICRO_ENDF(k_ifoot)

/* 32 KiB of straight-line `addi a1, a1, 1` (8192 instructions), then
 * ret. Entering at k_block_end - S runs a footprint of S bytes. */
MICRO_FUNC(k_block)
	.rept BLOCK_BYTES / 4
	addi	a1, a1, 1
	.endr
	.globl	k_block_end
k_block_end:
	ret
MICRO_ENDF(k_block)
