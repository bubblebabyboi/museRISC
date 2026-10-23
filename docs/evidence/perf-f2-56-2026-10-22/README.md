# #56: the benchmark suite on AWS F2 hardware (2026-10-22)

The #56 benchmark images, byte-identical to the ones the simulation
baselines ran, executed on a real `f2.6xlarge` with the public Sigil AFI
at 62.5 MHz. All 46 runs validated themselves. The hardware cycle counts
match the default-configuration simulation behind the AXI DDR model
(`fpga_top_tb`): 145 of 180 regions agree to within 0.1% and 165 to
within 1%. 178 of the 180 regions retire exactly the simulated
instruction count on every repeat.

| Benchmark | F2 hardware (62.5 MHz) | Simulation, default/axi |
|---|---|---|
| Dhrystone 2.1, scalar `-march` | **0.371 DMIPS/MHz**, 23.17 DMIPS | 0.371 DMIPS/MHz |
| CoreMark 1.0, 1000 iterations, performance seeds | **1.395 CoreMark/MHz, 87.19 CoreMark**, 11.47 s timed region, `Correct operation validated` | 1.395 (soc model, 1000 iterations; axi at 20 iterations) |
| CoreMark 1.0, 1000 iterations, validation seeds | 1.392 CoreMark/MHz, 87.02 CoreMark, `Correct operation validated` | 1.392 |
| SHA-256 chain, cycles/hash | plain C 9,918.4; Zknh 6,753.4; RVV x16 4,642.6; accelerator `sigil_sha256_block` 572.1 (109,250 hashes/s) | identical to 0.1 cycle/hash |
| 64 KiB bulk hashing, accelerator SHA-512 | 0.2195 bytes/cycle, 13.72 MB/s | 0.2205 bytes/cycle |

The CoreMark figures were measured on hardware with a timed region
longer than EEMBC's 10 s minimum, and both seed sets validated. They have
not been submitted to EEMBC.

## Files

| File | What |
|---|---|
| `tables.md` | all summary tables: Dhrystone/CoreMark, SHA, kernels, microbenchmarks, whole-run wall-clock |
| `regions.md` | every region: hardware median/min/max cycles and instret against the simulation (axi and soc) |
| `results.json` | `scripts/f2_validate.py` output: every run's checks, host report and region counters, plus the simulation numbers they are compared with |
| `logs/<image>.r<k>.uart`, `.host` | UART capture (`sigil_host --log`) and `sigil_host` report of each run; `logs/run_f2.log` is the run sequence |
| `logs/smoke/` | one Dhrystone run made before the sweep to check the setup; not in the tables |
| `logs/bins-sha256-check.log`, `SHA256SUMS` | the images' sha256, checked on the instance before the runs |
| `instance-info.txt` | instance, AMI, kernel, CPU, aws-fpga commit, `sigil_host` hashes, `fpga-describe-local-image` |
| `aws-lifecycle.txt` | launch command, hard cap, timeline, termination |
| `scripts/` | `build_images.sh` (sigil-verify), `user-data.sh`, `setup_f2.sh`, `run_f2.sh` (instance), `f2_validate.py`, `f2_report.py` |

## Setup

- **Hardware.** `f2.6xlarge` `i-0fa8f24634bfa912f` (1x VU47P), us-east-1a,
  FPGA Developer AMI `ami-069f868732bb588dc` (1.19.2), Ubuntu 24.04.1,
  Linux 6.8.0-1021-aws, AMD EPYC 7R13.
- **AFI.** `agfi-035116450e0a0d093` / `afi-019aabf5d4a815ae5` (public),
  Small Shell `0x10212415`, CL version `0x00030001`. Clock recipe B1
  gives 62.5 MHz, and `sigil_host` measured 62.500–62.501 MHz (cycle
  counter over host wall time) on all 46 runs.
