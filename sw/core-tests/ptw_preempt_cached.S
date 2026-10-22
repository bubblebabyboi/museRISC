// ptw_preempt_directed.S with the page tables in cacheable RAM, as
// under Linux: PTE reads go through the L1 D$ (refill misses on the
// first pass, hits after that).
#define PTW_PREEMPT_CACHED_PT
#include "ptw_preempt_directed.S"
