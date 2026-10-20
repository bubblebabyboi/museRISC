<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/muserisc-logo-dark.svg">
    <img src="docs/assets/muserisc-logo.svg" alt="museRISC — RV64GCV crypto accelerator SoC" width="760">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/bubblebabyboi/museRISC/actions/workflows/regression.yml"><img alt="RTL regression" src="https://github.com/bubblebabyboi/museRISC/actions/workflows/regression.yml/badge.svg"></a>
  <img alt="In-house core riscv-tests: 123/123" src="https://img.shields.io/badge/in--house%20core%20riscv--tests-123%2F123-brightgreen">
  <img alt="In-house core ACT: 543/544, one waiver" src="https://img.shields.io/badge/in--house%20core%20ACT-543%2F544%20(1%20waiver)-yellowgreen">
  <img alt="Linux 6.6 boot: pass" src="https://img.shields.io/badge/Linux%206.6%20boot-PASS-brightgreen">
  <img alt="Crypto KATs: pass" src="https://img.shields.io/badge/crypto%20KATs-PASS-brightgreen">
  <a href="LICENSE"><img alt="Licence: GPLv3" src="https://img.shields.io/badge/licence-GPLv3-57D0B8"></a>
</p>

# museRISC

museRISC is an open RISC-V project building a Linux-capable
processor and crypto accelerator in the open, one verified stage
at a time. The processor is now a clean-slate, in-house
SystemVerilog core: a 5-stage in-order RV64 design with
M/S/U privilege, Sv39 virtual memory, atomics, IEEE-754
floating point, compressed instructions, bit manipulation,
Zicond, scalar cryptography, and the H hypervisor extension
(HS/VS/VU modes with two-stage Sv39x4 translation). It boots
OpenSBI and Linux 6.6 in a Verilator platform model, and
Linux KVM on the core creates a VM and runs a tiny guest to
an MMIO exit. The companion crypto RTL
covers SHA-256, SHA-512, Keccak-f1600, and elliptic-curve
field arithmetic; the `muse_crypto` macro has a published
OpenROAD-generated GDS, but it is not attached to the core yet
and no chip has been taped out.

Third-party CVA6 and Ara were useful verification reference
points early in the project. They are no longer the product
core: current CPU claims refer to the in-house core under
`rtl/core/` and the evidence in `docs/evidence/`.

## Architecture

```text
                         museRISC in-house core
  +----------------------------------------------------------------+
  |  5-stage in-order pipeline  IF -> ID -> EX -> MEM -> WB       |
  |  RV64 IMABC + F/D + B/Zicond/scalar crypto + H                 |
  |  M/HS/VS/VU/U, Sv39 + Sv39x4 MMU, PMP, traps and interrupts    |
  +-----------------------------+----------------------------------+
                                | L1 I$ 8K + D$ 16K (write-back), one memory bus
          +---------------------+----------------------+
          |                                            |
  +-------v------------------+              +----------v-----------+
  | core_tb                  |              | soc_tb platform      |
  | directed asm, riscvtests |              | RAM, CLINT, PLIC,    |
  | and ACT compliance gates |              | UART, DTB, OpenSBI   |
  +--------------------------+              | and Linux 6.6        |
                                            +----------------------+

  +----------------------------------------------------------------+
  | muse_crypto macro (currently separate)                         |
  | SHA-256 | SHA-512 | Keccak-f1600 | EC field arithmetic         |
  | KAT-verified RTL; OpenROAD place-and-route complete; GDS made  |
  +----------------------------------------------------------------+
                       - - - future SoC attach (B4, #4) - - -
```

Key implementation files are
[`rtl/core/muserisc_core.sv`](rtl/core/muserisc_core.sv),
[`muserisc_csr.sv`](rtl/core/muserisc_csr.sv),
[`muserisc_mmu.sv`](rtl/core/muserisc_mmu.sv), and
[`muserisc_decoder.sv`](rtl/core/muserisc_decoder.sv). See
[`docs/CORE.md`](docs/CORE.md) for the staged design record.

## Current status

- **On `main`:** Stages 1–5 (scalar core, privilege, Sv39,
  A/F/D/B/C), Stage 6 (OpenSBI/Linux boot), and Stage 7
  (H hypervisor) are merged.
