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
| **riscv-dv vs Spike** | random programs; every retired instruction compared with Spike | `make -C sim riscv-dv` (this page) |

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
pygen needs about 3 minutes for a 10,000-instruction program on a busy
c7i.8xlarge; the simulations take seconds.

Useful driver options: `--instr-cnt N` (override every test's
`+instr_cnt`, for quick runs), `--out DIR` (default
`build/riscv-dv/run`), `--keep` (keep Spike logs and DUT traces of
passing runs too), `--core-tb PATH` (e.g. a harness built with another
Verilator), `--max-cycles`, `--gen-timeout`, `--sim-timeout`.

### Results

`<out>/results.csv`, one row per (test, seed):

| Column | Meaning |
|---|---|
| `status` | `PASS`, `MISMATCH`, `DUT_TIMEOUT`, `DUT_FAIL`, `GEN_FAIL`, `SPIKE_FAIL` (below) |
| `first_divergence` | first differing record: index, pc, instruction, Spike's disassembly, and each differing field (`x: dut {...} ref {...}`, `store: ...`, `csr 0x300 (mstatus): ...`, `cause: ...`) |
| `ref_records`, `dut_records` | records compared (up to and including the `tohost` store) |
| `dut_cycles`, `gen_s`, `spike_s`, `dut_s` | core cycles to `tohost`, wall-clock seconds per step |
| `dir`, `asm`, `elf`, `spike_log`, `dut_trace`, `ref_csv`, `dut_csv`, `report` | artifacts of the run |

| Status | Meaning |
|---|---|
| `PASS` | traces match and both sides wrote `tohost` = 1 |
| `MISMATCH` | the core finished, but its trace diverges from Spike's |
| `DUT_TIMEOUT` | `core_tb` reached `--max-cycles` (or `--sim-timeout`); `first_divergence` says where the traces split, if they did |
| `DUT_FAIL` | `core_tb` reported a failing `tohost` value or crashed |
| `GEN_FAIL` | pygen or the assembler failed (`gen.out`, `gcc.out`) |
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

Generation is deterministic per seed (pygen seeds Python's `random`
from `--seed`), so a failing (test, seed) reproduces with
`TESTS=<test> SEEDS=<seed>`. The seed also seeds `core_tb`'s random bus
latency/backpressure (`--mem-lat 1:6 --mem-gap 2 --mem-ready 70
--mem-seed <seed>`, as in `make riscv-tests`).

### Pins and versions

| Item | Version |
|---|---|
| riscv-dv | chipsalliance/riscv-dv `0d71c2b666dec48dde0b804a2138426da56aa252` (master, 2026-09-21); cloned to `third_party/riscv-dv` (git-ignored, never modified) |
| Generator | riscv-dv's Python generator (pygen, `run.py --simulator pyflow` equivalent): no SystemVerilog simulator is available. Copied to `build/riscv-dv/gen` and patched with [`sim/riscv-dv/patches/pygen-sigil.patch`](../sim/riscv-dv/patches/pygen-sigil.patch) |
| Python | 3.12.3 (Ubuntu 24.04), venv `build/riscv-dv/venv` with [`sim/riscv-dv/requirements.txt`](../sim/riscv-dv/requirements.txt) (pyvsc 0.9.1.10086043874, pyboolector 3.2.4.20240823.1, pyucis 0.1.3.7162246580, PyYAML 6.0.3, bitstring 5.0.0, ...) |
| Spike | riscv-isa-sim master `2c300cd90eb74bb79f3fcdd58596a6f8d842d01c` (1.1.1-dev, 2026-10-21) with its `berkeley-softfloat-3` submodule at `32eb3295`, built into `~/opt/spike` on sigil-verify |
| Toolchain | `deps/` riscv64-unknown-elf GCC 16.1.0 (`g6afcc4f6d`), binutils 2.47 (`scripts/install_deps.sh --gcc15`) |
| DUT simulator | Verilator 5.048 (`deps/`); the trace probe also lints and builds with 5.044 (macOS) and 5.020 (Ubuntu apt, CI) |

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
| Zba, Zbb/Zbs RV64 W forms, Zbkb (rest), Zbkc, Zbkx, Zkne, Zknd, Zknh, Zicond | no | not in pygen; covered by the directed `sigil_bitmanip_crypto_test` |
| RVV 1.0 Zve64d, VLEN 512 | no | pygen has no vector instruction classes; covered by the directed `sigil_vector_test` |
| H | no | not in pygen |
| M/S/U | yes | all three boot modes |
| Sv39 (+Svnapot) | no (`SATP_MODE = BARE`) | pygen cannot build page tables (`create_page_table` is a TODO upstream) |
| PMP, 16 entries, G=0 | opened, not tested | pygen's PMP setup is a TODO; [`user_init.s`](../sim/riscv-dv/user_extension/user_init.s) opens entry 0 (NAPOT, RWX, whole PA space) so S/U code can run |
| misaligned loads/stores trap | yes | `riscv_unaligned_load_store_test`; the generated handler skips the access |
| read-only `misa` | yes | `MISA_VALUE` (patch C) makes the generator write Sigil's value, which Spike (writable misa) keeps |
| CSRs | init only | free-running counters (cycle/time/instret) are left out of `implemented_csr`: they differ between RTL and an ISS by construction. pygen's random CSR instruction never constrains the CSR address, so random CSR instructions stay off (as in upstream pygen) |

