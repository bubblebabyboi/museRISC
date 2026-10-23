# 100 MHz core clock on F2: CL build 2026_10_22-211218 meets timing (#53, 2026-10-22, branch `53-100mhz-afi`)

> **Superseded as the AFI source by build 2 (`../b2-232507/`).** This
> build is from `cb6c1a2`. The #53 review round 2 FPGA_TIMING fixes
> (`53-mem-stage-pipeline` `d8d5e92`, merged as `cf63ab8`) landed after
> it was built. Its timing results remain valid for `cb6c1a2`. See
> [`../README.md`](../README.md).

This is the first full F2 CL build with a 100 MHz core clock. It is the
oops-fix platform (`73-oops-fix`: 80 GiB DDR4 + HBM map, finisher, RTC,
OCL v4, the walker race fixes) with #53's FPGA timing structures, built
as the source for a 100 MHz AFI. **Every clock meets timing after route,
and the post-route DCP is not marked `.VIOLATED`.** No AFI has been
created from it yet.

| | |
|---|---|
| Source | `53-100mhz-afi` `cb6c1a2` (`git archive` export; all 677 files checked by sha256) |
| Script | `fpga/scripts/build_cl_sigil.sh --recipe-b B5 --recipe-hbm H0 --fpga-timing` |
| Core clock | AWS_CLK_GEN `clk_extra_b1`, recipe **B5 = 100 MHz** (`SIGIL_CORE_CLK_KHZ=100000`) |
| HBM AXI clock | `clk_hbm_axi`, recipe H0 = 250 MHz (unchanged) |
| Defines | `SIGIL_FPGA_TIMING` and `SIGIL_VRF_OREG`. Both reach CL synthesis; see [`synth_check.txt`](synth_check.txt) |
| Flow | HDK v2.3.5 Small Shell, `BuildAll --aws_clk_gen --no-encrypt`, Vivado 2025.2, `general.maxThreads` 16 |
| Build time | 48 min (21:12 to 22:00 UTC) |
| Result | WNS **+0.049 ns** (in `clk_main_a0`), TNS 0, WHS **+0.005 ns**, THS 0, 0 failing endpoints |
| Core clock | WNS **+0.460 ns** at 10 ns, WHS +0.005 ns |
| DCP tarball | `sigil-fpga-build:~/mhz100-cl/build-211218/checkpoints/2026_10_22-211218.Developer_CL.tar`, sha256 `f9ddd72b…e813` |

## Timing per clock (post-route)

The values come from [`post_route_timing_summary.rpt`](post_route_timing_summary.rpt)
(intra-clock tables) and [`clock_summary.txt`](clock_summary.txt).

| Clock | What | Period | Setup WNS | Hold WHS | Endpoints |
|---|---|---|---|---|---|
| `clk_out2_clk_mmcm_b` | Sigil core (`clk_extra_b1`, B5) | 10.000 ns (100 MHz) | **+0.460** | +0.005 | 90,524 |
| `clk_main_a0` | Shell AXI/OCL, DDR crossbar, HBM register slices | 4.000 ns (250 MHz) | **+0.049** | +0.009 | 122,465 |
| `mmcm_clkout0` | DDR4 controller | 3.752 ns (266.5 MHz) | +0.177 | +0.010 | 64,141 |
| `clk_out1_clk_mmcm_hbm` | HBM AXI (`clk_hbm_axi`, H0) | 4.000 ns (250 MHz) | +0.445 (recovery +0.097) | +0.010 | 11,114 |
| `mmcm_clkout6` | DDR4 | 7.504 ns | +1.957 | +0.014 | 5,950 |
| `clk_hbm_ref` | HBM reference | 10.000 ns | +3.614 (recovery +3.343) | +0.012 | 20,513 |
| `pll_clk[0..2]_DIV` | DDR4 PHY, from `mmcm_clkout0` | 3.752 ns | +0.111 | +0.663 | 1,288 |

Inter-clock paths (CDC, datapath-only constraints):

- `clk_main_a0` → core +3.591 ns; core → `clk_main_a0` +3.878 ns.
- `clk_main_a0` → HBM AXI +2.925 ns; HBM AXI → `clk_main_a0` +1.157 ns.

