// viota.m with vstart != 0 must raise an illegal-instruction
// exception (RVV 1.0 sec. 15.8; Spike does). Half the iterations of
// sim/riscv-dv/directed/sigil_viota_test.S run viota.m after
// csrw vstart (1..64) and expect the trap with no register changed;
// the other half are the program's usual cases. Before the vstart
// check (RTL up to 4958c3f) Sigil executed viota.m from vstart
// (exit value 257: iteration 1, code 1 = trap not taken).
#define SIGIL_CORE_TEST 1
#define RDV_SEED 0x10a7
#define ITERS 32
#define VIOTA_VSTART 1
#include "../../sim/riscv-dv/directed/sigil_viota_test.S"
