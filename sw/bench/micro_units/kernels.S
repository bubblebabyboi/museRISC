/* micro_units kernels: M unit and FPU latency (dependent chains) and
 * back-to-back throughput (independent ops) (../micro_common/README.md).
 * Convention: ../micro_common/micro_asm.h. U operations per loop trip;
 * one operation = one instruction. FP kernels: a0 = trips, operands in
 * fa0.., result in fa0. Rounding mode: dynamic (fcsr.frm = RNE). */
#include "micro_asm.h"

#define U 64

	.option norvc

MICRO_FUNC(k_empty)
	li	a0, 0
	ret
MICRO_ENDF(k_empty)

/* Integer, a1 = x, a2 = y. Dependent: a1 = a1 op a2, returns a1.
 * Independent: t2..t5 = a1 op a2, returns t5. */
.macro INT_DEP name, op
MICRO_FUNC(\name)
1:
	.rept U
	\op	a1, a1, a2
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, a1
	ret
MICRO_ENDF(\name)
.endm

.macro INT_INDEP name, op
MICRO_FUNC(\name)
1:
	.rept U / 4
	\op	t2, a1, a2
	\op	t3, a1, a2
	\op	t4, a1, a2
	\op	t5, a1, a2
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, t5
	ret
MICRO_ENDF(\name)
.endm

/* FP, two operands: dependent fa0 = fa0 op fa1; independent
 * ft0..ft3 = fa0 op fa1, returns ft3. One operand (sqrt): fa0 = op(fa0)
 * and ft0..ft3 = op(fa0). */
.macro FP2_DEP name, op
MICRO_FUNC(\name)
1:
	.rept U
	\op	fa0, fa0, fa1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	ret
MICRO_ENDF(\name)
.endm

.macro FP2_INDEP name, op, fmv
MICRO_FUNC(\name)
1:
	.rept U / 4
	\op	ft0, fa0, fa1
	\op	ft1, fa0, fa1
	\op	ft2, fa0, fa1
	\op	ft3, fa0, fa1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	\fmv	fa0, ft3
	ret
MICRO_ENDF(\name)
.endm

.macro FP1_DEP name, op
MICRO_FUNC(\name)
1:
	.rept U
	\op	fa0, fa0
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	ret
MICRO_ENDF(\name)
.endm

.macro FP1_INDEP name, op, fmv
MICRO_FUNC(\name)
1:
	.rept U / 4
	\op	ft0, fa0
	\op	ft1, fa0
	\op	ft2, fa0
	\op	ft3, fa0
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	\fmv	fa0, ft3
	ret
MICRO_ENDF(\name)
.endm

	INT_DEP		k_mul_dep, mul
	INT_INDEP	k_mul_indep, mul
	INT_DEP		k_div_dep, div
	INT_INDEP	k_div_indep, div
	INT_DEP		k_divw_dep, divw
	INT_INDEP	k_rem_indep, rem

	FP2_DEP		k_fadd_d_dep, fadd.d
	FP2_INDEP	k_fadd_d_indep, fadd.d, fmv.d
	FP2_DEP		k_fmul_d_dep, fmul.d
	FP2_DEP		k_fdiv_d_dep, fdiv.d
	FP2_INDEP	k_fdiv_d_indep, fdiv.d, fmv.d
	FP1_DEP		k_fsqrt_d_dep, fsqrt.d
	FP1_INDEP	k_fsqrt_d_indep, fsqrt.d, fmv.d
	FP2_DEP		k_fdiv_s_dep, fdiv.s
	FP1_DEP		k_fsqrt_s_dep, fsqrt.s

/* fa0 = fa0 * fa1 + fa2, dependent through fa0. */
MICRO_FUNC(k_fmadd_d_dep)
1:
	.rept U
	fmadd.d	fa0, fa0, fa1, fa2
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	ret
MICRO_ENDF(k_fmadd_d_dep)
