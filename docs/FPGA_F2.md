# AWS EC2 F2 FPGA bring-up plan

Goal: run real code on the in-house `sigil_core` on an
AWS EC2 F2 FPGA at a core clock of **100 MHz or higher**,
with evidence captured from the host runtime (not just a
synthesis timing report). End state: baremetal tests, then
OpenSBI + Linux to `SIGIL_LINUX_BOOT_OK`, using the same
payloads already proven in `soc_tb` / QEMU (`docs/QEMU.md`).

This plan starts only after the #31 OpenROAD rerun closes
timing/liberty on the crypto macro (done 2026-10-14:
setup WS 4.34 ns, TNS 0 at the 100 MHz constraint; that
result is for `sigil_crypto_top` on nangate45 and says
nothing about core Fmax on FPGA — see below).

## Feasibility check (2026-10-21, research only — nothing launched)

Verdict: **the whole SoC (core + vector unit + L1s + crypto engine +
peripherals) fits comfortably; reaching 100 MHz is the open risk.**

- **Resources** (Yosys `synth_xilinx -family xcup`, whole `sigil_soc_top`,
  [`fpga-yosys-estimate-32-2026-10-21.log`](evidence/fpga-yosys-estimate-32-2026-10-21.log)):
  ~110k LUTs (109,339 logic + ~544 LUTRAM), 31,652 FFs, 32 DSP48E2,
  9 RAMB36 — about 8–9% of the VU47P's ~1.3M LUTs (2,851,800 logic
  cells / 162,960 CLBs × 8 LUTs; derived, confirm in DS890), <2% of FFs
  and DSPs. This is a Yosys estimate (20,281 separate INV cells that
  Vivado folds into LUTs); it excludes the AWS Shell, DDR4 controller,
  CL wrapper, virtual UART and AXI bridge. F0 replaces it with Vivado
  numbers.
