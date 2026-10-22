// ptw_svadu_race_directed.S as a VS-mode guest (issue #73 review,
// Svadu atomicity under two-stage translation). The fetch walk of
// page B reads its VS leaf PTE, then walks the G stage for that
// PTE's own GPA (W_G_READ, g purpose 2) before the VS A/D
// write-back (W_VS_UPD); an older store to the PTE must not get
// the port anywhere in between, or the write-back overwrites it.
// Fails if the walker keeps the port only in W_VS_UPD / W_G_UPD.
#define PTW_SVADU_HYP 1
#include "ptw_svadu_race_directed.S"
