<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/sigil-logo-dark.svg">
    <img src="docs/assets/sigil-logo.svg" alt="Sigil — RV64GCV signature and hash SoC" width="760">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/bubblebabyboi/sigil/actions/workflows/regression.yml"><img alt="RTL regression" src="https://github.com/bubblebabyboi/sigil/actions/workflows/regression.yml/badge.svg"></a>
  <a href="https://github.com/bubblebabyboi/sigil/actions/workflows/core-regression.yml"><img alt="Core regression" src="https://github.com/bubblebabyboi/sigil/actions/workflows/core-regression.yml/badge.svg"></a>
  <img alt="riscv-tests: 123/123" src="https://img.shields.io/badge/riscv--tests-123%2F123-brightgreen">
  <img alt="ACT: 2577/2578, one waiver" src="https://img.shields.io/badge/ACT-2577%2F2578%20(1%20waiver)-yellowgreen">
  <img alt="AWS F2: Debian boots" src="https://img.shields.io/badge/AWS%20F2-Debian%20boots-brightgreen">
  <img alt="nangate45 whole-SoC GDS" src="https://img.shields.io/badge/nangate45-whole--SoC%20GDS-blue">
  <a href="LICENSE"><img alt="Licence: GPLv3" src="https://img.shields.io/badge/licence-GPLv3-57D0B8"></a>
</p>

# Sigil

Sigil is an open, from-scratch RISC-V system-on-chip built to **hash and
verify signatures in hardware**. It pairs an in-house 64-bit RISC-V
application core with a crypto/hash engine, boots Linux, runs on a real
FPGA in the cloud, and has a placed-and-routed GDS — with every claim
backed by a reproducible gate and a dated log in
[`docs/evidence/`](docs/evidence/README.md).

**What works today**

- **In-house RV64GCV core** — 5-stage in-order pipeline, RV64IMAFDC + B +
  Zicond + scalar crypto (Zbk*/Zkn*), RVV 1.0 vector (Zve64d, VLEN 512),
  M/S/U + H hypervisor, Sv39/Sv39x4, PMP, L1 I$/D$. riscv-tests 123/123,
  RISC-V ACT 2,577/2,578 (one documented waiver).
- **Crypto/hash engine on the SoC** — SHA-256, streaming SHA-512 /
  SHA3-256 / Keccak-256 / SHAKE256 with hardware padding, and 256-bit
  field arithmetic for **Ed25519 and secp256k1** signature verification.
- **Linux** — **Debian 13 with gcc 14 and glibc 2.41** on Linux 6.12
  LTS **on real AWS F2 FPGA hardware**, with the DDR4 and the HBM as two
  NUMA nodes and a persistent disk: login prompt 5 min 48 s after the SoC
  starts, 22/22 acceptance checks on the F2 (23/23 in QEMU shaped like
  the F2). Linux 6.12 also boots on the RTL SoC in simulation.
- **FPGA** — the whole SoC runs on an AWS EC2 F2 (AMD VU47P) at a measured
  62.5 MHz with **all 64 GiB of DDR4 and 16 GiB of HBM**, from a
  **public AFI anyone can load**: `agfi-0c8aa56fde1a48495`.
- **Silicon flow** — the whole SoC is placed and routed on nangate45 to a
  GDS, timing met at 100 MHz (fmax 107.9 MHz), route DRC 0. A sky130
  (Caravel-sized) implementation is in progress.

## Architecture

```text
 +----------------------------------------------------------------------+
 | sigil_soc_top                                                         |
 |                                                                       |
 |  +------------------------------------------+   +------------------+  |
 |  | sigil_cpu                                |   | sigil_crypto_top |  |
 |  |  5-stage core  IF ID EX MEM WB           |   |  SHA-256         |  |
 |  |  RV64IMAFDC B Zicond Zbk*/Zkn* H         |   |  hash stream:    |  |
 |  |  RVV 1.0 (Zve64d, VLEN 512) on a         |   |   SHA-512, SHA3, |  |
 |  |   multi-cycle shared FPU                 |   |   Keccak, SHAKE  |  |
 |  |  Sv39/Sv39x4 MMU, PMP, CSRs, traps       |   |  EC field unit   |  |
 |  |  L1 I$ + D$ (write-back)                 |   |  (Ed25519 /      |  |
 |  +---------------------+--------------------+   |   secp256k1)     |  |
 |                        | memory bus             +--------+---------+  |
 |  +---------------------v-----------------------+  AXI-Lite|            |
 |  | fabric: boot ROM 0x1000 | CLINT 0x0200_0000 |<--------+            |
 |  | PLIC 0x0C00_0000 | UART 16550 0x1000_0000   |                      |
 |  | crypto 0x2000_0000 | RAM 0x8000_0000 (ext.) |                      |
 |  +---------------------------------------------+                      |
 +----------------------------------------------------------------------+
        |                         |                          |
   Verilator sims          AWS F2 FPGA (VU47P)        OpenROAD / ORFS
   (soc_rtl_tb, core_tb)   CL wrapper, DDR4 + HBM,     nangate45 GDS,
                           virtual UART, host tool     sky130 (in progress)
```

