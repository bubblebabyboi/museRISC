// viota.m directed core test: the riscv-dv program
// sim/riscv-dv/directed/sigil_viota_test.S (self-checking; see its
// header) built as a core test with a fixed seed and 32 iterations.
// Random legal vtype/AVL/policies, masked and unmasked, vs2 any
// register outside the vd group (issue #8: vs2 is one mask register
// whatever LMUL is), plus the encodings that must trap (vd not
// aligned, v0.t with vd = v0, vill). Exit store 0 = pass, else
// iteration << 8 | failure code.
#define SIGIL_CORE_TEST 1
#define RDV_SEED 0x10a7
#define ITERS 32
#include "../../sim/riscv-dv/directed/sigil_viota_test.S"
