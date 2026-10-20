# AWS EC2 F2 FPGA bring-up plan

Goal: run real code on the in-house `muserisc_core` on an
AWS EC2 F2 FPGA at a core clock of **100 MHz or higher**,
with evidence captured from the host runtime (not just a
synthesis timing report). End state: baremetal tests, then
OpenSBI + Linux to `MUSERISC_LINUX_BOOT_OK`, using the same
payloads already proven in `soc_tb` / QEMU (`docs/QEMU.md`).

This plan starts only after the #31 OpenROAD rerun closes
timing/liberty on the crypto macro (done 2026-10-14:
setup WS 4.34 ns, TNS 0 at the 100 MHz constraint; that
result is for `muse_crypto_top` on nangate45 and says
nothing about core Fmax on FPGA — see below).

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

1. **No synthesizable SoC.** `rtl/soc/muserisc_soc_top.sv`
   instantiates only the crypto macro; the machine that
   boots Linux (boot ROM 0x1000, CLINT 0x0200_0000,
   PLIC 0x0C00_0000, 16550 at 0x1000_0000, 128 MiB RAM at
   0x8000_0000) exists only as the C++ model in
   `tb/cpp/soc_tb.cpp` (issue #4, deferred). FPGA work
   un-defers the synthesizable subset of #4, keeping the
   exact memory map / DTS (`sw/linux/muserisc.dts`) so
   the proven OpenSBI/Linux payloads are reused.
2. **Combinational Harvard memory ports.** The core
   expects same-cycle `imem_rdata_i` (32b) and
   `dmem_rdata_i` (64b) (`rtl/core/muserisc_core.sv`).
   FPGA BRAM reads are synchronous (1 cycle) and DDR/HBM
   via the Shell AXI is tens of cycles. Needs an
   I/D cache or BRAM adapter plus a real stall/ready
   handshake; a first milestone can use LUTRAM/registered
   BRAM with an IF-stage fetch-latency fix.
3. **Single-cycle FP and whole-vector datapaths will not
   close 10 ns as-is.** The scalar `muserisc_fpu` is now
   multi-cycle behind a generic EX stall handshake (Nangate45
   synth 5.34 ns register-to-register, unplaced, see
   `docs/evidence/fpu-multicycle-upstream-2026-10-15.log`),
   but the vector FP path still calls the combinational
   `fp_eval` per element, and `muserisc_vec`
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
  `muserisc_core` and `muse_crypto_top` for the VU47P
  part/speed grade named by the pinned HDK shell at a
  100 MHz constraint. File LUT/FF/DSP/BRAM/WNS and the
  top critical paths under `docs/evidence/`. Gate:
  elaborates; we have real numbers, not guesses.
- **F1 — Synthesizable FPGA SoC.** New
  `rtl/soc/muserisc_fpga_soc.sv`: core + boot ROM +
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
  OpenSBI + Linux to `MUSERISC_LINUX_BOOT_OK` (Verilator
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
