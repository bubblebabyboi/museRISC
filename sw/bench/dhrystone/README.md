# Dhrystone 2.1

Reinhold P. Weicker's Dhrystone, C version 2.1 (May 1988), ported to the
Sigil SDK for the performance harness (`make -C sim perf
BENCHES=dhrystone`, [`docs/PERFORMANCE.md`](../../../docs/PERFORMANCE.md)).

## Source

The source is netlib's [`benchmark/dhry-c`](https://netlib.org/benchmark/dhry-c),
a shell archive with sha256
`038a7e9169787125c3451a6c941f3aca5db2d2f3863871afcdce154ef17f4e3e`,
fetched 2026-10-22. The files were extracted from the archive by
parsing it, without running it.

| File | sha256 of the netlib original | Here |
|---|---|---|
| `dhry.h` | `6593c6e4e8fe3a483925b2fb6e100d9e65451633da5f519cc40ba49b93859010` | unchanged |
| `dhry_2.c` | `7954383013caead70e8283375b249ecbaa1aaf092b526acbcac3f187a015c108` | unchanged |
| `dhry_1.c` | `442e47760cd43c1e6d87cfc0c03134101d97110d417e11a29b5ed42c0eb4767b` | port hunks only, all inside `#ifdef SIGIL_PORT` |

The port changes to `dhry_1.c` are:

1. The number of runs is `SIGIL_DHRY_RUNS` (= `BENCH_ITERATIONS`)
   instead of `scanf`.
2. `sigil_perf_begin()` comes right after the original *Start timer*
   block, and `sigil_dhry_perf = sigil_perf_end()` right before the
   *Stop timer* block. These calls delimit the measured region: exactly
   the `Number_Of_Runs` loop.
3. The wall-clock arithmetic and `%f` printout at the end are replaced
   by `sigil_dhry_finish(...)`. It checks **every** final value that
   `dhry_1.c` prints against its "should be" value: the globals, both
   records (including `Next_Ptr_Glob->Ptr_Comp == Ptr_Glob->Ptr_Comp`),
   the locals and the strings. It then prints the hardware-counter
   summary and `DHRYSTONE CHECK OK runs=<n>`, and passes the test. Any
   mismatch fails it.

Port glue, outside the measured region except `strcpy`:

- `port/stdio.h` is found first through `-Iport`. It maps `printf` to
  the SDK's `sigil_printf`.
- `sigil_port.c` provides `malloc` (the SDK bump allocator), `strcpy`
  (a byte loop, like the SDK's `strcmp`), a `time()` stub, and
  `sigil_dhry_finish`.

## Build

The flags are those of `sw/sdk/sdk.mk` (GCC, `-O2 -mstrict-align
-mcmodel=medany -ffreestanding -fno-common -ffunction-sections
-fdata-sections`, `-std=gnu11`) plus, from this directory's `Makefile`:

- `-fno-inline`: the ground rules ("no procedure merging", `RATIONALE`
  §5);
- `-DSIGIL_PORT -DTIME -DSIGIL_DHRY_RUNS=<n> -Iport`;
- `-Wno-implicit-int -Wno-implicit-function-declaration
  -Wno-return-type -Wno-pointer-to-int-cast` for the 1988 K&R C, which
  GCC 14+ otherwise rejects.

`dhry_1.c` and `dhry_2.c` are separate translation units (no LTO), as
the ground rules require. The SDK's `sigil_perf_*` helpers are
`always_inline`, so the region edges have no calls under `-fno-inline`.

## Variants (`bench.json`)

- **`scalar`** is the DMIPS/MHz headline:
  `SIGIL_MARCH=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh`,
  the SDK ISA without V.
- **`sdk`** uses the SDK default `-march` (with V). GCC's RISC-V
  backend expands the 56-byte record assignment in `Proc_1`
  (`structassign`) into a `vsetvli/vle8.v/vse8.v` loop, and SLP
  vectorizes two stores in `Proc_8`. On this core's element-serial
  vector load/store unit that costs about 19% of the cycles (see the
  evidence). It is kept as a measured case, not as the headline.

DMIPS/MHz = runs / cycles × 10^6 / 1757 (the VAX 11/780 rate).