Async resets: the core's recovery checks are at +2.254 ns and its
removal checks at +0.059 ns (`**async_default**`).

Bus skew: all 43 `set_bus_skew` constraints of the CDC IP are met, worst
+2.838 ns ([`bus_skew_summary.txt`](bus_skew_summary.txt)).

## Worst paths

[`worst_paths.txt`](worst_paths.txt) lists the 10 worst setup paths and
the 5 worst hold paths for each of these four clocks, plus the worst
inter-clock paths into and out of the core clock.

- **Core, +0.460 ns: reset fan-out.** The path runs from `u_soc/rst_sync_q_reg`
  to the clock enables of `u_sha512/w_reg[56][*]`. It has one LUT and is
  98 % route (9.37 of 9.59 ns). The reset net has a fanout of 18,928
  and needs 6.7 ns of route, from SLICE_X114Y529 to X204Y712, both in
  SLR2. The 64-load enable net adds 2.7 ns. Twelve endpoints have less
  than 1 ns of slack.
- **Core, +0.482 ns: vector access to the registered data translation.**
  The path runs from `u_csr/vl_q_reg[1]` to `u_mmu/g_dreg.mt_q_reg[pa][*]`
  through 27 levels (8 of them CARRY8). The chain is the VLS `vl`
  in-range compare (`vls_vl_eff`), then the D-port select
  (`g_dl.dl_mem`), the `exmem` address, `hgatp`/`vs_bare`, the TLB
  match and finally `mt_q`. That is #53's registered data-port lookup
  (step 5), driven by a vector element address (family A). It has
  46 endpoints, all into `mt_q[pa]`.
- **Rest of the core.** The next paths go from the FPU and
  `memwb_valid_q` to `exmem_result_q` at +0.665 ns or more. Only 75
  core endpoints have less than 1.0 ns of slack
  ([`core_near_critical.txt`](core_near_critical.txt)).
- **`clk_main_a0`, +0.049 ns (design WNS).** This is AWS/Xilinx IP, not
  Sigil: inside the DDR crossbar SmartConnect (`DDR_XBAR` `s00_mmu`), a
  one-LUT, route-dominated path. After it come the HBM register slices
  `HBM_SLC2 → HBM_SLC1 → HBM_SLC0` at +0.196 ns or more
  ([`main_a0_near_critical.txt`](main_a0_near_critical.txt)). In the
  62.5 MHz oops-fix build, `clk_main_a0` had +0.232 ns. These paths
  are fixed Shell-side IP on a 250 MHz clock, and the core recipe
  does not change them.
- **DDR (`mmcm_clkout0`), +0.177 ns.** MIG PHY bitslice to calibration
  registers, inside the DDR4 IP.
- **HBM AXI, +0.445 ns setup and +0.097 ns recovery.** The setup path
  runs from the HBM AXI port to `AXI3_REG_SLC_HBM`. The recovery path
  runs from the HBM wrapper's reset pipe to the `ARESET_N` pins of the
  HBM core.

### Compared with the SoC-only F0 run

The SoC-only, out-of-context F0 run (`fpga/f0`, `iter` strategy, at
`d7e8e41`) reached +0.614 ns at 10 ns. Its worst paths were
`vl_q → mt_q.pa` at +0.614 ns and the SHA-512 round → `h` at
+0.766 ns, with 1,201 endpoints under +1.0 ns
(`../../fpga-timing-53-iterations-2026-10-22.log`). In this CL build:

- **The F0 critical family is better.** `vl_q → mt_q.pa` is at
  +0.482 ns over 27 levels.
- **There are far fewer near-critical endpoints:** 75 under +1.0 ns,
  against 1,201 in F0.
- **The worst core path is new.** It is the reset fan-out into the
  SHA-512 schedule, at +0.460 ns, and it does not appear in F0's list.
  In the CL the SoC is placed in the SLR2 pblock. The reset net
  (fanout 18,928) needs 6.7 ns of route there to reach the clock
  enables of the hash's `w[80]` array. #53 step 13 (the 16-word
  SHA-512 window) is the planned fix; replicating the reset or setting
  `MAX_FANOUT` on `rst_sync_q` would also work. None is needed for
  this build.
