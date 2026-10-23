# #56 analysis: memory hierarchy and load/store unit

Recorded as written on 2026-10-22, before reconciliation. `docs/PERFORMANCE.md` sections 12-14 reconcile the three analyses and drop the claims the counters do not support; where this file and PERFORMANCE.md differ, PERFORMANCE.md is the result.

## Where the cycles go

Lens: memory hierarchy and LSU. Sources, read-only: branch 56-perf-harness at de21e4b, docs/evidence/perf-baseline-56-2026-10-22/ ({default,sky130,fpga}/results.csv and headline.md), perf-f2-56-2026-10-22/README.md, docs/SOC_AREA.md, docs/evidence/fpga-f0-2026-10-21/impl_util_hier.rpt, and the RTL files rtl/core/sigil_icache.sv, sigil_dcache.sv and sigil_core.sv (VLS sequencer at about L1232-1460). I read the #53 plan without checking anything out (git show origin/53-mem-stage-pipeline:docs/FPGA_TIMING_53.md). I ran no new simulations and changed nothing in the repo.

HEADLINE: In default/fpga, cache misses cost almost nothing on the headline benchmarks.
- CoreMark scalar: 39 I$ + 11 D$ misses = 1,494 of 14,337,806 cycles on axi.
- Dhrystone: 13 I$ + 2 D$ misses. SHA chains: 8 + 0.
- On F2 hardware, 1000-iteration CoreMark is within 0.0002% of the 1-cycle soc memory model.
Nearly all of the memory-side cost is L1 hit bandwidth and hit latency.

1) I$ HIT BANDWIDTH (largest bucket in the suite)
- The I$ is blocking and unpipelined: S_IDLE accepts, S_LOOKUP answers. It returns one aligned 32-bit word per 2 cycles (3 with SRAM_OREG).
- The core keeps one fetch in flight and has no fetch buffer. Every instruction re-reads the I$, including the second RVC parcel of the word it just read: micro_pipe alu32_indep = 2.029 cycles/instr, alu32_straddle = 4.045.
- I$ port busy (2 x ic_access / cycles):
  - CoreMark: 2 x 6,806,626 / 14,337,806 = 94.9%
  - Dhrystone: 2 x 1,502,031 / 3,070,244 = 97.8%
  - SHA-256 C 98.9%, Zknh 97.4%, accel block 78.3%, bulk accel 72.4%
  - sky130 CoreMark: 3 x 6,699,401 / 23,030,662 = 87.3%
- I$ accesses per retired instruction: CoreMark 1.30, Dhrystone 1.45, SHA C 1.35.
- stk_fetch_lat + stk_fetch_straddle as % of cycles: CoreMark 45.8 (40.4 + 5.4), Dhrystone scalar 49.5, SHA C 57.3, Zknh 51.6, accel block 36.7, bulk accel 30.2, scalar C kernels 29-56. sky130: CoreMark 63.7, SHA C 70.8.

2) D$ HIT LATENCY
- Every load/store holds MEM one extra cycle (two with SRAM_OREG). stk_dc_lat equals dc_load + dc_store exactly:
  - CoreMark 1,365,092 = 1,082,027 + 283,065 = 9.5% of cycles
  - Dhrystone 390,006 = 12.7%; SHA C 4.7%; Zknh 6.9%; C kernels 7-16%
  - sky130: 2 cycles per access = 11.9-14.8%
- In default only about 0.5 cycle per access is actually exposed: the frozen MEM cycle overlaps the 2-cycle fetch gap (ld_indep and st both 2.525 vs alu 2.028 cycles/op). In sky130 all 2 cycles are exposed (ld 5.04 vs alu 3.05).
- Dependent load-to-load (ld_dep) is 3.0 cycles (5.0 sky130). Load-use pairs are fetch-bound today: ld_use1 = 4.02 = 2 instructions x 2 cycles.