pygen at this pin is a partial port of the SV generator and has bugs
that stop generation or make programs wrong. The setup applies fixes A
to S, each described in the
[patch header](../sim/riscv-dv/patches/pygen-sigil.patch): Python 3.12
(`imp`), wrong `randrange` bounds, enum/string mix-ups in instruction
selection (the AMO stream drew from every instruction), the AMO/LR/SC
register constraints, the loop stream (counter update and branch were
unconstrained, so loops need not terminate) and its instruction mixing,
the load/store streams (offsets the encodings cannot hold, `la zero`,
addresses off by one), a hang when a generator error happens inside a
multiprocessing worker, the B-extension enable, and same-width LR/SC
pairs. Without these, every test with a load/store stream fails to
assemble at 10,000 instructions. Sub-programs (the
call stack) are not implemented in pygen at all: every test runs with
`+num_of_sub_program=0`.

### Reference model configuration (Spike)

```
spike --isa=rv64imafdcbvh_zicsr_zifencei_zicntr_zbc_zbkb_zbkc_zbkx_zkne_zknd_zknh_zicond_zcb_zvl512b_svnapot \
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
| misaligned loads/stores trap | no `zicclsm` in the ISA string (Spike emulates misaligned accesses only with it) |
| WFI completes like a NOP | `--wfi-as-nop` |
| RAM at `0x8000_0000` | Spike's default 2 GiB at `0x8000_0000`; programs are linked there (riscv-dv `scripts/link.ld`) and `core_tb` loads ELF segments at their physical addresses. Spike's boot ROM (5 instructions at `0x1000`) is skipped by the comparison, which starts at the ELF entry |

### DUT trace (simulation only)

`rtl/core/sigil_core.sv` ends with a block under `` `ifndef SYNTHESIS ``
that writes the trace when the simulation gets `+sigil_trace=<file>`
(`core_tb` passes plusargs through). Synthesis never sees it, nothing in
it feeds back into the design, and without the plusarg it writes
nothing. One line per retired instruction or trap:

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
- `v`: whole 512-bit vector registers the instruction wrote (from a
  shadow of every VRF write).

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
  writes are compared field by field (Spike logs the fields);
- vector registers: compared where both logged the register;
- traps: cause, epc and tval;
- Spike's trace is cut after its first store to `tohost`; the DUT trace
  must contain exactly the same records up to that point.

The comparator was checked against corrupted DUT traces (a dropped
record, a changed store value, a changed privilege): each is reported as
`MISMATCH` at the right record.

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

Supported (18 generated + 2 directed):

