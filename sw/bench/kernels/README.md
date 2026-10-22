# Vector and FP kernels: C vs RVV

Thirteen small compute kernels, each measured as portable C and as RVV
1.0 C intrinsics (Zve64d, VLEN-agnostic code; VLEN 512 on Sigil), and
each checked bit for bit against a scalar reference whose output is
itself checked against a host-computed known answer. Run by the
performance harness ([`docs/PERFORMANCE.md`](../../../docs/PERFORMANCE.md)):

```sh
make -C sim perf BENCHES=kernels [CONFIG=...] [MEM=...] [REPEAT=2]
sw/bench/kernels/kernels_report.py build/perf/run --md kernels.md --csv kernels.csv
```

The harness tabulates every region on its own (cycles, IPC,
cycles/iteration, accounting). Each region in `bench.json` declares its
work per call (`work_per_iteration`, `work_unit`) and, for the RVV
regions, the C region as `baseline`, so `report.md` also has work per
cycle and the RVV speedups. `kernels_report.py` pairs each kernel's
regions into one row per kernel (work from `bench.json`'s `kernels`
list), with the vector-unit shares and the GCC auto-vectorization
comparison across the two variants.

## Kernels

| # | Kernel | Work per call | Data | RVV form |
|---:|---|---|---|---|
| 1 | `vadd_i32` | 1024 elements | `c = a + b`, int32 | `vle32`/`vadd.vv`/`vse32`, e32 m8 |
| 2 | `vadd_i64` | 512 elements | `c = a + b`, int64 | e64 m8 |
| 3 | `daxpy` | 512 elements | `y += a x`, fp64, in place | `vfmacc.vf`, e64 m8 |
| 4 | `saxpy` | 1024 elements | `y += a x`, fp32, in place | `vfmacc.vf`, e32 m8 |
| 5 | `ddot` | 512 element pairs | `sum x y`, fp64 | `vfmacc.vv` into lanes (tu), one `vfredusum` |
| 6 | `idot_i32` | 1024 element pairs | `sum x y`, int32 x int32 -> int64 | `vwmacc.vv` e32 -> e64 (tu), one `vredsum` |
| 7 | `memcpy` | 4096 bytes | 8-byte aligned | RVV: `vle64`/`vse64` e64 m8; RVV-e8: `vle8`/`vse8` e8 m8 |
| 8 | `memset` | 4096 bytes | 8-byte aligned | RVV: `vmv.v.x` + `vse64`; RVV-e8: `vse8` |
| 9 | `dgemm` | 32,768 MACs | `C = A B`, 32 x 32 fp64, row-major | row of C += `a[i][k]` x row k of B (`vfmacc.vf`) |
| 10 | `sgemm` | 32,768 MACs | same, fp32 | same, e32 |
| 11 | `fir_f32` | 16,384 MACs | 1024 outputs x 16 taps, fp32 | a strip of outputs, `vfmacc.vf` per tap |
| 12 | `mac_i8` | 4096 MACs | `sum x y`, int8 x int8 -> int32 | `vwmul.vv` e8 -> e16, `vwredsum` e16 -> e32 per strip |
| 13 | `mac_i16` | 2048 MACs | `sum x y`, int16 x int16 -> int32 | `vwmacc.vv` e16 -> e32 (tu), one `vredsum` |

Every streaming array is 4 KiB, so each kernel's arrays fit the
default 16 KiB D$ (the 32 x 32 fp64 matrices are 8 KiB each). Buffers
are 64-byte aligned with a 64-byte guard band on each side; each
buffer's guard bands hold a byte value of their own, so an overrun that
copies another buffer's guard is caught too.

The C versions ([`kern_c.c`](kern_c.c)) are plain loops, no unrolling
or intrinsics. `memcpy`/`memset` C are the SDK's library routines
(`sw/sdk/lib/runtime.c`: 8-byte words when aligned). The RVV versions
([`kern_rvv.c`](kern_rvv.c)) are plain strip-mined intrinsic loops, LMUL
8 for the widest operand. `mac_i8` reduces each strip with the widening
`vwredsum`: accumulating into int32 lanes with `vwadd.wv` makes GCC 16
copy the accumulator group (`vmv8r.v`) every strip.

## Regions and variants

Region `10*k + i` measures kernel `k` with implementation `i`: 0 = C,
1 = RVV, 2 = RVV-e8 (memcpy and memset only). Each region is one warm-up
call outside the region (caches), then `BENCH_ITERATIONS` calls back to
back (bench.json `iterations` = 4), so the harness's *cycles/iteration*
is cycles per call.

| Variant | C kernels built with | Meaning of the C regions |
|---|---|---|
| `scalar` | `-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh -O2` (no V) | the scalar baseline |
| `autovec` | the SDK `-march` (with V) `-O3` | GCC 16 auto-vectorization of the same C |

