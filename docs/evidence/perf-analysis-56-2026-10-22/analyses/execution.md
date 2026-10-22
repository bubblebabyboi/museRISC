# #56 analysis: execution units and parallelism

Recorded as written on 2026-10-22, before reconciliation. `docs/PERFORMANCE.md` sections 12-14 reconcile the three analyses and drop the claims the counters do not support; where this file and PERFORMANCE.md differ, PERFORMANCE.md is the result.

## Where the cycles go

Source: branch 56-perf-harness at de21e4b, docs/evidence/perf-baseline-56-2026-10-22/{headline.md, default|sky130|fpga/results.csv}. Main eeaa332 RTL, rtl/ tree 89b98cb227c6. Unless noted, numbers are default/soc. sky130 and fpga are noted where they differ. The repo was not modified. The helper scripts are in counters/.

THE CEILING THAT LIMITS EVERY CANDIDATE IN THIS LENS: the I$ port.
- How fetch works:
  - The I$ accepts a request only in S_IDLE, and a hit answers in S_LOOKUP (rtl/core/sigil_icache.sv), so the port can start a new request at most every 2 cycles (every 3 on sky130).
  - The core starts the next fetch only after the previous response (sigil_core.sv, `ireq_valid_o ... !ifq_pend_q`).
  - Every instruction re-fetches its own aligned 32-bit word. Two RVC halves in one word are fetched twice, and the other 32 bits of the 64-bit array read are thrown away.
- Fetches per instruction: CoreMark makes 6,806,626 I$ accesses for 5,246,413 instructions, 1.297 per instruction (straddles plus 683,136 squashed wrong-path instructions).
- Measured port occupancy, computed as 2 x ic_access / cycles:

  | Benchmark | Occupancy | Idle cycles |
  |---|---|---|
  | CoreMark | 94.9% | 724,086 (5.05%) |
  | Dhrystone | 97.8% | 66,026 (2.2%) |
  | SHA-256 C | 98.9% | 1.1% |
  | Zknh | 97.4% | 2.6% |
  | sky130 CoreMark (3 cycles per access) | 87.3% | 12.7% |

- What this means:
  - Scalar code already runs at 95–99% of its fetch ceiling. CoreMark's ceiling IPC is 5,246,413 / (2 x 6,806,626 + misses) = 0.385, and it measures 0.366. The absolute ceiling is 1/2.028 = 0.493, from the micro_pipe alu32_dep result.
  - The execution-side accounting categories overlap the fetch gap:
    - A load's 1-cycle dc_lat really costs +0.5 (ld_indep 2.525 vs alu 2.028).
    - A 2-cycle MUL hold costs about 1 in mixed code: during the hold the I$ prefetches one word.
  - So any change that does not touch fetch (faster M/FPU, dual-issue, FGMT) can recover at most the I$-idle cycles: 5.05% of CoreMark, 2.2% of Dhrystone, 1.1% of SHA-C.
  - Vector and accelerator regions are the opposite case. The I$ is 1–9% busy (SHA RVV 9.3%, dgemm RVV 4.1%), so the execution units are the critical path there.

PER BENCHMARK, from the execution-unit and parallelism lens (stk % of cycles):
- **CoreMark scalar**: 14,337,806 cycles, IPC 0.366.
  - retire 36.6, fetch_lat 40.4, straddle 5.4, dc_lat 9.5, branch+jal+jalr 4.8, muldiv 2.6, loaduse 0.7, FPU 0, vec 0.
  - dc_lat is exactly 1 cycle x 1,365,092 loads and stores.
  - muldiv is 187,920 MUL x 2.0 busy cycles = 375,840 (no divides). Its real marginal cost is about 1 cycle per MUL, 1.3%.
  - The execution units are not a CoreMark lever on today's front end. sky130 has the same shape: fetch_lat 60.6, muldiv 1.6.
- **Dhrystone scalar**: 3,070,244 cycles, IPC 0.337.
  - fetch 40.6 + straddle 8.9, dc_lat 12.7, branch 3.7, muldiv 0.2 (2,000 DIV x 3 cycles).
