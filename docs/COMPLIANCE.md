# Compliance matrix

"Compliant" here means: passes the named public test suite with a
stored report. Anything else is marked **not yet claimed**.
Last updated: 2026-10-14 (in-house core stages 1–8: RV64 IMABC FD SU + Sv39/PMP, B/Zicond/scalar crypto, Linux boot, H hypervisor with a KVM smoke, and integer V; earlier rows are the historical CVA6 characterization).

| Block | Suite | Status |
|---|---|---|
| SHA-256 core | FIPS 180-4 "abc"/empty KATs (`tb/cpp/sha256_tb.cpp`) | PASS (`make test`) |
| SHA-512 core | FIPS 180-4 / hashlib KATs (`tb/cpp/sha512_tb.cpp`) | PASS (`make test`) |
| Keccak-f1600 | Golden model vs hashlib SHA3-256 (`tb/cpp/keccak_tb.cpp`) | PASS (`make test`) |
| Streaming hash (accelerator top) | 70 multi-block KATs through AXI-Lite: SHA-512, SHA3-256, SHAKE256 vs hashlib; Keccak-256 vs in-repo sponge checked against published vectors (`tb/cpp/hash_stream_tb.cpp`, `sw/hash_kat.py`); RTL SoC firmware `sw/hash-tests/` | PASS (`make test`, `make -C sim sochash`); see `docs/evidence/` (2026-10-20) |
| EC field unit | Python mod-arith cross-check, edge cases | PASS (`make test`) |
| Ed25519 (ref model) | RFC 8032 TEST 1+2 sign/verify (`sw/ec_ops.py`) | PASS (algorithm only; HW sequencer pending) |
| secp256k1 (ref model) | `cryptography` ECDSA oracle vector | PASS (algorithm only) |
| ACT4 harness | riscv-arch-test ACT4, RV64I, DUT = Sail | 51/51 PASS on Sail — harness validation, **not** a hardware claim |
| CVA6 host smoke (B1) | riscv-tests `rv64ui-p-add`, `rv64ui-p-simple` on Verilator model | PASS — `*** SUCCESS *** (tohost = 0)`; see `docs/evidence/` (smoke only) |
| Spike solo (B2.1) | All 174 B2 directed-list ELFs on standalone tandem Spike, profile `matched` (config frozen in `docs/SPIKE_CONFIG.md`, B2.0) | 174/174 PASS exit 0 — validates ELFs + oracle only, **not** a CVA6 result; see `docs/evidence/` |
| Spike tandem (B2.3) | `SPIKE_TANDEM=1` RVFI lockstep vs CVA6 (`rvfi_compare`) | 173/174 PASS with 0 mismatches + 1 waived config divergence (`rv64mi-p-csr` cycle CSR without Zicntr; DUT passes) on branch `b2-tandem-act4`; zero unexplained mismatches; see `docs/evidence/` |
| RV64I/M/A/C + priv subset on CVA6 (B2.2) | 174 riscv-tests (ui/um/ua/uc/si/mi, `-p-`+`-v-`) on Verilator model via batch runner | 174/174 PASS — `*** SUCCESS *** (tohost = 0)` each, 0 fail/timeout/mismatch; solo only, no lockstep compare (B2.3); see `docs/evidence/` |
| ACT4 I/M on CVA6 (B2.4) | 64 self-checking ACT ELFs (51 I + 13 M, `sw/act4-cva6/` DUT config) on Verilator model | 64/64 PASS — each `*** SUCCESS ***` + `RVCP-SUMMARY: TEST PASSED`, 0 fail/timeout; combined B2 matrix in `docs/evidence/b2-combined-matrix-2026-10-12.csv` (B2.5) |
| RV64 F/D directed + ACT + TestFloat (sweep, #7/#20) | riscv-tests fp lists (46) solo/tandem + ACT F (84) / D (116) + Berkeley TestFloat level-1: RNE arithmetic/conversions/comparisons (756,144 vectors) + RTZ/RDN/RUP/RMM arithmetic/conversions (771,936 vectors) on model | Solo 46/46 + Spike 46/46, tandem F 22/22 (D tandem waived: harness `fld` stepping), ACT F/D 200/200, TestFloat 112/112 PASS, 1,528,080 vectors — `docs/evidence/testfloat{,-cvt,-rm}-cva6-2026-10-13.csv` (float->int flags compare masks NX: TestFloat `exact=false` oracle semantics, see evidence notes); level-2 density not yet claimed |
| RV64 A atomics ACT (sweep, #7) | ACT Zaamo (18) + Zalrsc (4) on model | 20/22 PASS; `Zalrsc-sc` (2) waived testharness hang (directed `lrsc` passes B2) — ACT A not yet claimed |
| RV64 B/C/Zicond/Zkn ACT (sweep, #16/#17) | ACT Zba/Zbb/Zbc/Zbs, Zbkb/Zbkc, Zca/Zcb/Zcd, Zicsr, Zifencei, Zicond, Zkne/Zknd/Zknh (133) on model | 133/133 PASS solo on branch `isa-verify-sweep` — `docs/evidence/act-bc-cva6-2026-10-12.csv`; tandem for these suites not run/claimed |
| RVV 1.0 (CVA6+Ara, superseded) | ACT4 vector suite (fixed VLEN) | Not claimed on the third-party stack; see in-house row below |
| In-house core integer V (stage 8, #23) | Own vec TB (1,014,476 checks) + directed asm; ACT Vx8/16/32/64 + Vls8/16/32/64 self-checking ELFs (Zve32x/Zve64x, VLEN 512) on the core | PASS (integer subset) — 1872/1872 generated ELFs; 34 ordered-indexed tests not generatable (Sail trap-signature overflow) and 9 Vx64 tests deselected (require full V), listed in `docs/evidence/act-vector-core-genfail-2026-10-14.csv`; FP vector (Zve32f/Zve64f/Zve64d) **not implemented / not claimed**; see stage-8 section of `docs/evidence/README.md` |
| Privileged/Sv39 (sweep, #7) | ACT privileged suites for this config (134: Sv/Svbare/Svade/Svnapot/SvSm/SvPMP, PMP S/U/Sm/F/Za, ExceptionsSv*) on model | 126/134 PASS solo — `docs/evidence/act-priv-cva6-2026-10-13.csv`; 8 waived (6 LR cause-class, 1 PMP G=1 readback, 1 PA0 data); Misalign/Svadu/Svinval/Svpbmt/Zicbo suites deselected (not implemented); Linux boot not yet claimed |
| OpenROAD macro (B3, #3) | ORFS nangate45, `muse_crypto_top` @ 100 MHz | PASS — detail-route DRC 0, antenna 0, liberty max-cap/slew/fanout 0 (signoff script in repo), setup WS +4.52 ns / hold WS +0.039 ns @ 10 ns, TNS 0; 61,590 cells, 95,431 µm², 20.16 mW; GDS in GitHub release `b3-nangate45-2026-10-13`; see `docs/evidence/b3-openroad-nangate45-2026-10-13.log`. Local Docker (emulated amd64) run, not a foundry signoff |
| In-house core scalar+priv (stages 1–6, #18/#21) | Own C++ Verilator TBs + directed asm (`make core-test`), riscv-tests, ACT, OpenSBI/Linux boot in `soc_tb` | PASS — riscv-tests 123/123, ACT 543/544 (1 PA0 waiver), Linux 6.6 to `/init` at 508,905,040 cycles; see stage-6 section of `docs/evidence/README.md` |
| In-house core H hypervisor (stage 7, #22) | Own CSR/MMU/decoder TBs + `hyp_directed.S`; Linux KVM ioctl/entry/exit smoke in `soc_tb`. No ACT H suite exists in the pinned ACT tree | PASS (smoke scope) — KVM reports Sv39x4/VMID14, a 4-instruction VS guest exits via `KVM_EXIT_MMIO` with the expected data, `SOC TB PASS` at 502,972,620 cycles; ACT H **not yet claimed** (no suite to run); see stage-7 section of `docs/evidence/README.md` |

Reproduce locally:

```sh
make test                 # crypto KATs (done today)
make lint                 # Verilator -Wall clean
make compliance           # ACT4 RV64I on Sail (harness only)
./scripts/cva6_docker.sh  # CVA6 model + ISA smoke tests (B1, long)
TEST_LISTS=asm,amo,mul ./scripts/spike_solo.sh        # B2.1 Spike-solo baseline
TEST_LISTS=asm,amo,mul RUN_NAME=solo-full ./scripts/cva6_docker.sh regression   # B2.2 (long)
SPIKE_TANDEM=1 TEST_LISTS=asm,amo,mul RUN_NAME=tandem ./scripts/cva6_docker.sh regression  # B2.3 (long)
./scripts/build_act4_cva6.sh  # B2.4 ACT ELFs; then run via cva6_docker.sh ELF_SUBDIR=act-elfs
./scripts/build_testfloat.sh  # sweep TestFloat checkers; then run via cva6_docker.sh ELF_SUBDIR=testfloat-elfs TEST_LISTS=testfloat
make openroad             # ORFS on muse_crypto (B3, long)
```

Pinned sources: CVA6 `81245a47`, Ara `34bd3bc1`,
riscv-arch-test `6af53584`, Sail 0.15, berkeley-softfloat-3
`a0c6494c`, berkeley-testfloat-3 `a9c849f1`. Notes: RISCOF is deprecated
upstream in favour of ACT4; Ubuntu Verilator 5.020 internal-faults on
CVA6 master (use its pinned v5.008); Docker builds here cap jobs at 2
(~8 GB RAM). Archive every future report under `docs/evidence/`.
