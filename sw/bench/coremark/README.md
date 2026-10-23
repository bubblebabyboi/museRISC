# CoreMark

EEMBC CoreMark 1.0, ported to the Sigil SDK for the performance harness
(`make -C sim perf BENCHES=coremark`,
[`docs/PERFORMANCE.md`](../../../docs/PERFORMANCE.md)). Metric:
CoreMark/MHz = iterations / cycles × 10^6 over CoreMark's timed region.
Measured numbers are in [`docs/evidence/`](../../../docs/evidence/), not
here.

## Source

The benchmark files are not in this repository. `fetch_coremark.sh`
fetches them on first use (the Makefile calls it; it needs network
once) into the git-ignored `third_party/coremark`, at a pinned commit,
and checks them before anything is built:

- Upstream: <https://github.com/eembc/coremark>, commit
  `b56889a7bd9d5624fbeff2a73ba69878e6a9c146` (2025-05-01). This is the
  newest commit whose benchmark files match upstream's own
  `coremark.md5` (the file `make check` uses). The one later commit,
  `1f483d5`, changes a comment in `coremark.h` without updating
  `coremark.md5`.
- The script checks the sha256 of every file below and, where `md5sum`
  exists, runs upstream's `md5sum -c coremark.md5`. If an existing
  `third_party/coremark` does not match, the script fails and leaves
  it as it is.

| File | sha256 | Here |
|---|---|---|
| `core_list_join.c` | `ca00e4e010ece47d7f040cb92aa50a95345a00d3171b59d088f6b243be06ce7b` | unmodified |
| `core_main.c` | `17884c93c5b94378eb0ff02b4df3725756cf2addb9b8cbcaa6200a4649ff5ca7` | unmodified |
| `core_matrix.c` | `ecdff717b5a5c4907d221a606760e25499899cbf617582c05d40db71c91351e4` | unmodified |
| `core_state.c` | `f4b84bb0a3452c45a4daa664ab502bfdccbd31cb57d93e9ac490c60937717a4e` | unmodified |
| `core_util.c` | `a3fbfcb9bb943b638624b8ece01c5836dd56a96d7bcde2697b248d077447327f` | unmodified |
| `coremark.h` | `29f7eb0f0bdf6002f6c7dccfa4f8f9f32c0b8f6709f6538c2b73221938a9c8f1` | unmodified |
| `coremark.md5` | `dad92861212f8f012e75974e23ea97f7a275a375e0d3bc1d3b216423ba6b6306` | (integrity list) |
| `LICENSE.md` | `9577b9c846f61fd69a0d8ac965998c6450c7d8969f71f0bb4a931b91aebad28a` | (license) |

CoreMark is Apache-2.0 code under EEMBC's CoreMark acceptable-use
agreement (`LICENSE.md` upstream). Only files that EEMBC's run rules
allow a port to change live here: `core_portme.c` and `core_portme.h`.

## Port (`core_portme.c`, `core_portme.h`)

The port follows EEMBC's `barebones` port. It differs in these ways:

- **Types.** The target is LP64, so `ee_ptr_int` is `uintptr_t`; the
  barebones `ee_u32` would fail `check_data_types()`. `CORE_TICKS` is 64
  bits. The other types are the barebones ones, and `_Static_assert`s
  check EEMBC's size rule (run rule 5) at compile time.
- **Timer.** `start_time()` is `sigil_perf_begin()` and `stop_time()` is
  `sigil_perf_end()`. The harness's measured region is therefore
  CoreMark's own timed region: the single `iterate()` call in
  `core_main.c`, plus the call and return of the two timer functions.
  CoreMark's ticks are the `mcycle` delta of that region; this is the
  `Total ticks` line and the program's `SIGIL PERF` line. Seconds are
  ticks / `COREMARK_CLOCK_HZ`, which defaults to the 62.5 MHz clock
  of the F2 B1 build (`docs/FPGA_F2.md`). Only CoreMark's printout uses
  seconds.
- **Seeds.** `SEED_VOLATILE`, as in barebones: performance seeds
  `0,0,0x66` or validation seeds `0x3415,0x3415,0x66`, with
  `TOTAL_DATA_SIZE` 2000 (666 bytes per algorithm). The iteration count
  is `ITERATIONS` = `BENCH_ITERATIONS`. Data is on the stack
  (`MEM_STACK`), which is in RAM, behind the L1 D$.
- **Output.** `ee_printf` passes each conversion to the SDK's
  `sigil_printf` and prints `%f` with `sigil_print_fixed`. It runs only
  outside the timed region.
