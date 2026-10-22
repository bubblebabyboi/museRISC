// ptw_gwidth_directed.S without phase 0 (issue #73 skeptic review):
// only the data-walk consumers of the stale G-root read left by a
// W_G_READ GPA-width-fault exit (the guest load's data walk starts
// after the speculative page-B fetch walk faulted, with that read
// still in flight). Small sled lengths are plain fetch-walk
// preemptions and pass with the preemption fix; the first failing
// n marks the width-fault window.
#define PTW_GW_DATA_ONLY 1
#include "ptw_gwidth_directed.S"