- **Dhrystone sdk**: vls is 19.3%: 4,000 vle8/vse8 at vl=56 (the 56-byte record copy) x 168 cycles = 3 cycles per byte.
  - The element-serial VLS makes the vectorized struct copy about 10x slower than 7 ld/sd pairs. That is why sdk scores 0.327 DMIPS/MHz against 0.371 for scalar.
  - On fpga the vls share is 21.8% (196 cycles per instruction); on sky130 it is 16.9% (252).
- **SHA-256 plain C**: 9,918 cycles/hash, 3,627 instructions/hash, fetch-bound.
- **SHA-256 Zknh**: 6,753 cycles/hash. The Zknh ops are single-cycle in bext. The 1.47x is just the instruction-count cut (2,667 vs 3,627 per hash, -26.5%) at the same fetch ceiling.
- **SHA-256 RVV x16**: 4,642 cycles/hash, vec 89.6%.
  - 213,131 vector ops at vl=16, e32, each N+4 = 19.98 busy cycles. That is 16 element-ops per ~21.75 cycles, or 0.74 per cycle.
  - The fixed +4 is 20% of vector time.
  - It beats C by 2.14x only because the vector unit escapes the fetch ceiling.
- **SHA-256 accelerator, sigil_sha256_block**: 572 cycles/hash.
  - The engine itself is 64 cycles at 1 round/cycle, 11% of the time.
  - The rest is CPU PIO: 159 instructions/hash plus 31 uncached 32-bit MMIO accesses at 5.0 cycles each (io 21.7% = 124 cycles/hash).
  - The byte API costs 2,793 cycles/hash: +846 instructions/hash of byte-wise packing and unpacking in sw/sdk/lib/accel.c (lines 26 and 30).
  - Comparison: the accelerator is 8.1x RVV and 11.8x Zknh. Zkn and RVV upgrades cannot catch it.
- **Bulk SHA-512 and SHA3 accelerators**: 0.2388 and 0.2398 B/cycle (axi 0.2205 / 0.2215).
  - Cost per 32-bit word through the AXI-Lite bridge: 16.73 cycles = retire 4.05 + fetch 5.06 + io 4.0 + dc_lat 2.0 + branch 1.0 + dc_miss 0.61 (lw, sw MMIO, addi, bne).
  - The engines can go far faster: SHA-512 1.6 B/cycle (128 B per 80 cycles), Keccak 5.67 B/cycle (136 B per 24 cycles). They sit idle 85% and 96% of the time.
- **RVV kernels**: vec + vls is 95–99% of cycles, fully serialized.
  - FP vector ops pay the full FPU latency +1 per element. vfmacc costs 8 cycles per element: dgemm runs 1024 vfmacc per call x (8x32+4) = 260 cycles, so vec is 68.5%; fir 71%.
  - Vector integer multiply costs (k+4) per element: vwmul e8 is 5 per element (mac_i8 vec 49.7%), vwmacc e32 is 6 (idot vec 49.2%).
  - Vector ALU ops cost 1 per element +4.
  - VLS costs 3 cycles per element at any SEW (vle8 vl=512 = 1,537.6 cycles). It is 26–28% of gemm and fir, 47–53% of the mac kernels, saxpy and daxpy, and 86–99% of vadd, memcpy and memset.
  - fpga (VRF_OREG) adds +1 per vector op and +1 per stored element. sky130 adds +1 per op, with loads at 4 per element and stores at 5.
- **Scalar FP C kernels**: stk_fpu is 18.7–27.2%. Every fmadd holds EX 6 cycles (dgemm C: 131,072 x 6 = 786,432). The I$ is idle 20–33% of the time, so this time is recoverable.

PARALLELISM CEILINGS:
- **Dual-issue and FGMT** share the saturated I$ port, so today they can gain at most 1/0.9495 = 1.053x on CoreMark, 1.022x on Dhrystone and 1.011x on SHA-C (sky130 CoreMark 1.146x).
- **Multicore** escapes that limit through private I$s, and CoreMark's bus is 0.0% busy.
- **If the front end were fixed** (another lens): the best single-issue case would be retire 36.6 + dc_lat 9.5 + branch 4.8 + muldiv 2.6 + loaduse 0.7 = 54.2% of today's CoreMark cycles (IPC 0.675). Only then do issue width and multithreading become worth their cost.