| Test | Source list | Notes |
|---|---|---|
| `riscv_arithmetic_basic_test` | base | M-mode, no load/store/branch |
| `riscv_rand_instr_test` | base | load/store, loop, hazard and jal streams |
| `riscv_jump_stress_test` | base | `riscv_jal_instr` x20 |
| `riscv_loop_test` | base | `riscv_loop_instr` x20 (needs patches O/P) |
| `riscv_no_fence_test` | base | pygen never emits FENCE in random streams anyway |
| `riscv_illegal_instr_test` | base | 5 illegal instructions per 1000 |
| `riscv_ebreak_test` | base | breakpoint exceptions (needs patch E) |
| `riscv_unaligned_load_store_test` | base | misaligned accesses trap |
| `riscv_mmu_stress_test` | base | load/store stress in a random boot mode; satp Bare |
| `riscv_machine_mode_rand_test` | rv64gc | |
| `riscv_privileged_mode_rand_test` | rv64gc | random boot mode |
| `riscv_u_mode_rand_test` | rv32imc_sv32 | U-mode |
| `riscv_non_compressed_instr_test` | rv32imc | assembled without C/Zcb |
| `riscv_amo_test` | rv64gc | LR/SC and AMO streams (needs patches G-M, R) |
| `riscv_floating_point_arithmetic_test` | rv64gc | F/D, M-mode |
| `riscv_floating_point_rand_test` | rv64gc | |
| `riscv_floating_point_mmu_stress_test` | rv64gc | satp Bare |
| `riscv_b_ext_test` | rv32imcb | ratified subset of draft B |
| `sigil_bitmanip_crypto_test` | Sigil, directed | Zba/Zbb/Zbs W forms, Zbkb/c/x, Zkn, Zicond |
| `sigil_vector_test` | Sigil, directed | RVV e8/e32/e64, LMUL 1/2/8, masks, FP, reductions |

Excluded (18), with the reason recorded in the test list:

| Test | Reason |
|---|---|
| `riscv_rand_jump_test` | jumps among sub-programs; pygen has none |
| `riscv_ebreak_debug_mode_test` | debug mode: Sigil has none, pygen's debug ROM is a TODO |
| `riscv_full_interrupt_test` | needs interrupts raised at the same instruction on the core and on Spike (riscv-dv's UVM irq agent); `core_tb` raises them at a cycle, Spike's CLINT counts instructions. Needs a lockstep flow |
| `riscv_csr_test` | `gen_csr_test.py` needs a per-field CSR description of Sigil; upstream runs it RTL-only (`no_iss`) |
| `riscv_pmp_test` | pygen's PMP configuration (`riscv_pmp_cfg`, `+pmp_*`) is not ported; PMP is covered by ACT |
| `riscv_hint_instr_test`, `riscv_rand_test` (ml) | pygen's HINT generation fails to solve for every seed tried |
| `riscv_misaligned_instr_test` | for IALIGN=32 cores; with C no misaligned-fetch exception can occur |
| `riscv_invalid_csr_test` | pygen's CSR instruction does not constrain the address; random addresses hit the counters |
| `riscv_sfence_exception_test` | pygen never emits SFENCE.VMA in random streams |
| `riscv_page_table_exception_test` | no page tables in pygen (upstream runs it with 0 iterations) |
| `riscv_vector_*` (4 tests) | no vector instructions in pygen; see `sigil_vector_test` |
| `riscv_zbb_zbt_test` | Zbt is not ratified; Sigil does not implement it |
| `riscv_load_store_shared_mem_test`, `riscv_single_hart_test` | multi-hart target; Sigil is single-hart |

### Findings

- LR/SC of different widths (`lr.w` then `sc.d` to the same address):
  Sigil's SC fails (its reservation covers exactly the LR's 4 bytes),
  Spike's succeeds. Both are allowed: the SC may only succeed if the
  reservation set contains the bytes it writes, and the reservation
  set's extent is implementation-defined. pygen picks the LR and SC
  widths independently (so does the SV generator); patch R pairs them
  so the regression only checks architecturally defined outcomes. Seen
  once in a 300-instruction smoke run of `riscv_amo_test` seed 3 before
  the patch.
- Regression results and anything they find are recorded in
  `docs/evidence/riscv-dv-*` (index in
  [`evidence/README.md`](evidence/README.md)).

### Limits (what this regression does not check yet)

- No address translation, no PMP programming, no interrupts, no
  sub-program calls, no random CSR accesses, and no V/Zk/Zicond/H in
  the generated programs (pygen limits above; the last three are
  covered by the two directed programs only).
- The DUT trace does not log load addresses or implicit CSR updates
  other than `fflags`; a wrong implicit update shows up only when
  software reads the CSR.
- Not in CI yet: the flow needs Spike and a Python venv with pyvsc and
  pyboolector, and a full run takes tens of minutes. Issue #8's
  "nightly/manual CI first" step is still open.
