# Roadmap

Detailed, ordered remaining work: [REMAINING-WORK-PLAN.md](REMAINING-WORK-PLAN.md).
Issue status: [TASKS.md](TASKS.md).

## Phase 0 — Foundation (2026-10-12) ✅
- [x] Repo scaffold, spec, locked decisions (RV64GCV / dual-curve / sim+OpenROAD)
- [x] SHA-256 + SHA-512 block cores, Keccak-f1600, EC field unit + KATs
- [x] AXI-Lite `muse_crypto` top, Verilator lint clean
- [x] Ed25519 (RFC 8032) + secp256k1 (ECDSA) reference ops over field primitives
- [x] Toolchain, ACT4 harness, CVA6/Ara/arch-test at pinned commits

## Baseline gates ✅ except B4
- [x] **B1/B2** CVA6 host smoke + regression (historical reference host)
- [x] **B3** `muse_crypto` OpenROAD closure, nangate45 GDS (#3)
- [ ] **B4** SoC integration on the in-house core (#4): synthesizable SoC
      and on-core secp256k1 verify done; Ed25519 verify remaining (W1)

## Phase 1 — In-house RV64GCV core (replaces CVA6/Ara) ✅
- [x] Stages 1–9 in `docs/CORE.md`: scalar IMABC, F/D, B/Zicond/scalar
      crypto, Sv39/PMP, Linux 6.6 + OpenSBI boot, H, integer + FP vector
      (RVV 1.0, VLEN 512); riscv-tests 123/123, ACT 2577/2578 (one PA0
      platform waiver)
- [x] Timing-closure refactors (PRs #33–#50): multi-cycle FPU/M, L1
      caches, element-serial vector, SRAM-macro arrays; SoC synthesizes
      (`docs/SOC_AREA.md`)

## Phase 2 — Hardened crypto
- [ ] Streaming SHA-512/Keccak into the accelerator top (#6, W3)
- [ ] Constant-time hardware scalar-mul sequencer (#5, W2)
- [ ] Side-channel/fault security review before any key handling (#12, W4)
- [ ] SHA-256 chain benchmark: scalar vs vector vs accelerator (#10, W6)

## Phase 3 — Verification hardening
- [ ] riscv-dv random regression + branch protection (#8, W5)
- [ ] ISA follow-ups and legacy waivers (#20, W5)

## Phase 4 — Physical proof
- [ ] FPGA: AWS F2 bring-up, ≥100 MHz, bare-metal → Linux (#32, W8)
- [ ] ASIC: full-SoC OpenROAD closure (#11), then MPW go/no-go (#13) (W7).
      Area check first: if RV64GCV+crypto exceeds the harness, ship the
      crypto macro + RV64GC host and keep vector as FPGA/ASIC-v2.