Key files: [`rtl/core/sigil_core.sv`](rtl/core/sigil_core.sv),
[`rtl/soc/sigil_soc_top.sv`](rtl/soc/sigil_soc_top.sv),
[`rtl/crypto/sigil_crypto_top.sv`](rtl/crypto/sigil_crypto_top.sv),
[`rtl/fpga/sigil_fpga_top.sv`](rtl/fpga/sigil_fpga_top.sv),
[`fpga/cl_sigil/`](fpga/cl_sigil/). Design records:
[`docs/CORE.md`](docs/CORE.md) · [`docs/SPEC.md`](docs/SPEC.md) ·
[`docs/SOC_AREA.md`](docs/SOC_AREA.md) · [`docs/FPGA_F2.md`](docs/FPGA_F2.md) ·
[`docs/PERFORMANCE.md`](docs/PERFORMANCE.md).

## Run it yourself

### 1. In simulation (any Linux or macOS machine)

You need Verilator (5.044+ recommended), a bare-metal RISC-V GCC
(`riscv64-elf-gcc` or `riscv64-unknown-elf-gcc`) and Python 3.
`./scripts/install_deps.sh` installs them (Homebrew on macOS, apt on
Ubuntu/Debian; on Linux it builds the pinned Verilator into `deps/`).

```sh
git clone https://github.com/bubblebabyboi/sigil.git
cd sigil
./scripts/install_deps.sh          # once; then in every shell on Linux: source deps/env.sh

make lint                          # Verilator lint of all RTL
make test                          # crypto/hash engine known-answer tests
make -C sim examples               # build the example C programs and run each on the RTL SoC
make core-test                     # full core + SoC regression (~30 min)
```

Run the signature-verify firmware on the full RTL SoC:

```sh
make -C sim socrtl                 # secp256k1 ECDSA + Ed25519 verify -> "SOC CRYPTO PASS"
```

Upstream compliance and the Linux boot are longer runs:
[`sim/run_riscv_tests.sh`](sim/run_riscv_tests.sh),
[`sw/act4-core/README.md`](sw/act4-core/README.md) (ACT), and
[`sw/linux/README.md`](sw/linux/README.md) (Linux 6.12 to
`SIGIL_LINUX_BOOT_OK` in 261M cycles on `soc_rtl_tb`).

### 2. On a real FPGA (AWS EC2 F2)

The whole SoC is published as a public Amazon FPGA Image. On an
`f2.6xlarge` (us-east-1, ~$2/h — stop it when done):

```sh
# AWS FPGA runtime SDK
git clone -b v2.3.5 https://github.com/aws/aws-fpga ~/aws-fpga
cd ~/aws-fpga && source sdk_setup.sh

# load Sigil onto the FPGA
sudo fpga-load-local-image -S 0 -I agfi-0c8aa56fde1a48495 -H

# build the host tool and run a program
git clone https://github.com/bubblebabyboi/sigil ~/sigil && cd ~/sigil
make -C fpga/host SDK_DIR=$HOME/aws-fpga/sdk
sudo fpga/host/sigil_host --bin path/to/program.bin
```

