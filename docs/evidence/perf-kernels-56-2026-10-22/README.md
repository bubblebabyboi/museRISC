# #56 kernels: C vs RVV, default configuration (2026-10-22)

Thirteen vector/FP kernels from [`sw/bench/kernels`](../../../sw/bench/kernels/README.md),
each run as portable C and as RVV 1.0 intrinsics, and each checked bit
for bit against a scalar reference whose output is itself checked
against a host-computed known answer. Method:
[`docs/PERFORMANCE.md`](../../PERFORMANCE.md).

- **Design.** main `eeaa332` RTL plus the harness's simulation-only
  counters (`rtl/` tree `89b98cb227c6`, the tree measured in
  [`perf-dhrystone-56-2026-10-22`](../perf-dhrystone-56-2026-10-22/report.md),
  whose synthesis view is byte-identical to `eeaa332`). Measured before
  any #53 pipelining.
- **Commit.** `7ea3e51` on branch `56-perf-kernels` (base
  `56-perf-harness` `d2b3df4`). Later commits change only the fault
  self-test script, documentation and evidence; the benchmark sources
  and images are unchanged.
- **Run.** `run-commands.sh` on sigil-verify (c7i.8xlarge, Ubuntu 24.04):
  `make -C sim perf BENCHES=kernels CONFIG=default MEM="soc axi"
  REPEAT=2 JOBS=8`. Results written 2026-10-22T10:24:31Z; Verilator
  5.048, riscv64-unknown-elf-gcc 16.1.0 (g6afcc4f6d), GNU binutils
  2.47, Python 3.12.3. Each simulation took 124–232 s.
- **Memory models.** `soc`: `soc_rtl_tb`, 1-cycle first-beat latency.
  `axi`: `fpga_top_tb` through the AXI4 bridge, 24-cycle latency.
- **Images** (`results.json` `images`): `kernels-scalar` sha256
  `afc14632…`, `kernels-autovec` `44822b77…`. Four calls of the kernel
  per region (`iterations` = 4) after one warm-up call; cycles/call =
  region cycles / 4.

## Files

| File | Content |
|---|---|
| `report.md`, `results.csv`, `results.json` | the harness output: every counter of all 224 region results, metadata, images, build commands |
| `kernels-report.md`, `kernels.csv` | `sw/bench/kernels/kernels_report.py`: per kernel C vs RVV, work per cycle, speedups, a per-region cycle-accounting table, GCC auto-vectorization |
| `runs/` | UART log and `SIGIL_PERF` records of all 8 simulations |
| `build-kernels-*.log` | full compiler commands of both images |
| `disasm-kernels-*.txt` | every kernel function of both images, with an instruction census (vector instructions per function) |
| `kat-check.log` | `kernels_model.py --check`: `kernels_kat.h` matches the host model |
| `repeat-compare.log` | repeat 0 vs 1: records byte-identical |
| `selfcheck-faults.log` | `selfcheck_faults.sh`: 7 injected wrong results, 7 failed runs |
| `alignment-shift2.log`, `alignment-shift2.py` | the code-placement experiment (below) |
| `summary.py`, `summary.log` | every number quoted here, from `results.json` and `alignment-shift2.log` |
| `run-commands.sh`, `postprocess.sh` | the commands that produced these files |

## Validation

- **224/224 region results valid** (28 regions x 2 variants x 2 memory
  models x 2 repeats), 0 failed. Every run exited on `SIGIL TEST PASS
  kernels` and printed all 14 `expect` lines (13 `KERNEL <name> CHECK
  OK ...` and `KERNELS CHECK OK kernels=13 iterations=4`). In every
  record, `cycles` = `mcycle` delta, `instret` = `minstret` delta and the
  accounting sums to `cycles`. The program's own counter window is
  within 193 cycles of the marker window.
- **Self-checks, per kernel:** reference output hash = KAT from the
  exact host model; C and RVV outputs equal the reference bit for bit;
  64-byte guard bands around every output untouched; outputs poisoned
  after the warm-up call, so the measured calls produce them.
- **Exactness:** every FP input is k/16, and the host model proves that
  every FP result is exact in any summation order, so vector reductions
  must match bit for bit (`sw/bench/kernels/README.md`).
- **The checks catch errors:** `selfcheck-faults.log` injects a wrong
  KAT, a short vector store, one wrong C element, a wrong RVV operand,
  a memcpy overrun into the guard band, one wrong reference element
  and a short last strip in a widening MAC. All 7 runs fail.