- **The design in the AFI is the `default` configuration.** The AFI was
  built from `4058108`. Its `rtl/` differs from main `eeaa332`, the #56
  baseline design, in two ways:
  - the `VRF_OREG` option (#53) is missing. It is off in this AFI, since
    the CL synthesis defines only `SYNTHESIS` and `SIGIL_CORE_CLK_KHZ`;
  - a simulation-only assertion in `sigil_mbus_axi4`.

  The hardware therefore runs the design that the harness's `default`
  configuration simulates. The `fpga` configuration (`SIGIL_VRF_OREG`)
  is the next F2 build, not this AFI. The vector regions below confirm
  this (see *Which simulation the hardware matches*). No #53 pipelining
  is involved anywhere.
- **Images.** These are `56-perf-harness` at `8d15410`; no image has
  changed since `662bad7`. They were built on sigil-verify with
  riscv64-unknown-elf-gcc 16.1.0 (`deps/`) and the harness's make
  arguments (`scripts/build_images.sh`), 16 images in all:
  - the 14 images of `perf-suite-56-2026-10-22`. They are byte-identical
    to the `bin_sha256` in its `results.json`;
  - the 2 images of `perf-coremark-56-2026-10-22/long-1000`, CoreMark
    with 1000 iterations and both seed sets. They are byte-identical to
    that `results.json`.

  The images were copied to the instance with ssh and checked with
  `sha256sum -c` there (`logs/bins-sha256-check.log`).
- **Host runtime.** `fpga/host/sigil_host.c` is the same file on main
  `eeaa332` and `56-perf-harness` (sha256 `dd2d1374…`). It was built on
  the instance with GCC 13.3.0 against aws-fpga v2.3.5 (`c34f88e`),
  after `sdk_setup.sh` (`scripts/setup_f2.sh`, the steps of
  `fpga/scripts/f2_playground_setup.sh` without the RISC-V compiler).
- **Runs** (`scripts/run_f2.sh`, 2026-10-22T11:25:40Z to 11:27:43Z):

  ```
  sudo ./host/sigil_host --ignore-mem-err --bin bins/<image>.bin --timeout 60|120 \
       --exit "SIGIL TEST PASS <bench>" --fail "SIGIL TEST FAIL" --log logs/<image>.r<k>.uart
  ```

  Each of the 14 suite images ran 3 times, and each 1000-iteration
  CoreMark image ran twice: 46 runs. `--ignore-mem-err` is the known
  #62 workaround that this AFI requires.

## Validation

All 46 runs are valid (`scripts/f2_validate.py`). The checks are the
harness's (`docs/PERFORMANCE.md` §6), minus the simulation-only counter
records, plus a comparison with the simulation's UART output:

1. `sigil_host` exited 0 on `SIGIL TEST PASS <bench>`. Each program
   prints this only after its own checks pass:
   - CoreMark: CRCs against native references;
   - Dhrystone: final values;
   - kernels: bit-exact reference plus known answers;
   - micro: values computed in C;
   - SHA: FIPS 180-4/202 KATs and Python `hashlib` values.
2. No UART TX overflow. The final `STATUS` was `0x42` (#62 `mem_err`,
   DDR calibrated) or `0x62` (TX bytes still queued after the exit
   marker). No run trapped.
3. Every `expect` line of the bench and variant is present, matched as
   a substring as in `scripts/perf_run.py`.
4. There is exactly one `SIGIL PERF region=<id>` line per declared
   region, and no other region.
5. The UART output is line-for-line the simulation's output of the same
   image (`perf-suite-56-2026-10-22/runs/*.axi-default.r0.log`; for the
   1000-iteration images, `long-1000/runs/*.soc-default.r0.log`).
   - Only numbers on timing lines differ: `SIGIL PERF`, `RESULT`,
     `KERNEL ... cyc`, `MICRO region=`, `DHRYSTONE runs=`, `COREMARK
     ... run:`, and CoreMark's `Total ticks`, `Total time`,
     `Iterations/Sec` and `CoreMark 1.0 :` lines.
   - Every CHECK, KAT, CRC and hash-value line is byte-identical.
   - There is no missing, extra or altered line in 1,726 lines. No byte
     was dropped (#63 did not appear).

**Retired instructions.** 178 of 180 regions retired exactly the
simulation's `minstret` on every repeat, so the hardware executed the
same instruction stream. The two exceptions are the SHA-512 accelerator
regions, whose `sigil_hash` busy-wait loop polls a timing-dependent
number of times:
- `sha256chain` region 5: 1,011,729 against 1,011,732;
- `sha256chain_bulk` region 3: 66,452 or 66,461 against 66,461.

## Results

All metrics come from the program's own `SIGIL PERF` counter window
(`mcycle`/`minstret` deltas). The simulation figures below use the
same window (`hw_cycles` in the harness), so both sides are measured
the same way. The harness's published metrics use the marker window,
which is a few tens of cycles longer; at the precision shown, this
changes no figure. Hardware values are medians of the repeats. Wall-clock
is cycles divided by the measured 62.500 MHz. The full tables, including
kernels, every microbenchmark and whole-run wall-clock, are in
[`tables.md`](tables.md).

| Image | Iterations | HW cycles | HW instret | IPC | HW metric | Sim default/axi | Sim default/soc | Sim fpga/axi | HW vs default/axi | At 62.5 MHz (HW) | Region wall-clock |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| dhrystone-scalar | 2,000 | 3,070,662 | 1,036,012 | 0.337 | **0.371** DMIPS/MHz | 0.371 | 0.371 | 0.371 | +41 cycles | 23.17 DMIPS | 0.049 s |
| dhrystone-sdk | 2,000 | 3,482,584 | 1,022,010 | 0.293 | 0.327 DMIPS/MHz | 0.327 | 0.327 | 0.317 | −11 cycles | 20.43 DMIPS | 0.056 s |
| coremark-scalar | 20 | 14,339,138 | 5,246,400 | 0.366 | 1.395 CoreMark/MHz | 1.395 | 1.395 | 1.395 | +111 cycles | 87.17 CoreMark | 0.229 s |
| coremark-sdk | 20 | 14,573,818 | 5,238,325 | 0.359 | 1.372 CoreMark/MHz | 1.372 | 1.372 | 1.372 | +93 cycles | 85.77 CoreMark | 0.233 s |
| coremark-validation | 20 | 14,366,107 | 5,253,766 | 0.366 | 1.392 CoreMark/MHz | 1.392 | 1.392 | 1.392 | +99 cycles | 87.01 CoreMark | 0.230 s |
| **coremark-scalar-1000** | 1,000 | 716,835,385 | 262,309,875 | 0.366 | **1.395** CoreMark/MHz | | 1.395 | | +1,336 cycles vs soc | **87.19 CoreMark** | **11.469 s** |
| coremark-validation-1000 | 1,000 | 718,246,870 | 262,700,080 | 0.366 | 1.392 CoreMark/MHz | | 1.392 | | +1,373 cycles vs soc | 87.02 CoreMark | 11.492 s |

On hardware, CoreMark printed `CoreMark 1.0 : 87.188777 / GCC16.1.0
-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
-mabi=lp64d -mcmodel=medany -mstrict-align -O2 ... / STACK`, together
with `Correct operation validated`, `crcfinal 0xd340` (validation seeds:
`0x26c2`, `Correct operation validated`). Its seconds are `mcycle` /
62.5 MHz, and the host's measured clock (62.500 MHz) confirms the 11.47 s
in real time: the whole run took 11.474 s of host wall-clock.

SHA-256 chain, 1024 hashes per region:

| Implementation | HW cycles/hash | Sim default/axi | Sim fpga/axi | HW hashes/s at 62.5 MHz |
|---|---:|---:|---:|---:|
| plain C | 9,918.4 | 9,918.4 | 9,918.4 | 6,301 |
| C + Zknh | 6,753.4 | 6,753.4 | 6,753.4 | 9,255 |
| RVV x16 (aggregate over 16 chains) | 4,642.6 | 4,642.6 | 4,855.2 | 13,462 |
| accelerator, `sigil_sha256_block` | 572.1 | 572.1 | 572.1 | 109,250 |
| accelerator, `sigil_sha256` | 2,793.3 | 2,793.3 | 2,793.3 | 22,375 |
| accelerator SHA-512 chain (64 B), `sigil_hash` | 2,472.3 | 2,472.2 | 2,472.2 | 25,280 |
| accelerator SHA3-256 chain, `sigil_hash` | 1,370.1 | 1,370.1 | 1,370.1 | 45,616 |

64 KiB bulk hashing on hardware:

| Implementation | bytes/cycle | MB/s at 62.5 MHz | Cycles vs axi model |
|---|---:|---:|---:|
| SHA-256 plain C | 0.0065 | 0.40 | −0.01% |
| SHA-256 Zknh | 0.0095 | 0.59 | +0.02% |
| SHA-256 RVV x16 | 0.0130 | 0.81 | +0.06% |
| accelerator SHA-512 | 0.2195 | 13.72 | +0.45% |
| accelerator SHA3-256 | 0.2206 | 13.78 | +0.45% |

## Hardware versus simulation

### Which simulation the hardware matches

The hardware matches `default` and not `fpga` (VRF_OREG). `VRF_OREG`
adds one cycle to every VRF read: one per vector arithmetic instruction
and one per element of a vector store. The hardware shows neither. In
all 61 regions where `default` and `fpga` differ, the hardware is
closer to `default`; examples:

| Region | HW | default/axi | fpga/axi |
|---|---:|---:|---:|
| `micro_vec` `vse8.v` vl=512, cycles/instruction | 1,537.80 | 1,537.80 | 2,049.80 |
| `micro_vec` `vadd.vv` e8 vl=512 | 518.27 | 518.27 | 519.27 |
| `micro_vec` `vredsum.vs` e64 vl=8 | 16.29 | 16.29 | 17.29 |
| `kernels-scalar` memset RVV, cycles/call | 1,758 | 1,758 | 2,271 |
| `dhrystone-sdk` (V struct copy), cycles | 3,482,584 | 3,482,595 | 3,594,595 |

The `fpga` column therefore predicts the next AFI, the one with
`VRF_OREG`, not this one. On scalar code, `fpga` and `default` are
identical. On vector code, `fpga` is up to 29% slower than `default`
(RVV memset +29%, memcpy +15%, vadd +9%, Dhrystone `sdk` +3.2%,
SHA-256 RVV x16 +4.6%). Once `VRF_OREG` lands in an AFI, expect the vector rows to move
by those amounts.

The remaining gap between hardware and `default/axi` comes from the
memory model.

### Compute-bound code: no gap

When a region's working set stays in the L1s, the hardware gives the
simulation's count to within a few cycles in a million.

- **Dhrystone.** +41 cycles out of 3.07 M.
- **CoreMark.** +111 cycles out of 14.3 M at 20 iterations. At 1000
  iterations, +1,336 out of 716.8 M against the 1-cycle soc model,
  which is +0.0002%.
- **SHA, M unit, FPU, vector arithmetic and branches.** All `micro_pipe`,
  `micro_units` and `micro_vec` regions are within 0.16%. The SHA
  chains are within 0.001%.

The 32 regions with no cache miss and no uncached access in simulation
repeat cycle-exactly on hardware. The whole spread between repeats lies
in regions that touch memory:
- at most 268 cycles: `micro_dmem` `chase_rand_20k`, 0.36%;
- 8 cycles out of 716.8 M for the 1000-iteration CoreMark.

So the simulation's per-MHz figures are hardware figures for this AFI.
The earlier "projection only" numbers at 62.5 MHz in the #56 evidence
are now measured:
- 23.17 DMIPS for Dhrystone;
- 87.19 CoreMark;
- every hashes/s figure in the `sha256chain` table.

### Memory-bound code: real DDR4 against the 24-cycle AXI model

The 15 regions that differ by more than 1% are all cache-miss
microbenchmarks:
- `micro_dmem` working sets of 20 KiB and up, and the streams;
- `micro_imem` footprints of 12 KiB and up;
- the 61-cycle `micro_dmem` empty window;
- `kernels` vadd_i64 RVV, at −1.2%.

With the simulation's own miss counts (`ic_miss`, `dc_miss`, `bus_dwb`
of the axi run), the difference splits into two effects.

| Region | HW cycles/op | axi model | soc (1-cycle) | HW − axi | Misses (sim) | HW − axi per miss |
|---|---:|---:|---:|---:|---:|---:|
| D$ random chase 128/256 KiB (dependent loads, every one misses) | 40.62 | 39.11 | 14.09 | +6,177 | 4,100 | **+1.51** |
| D$ address-order chase 32 KiB | 28.26 | 27.24 | 10.47 | +4,163 | 2,749 | +1.51 |
| D$ load stream (8-byte `ld`) | 7.63 | 7.39 | 4.26 | +954 | 513 | +1.86 |
| I$ straight-line 32 KiB (cycles/instruction) | 4.07 | 3.98 | 2.61 | +4,265 | 2,701 | **+1.58** |
| I$ straight-line 12 / 16 / 24 KiB | | | | | | +1.60 / +1.65 / +1.62 |
| D$ store stream into dirty lines (8-byte `sd`) | 11.95 | 12.98 | 6.23 | −4,216 | 514 refills, 450 write-backs | about −11 per write-back |
| kernels dgemm C (32x32, 16 KiB D$ thrashed) | 733,382/call | 734,024 | 721,490 | −2,572 | 1,370 refills, 483 write-backs | about −10 per write-back |

- **A line refill costs about 1.5 core cycles more on F2 than in the
  model.** This holds for an I$ refill and a D$ refill alike. The model
  delivers the first R beat 24 cycles after AR, and a clean refill
  costs 37.0 cycles at the cache (`dc_miss_cyc / dc_miss`). On F2 it
  costs about 38.5. The CL's path is a 512-bit `sigil_mbus_axi4`, the
  AXI clock converter to the 250 MHz Shell clock, SmartConnect and the
  `sh_ddr` DDR4 controller. At 62.5 MHz this path behaves like the
  model with a read latency of about 25.5 cycles instead of 24. The
  difference is the same with a working set of 32 KiB and of 256 KiB,
  and for random and address-order access. The fixed 24-cycle model is
  a close stand-in for this DDR4 path at this clock.
- **A dirty-line write-back costs about 10 cycles less on F2.** The
  refills in the store stream and in dgemm cost +1.5 each. The
  write-backs then account for about −11 and −10 cycles each. The model
  answers B 24 cycles after the last W, and the miss handling waits for
  it. The F2 result is consistent with a write response that arrives
  about 10 cycles sooner, which is plausible for a write acknowledged
  in the interconnect or controller before it reaches the DRAM. The
  data path width also differs: 512-bit AXI on F2 against 64-bit in
  `fpga_top_tb`. Both effects partly cancel in mixed code: the
  `kernels` regions range from −1.2% to +0.2% against the model, and
  most of them are slightly *faster* on hardware.
- **Against the ideal 1-cycle memory (`soc`)**, the DDR4 path makes a
  dependent D$ miss 2.9x as expensive: 40.6 against 14.1 cycles per
  load. Only code that misses notices this. CoreMark and Dhrystone fit
  in the L1s, so they are the same on every memory model, on hardware
  too. The accelerator bulk rows lose 8% against `soc`, from the
  data-cache refills of the 64 KiB buffer.

At a higher core clock with the same DDR4, the miss penalty in core
cycles grows, because DRAM latency is fixed in nanoseconds. These
results apply to 62.5 MHz. To check another clock, rerun the micro_dmem
chase on it.

## F2 time

There was one instance, `i-0fa8f24634bfa912f`:

| Event | Time (UTC) |
|---|---|
| Launched | 11:23:13 |
| Setup done | about 11:25:25 (SDK and host build, AFI load: 32 s) |
| Last run finished | 11:27:43 |
| Terminate requested | 11:28:48 |
| `terminated` confirmed | 11:33:22 |

That is 5 min 35 s running, or 0.093 instance-hours (at most 0.17 h
counting until `terminated`), out of a 1 instance-hour budget. The
instance had a hard cap, which it never reached: user-data `shutdown
-h +55` with shutdown behaviour `terminate` (`aws-lifecycle.txt`).

## Reproduce

1. On a #56 build host, run `scripts/build_images.sh`. Check the result
   against `SHA256SUMS`.
2. Launch an `f2.6xlarge` from the FPGA Developer AMI with
   `scripts/user-data.sh`.
3. Copy `bins/`, `fpga/host/` (as `host/`) and the two instance scripts
   to `~/f2perf`.
4. Run `setup_f2.sh`, then `run_f2.sh`.
5. Validate on the build host:
   ```
   python3 docs/evidence/perf-f2-56-2026-10-22/scripts/f2_validate.py \
     --logs <logs> --bench-dir sw/bench --sha256sums SHA256SUMS \
     --sim docs/evidence/perf-suite-56-2026-10-22/results.json:docs/evidence/perf-suite-56-2026-10-22/runs \
     --sim-long docs/evidence/perf-coremark-56-2026-10-22/long-1000/results.json:docs/evidence/perf-coremark-56-2026-10-22/long-1000/runs \
     --sim-extra base=docs/evidence/perf-baseline-56-2026-10-22/fpga/results.json \
     --json results.json --md regions.md
   python3 .../scripts/f2_report.py results.json > tables.md
   ```

The `fpga` column comes from the #56 simulation baseline at `8d15410`,
[`perf-baseline-56-2026-10-22/fpga/results.json`](../perf-baseline-56-2026-10-22/fpga/results.json)
(`run_baseline.sh`, `CONFIG=fpga`, written 2026-10-22T11:40:56Z, the
same images, 712/712 valid; sha256 `328237fc…c42d`, the file this
comparison read). The `default/axi` and `default/soc` columns come from
`perf-suite-56-2026-10-22`, which has the same images and RTL. The values
used are copied into `results.json` (`sim_axi`, `sim_soc` and
`base_fpga_*` fields).
