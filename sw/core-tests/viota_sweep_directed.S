// viota.m sweep as a directed core test: the riscv-dv program
// sim/riscv-dv/directed/sigil_viota_test.S with VIOTA_SWEEP, all 1408
// combinations in one run (22 legal vtypes x tu/ta x mu/ma x
// unmasked/v0.t x 8 AVL classes incl. 0, 1, VLMAX-1, VLMAX, VLMAX+1),
// vs2 mostly an odd register (not aligned to any LMUL > 1), every
// element of the vd group and every other register checked (issue #8:
// vs2 is one mask register whatever LMUL is). Not in the directed
// suite (about 40M cycles); run by hand. Exit store 0 = pass, else
// iteration << 8 | failure code (combination = iteration).
#define SIGIL_CORE_TEST 1
#define VIOTA_SWEEP 1
#define RDV_SEED 0x5eed
#define ITERS 1408
#define SWEEP_START 0
#include "../../sim/riscv-dv/directed/sigil_viota_test.S"
