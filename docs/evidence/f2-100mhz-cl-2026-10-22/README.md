# 100 MHz core clock on F2: CL builds meet timing (#53, 2026-10-22, branch `53-100mhz-afi`)

These are the first full F2 CL builds with a 100 MHz core clock. They
build the oops-fix platform (`73-oops-fix`: 80 GiB DDR4 + HBM map,
finisher, RTC, OCL v4, the walker race fixes) with #53's FPGA timing
structures.

Both builds use `fpga/scripts/build_cl_sigil.sh --recipe-b B5
--recipe-hbm H0 --fpga-timing`:

- AWS_CLK_GEN group-B recipe **B5** gives `clk_extra_b1` = **100 MHz**,
  the core clock. aws-fpga v2.3.5 `hdk/docs/Clock_Recipes_User_Guide.md`
  lists B5 as `clk_extra_b0` 400 MHz and `clk_extra_b1` 100 MHz.
- The HBM AXI clock uses recipe H0, 250 MHz.
- `SIGIL_FPGA_TIMING` and `SIGIL_VRF_OREG` both reach CL synthesis. This
  is checked in each build's `synth_check.txt`.
- The flow is HDK v2.3.5 Small Shell, `BuildAll --aws_clk_gen
  --no-encrypt`, Vivado 2025.2 with `general.maxThreads` 16, the same
  as the oops-fix AFI.

**Both builds meet timing on every clock after route. Build 2 is the
AFI candidate.** No AFI has been created yet.

| | Build 1 [`b1-211218/`](b1-211218/README.md) | **Build 2 [`b2-232507/`](b2-232507/build-steps.txt)** |
|---|---|---|
| Source | `cb6c1a2` | **`cf63ab8`**. `rtl/` and `fpga/` are identical at the branch head `0deea68` |
| #53 review round 2 fixes | no | yes (`d8d5e92`: EX-capture walk-fault replay, fetch guest-fault flag) |
| Design WNS / TNS / WHS | +0.049 / 0 / +0.005 ns | **+0.033 / 0 / +0.005 ns** |
| Core clock (10 ns) WNS / WHS | +0.460 / +0.005 ns | **+0.336 / +0.005 ns** |
| Build time | 48 min | 51 min (gate chains ran on the same instance) |
| DCP tarball on sigil-fpga-build | `~/mhz100-cl/build-211218/checkpoints/2026_10_22-211218.Developer_CL.tar` | **`~/mhz100-cl/build-232507/checkpoints/2026_10_22-232507.Developer_CL.tar`** |
| Tarball sha256 | `f9ddd72b…3be813` | **`0fe4b1ea…50ca24c`** |

Build 1 ran from `cb6c1a2` before the #53 ISA review's round 2
FPGA_TIMING fixes landed on `53-mem-stage-pipeline` (`d8d5e92`). Those
fixes were merged here as `cf63ab8`, and build 2 was rebuilt from that
source with the same flow. The mmu_tb update that followed (`08c607a`,
merged as `0deea68`) is testbench only.

## Build 2: timing per clock (post-route)

The values come from [`b2-232507/post_route_timing_summary.rpt`](b2-232507/post_route_timing_summary.rpt)
and [`b2-232507/clock_summary.txt`](b2-232507/clock_summary.txt). The
build 1 values are in brackets.

| Clock | What | Period | Setup WNS | Hold WHS | Endpoints |
|---|---|---|---|---|---|
| `clk_out2_clk_mmcm_b` | Sigil core (`clk_extra_b1`, B5) | 10.000 ns (100 MHz) | **+0.336** [+0.460] | +0.005 [+0.005] | 90,496 |
| `clk_main_a0` | Shell AXI/OCL, DDR crossbar, HBM register slices | 4.000 ns (250 MHz) | **+0.033** [+0.049] | +0.010 [+0.009] | 122,479 |
| `mmcm_clkout0` | DDR4 controller | 3.752 ns (266.5 MHz) | +0.051 [+0.177] | +0.010 [+0.010] | 64,071 |
| `clk_out1_clk_mmcm_hbm` | HBM AXI (`clk_hbm_axi`, H0) | 4.000 ns (250 MHz) | +0.120 [+0.445] (recovery +0.318 [+0.097]) | +0.014 [+0.010] | 11,114 |
| `mmcm_clkout6` | DDR4 | 7.504 ns | +1.909 (into it from `mmcm_clkout0`: +1.339) | +0.011 | 5,950 |
| `clk_hbm_ref` | HBM reference | 10.000 ns | +4.691 (recovery +4.204) | +0.012 | 20,509 |
| `pll_clk[0..2]_DIV` | DDR4 PHY, from `mmcm_clkout0` | 3.752 ns | +0.565 | +0.633 | 1,288 |