COST REFERENCES:
- nangate45, hierarchical (docs/SOC_AREA.md): SoC 689,218 µm²; the core including L1s is about 585,100.
  - fpu 51,448; vec 62,231; VRF 3 x 13,252; muldiv 39,147; csr 57,009; mmu 65,119; pipeline and RFs 95,212; crypto top and bridge 45,895 (measured before the hash stream existed).
- FPGA, F0 VU47P (docs/evidence/fpga-f0-2026-10-21/impl_util_hier.rpt):
  - u_cpu 54,848 LUTs / 15,427 FFs.
  - fpu 5,571 LUTs / 1,346 FFs / 9 DSPs; vec 13,091 LUTs / 4 DSPs; muldiv 2,514 LUTs / 16 DSPs; hash_stream 13,653 LUTs.
  - SoC total 78,699 LUTs, 6.1% of the device.
- Timing:
  - The F2 build runs at 62.5 MHz. Its worst path is VRF bank to D$ enable, 43 levels (fpga-cl-54).
  - The F0 out-of-context (OOC) run at 10 ns gives 68.0 MHz, and 70.3 MHz with VRF_OREG. Its worst path is then EX/MEM to MEM-stage translate/PMP/trap to exmem_result, 68 levels (fpga-vrf-oreg-53 log).
  - nangate45 reaches 162 MHz unrepaired. So fmax risk means the FPGA MEM stage and the VRF-to-memory paths.

## Upgrade candidates

### 1. Hash-engine fast feed: posted MMIO writes in sigil_crypto_bridge plus a 64-bit HDATA write (sd) into sigil_hash_stream; also unroll the SDK sigil_hash_update loop and pack the sigil_sha256 byte API by word (software)

**Evidence.**

- Bulk SHA-512 and SHA3 spend 16.73 cycles per 32-bit word (default/soc): retire 4.05 (lw, sw, addi, bne), fetch 5.06, io 4.00, dc_lat 2.0, branch 1.0, dc_miss 0.61.
- Each uncached access costs 5.0 cycles (dc_unc_cyc 82,045 / dc_unc 16,409).
- The engines can take 1.6 B/cycle (SHA-512) and 5.67 B/cycle (Keccak), but they are fed 0.239 B/cycle.
- The I$ is idle 27.6% of the time (4.6 cycles/word), so the io stall really is exposed.
- The sigil_sha256 byte API runs +846 instructions/hash of byte loops (accel.c lines 26 and 30): 2,793 vs 572 cycles/hash.

**Estimated speedup.**

**Bulk SHA-512 / SHA3, default/soc:**
- 64-bit HDATA: one (ld, sd, addi, bne) iteration of about 16.7 cycles now moves 8 bytes, so 2 x 16.73 = 33.5 becomes 16.7 cycles per 8 B (2.0x).
- Posted writes: io drops from 4.0 to about 0.5 per store (bounded by the 4.6 cycles/word of I$ idle), saving about 3.5, so about 13.2 cycles per 8 B.
- Together: 0.2388 becomes about 0.60 B/cycle, 2.5x. axi: 18.12 becomes about 14.6 cycles per 8 B, 0.55 B/cycle, 2.5x.
- Adding the unrolled SDK loop (x4): the addi + taken-bne overhead of about 6 cycles drops to about 1.5, so about 8.7 cycles per 8 B, 0.92 B/cycle, about 3.8x.
- The engine still has headroom: 1.6 B/cycle for SHA-512.

**SHA-256 chain:**
- Block API: 17 posted writes x about 3.5 = about 60 of 572 cycles, 1.12x.
- Byte API with word packing (software only): 846 extra instructions become about 40, at IPC 0.36, so 2,793 becomes about 690 cycles/hash, 4.0x.
- CoreMark and Dhrystone: 0.

**Estimated cost.**

- **Area**: about 2–3k µm² nangate45 (0.3–0.4% of 689k), for a 4-entry write FIFO in the bridge (about 160 flops) and 2-word acceptance in hash_stream. About 200–400 LUTs.
- **fmax risk**: low. Only the bridge and device port change, and they are off the core's MEM-stage critical path.
- **Verification**: low–medium. Read-after-posted-write ordering (status reads drain the FIFO first), backpressure when the buffer is full, FIPS/hashlib KATs through sha256chain_bulk and the hash-stream TB.

