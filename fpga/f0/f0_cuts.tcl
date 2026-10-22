# #53 cut steps for f0_timing_reports.tcl (standalone mode): each step
# false-paths everything through the nets it matches, on top of the
# previous steps, so the next layer of failing paths shows. Nets are
# matched by the names they keep after synthesis (RTL signal and
# function-return names), so the regexps follow the routed netlist.
# Only cuts that a name can isolate: the fetch PMP / fetch-control
# logic and the walker's TLB fill have no surviving net name in common.
set cuts {
  {d_translate {{.*/mmu_d_[a-z_]+(\[[0-9]+\])?} {.*/pmp_allow_data}}}
  {tlb_lookup  {{.*/entry_match[a-z0-9_]*(\[[0-9]+\])?}
                {.*/fetch_va[0-9]*(\[[0-9]+\])?} {.*/perm_ok[a-z0-9_]*}}}
}