- **Deterministic:** both repeats give identical records
  (`repeat-compare.log`).
- **Scalar really is scalar:** the build fails if a scalar-ISA object
  contains a vector instruction. `disasm-kernels-scalar.txt` shows 0
  vector instructions in every C and reference function.

## Results: scalar C vs RVV (variant `scalar`, default, soc)

Work units: elem = output element (dot products: element pair), byte,
mac = multiply-accumulate. *Speedup* = C cycles / RVV cycles.

| # | Kernel | Work/call | C cyc/call | C units/cyc | RVV cyc/call | RVV units/cyc | RVV speedup | axi speedup |
|---:|---|---|---:|---:|---:|---:|---:|---:|
| 1 | vadd_i32 | 1,024 elem | 19,520 | 0.0525 | 10,803 | 0.0948 | 1.81x | 1.72x |
| 2 | vadd_i64 | 512 elem | 9,842 | 0.0520 | 5,576 | 0.0918 | 1.77x | 1.68x |
| 3 | daxpy | 512 elem | 14,988 | 0.0342 | 9,022 | 0.0568 | 1.66x | 1.66x |
| 4 | saxpy | 1,024 elem | 32,904 | 0.0311 | 17,734 | 0.0577 | 1.86x | 1.85x |
| 5 | ddot | 512 elem | 12,857 | 0.0398 | 7,904 | 0.0648 | 1.63x | 1.63x |
| 6 | idot_i32 | 1,024 elem | 19,500 | 0.0525 | 12,912 | 0.0793 | 1.51x | 1.51x |
| 7 | memcpy (e64) | 4,096 byte | 8,280 | 0.4947 | 3,302 | 1.2404 | 2.51x | 2.46x |
| | memcpy (e8) | | | | 24,782 | 0.1653 | 0.33x | 0.34x |
| 8 | memset (e64) | 4,096 byte | 5,208 | 0.7865 | 1,760 | 2.3279 | 2.96x | 2.96x |
| | memset (e8) | | | | 12,968 | 0.3159 | 0.40x | 0.40x |
| 9 | dgemm 32x32 | 32,768 mac | 721,504 | 0.0454 | 390,475 | 0.0839 | 1.85x | 1.82x |
| 10 | sgemm 32x32 | 32,768 mac | 809,562 | 0.0405 | 390,794 | 0.0838 | 2.07x | 2.07x |
| 11 | fir_f32 (16 taps) | 16,384 mac | 479,294 | 0.0342 | 186,908 | 0.0877 | 2.56x | 2.56x |
| 12 | mac_i8 | 4,096 mac | 86,059 | 0.0476 | 49,786 | 0.0823 | 1.73x | 1.73x |
| 13 | mac_i16 | 2,048 mac | 43,052 | 0.0476 | 23,277 | 0.0880 | 1.85x | 1.85x |

The `axi` cycle counts are in `kernels-report.md`. After the warm-up
call the arrays are L1-resident, so the 24-cycle memory adds at most
6.8% to any region (vadd_i64 RVV) and 0–6% to the rest.

## Results: GCC 16 auto-vectorization (variant `autovec`, soc)

The same C built with V at `-O3`; at `-O2` GCC 16 vectorizes only the
FIR inner loop. The census in `disasm-kernels-autovec.txt` shows which
C kernels became vector code: all but the two gemms (i-j-k loop over a
column of B) and memcpy/memset (SDK library calls).

| Kernel | scalar C cyc/call | autovec C cyc/call | autovec speedup | RVV intrinsics speedup |
|---|---:|---:|---:|---:|
| vadd_i32 | 19,520 | 12,610 | 1.55x | 1.81x |
| vadd_i64 | 9,842 | 7,142 | 1.38x | 1.77x |
| daxpy | 14,988 | 10,693 | 1.40x | 1.66x |
| saxpy | 32,904 | 19,708 | 1.67x | 1.86x |
| ddot | 12,857 | 12,911 | 1.00x | 1.63x |
| idot_i32 | 19,500 | 15,714 | 1.24x | 1.51x |
| fir_f32 | 479,294 | 373,820 | 1.28x | 2.56x |
| mac_i8 | 86,059 | 61,559 | 1.40x | 1.73x |
| mac_i16 | 43,052 | 25,970 | 1.66x | 1.85x |