- **Linux:** OpenSBI v1.9 and Linux 6.6 boot on one hart to
  an embedded initramfs `/init`; the run reaches
  `MUSERISC_LINUX_BOOT_OK` and `SOC TB PASS` at 508,905,040
  cycles.
- **KVM smoke:** Linux KVM on the core reports the
  hypervisor extension with Sv39x4, creates a VM/vCPU, and
  a four-instruction VS-mode guest exits via `KVM_EXIT_MMIO`
  with the expected data (`SOC TB PASS`, 502,972,620
  cycles). This is an entry/exit smoke, not a guest-OS boot.
- **Integer V vector:** RVV 1.0 integer subset
  (Zve32x/Zve64x, VLEN 512) passes the ACT Vx/Vls vector
  suites, 1872/1872 generated self-checking ELFs
  ([#23](https://github.com/bubblebabyboi/museRISC/issues/23));
  43 tests were not generated/selected (documented in
  the evidence index).
- **Floating-point V vector:** Zve32f/Zve64f/Zve64d
  executes per element on the core's multi-cycle scalar
  FPU (`muserisc_fpu`, shared with the vector unit; the
  `vfrec7`/`vfrsqrt7` estimates run in the vector unit),
  including widening/narrowing
  forms, FMA, conversions (incl. `vfncvt.rod`),
  reductions, and the `vfrec7`/`vfrsqrt7` estimates. It
  passes the ACT Vf32+Vf64 suites, 162/162 generated
  self-checking ELFs
  ([#29](https://github.com/bubblebabyboi/museRISC/issues/29)).
  Full V and FP16 (Zvfh/Vf16) are not claimed.
- **L1 caches:** the core's memory ports are request/response
  with blocking L1 I$/D$ (SRAM-macro/BRAM-friendly arrays) in
  `muserisc_cpu` behind one AXI4-mappable memory bus; the core
  gates re-run with caches on and random bus latency, and with
  caches off ([evidence](docs/evidence/README.md), `docs/CORE.md`).
- **Crypto:** KATs pass and the standalone macro is
  place-and-route complete with GDS generated. Core attach
  (B4, [#4](https://github.com/bubblebabyboi/museRISC/issues/4))
  remains deferred.

## Supported features and coverage

“Covered” below means the result is reproduced by a repository
gate and recorded under `docs/evidence/`. The core target is
RV64GCV, built in stages; unchecked items are not claims.

### In-house core ISA

- [x] **RV64I + M** — base integer and multiply/divide
- [x] **A** — atomics, LR/SC and AMOs
- [x] **F/D** — single/double-precision floating point
- [x] **C** — compressed instructions (Zca/Zcb/Zcd),
      IALIGN=16, fetch realignment and page-straddle handling
- [x] **B + Zicond + scalar crypto** — Zba/Zbb/Zbc/Zbs,
      Zicond, Zbkb/Zbkc/Zkne/Zknd/Zknh
- [x] **Privilege M/S/U** — CSRs, precise traps, delegation,
      interrupts, PMP
- [x] **Sv39** — virtual memory, page faults, SFENCE.VMA
- [x] **H hypervisor** — HS/VS/VU modes, hypervisor CSRs,
      HLV/HSV/HLVX, HFENCE, and two-stage Sv39x4 (GEILEN=0)
      ([#22](https://github.com/bubblebabyboi/museRISC/issues/22))
- [x] **V vector (integer)** — RVV 1.0 Zve32x/Zve64x,
      VLEN 512/ELEN 64
      ([#23](https://github.com/bubblebabyboi/museRISC/issues/23))
- [x] **V vector (floating point)** — Zve32f/Zve64f/Zve64d
      ([#29](https://github.com/bubblebabyboi/museRISC/issues/29));
      full V and FP16 not claimed

### Tests and platform gates

- [x] Fast C++ Verilator unit testbenches for core modules —
      `make core-test`
- [x] Directed self-checking assembly suites —
      `sw/core-tests/`
- [x] Upstream `riscv-tests` on the in-house core —
      **123/123 PASS**
- [x] RISC-V ACT/arch-tests on the in-house core —
      **543/544 PASS**, one documented platform waiver
      (`PMPSm_cfg_A_tor_zero-00`)
- [x] OpenSBI boot smoke in `soc_tb`
- [x] **Linux boot smoke** — Linux 6.6 to embedded
      initramfs `/init`,
      [`MUSERISC_LINUX_BOOT_OK`](docs/evidence/core-stage6-linux-boot-2026-10-14.log)
- [x] Crypto RTL KATs — `make test`
      (`ALL PHASE-0 KATs PASS`)
- [x] Verilator lint — `make lint`
- [x] Standalone `muse_crypto` OpenROAD closure and GDS
      (GDS generated / place-and-route complete; not taped out)
- [x] H/KVM guest smoke — VM/vCPU creation and a tiny
      guest's MMIO exit under Linux KVM
      ([#22](https://github.com/bubblebabyboi/museRISC/issues/22));
      no ACT H suite exists in the pinned ACT tree yet
- [x] ACT vector suite — **1872/1872** generated
      self-checking ELFs (Vx8/16/32/64 + Vls8/16/32/64);
      43 ordered-indexed / full-V-required tests not
      generated by Sail/ACT selection, listed in
      [`docs/evidence/`](docs/evidence/act-vector-core-genfail-2026-10-14.csv)
      ([#23](https://github.com/bubblebabyboi/museRISC/issues/23))
- [ ] Core-attached crypto end-to-end test (B4,
      [#4](https://github.com/bubblebabyboi/museRISC/issues/4))
- [ ] Random-instruction riscv-dv regression in CI
      ([#8](https://github.com/bubblebabyboi/museRISC/issues/8))

### Current evidence snapshot

| Gate | Result | Evidence |
|---|---:|---|
| `make core-test` | PASS | `tb/cpp/`, `sw/core-tests/` |
| `riscv-tests` | 123/123 | [`riscv-tests-core-stage7-2026-10-14.csv`](docs/evidence/riscv-tests-core-stage7-2026-10-14.csv) |
| ACT | 543/544, 1 waiver | [`act-core-stage7-2026-10-14.csv`](docs/evidence/act-core-stage7-2026-10-14.csv) |
| ACT vector (integer) | 1872/1872 run, 43 not generated | [`act-core-stage8-2026-10-14.csv`](docs/evidence/act-core-stage8-2026-10-14.csv) |
| OpenSBI | PASS | [`core-stage6a-opensbi-2026-10-14.log`](docs/evidence/core-stage6a-opensbi-2026-10-14.log) |
| Linux 6.6 | PASS to `/init` | [`core-stage6-linux-boot-2026-10-14.log`](docs/evidence/core-stage6-linux-boot-2026-10-14.log) |
| L1 caches (random bus latency): riscv-tests / ACT | 123/123 · 2577/2578 (1 waiver) | [`act-core-l1cache-upstream-2026-10-16.csv`](docs/evidence/act-core-l1cache-upstream-2026-10-16.csv), [`l1cache-upstream-2026-10-16.log`](docs/evidence/l1cache-upstream-2026-10-16.log) |
| Linux KVM smoke | PASS (MMIO exit) | [`core-stage7-kvm-smoke-2026-10-14.log`](docs/evidence/core-stage7-kvm-smoke-2026-10-14.log) |
| Crypto KATs | PASS | `make test` |

The ACT waiver is a harness/platform-model mismatch at
physical address 0, documented in
[`docs/evidence/README.md`](docs/evidence/README.md); it is
not hidden in the count above.

## Quick start

Prerequisites for the fast gates are Verilator, a RISC-V ELF
toolchain (`riscv64-elf-gcc` or compatible), and Python 3.
The setup script checks tools and fetches pinned third-party sources.

```sh
git clone https://github.com/bubblebabyboi/museRISC.git
cd museRISC
./scripts/setup.sh

make core-test   # in-house core: C++ TBs + directed asm + coverage
make test        # crypto RTL KATs and Python golden models
make lint        # Verilator lint on RTL
```

Run the upstream core gates after setup and a core build:

```sh
bash sim/run_riscv_tests.sh
bash scripts/build_act4_core.sh
bash sim/run_act_core.sh
```

Reproduce the Linux boot with the commands in
[`sw/linux/README.md`](sw/linux/README.md). The boot is a
long Verilator run (about 509M cycles), not a per-commit gate.

## Roadmap

All major work is tracked as GitHub epics with native
sub-issues. Each milestone lands on an issue branch and is
merged to `main` only with its gates and evidence.

| Epic | Ordered work | Status |
|---|---|---|
| [#18 Core + software](https://github.com/bubblebabyboi/museRISC/issues/18) | [#21 Linux](https://github.com/bubblebabyboi/museRISC/issues/21) → [#22 H hypervisor](https://github.com/bubblebabyboi/museRISC/issues/22) → [#23 V vector](https://github.com/bubblebabyboi/museRISC/issues/23) | Linux + H + integer V done |
| [#24 Verification + CI](https://github.com/bubblebabyboi/museRISC/issues/24) | [#20 ISA follow-ups](https://github.com/bubblebabyboi/museRISC/issues/20) · [#8 riscv-dv/CI](https://github.com/bubblebabyboi/museRISC/issues/8) · [#19 SV/cocotb](https://github.com/bubblebabyboi/museRISC/issues/19) | Supports #18 |
| [#25 Crypto + security](https://github.com/bubblebabyboi/museRISC/issues/25) | [#6 streaming](https://github.com/bubblebabyboi/museRISC/issues/6) · [#5 scalar-mul](https://github.com/bubblebabyboi/museRISC/issues/5) · [#12 security review](https://github.com/bubblebabyboi/museRISC/issues/12) · [#10 benchmark](https://github.com/bubblebabyboi/museRISC/issues/10) | Security review gates key use |
| [#26 SoC + physical](https://github.com/bubblebabyboi/museRISC/issues/26) | [#4 B4 SoC attach](https://github.com/bubblebabyboi/museRISC/issues/4) → [#11 OpenROAD](https://github.com/bubblebabyboi/museRISC/issues/11) → [#13 MPW](https://github.com/bubblebabyboi/museRISC/issues/13) | Deferred |

More detail: [`docs/ROADMAP.md`](docs/ROADMAP.md) ·
[`docs/SPEC.md`](docs/SPEC.md) ·
[`docs/COMPLIANCE.md`](docs/COMPLIANCE.md) ·
[`docs/CORE.md`](docs/CORE.md)

## Repository layout

```text
rtl/core/     In-house SystemVerilog RV64 core
rtl/crypto/   SystemVerilog SHA-256/512, Keccak, EC-field RTL
rtl/soc/      SystemVerilog standalone crypto/SoC top
tb/cpp/       C++ Verilator unit, core, platform, crypto KAT TBs
sw/core-tests/ Directed assembly suites for the in-house core
sw/linux/     DT, boot stub, OpenSBI/Linux build inputs, init
sim/          Core/platform runners and upstream-suite scripts
scripts/      Setup, ACT/OpenSBI/Linux/OpenROAD build scripts
docs/         Specs, roadmap, compliance notes, and evidence/
flow/         OpenROAD designs for the crypto macro
third_party/  Pinned external sources (fetched, not the product core)
```

## Claim boundaries

- “Linux boots” means the recorded single-hart Verilator run
  reaches the embedded initramfs `/init`. It is not a distro,
  SMP, block/network, or hardware claim. The separate KVM
  result is a one-vCPU entry/exit smoke with a
  four-instruction guest, not a guest-OS boot.
- “GDS generated / place-and-route complete” describes the
  standalone crypto macro flow. It does not mean taped out,
  fabricated, or silicon-verified.
- ACT and riscv-tests results apply to the configurations
  and evidence files linked above; unchecked ISA items are
  future work.
- Phase-0 crypto is a functional reference, not
  side-channel-hardened production key hardware.

## Licence

Original museRISC code and documentation are licensed under
the **GNU General Public License v3.0** — see
[LICENSE](LICENSE). External cores and tools under
`third_party/` keep their own licences.

The museRISC logo is an original project mark, not an
official Muse or RISC-V logo. “RISC-V” is used descriptively
for the instruction-set target.