`sigil_host` loads your image into the FPGA's DDR4, releases the SoC,
streams its UART to your terminal (`--stdin` sends your keyboard to it),
stops on a pass/fail marker, and reports the **measured core clock**.
`--load` / `--save` move data into and out of any of the 64 GiB of DDR4
and 16 GiB of HBM. Full walkthrough:
[`docs/FPGA_F2.md` → Flash Sigil on your own F2](docs/FPGA_F2.md#flash-sigil-on-your-own-f2).
Earlier AFIs are history: `agfi-0a1fd54ef68bdc754`, the first build with
all of the memory, is superseded and must not be used for Linux (its core
has the MMU walker race,
[#74](https://github.com/bubblebabyboi/sigil/issues/74)); the first
public AFI `agfi-035116450e0a0d093` (128 MiB of DDR4, needs
`--ignore-mem-err`) works with the current `sigil_host`, but its core
also has the walker race (#74), so use it for bare-metal programs only.

## Boot Debian on your own F2

A real Debian 13 with gcc, on Sigil, on an FPGA in your own AWS account.

> **Status (2026-10-22): works on the F2.** Debian boots to the login
> prompt 5 min 48 s after the SoC is released, passes 22/22 acceptance
> checks, and a disk saved after `sudo poweroff` boots again with its files
> ([evidence](docs/evidence/linux-debian-73-2026-10-22/f2-boot-fixed/)).
> Those F2 runs used the `sigil_host` command that `sigil-linux` wraps;
> `sigil-linux` itself passed its tests against a simulated `sigil_host`.

Launch an `f2.6xlarge` in us-east-1 from the AWS **FPGA Developer AMI**,
log in as `ubuntu`, and:

```sh
curl -fsSL https://raw.githubusercontent.com/bubblebabyboi/sigil/main/fpga/scripts/f2_playground_setup.sh | bash
tmux                  # recommended: keeps the session alive if SSH drops
~/bin/sigil-linux     # downloads the release, loads the AFI, boots to the login prompt
# log in as sigil / sigil; gcc, numactl --membind=1 ./prog (HBM), ...
# sudo poweroff saves your disk (~/sigil-disk.ext4) for the next sigil-linux
```

[`sigil-linux`](fpga/scripts/sigil-linux) boots OpenSBI + Linux 6.12
with the Debian disk from the release `sigil-linux-f2-2026-10-22`, your
terminal as the console. The login prompt comes 5 min 48 s after the
SoC starts (measured on the F2; the host first zeroes DDR4 and loads the
8 GiB disk, about 21 s): the core runs at 62.5 MHz and it is slow. Using the system — compiling on the board, DDR4 vs HBM, vector
code, getting files in and out — is in [`docs/LINUX.md`](docs/LINUX.md).

## Write code for Sigil

Sigil comes with a small bare-metal SDK ([`sw/sdk/`](sw/sdk/)): startup
code, one header (`sigil.h`) with the memory map, UART `printf`, timers
and interrupts, cycle counters, and drivers for the hash engine, field
arithmetic and Ed25519 verify. Programs run unchanged in simulation and on
the F2 (except `hbm_touch`, which needs the F2's memory map; it has
passed on the simulated F2 map but not yet run on the F2).

```sh
cp -r sw/sdk/template myprog && cd myprog   # main.c + Makefile
make            # -> build/myprog.elf, .bin (flat image), .dis (disassembly)
make run        # run on the RTL SoC simulator
```

```c
#include "sigil.h"

int main(void) {
  uint64_t t0 = sigil_rdcycle();
  uint8_t digest[64];
  sigil_hash(SIGIL_HASH_SHA512, "hello, sigil", 12, digest, 64);
  sigil_printf("sha512 took %lu cycles\n", sigil_rdcycle() - t0);
  return 0;                     // prints "SIGIL TEST PASS <name>"
}
```

Worked examples ([`sw/examples/`](sw/examples/), each self-checking and
part of the regression):

| Example | Shows |
|---|---|
| `hello` | UART output, `misa`, cycle/instret counters |
| `timer_irq` | CLINT timer + software interrupts, `wfi` |
| `sha256_accel` | SHA-256 on the engine vs plain C vs Zknh instructions |
| `hash_stream` | SHA-512 / SHA3-256 / SHAKE256 of any length |
| `ed25519_verify` | signature verification with the field unit |
| `vector_dot` | RVV 1.0 vector code vs scalar |
| `fp_math` | IEEE-754 double precision, rounding modes, FMA |
| `hbm_touch` | F2 only: the 16 GiB of HBM and DDR4 beyond 128 MiB from bare-metal C ([`docs/PROGRAMMING.md` §8.1](docs/PROGRAMMING.md#81-the-f2-memory-map-64-gib-ddr4-and-16-gib-hbm)); passes on `fpga_top_tb_f2`, not yet run on the F2 |

The programmer's guide — toolchain, memory map, SDK API, running in
simulation and on F2, interrupts, vector, performance counters and
gotchas — is [`docs/PROGRAMMING.md`](docs/PROGRAMMING.md).

## Build configurations

One RTL tree, selected by Verilog defines (each read once, in a
package) and `sigil_soc_top` / `sigil_cpu` parameters:

| Configuration | Selected by | Used for |
|---|---|---|
| Default: RV64GCV, behavioural arrays, 8 KiB 2-way I$ + 16 KiB 4-way D$ | (none) | simulation, `make core-test` |
| FPGA (AWS F2) | default + `SIGIL_VRF_OREG` (registered VRF reads) | `fpga/cl_sigil/`, `make -C sim srammacro` (`vrforeg`) |
| nangate45 | `SIGIL_SRAM_FAKERAM45` (fakeram45 macros) | `flow/designs/nangate45/sigil_soc/` |
| sky130 | `SIGIL_SRAM_SKY130` (OpenRAM macros, registered SRAM reads) + `SIGIL_SOC_PARAMS_SKY130` (4 KiB direct-mapped I$ / D$) | `flow/designs/sky130hd/sigil_soc/` |
| **MPW cut-down, no vector unit** ([#13](https://github.com/bubblebabyboi/sigil/issues/13)) | `SIGIL_NO_VECTOR` (`sigil_pkg::HAS_VECTOR = 0`); with the sky130 settings for the MPW build | `SIGIL_NO_VECTOR=1` on the ORFS make line; `make -C sim core-novec` |
| Simulation-only variants | `SIGIL_SRAM_OREG`, `SIGIL_MULDIV_COMB`, `SIGIL_FPU_DS_BITS=1`, `SIGIL_COMMIT_TRACE` | `make -C sim` sub-targets |

The no-vector configuration is RV64GC + B + K + H with the FPU, MMU,
caches and crypto engine unchanged: no vector unit, no vector register
file (and so none of the 3 VRF SRAM macros), `misa.V = 0`,
`mstatus.VS` read-only zero, and every vector instruction or vector CSR
access raises illegal-instruction, as on a core without V. Without
the define every other configuration is unchanged; that is proven with
Yosys against the previous `main` ([`docs/SOC_AREA.md`](docs/SOC_AREA.md),
MPW section).

## Status and evidence

| Gate | Result | Evidence |
|---|---:|---|
| `make core-test` (unit TBs, directed suites, SRAM-macro builds, FPGA top, examples) | PASS | `tb/cpp/`, `sw/core-tests/`, `sw/examples/` |
| riscv-tests | 123/123 | [`linux-release-73-final-gates-2026-10-22.log`](docs/evidence/linux-release-73-final-gates-2026-10-22.log) |
| RISC-V ACT (scalar, priv, A/F/D/B/K/Zicond/C, Vx/Vls/Vf) | 2,577/2,578, 1 waiver | [`act_summary.txt`](docs/evidence/linux-oops-fix-73-2026-10-22/act_summary.txt) |
| On-core crypto (RTL SoC): secp256k1 + Ed25519 verify, tamper reject | PASS | [`soc-rtl-ed25519-4-2026-10-20.log`](docs/evidence/soc-rtl-ed25519-4-2026-10-20.log) |
| Streaming hash engine (70 KATs + SoC firmware) | PASS | [`hash-stream-make-test-2026-10-20.log`](docs/evidence/hash-stream-make-test-2026-10-20.log) |
| Linux 6.6 (Verilator) | PASS to userspace | [`core-stage6-linux-boot-2026-10-14.log`](docs/evidence/core-stage6-linux-boot-2026-10-14.log) |
| Linux 6.12 on the RTL SoC (`soc_rtl_tb`) | PASS, 261M cycles | [`linux_boot.log`](docs/evidence/linux-oops-fix-73-2026-10-22/linux_boot.log) |
| Debian 13 + Linux 6.12 in QEMU shaped like the F2 (gcc, NUMA/HBM, RVV, disk, power-off) | 23/23 | [`linux-debian-73-2026-10-22/`](docs/evidence/linux-debian-73-2026-10-22/qemu-check-summary.txt) |
| **AWS F2 hardware**, first AFI: crypto, OpenSBI, **Linux 6.6 to userspace**, 62.5 MHz measured | PASS | [`f2-first-boot-55-2026-10-22/`](docs/evidence/f2-first-boot-55-2026-10-22/SUMMARY.md) |
| **AWS F2 hardware**, platform AFI `agfi-0a1fd54ef68bdc754` (same CL as the current AFI except the core's walker-race fix and atomic A/D update, #74): full-range memory test of 64 GiB DDR4 + 16 GiB HBM, core sparse test, finisher, RTC, console, firmware + SDK examples | 0 errors, PASS | [`f2-platform-73-2026-10-22/`](docs/evidence/f2-platform-73-2026-10-22/SUMMARY.md) |
| **AWS F2 hardware**, current AFI `agfi-0c8aa56fde1a48495`: **Debian 13 to a login prompt in 5 min 48 s**, gcc, NUMA (DDR4 node 0, HBM node 1), RVV, sudo, python3, power-off, saved disk boots again | 22/22 + persistence, PASS | [`linux-debian-73-2026-10-22/f2-boot-fixed/`](docs/evidence/linux-debian-73-2026-10-22/f2-boot-fixed/) |
| MMU walker race ([#74](https://github.com/bubblebabyboi/sigil/issues/74)), the cause of the kernel oopses in the first F2 Debian boots: fixed in the core, in the current AFI | race tests 0/39 → 39/39; core-test, riscv-tests, ACT rerun | [`linux-oops-fix-73-2026-10-22/`](docs/evidence/linux-oops-fix-73-2026-10-22/README.md) |
| FPGA utilization (Vivado, VU47P), current AFI: full CL / SoC + OCL block | 131,259 (10.08%) / 82,201 LUTs | [`f2-platform-73-oopsfix-2026-10-22/vivado/`](docs/evidence/f2-platform-73-oopsfix-2026-10-22/vivado/) |
| **Whole-SoC GDS, nangate45**: 100 MHz met, route DRC 0, antenna 0 | GDS generated | [`soc-pnr-nangate45-11-2026-10-21/`](docs/evidence/soc-pnr-nangate45-11-2026-10-21/summary.log) |
| No-vector (MPW cut-down, [#13](https://github.com/bubblebabyboi/sigil/issues/13)) configuration: directed suites, riscv-tests, ACT non-V; default configurations proven unchanged (Yosys) | PASS; 123/123; 543/544, 1 waiver | [`mpw-novec-13-2026-10-24.log`](docs/evidence/mpw-novec-13-2026-10-24.log) |
| Whole-SoC sky130 (Caravel area) | in progress (hierarchical) | [`w7-sky130-pnr-2026-10-21.log`](docs/evidence/w7-sky130-pnr-2026-10-21.log), [#11](https://github.com/bubblebabyboi/sigil/issues/11) |

The ACT waiver (`PMPSm_cfg_A_tor_zero-00`) is a harness/platform
mismatch at physical address 0, documented in the evidence index.

### ISA coverage

- [x] **RV64I + M**, **A** (LR/SC, AMOs), **F/D**, **C** (Zca/Zcb/Zcd)
- [x] **B + Zicond + scalar crypto** — Zba/Zbb/Zbc/Zbs, Zicond, Zbkb/Zbkc/Zbkx, Zkne/Zknd/Zknh
- [x] **Privilege M/S/U**, precise traps, interrupts, PMP, **Sv39**
- [x] **H hypervisor** — HS/VS/VU, two-stage Sv39x4; Linux KVM entry/exit smoke
- [x] **V vector** — RVV 1.0 Zve32x/Zve64x/Zve32f/Zve64f/Zve64d, VLEN 512 (full V and FP16 not claimed)

## Roadmap

All work is tracked as GitHub epics with sub-issues; each change lands
on a branch and merges to `main` only with its gates and evidence.

| Epic | Status |
|---|---|
| [#73 Linux OS on F2](https://github.com/bubblebabyboi/sigil/issues/73) | **Done**: Debian 13 on Linux 6.12 boots on the F2 and passes 22/22 checks (release `sigil-linux-f2-2026-10-22`); public AFI `agfi-0c8aa56fde1a48495` with all 64 GiB DDR4 + 16 GiB HBM ([#65](https://github.com/bubblebabyboi/sigil/issues/65)–[#67](https://github.com/bubblebabyboi/sigil/issues/67); [#62](https://github.com/bubblebabyboi/sigil/issues/62), [#63](https://github.com/bubblebabyboi/sigil/issues/63), [#74](https://github.com/bubblebabyboi/sigil/issues/74) fixed), Linux 6.12 + Debian 13 ([#68](https://github.com/bubblebabyboi/sigil/issues/68)–[#70](https://github.com/bubblebabyboi/sigil/issues/70), [#64](https://github.com/bubblebabyboi/sigil/issues/64)); next: F2 platform quirks ([#75](https://github.com/bubblebabyboi/sigil/issues/75)), Linux SDK ([#71](https://github.com/bubblebabyboi/sigil/issues/71)), networking ([#72](https://github.com/bubblebabyboi/sigil/issues/72)) |
| [#32 FPGA on AWS F2](https://github.com/bubblebabyboi/sigil/issues/32) | Whole SoC + Linux on hardware at 62.5 MHz; next: 100 MHz ([#53](https://github.com/bubblebabyboi/sigil/issues/53)) |
| [#26 SoC + physical](https://github.com/bubblebabyboi/sigil/issues/26) | nangate45 GDS done; sky130 hierarchical in progress ([#11](https://github.com/bubblebabyboi/sigil/issues/11)) → MPW go/no-go ([#13](https://github.com/bubblebabyboi/sigil/issues/13)) |
| [#61 Performance + microarchitecture](https://github.com/bubblebabyboi/sigil/issues/61) | Next track: performance harness, then branch prediction, superscalar, multithreading, multicore |
| [#25 Crypto + security](https://github.com/bubblebabyboi/sigil/issues/25) | Streaming hashes and on-core verify done; constant-time scalar-mul ([#5](https://github.com/bubblebabyboi/sigil/issues/5)); security review deferred ([#12](https://github.com/bubblebabyboi/sigil/issues/12)) |
| [#24 Verification + CI](https://github.com/bubblebabyboi/sigil/issues/24) | riscv-dv + branch protection ([#8](https://github.com/bubblebabyboi/sigil/issues/8)), ISA follow-ups ([#20](https://github.com/bubblebabyboi/sigil/issues/20)) |
| [#18 Core + software](https://github.com/bubblebabyboi/sigil/issues/18) | RV64GCV feature set complete |

More: [`docs/REMAINING-WORK-PLAN.md`](docs/REMAINING-WORK-PLAN.md) ·
[`docs/ROADMAP.md`](docs/ROADMAP.md) · [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md)

## Repository layout

```text
rtl/core/      In-house RV64GCV core: pipeline, FPU, vector unit, MMU, L1 caches
rtl/crypto/    SHA-256/512, Keccak, streaming hash engine, EC field unit
rtl/soc/       SoC top, fabric, CLINT, PLIC, UART, boot ROM, crypto bridge
rtl/fpga/      FPGA top, memory-bus -> AXI4 bridge, OCL registers
fpga/          AWS F2 Custom Logic (cl_sigil), build scripts, host runtime (sigil_host)
sw/sdk/        Bare-metal SDK (sigil.h, startup, drivers, template)
sw/examples/   Self-checking example programs
sw/            Firmware tests, Linux/OpenSBI inputs, ACT configs, golden models
tb/            Verilator C++ testbenches and SV harnesses
sim/           Simulation targets and suite runners
flow/          OpenROAD (ORFS) designs: nangate45 / sky130hd SoC and crypto macro
scripts/       Setup, builds, synthesis helpers
docs/          Specs, guides, plans, and evidence/
```

## Claim boundaries

- "GDS generated / place-and-route complete" describes the nangate45
  whole-SoC flow and the earlier crypto macro. Nothing has been taped
  out, fabricated or silicon-verified; nangate45 is an open research PDK.
- "Runs on F2" means the published AFIs on an AWS F2 FPGA, at the
  interim 62.5 MHz clock, with the evidence linked above.
- "Linux boots" on the F2 means single-hart OpenSBI + Linux 6.6 to an
  initramfs userspace (first AFI). "Debian" means Debian 13 on Linux
  6.12, one hart, the root file system on a host-loaded pmem disk, no
  network: 22/22 acceptance checks and a save/reload of the disk on one
  `f2.6xlarge` with AFI `agfi-0c8aa56fde1a48495` (2026-10-22), and 23/23
  in QEMU shaped like the F2 platform. No SMP claim.
  The KVM result is an entry/exit smoke with a tiny guest.
- ACT and riscv-tests results apply to the configurations and evidence
  files linked above; unchecked items are future work.
- The crypto engine is a functional implementation. It has **not** had a
  side-channel or fault-injection review and must not be used with real
  keys.

## Licence

Original Sigil code and documentation are licensed under the **GNU
General Public License v3.0** — see [LICENSE](LICENSE). External cores and
tools under `third_party/` keep their own licences.

The Sigil logo is an original project mark, not an official RISC-V logo.
Its lettering is UnifrakturMaguntia and Cinzel (both SIL Open Font License
1.1), converted to outlines by `docs/assets/src/gen_sigil_logo.py`.
"RISC-V" is used descriptively for the instruction-set target.