**Risk.**

A posted write hides a write error from the store. The bridge must report AXI errors through a status bit, not a precise fault. The F2 AFI must be rebuilt to see it.

### 2. Pipelined FPU (initiation interval 1 for add/mul/FMA), so the vector unit streams FP elements

**Evidence.**

- sigil_fpu is an FSM over shared stage registers. The header comment explains it was not pipelined because the scalar core never has a second op in flight. The vector unit does have more elements in flight, but serializes them through done/ack.
- vfmacc costs 8 cycles per element: dgemm vec = 4 x (1024 x (8x32+4) + 32 x 36) = 1,069,568, exactly stk_vec. fir: 4 x (128 x 1028 + 8 x 132) = 530,560, exactly.
- vec share of cycles: dgemm 68.5%, sgemm 68.4%, fir 71.0%, ddot 58.1%, saxpy 46.4%, daxpy 45.8%.
- The multiplier runs once, in EX1 (fp_mul_pp) and MUL2 (fp_mul_sum), so II=1 needs only per-stage copies of the registers, not a second multiplier.

**Estimated speedup.**

vfmacc at vl=N goes from 8N+4 to N+4+7 cycles; savings are config-independent.

| Kernel | Arithmetic | Speedup | RVV over C |
|---|---|---|---|
| dgemm and sgemm | 4096 x (256-39) = 888,832 saved; dgemm 1,561,900 to 673,068 | 2.32x | dgemm 1.85x to 4.29x |
| fir_f32 | 512 x 889 = 455,168 saved; 747,633 to 292,465 | 2.56x | 2.56x to 6.55x |
| ddot | 32 x 441 = 14,112 saved | 1.81x | |
| saxpy | 32 x 889 = 28,448 saved | 1.67x | |
| daxpy | 32 x 441 saved | 1.64x | |

- sky130: dgemm 1.85x, sgemm 2.00x, fir 2.19x.
- fpga: dgemm 2.30x, fir 2.53x.
- CoreMark, Dhrystone and SHA: 0.

**Estimated cost.**

- **Area**: about 520 extra pipeline flops (copies of ua/ub/uc and control, a second sum_q) plus an in-order tag FIFO of about 7 x 20 bits in vec S2/S3. About 4–8k µm² (0.6–1.2% SoC; fpu is 51,448 today). FPGA about +600 FFs and +300–600 LUTs, no new DSPs (9 today).
- **fmax risk**: low. The stage functions and logic depth are unchanged. Per-stage valids can actually cut the 145-load FPU-enable fanout named in SOC_AREA.
- **Verification**: medium. The fp_eval cross-check on every completion stays. Run Vf ACT 162/162 and the vec_tb random suite. The read-ahead grows from 3 to about 10 elements, which the RVV overlap rules allow; the partial-write retry needs re-checking. div/sqrt stay iterative, and scalar latency is unchanged if mixed op classes drain first.

**Risk.**

Mixed add/FMA streams collide on the shared aligner (EX1 vs ALIGN). Either drain between op classes or route fadd through the FMA path. vfred*osum (ordered) stays serial.

### 3. Vector unit-stride load/store packing: one 64-bit D$ access per 8 bytes instead of one per element

**Evidence.**

- VLS costs 3.0 cycles per element at every SEW: vle8 vl=512 takes 1,537.6; vadd_i32 takes 395.6 per vl=128 instruction.
- stk_vls share: memcpy-e8 99.2%, memset-e8 94.8%, vadd_i32 87.9%, saxpy 52.4%, mac_i16 52.8%, mac_i8 49.4%, idot 47.6%, sgemm 26.0%, fir 28.0%, Dhrystone sdk 19.3% (4,000 vle8/vse8 at vl=56 = 168 cycles each).
- The VRF is already organized as 64-bit words, so an 8-byte-aligned unit-stride access maps word to word.

**Estimated speedup.**

vls cycles x (1 - 1/k), where k is the elements per 64-bit access.

