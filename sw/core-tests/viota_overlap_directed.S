// viota.m with vs2 inside the vd group: the encoding breaks the
// overlap rule of RVV 1.0 sec. 15.8 and is reserved (sec. 5.2);
// Sigil raises an illegal-instruction exception for it, as Spike
// does. Half the iterations of sim/riscv-dv/directed/
// sigil_viota_test.S pick vs2 inside the vd group (any LMUL, any
// position in the group) and expect the trap with no register
// changed; the other half are the program's usual cases. Before
// the overlap check (RTL up to 4958c3f) Sigil executed these.
#define SIGIL_CORE_TEST 1
#define RDV_SEED 0x0e1a
#define ITERS 32
#define VIOTA_OVERLAP 1
#include "../../sim/riscv-dv/directed/sigil_viota_test.S"