- **Readiness gaps 1–3 above are closed on `main`:** synthesizable SoC
  (`rtl/soc/sigil_soc_top.sv`, #4), L1 I$/D$ with a latency-tolerant
  bus (#44), multi-cycle FPU and M unit (#41/#43), element-serial
  vector unit with a banked sync-read VRF (#38), vector FP on the
  shared FPU (#47). Gap 4 (Vivado elaboration) remains F0.
- **Fmax expectation:** the unrepaired Nangate45 worst path is 6.19 ns
  (`vls_started_q` → vector `cnt_ok_q`, `docs/SOC_AREA.md`). FPGA
  fabric is typically 2–4× slower on the same logic depth, so a first
  build may land around 50–80 MHz; 100 MHz likely needs a few vector /
  FPU paths pipelined. A labelled lower-clock interim bitstream is an
  acceptable first step.
- **Tooling:** the AWS F2 HDK supports the Small Shell only (no built-in
  DMA; CL gets the full top SLR), base clocks 250 MHz `clk_main_a0` and
  100 MHz `clk_hbm_ref`, other frequencies via `AWS_CLK_GEN` recipes.
  Supported Vivado per the HDK docs: 2024.2 / 2025.1 / 2025.2 (2025.2
  ships on the current Developer AMI). The `vivado_rnd` host has Vivado
  2026.1 with `virtexuplusHBM` device files but **no license**, and the
  VU47P is not a free-edition device — F0 must run on the AWS FPGA
  Developer AMI (license included on EC2), on a non-F2 compute instance.
- **Work still to build for F3:** ~~core bus → AXI4 bridge to Shell
  DDR4~~ (done in F1, below), ~~OCL AXI-Lite mapping of the virtual UART +
  control/reset/cycle counter that `sigil_fpga_top` exposes, host loader
  for OpenSBI/Image/DTB~~ (done in F3, below).
- **Cost:** `f2.6xlarge` ≈ $1.98/h On-Demand in us-east-1/us-west-2
  (third-party price trackers; spot seen ≈ $0.67/h). Account F-instance
  quota (128 vCPUs) covers one. Builds (30–90 min) run off-F2.

## F0 result (2026-10-21, #51)

Vivado 2025.2 (F2 Developer AMI 1.19.2) out-of-context synthesis + full
implementation of the whole `sigil_soc_top` for `xcvu47p-fsvh2892-2-e`
(F2 Small Shell part, aws-fpga HDK v2.3.5), 100 MHz constraint, script
`fpga/f0/f0_ooc.tcl`, on an r7iz.8xlarge build instance: **27 min wall**
(synth 2:49, place 7:56, route 13:05). Reports:
[`evidence/fpga-f0-2026-10-21/`](evidence/fpga-f0-2026-10-21/).

| Resource | Used | VU47P | % |
|---|---:|---:|---:|
| CLB LUTs | 78,699 | 1,303,680 | 6.04 |
| CLB registers | 32,463 | 2,607,360 | 1.25 |
| RAMB36 | 9 | 2,016 | 0.45 |
| DSP48E2 | 29 | 9,024 | 0.32 |
| URAM | 0 | 960 | 0 |

- Timing at 10 ns: setup WNS **−4.703 ns** (TNS −48,526 ns, 19,765 failing
  endpoints), hold WHS +0.042 ns → about **68 MHz** today.
- Worst path: vector register file BRAM read (`u_vregfile ... mem_q_reg`,
  no BRAM output register) → 63 logic levels (17 CARRY8) → core
  `exmem_result_q`. 65% of the delay is routing.
- Portability: one fix needed for Vivado (`sigil_alu` `input var` for
  the enum-typed port under `default_nettype none`).
- Next (#53): register the VRF BRAM outputs (free BRAM DOB_REG, FPGA build
  only), then pipeline the vector datapath into EX/MEM; re-run F0 after
  each step.
- #53 step 1 done (2026-10-21): `SIGIL_VRF_OREG` → WNS −4.226 ns (≈70.3 MHz).
  The FPGA build should define it. Next limit: the MEM-stage translate /
  PMP / trap-cause path (68 levels) into `exmem_result_q`.

## F1 status (2026-10-21, #52): FPGA SoC top + AXI4 DDR bridge

What exists now (Verilator-proven, not yet synthesized in Vivado):

- `rtl/fpga/sigil_fpga_top.sv` — the unit the F2 CL wrapper (#54)
  instantiates: the unchanged `sigil_soc_top` (core + L1s + boot ROM +
  CLINT + PLIC + 16550 + crypto; same memory map and
  `sw/linux/sigil.dts`, RAM 128 MiB at `0x8000_0000`), its external-RAM
  memory bus bridged to an AXI4 master, plus boot/control and
  virtual-UART ports.
- `rtl/fpga/sigil_mbus_axi4.sv` — mbus → AXI4 master bridge.
  `AXI_DATA_W` 64/128/256/512 (`AXI_ID_W`, `AXI_ADDR_W`, `AXI_ID`
  parameters; one fixed ID, so everything is in order). Single-beat
  accesses (uncached, 8 bytes) become narrow `AxSIZE=3`, `AxLEN=0`
  transfers with `WSTRB` on the addressed lane; L1 line refills and
  write-backs (64-byte, line-aligned, 8 × 64-bit beats) become INCR
  bursts of `64/(AXI_DATA_W/8)` wide beats — **one 512-bit beat at the
  Shell DDR4 width**, so no separate width converter is needed. Write
  beats are packed into wide W beats; wide R beats are unpacked into
  64-bit mbus beats (RREADY drops only while unpacking). All AXI
  outputs are registered; AW and W are issued independently; B and R
  are always accepted when a response is expected. xRESP errors and
  unexpected IDs set a sticky `mem_err_o` (the mbus has no error
  response). `ARPROT[2]` = instruction fetch, `AxCACHE=0011`.
- `rtl/fpga/sigil_fifo.sv` — small FWFT FIFO for the virtual UART.
- `sigil_uart16550` / `sigil_soc_top` gained `rx_ready_o` /
  `uart_rx_ready_o` (high when a byte on the parallel RX port is
  accepted) so host RX bytes are never dropped.

Clocking choice: **one clock domain.** `clk_i` clocks the SoC, the
bridge and the AXI master; CDC is out of scope for F1. #54 either runs
the core on `clk_main_a0` (250 MHz, unlikely to close) or, more likely,
on an `AWS_CLK_GEN` clock with an AXI clock converter between the
bridge and the Shell DDR4 port, and does its own OCL-side CDC.

Interface for #54 (`sigil_fpga_top` ports, all on `clk_i`):

| Port | Dir | Meaning |
|---|---|---|
| `clk_i`, `rst_ni` | in | core clock; Shell reset for that domain (active low, synchronized inside) |
| `soc_reset_req_i` | in | 1 = hold the SoC in reset. Map to an OCL control bit that **resets to 1**; the host loads DDR, then writes 0. Asserting it while running quiesces the bridge (no new requests), waits for the transaction in flight, then resets the SoC — the AXI side never sees a torn burst |
| `soc_in_reset_o` | out | SoC is held in reset |
| `boot_pc_i[63:0]` | in | reset PC (`0x1000` = boot ROM → OpenSBI at `0x8000_0000`, DTB `0x8300_0000`) |
| `cache_en_i` | in | L1 strap, sampled during reset (1 for normal runs) |
| `cycle_count_o[63:0]` | out | free-running `clk_i` count since `rst_ni` release — read twice over OCL against host wall time to measure the runtime clock |
| `mem_err_o` | out | sticky AXI error |
| `trap_o`, `trap_cause_o`, `trap_pc_o` | out | core trap pulse (debug) |
| `uart_tx_data_o[7:0]`, `uart_tx_valid_o`, `uart_tx_pop_i`, `uart_tx_count_o`, `uart_tx_overflow_o` | | SoC → host byte FIFO (FWFT, `UART_TX_DEPTH`=1024); overflow is sticky until the next SoC reset; never flushed |
| `uart_rx_data_i[7:0]`, `uart_rx_push_i`, `uart_rx_full_o`, `uart_rx_count_o` | | host → SoC byte FIFO (`UART_RX_DEPTH`=64), fed into the 16550 whenever it has room; flushed when a running SoC is reset |
| `m_axi_*` | | AXI4 master (AW/W/B/AR/R incl. `id`, `len`, `size`, `burst`, `lock`, `cache`, `prot`, `qos`) → Shell DDR4 |

Parameters: `AXI_DATA_W` (set 512 for the Shell DDR4), `AXI_ID_W`,
`AXI_ADDR_W` (64), `AXI_ID`, `DDR_BASE` (DDR offset of SoC RAM, default
0), `RAM_SIZE` (128 MiB, must match the DTS), FIFO depths, and the L1
geometry passed through to `sigil_soc_top`.

Verilator proof ([evidence](evidence/fpga-top-52-2026-10-21.log)):
`tb/cpp/axi4_slave_model.h` stands in for the Shell DDR4 (seeded
latency, R gaps, AW/W/AR backpressure; checks VALID/payload stability,
WLAST, burst shape, 4 KiB, WSTRB lanes). `make -C sim axibridge` (in
core-test) runs the bridge alone against a reference memory at 64,
128 and 512 bits; `make -C sim fpgatop-quick` (in core-test) and
`fpgatop` run firmware through `sigil_fpga_top` at 64- and 512-bit AXI
with DDR-like latency (8–40 cycles): a D$-thrashing memory test with
partial stores + a 170-byte virtual-UART RX line, mid-traffic SoC reset
and rerun, `SOC HASH PASS`, both crypto images (`SOC CRYPTO PASS`);
`fpgatop-rvtests` runs the upstream riscv-tests uncached through the
AXI path; `fpgatop-hello` boots OpenSBI + `s_hello`.

Not done in F1: Vivado elaboration/synthesis of the FPGA top (F0/#51),
any CDC, BRAM-only bring-up variant (unneeded: the AXI path works at
every width), AXI-Lite/OCL register map (#54).

## F3 status (2026-10-21, #54): AWS CL wrapper, virtual UART, host runtime

Pinned toolchain: **aws-fpga HDK v2.3.5** (tag `v2.3.5`, commit
`c34f88e97eaf8a9b6ea7a3516ab65ee64690ab82`), **Small Shell
`0x10212415`**, part `xcvu47p-fsvh2892-2-e`, Vivado 2025.2 on the F2
Developer AMI 1.19.2. Everything is built unencrypted (`--no-encrypt`)
so the AFI can be published and rebuilt from this repository.

### CL architecture (`fpga/cl_sigil/`, HDK CL layout)

```
Shell SDA ──────────────────────────────> AWS_CLK_GEN (all 4 MMCM groups)
                                             └─ clk_extra_b1 = core clock
Shell OCL (AXI-Lite, clk_main_a0) ─> OCL_CDC (AXI-Lite clock converter)
   ─> SIGIL = sigil_fpga_ocl (core clock)
        sigil_ocl_regs (OCL register map below)
        sigil_fpga_top (SoC + mbus→AXI4 bridge @512 bit + UART FIFOs)
            m_axi ─> DDR_CDC (AXI4 clock converter, 512 b) ─> SmartConnect "ATG" ─┐
Shell PCIS (host loads DDR) ─> PCIS_SLC (register slice) ─> SmartConnect "XDMA" ─┤
            SmartConnect 2x2 (HDK cl_axi_sc_2x2, clk_main_a0):                  │
              DDRA 0x0..64 GiB ─> SH_DDR (sh_ddr, Shell DDR4 controller)  <─────┘
              DDRB 64 GiB..    ─> DDRB_DECERR (sigil_axi_decerr)
```

- `design/cl_sigil.sv` — CL top: AWS_CLK_GEN (named `AWS_CLK_GEN`
  in the CL top as the HDK requires, SDA wired straight to it), the
  two Xilinx clock converters (HDK IP `cl_axi_clock_converter`,
  `cl_axi_clock_converter_light`), PCIS register slice
  (`axi_register_slice`), SmartConnect (`cl_axi_sc_2x2` block design),
  `sh_ddr` with the stat bus piped like the HDK examples, FLR
  handshake, PCIe IDs (`cl_id_defines.vh`: `0xF054/0x1D0F`,
  subsystem `0x5160/0x1D0F`), CL_TEMPLATE tie-offs for PCIM, IRQs,
  virtual JTAG, HBM APB and the PCIe pass-through pins. Virtual LEDs:
  bit 0 SoC held in reset, bit 1 AXI error, bit 2 DDR calibrated.
- `rtl/fpga/sigil_fpga_ocl.sv` + `rtl/fpga/sigil_ocl_regs.sv` — the
  core-clock half (no Xilinx primitives; Verilator-linted).
  `rtl/fpga/sigil_axi_decerr.sv` — DECERR responder.
- Resets: `sh_ddr` gets `rst_main_n` only (HDK rule); the main-clock
  fabric uses AWS_CLK_GEN `cl_rst_main_n`; the core domain and both
  clock-converter sides use `cl_rst_b1_n AND cl_rst_main_n` (XPM
  synchronizers into each clock), so both converter sides reset
  together. `cl_rst_b1_n` stays asserted after AFI load until the host
  calls `aws_clkgen_deassert_resets()` / `aws_clkgen_set_recipe()`.
  The SoC is additionally held by OCL `CTRL.soc_reset_req` (resets
  to 1).
- Clock-domain crossings: only the two AXI clock converters and XPM
  CDC cells (`xpm_cdc_async_rst`, `xpm_cdc_single`,
  `xpm_cdc_array_single`).
- Placement: `small_shell_cl_pnr_user.xdc` keeps `SIGIL`, `DDR_CDC`
  and `SH_DDR` in SLR2 (clock regions X0Y8:X7Y11, wholly CL, where
  the HDK `cl_mem_perf` example also places `SH_DDR`).
- DDR map: SoC RAM `0x8000_0000 + x` (128 MiB, `sw/linux/sigil.dts`)
  = DDR / PCIS (AppPF BAR4) offset `x` (bridge `DDR_BASE = 0`,
  `MEM_MASK = 0x07FF_FFFF`). OpenSBI `fw_jump.bin` → PCIS `0x0`,
  Linux `Image` → `0x20_0000`, DTB → `0x300_0000`.

### Core clock recipe

The core runs on AWS_CLK_GEN **group B, `clk_extra_b1`**. Recipe is a
build parameter (`fpga/scripts/build_cl_sigil.sh --recipe-b`), also
settable at run time (`sigil_host --recipe-b N` →
`aws_clkgen_set_recipe`):

| Recipe | clk_extra_b1 | Use |
|---|---:|---|
| **B1** (default) | **62.5 MHz** | **interim label for the first AFI** — F0 closed ~68 MHz OOC; the CL build closes 16 ns with +0.147 ns |
| B4 | 75 MHz | after partial #53 progress |
| B5 | 100 MHz | the epic target once #53 closes 10 ns |

Groups A/C/HBM are instantiated (the SDK's clkgen calls program and
poll every MMCM) but unused, left at the HDK defaults A1/C0/H2. The
OCL `CLK_KHZ` register reports the build recipe's nominal frequency;
the host compares it with the measured one.

### OCL register map (AppPF BAR0, 32-bit accesses)

All registers live in the core-clock domain behind the AXI-Lite clock
converter. Unmapped reads return `0xBAAD_DEC0`; registers alias every
4 KiB.

| Offset | Name | Access | Reset | Meaning |
|---|---|---|---|---|
| 0x000 | ID | RO | `0x5349_474C` | "SIGL" |
| 0x004 | VERSION | RO | `0x0003_0001` | F3, revision 1 |
| 0x008 | CTRL | RW | `0x3` | bit 0 `soc_reset_req` (1 = hold SoC in reset; a running SoC is quiesced first, see F1), bit 1 `cache_en` (L1 strap, sampled in reset) |
| 0x00C | STATUS | RO | | bit 0 `soc_in_reset`, 1 `mem_err` (sticky AXI error), 2 `tx_overflow` (sticky until SoC reset), 3 `rx_full`, 4 trap seen since release, 5 TX data available, 6 DDR calibrated |
| 0x010 / 0x014 | BOOT_PC_LO / HI | RW | `0x1000` | reset PC (`0x1000` = boot ROM, which jumps to `0x8000_0000` with the DTB at `0x8300_0000`) |
| 0x018 | CYCLE_LO | RO, side effect | | core-clock cycles since CL reset, low half; **reading it snapshots the high half** |
| 0x01C | CYCLE_HI | RO | | high half captured by the last CYCLE_LO read (read LO then HI = atomic 64-bit value) |
| 0x020 | TRAP_COUNT | RO | 0 | core traps since release (cleared while held) |
| 0x024 | CLK_KHZ | RO | build | nominal core clock of the build recipe (62500 for B1) |
| 0x028 / 0x02C | TRAP_CAUSE_LO / HI | RO | | cause of the last trap (`trap_cause_o`) |
| 0x030 / 0x034 | TRAP_PC_LO / HI | RO | | PC of the last trap |
| 0x03C | SCRATCH | RW | 0 | host scratch |
| 0x040 | UART_TX_DATA | RO, pops | | bit 31 valid, bits 7:0 byte; a read with bit 31 set **pops** the TX FIFO (1024 B, SoC → host) |
| 0x044 | UART_TX_STATUS | RO | | bit 31 overflow, bits 15:0 bytes waiting |
| 0x048 | UART_RX_DATA | WO, pushes | | bits 7:0 pushed into the RX FIFO (64 B, host → SoC); dropped when full |
| 0x04C | UART_RX_STATUS | RO | | bit 31 full, bits 15:0 bytes queued |

### Building the DCP

```
# on the F2 Developer AMI (Vivado 2025.2), aws-fpga v2.3.5 at
# $AWS_FPGA_REPO_DIR (default ~/src/project_data/aws-fpga)
fpga/scripts/build_cl_sigil.sh --recipe-b B1 [--tag NAME]
```

runs `aws_build_dcp_from_cl.py -c cl_sigil --mode small_shell
--aws_clk_gen --no-encrypt --clock_recipe_a A1 --clock_recipe_b B1
--clock_recipe_c C0 --clock_recipe_hbm H2` (HDK build scripts linked
into `fpga/cl_sigil/build/scripts/`; `synth_cl_sigil.tcl` reads the SoC
RTL straight from `rtl/`). Output:
`fpga/cl_sigil/build/checkpoints/<tag>.Developer_CL.tar` (routed DCP +
manifest: the `create-fpga-image` input for #55) and reports in
`fpga/cl_sigil/build/reports/`.

Result (2026-10-21, recipe B1, r7iz.8xlarge F2 Developer AMI 1.19.2,
Vivado 2025.2; reports in
[`evidence/fpga-cl-54-2026-10-21/`](evidence/fpga-cl-54-2026-10-21/)):
the full `BuildAll` flow (synthesis, link into the Small Shell
`cl_bb_routed` checkpoint, place, phys_opt, route) completes in
**1 h 07–1 h 09 min**; **"SUCCESS: Design has no negative slack path"**,
so the HDK writes `post_route.dcp` (not `.VIOLATED`) and the
`Developer_CL.tar` (manifest: PCIe `0xF054/0x1D0F`, subsystem
`0x5160/0x1D0F`, shell `0x10212415`, hdk 2.3.5, tool v2025.2, recipes
A1/B1/C0/H2). Three builds (commits `9ed857b`, `77373eb`, `4058108`;
the RTL between them changed only in simulation-only code) gave
identical timing and utilization. **Candidate for #55:**
`2026_10_21-092135.Developer_CL.tar` from `4058108` (sha256
`9a8ecf4a5c8f594d1086942e7e33d4de63fe58f81e986d32d948a1a092cbc112`,
manifest `dcp_hash=b7e54d4f2c059be6adbe2db9bc2d36f189c4c75385e76b1177feeb14bbffbf7d`),
kept on the build instance under
`~/cl-sigil-build3/fpga/cl_sigil/build/checkpoints/`. (Pass `--tag` only
in the HDK's `YYYY_MM_DD-HHMMSS` form: it becomes the manifest `date`.)

| Clock (period) | Setup WNS | Hold WHS | Endpoints |
|---|---:|---:|---:|
| core `clk_extra_b1` = `clk_out2_clk_mmcm_b` (16 ns, B1 62.5 MHz) | **+0.147 ns** | +0.010 ns | 84,473 |
| `clk_main_a0` (4 ns, 250 MHz: SmartConnect, PCIS slice, converters' main side) | +0.197 ns | +0.011 ns | 78,905 |
| DDR4 controller `mmcm_clkout0` | +0.213 ns | +0.010 ns | 64,317 |
| core ↔ main crossings (clock converters, XPM) | +3.577 / +3.958 ns | | 72 / 52 |
| whole design (incl. `async_default` recovery in `clk_main_a0`) | +0.070 ns | +0.010 ns | 275,923 |

The core path closes 16 ns with 0.147 ns to spare (≈63.1 MHz Fmax
estimate), the same picture as F0's 68 MHz OOC result once the Shell,
pblock and DDR placement are in: worst path is again the vector
register file BRAM read (`u_vregfile ... mem_q_reg`, no output
register) → 43 logic levels (13 CARRY8) → D$ data RAM enable, 70%
routing. B1 therefore has no margin to spare; 75 MHz (B4) or
100 MHz (B5) needs #53's pipelining first.

Utilization of the CL partition (`WRAPPER/CL`, post-route):

| Block | LUTs | FFs | RAMB36 | RAMB18 | DSP |
|---|---:|---:|---:|---:|---:|
| **CL total** | **122,329 (9.4%)** | **95,551 (3.7%)** | **71** | **3** | **32** |
| SIGIL (SoC + bridge + OCL regs) | 80,529 | 34,572 | 9 | 0 | 29 |
| SH_DDR (DDR4 controller) | 23,638 | 31,544 | 26 | 1 | 3 |
| DDR_XBAR (SmartConnect 2x2) | 8,495 | 15,338 | 36 | 2 | 0 |
| AWS_CLK_GEN (4 MMCMs + regs) | 5,636 | 7,699 | 0 | 0 | 0 |
| DDR_CDC / OCL_CDC / PCIS_SLC | 889 / 42 / 672 | 2,816 / 282 / 2,647 | 0 | 0 | 0 |

(Percentages of the VU47P; 5 MMCMs incl. the DDR controller's.)

### Simulating (HDK XSIM)

```
# firmware from the dev machine: make -C sim build/soc-tests/*.bin
fpga/scripts/sim_cl_sigil.sh <fw_dir> test_sigil_regs test_sigil_hash ...
```

uses the HDK testbench (Shell BFM on OCL/PCIS/SDA/stat bus) with the
HDK fast AXI memory model behind `sh_ddr` (`AXI_MEMORY_MODEL=1`:
DDR4 calibration and DRAM timing are not simulated; the
PCIS/SoC → SmartConnect → `sh_ddr` AXI path is). Tests in
`fpga/cl_sigil/verif/tests/` do what the host does: program
AWS_CLK_GEN group B to B1 over SDA and release its resets, Shell DDR
init over the stat bus, hold the SoC, load the image over PCIS (with
read-back), set the boot PC, release, drain the virtual UART over OCL
(feeding RX bytes when given) until the pass string.
`test_sigil_host_cosim` instead runs **`fpga/host/sigil_host.c`
itself** against the simulated CL (DPI shim
`fpga/host/cosim/sigil_host_cosim.c` maps the SDK calls onto the BFM).

Results (2026-10-21, Vivado 2025.2 XSIM, aws-fpga v2.3.5 testbench,
fast AXI memory model; evidence log
[`fpga-cl-54-2026-10-21.log`](evidence/fpga-cl-54-2026-10-21.log)):

| Test | Core clock | Result |
|---|---|---|
| `test_sigil_regs` | B1 62.5 MHz | PASS — ID/VERSION/CLK_KHZ, CTRL/STATUS/BOOT_PC reset values, scratch + boot-PC read/write, unmapped `0xBAAD_DEC0`, TX empty, RX FIFO count with the SoC held, PCIS write/read at DDR `0x0` and `0x7FF_FFC0`; **measured 62.475–62.525 MHz** (cycle counter over 20.28 µs) |
| `test_sigil_hash` | B1 | PASS — boot ROM → sochash `SOC HASH PASS` after 104,734 core cycles (1.68 ms simulated), measured 62.499 MHz |
| `test_sigil_host_cosim` | B1 | PASS — **`fpga/host/sigil_host.c` unchanged** (`--recipe-b 1 --bin hash_soc_test.bin`): clock recipe, ID check, hold, PCIS load + read-back, release, UART drain → `SOC HASH PASS` after 113,156 cycles; host-reported measured clock 62.500 MHz |
| `test_sigil_smoke` | B5 100 MHz (sim speed) | PASS — boot ROM → FPGA smoke firmware: D$-thrashing memory test over the SmartConnect/DDR path, then the 170-byte line pushed through `UART_RX_DATA` → `FPGA SMOKE PASS` after 11,740,850 core cycles (5 h 02 min wall) |
| `test_sigil_crypto` | B5 | PASS — socrtl `crypto_soc_test` (SHA-256, field mul, secp256k1 ECDSA verify + tamper reject on the accelerator) → `SOC CRYPTO PASS` after 27,690,806 core cycles (12 h 13 min wall) |
| `test_sigil_ed25519` | B5 | PASS — socrtl `ed25519_soc_test` (RFC 8032 verify, tampered/non-canonical S rejected) → `SOC CRYPTO PASS` after 28,617,201 core cycles (12 h 21 min wall) |
| `test_sigil_hello` | B5 | PASS — boot ROM → **OpenSBI v1.9** `fw_jump` (279 KB over PCIS) + DTB at `0x8300_0000` → S-mode `s_hello` → `HELLO FROM S-MODE` after 11,451,667 core cycles (4 h 59 min wall; full OpenSBI banner in the log). DTB: the build of the same DTS from before the rename commit `95b02da` (same nodes, only the name strings differ; no `dtc` on the build hosts) |

XSIM speed: about 400 core cycles per second at B1 and ~800 at B5
(r7iz.8xlarge, one simulator process per test), so a full Linux boot
(~509M cycles in Verilator) would take about a week in XSIM and is
**not attempted**; Linux is left to the F2 hardware run (#55). The
same images run through the core-clock half in Verilator through the
OCL registers (`make -C sim fpgaocl`, below) in minutes.

Two XSIM-specific fixes were needed: `sigil_mbus_axi4`'s simulation-only
`a_wbeat_addr` assertion made Vivado 2025.2 `xelab` segfault (the
width cast moved out of the property; Verilator unaffected), and the
test bench's image loader works around an XSIM quirk with
`queue.push_back(byte'(c))`.

Verilator (`make -C sim fpgaocl`; `fpgaocl-quick` is in `core-test`):
`tb/cpp/fpga_ocl_tb.cpp` drives `sigil_fpga_ocl` (OCL register block +
FPGA top, 512-bit AXI to the DDR model with 8–40-cycle latency and
backpressure) only through AXI-Lite register accesses, like the host:
register reset values, scratch/boot-PC, cycle-counter delta = harness
cycles, then `SOC HASH PASS` (105,056 cycles), `FPGA SMOKE PASS`
(11,791,881; the 170-byte RX line pushed through `UART_RX_DATA`) and
`SOC CRYPTO PASS` (27,690,936), re-hold with the AXI side idle — PASS.


### Host runtime (`fpga/host/`)

`make -C fpga/host SDK_DIR=<aws-fpga>/sdk` (after building the SDK
once: `sdk/userspace/mkall_fpga_mgmt_tools.sh`, or `source
sdk_setup.sh`); links `libfpga_mgmt.a` statically. Run as root on the
F2 instance:

```
sudo ./sigil_host --afi agfi-XXXX --bin crypto_soc_test.bin            # baremetal
sudo ./sigil_host --linux --fw fw_jump.bin --image Image --dtb sigil.dtb \
                  --timeout 300 --stdin --log boot.log                 # OpenSBI + Linux
sudo ./sigil_host --no-cache --tohost 0x80001000 --bin rv64ui-p-add.bin  # riscv-tests (HTIF)
```

Flow: optional AFI load (`fpga_mgmt_load_local_image_sync`) →
`aws_clkgen_deassert_resets` (or `aws_clkgen_set_recipe` with
`--recipe-b`) → check `ID` → hold the SoC (`CTRL`) and drain stale
UART bytes → wait for DDR → copy the images through PCIS
(`fpga_pci_write_burst` on AppPF BAR4, then head/tail or full
`--verify` read-back) → `BOOT_PC` → release → loop: pop
`UART_TX_STATUS.count` bytes to stdout (and `--log`), push stdin to
`UART_RX_DATA` with `--stdin`, poll `tohost` with `--tohost`, check
`STATUS` for AXI errors/overflow → stop on an exit marker (defaults
`SIGIL_LINUX_BOOT_OK`, `SOC CRYPTO PASS`, `SOC HASH PASS`, `FPGA SMOKE
PASS`, `HELLO FROM S-MODE`), a fail marker (`FAIL`, `Kernel panic`)
or `--timeout` → print **measured core clock = Δ`CYCLE` / Δwall time**
next to the build recipe, trap count / last trap, and hold the SoC
again (unless `--keep-running`). Exit status 0 pass, 1 fail, 2
timeout, 3 setup error.

### Left for #55

Upload the DCP tarball to S3 and `create-fpga-image` (owner sign-off on
region/budget), make the AFI/AGFI public, load it on an `f2.6xlarge`
and run the F5 sequence with `sigil_host`; nothing here has run on F2
hardware yet. Raise `--recipe-b` to B5 once #53 closes 100 MHz.

## Flash Sigil on your own F2 (draft — TODO: public AGFI id)

> Draft for the public AFI from #55; the AGFI id and the
> pre-built payload downloads do not exist yet.

1. Launch an **`f2.6xlarge`** in a region with F2 (e.g. us-east-1)
   from the AWS **FPGA Developer AMI** (or Amazon Linux 2023 / Ubuntu
   with the aws-fpga SDK). Budget about $2/h On-Demand; stop it when
   done.
2. Install the SDK: `git clone -b v2.3.5
   https://github.com/aws/aws-fpga && cd aws-fpga && source
   sdk_setup.sh`.
3. Load the public Sigil AFI: `sudo fpga-load-local-image -S 0 -I
   agfi-TODO` (check with `sudo fpga-describe-local-image -S 0 -H`;
   the PCIe IDs are `0xF054/0x1D0F`).
4. Build the runtime: `git clone https://github.com/bubblebabyboi/sigil
   && make -C sigil/fpga/host SDK_DIR=$PWD/aws-fpga/sdk`.
5. Run: `sudo sigil/fpga/host/sigil_host --bin crypto_soc_test.bin`
   (baremetal) or `sudo sigil/fpga/host/sigil_host --linux --fw
   fw_jump.bin --image Image --dtb sigil.dtb --stdin --timeout 600`
   (payloads: `make -C sim` / `scripts/build_opensbi.sh` / `make soc`,
   see `docs/QEMU.md`). The last lines report the measured core clock.
6. To rebuild the AFI yourself: `fpga/scripts/build_cl_sigil.sh` on
   the FPGA Developer AMI, then the AWS `create-fpga-image` flow.

## Platform facts (verified 2026-10-14)

- F2 FPGA: AMD/Xilinx Virtex UltraScale+ **VU47P**
  (2.85M system logic cells, 9,024 DSP slices), per FPGA
  16 GiB HBM + 64 GiB DDR4. Confirmed two ways: the AWS
  F2 launch blog, and `aws ec2 describe-instance-types`
  from this account (`f2.6xlarge` = 1× VU47P, 24 vCPU,
  256 GiB host RAM; `f2.12xlarge` = 2; `f2.48xlarge` = 8).
  This account's Running On-Demand F-instance quota is
  128 vCPUs (checked 2026-10-14), so an `f2.6xlarge`
  (24 vCPUs) fits without a quota request.
- Flow (aws/aws-fpga HDK): write Custom Logic (CL) to the
  Shell spec → Vivado build on the FPGA Developer AMI →
  encrypted DCP → S3 + `create-fpga-image` → AFI → load
  on an F2 instance with the FPGA management tools.
  Builds do **not** need an F2 instance; run them on a
  cheaper compute instance with the Developer AMI and
  rent F2 only to load/test. Vivado is not available on
  this Mac (Linux AMI only).
- There is no board UART/LED for the CPU console. Host
  communication is PCIe: OCL AXI-Lite BAR registers, DMA,
  and virtual DIP switches / LEDs / JTAG. The CPU UART
  therefore becomes a **virtual UART**: TX/RX FIFOs in
  the CL, exposed over the OCL BAR and polled/drained by
  the host runtime program.

## Readiness gaps in the current RTL (must close first)

1. **No synthesizable SoC.** `rtl/soc/sigil_soc_top.sv`
   instantiates only the crypto macro; the machine that
   boots Linux (boot ROM 0x1000, CLINT 0x0200_0000,
   PLIC 0x0C00_0000, 16550 at 0x1000_0000, 128 MiB RAM at
   0x8000_0000) exists only as the C++ model in
   `tb/cpp/soc_tb.cpp` (issue #4, deferred). FPGA work
   un-defers the synthesizable subset of #4, keeping the
   exact memory map / DTS (`sw/linux/sigil.dts`) so
   the proven OpenSBI/Linux payloads are reused.
2. **Combinational Harvard memory ports.** The core
   expects same-cycle `imem_rdata_i` (32b) and
   `dmem_rdata_i` (64b) (`rtl/core/sigil_core.sv`).
   FPGA BRAM reads are synchronous (1 cycle) and DDR/HBM
   via the Shell AXI is tens of cycles. Needs an
   I/D cache or BRAM adapter plus a real stall/ready
   handshake; a first milestone can use LUTRAM/registered
   BRAM with an IF-stage fetch-latency fix.
3. **Single-cycle FP and whole-vector datapaths will not
   close 10 ns as-is.** The scalar `sigil_fpu` is now
   multi-cycle behind a generic EX stall handshake (Nangate45
   synth 5.34 ns register-to-register, unplaced, see
   `docs/evidence/fpu-multicycle-upstream-2026-10-15.log`),
   but the vector FP path still calls the combinational
   `fp_eval` per element, and `sigil_vec`
   evaluates up to `512/SEW` elements combinationally
   fed by three 4096-bit register-group read ports from a
   flop-array VRF (32×512). Closing ≥100 MHz needs:
   iterative/pipelined FP div/sqrt/FMA with EX stall,
   element-serial vector execution over a narrow (e.g.
   64-bit) datapath, and a banked BRAM/LUTRAM VRF. ISA
   semantics must not change: riscv-tests, ACT and the
   unit TBs re-run after every such refactor.
4. **Synthesis portability is unproven for the core.**
   The core has only been Verilated. The FPU uses packed
   structs only and synthesizes (sv2v + Yosys,
   `scripts/synth_fpu.sh`). Vivado handles much more
   SystemVerilog, but elaboration of the full core in
   Vivado is itself milestone F0, not an assumption.

## Stages

- **F0 — Vivado out-of-context baseline (no F2 spend).**
  Developer AMI on a compute instance; synthesize
  `sigil_core` and `sigil_crypto_top` for the VU47P
  part/speed grade named by the pinned HDK shell at a
  100 MHz constraint. File LUT/FF/DSP/BRAM/WNS and the
  top critical paths under `docs/evidence/`. Gate:
  elaborates; we have real numbers, not guesses.
- **F1 — Synthesizable FPGA SoC.** (Done 2026-10-21 as
  `rtl/fpga/sigil_fpga_top.sv` around `sigil_soc_top` with RAM over
  AXI4 instead of BRAM; see "F1 status" above.) Original plan:
  `rtl/soc/sigil_fpga_soc.sv`: core + boot ROM +
  CLINT + PLIC subset + 16550-compatible UART RTL +
  BRAM RAM (size what fits; DDR in F3) at the `soc_tb`
  addresses, timer/external IRQs wired. Extend the
  Verilator harness so the *RTL* platform (not the C++
  model) boots `s_hello` and baremetal directed tests.
  Gate: Verilator Linux-smoke path still works on the
  C++ platform, RTL SoC passes baremetal in Verilator.
- **F2 — Timing closure to ≥100 MHz.** Do the FPU/vector/
  memory refactors from gap 2–3 above, driven by F0's
  critical paths. An interim "lite" configuration (e.g.
  scalar-only) is allowed to de-risk Shell/DDR bring-up,
  but any boot claim must name its exact configuration;
  the final Linux claim is for the full RV64GC + Zve*
  configuration already verified, or is explicitly
  labelled otherwise. Gate: Vivado post-route WNS ≥ 0
  at 100 MHz (report filed), unit/ACT gates re-run.
- **F3 — AWS CL wrapper + host runtime.** (Done 2026-10-21, see
  "F3 status" above: aws-fpga v2.3.5, Small Shell 0x10212415.) Pin the
  aws-fpga HDK commit and shell version in this doc when
  chosen. CL wraps the SoC: Shell clocks → 100 MHz core
  clock (HDK clock recipe), OCL AXI-Lite control/status
  + virtual-UART FIFOs + reset/load doorbells, Shell
  DDR4 AXI for RAM ≥128 MiB (HBM optional later). Host
  C runtime: load AFI, write OpenSBI/Image/DTB, release
  reset, drain UART, assert exit markers. Include a
  free-running cycle counter readable over OCL so the
  *runtime* clock rate is measured (counter delta vs
  host wall time), not inferred from the build report.
- **F4 — AFI build and F2 run.** Build DCP on the
  Developer AMI compute instance, create the AFI via
  S3, run on `f2.6xlarge` (single FPGA, cheapest).
  Evidence log: AFI id, shell/HDK versions, Vivado
  timing summary, host runtime UART capture.
- **F5 — Real code.** In order: (1) baremetal hello +
  directed tests + a CoreMark/Dhrystone-class benchmark
  with cycle counts; (2) crypto KATs through the
  accelerator once it is on the SoC fabric; (3)
  OpenSBI + Linux to `SIGIL_LINUX_BOOT_OK` (Verilator
  needed ~509M cycles, so expect single-digit seconds
  at 100 MHz before DDR stalls); (4) a static user
  binary printing its marker. Each with a dated log
  under `docs/evidence/`.

## Cost and safety guardrails

- Check F2 On-Demand quota and region availability
  before scheduling F4; F2 is not in every region.
- Never leave an F2 instance running idle: builds on
  compute AMIs, F2 only for load/test, stop/terminate
  in the same script that starts it, and list live
  instances before reporting anything as "running".
- Budget decision needed from the owner before F4:
  region, and a cap on F2 hours. Default recommendation:
  `f2.6xlarge`, F0–F3 completed before the first F2 hour
  is spent.
