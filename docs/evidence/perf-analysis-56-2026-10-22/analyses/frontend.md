# #56 analysis: front end and control flow

Recorded as written on 2026-10-22, before reconciliation. `docs/PERFORMANCE.md` sections 12-14 reconcile the three analyses and drop the claims the counters do not support; where this file and PERFORMANCE.md differ, PERFORMANCE.md is the result.

## Where the cycles go

FRONT-END LENS: about half of every scalar cycle on main (eeaa332) is lost in instruction fetch and control flow.

METHOD. Two sources:
(1) The measured #56 counters: perf-baseline-56-2026-10-22, branch 56-perf-harness at de21e4b.
(2) A trace-driven cycle model of the eeaa332 pipeline, with the front end coded to the RTL rules. Validated against the RTL counters before any what-if:
- Model cycles vs the RTL baseline cycles: CoreMark scalar 14,337,836 vs 14,337,806 (+0.0002%); validation +39 cycles; Dhrystone scalar 3,070,286 vs 3,070,244; SHA-256 C +8; Zknh +8. sky130: CoreMark +0.005%, Dhrystone +13, SHA C +40, Zknh +39.
- Exact matches: ic_access (6,806,626 / 1,502,031 / 1,384,025), ret_branch, br_taken, jal_redir, jalr_redir and muldiv_busy (375,840 / 6,000).
- micro_pipe agrees within 1 cycle per region, except brpat_always/alt/rand: a branch to the next instruction cannot be seen as taken in a PC trace.
- Scalar C kernels agree to -0.2..+1.1% (FPU latencies other than fadd/fmul/fmadd/fdiv/fsqrt are estimated). CoreMark sdk is -0.29% (9,443 vector ops not modelled).
- Traces: CoreMark, Dhrystone and kernels from Spike --log-commits on the baseline ELFs. sha256chain(_bulk) from an RTL retirement trace (Spike has no hash engine), using a sim-only $fwrite added to a git-archive copy of 8d15410. The copy's region-0 cycles equal the baseline, so the tap is passive.

MECHANISM (rtl/core/sigil_core.sv, sigil_icache.sv):
- IF asks the blocking I$ for one aligned 32-bit word per instruction. The I$ takes S_IDLE->S_LOOKUP->S_IDLE, and the core issues the next request only after the response (ifq_pend_q / ifw_valid_q). Result: 1 word per 2 cycles, 3 with SRAM_OREG.
- The second RVC parcel of a word is refetched (micro alu16 = alu32 = 2.04 CPI).
- A 32-bit instruction at pc%4==2 takes two fetches (straddle micro 4.06).
- Every taken branch, jal or jalr resolves in EX with predict-not-taken: br_taken 4.04 vs br_nt 2.04, call_ret 10.04; sky130 +3 per taken control transfer.

FETCH PORT SATURATION. Counters show the fetch port is ~95% busy:

| Benchmark | ic_access | 2 x ic_access | Cycles | Share |
|---|---:|---:|---:|---:|
| CoreMark | 6,806,626 | 13,613,252 | 14,337,806 | 94.9% |
| Dhrystone | 1,502,031 | 3,004,062 | 3,070,244 | 97.8% |
| SHA C | 5,020,738 | 10,041,476 | 10,156,268 | 98.9% |

sky130 CoreMark: 3 x 6,699,401 = 87% of cycles. CoreMark averages 2.97 B per instruction (51.4% RVC), but the pipe delivers 2 B/cycle, so IPC cannot exceed ~0.5.

PER-BENCHMARK, default soc. Each row gives the counter stk view, then the model's front-end cost split. Model terms: the floor is a near-ideal front end with perfect prediction; redirects = F0 minus F0+perfect; straddles = F0 minus the no-straddle run; the remainder is the issue gap.
- CoreMark scalar (IPC 0.366): stk fetch_lat 40.4%, straddle 5.4%, br+jal+jalr 4.8%, dc_lat 9.5%, muldiv 2.6%. Model: 45.0% of cycles are front end.
  - Issue gap 25.0%.
  - Taken redirects 11.9%: 744,296 = 617,615 br + 83,907 jal + 42,774 jalr, 14.2% of instructions, 2.29 cycles each.
  - Straddles 8.1%: 708,693, 13.5% of instructions.
  - Floor 7.88M cycles, IPC 0.666, set by retire + 1 D$ freeze cycle per load/store (1,365,221) + mul holds (375,840).
