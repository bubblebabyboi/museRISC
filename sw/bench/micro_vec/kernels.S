/* micro_vec kernels: vsetvli cost and element-serial vector throughput
 * versus VL (../micro_common/README.md). Convention:
 * ../micro_common/micro_asm.h. U vector instructions per loop trip;
 * one operation = one vector instruction. The measured kernels use the
 * vl/vtype and the v8 (vd/vs1) and v16 (vs2) groups set up by the
 * k_vinit_* / k_vset_* helpers, which run outside the measured region
 * (the C driver is built without V, so nothing between the calls
 * touches vector state). */
#include "micro_asm.h"

#define U 32

	.option norvc
	.option arch, +v

MICRO_FUNC(k_empty)
	li	a0, 0
	ret
MICRO_ENDF(k_empty)

/* vsetvli with an unchanged vtype and AVL. Returns vl. */
MICRO_FUNC(k_vsetvli_same)
1:
	.rept U
	vsetvli	t1, a1, e8, m8, ta, ma
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, t1
	ret
MICRO_ENDF(k_vsetvli_same)

/* vsetvli alternating e8/m8 and e32/m1. Returns the last vl. */
MICRO_FUNC(k_vsetvli_toggle)
1:
	.rept U / 2
	vsetvli	t1, a1, e8, m8, ta, ma
	vsetvli	t1, a1, e32, m1, ta, ma
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	mv	a0, t1
	ret
MICRO_ENDF(k_vsetvli_toggle)

/* Setup helpers (not measured). a0 = vl; returns the vl granted. */
MICRO_FUNC(k_vset_e8m8)
	vsetvli	a0, a0, e8, m8, ta, ma
	ret
MICRO_ENDF(k_vset_e8m8)

/* v8 = a1[0..vl), v16 = a2[0..vl). */
MICRO_FUNC(k_vinit_e8)
	vsetvli	a0, a0, e8, m8, ta, ma
	vle8.v	v8, (a1)
	vle8.v	v16, (a2)
	ret
MICRO_ENDF(k_vinit_e8)

MICRO_FUNC(k_vinit_e64)
	vsetvli	a0, a0, e64, m1, ta, ma
	vle64.v	v8, (a1)
	vle64.v	v16, (a2)
	ret
MICRO_ENDF(k_vinit_e64)

/* a1[0..vl) = v8. */
MICRO_FUNC(k_vstore_e8)
	vsetvli	a0, a0, e8, m8, ta, ma
	vse8.v	v8, (a1)
	ret
MICRO_ENDF(k_vstore_e8)

MICRO_FUNC(k_vstore_e64)
	vsetvli	a0, a0, e64, m1, ta, ma
	vse64.v	v8, (a1)
	ret
MICRO_ENDF(k_vstore_e64)

/* Arithmetic, dependent through v8: v8 = v8 op v16 (for vredsum:
 * v8[0] = v8[0] + sum(v16)). */
.macro VARITH name, op, vd, vs2, vs1
MICRO_FUNC(\name)
1:
	.rept U
	\op	\vd, \vs2, \vs1
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	li	a0, 0
	ret
MICRO_ENDF(\name)
.endm

	VARITH	k_vadd, vadd.vv, v8, v8, v16
	VARITH	k_vmul, vmul.vv, v8, v8, v16
	VARITH	k_vfadd, vfadd.vv, v8, v8, v16
	VARITH	k_vredsum, vredsum.vs, v8, v16, v8

/* Unit-stride byte load / store of v8 at a1 (current vl, e8). */
MICRO_FUNC(k_vle8)
1:
	.rept U
	vle8.v	v8, (a1)
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	li	a0, 0
	ret
MICRO_ENDF(k_vle8)

MICRO_FUNC(k_vse8)
1:
	.rept U
	vse8.v	v8, (a1)
	.endr
	addi	a0, a0, -1
	bnez	a0, 1b
	li	a0, 0
	ret
MICRO_ENDF(k_vse8)