| Region (default/soc) | Speedup | Note |
|---|---|---|
| Dhrystone sdk | 1.203x | 672,000 x 7/8 = 588,000 saved; 0.327 to 0.393 DMIPS/MHz, above scalar's 0.371 |
| memcpy RVV-e8 | 7.57x | 0.33x to 2.53x of C |
| memset RVV-e8 | 5.85x | |
| vadd_i32 | 1.78x | 1.81x to 3.22x of C |
| mac_i8 | 1.76x | |
| mac_i16 | 1.66x | |
| saxpy | 1.35x | |
| idot | 1.31x | |
| sgemm | 1.15x | |
| fir | 1.16x | |
| e64 kernels | 1.0x | |

- fpga config: Dhrystone sdk 1.236x, memset-e8 6.25x. This removes the +1 cycle per stored element that VRF_OREG adds.
- sky130: Dhrystone sdk 1.17x, mac_i8 2.01x.
- Combined with #2: sgemm 3.32x, fir 3.98x. Combined with #4: mac_i8 4.17x.

**Estimated cost.**

- **Area**: an aligned fast path with element-serial fallback for misaligned or non-cacheable addresses. About 2–4k µm² (0.3–0.6%), about 300–600 LUTs.
- **fmax risk**: medium. It lives in the MEM-stage VLS sequencer, and the VRF-to-D$ and MEM-stage paths are the FPGA critical family (43–68 levels). Compute the pack decision in the registered RD/VLS_RW cycle.
- **Verification**: medium. Vls ACT 1051 tests. Check vstart on faults (a page boundary never splits an aligned 8-byte word), mask byte-enables, and fault-only-first.

**Risk.**

Masked-off elements in an accessed word are read but not written, so restrict this to cacheable RAM. A zero-cost alternative for Dhrystone only is an SDK/GCC flag that avoids e8 struct-copy vectorization, giving back scalar's 0.371.

### 4. Hash DMA: a bus-master stream from RAM into sigil_hash_stream, plus SHA-256 as a hash_stream mode with hardware padding

**Evidence.**

- Even with #1, PIO peaks near 0.6–0.9 B/cycle, while the engines can take 1.6 B/cycle (SHA-512: 128 B per 80 rounds, and the buffer refills during compression) and 5.67 B/cycle (Keccak: 136 B per 24 rounds; the input port of 1 word per cycle limits it to 4 B/cycle).
- Bus busy is 26.9% (soc) and 32.5% (axi), so there is headroom.
- SHA-256 has only the block API: 572 cycles per 64 B = 0.112 B/cycle against an engine rate of 1 B/cycle.

**Estimated speedup.**

- **SHA-512 bulk**: engine-bound at 1.6 B/cycle. 1.6/0.2388 = 6.7x (soc). On axi, refills at 64 B per about 37 cycles = 1.73 B/cycle ≥ 1.6, so 1.6/0.2205 = 7.3x. 64 KiB goes from 274,480 to about 41,000 cycles.
- **SHA3-256 bulk**: 4.0/0.2398 = 16.7x on soc. Bus-bound on axi: 1.73/0.2215 = 7.8x (F2 DDR refills measured +1.5 cycles each).
- **SHA-256 stream mode**: with PIO, 0.239 B/cycle = 2.1x the block API; with DMA, 1 B/cycle = 8.9x the block API and 154x C.
- CoreMark and Dhrystone: 0.

**Estimated cost.**