- Dhrystone scalar (IPC 0.337): 46.6% front end. Issue gap 17.1%, redirects 16.7% (179,999 = 17.4% of instructions), straddles 12.9% (210,011 = 20.3% of instructions). Floor IPC 0.632.
- SHA-256 C: 57.8% front end. Straddles 22.5% (1,159,176 = 31.2% of instructions), gap 32.4%, redirects 2.9% (loops, 96.6% taken).
- SHA-256 Zknh: 52.2% front end (gap 33.9%, straddles 13.6%, redirects 4.7%). Bulk C and Zknh are the same within 0.3 points.
- sky130 (registered SRAM reads): front end is 58.0% (CoreMark), 56.1% (Dhrystone), 69.4% (SHA C), 65.0% (Zknh). Each redirect and each straddle costs 3.0 cycles. This is why sky130 is 1.58-1.85x slower.
- Dhrystone sdk: same front end plus vls 19.3% (vector struct copy). The model reproduces RTL minus stk_vls to within 4k cycles.
- Front end is negligible here:
  - RVV paths: SHA RVV x16 is vec 89.6% / fetch 3.6%, so at most 1.037x from the front end. RVV kernels are vec+vls >= 95%, fetch <= 2.6%.
  - Accelerator regions: block API is fetch 33.4 + straddle 3.3 + br 4.2 against io 21.7. The CPU-side driver is front-end bound, but busy-wait polls depend on engine timing, so these regions are not modelled.
- I$ misses are negligible everywhere: CoreMark 39 misses = 468 cycles (0.003%); sky130 4 KiB DM 1,187 x 13 = 15,431 (0.07%). Dhrystone 13, SHA 8. Hot code is <= 6 KiB.

BRANCH BEHAVIOUR, from traces matching the RTL counters:
- CoreMark: 1,053,669 conditional branches (20.1% of instructions), 58.6% taken; 36,387 returns; 6,387 indirect calls.
- Dhrystone: 172,000 branches, 66.3% taken; 30,000 returns.
- SHA C: 148,481 branches, 96.6% taken.

| Predictor accuracy | CoreMark | Dhrystone | SHA (all regions) | Kernels C |
|---|---:|---:|---:|---:|
| BTFN | 81.6% | 90.7% | 91.3% | 96.7% |
| Bimodal 16 | 88.8% | 93.0% | 89.4% | 96.7% |
| Bimodal 32 | 90.7% | 96.5% | 90.5% | 96.7% |
| Bimodal 64 | 92.1% | 96.5% | 92.0% | 96.7% |
| Bimodal 256 | 92.5% | 96.5% | 92.3% | 96.7% |
| gshare 1K | 91.8% | 97.7% | 97.9% | |
| gshare 4K | 93.6% | 97.7% | 97.9% | |
| RAS-4 returns | 99.7% | 100% | | |
| RAS-8 returns | 100% | 100% | | |
| BTB 32 DM (taken targets) | 91.8% | 82.7% | 98.2% | |
| BTB 64 DM (taken targets) | 98.1% | 94.7% | 98.9% | |

With predecoded targets a BTB is unnecessary.

KEY INTERACTION. On today's fetch a predictor only removes 2 cycles per taken control transfer. Once fetch is decoupled, the redirect penalty becomes 3 cycles against a 1-CPI baseline (micro br_taken 4.04 on F3), so the same predictor is worth twice as much.

OTHER OBSERVATIONS:
- Code-placement sensitivity in PERFORMANCE.md (+/-24-26% for a 2-byte shift, +43% for SHA-512 without align-64) is this straddle mechanism.
- Part of the RVV advantage is the scalar front-end tax. With F3+BHT the scalar C kernels reach RVV/C of 0.98 (daxpy), 0.91 (ddot), 0.95 (idot_i32) and 0.99 (mac_i8), against 1.51-1.73 today. RVV itself is unchanged.