3) VECTOR LS PORT
- The VLS sequencer moves one element per D$ access at 3 cycles (VLS_RD + D$ accept + lookup), 4 for stores with VRF_OREG. stk_vls per access is 2.91-3.12 on every RVV kernel.
- Dhrystone sdk: GCC copies the 56-byte struct with one vle8/vse8 pair per run (ret_vls 4,000; 224,000 element accesses). That is 672,000 cycles = 19.3% (fpga 784,000 = 21.8%), the whole sdk-vs-scalar gap (3,482,242 vs 3,070,244).
- RVV kernels: vls is 26-99% of cycles.
  - memcpy RVV-e8: 98,333 of 99,129 cycles, hence 0.33x of C
  - memset RVV-e8: 49,152 of 51,872, hence 0.40x of C
  - vadd_i32 87.9%, mac_i8 49.4%, dgemm 27.0%
- SHA RVV x16 is bound by vector arithmetic (stk_vec 89.6%); vls is 2.1%.

4) UNCACHED I/O TO THE CRYPTO ENGINE
- Each uncached access costs 5.0 cycles (dc_unc_cyc / dc_unc = 158,720 / 31,744 = 1 dc_lat + 4 io).
- sigil_sha256_block makes 31 uncached accesses per hash (16 DIN + 1 CTRL stores; 8 DOUT + about 6 status loads). That is about 155 of 572.1 cycles.
- io share: byte API 4.4%, SHA-512 chain 6.5%, SHA3 chain 5.8%.
- Bulk SHA-512/SHA3 feed loop (lw from the buffer + sw HDATA): 16.75 cycles per 4-byte word on soc = retire 4.06 + fetch_lat 5.06 + branch 1.0 + dc_lat 2.0 + io 4.0 + dc_miss 0.61 (2.0 on axi). Result: 0.2388 / 0.2205 bytes/cycle.

5) MISSES, WHERE THEY DO MATTER
- Bulk accel: dc_miss 3.7% soc / 11.0% axi (894 misses at 12.2 vs 37.7 cycles each).
- Kernels on axi: at most 2.5% of cycles (vadd_i32 RVV is 5.6% slower on axi than soc, including dirty misses at 75 cycles).
- micro_dmem working sets above 16 KiB: 14.1 soc / 39.1 axi / 40.6 F2 cycles per dependent load. stream_ld 4.26 / 7.39 / 7.63; stream_st 6.23 / 13.00 / 11.95.
- micro_imem code above 8 KiB: 2.47-2.61 (soc) and 3.51-3.98 (axi) cycles/instr, vs 2.03.
- Write-backs are serialised before the refill (WB_RD 9 + WB_BUS 8 + wait for B). They add 15.8 cycles/line on soc and 44.9 on axi (stream_st vs stream_ld), and about 10 fewer on F2.

SKY130
- The SRAM_OREG cycle on every I$ access causes most of the 1.58-1.85x scalar slowdown (CoreMark fetch_lat 40.4% -> 60.6%).
- The 4 KiB direct-mapped D$ adds conflict misses only to Dhrystone: 8,004 misses + 6,004 write-backs over 2000 runs (default: 2 + 1). That is 4.0% soc / 10.7% axi; a dirty miss costs 27.3 / 77.0 cycles.
- It adds capacity misses to kernels above 4 KiB (dgemm C on axi: 55.6% stk_dc_miss).
- I$ misses (CoreMark 1,187) cost 0.1-0.2%.

FPGA (VRF_OREG)
- Scalar code is identical to default.
- Vector stores take +1 cycle per element (VLS_RW): memset RVV 2.99 -> 3.99 cycles/access; Dhrystone sdk +112,000 cycles.

F2 / DDR4
- The axi model is a close stand-in: refills +1.5 cycles, write-backs about -10.
- A dependent miss is 40.6 cycles, 2.9x the soc model. About 26.5 of those cycles (~424 ns at 62.5 MHz) are DDR/interconnect time fixed in ns, so at 100 MHz a miss becomes about 54 cycles. Only miss-bound code notices.
- Bus busy is at most 32.5% (bulk accel on axi) with one line in flight, so the core is latency-bound, not bandwidth-bound.