- **The core clock's insertion delay.** The clock crosses SLR0 → SLR2
  and arrives at about 9.9 ns. The data paths of the worst core paths
  stay inside SLR2.

The CL glue that F0 does not include meets timing:

- **OCL register CDC** (`OCL_CDC` → `u_regs`): hold +0.005 ns. This is
  the core's worst hold path, and it is met.
- **Core ↔ `clk_main_a0` crossings** (OCL and DDR clock converters):
  +3.591 ns and +3.878 ns setup. Bus skew is met (above).
- **Memory engine, UART and error capture:** none of them is among the
  75 core endpoints below 1 ns.

No CL change was needed.

## Comparison with the 62.5 MHz oops-fix AFI build

The oops-fix build is `2026_10_22-143914`, from `31a1568`, B1 + H0,
default configuration.

| | Oops-fix (B1, 16 ns, default) | This build (B5, 10 ns, FPGA_TIMING + VRF_OREG) |
|---|---|---|
| Core WNS / WHS | +0.095 / +0.011 | +0.460 / +0.005 |
| Design WNS / WHS | +0.095 / +0.010 | +0.049 / +0.005 |
| CL LUTs / FFs | 131,259 / 117,030 | 130,732 / 117,738 |
| `SIGIL` LUTs / FFs | 82,201 / 36,602 | 81,869 / 37,346 |
| BRAM tiles / DSP | 76.5 / 32 | 76.5 / 32 |
| Build time | 1 h 16 min | 48 min |

In `SIGIL`, the FPGA setting adds 744 flops, mainly the registered
translations (`mt_q`, `it_q`) and the VRF output registers, and uses
332 fewer LUTs. Outside `SIGIL`, the CL differs by about 200 LUTs and
40 flops, which is place-and-route variation. Utilisation:
[`post_route_util_cl.rpt`](post_route_util_cl.rpt) and
[`post_route_util_hier.rpt`](post_route_util_hier.rpt).

## Files

- [`build-steps.txt`](build-steps.txt): the commands, build timeline,
  tarball location and hash, and the AFI commands for the lead.
- [`developer_cl_manifest.txt`](developer_cl_manifest.txt): the tarball
  listing, `manifest.txt` (`clock_recipe_b=B5`, `clock_recipe_hbm=H0`,
  `dcp_hash`) and the tarball's sha256.
- [`post_route_timing_summary.rpt`](post_route_timing_summary.rpt):
  `report_timing_summary -max_paths 5`, cut before "Timing Details",
  as in the earlier F2 evidence.
- [`post_route_util_cl.rpt`](post_route_util_cl.rpt),
  [`post_route_util_hier.rpt`](post_route_util_hier.rpt).
- [`clock_summary.txt`](clock_summary.txt),
  [`worst_paths.txt`](worst_paths.txt),
  [`core_near_critical.txt`](core_near_critical.txt),
  [`main_a0_near_critical.txt`](main_a0_near_critical.txt),
  [`bus_skew_summary.txt`](bus_skew_summary.txt).
- [`synth_check.txt`](synth_check.txt): the defines in the build log,
  the `FPGA_TIMING` parameter bindings, and the cell and net checks
  on the post-synth netlist.
- Scripts, all read-only on the DCPs: [`rpt.tcl`](../rpt.tcl),
  [`busskew.tcl`](../busskew.tcl), [`synthcheck.tcl`](../synthcheck.tcl),
  [`netcheck.tcl`](../netcheck.tcl).

## Not done here

- **No AFI yet.** The tarball has not been uploaded and
  `create-fpga-image` has not run (`build-steps.txt` has the commands).
- **No 100 MHz hardware run yet.** This build passes static timing
  only. The RTL in the FPGA setting passed the `53-100mhz-afi` gates
  ([`../fpga-timing-100mhz-afi-53-2026-10-22/`](../../fpga-timing-100mhz-afi-53-2026-10-22/README.md)).
  Debian and the F2 smoke tests at 100 MHz are still open.
- **Margin.** The design WNS (+0.049 ns) is in AWS IP running on
  `clk_main_a0`, which this build does not change. The core has
  +0.460 ns.