ARTIFACTS:
- `../frontend-model/` in this evidence set
  - fe.cpp: analyzer plus cycle model, final; identical to fe3.cpp on sigil-verify (sha256 8d2adf6f...).
  - run.sh, rtlrun.sh, batch3/4/5.sh, trace_patch.svh, tab.py, fe_summary.py (whatif.md).
  - out3/, out4/, out5/: results (newest copy of each file).
- sigil-verify: ~/fe-trace/
  - src/: git archive of 8d15410 plus the sim-only trace tap; never committed.
  - rtltrace.*.log.gz: RTL retirement traces.
  - run3.sh, out3..5.
- Tools: Spike 1.1.1-dev (riscv-isa-sim 2c300cd9), Verilator 5.048, g++ 13.3.0. ELFs from build/perf/baseline-56/default/bin at 8d15410. 2026-10-22.

ASSUMPTIONS:
- The default config models soc memory; axi adds <0.02% to these regions, and F2 hardware matches default/axi, so the results apply to the current AFI.
- The fpga (VRF_OREG) config equals default for all scalar regions.
- The model predicts at extraction into IF/ID, updates the BHT with the true outcome, and updates the RAS only on the correct path.
- Mispredicts flush from EX as today.
- The I$ stays blocking except in F4.
- D$ timing is unchanged: 1 freeze cycle per access (2 on sky130), unpipelined.

## Upgrade candidates

### 1. RVC/word reuse in IF (F1): keep the fetched 32-bit word (ifw_q) after its low parcel is consumed, so a following 16-bit parcel, or the low half of a straddling 32-bit instruction, needs no new I$ access

**Evidence.**

- RVC is 51.4% of CoreMark instructions (ret_rvc 2,695,749 / 5,246,413), 73.7% of Dhrystone, 37-55% of SHA.
- Today the second parcel of a word is refetched: micro alu16_dep 2.04 = alu32_dep 2.04 CPI.
- A straddle after an RVC fetches the same word twice: alu32_straddle 4.06.
- Correct-path I$ accesses from the CoreMark trace drop from 5,955,107 (per-instruction rule) to 4,193,728 with word reuse; the model's ic_access goes from 6,806,626 to 4,954,807.
- The cycle gain is mostly straddle-after-RVC: the next word is still requested only after the held word is used up.

**Estimated speedup.**

Counter arithmetic: each RVC-then-straddle pair saves 1 of 2 cycles (2 of 3 on sky130). CoreMark straddles 708,693 x ~1 cycle ≈ 0.7M ≈ 4.9% of 14.34M.

Model results (default / sky130):
- CoreMark: 14,337,836 -> 13,650,879 = 1.050x / 1.207x
- Dhrystone: 1.103x / 1.320x
- SHA-256 C: 1.194x / 1.329x
- Zknh: 1.166x / 1.303x

The fpga config is the same as default.

**Estimated cost.**

- Area: no new storage beyond one control bit next to ifw_q (32 b, already present); roughly 0.1 kµm² on nangate45 (<0.02% of 0.662 mm²) and about 15 LUTs / 1 FF on FPGA.
- fmax: low to medium. The 'keep word' term depends on parcel_long from the I$ response, which already drives pc_d. It adds a term to the ifw_valid/ifw_q enables; IF-stage state is a family-A sink at −3.48 ns in the #53 10 ns baseline, and ifw_q CE is a +0.21 ns path at 16 ns in the CL build.
- Verification: low, about 0.5 person-week. Directed tests: RVC pairs within a word across a trap, interrupt and FENCE.I; a straddle after an RVC; self-modifying code within one word.

**Risk.**

Small absolute gain on default/FPGA. It is completely subsumed by candidate 2, so only do it if candidate 2 is deferred. Its value is mainly on sky130 (1.21-1.33x), where each I$ access costs 3 cycles.

### 2. Decoupled 64-bit fetch (F3): widen irsp to the I$'s native 64-bit data word, add a 2-entry doubleword fetch queue with a parcel aligner, and prefetch the next sequential doubleword whenever the I$ is idle and the queue has room

**Evidence.**

