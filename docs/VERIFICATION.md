# Verification

How the Sigil core is checked, and where the evidence lives. The
compliance claims (riscv-tests, ACT, TestFloat) and their evidence are
in [`COMPLIANCE.md`](COMPLIANCE.md) and [`evidence/`](evidence/README.md);
the gates are listed in [`../AGENTS.md`](../AGENTS.md) (`make test`,
`make lint`, `make core-test`, `make riscv-tests`, ACT).

| Flow | What it checks | Entry point |
|---|---|---|
| Unit and directed core tests | each RTL unit, then directed asm on the core (`sw/core-tests`) with coverage | `make core-test` |
| riscv-tests | upstream rv64ui/um/ua/uf/ud/uc/mi/si `-p-` on the core, random bus timing | `make riscv-tests` |
| ACT (riscv-arch-test) | signatures vs the Sail reference, per extension | `scripts/build_act4_core.sh`, `sim/run_act_core_par.sh` |
| TestFloat | the FPU against SoftFloat | `scripts/build_testfloat.sh` |
| **riscv-dv vs Spike** | random programs; every retired instruction compared with Spike | `make -C sim riscv-dv` (this page); nightly/manual CI `.github/workflows/riscv-dv.yml` |

## riscv-dv random-instruction regression vs Spike (issue #8)

For each (test, seed) the regression generates a random program with
riscv-dv, runs it on Spike and on the Verilated core, and compares the
two commit traces record by record: program counter, instruction bits,
privilege, every integer/FP/vector register write, CSR writes, stores,
and every trap. Both runs must also end the same way (HTIF `tohost` = 1).

```
testlist.yaml ──> pygen (target sigil) ──> test.S ──gcc──> test.elf
                                                              │
                       spike -l --log-commits <── test.elf ──> core_tb +sigil_trace
                                │                                   │
                            spike.log                           dut.trace
                                └──────> rdv_trace.py compare <─────┘
                                     ref.csv / dut.csv (riscv-dv trace CSV)
                                     compare.txt, one row in results.csv
```

### Running it (sigil-verify)

```sh
cd ~/wt/8-riscv-dv                      # any checkout of this branch
source deps/env.sh                      # Verilator + riscv64-unknown-elf-gcc
scripts/build_spike.sh ~/opt/spike      # pinned Spike, once (idempotent)
export SPIKE=~/opt/spike/bin/spike      # or put spike on PATH
make -C sim riscv-dv                    # all supported tests, seeds 1,2,3
make -C sim riscv-dv TESTS=riscv_amo_test,riscv_b_ext_test SEEDS=1-10 JOBS=16
scripts/riscv_dv_regress.sh --list      # supported and excluded tests
scripts/riscv_dv_regress.sh --help      # all options
```

`make -C sim riscv-dv` builds `build/sim/core_tb` (the harness that runs
riscv-tests and ACT) if needed and calls `scripts/riscv_dv_regress.sh`,
which runs `scripts/riscv_dv_setup.sh` the first time (and whenever the
pygen patch, the core setting or the riscv-dv pin changes). `TESTS` is
only taken from the make command line (`sim/Makefile` has its own
`TESTS` list of directed programs); extra driver options go in
`RDV_ARGS`, e.g. `RDV_ARGS="--instr-cnt 1000 --keep"`. Keep `JOBS` at 16
or below on the shared machine. Generation dominates the run time:
pygen took 3 to 11 minutes (median 5) per 5,000- to 10,000-instruction
program on the busy c7i.8xlarge, Spike and the core a few seconds; the
full list (22 tests x 5 seeds) takes about 30 minutes with 12 jobs. The
four directed programs need no generation and take seconds each.