The FP dot product and the FIR gain little because GCC keeps IEEE
order: `vfmul` plus an ordered `vfredosum` per strip (FIR: per
output). The RVV regions run the same code at the same addresses in
both images. Their cycles differ by up to 0.7%, from the D$ state the
preceding C region leaves.

## Code placement: a 2-byte shift moves scalar C by -24% to +26%

`alignment-shift2.log` reruns the `scalar` image (byte-identical to the
harness image) and a copy whose C kernels are shifted by one 2-byte
`c.nop` at entry (`KERNELS_C_EXTRA=-fpatchable-function-entry=1`).
Both runs passed every check.

| C region | 64-byte aligned (measured above) | shifted 2 bytes | shifted / aligned |
|---|---:|---:|---:|
| vadd_i32 | 19,520 | 21,568 | 1.105 |
| daxpy | 14,988 | 12,938 | 0.863 |
| saxpy | 32,904 | 25,734 | 0.782 |
| ddot | 12,857 | 10,811 | 0.841 |
| dgemm | 721,504 | 911,712 | 1.264 |
| sgemm | 809,562 | 912,218 | 1.127 |
| fir_f32 | 479,294 | 362,562 | 0.756 |
| mac_i8 | 86,059 | 98,347 | 1.143 |

The cause is `stk_fetch_straddle`: a 32-bit instruction that straddles
a 4-byte fetch word costs a second fetch. Examples: saxpy C is 15.6% of
cycles at the aligned placement and 0.0% shifted; dgemm C is 0.6% and
10.8%. Two consequences:

- **The kernels are 64-byte aligned** (`KERNEL_FN`). A kernel's
  numbers then depend only on its own code. Without the alignment, any
  change to the size of the code linked before it (`main.c`, the SDK)
  could shift it like this.
- **Read scalar C numbers with a +-25% placement band.** Against the
  better of the two placements, the RVV speedup is 1.43x (daxpy),
  1.45x (saxpy), 1.37x (ddot) and 1.94x (fir_f32); the others are
  unchanged (`summary.log`). The RVV loops straddle little (at most
  1.1% of cycles).

## Where the cycles go

Per-region accounting is in `kernels-report.md`. Numbers below are
from `summary.log`.

- **Vector loads/stores cost about 3 cycles per element**, whatever the
  element width: `stk_vls` / D$ accesses is 2.91–3.12 in every RVV region
  (soc). `docs/CORE.md` quotes 2 cycles per active element for the MEM
  sequencer; with the D$ in the loop it is about 3 (not broken down
  further here). So:
  - e64 memcpy/memset move 8 bytes per access and beat the scalar SDK
    loops by 2.5x and 3.0x;
  - e8 moves one byte per access and is 2.5–3x slower than scalar
    (memcpy e8: 24,782 cycles for 4 KiB = 3.0 cycles per byte access).
    This is the mechanism behind Dhrystone's `sdk` slowdown.
- **FP vector arithmetic is 8 cycles per element.** `vfmacc` takes
  8N + 4 cycles (the 7-cycle FMA plus 1). `vec_busy` matches this
  exactly: dgemm/sgemm RVV 1,069,568 = 4 x 32 x (32 x (8 x 32 + 4) + 36);
  daxpy RVV 16,512 = 4 x 8 x (8 x 64 + 4). With about 3 cycles per
  vector load/store element on top, the FP kernels reach 0.06 (axpy:
  two loads and a store per FMA) to 0.09 (gemm, FIR: one load per FMA)
  MAC/cycle, for fp32 and fp64 alike.
- **Integer vector ops:** `vadd` takes N + 4 cycles. The widening
  multiplies at e8/e16 take 5N + 4 (`vwmul`, `vwmacc`) and `vwredsum`
  takes N + 6. `vec_busy` matches: vadd_i32 RVV 4,224, mac_i16 RVV
  42,316, mac_i8 RVV 98,980. That puts mac_i8/mac_i16 at 0.082–0.088
  MAC/cycle.
- **Scalar C is front-end bound.** The fetch categories take 30–56% of
  cycles. Each scalar FMA holds EX for 6 extra cycles (7-cycle latency;
  `stk_fpu` / `ret_fp` = 5.99 in the axpy and ddot loops). The C IPC is
  0.22–0.42.
- **The speedup comes from instruction count, not datapath width.** The
  RVV regions retire 0.6–3.9% as many instructions as C. The
  element-serial unit does at most one element per cycle, so the RVV
  speedup stays between 1.5x and 3x.