The fetch port is saturated (2 x ic_access / cycles):
- CoreMark 13,613,252 / 14,337,806 = 95%
- Dhrystone 98%
- SHA C 99%
- sky130 CoreMark 3 x 6,699,401 = 87%

Why F3 helps:
- Average instruction size is 2.97 B (CoreMark) but delivery is 2 B/cycle; 8 B per 2-cycle access gives 4 B/cycle.
- The sigil_icache data way is already 64 bits; rsp_rdata_o just drops half of it.
- Correct-path doubleword fetches (trace): CoreMark 2,500,679 vs 5,955,107 word fetches.
- Straddles vanish because the next block is queued: micro alu32_straddle goes 4.06 -> 1.04, alu32/alu16 2.04 -> 1.03.
- Model front-end cost today: issue gap 25.0% plus straddles 8.1% of CoreMark; 17.1% + 12.9% of Dhrystone; 32.4% + 22.5% of SHA C.
- It also removes the ±24-26% code-placement sensitivity documented in PERFORMANCE.md, and cuts I$ SRAM reads from 6.81M to 3.74M on CoreMark.

**Estimated speedup.**

Counter-only bound (after the fix, the floor is instret + mem_stall_cyc + muldiv_busy + 3 x taken redirects, because micro br_taken on F3 = 4.04):
- CoreMark: 5,246,413 + 1,365,221 + 375,840 + 3 x 744,296 = 9.22M -> at most 1.555x
- Dhrystone: 1,036,022 + 390,046 + 6,000 + 3 x 179,999 = 1.97M -> 1.557x
- SHA C: 3,714,106 + 475,170 + 3 x 146,433 = 4.63M -> 2.19x
- Zknh: 1.90x

Model results (default / sky130); it adds load-use bubbles that were hidden by the fetch gap and the post-redirect I$ occupancy:
- CoreMark: 14.338M -> 10.197M = 1.406x / 1.751x
- CoreMark sdk: 1.419x
- Dhrystone: 1.431x / 1.716x
- SHA-256 C: 2.150x / 2.640x
- Zknh: 1.845x / 2.357x
- Bulk C / Zknh: 2.175x / 1.859x
- Dhrystone sdk (vector LS held constant): 3,482,242 -> 2,736,207 = 1.273x

Scalar C kernels 1.25-1.60x; RVV regions ~1.0x. The fpga config matches default on all scalar regions.

Variants:
- Registered queue only, no response bypass (F3s): CoreMark 1.274x, Dhrystone 1.293x.
- Keep 32-bit words but prefetch the next word (F3w4): with bim64 below, CoreMark 1.498x vs 1.702x; SHA C 1.641x vs 2.315x.

**Estimated cost.**