Useful driver options: `--instr-cnt N` (override every test's
`+instr_cnt`, for quick runs), `--out DIR` (default
`build/riscv-dv/run`), `--keep` (keep Spike logs and DUT traces of
passing runs too), `--core-tb PATH` (e.g. a harness built with another
Verilator), `--gen-mem-gb` (below), `--max-cycles`, `--max-instr`
(Spike's budget, below), `--gen-timeout`, `--sim-timeout`.

### CI (nightly and manual)

[`.github/workflows/riscv-dv.yml`](../.github/workflows/riscv-dv.yml)
runs the regression on a GitHub-hosted `ubuntu-24.04` runner (4 vCPUs,
16 GB): nightly (03:41 UTC) every supported test with seed 1 (the same
programs every night, so a red run after a change is a regression) and
seed 1000 + the run number (new programs every night), and on demand
(`workflow_dispatch`: tests, seeds, instruction count). It never runs
on push or pull_request and is not a required check: one program takes
minutes to generate. It installs apt Verilator 5.020 and the pinned
GCC toolchain of `compliance.yml`, builds Spike with
`scripts/build_spike.sh`, and caches the toolchain, Spike, and the
riscv-dv clone with the generator's venv. The step summary lists the
status counts and every failing (test, seed) with its first divergence;
the artifact holds `results.csv`, the log and the run directories of
the failures. A failure reproduces locally with `make -C sim riscv-dv
TESTS=<test> SEEDS=<seed>`.

### Generator memory

pygen needs far more memory than Spike or the core. Peak resident set
size per program, all generated tests x seeds 100000-100009 on
sigil-verify (`gen_rss_mb`):

| Test | pygen peak RSS |
|---|---|
| `riscv_amo_test` (randomizing the LR/SC and AMO streams) | 7.8-8.4 GiB (up to 9.0 GiB, 9,231 MiB, over the 65 seeds of rounds 2 and 3) |
| `riscv_mmu_stress_test`, `riscv_floating_point_mmu_stress_test`, `riscv_rand_instr_test` | 1.8-2.0 GiB |
| the other 14 generated tests | 0.9-1.8 GiB |

Started together, the ten seeds of `riscv_amo_test` need about 80 GiB;
sigil-verify has 61 GiB and no swap. In round 1 (seeds
100000-100009, 16 jobs, all ten `riscv_amo_test` generations started
within 90 s) the kernel's OOM killer stopped four of them: `GEN_FAIL`
with `pygen rc=-9`, `gen.log` ending at "Start generating 5000
instruction", no traceback, no program. A harness failure, not a core
result: no program existed for the core to run, and the four programs,
regenerated alone (pygen is deterministic), match Spike.

The driver therefore runs generations under a memory budget. Each
generation reserves its test's `gen_mem_gb` from `testlist.yaml` (10 for
`riscv_amo_test`; 2.5 for tests without the key, `DEFAULT_GEN_MEM_GB`
in `rdv_regress.py`) while pygen runs, and waits, in submission order,
until it fits in `--gen-mem-gb` (default 75% of `MemAvailable` when the
driver starts: about 44 GiB on an idle sigil-verify, so four
`riscv_amo_test` generations at a time; 0 turns the limit off). A
generation larger than the whole budget still runs, alone. Jobs are
queued seed by seed (every test's seed 1, then seed 2, ...), so the
seeds of one test are spread over the run. The budget is fixed at
start: pass a lower `--gen-mem-gb` when another job will start using
memory during the run. GB here are GiB.

pygen's peak resident set size goes into the `gen_rss_mb` column, the
driver prints the maximum per test at the end, and it prints a note
when a generation exceeds its test's `gen_mem_gb`. A pygen killed by
SIGKILL is reported as `pygen rc=-9 (SIGKILL: out of memory? ...)`:
check `dmesg` for an OOM kill, then lower `--gen-mem-gb` or raise the
test's `gen_mem_gb`.

### Results

`<out>/results.csv`, one row per (test, seed):

| Column | Meaning |
|---|---|
| `status` | `PASS`, `MISMATCH`, `DUT_TIMEOUT`, `DUT_FAIL`, `GEN_FAIL`, `SPIKE_FAIL` (below) |
| `first_divergence` | first differing record: index, pc, instruction, Spike's disassembly, and each differing field (`x: dut {...} ref {...}`, `store: ...`, `csr 0x300 (mstatus): ...`, `cause: ...`) |
| `ref_records`, `dut_records` | records compared (up to and including the `tohost` store) |
| `dut_cycles`, `gen_s`, `spike_s`, `dut_s` | core cycles to `tohost`, wall-clock seconds per step |
| `gen_rss_mb` | pygen's peak resident set size (MiB) |
| `dir`, `asm`, `elf`, `spike_log`, `dut_trace`, `ref_csv`, `dut_csv`, `report` | artifacts of the run |

| Status | Meaning |
|---|---|
| `PASS` | traces match and both sides wrote `tohost` = 1 |
| `MISMATCH` | the core finished, but its trace diverges from Spike's |
| `DUT_TIMEOUT` | `core_tb` reached `--max-cycles` (or `--sim-timeout`); `first_divergence` says where the traces split, if they did |
| `DUT_FAIL` | `core_tb` reported a failing `tohost` value or crashed |
| `GEN_FAIL` | pygen or the assembler failed (`gen.out`, `gcc.out`); `pygen rc=-9` is usually an out-of-memory kill ("Generator memory") |
| `SPIKE_FAIL` | Spike failed or did not end with `tohost` = 1 (a generator or config problem, not a core bug) |

Each run directory holds `<test>_0.S`, `<test>.elf`, `gen.log`
(pygen's log with the randomized configuration), `spike.log`,
`dut.trace`, `ref.csv`/`dut.csv` (riscv-dv trace CSV, the format of
`scripts/riscv_trace_csv.py`, so riscv-dv's own
`scripts/instr_trace_compare.py` can read them too) and `compare.txt`
(the first divergence with the four records before it). Triage
starts there; a single comparison can be re-run by hand:

```sh
sim/riscv-dv/rdv_trace.py --elf T.elf --spike spike.log --dut dut.trace
```

Generation is deterministic: pygen seeds Python's `random` from its
`--seed`, which the driver derives from the test name and the seed
(`gen_seed` column, CRC32 of the name plus the seed; with the bare seed
every test would draw the same boot mode). A failing (test, seed)
reproduces with `TESTS=<test> SEEDS=<seed>`. The seed also seeds
`core_tb`'s random bus latency/backpressure (`--mem-lat 1:6 --mem-gap 2
--mem-ready 70 --mem-seed <seed>`, as in `make riscv-tests`).

### Pins and versions

| Item | Version |
|---|---|
| riscv-dv | chipsalliance/riscv-dv `0d71c2b666dec48dde0b804a2138426da56aa252` (master, 2026-09-21); cloned to `third_party/riscv-dv` (git-ignored, never modified) |
| Generator | riscv-dv's Python generator (pygen, `run.py --simulator pyflow` equivalent): no SystemVerilog simulator is available. Copied to `build/riscv-dv/gen` and patched with [`sim/riscv-dv/patches/pygen-sigil.patch`](../sim/riscv-dv/patches/pygen-sigil.patch) |
| Python | 3.12.3 (Ubuntu 24.04), venv `build/riscv-dv/venv` with [`sim/riscv-dv/requirements.txt`](../sim/riscv-dv/requirements.txt) (pyvsc 0.9.1.10086043874, pyboolector 3.2.4.20240823.1, pyucis 0.1.3.7162246580, PyYAML 6.0.3, bitstring 5.0.0, ...) |
| Spike | riscv-isa-sim master `2c300cd90eb74bb79f3fcdd58596a6f8d842d01c` (1.1.1-dev, 2026-10-21) with its `berkeley-softfloat-3` submodule at `32eb3295`, built into `~/opt/spike` on sigil-verify; [`scripts/build_spike.sh`](../scripts/build_spike.sh) builds this pin (CI uses it) |
| Toolchain | `deps/` riscv64-unknown-elf GCC 16.1.0 (`g6afcc4f6d`), binutils 2.47 (`scripts/install_deps.sh --gcc15`); CI: the same release from riscv-collab `2026.08.27` (as `compliance.yml`) |
| DUT simulator | Verilator 5.048 (`deps/`); the trace probe also lints and builds with 5.044 (macOS) and 5.020 (Ubuntu apt, used by CI) |

### Generator configuration (target `sigil`)

[`sim/riscv-dv/target/sigil/riscv_core_setting.py`](../sim/riscv-dv/target/sigil/riscv_core_setting.py),
installed into the pygen copy by the setup script. What Sigil
implements against what riscv-dv's pygen can generate:

| Sigil | Generated | Notes |
|---|---|---|
| RV64I, M, A, F, D | yes | groups RV32/RV64 I, M, A, F, D |
| C (Zca, Zcd) | yes | RV32C, RV64C, RV32DC (`c.fld`/`c.fsd`...) |
| Zcb | via the assembler | programs are assembled with `-march=rv64gc_zba_zbb_zbc_zbs_zbkb_zcb`, so eligible instructions get Zcb encodings |
| Zbb, Zbs, Zbc, Zbkb `pack`/`packh` | yes, `riscv_b_ext_test` | pygen only has the draft-0.92 B extension (one RV32B group). The draft instructions that were ratified with unchanged encodings are generated, with the ratified mnemonics (patch D); the dropped draft instructions are in `unsupported_instr` |
| Zba, Zbb/Zbs RV64 W forms, Zbkb (rest), Zbkc, Zbkx, Zkne, Zknd, Zknh, Zicond | no | not in pygen; covered by the directed `sigil_bitmanip_crypto_test` (operands from a PRNG seeded per seed) |
| RVV 1.0 Zve64d, VLEN 512 | no | pygen has no vector instruction classes; covered by the random directed `sigil_vector_test` (random vtype, AVL, operands and data per seed; below) |
| H | no | not in pygen, and no directed program yet |
| M/S/U | yes | all three boot modes: `+boot_mode` where the test asks for one, otherwise random per (test, seed) as in SV (patch V). pygen does not delegate traps (`gen_delegation_instr` is a TODO), so in its tests every trap is handled in M-mode; delegation is covered by the random directed `sigil_priv_test` (below) |
| Sv39 (+Svnapot, Svadu) | no (`SATP_MODE = BARE`) | pygen cannot build page tables (`create_page_table` is a TODO upstream); covered by `sigil_priv_test` |
| PMP, 16 entries, G=0 | opened, not tested by pygen | pygen's PMP setup is a TODO; [`user_init.s`](../sim/riscv-dv/user_extension/user_init.s) opens entry 0 (NAPOT, RWX, whole PA space) so S/U code can run. `sigil_priv_test` programs random NA4/NAPOT/TOR entries |
| S-level interrupts, delegation | no | `sigil_priv_test`: SSIP/STIP/SEIP made pending by M-mode `mip` writes, random `mideleg`/`mie`/`medeleg`/`sstatus.SIE` |
| misaligned loads/stores trap | yes | `riscv_unaligned_load_store_test`; the generated handler skips the access and resumes (patch AE), about 2,000 misaligned traps per run |
| read-only `misa` | yes | `MISA_VALUE` (patch C) makes the generator write Sigil's value, which Spike (writable misa) keeps |
| CSRs | init only | free-running counters (cycle/time/instret) are left out of `implemented_csr`: they differ between RTL and an ISS by construction. pygen's random CSR instruction never constrains the CSR address, so random CSR instructions stay off (as in upstream pygen) |

pygen at this pin is a partial port of the SV generator and has bugs
that stop generation or make programs wrong. The setup applies fixes A
to Z and AA to AE, each described in the
[patch header](../sim/riscv-dv/patches/pygen-sigil.patch). In groups:

- generation fails: Python 3.12 (`imp`), wrong `randrange` bounds,
  enum/string mix-ups in instruction selection, an AMO stream that
  cannot be constructed, unsatisfiable register picks, a
  multiprocessing hang on any generator error, no SSTATUS/SIE model;
- programs do not assemble: load/store offsets the encodings cannot
  hold, `la zero`, compressed FP loads/stores printed with integer
  registers, a missing S-mode trap handler section;
- programs are wrong or end early: S/U boots that silently stayed in
  M-mode and no random boot mode; operand fields shared between
  instruction copies (loads through another stream's base register);
  load/store addresses off by one and a mis-indented "unaligned" branch
  (misaligned accesses in every test); loops whose counter update and
  branch were unconstrained or used one register for counter and limit
  (endless loops); `ra`/`jal` destinations that overwrite the trap
  handlers' stack pointer; no ebreak handler and no ECALL-from-S/U
  dispatch; the AMO stream drawing from every instruction, and LR/SC
  without base-register constraints or with mismatched widths;
  `+enable_b_extension` ignored by most B groups; every misaligned-access
  exception ending the test in `test_done` (AE: the Sigil target's
  handler skips the access, since the core traps every misaligned
  access).

Before these fixes, at 10,000 instructions every test with a
load/store stream failed to assemble, and most of the rest ended within
a few hundred instructions at a misaligned access or the first ebreak.
Sub-programs (the call stack) are not implemented in pygen at all:
every test runs with `+num_of_sub_program=0`.

### Reference model configuration (Spike)

```
spike --isa=rv64imafdcbvh_zicsr_zifencei_zicntr_zbc_zbkb_zbkc_zbkx_zkne_zknd_zknh_zicond_zcb_zvl512b_svnapot_svadu \
      --priv=msu --triggers=0 --pmpregions=16 --pmpgranularity=4 --wfi-as-nop \
      -l --log-commits --log=spike.log --instructions=N test.elf
```

| Sigil | Spike setting |
|---|---|
| RV64IMAFDC, B (Zba/Zbb/Zbs), Zbc, Zbkb/c/x, Zkn, Zicond, Zcb, H | ISA string above. With it Spike's `misa` reads `0x8000_0000_0034_11AF`, the value Sigil's read-only `misa` returns (checked on both) |
| RVV Zve64d, VLEN 512, ELEN 64 | `v` (Zve64d + Zvl128b) plus `_zvl512b`; Spike 1.1.1-dev takes VLEN from the ISA string (there is no `--varch`) |
| M/S/U | `--priv=msu` |
| 16 PMP entries, G=0 | `--pmpregions=16 --pmpgranularity=4` |
| no debug triggers (Sdtrig CSRs read 0) | `--triggers=0` |
| A/D bits set by the page walker (Svadu semantics, always on) | `svadu` in the ISA string; Spike then updates A/D when `menvcfg.ADUE` = 1, which `sigil_priv_test` sets (pygen programs run with satp Bare and never touch `menvcfg`) |
| misaligned loads/stores trap | no `zicclsm` in the ISA string (Spike emulates misaligned accesses only with it) |
| WFI completes like a NOP | `--wfi-as-nop` |
| RAM at `0x8000_0000` | Spike's default 2 GiB at `0x8000_0000`; programs are linked there (riscv-dv `scripts/link.ld`) and `core_tb` loads ELF segments at their physical addresses. Spike's boot ROM (5 instructions at `0x1000`) is skipped by the comparison, which starts at the ELF entry |

`--instructions=N` is a safety limit, and Spike charges it in steps of
5,000 instructions (`sim_t::INTERLEAVE`): a trap ends the current step
early, so every trap can cost up to 5,000 of the budget, and at the
limit Spike exits 0 without writing `tohost` (reported as `SPIKE_FAIL`,
"did not write tohost within its --instructions budget"). The default
budget is 2,000,000 (`--max-instr`); a trap-heavy test sets its own with
`spike_max_instr` in `testlist.yaml` (`riscv_unaligned_load_store_test`:
40,000,000 for about 2,000 traps).

### DUT trace (simulation only)

`rtl/core/sigil_core.sv` ends with a block under `` `ifndef SYNTHESIS ``
that writes the trace when the simulation is built with
`+define+SIGIL_COMMIT_TRACE` (as `build/sim/core_tb` is) and run with
`+sigil_trace=<file>`. Synthesis never sees it, nothing in it feeds back
into the design, and without the plusarg it writes nothing. (The define
keeps the `$value$plusargs` call out of harnesses that never pass their
arguments to Verilator, such as `fpga_ocl_tb`, where Verilator would
abort.) `make lint` checks the core with and without the define. One
line per retired instruction or trap:

```
I <cycle> <priv> <pc> <insn> [x<n>=<v>] [f<n>=<v>] [c<csr>=<v>] [m<va>:<bytes>=<data>] [v<n>=<512 bits>]...
E <cycle> <priv> <epc> <cause> <tval>
```

- An instruction retires in WB on the `minstret` condition
  (`memwb_valid_q && !memwb_exc_q && !mem_stall`); a trap is logged on
  `trap_take`. Instruction bits (the 16-bit parcel for RVC), privilege
  as executed, and the side effects MEM/WB does not carry ride along in
  shadow registers loaded under the pipeline registers' own update
  conditions.
- `x`/`f`: the register file write (`x0` is not logged); FP values are
  the 64-bit register contents (NaN-boxed singles).
- `c`: explicit CSR-instruction writes, with the value the CSR reads
  back after the write (as Spike logs it). `sigil_csr.sv` has a
  sim-only copy of its read mux, addressed by the last written CSR, for
  this; an assertion checks the copy against the real read port whenever
  both read the same CSR. FP instructions that raise flags log the new
  `fflags` (`c001`). Other implicit CSR updates (trap entry, xRET,
  `mstatus.FS/VS` dirtying, `vl`/`vtype`/`vstart`) are not logged.
- `m`: the scalar store the instruction issued (virtual address, size,
  data; the write phase of an AMO; nothing for a failing SC).
- `v`: whole 512-bit vector registers the instruction wrote, as they
  were when it entered WB (from a shadow of every VRF write). Not as
  they are when it retires: a younger vector load in MEM stalls
  retirement while it writes the VRF, possibly the same registers.

`core_tb --drain 64` keeps clocking for 64 cycles after the HTIF
`tohost` store so that the store and everything older retire into the
trace; without `--drain` the harness stops at the store, as before.

### Comparison rules

`sim/riscv-dv/rdv_trace.py` turns both logs into the same records and
compares them in order; the first difference is reported:

- record kind, pc and instruction bits; privilege for retired
  instructions;
- integer and FP register writes: same registers, same values;
- stores: the same (address, size, data) list for scalar stores (vector
  store data is checked when it is loaded back);
- CSRs: the value of every CSR both sides logged for the instruction
  must match (Spike also logs side effects the DUT does not, e.g.
  `mstatus` on FS dirtying or xRET; those are not compared), and an
  `fflags` update must be logged by both or neither. `fcsr`/`vcsr`
  writes are compared field by field (Spike logs the fields), and an
  `sstatus` write against the `mstatus` value Spike logs for it;
- vector registers: compared where both logged the register; a register
  that only one side logged must already hold that value on the other
  side (its last logged value, 0 at reset). Writes that leave a register
  unchanged may be logged by one side only (the DUT logs the mask
  register of a compare whose elements are all masked off; Spike does
  not);
- traps: cause, epc and tval (interrupts included);
- Spike's trace is cut after its first store to `tohost`; the DUT trace
  must contain exactly the same records up to that point;
- one implementation-defined CSR bit is left out of CSR-write
  comparisons (`CSR_IMPL_DEFINED` in `rdv_trace.py`): `mideleg` bit 12
  (SGEIP), which Spike with H reads as one even without guest external
  interrupts, and Sigil (GEILEN = 0) reads as zero.

The comparator was checked against corrupted DUT traces (a dropped
record, changed x/f/vector/CSR/store values, a changed privilege or trap
cause, a missing `fflags` update, a dropped vector register write): each
is reported as `MISMATCH` at the right record.

### Test list

[`sim/riscv-dv/testlist.yaml`](../sim/riscv-dv/testlist.yaml) lists
every riscv-dv built-in test at the pin (`yaml/base_testlist.yaml` and
the `target/*/testlist.yaml` lists) once, either with the options it
runs with or with `excluded:` and the reason. Changes for all runnable
tests: `+num_of_sub_program=0`, `gen_test: riscv_instr_base_test` with
the directed streams spelled out (pygen's `riscv_rand_instr_test`
hard-codes 5 sub-programs), and the streams pygen does not implement
(`riscv_hazard_instr_stream`, `riscv_multi_page_load_store_instr_stream`,
`riscv_mem_region_stress_test`) dropped.

Supported (18 generated + 6 directed):

| Test | Source list | Notes |
|---|---|---|
| `riscv_arithmetic_basic_test` | base | M-mode, no load/store/branch |
| `riscv_rand_instr_test` | base | load/store, loop, hazard and jal streams |
| `riscv_jump_stress_test` | base | `riscv_jal_instr` x20 |
| `riscv_loop_test` | base | `riscv_loop_instr` x20 (needs patches O/P) |
| `riscv_no_fence_test` | base | pygen never emits FENCE in random streams anyway |
| `riscv_illegal_instr_test` | base | 5 illegal instructions per 1000 |
| `riscv_ebreak_test` | base | about 50 breakpoint exceptions per run, each resumed by the handler (patches E, AC) |
| `riscv_unaligned_load_store_test` | base | Sigil traps misaligned accesses; the handler skips each one and resumes (patch AE; SV riscv-dv and pygen end the test at the first): about 2,000 load/store-misaligned traps and 200,000 records per run |
| `riscv_mmu_stress_test` | base | load/store stress in a random boot mode; satp Bare |
| `riscv_machine_mode_rand_test` | rv64gc | |
| `riscv_privileged_mode_rand_test` | rv64gc | random boot mode (patch V) |
| `riscv_u_mode_rand_test` | rv32imc_sv32 | U-mode |
| `riscv_non_compressed_instr_test` | rv32imc | assembled without C/Zcb |
| `riscv_amo_test` | rv64gc | LR/SC and AMO streams (needs patches G-M, R) |
| `riscv_floating_point_arithmetic_test` | rv64gc | F/D, M-mode |
| `riscv_floating_point_rand_test` | rv64gc | |
| `riscv_floating_point_mmu_stress_test` | rv64gc | satp Bare |
| `riscv_b_ext_test` | rv32imcb | ratified subset of draft B |
| `sigil_bitmanip_crypto_test` | Sigil, directed | Zba/Zbb/Zbs W forms, Zbkb/c/x, Zkn, Zicond; 300 PRNG iterations seeded by the seed (`-DRDV_SEED`) |
| `sigil_hint_test` | Sigil, directed, random | HINT encodings, seeded by the seed: 200 blocks of 24 random HINTs written to memory and run after FENCE.I with PRNG data in the registers: 32-bit rd = x0 forms of LUI, AUIPC, OP-IMM (incl. the Zicbop prefetch encodings), OP (incl. M and the Zbb funct7 0x20 forms), OP-IMM-32, OP-32; FENCE with random pred/succ, fm and the ignored rs1/rd fields; 16-bit C.NOP with nzimm, C.ADDI with imm 0, C.LI/C.LUI/C.MV/C.ADD with rd = x0, C.SLLI with rd = x0 or shamt 0, C.SRLI/C.SRAI with shamt 0; about 250,000 records |
| `sigil_priv_test` | Sigil, directed, random | privileged architecture, seeded by the seed: 128 iterations, each with random Sv39 test mappings (4 KiB leaves with random V/R/W/X/U/G/D and backing page, sometimes a reserved PTE bit; a whole Svnapot 64 KiB group; a 2 MiB leaf, sometimes misaligned; a non-leaf with reserved bits), random PMP entries 0-2 (NA4, NAPOT 8 B-16 KiB, TOR) over the page tables and backing pages, random `medeleg`/`mideleg`/`mie` and pending SSIP/STIP/SEIP, random `mstatus` (MPP S or U, TVM, SUM, MXR, FS, SIE, SPIE, SPP, MPIE); then one random load, store, AMO, LR, FP load, fetch, EBREAK, S CSR read or SFENCE.VMA in S or U; handlers in M and S log cause/epc/tval/status, the iteration ends by ECALL; hardware D updates (`menvcfg.ADUE`) read back each iteration; about 110,000 records and 300 traps per run |
| `sigil_vector_test` | Sigil, directed, random | RVV, seeded by the seed: 24 iterations, each a random legal vtype (SEW 8-64, LMUL mf8-m8, ta/ma), AVL in [0, VLMAX], vxrm, frm and data with corner values; loads/stores of every addressing mode (unit-stride, strided incl. negative and zero stride, indexed, segment, fault-only-first, mask, whole-register); integer, fixed-point, widening/narrowing, extension, mask, permutation, reduction and FP (SEW 32/64) arithmetic, masked and unmasked; CSRs read back and all 32 vector registers stored and reloaded each iteration; about 82,000 records |
| `sigil_viota_test` | Sigil, directed, random | `viota.m`, self-checking, seeded by the seed: 96 iterations, each a random legal vtype (SEW 8-64, LMUL mf8-m8, ta/tu, ma/mu), AVL 0, 1, 2, VLMAX-1, VLMAX, above 2*VLMAX or random, masked or unmasked, an LMUL-aligned vd group (v0 when unmasked) and vs2 any register outside it (v0 included, also under `v0.t`), with random, all-ones, sparse or dense masks; every element of the vd group (tail elements unchanged or, under ta, all ones; unchanged at vl = 0) and every other register is checked in scalar code (and so compared); one iteration in 16 each runs vd not aligned, `v0.t` with vd = v0, or `vill` set, which must trap and change nothing. `-DVIOTA_VSTART=1` / `-DVIOTA_OVERLAP=1` add `vstart` != 0 and vs2 inside the vd group (both trap on Spike; not in the list, Sigil executes them); about 720,000 records |
| `sigil_viota_sweep_test` | Sigil, directed, sweep | the same program with `-DVIOTA_SWEEP=1` (testlist `defines`): every combination of the 22 legal vtypes, tu/ta, mu/ma, unmasked/`v0.t` and 8 AVL classes (0, 1, 2, VLMAX-1, VLMAX, all ones, VLMAX+1, random), 1,408 in all, legal encodings only, vs2 an odd register (not LMUL-aligned) in 6 of 8 iterations and v0 in 1 of 8; each run is one chunk of 88 combinations (RDV_SEED mod 16). `sw/core-tests/viota_sweep_directed` runs all 1,408 on the core |

Excluded (18), with the reason recorded in the test list:

| Test | Reason |
|---|---|
| `riscv_rand_jump_test` | jumps among sub-programs; pygen has none |
| `riscv_ebreak_debug_mode_test` | debug mode: Sigil has none, pygen's debug ROM is a TODO |
| `riscv_full_interrupt_test` | needs interrupts raised at the same instruction on the core and on Spike (riscv-dv's UVM irq agent); `core_tb` raises them at a cycle, Spike's CLINT counts instructions. Needs a lockstep flow. Interrupts made pending by software (`mip` writes) are covered by `sigil_priv_test` |
| `riscv_csr_test` | `gen_csr_test.py` needs a per-field CSR description of Sigil; upstream runs it RTL-only (`no_iss`) |
| `riscv_pmp_test` | pygen's PMP configuration (`riscv_pmp_cfg`, `+pmp_*`) is not ported; random PMP entries are in `sigil_priv_test`, PMP is also covered by ACT |
| `riscv_hint_instr_test`, `riscv_rand_test` (ml) | pygen's HINT generation fails to solve for every seed tried ([evidence](evidence/riscv-dv-8-2026-10-22/critic/hint-test-gen-fail.txt)); HINT encodings run in `sigil_hint_test` |
| `riscv_misaligned_instr_test` | for IALIGN=32 cores; with C no misaligned-fetch exception can occur |
| `riscv_invalid_csr_test` | pygen's CSR instruction does not constrain the address; random addresses hit the counters |
| `riscv_sfence_exception_test` | pygen never emits SFENCE.VMA in random streams |
| `riscv_page_table_exception_test` | no page tables in pygen (upstream runs it with 0 iterations); page-table exceptions (permissions, reserved bits, misaligned superpages, PMP on PTE reads) are in `sigil_priv_test` |
| `riscv_vector_*` (4 tests) | no vector instructions in pygen; see `sigil_vector_test` |
| `riscv_zbb_zbt_test` | Zbt is not ratified; Sigil does not implement it |
| `riscv_load_store_shared_mem_test`, `riscv_single_hart_test` | multi-hart target; Sigil is single-hart |

### Results and findings

Evidence: [`evidence/riscv-dv-8-2026-10-22/`](evidence/riscv-dv-8-2026-10-22/);
every round, run count, root cause and waiver is in its
[`SUMMARY.md`](evidence/riscv-dv-8-2026-10-22/SUMMARY.md), and the "#8"
entries of [`evidence/README.md`](evidence/README.md) index the files.

| Round | Commit | Seeds | Runs | Result | Records |
|---|---|---|---|---|---|
| builder | `384d813`, `661c046` | 1-6 | 120 | 120 PASS | 1,354,066 |
| rounds 1-3 | `b86bc8d`-`84974af` | 100000-300039 | 1,500 | 1,496 PASS, 4 GEN_FAIL (generator OOM kills; PASS under the memory budget) | 16,533,928 |
| review: full list | `34ddf8e`, `e1c4338` | 1-5 | 200 | 200 PASS | 5,070,824 |
| review: directed programs | `ef27681` | 6-205 | 400 | 400 PASS | 21,417,310 |
| main merged into the branch | `adf4c97` | 1-5 | 100 | 100 PASS | 2,535,412 |
| review: full list with the PMP fix and `sigil_priv_test` | `c98428b` | 1-5 | 105 | 105 PASS | 3,100,449 |
| review: the four directed programs | `37aa1d7` | 1-205 | 820 | 820 PASS | 97,111,729 |

The full list on `c98428b` (21 tests then; 30 minutes with 12 jobs)
compared 12,645 traps and interrupts and 3.1 million records, with the
generated programs booting in M, S and U mode. Over its 205 seeds on
`37aa1d7` the privileged program took 67,826 traps: 17,212 S-level
interrupts (SSI, STI and SEI about equally), 12,209 page faults, 1,060
access faults, 5,216 illegal instructions, 809 breakpoints and 31,320
ECALLs; the RVV program ran 4,920 iterations over all 22 legal SEW/LMUL
pairs; the HINT program ran 984,000 HINTs. All 820 runs passed.

Rounds up to 3 ran the earlier directed programs (a fixed 53-record
vector program, one PRNG seed for the bit-manipulation program) and the
earlier `riscv_unaligned_load_store_test` (ended at its first
misaligned access); the privileged and HINT programs came with the
review.

Findings:

- **Core: `viota.m` with a mask register not aligned to LMUL trapped**
  (illegal instruction, e.g. `viota.m v24, v5, v0.t` at LMUL 2). The
  legality check treated vs2 as an LMUL group; it is one mask register.
  Fixed in `63a50a5`; `vec_directed` test 25 fails on the earlier RTL.
  Review (branch `8-dvfix-viota`): `sigil_viota_test`, the 1,408-case
  sweep (`sigil_viota_sweep_test`, `viota_sweep_directed`) and
  `viota_cases_directed` (hand-computed results: the spec's examples,
  LMUL 1-8, vl = 0 and VLMAX, vs2 = v0 under `v0.t`, back-to-back
  producers and consumers, the illegal encodings) pass on Spike and on
  the fixed RTL and fail without the fix
  ([evidence](evidence/riscv-dv-8-2026-10-22/critic/viota-review.txt)).
- **Core: `vstart` != 0 does not make `viota.m` illegal** (open,
  older than `63a50a5`). RVV 1.0 requires an illegal-instruction
  exception for `vstart` != 0 on `viota.m`, `vcpop.m`, `vfirst.m`,
  `vmsbf/vmsif/vmsof.m`, `vcompress.vm` and the reductions; Spike raises
  it, Sigil executes all of them from `vstart` (`viota.m` counts from 0
  at element `vstart`). The riscv-dv programs never write `vstart` before
  them. `viota_vstart_directed` and `vstart_illegal_directed` (all
  twelve instructions; passes on Spike) fail; not in the suite.
- `viota.m` with vs2 inside the vd group is reserved; Spike raises an
  illegal-instruction exception, Sigil executes it. Before `63a50a5` an
  unaligned vs2 in the group trapped by the alignment rule (e.g.
  `viota.m v8, v9` at LMUL 2), an aligned one (`viota.m v8, v8`) did not;
  now none does. Either is allowed for a reserved encoding.
- **Core: `.vf` scalars at SEW=32 were not NaN-box checked in the moves**
  (`vfmv.v.f`, `vfmv.s.f`, `vfmerge.vfm`, `vfslide1up/down.vf` took the low
  half of an f register that does not hold a NaN-boxed single; RVV
  requires the canonical NaN, as the FPU-computed `.vf` forms already
  did). Fixed in `63a50a5`; `fpvec_directed` test 11 fails on the
  earlier RTL. Both were found by the random RVV program in its first
  run (8 of 8 seeds), after rounds 1-3 had passed 1,500 runs with the
  fixed vector program.
- **Core: PMP decided an 8-byte access by its first 4-byte word.** The
  lowest-numbered entry that matches any byte of an access decides, and
  an entry that matches only part of the access fails it in every mode.
  With the 4-byte grain an NA4 entry or a TOR boundary can split an
  8-byte load, store, AMO, 64-bit vector element or PTE access; the core
  checked only the first word, so such an access passed or failed by
  that word alone, and always passed in M-mode. Found by the random
  privileged program (5 of 8 seeds: Spike faults an M-mode `ld` of a
  PTE that a TOR top splits). Fixed in `3ae351d`; the new core test
  `pmp_partial_directed` fails on the earlier RTL, and `vec_trap_directed`
  test 11, which set up its buffer with M-mode stores across such a
  boundary, was corrected (`37aa1d7`)
  ([evidence](evidence/riscv-dv-8-2026-10-22/critic/pmp-partial-match.txt)).
- Trace probe: vector registers were logged after a younger vector load
  had overwritten them (false `vslide1down.vx` mismatches); fixed in
  `862868c` (simulation only).
- Harness: pygen out-of-memory kills when ten `riscv_amo_test`
  generations ran at once (round 1; memory budget, `d02176b`; the amo
  estimate is 10 GiB since round 2 peaked at 9,231 MiB); Spike's
  `--instructions` budget is charged up to 5,000 per trap (per-test
  `spike_max_instr`, `a397c78`); Spike's CLINT raises MTIP after reset
  (`sigil_priv_test` sets mtimecmp to the maximum).
- Comparator: a vector register write logged by one side only was not
  compared (`34ddf8e`).
- LR/SC of different widths (`lr.w` then `sc.d` to the same address):
  Sigil's SC fails (its reservation covers exactly the LR's 4 bytes),
  Spike's succeeds. Both are allowed: the SC may only succeed if the
  reservation set contains the bytes it writes, and the reservation
  set's extent is implementation-defined. pygen picks the LR and SC
  widths independently (so does the SV generator); patch R pairs them
  so the regression only checks architecturally defined outcomes. Seen
  in a 300-instruction smoke run of `riscv_amo_test` seed 3 before the
  patch
  ([compare report](evidence/riscv-dv-8-2026-10-22/lrsc-width-mismatch-compare.txt)).
- Delegation: Sigil keeps instruction/load/store access faults in M
  (its `medeleg` write mask), Spike can delegate them; `mideleg` bit 12
  (SGEIP) reads one on Spike and zero on Sigil (GEILEN = 0). Both are
  the implementation's choice: `sigil_priv_test` delegates only what
  both can, and the comparator ignores that one `mideleg` bit
  ([evidence](evidence/riscv-dv-8-2026-10-22/critic/priv/program-bringup.txt)).
- Other implementation-defined behaviour the programs stay clear of:
  fractional LMUL with SEW > LMUL*ELEN (Sigil supports it, Spike sets
  `vill`), AVL between VLMAX and 2*VLMAX (the spec allows vl < VLMAX),
  `vfredusum` ordering, stride-0 and unordered-indexed stores with
  repeated addresses, `vstart` != 0 on arithmetic; speculative A-bit
  updates (A is preset; D, whose update must be exact, is random), the
  priority of misaligned against page and access faults, a failing SC
  to a page without write permission, imprecise FS dirtying, WFI in U,
  ASIDLEN, mixed Svnapot groups.

### Limits (what this regression does not check yet)

- Interrupts at a given time: `riscv_full_interrupt_test` needs
  interrupts raised at the same instruction on both sides (a lockstep
  flow), and `core_tb` has no CLINT or PLIC. Compared today: S-level
  interrupts made pending by `mip` writes (SSIP/STIP/SEIP), with random
  delegation and enables, taken after MRET/SRET or after the CSR write
  that enables them (`sigil_priv_test`).
- Address translation is exercised by the directed `sigil_priv_test`
  only: the generated tests run with satp Bare, so no random instruction
  stream runs under Sv39. Not covered: the H extension (two-stage
  translation), debug mode, random CSR accesses (`riscv_csr_test`),
  sub-programs, locked PMP entries, MPRV, PMP entry 0 in TOR mode.
  ACT, riscv-tests `-v-` and the directed core tests cover parts of
  these.
- V, Zba/Zbk*/Zkn/Zicond and HINTs come only from directed programs:
  random operands and (for V) random vtype/AVL, but a fixed instruction
  order; no vector traps (faulting elements, `vstart`) in them.
- The DUT trace does not log load addresses or implicit CSR updates
  other than `fflags` (trap entry, xRET, `vl`/`vtype`/`vstart`,
  `vxsat`, hardware A/D updates); a wrong implicit update shows up only
  when software reads it back (the RVV program reads the vector CSRs
  every iteration; the privileged program's handlers read
  cause/epc/tval/status and it reads every test PTE back).
- CI: the workflow has not run on GitHub yet (`workflow_dispatch` needs
  it on the default branch); its steps were replayed on sigil-verify.