- **Inter-clock (CDC, datapath-only constraints):**
  - `clk_main_a0` → core +3.593 ns; core → `clk_main_a0` +3.875 ns.
  - `clk_main_a0` → HBM AXI +2.907 ns; HBM AXI → `clk_main_a0` +1.181 ns.
- **Core async resets:** recovery +2.746 ns, removal +0.032 ns.
- **Bus skew:** all 43 `set_bus_skew` constraints of the CDC IP are met,
  worst +2.861 ns ([`b2-232507/bus_skew_summary.txt`](b2-232507/bus_skew_summary.txt)).

## Build 2: worst paths

[`b2-232507/worst_paths.txt`](b2-232507/worst_paths.txt) lists 10 setup
and 5 hold paths per clock, the inter-clock paths of the core, and the
net trace of the worst core path.

- **Core, +0.336 ns: data PMP → trap → CSR write enable.** The path
  goes from `u_csr/pmpaddr_q_reg[15]` through `g_pmp_par` (#53's
  parallel PMP) to `pmp_allow_data`. From there it runs through MEM's
  exception cause and `ack` to `csr_we`, and ends at the clock enables
  of `pmpaddr_q[11]`. It has 27 levels and is 77 % route (7.26 of
  9.47 ns).
  - 773 of the 931 core endpoints under +1.0 ns are this CSR enable
    fan-out ([`b2-232507/core_near_critical.txt`](b2-232507/core_near_critical.txt)).
  - The other groups under +1.0 ns:
    - `vls_started_q` → `u_mmu` (the VLS address into `mt_q`): +0.534 ns, 54 endpoints;
    - `memwb_rd_q`/FPU → `exmem_result_q`: from +0.542 ns;
    - the SoC reset → SHA-512 schedule: +0.737 ns. This was build 1's worst path, at +0.460 ns.
- **`clk_main_a0`, +0.033 ns (design WNS).** The path runs from the DDR
  crossbar SmartConnect (`DDR_XBAR` `s01_mmu`) into the `DDR_CDC` clock
  converter FIFO. It has one LUT, and 94 % of the delay is route. The
  next paths are inside the crossbar (+0.092 ns) and from
  `CDC_RST_MAIN` to the DDR stat pipeline `PIPE_DDR_STAT0` (+0.105 ns).
  - All of these are AWS/Xilinx IP or HDK template glue on the
    250 MHz Shell clock. Their slack moves between builds with
    placement: +0.232 ns at B1, +0.049 ns in build 1, +0.033 ns here.
    The core recipe does not change their logic.
- **DDR (`mmcm_clkout0`), +0.051 ns.** MIG PHY bitslice to the
  calibration registers, inside the DDR4 IP.
- **HBM AXI, +0.120 ns.** `AXI3_REG_SLC_HBM` → the AXI4→AXI3 converter's
  upsizer.
- **Hold.** The core's worst hold path is the OCL register CDC
  (`OCL_CDC` → `u_regs`), at +0.005 ns.

### Paths the SoC-only F0 run did not include, and CL changes

The SoC-only, out-of-context F0 run (`fpga/f0`, `iter`, `d7e8e41`)
reached +0.614 ns. Its worst paths were `vl_q → mt_q.pa` and the
SHA-512 round.

The CL builds add three things:

- the Shell clocking (the core clock crosses SLR0 → SLR2 and arrives
  at about 9.9 ns);
- the SLR2 pblock placement;
- the CL glue: OCL CDC, the DDR/HBM bridges and clock converters, the
  memory engine, UART and error capture.

In the two builds:

- **The worst core path changes with placement.** It is a different
  family in each build: the reset fan-out into SHA-512 in build 1, the
  CSR write enable in build 2. Each is met with 0.3–0.5 ns.
- **The CL glue meets timing.** The OCL CDC is met for hold at
  +0.005 ns. The core ↔ `clk_main_a0` crossings have +3.6 ns or more.
  The memory engine, UART and error capture are not among the core's
  near-critical endpoints in either build.