- Area: about 2.3 kµm² nangate45 (~0.35% of the 0.662 mm² SoC; ~2.4% of the 95.2 kµm² core pipeline). Made up of ~240 stored bits (2 x (64 data + ~54 address) + valid) at ~8 µm²/bit, plus the aligner, a +8 incrementer and control, minus ifw_q and straddle_lo_q. Bottom-up estimate, not synthesized.
- FPGA: about 250-350 LUTs and ~240 FFs (+3% of u_core's own 9,396 LUTs, +0.4% of the 80.5k-LUT SIGIL).
- fmax: low to medium.
  - The fetch address now comes from the queue's registered next-block pointer, which matches #53's step-7 contingency (a registered fetch_va) and keeps adders off pc_d.
  - The I$-data -> IF/ID bypass gains about one mux level: a 4:1 parcel select plus a queue/bypass select, against today's two 2:1.
  - The F3s fallback has no new paths.
- Verification: medium to high, about 3-4 person-weeks.
  - PMP has a 4-byte grain (sigil_csr pmp_match uses PA[55:2]), so the two halves of a doubleword can differ in X. Add a registered 'fine-PMP' flag, set when any active entry boundary is not 8-byte aligned, that falls back to 32-bit fetch; or check both words.
  - Never prefetch across a 4 KiB page, so there are no speculative walks or faults; a fault rides with the queued block and is raised only when the block is consumed.
  - Straddle-across-page tval; flush on FENCE.I/SFENCE/satp/trap; I$ inval during an in-flight prefetch (fill_kill); uncached boot-ROM fetch.
  - Gates: core-test, riscv-tests, ACT including PMP, the riscv-dv flow, Linux boot.

**Risk.**

- Fetch is the most correctness-sensitive unit: speculative prefetch near page and PMP boundaries is the main bug risk.
- Benefit depends on keeping the response bypass: F3s is 1.27x instead of 1.41x on CoreMark.
- After the fix the D$ hit freeze (1 cycle per load/store, 1.365M cycles on CoreMark) becomes the next limiter. That is outside my lens.
- Cycle-count-based evidence (perf baselines, F2 sim-vs-hardware match) must be regenerated.

### 3. Branch prediction on top of F3: JAL/c.j taken via predecode, conditional branches from a 64-entry 2-bit bimodal BHT (indexed by pc[6:1]) with predecoded target pc+imm, returns from a 4-entry RAS, other jalr left to EX; mispredicts use the existing EX flush

**Evidence.**

Taken control transfers on F3 cost 3 cycles each (micro br_taken 4.04, call_ret 10.03); CoreMark has 744,296 of them (14.2% of instructions), Dhrystone 179,999 (17.4%), SHA C 146,433 (3.9%).

Trace accuracy:

| | CoreMark | Dhrystone | SHA loops |
|---|---:|---:|---:|
| bim64 | 92.1% (83,217 mispredicts / 1,053,669) | 96.5% | 92-97% |
| RAS4 | 99.7% of 36,387 | 100% | |

Other schemes on CoreMark:
- Remaining CoreMark flushes: 89,706, down from 744,296.
- Static BTFN only: 81.6% (CoreMark), 90.7% (Dhrystone).
- Bigger tables add almost nothing: bim256 92.5%, gshare-4K 93.6% (+0.8% cycles for 8 kbit).
- A 64-entry BTB instead of predecoded targets is slightly worse (CoreMark 1.117x vs 1.118x on today's fetch) and costs ~4.5 kbit.

Correctly predicted taken transfers cost 1 cycle at extraction (micro br_taken 2.04, call_ret 5.02).

**Estimated speedup.**

Counter arithmetic on F3 (each transfer is either predicted-taken at 1 cycle or a mispredict at 3; floor = instret + mem_stall_cyc + muldiv_busy):
- CoreMark: 5,246,413 + 1,365,221 + 375,840 + 766,500 x 1 + 89,706 x 3 = 8.02M -> at most 1.787x
- Dhrystone: 1,036,022 + 390,046 + 6,000 + 181,992 + 6,009 x 3 = 1.63M -> at most 1.881x

Model results, F3+bim64 (default / sky130), and the marginal gain over F3 alone:
- CoreMark: 8.424M = 1.702x / 2.084x; +21.1% over F3
- CoreMark sdk: 1.713x
- Dhrystone: 1.804x / 2.129x; +26.1%
- SHA C: 2.315x / 2.836x; +7.7%
- Zknh: 2.070x / 2.590x
- Dhrystone sdk: 3,482,242 -> 2,312,219 = 1.506x (fpga config 1.483x)
- C kernels: 1.50-2.48x

Variants (CoreMark / Dhrystone / SHA C):
- Timing-safe one-bubble variant (target formed from registered data, +1 cycle per predicted-taken, 'r1'): 1.585x / 1.698x / 2.248x.
- Static BTFN + JAL + RAS4 only: 1.655x / 1.770x / 2.315x.
- Perfect prediction ceiling on F3: 1.763x / 1.832x / 2.326x.

**Estimated cost.**

- Area: about 5.2 kµm² nangate45 (0.8% of SoC; ~5.5% of the core pipeline). Breakdown:
  - BHT 128 b ≈ 1.0 kµm²
  - RAS 4 x 64 b ≈ 2.0 kµm²
  - Predecode, immediate select and target adder ≈ 1.0 kµm²
  - Predicted bit and target through IF/ID and ID/EX plus the EX compare ≈ 1.2 kµm²
  - Static-only (no BHT) ≈ 4.2 kµm²
- FPGA: about 350 LUTs and ~400 FFs; the BHT fits in 2-4 LUTRAM LUTs.
- fmax: medium for the zero-bubble form, low to medium for the r1 form.
  - Zero-bubble puts predecode plus an adder after the I$/queue data into the next-fetch address; this is the same pc_r/pc_d region #53 already calls tight. Mitigate with a split carry-select adder on imm[12:0]/[20:0].
  - Mispredict detection adds an XOR on the EX flush (flush arrives at 8.83 ns and branch_taken at 6.88 ns in the #53 10 ns baseline).
  - Return checks compare ex_rs1 (3.44 ns) against the RAS target for imm==0 returns only, which keeps them off the critical path.
- Verification: medium, about 2-3 person-weeks. New redirect source; predicted-taken but not taken goes to pc+len; RAS target mismatch; faults and interrupts on the predicted path (precise, since faults ride to WB and are flushed); never predict xRET/FENCE.I/SFENCE; br_taken and squash counter semantics change.

**Risk.**

- The gain roughly halves if the zero-bubble path cannot close at 100 MHz (r1 variant).
- RAS corruption by wrong-path calls is a performance issue, not a correctness one.
- Accuracy is measured on these benchmarks only; Linux and indirect-heavy code will be lower. The 6,387 CoreMark indirect calls stay in EX.
- The gain is far larger after candidate 2 than before it (see 4), so sequence it after 2.

### 4. Same predictor (bim64 + JAL predecode + RAS4) on today's 2-cycle fetch (F0), as an alternative if candidate 2 is deferred

**Evidence.**

On today's fetch:
- Taken redirects cost 2.0 cycles each (micro br_taken 4.04 vs br_nt 2.04; jal 4.04; call_ret 10.04).
- CoreMark 744,296 redirects x 2 = 1.49M = 10.4% of cycles; Dhrystone 2 x 179,999 = 11.7%; SHA C 2.9%.
- stk_branch+jal+jalr (4.8% / 3.7%) shows only half of this, because the refetch after a redirect is charged to stk_fetch_lat.
- Because the next I$ request is not issued until the cycle after extraction anyway, a correct prediction at extraction hides the redirect completely: micro br_taken 2.04, call_ret 6.03.

**Estimated speedup.**

Counter arithmetic: (744,296 − 89,706 remaining flushes) x 2 = 1.31M -> 9.1% fewer CoreMark cycles. Dhrystone: (179,999 − 6,009) x 2 = 0.35M = 11.3%.

Model (default / sky130):
- CoreMark: 1.118x / 1.093x; one-bubble r1 variant 1.060x / 1.055x
- Dhrystone: 1.193x / 1.110x; r1 1.117x / 1.069x
- SHA C: 1.029x / 1.027x
- Zknh: 1.047x / 1.040x
- Perfect-prediction ceiling on today's fetch: CoreMark 1.135x, Dhrystone 1.200x
- Static BTFN + JAL + RAS4: CoreMark 1.098x, Dhrystone 1.182x

**Estimated cost.**

- Area: same as candidate 3 (~5.2 kµm², ~350 LUTs).
- fmax: the zero-bubble form needs the adder on the I$-data -> pc_d path (medium to high risk at 100 MHz). The r1 form registers the target in ID and gates ireq_valid with a registered 'predicted-taken in IF/ID' bit (low risk).
- Verification: same as candidate 3, 2-3 person-weeks.

**Risk.**

Worse speedup per unit of cost than 2 or 3: the same hardware buys 1.12x here against +21% after F3. Only worth it if fetch decoupling is deferred for a long time.

### 5. Pipelined (back-to-back) I$ hits (F4): let sigil_icache accept a new request in S_LOOKUP on a hit, extending #53 step 6's speculative array reads to the lookup state, with a 3-entry fetch queue

**Evidence.**

With F3 the blocking I$ (one access per 2 cycles, 3 on sky130) is the remaining fetch limit, especially on sky130 and after redirects: a useless sequential prefetch occupies the I$ when the EX redirect arrives. Model F3+bim64 -> F4+bim64.

**Estimated speedup.**

Increments over F3+bim64 (model):
- CoreMark: 1.702x -> 1.752x (+2.9%)
- Dhrystone: 1.804x -> 1.840x (+2.0%)
- SHA C: +1.8%
- sky130 CoreMark: 2.084x -> 2.242x (+7.6%)
- sky130 Dhrystone: +4.0%
- sky130 SHA C: 2.836x -> 3.242x (+14.3%)

The near-ideal front end with perfect prediction (64 B/access, 4-deep, pipelined) tops out at CoreMark 1.819x, Dhrystone 1.874x, SHA C 2.369x (default).

**Estimated cost.**

- Area: about 0.5 kµm² (FSM, address mux, one extra queue entry ≈ 120 b).
- FPGA: about 100-150 LUTs.
- fmax: medium. The hit (tag LUTRAM -> 44-bit compare) now gates acceptance and the next array address in the same cycle. With SRAM_OREG it is a natural 2-stage read pipeline.
- Verification: medium, 1-2 person-weeks (icache_tb plus core tests with random bus latency, fill_kill/inval in flight).

**Risk.**

Small gain on default/FPGA. It mainly benefits sky130, where each access is 3 cycles. Touches the I$, which #53 is also editing.

### 6. 128-bit fetch block for the sky130 build (F3 with W=16)

**Evidence.**

- The sky130 L1 data way is a sky130_sram_1rw1r_128x256_8 already read 128 bits wide and then half-selected (SOC_AREA.md), so a 16-byte block costs no macro change on sky130.
- On sky130 the fetch stays partly bandwidth-bound even with F3: 8 B per 3-cycle access = 2.67 B/cycle < 2.97 B/instruction.

**Estimated speedup.**

Model (CoreMark / Dhrystone):
- sky130, F3 -> F3w16: 1.751x -> 1.886x (+7.7%) / 1.716x -> 1.817x
- sky130 with BHT (registered-queue form): F3s+bim64 1.849x -> F3w16s+bim64 2.079x (+12.4%)
- default: 1.406x -> 1.460x (+3.8%)

**Estimated cost.**

- sky130: no macro change; the queue grows by ~2 x 64 b (≈ 1 kµm² nangate45-equivalent).
- nangate45: needs a 256x128 fakeram or two 512x64 macros per way read together.
- FPGA: +1 BRAM36 per way.
- fmax: low (queue width only).
- Verification: small on top of candidate 2.

**Risk.**

Only worth it for the sky130 respin; on default/FPGA the gain is 3-4%.

### 7. Not recommended from this lens: larger or global predictors and BTBs, a larger or more associative I$, wider decode / dual issue

**Evidence.**

- Predictors: gshare-4K vs bim64 is +0.8% on CoreMark, +0.3% on Dhrystone and 0 on SHA (F3 model). A 64-entry BTB instead of predecoded targets is equal or worse (1.117x vs 1.118x on F0) at ~4.5 kbit.
- I$: CoreMark 39 misses = 468 cycles (0.003%); sky130 4 KiB DM 1,187 x 13 = 15,431 (0.07%); all hot code is <= 6 KiB (micro_imem: footprints <= 8 KiB hit).
- Decode width: even a near-ideal front end with perfect prediction leaves single-issue IPC at 0.666 (CoreMark) and 0.632 (Dhrystone). The floor is retire + 1 D$ freeze cycle per load/store (mem_stall_cyc 1,365,221 = 16% of F3+bim64 cycles) + mul holds (375,840) + load-use, so a second decode slot has nothing to issue.
- Software-only control (not a uarch change): building without C (no straddles) gives 1.088x CoreMark, 1.148x Dhrystone, 1.290x SHA C on today's core. That quantifies the straddle cost; candidate 2 recovers it in hardware.

**Estimated speedup.**

- gshare-4K: +0.3-0.8%
- BTB: ≈ 0
- I$ capacity: < 0.1%
- Dual issue: no measurable gain until the D$ hit freeze is pipelined (memory lens)

**Estimated cost.**

- gshare-4K: 8 kbit ≈ 64 kµm² in flops (≈10% of SoC) or an SRAM macro.
- BTB64: ≈ 36 kµm² in flops.
- I$ growth: macro area (6.2 mm² of sky130 macros already).
- Dual issue: very high area and verification cost.

**Risk.**

Cost far exceeds any measurable benefit on these workloads; revisit with Linux or OS traces.