- **Self-check.** `core_main.c` prints its report and calls
  `portable_fini(&results[0].port)`. `portable_fini` then checks the
  results itself and fails the test (`sigil_fail`) on any mismatch:
  - the seed CRC, which also covers the size;
  - the algorithm mask and the iteration count;
  - `crclist`, `crcmatrix` and `crcstate` against CoreMark's known values
    for the run type (known_id 3 and 4 in `core_main.c`);
  - CoreMark's per-result error count;
  - `crcfinal`, the CRC over all iterations, against a reference table
    for 1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50, 100, 200, 500, 1000 and
    2000 iterations. The reference comes from the same unmodified
    sources built natively for x86-64 with EEMBC's `posix` port (Ubuntu
    GCC 13.3 `-O2`), run with the same seeds. At other counts the
    program says that `crcfinal` was not checked.

  Only if every check passes does it print
  `COREMARK CHECK OK iterations=<n>` (the `bench.json` `expect` line)
  and `SIGIL TEST PASS coremark`. If `main` ever returned early, without
  the region and that line, the harness would reject the run.

## The 10-second rule

EEMBC run rule 1 requires a run of at least 10 s. At the harness's
default of 20 iterations, the timed region is well under a second at
62.5 MHz (the evidence has the exact figure). For a run below 10 s,
`core_main.c` itself prints
`ERROR! Must execute for at least 10 secs for a valid result!` and
`Errors detected`, and it does not print `Correct operation validated`.
These lines are expected in harness runs. They refer only to the time
rule: the program prints a `COREMARK NOTE` line saying so, and the CRC
checks above are complete. CoreMark/MHz from such a run is a simulation
measurement. It is not a reportable CoreMark score.

A 10 s region at 62.5 MHz needs several hundred iterations, which takes
hours of Verilator time per run, too long for the harness. The evidence
has such runs, at 1000 iterations with both seed sets, made with the
harness code and a raised cycle limit. In those runs CoreMark validates
itself and prints its `CoreMark 1.0` line. On F2 hardware, build with
`BENCH_ITERATIONS=1000` or more to get a run that meets the rule. The
`ITER` override of `make perf` does not raise `bench.json`'s
`max_cycles` (2e8), which is enough for about 270 iterations in the
default configuration.

## Build

The flags are the SDK's (`sw/sdk/sdk.mk`): GCC `-O2 -mstrict-align
-mcmodel=medany -mabi=lp64d -std=gnu11 -ffreestanding -fno-common
-ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables
-fno-math-errno`, the same for every file (run rule 4). The program
links with the SDK runtime and `-Wl,--gc-sections`. There is no LTO and
no profile feedback. CoreMark's `Compiler flags` line prints exactly
these code-generation flags; the Makefile takes them from `CFLAGS`.

Make variables, besides the usual `sdk.mk` ones (`OUT`, `RISCV_PREFIX`,
`SIGIL_MARCH`, `OPT`, ...):

| Variable | Default | Meaning |
|---|---|---|
| `BENCH_ITERATIONS` | 20 | CoreMark `ITERATIONS` (the harness passes `bench.json`'s `iterations`) |
| `COREMARK_RUN` | `performance` | `performance` (seeds `0,0,0x66`) or `validation` (`0x3415,0x3415,0x66`) |
| `COREMARK_CLOCK_HZ` | 62500000 | clock for CoreMark's seconds and iterations/s printout |
| `COREMARK_DIR` | `third_party/coremark` | the fetched sources |

## Variants (`bench.json`)

- **`scalar`** is the CoreMark/MHz headline. It uses the performance
  seeds and the SDK ISA without V:
  `-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`.
  This is the same ISA string as Dhrystone's headline.
- **`sdk`** uses the performance seeds and the SDK default `-march`,
  which includes V. GCC's SLP vectorizer turns a few short groups of
  loads and stores into `vsetivli` + `vle32`/`vse32`/`vse16` sequences:
  the state counters in `core_state_transition` and `core_bench_state`,
  and the CRC fields in `iterate`. This core's vector load/store unit
  is element-serial.
- **`validation`** uses the validation seeds and the `scalar` flags. It
  covers EEMBC run rule 2, which requires both seed sets to validate.
  It is a correctness run, not the score.

To report a result, use EEMBC's scaling format, `CoreMark/MHz 1.0 : N /
C / P`, with `C` = `GCC16.1.0` plus the flags above and `P` = data on
the stack in RAM, plus the memory model and the cache configuration of
the run (`docs/PERFORMANCE.md` §4).