- **Area**: DMA with address, length, an 8x64 FIFO (about 600 flops), a second master on sigil_soc_fabric (single-master today), and a SHA-256 mode mux in hash_stream. About 6–9k µm² nangate45 (about 1%), about 0.8–1.2k LUTs and 0.8k FFs.
- **fmax risk**: low. It is a separate registered block plus one arbiter input.
- **Verification**: medium-high: a new bus master, arbitration against I$/D$ refills, errors, and coherence. The D$ is write-back, so software must clean the buffer first (FENCE.I's DOP_CLEAN cleans the whole 16 KiB D$, about a few thousand cycles, small next to about 41k cycles for 64 KiB). SDK API changes, KATs.

**Risk.**

Coherence is the main hazard. Without a range clean (Zicbom) or snooping, small messages lose to PIO. Keep PIO for short messages.

### 5. Pipelined vector integer multiply (II=1), ideally by routing it through the M unit's 2-stage 4x33x33 multiplier the way the FPU is already shared

**Evidence.**

- The vector multiply family costs (k+4) per element: vwmul e8 = 5, vwmacc e32 = 6 (radix-2^16 iterative, CORE.md).
- mac_i8 vec = 4 x (16 x 1,284 + 16 x 262 + ...) = 98,980, matching stk_vec (49.7%).
- mac_i16 vec 45.4%; idot_i32 vec 49.2%.

**Estimated speedup.**

Savings = n x ((k+4) x vl - (vl+2)).

| Kernel (default/soc) | Arithmetic | Speedup | RVV over C |
|---|---|---|---|
| mac_i8 | 64 x 1,022 = 65,408 saved; 199,144 to 133,736 | 1.49x | 1.73x to 2.57x |
| mac_i16 | 64 x 510 = 32,640 saved | 1.54x | |
| idot_i32 | 64 x 318 = 20,352 saved | 1.65x | |

- With #3: mac_i8 4.17x (7.2x over C), mac_i16 3.94x, idot 2.72x.
- sky130: about 1.38–1.43x.
- CoreMark, Dhrystone and SHA: 0.

**Estimated cost.**

- **Area**: about neutral. Add stage valids to MUL1/MUL2 and a 2:1 operand mux (about 2–3k µm²), and delete the vector unit's own iterative multiplier, which frees about 4 DSPs on FPGA.
- **fmax risk**: low–medium. The operand mux sits in front of the 16-DSP multiplier.
- **Verification**: medium. Vx ACT 821 (vmul*, vwmul*, vmacc, vsmul) and vec_tb random. The scalar M path keeps its current latency.

**Risk.**

vsmul rounding and saturation and the mulh variants need the post-processing kept in vec S2.

### 6. Non-blocking scalar multiply: MUL leaves EX into a 2-stage side pipe that writes back at WB, with a 1-cycle interlock only for an immediately dependent consumer

**Evidence.**

- CoreMark: 187,920 MUL x 2.0 busy = 375,840 = stk_muldiv 2.6%.
- The micro results mul_dep 4.136 and mul_indep 4.126 (vs ALU 2.028) show that independent multiplies do not overlap today.
- In mixed code the hold overlaps one prefetch, so the real cost is about 1 cycle per MUL.
- Integer C kernels: mac_i8/mac_i16 C stk_muldiv 9.5%, idot C 10.5%.

**Estimated speedup.**

- **CoreMark**: about 1 cycle x 187,920 = 1.3%, so 1.013x. The upper bound is 375,840 = 2.6% (1.027x), within the 5.05% I$-idle cap.
- **After a front-end fix**: the 2-cycle hold is fully exposed and the saving is 1.3–2.6% of a much smaller cycle count.
- **mac_i8 C**: 16,384 to 32,768 of 344,236 cycles, 1.05–1.105x. idot C 1.055–1.117x.
- Dhrystone 0 (2,000 DIVs = 0.2%; the divider is not worth touching). SHA 0.

**Estimated cost.**

- **Area**: under 1–2k µm². It reuses the MUL1/MUL2 registers and adds a scoreboard bit and a WB mux input. About 100–200 LUTs.
- **fmax risk**: low–medium. Keep MUL2's sum out of the EX forward path and use an interlock instead.
- **Verification**: low–medium: RV64M ACT, riscv-tests um, core-test muldiv.

**Risk.**

Small gain today. It is worth bundling with the front-end work, where it doubles in value.

### 7. Non-blocking scalar FP: a scoreboard over the pipelined FPU from #2, with in-order issue and out-of-order FP completion

**Evidence.**

- fmadd holds EX 6 cycles: dgemm C 131,072 x 6 = 786,432 = 27.2% stk_fpu.
- sgemm C 24.3%, ddot C 23.9%, fir/daxpy C 20.5%, saxpy C 18.7%.
- The I$ is idle 20–33% in these regions.
- The loops are 6.1 instructions (about 16 cycles) per FMA, longer than the 7-cycle latency, so even the accumulator chains would hide.

**Estimated speedup.**

About 5 of the 6 hold cycles are hidden per op (one overlaps the prefetch).

| Kernel | Arithmetic | Speedup |
|---|---|---|
| dgemm C | 655,360 saved; 2,886,016 to 2,230,656 | 1.29x |
| sgemm C | | 1.25x |
| ddot C | | 1.25x |
| fir C | | 1.21x |
| daxpy C | | 1.21x |
| saxpy C | | 1.18x |

CoreMark, Dhrystone and SHA: 0. Vectorized code gets more from #2.

**Estimated cost.**

- **Area**: about 2–4k µm² on top of #2 (FP scoreboard, FP RF write-port arbitration with FP loads). About 300 LUTs.
- **fmax risk**: medium. The scoreboard check sits in ID/EX issue.
- **Verification**: high. FP traps are impossible (only fflags), but in-flight FP ops must be killable until they pass the commit point. fflags/fcsr reads must drain the pipe, and fmv/fcvt to integer registers needs integer scoreboard bits. TestFloat, F/D ACT and riscv-tests uf/ud.

**Risk.**

Only useful for scalar FP code that RVV does not cover.

### 8. Vector overlap: back-to-back vector-op issue (hide the +4 S0..S3 overhead), then chaining VLS with vector arithmetic

**Evidence.**

- SHA RVV: 213,131 ops at about 21.75 cycles each, of which N=16 is element work. The other about 5.75 is overhead plus issue.
- Kernels keep vls and vec strictly serial: a vector op never starts while a vector load/store is in MEM, and they share the VRF ports. vec+vls is 95–99%.

**Estimated speedup.**

- **Back-to-back issue**: about 3.75 cycles per op saved. SHA RVV: 213,131 x 3.75 = 799k, so 4,753,403 becomes 3.95M, 1.20x (4,642 to about 3,860 cycles/hash, still 6.7x the accelerator).
- **Chaining**: the upper bound is (vec+vls)/max(vec,vls):

| Kernel | Upper bound |
|---|---|
| mac_i8 | 99.1/49.7 = 1.99x |
| idot | 1.97x |
| saxpy | 1.89x |
| daxpy | 1.88x |
| mac_i16 | 1.86x |
| dgemm | 1.39x |
| fir | 1.39x |

The chaining gain shrinks after #2 and #3, and gives 0 on CoreMark, Dhrystone and scalar SHA.

**Estimated cost.**

- **Back-to-back issue**: about 1–2k µm², medium verification. Release EX after S0 for element-wise ops with vl ≥ 4; reductions, gathers and slides excluded.
- **Chaining**: a second VRF write path (the 3 replicas take every write today), about +40k µm² (+6%), +1–2k LUTs and BRAMs.
- **fmax risk**: medium-high. The VRF port mux sits on the F2 critical-path family.
- **Verification**: high: element-ordering hazards, VRF collision rules, interrupt latency.

**Risk.**

Chaining is a large change. Only the back-to-back part is cheap.

### 9. Dual-core (two sigil_cpu instances on a 2-master fabric, coherent D$)

**Evidence.**

- CoreMark bus busy is 0.0% (default and sky130 soc) and Dhrystone 0.0% (default), so a second core does not contend.
- Private I$s escape the saturated I$ port (94.9% occupancy), which caps every single-core parallelism option at 1.053x.

**Estimated speedup.**

- 2.0x aggregate throughput on independent work (multi-instance CoreMark/Dhrystone: 2 x 1.395 CoreMark/MHz).
- 1.0x single-thread.
- Bulk hashing 1.0x: one shared accelerator.

**Estimated cost.**

- **Area**: +585k µm² nangate45 (+85% of 689k; sigil_cpu incl. L1 macros). A scalar-only second core is about 478k (+69%).
- **FPGA**: +55k LUTs / 15k FFs (fits VU47P: about 134k of 1.30M).
- **fmax risk**: low per core, medium on the shared fabric and arbiter.
- **Verification**: very high: MSI snooping or a shared L2 for the write-back D$ with LR/SC and AMOs, per-hart CLINT msip/mtimecmp, PLIC contexts, multi-hart boot and SBI.

**Risk.**

No single-thread gain, and the headline per-MHz scores do not change.

### 10. In-order dual-issue superscalar

**Evidence.**

- I$ occupancy is 94.9% (CoreMark), 97.8% (Dhrystone) and 98.9% (SHA C).
- Fetch delivers one instruction per 2-cycle access and re-fetches shared RVC words (1.297 fetches per instruction).
- The retire share is only 36.6%.

**Estimated speedup.**

- **Today**: at most 1/(1-0.0505) = 1.053x CoreMark, 1.022x Dhrystone, 1.011x SHA-C (sky130 CoreMark ≤1.146x). Essentially 0 until fetch delivers ≥2 instructions per cycle.
- **After a front-end fix**: the best single-issue case is 54.2% of today's CoreMark cycles. If 30% of instructions pair, retire falls by 0.30 x 36.6 = 11.0 points, from 54.2% to 43.2%, so 1.25x over the fixed single-issue core.

**Estimated cost.**

- **Area**: 2nd ALU, +2R/+1W ports on the flop integer RF (about 7–10k µm²), dual decode/RVC, 64-bit fetch alignment buffer, doubled forwarding and hazard logic. About +40–50k µm² (+6–7%), +6–10k LUTs.
- **fmax risk**: high: wider forwarding muxes in EX and issue logic against #53's 100 MHz push, with the FPGA already at 68-level MEM paths.
- **Verification**: very high (full ACT, riscv-dv, all pairing hazards).

**Risk.**

It has value only after a front-end fix (another lens). Do not start it first.

### 11. Multi-lane vector integer datapath (4 lanes, 256-bit VRF ports)

**Evidence.**

- Integer vector ops cost N+4. SHA RVV spends 89.6% in vec at vl=16, 20 cycles per op.
- The kernels' vec share is mostly FP, multiply or VLS, which extra integer lanes do not speed up.

**Estimated speedup.**

- **SHA RVV**: 16/4+4 = 8 vs 20 cycles per op, so 213,131 x 12 = 2,557,572 saved; 4,753,403 to 2,195,831, 2.16x (4,642 to 2,144 cycles/hash, still 3.7x the accelerator's 572).
- vadd_i32: 32 x 96 = 3,072 saved, 1.08x. Other kernels ≤1.05x until #2/#3/#5 land.
- 4 FP lanes after #2: dgemm only 1.18x more, for about +120k µm².

**Estimated cost.**

- **Area**: 3 more S2 integer lanes, extract/insert muxes, and a VRF reorganized to 3 x 64x256 or banked. About +45–60k µm² (+7–9%), +10–20k LUTs.
- **fmax risk**: high. The VRF port to D$ and result path is the F2 critical path (43 levels at 62.5 MHz).
- **Verification**: high: Vx/Vls ACT and vec_tb with tails and masks per lane.

**Risk.**

Poor value: the main beneficiary, SHA, already has an accelerator 8x faster than RVV.

### 12. Fine-grained multithreading (2 hardware threads, barrel interleave)

**Evidence.**

- Both threads would share the I$ port, which is already 94.9% busy on CoreMark: 6,806,626 accesses x 2 cycles = 13.6M of 14.3M cycles.
- The stalls FGMT could hide (dc_lat 9.5, branch 4.8, muldiv 2.6, loaduse 0.7) already overlap the fetch gap.

**Estimated speedup.**

- **Today**: at most 1.053x aggregate throughput on CoreMark, 1.022x on Dhrystone. Single-thread 1.0x or worse.
- **After a front-end fix**: at most 1/0.675 = 1.48x aggregate in the limit, about 1.2x realistic.

**Estimated cost.**

- **Area**: duplicate integer and FP RFs (about 20k µm² each), most CSR state including H (part of csr's 57k, about +45k), VRF (about +45k if V per thread), and thread-tagged TLB/PC. About +150k µm² (+22%), +15–20k LUTs.
- **fmax risk**: medium-high: thread-select muxes on RF/CSR read paths.
- **Verification**: very high (privilege, H extension, interrupts per thread).

**Risk.**

Worst ratio of speedup to cost in this lens. Dual-core gives 2x throughput for about 4x the area with simpler semantics.
