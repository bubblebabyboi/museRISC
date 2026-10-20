# Task tracking

Canonical tracking is GitHub Issues. Execution order and acceptance
for everything still open is in
[docs/REMAINING-WORK-PLAN.md](REMAINING-WORK-PLAN.md) (packages
W0–W8). An issue closes only with a link to committed evidence under
`docs/evidence/`.

## Baseline gates ([milestone: Baseline B1-B4](https://github.com/bubblebabyboi/sigil/milestone/1))

- [x] [#1](https://github.com/bubblebabyboi/sigil/issues/1) **[B1] Host smoke** — CVA6 Verilator model passes `rv64ui-p-add` / `rv64ui-p-simple` *(historical CVA6 baseline)*
- [x] [#2](https://github.com/bubblebabyboi/sigil/issues/2) **[B2] Host regression** — Spike solo + CVA6 solo 174/174, tandem 173/174 + 1 waived divergence, ACT4 I/M 64/64 *(historical CVA6 baseline; `docs/evidence/b2-combined-matrix-2026-10-12.csv`)*
- [x] [#3](https://github.com/bubblebabyboi/sigil/issues/3) **[B3] OpenROAD closure** — `sigil_crypto` nangate45: DRC/antenna/liberty-electrical 0, setup +4.52 ns / hold +0.039 ns @ 10 ns; GDS in release `b3-nangate45-2026-10-13`
- [x] [#4](https://github.com/bubblebabyboi/sigil/issues/4) **[B4] SoC integration** — host is the in-house core (#18), not CVA6. Synthesizable SoC + on-core secp256k1 ECDSA verify (`docs/evidence/soc-rtl-4-2026-10-15.log`) and Ed25519 RFC 8032 verify, both with tamper rejects, cached and uncached (`docs/evidence/soc-rtl-ed25519-4-2026-10-20.log`; plan W1)

## In-house core ([epic #18](https://github.com/bubblebabyboi/sigil/issues/18))

- [x] Stages 1–9 (`docs/CORE.md`): RV64IMABC + F/D + B/Zicond/scalar crypto, Linux/OpenSBI boot ([#21](https://github.com/bubblebabyboi/sigil/issues/21)), H ([#22](https://github.com/bubblebabyboi/sigil/issues/22)), integer V ([#23](https://github.com/bubblebabyboi/sigil/issues/23)), FP vector ([#29](https://github.com/bubblebabyboi/sigil/issues/29))
- [x] Timing-closure refactors from PRs #33–#50: multi-cycle FPU and M unit, L1 I$/D$, element-serial vector unit, vector FP on the shared FPU, SRAM-macro arrays (toward [#32](https://github.com/bubblebabyboi/sigil/issues/32))

## Open work (see the plan for order and acceptance)

- [ ] [#5](https://github.com/bubblebabyboi/sigil/issues/5) Hardware scalar-multiply sequencer (constant-time) for Ed25519 + secp256k1 → W2
- [ ] [#6](https://github.com/bubblebabyboi/sigil/issues/6) Streaming SHA-512 and Keccak/SHA3 into the accelerator top → W3
- [ ] [#12](https://github.com/bubblebabyboi/sigil/issues/12) Security review before any key handling → W4
- [ ] [#8](https://github.com/bubblebabyboi/sigil/issues/8) riscv-dv random regression + branch protection → W5
- [ ] [#20](https://github.com/bubblebabyboi/sigil/issues/20) ISA verification follow-ups and legacy waivers → W5
- [ ] [#10](https://github.com/bubblebabyboi/sigil/issues/10) SHA-256 chain benchmark: scalar vs in-house V vs accelerator → W6
- [ ] [#11](https://github.com/bubblebabyboi/sigil/issues/11) Full-SoC hierarchical OpenROAD closure → W7
- [ ] [#13](https://github.com/bubblebabyboi/sigil/issues/13) MPW readiness: Caravel decision, DRC/LVS, shuttle checklist → W7
- [ ] [#32](https://github.com/bubblebabyboi/sigil/issues/32) AWS EC2 F2 FPGA bring-up (`docs/FPGA_F2.md`) → W8

## Closed

#7 ACT4 A/F/D + TestFloat · #9 Ara RVV (superseded by in-house V) ·
#16 C extension verification · #17 B/Zicond/scalar-crypto verification ·
#19 SystemVerilog/Verilator port · #27 helper packages ·
#28 CI core TBs + upstream smokes · #30 QEMU boot oracle ·
#31 OpenROAD rerun + tagged release
