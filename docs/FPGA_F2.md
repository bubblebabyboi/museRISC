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
- **Work still to build for F3:** core bus → AXI4 bridge to Shell DDR4,
  OCL AXI-Lite virtual UART + control/reset/cycle counter, host loader
  for OpenSBI/Image/DTB.
- **Cost:** `f2.6xlarge` ≈ $1.98/h On-Demand in us-east-1/us-west-2
  (third-party price trackers; spot seen ≈ $0.67/h). Account F-instance
  quota (128 vCPUs) covers one. Builds (30–90 min) run off-F2.

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
- **F1 — Synthesizable FPGA SoC.** New
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
- **F3 — AWS CL wrapper + host runtime.** Pin the
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
