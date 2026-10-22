// Control for ptw_preempt_directed.S: the same tables, passes and
// checks, but the load is the first of the 16 words before the page
// end, so its data walk completes before IF reaches page B and the
// fetch walk never overlaps it. Must pass.
#define PTW_PREEMPT_CONTROL
#include "ptw_preempt_directed.S"