`main.c` and `kern_rvv.c` are built by `sdk.mk` with the SDK flags
(`-O2`, with V) in both variants, so the RVV regions run the same code.
At `-O2` GCC 16 auto-vectorizes only the FIR inner loop (an ordered
`vfredosum` per output), so the `autovec` variant uses `-O3`; there it
vectorizes every C kernel except the two gemms (whose i-j-k inner loop
walks a column of B), using `vfredosum` (ordered) for the FP dot
product and the FIR. `memcpy`/`memset` C call the SDK routines, which
are scalar in both variants.

**Code placement.** Every measured kernel starts on a 64-byte boundary
(`KERNEL_FN` in `kernels.h`). On this core a 32-bit instruction that
straddles a 4-byte fetch word costs a second fetch, so shifting a scalar
loop by 2 bytes changes its cycles by up to about 25% either way
([evidence](../../../docs/evidence/perf-kernels-56-2026-10-22/README.md)).
With the alignment, a kernel's numbers depend only on its own code, not
on the size of `main.c` or the SDK. `make KERNELS_C_EXTRA=-fpatchable-function-entry=1`
shifts every C kernel by one `c.nop` to measure the other placement.

The Makefile compiles `kern_c.c` and `ref.c` to objects with their own
flags (`KERNELS_C_MARCH`, `KERNELS_C_OPT`, `KERNELS_C_EXTRA`) and checks that no
scalar-ISA object contains a vector instruction (any mnemonic starting
with `v` fails the build).

## Validation

A run passes only if, for every kernel:

1. the scalar reference ([`ref.c`](ref.c): scalar ISA, `-O1`, no
   vectorization, no loop-to-`memcpy` conversion, no FMA contraction)
   produces output whose FNV-1a 64 hash equals the known answer in
   [`kernels_kat.h`](kernels_kat.h);
2. the C output and the RVV (and RVV-e8) output equal the reference
   bit for bit, and the 64-byte guard bands around every output buffer
   are intact. Each region's output is poisoned (or, for the in-place
   axpy, restored) after the warm-up call, so it is the measured calls
   that produce it.

It then prints `KERNEL <name> CHECK OK <unit>=<n> iterations=<R>` (all
13 are bench.json `expect` lines), the final `KERNELS CHECK OK
kernels=13 iterations=<R>` and passes the test; any mismatch fails it
with the kernel, implementation and first differing byte.

[`selfcheck_faults.sh`](selfcheck_faults.sh) shows that the checks
catch wrong results: it builds seven copies of the benchmark, each with
one injected fault (a wrong KAT, a short vector store, one wrong C
element, a wrong RVV operand, a memcpy overrun into the guard band, one
wrong reference element, a short last strip in a widening MAC), runs
each on `soc_rtl_tb` and requires every run to fail (GNU sed; run on
Linux).

The known answers come from [`kernels_model.py`](kernels_model.py), an
independent host model of the input generator (splitmix64, one stream
per kernel and array) and of every kernel in exact arithmetic (Python
integers and fractions). `kernels_model.py --check` verifies that
`kernels_kat.h` is current.

**Exactness.** Every floating-point input is `k/16` with
`1 <= |k| <= 127`, so every product is a multiple of 1/256. The model
proves, for every FP output, that the sum of the absolute values of
its terms is below 2^24 (binary32) or 2^53 (binary64) in units of
1/256, so every partial sum, in any order, fused or not, is exact.
Vector code that reassociates a reduction (per-lane partial sums, tree
or ordered reductions) must therefore still match the reference bit for
bit, and a check failure always means a wrong result. The in-place axpy
regions compute `y0 + R a x`; exact up to about R = 20,000 calls.
Integer kernels use full-range data where the C type allows (wrapping
sums mod 2^32 / 2^64), which also makes them order-independent.

## Output

Besides the harness's `SIGIL PERF` lines, the program prints one summary
per kernel from the hardware counters (what an F2 run reports):

```text
KERNEL daxpy 512 elem per call: C <cycles> cyc (IPC .., .. elem/cyc) RVV <cycles> cyc (...) speedup RVV <x>x
```

## Files

| File | |
|---|---|
| `main.c` | inputs, buffers, regions, checks, summary |
| `kernels.h` | sizes and prototypes |
| `kern_c.c` | C kernels (measured) |
| `kern_rvv.c` | RVV intrinsic kernels (measured) |
| `ref.c` | scalar reference (not measured) |
| `kernels_kat.h` | known answers, generated by `kernels_model.py` |
| `kernels_model.py` | host model: inputs, exact outputs, KATs |
| `kernels_report.py` | per-kernel table (work/cycle, speedups) from `results.json` |
| `selfcheck_faults.sh` | fault injection: every injected wrong result must fail the run |
| `bench.json` | harness metadata; `kernels` lists each kernel's work per call |