- **The thinnest margins are AWS IP at 250 MHz.** These are the DDR
  crossbar, the DDR4 MIG and the HBM converter, at +0.033 to +0.120 ns.

**No CL or RTL change was needed for timing.**

## Gates at the branch head `0deea68` (RTL = build 2's `cf63ab8`)

The gates ran on sigil-fpga-build alongside build 2. Full logs are in
[`gates.log`](gates.log).

| Gate | FPGA_TIMING off | FPGA_TIMING + VRF_OREG |
|---|---|---|
| Lint, Verilator 5.048 and 5.020, plus the FPGA tops and parameterized modules | rc 0 (12 FPGA lint lines OK) | (in the off chain) |
| Walker race set (`oops-ptw-walker`) | 42/42, `PTWINV violations=0` | 42/42, `PTWINV violations=0` |
| `make core-test`, which includes `fpgatop-f2-quick` | rc 0: 396 TB PASS, 0 FAIL; 74/74 directed in each of the 5 SRAM families; F2 PLATFORM PASS x5, F2 MEMTEST PASS | rc 0: 387 TB PASS, 0 FAIL; 74/74 directed (vrforeg, fpga); F2 PLATFORM PASS x5, F2 MEMTEST PASS |
| riscv-tests | 123/123 | 123/123 |
| Yosys equivalence, FPGA_TIMING=0 vs `73-oops-fix` `2968b6d` | sigil_csr, sigil_mmu, both caches, and sigil_core (default and SRAM_OREG): EQUIVALENT | n/a |

Notes on these runs:

- **First chain run, at `cf63ab8`.** `mmu_tb_fpga` failed in both
  settings at `mmu_tb.cpp:194`. The unit testbench did not yet drive
  sigil_mmu's new `dl_mem_i` port. The #53 branch fixed the testbench
  in `08c607a`, merged here as `0deea68`, without changing RTL. Every
  other step of that first run passed.
- **Scope.** These are the per-commit gates of `53-100mhz-afi`. The
  #53 branch's own full gates and its ISA review run separately, on
  `53-mem-stage-pipeline`. Full ACT and the Linux boot were not rerun
  at this head.

## Utilisation

| | Oops-fix (B1, 62.5 MHz, default) | Build 1 | Build 2 |
|---|---|---|---|
| CL LUTs / FFs | 131,259 / 117,030 | 130,732 / 117,738 | 131,100 / 117,758 |
| `SIGIL` LUTs / FFs | 82,201 / 36,602 | 81,869 / 37,346 | 82,280 / 37,320 |
| BRAM tiles / DSP | 76.5 / 32 | 76.5 / 32 | 76.5 / 32 |

Details are in `b*/post_route_util_cl.rpt` and `b*/post_route_util_hier.rpt`.

## Files

- **`b2-232507/` (AFI candidate) and `b1-211218/`**, one per build:
  - `build-steps.txt`: commands, build timeline, tarball location and
    hash, and the AFI commands for the lead;
  - `developer_cl_manifest.txt`: the tarball listing, `manifest.txt`
    (`clock_recipe_b=B5`, `clock_recipe_hbm=H0`, `dcp_hash`) and the
    tarball's sha256;
  - `post_route_timing_summary.rpt`: cut before "Timing Details";
  - `post_route_util_cl.rpt`, `post_route_util_hier.rpt`;
  - `clock_summary.txt`, `worst_paths.txt`, `core_near_critical.txt`,
    `main_a0_near_critical.txt`, `bus_skew_summary.txt`;
  - `synth_check.txt`.
- **Scripts.** These are read-only on the DCPs: [`rpt.tcl`](rpt.tcl),
  [`busskew.tcl`](busskew.tcl), [`synthcheck.tcl`](synthcheck.tcl),
  [`netcheck.tcl`](netcheck.tcl).
- [`gates.log`](gates.log): the gate chains and the equivalence proof
  at `0deea68` / `cf63ab8`.

## Not done here

- **No AFI yet.** Nothing has been uploaded, and `create-fpga-image` has
  not run. `b2-232507/build-steps.txt` has the commands.
- **No hardware run at 100 MHz yet.** This is static timing only.
  Debian and the F2 smoke tests at 100 MHz are still open.
- **`origin/main` is not merged here.** Since `73-oops-fix`, main has
  added simulation-only performance counters (#56, under
  `ifndef SYNTHESIS`, plus two cache taps that drive nothing) and the
  Linux release docs. None of that changes a netlist.