CONSEQUENCES FOR ORDERING
- Today half of the D$ hit cycle hides behind the fetch gap. D$/LSU upgrades are therefore worth about twice as much once I$ bandwidth is fixed.
- #53 is the right base for candidates 1 and 2. Its D-TLB lookup in EX (mt_q), dedicated AGU, speculative array reads and fetch page register (it_q) cost no cycles on bare metal.
- Each L1 way is 64 sets x 64 B = 4 KiB = one page, so the I$/D$ index bits [11:3] are untranslated (VIPT-safe).

## Upgrade candidates

### 1. I$ fetch bandwidth: return the full 64-bit SRAM word from the I$ and add a 2 x 8 B fetch buffer with next-block prefetch (I$ state machine unchanged; option 1b also pipelines the I$)

**Evidence.**

- I$ port busy: 94.9% CoreMark, 97.8% Dhrystone, 98.9% SHA C, 97.4% Zknh (2 x ic_access / cycles).
- stk_fetch_lat + stk_fetch_straddle: 45.8% CoreMark, 49.5% Dhrystone, 57.3% SHA C, 51.6% Zknh.
- 1.30 I$ accesses per instruction on CoreMark (6,806,626 / 5,246,413). RVC is 51.4% of CoreMark and 73.7% of Dhrystone instructions.
- The SRAM already reads 64 bits per access; the I$ discards half with r_addr_q[2].
- Average instruction size: CoreMark (2 x 2,695,749 + 4 x 2,550,664) / 5,246,413 = 2.97 B; Dhrystone 2.53 B; SHA C 3.25 B; Zknh 2.90 B. All are below the 4 B/cycle that one 8-byte access every 2 cycles supplies.
- micro_pipe: alu32 2.03 cycles/instr, straddle 4.05, taken branch 4.03.

**Estimated speedup.**

