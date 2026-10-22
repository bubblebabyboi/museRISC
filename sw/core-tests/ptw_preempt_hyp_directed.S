// Fetch-walk preemption with G-stage walks (issue #73 skeptic
// review): ptw_gwidth_directed.S with page B validly mapped, so the
// speculative page-B fetch walk is a 7-read two-stage walk (W_G_READ
// / W_VS_READ) that the guest load's data miss preempts at every
// point of the NOP-sled sweep. None of the hunters' tests runs with
// V=1, so this is the only one that exercises walk_preempt_o from
// W_G_READ. Fails on 73-linux-release RTL, must pass with the fix.
#define PTW_HYP_GOOD_B 1
#include "ptw_gwidth_directed.S"