Model of cycles after the change:
  retire
  + 3.5 x redirects (the 3 bubbles of today's 4-cycle taken branch, plus 0.5 for the supply ramp or a busy I$)
  + dc_lat (1 per access, now fully exposed)
  + muldiv
  + new load-use bubbles (0.3 x loads, range 0.2-0.4).
Redirects = br_taken + jal_redir + jalr_redir.

- CoreMark: 5,246,413 + 3.5 x 744,296 + 1,365,092 + 375,840 + 0.3 x 1,082,027 = 9,916,989 vs 14,337,806 -> 1.45x (range 1.43-1.52x). CoreMark/MHz 1.395 -> about 2.02.
- Dhrystone: 1,036,022 + 3.5 x 179,999 + 390,006 + 6,000 + 0.3 x 236,002 = 2,132,826 vs 3,070,244 -> 1.44x. DMIPS/MHz 0.371 -> about 0.534.
- SHA-256 C: 3,714,106 + 3.5 x 146,433 + 475,170 + 0.3 x 375,822 = 4,814,539 vs 10,156,268 -> 2.11x (9,918 -> about 4,700 cycles/hash).
- Zknh: 2,731,068 + 512,516 + 475,171 + 113,054 = 3,831,809 vs 6,915,325 -> 1.80x.
- Accelerator block API: 162,844 + 3.5 x 30,721 + 56,332 + 126,976 io + 9,218 = 462,894 vs 585,822 -> 1.27x.
- Bulk SHA-512 accelerator (soc): 66,472 + 3.5 x 16,460 + 32,879 + 65,636 + 10,050 + 4,925 = 237,572 vs 274,480 -> 1.16x.
- RVV-bound regions: under 4% (their fetch_lat is 0.5-4%).
- Option 1b, pipelined I$ (accept a new request in S_LOOKUP on a hit): removes the 0.5-per-redirect term. CoreMark 9,544,841 -> 1.50x; Dhrystone 2,042,826 -> 1.50x.
- sky130 (3-cycle access, so 2.67 B/cycle supply against 2.97 B/instr demand), rough: 5,246,413 x 1.112 + 5 x 744,296 + 2,730,184 + 375,840 + 2 x 0.3 x 1,082,027 + 0.5 x 744,296 = about 13.7M vs 23.03M -> about 1.68x. This is for a respin, not the in-flight GDS.

**Estimated cost.**

Area (nangate45):
- About 260 flops (2 x (64 data + 61 VA tag + valid)) at about 13-15 um2 per flop including its logic. Calibration from SOC_AREA: I$ logic 9,221 - 2 x 2,628 tag = 3,965 um2 for 270 flops; D$ 16,293 um2 for 1,299 flops.
- Total about 3,400-4,000 um2 = +0.5% of the 689,218 um2 SoC. The I$ also loses its 32-bit half-select mux.

FPGA:
- About +300 FF and +400-600 LUT. For scale: I$ today is 481 LUT / 354 FF / 2 BRAM36; the SoC is 78,699 LUT = 6.0% of the VU47P. Negligible.

Fmax risk: moderate.
- #53 family B is the second-worst path family: fetch_va -> I-TLB -> PMP -> fetch_stall -> ireq_valid -> I$ BRAM enable, -3.857 ns, I$ enable at 13.52 ns.
- Sequential prefetch should issue from a registered block address. That takes those requests off family B.
- Redirects still go through fetch_va. Build on #53 step 7 (it_q).
- Do not register the redirect: one more bubble per redirect adds 744K cycles (5%) on CoreMark.
- The 3-source parcel aligner adds about 2 LUT levels before IF/ID, which is not a failing path family.
- Option 1b (accept in S_LOOKUP) puts the tag compare in front of the BRAM enable: high risk at 100 MHz.

Verification: medium-high, about 1-2 engineer-weeks.
- Existing gates: core-test 234, riscv-tests 123, ACT 2577 (C extension), smc_fencei_directed, riscv-dv.
- New directed tests: straddles across block boundaries; fetch faults on a prefetched block deferred until consumed (tval = pc+2 rule); PMP NA4 regions that split a block; FENCE.I, SFENCE and trap flushes of the buffer; uncached boot-ROM fetch.

**Risk.**

- Overlaps the front-end analysis. This is the memory-side half: I$ port bandwidth.
- A taken branch still costs 4 cycles, so a BTB becomes the next frontend lever.
- A prefetch must never fault, trap or touch an I/O region speculatively.
- The fetch-port contract in docs/CORE.md changes from 32 to 64 bits.
- The load-use rate (0.3 x loads) is an assumption. It is ±108K cycles on CoreMark.

### 2. D$ hits without the MEM stall: launch the D$ array read from the EX-stage address unit (index bits [11:3] untranslated, since each way is 4 KiB = one page), compare tags in MEM against the registered PA (#53 mt_q), and add a 1-entry store buffer so a store's data write does not block the next read

**Evidence.**

- stk_dc_lat is exactly 1 cycle per D$ access: CoreMark 1,365,092 = 9.5%; Dhrystone 390,006 = 12.7%; SHA C 475,170 = 4.7%; Zknh 6.9%; C kernels 7-16%.
- Today a hit takes S_IDLE -> S_LOOKUP = 2 cycles, and a store hit writes the data array in S_LOOKUP.
- micro_pipe: ld_indep 2.525 and st 2.525 vs alu 2.028, so only about 0.50 cycle per access is exposed today. ld_dep is 3.016 cycles per dependent load.
- #53 step 5 adds a dedicated EX address unit and moves the D-TLB lookup into EX. Step 6 makes array reads speculative. Both are cycle-neutral, and neither removes this cycle.

**Estimated speedup.**

Alone, on today's fetch-bound pipeline (saves about 0.5 per access; range 0.25-0.75):
- CoreMark: -0.5 x 1,365,092 = -682,546 -> 1.050x (range 1.02-1.08x).
- Dhrystone: -195,003 -> 1.068x.
- SHA C: -237,585 -> 1.024x.
- Zknh: -237,586 -> 1.036x.

After candidate 1 (removes the full 1 per access):
- CoreMark: 9,916,989 - 1,365,092 = 8,551,897 -> 1.16x on top; 1.68x cumulative = about 2.34 CoreMark/MHz.
- Dhrystone: 2,132,826 - 390,006 = 1,742,820 -> 1.22x on top; 1.76x cumulative = about 0.65 DMIPS/MHz.
- SHA C: 1.11x on top (2.34x cumulative). Zknh: 1.14x on top (2.06x cumulative).
- Dependent pointer-chasing loads go from 3 to 2 cycles.

Store buffer alone (no EX launch), stores x 0.5 now / x 1 after candidate 1:
- CoreMark: 283,065 stores -> 1.0% / 2.9%.
- Dhrystone: 154,004 stores -> 2.5% / 7.2%.

**Estimated cost.**

Area (nangate45):
- Store buffer: about 140 flops (index 9 + way 2 + data 64 + byte enables 8 + 44-bit tag for forwarding + valid), about 1,800 um2.
- Forward/merge mux, compare and control: about 700 um2.
- Total about 2,500 um2 = +0.4% (D$ logic today is 26,805 um2).

FPGA: about +150 FF and +300 LUT (D$ today is 2,883 LUT / 1,477 FF / 4 BRAM36).

Fmax risk: moderate-high, possibly a net gain.
- Today the D$ BRAM enables and request registers sit in #53 family A (-4.093 ns, 1,972 endpoints) behind MEM translation and PMP.
- Launching the read from the #53 EX address unit (about 1.8 ns: operand copy 1.0 + adder 0.8, in parallel with the TLB lookup) with step 6's speculative reads takes them out of family A.
- The MEM path hit -> mem_stall -> global clock enable has the same depth as today's drsp_valid path.
- Forwarding from the store buffer adds about 2 levels on the load-data path.
- Must be built after #53 steps 5-6.

Verification: high, about 2-3 engineer-weeks.
- Cases: store-to-load forwarding; AMO/LR/SC; page-table walker reads of PTEs that sit in the store buffer (drain before a walk); FENCE.I clean must drain the buffer; VLS and walker sharing the port; buffer cacheable stores only; precise traps.
- Tests: dcache_tb, amo_cache_directed, vm_directed, mmio_bypass_directed, ACT, Linux boot.

**Risk.**

- Most of the value depends on candidate 1.
- Merge conflict with #53's MEM-stage work if started before it lands.
- Walker and store-buffer coherence bugs are subtle.

### 3. Vector load/store port efficiency: pack unit-stride vle/vse into one 64-bit D$ access per aligned 8 bytes (VRF word writes already take byte enables), and overlap VLS_RD of element i+1 with VLS_ACC of element i

**Evidence.**

- stk_vls per D$ access is 2.91-3.12 on every RVV kernel (vle8 vl=512 = 1,537.6 cycles); stores take 4 with VRF_OREG.
- Dhrystone sdk: ret_vls 4,000 = one 56-byte vle8/vse8 pair per run = 224,000 element accesses = 672,000 cycles (19.3%). On fpga: 784,000 (21.8%).
- memcpy RVV-e8: vls 98,333 of 99,129 cycles (0.33x of C).
- memset RVV-e8: 49,152 of 51,872 (0.40x of C).
- vadd_i32 87.9%, mac_i8 49.4%, mac_i16 52.8%.
- Every kernel uses unit-stride __riscv_vle/vse only (sw/bench/kernels/kern_rvv.c).

**Estimated speedup.**

Formula: new cycles = cycles - vls x (1 - 1/k), where k = elements per 8 bytes (e8 8, e16 4, e32 2, e64 1).
- Dhrystone sdk: 3,482,242 - 672,000 x 7/8 = 2,894,242 -> 1.20x (0.327 -> 0.393 DMIPS/MHz, above scalar's 0.371).
- Dhrystone sdk, fpga: per run 56x3 + 56x4 = 392 -> 7x3 + 7x4 = 49, saving 686,000 -> 2,908,242 -> 1.24x (0.317 -> 0.392).
- memcpy RVV-e8: 99,129 - 86,041 = 13,088 -> 7.6x (0.33x -> 2.53x of C).
- memset RVV-e8: 51,872 - 43,008 = 8,864 -> 5.9x (0.40x -> 2.35x of C).
- mac_i8: 199,144 - 86,016 -> 1.76x. mac_i16: 93,107 - 36,864 -> 1.66x.
- vadd_i32: 43,212 - 18,991 -> 1.78x. saxpy 1.36x. idot_i32 1.31x. fir_f32 1.16x. sgemm 1.15x.
- e64 kernels: 1.00x.

Overlap of VLS_RD with the previous VLS_ACC (3 -> 2 cycles per access):
- dgemm: 1,561,900 - 421,520/3 = 1,421,393 -> 1.10x.
- memcpy RVV: 13,209 - 12,433/3 = 9,065 -> 1.46x.
- With candidate 2's back-to-back port (1 cycle per access): dgemm 1.22x, memcpy RVV 2.68x.

No gain on scalar CoreMark, scalar Dhrystone or the SHA C/Zknh chains. CoreMark sdk 0.2%; SHA RVV x16 about 1%.

**Estimated cost.**

Area (nangate45):
- Byte rotator (64 x 8:1) about 1,500 um2, plus chunk and byte-enable logic and about 100 flops.
- Total about 2,500-3,000 um2 = +0.4%.

FPGA: about +100 FF and +400-600 LUT.

Fmax risk: moderate.
- #53 family J (D$ read -> align -> VRF write data, -1.033 ns) gains the rotator. Register the D$ word for vector accesses: +1 cycle per access, with 8x fewer accesses for e8.
- The family A address path is unchanged; the address advances by 8 instead of the element width.

Verification: high, about 2 engineer-weeks.
- Cases: masks (v0 -> byte enables); vstart resuming mid-word; fault-only-first trimming at the first faulting element; PMP NA4 regions inside a doubleword (fall back to element mode); misaligned base (chunk bounded by both the memory doubleword and the VRF word).
- Tests: ACT vector, Ara rv64uv, kernels bit-exact, micro_vec.

**Risk.**

- Overlaps the execution-unit analysis (vector).
- Segment, strided and indexed accesses stay element-serial.
- vlm/vsm and whole-register loads/stores could reuse the same path later.

### 4. Posted uncached stores: a 2-entry in-order I/O write buffer in the D$. A store retires once buffered; the buffer drains while cached hits continue, and drains before any uncached load, FENCE, FENCE.I, AMO, refill, WFI or trap

**Evidence.**

- 5.0 cycles per uncached access (158,720 / 31,744): 1 dc_lat + 4 io.
- sigil_sha256_block: 17 of its 31 uncached accesses per hash are stores; io is 124 of 572.1 cycles (21.7%).
- Bulk SHA-512/SHA3 feed loop: 16.75 cycles per 4-byte word, of which io is 4.0 (65,636 / 16,409).
- The SDK relies on HDATA backpressure (the store stalls while the block buffer is full). A posted buffer keeps that, as a stall when the buffer is full.

**Estimated speedup.**

Removes the 4 io cycles of each uncached store whenever the loop body (at least 8 cycles) covers the 5-cycle drain.
- Bulk SHA-512, soc: 274,480 - 65,636 = 208,844 -> 1.31x (0.2388 -> 0.314 B/cycle).
- Bulk SHA-512, axi: 297,276 - 65,636 = 231,640 -> 1.28x (0.2205 -> 0.283).
- Bulk SHA3: 1.32x.
- sigil_sha256_block: 17 x 4 = 68 cycles saved; 572.1 -> about 504 cycles/hash -> 1.13x (about 124K hashes/s at 62.5 MHz).
- Byte API: 2,793 -> about 2,725 -> 1.02x. SHA-512 and SHA3 chains: about 1.03x.
- All other benchmarks: 0.
- With candidate 1 as well: bulk 237,572 - 65,636 = 171,936 -> 1.60x cumulative.

**Estimated cost.**

Area (nangate45): 2 x (56-bit PA + 64 data + 8 byte enables + valid) = about 260 flops = about 3,400 um2 (+0.5%). One entry is about 1,700 um2.

FPGA: about +260 FF and +150 LUT.

Fmax risk: low. The buffer is loaded from the already-registered D$ request registers and drains on the bus side.

Verification: medium.
- Cases: RVWMO I/O ordering and FENCE; CLINT mtimecmp and PLIC claim/complete side effects before WFI or CSR reads; UART TX ordering; HDATA backpressure with a full buffer; bus errors becoming imprecise (#62 mem_err).
- Tests: soc-tests, hash-tests, crypto firmware, Linux boot.

**Risk.**

- I/O store errors become imprecise.
- Drivers that assume a store has completed must use FENCE, so the SDK needs a review.
- Gains are limited to the accelerator paths.

### 5. D$ next-line prefetch into a 1-line (64 B) stream buffer, filled in the background over the idle bus

**Evidence.**

- Misses are near zero on CoreMark, Dhrystone and the SHA chains (11 / 2 / 0 D$ misses).
- Bulk accel: dc_miss 3.7% soc / 11.0% axi (894 misses at 12.2 vs 37.7 cycles each).
- stream_ld: 4.257 soc / 7.388 axi / 7.63 F2 cycles per load, i.e. 34.5 cycles exposed per line on axi.
- Kernels: axi is at most 5.6% slower than soc.
- Bus busy is at most 32.5%, so there is idle bus to prefetch over.
- F2: a refill is about 38.5 cycles at 62.5 MHz; the ~26.5-cycle DDR part is fixed in ns, so a miss is about 54 cycles at 100 MHz.

**Estimated speedup.**

- soc model: about 1.00x (an on-chip refill costs about the same as copying the buffered line in).
- Bulk accel on axi: 33,690 - 10,944 = 22,746 cycles saved -> 297,276 -> 274,530 -> 1.08x (F2 about 1.09x). At 100 MHz: (54 - 12) x 894 = 37.5K of about 312K -> about 1.14x.
- stream_ld on axi: 7.388 -> about 4.26 -> 1.73x.
- RVV vadd kernels on axi: up to about 5%.
- CoreMark, Dhrystone and SHA chains: 0.

**Estimated cost.**

Area (nangate45): about 570 flops (512 data + tag + state), about 7,400 um2 (+1.1%).

FPGA: about +570 FF (or 11 LUTRAMs) and +300 LUT.

Fmax risk: low-moderate. The buffer's tag compare runs in parallel with the way compare in S_LOOKUP.

Verification: medium. Cases: stores to a buffered line (update or invalidate), FENCE.I clean, uncached aliases.

**Risk.**

- No benefit in the soc model or on the headline benchmarks.
- Value grows with core clock on F2.
- Coordinate with the 73-f2-memory-platform branch (another work branch).

### 6. Write-back buffer: on a dirty miss, read the victim into the existing linebuf_q, issue the refill first and write the victim back afterwards

**Evidence.**

- Today a dirty miss runs WB_RD (9) -> WB_BUS (8) -> wait for B (24 in the axi model) -> refill.
- stream_st vs stream_ld: +15.8 cycles/line on soc, +44.9 on axi. F2 is about 10 cycles cheaper per write-back.
- sky130 Dhrystone: 6,004 write-backs.
  - soc: (218,128 - 8,004 x 13) / 6,004 = 19.0 extra cycles per write-back.
  - axi: (616,360 - 8,004 x 38) / 6,004 = 52.0.
- default: Dhrystone has 1-2 write-backs in total.

**Estimated speedup.**

default:
- About 1.00x on every headline region.
- dgemm C on axi: 483 x ~42 = 20K of 2,936,230 -> 1.007x.
- stream_st on axi: about 12.997 -> 7.4 per store.

sky130:
- Dhrystone axi: 6,004 x ~42 = 252K of 5,670,943 -> 1.046x.
- Dhrystone soc: 6,004 x ~9.5 = 57K -> 1.011x.

**Estimated cost.**

Area: linebuf_q (8 x 64 flops) already exists. About +60 flops (victim address and state), about 800 um2 (+0.1%).

FPGA: about +60 FF and +100 LUT.

Fmax risk: low (state machine reorder).

Verification: medium. Cases: a miss or uncached access to the line held in linebuf must wait or forward; CLEAN/FENCE.I; AMO.

**Risk.**

Small payoff outside sky130 and kernels larger than the D$.

### 7. sky130 respin only: remove the 4 KiB direct-mapped D$ conflict misses with a 2-line victim buffer (or 2 x 2 KiB ways)

**Evidence.**

- sky130 Dhrystone: 8,004 D$ misses + 6,004 write-backs over 2000 runs (default: 2 + 1).
- stk_dc_miss: 210,124 (4.0%) soc / 608,356 (10.7%) axi.
- CoreMark has 18 misses.
- chase_rand at 8 KiB misses on every access (17.2 / 42.2 cycles per load).

**Estimated speedup.**

- Dhrystone sky130 soc: 5,272,386 - 210,124 = 5,062,262 -> 1.04x.
- Dhrystone sky130 axi: 5,670,943 - 608,356 -> 1.12x (0.201 -> 0.225 DMIPS/MHz).
- CoreMark: about 1.00x.
- Capacity-bound kernels such as dgemm C (137,875 misses) are not fixed by a victim buffer.

**Estimated cost.**

2-way 4 KiB:
- 4 more macros: 2.914 -> 3.664 mm2 of macro area (+0.75 mm2, +26%).
- The W7 floorplan already fails detail routing at about 2x demand, so this is prohibitive now.

Victim buffer:
- About 1,130 flops at about 54 um2 per flop including logic on sky130 (D$ there: 69,953 um2 / 1,299 flops), about 0.06 mm2.
- About 14,700 um2 on nangate45.

Verification: medium.

**Risk.**

Do not disturb the in-flight GDS. This is next-tapeout material only.

### 8. Not recommended now: larger L1s, non-blocking D$ with MSHRs, HBM instead of DDR4, critical-word-first / wider refills, changing the line size

**Evidence.**

- Headline miss cycles are at most 0.01%: CoreMark 39 + 11 misses, Dhrystone 13 + 2.
- chase_rand hits at 3.08 cycles up to 16 KiB. dgemm C is only 1.7% slower on axi than soc.
- The in-order pipeline freezes MEM on a miss, so hit-under-miss would need scoreboarded loads.
- Bus busy is at most 32.5% with one line in flight: latency-bound.
- The 8-beat transfer is 8 of the 37 cycles of an axi miss.

**Estimated speedup.**

- One more 4 KiB D$ way: about 1.00x on every benchmark here.
- Non-blocking D$/MSHRs: at most the miss share, which is at most 0.01% on the headline benchmarks and 11% on bulk axi (candidate 5 recovers most of that more cheaply).
- HBM: at most 1.00x; its latency is no better than DDR4.
- Critical-word-first: about 8 of 12 (soc) / 37 (axi) cycles per miss. chase_rand_256k 14.1 -> about 6 (soc) and 39.1 -> about 31 (axi); 0 on the headline benchmarks.
- Bigger code (Linux) may justify a larger I$ later: micro_imem above 8 KiB costs 2.47-3.98 cycles/instr. Measure first.

**Estimated cost.**

- One extra D$ way: fakeram45_512x64 17,735 + tag 2,628 = about 20,400 um2 (+3%).
- MSHRs plus scoreboarded loads: a large redesign.
- HBM: platform rework.
- Critical-word-first: WRAP bursts in sigil_mbus_axi4.

**Risk.**

Spends area and verification effort for no measured gain on this suite. If F2 miss latency matters at 100 MHz, the platform lever is shortening the CL DDR path (clock converter + SmartConnect + sh_ddr, about 424 ns), not HBM.
