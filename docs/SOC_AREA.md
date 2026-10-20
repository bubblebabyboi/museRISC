# SoC area and timing estimate (synthesis, 2026-10-16)

This is ORFS synthesis of the whole `muserisc_soc_top`: the core with
the element-serial vector unit (FP on the shared multi-cycle FPU,
#47), the multi-cycle M unit, the L1 I$/D$ with bus arbiter (#44), the
SoC fabric, CLINT/PLIC/UART/boot ROM and crypto.

The numbers were measured on the development tree
(CantelopePeel/museRISC at b634ffc). That tree is this stack plus the
CSR VLMAX shift and PLIC tournament tree (#45), the PLIC spec fixes
(#48, 3-bit priorities) and the AES S-box rework (#35). Without #45,
this stack still has the 64-bit VLMAX divider in the CSR (~40 ns on
Nangate45) and a larger PLIC; see "Timing findings".

Every large array is an SRAM macro, 15 per SoC:

| Array | Count | Nangate45 macro | sky130hd macro |
|---|---:|---|---|
| VRF bank (256×64 1R1W) | 3 | `fakeram45_256x64_1r1w` (generated) | `sky130_sram_1rw1r_64x256_8` |
| L1 data way (512×64 1RW) | 6 | `fakeram45_512x64` (stock) | `sky130_sram_1rw1r_128x256_8`, used as 256×128 |
| L1 tag way (64×44 1RW) | 6 | `fakeram45_64x44` (generated) | `sky130_sram_1rw1r_44x64_8` |

These are post-synthesis numbers: no placement, no timing repair,
and delays from the liberty wire-load model. They are meant for the
chip-size decision, not for signoff.

Evidence: [`evidence/soc-sram-synth-2026-10-16.log`](evidence/soc-sram-synth-2026-10-16.log).

## Results

Flat synthesis (the ORFS default) gives the totals. A second,
hierarchical run (`SYNTH_HIERARCHICAL=1`) gives the per-module split;
it keeps module boundaries, so it comes out 1–4 % larger.

Both flows read the RTL with `-D SYNTHESIS`, so simulation-only
checks are dropped. ORFS passes that define itself, and the configs
repeat it.

| | Nangate45 | sky130hd |
|---|---:|---:|
| Std-cell area | 0.504 mm² (504,350 µm²) | 2.364 mm² (2,364,368 µm²) |
| SRAM macros (15) | 0.158 mm² (158,051 µm²) | 6.225 mm² (6,225,284 µm²) |
|   VRF banks (3) | 38,473 µm² | 1,258,388 µm² |
|   L1 data ways (6) | 103,809 µm² | 4,332,656 µm² |
|   L1 tag ways (6) | 15,769 µm² | 634,240 µm² |
| Total synthesized area | 0.662 mm² | 8.590 mm² |
| Cells (incl. macros) | 296,459 | 260,033 |
| Flip-flops | 26,447 | 26,453 |
| **Fmax (unrepaired, wire-load)** | **162 MHz** (6.19 ns) | **12.3 MHz** (81.4 ns) |
| Limiting path | `vls_started_q` → vector unit `cnt_ok_q` | VRF OpenRAM `dout1`, launched on the falling edge → FPU operand enable: 0.38 ns clk→q + 38.38 ns logic + 1.42 ns setup + 0.5 ns uncertainty = half the period |
| Fmax with only the 3 VRF macro outputs registered | (same) | **18.4 MHz** (54.3 ns): D$ tag-way OpenRAM `dout0` (falling edge) → same FPU enable, 24.9 ns of logic in half a cycle |
| Fmax with all 15 macro outputs registered | (same) | **23.0 MHz** (43.5 ns): `vls_started_q` → FPU operand enable, full cycle |
| Yosys wall time / peak RSS (whole make) | 1 h 23 min / 2.68 GB | 1 h 08 min / 2.71 GB |

Fmax is found by bisecting the clock period in OpenSTA, which is the
`min_period_*` lines of `sta_synth.tcl`. A period-minus-WNS figure
is wrong once a path starts at a falling-edge macro output, whose
budget is half the period.

**The sky130 fmax is set by the OpenRAM half-cycle read paths.**
- Registering only the VRF outputs (a VRF read pipeline stage)
  leaves the L1 macros' half-cycle paths, which give 18.4 MHz.
- About 23 MHz needs all 15 macro outputs registered, which costs one
  more cycle of latency on VRF reads and on cache hits.

These are unrepaired wire-load numbers, and one gate dominates. Both
FPU-enable paths go through a single `sky130_fd_sc_hd__a2111oi_0`
that drives 145 loads unbuffered, and it alone is 22.4 ns of the
38.4 ns. That is an artefact of the unrepaired netlist (repair would
buffer or upsize it), so these fmax figures mostly reflect fanout,
not logic depth.

On Nangate45 every block has at least 3.8 ns of slack at 100 MHz.

The sky130 column comes from a direct sky130hd synthesis run (the
platform and the OpenRAM macros ship in `openroad/orfs:latest`), not
from scaling:
- Std-cell area scales 4.69× from Nangate45 to sky130hd (flat runs).
- The macros do not scale that way: sky130 OpenRAM is 33–42× the
  fakeram45 area for the same array.
- So on sky130 the macros are 72 % of the synthesized area.

Where the Yosys time went: mostly in `abc` (Nangate45 4,084 s, sky130
3,179 s), with `extract_fa` at ~330 s, on a loaded host. The
hierarchical runs took ~28 min each at 2.2 GB.

### Area by module (hierarchical runs)

"Own" is the module's area excluding kept children. The sky130 run
keeps more modules. On Nangate45 the regfiles, ALU, decoder and RVC
are flattened into `muserisc_core`, SHA-256 into `muse_crypto_top`,
the L1 tag wrappers into the caches, and CLINT, UART, fabric and
arbiter into the top.

| Module | Nangate45 own (µm²) | sky130hd own (µm²) | Own flops (sky130 run) | Notes |
|---|---:|---:|---:|---|
| L1 data ways (6 × `muserisc_sram_sp`) | 6 × 17,735 | 6 × 724,923 | 6 × 66 | macro + read capture + half select |
| L1 tag ways (6 × `muserisc_sram_sp`) | ² | 6 × 107,366 | 6 × 45 | macro + read capture |
| VRF banks (3 × `muserisc_vrf_bank`) | 3 × 13,252 | 3 × 421,852 | 3 × 65 | macro + read capture |
| `muserisc_vec` | 62,231 | 287,563 | 1,645 | element-serial vector unit; FP on the shared FPU; VRF write combining |
| `muserisc_csr` | 57,009 | 268,990 | 3,063 | |
| `muserisc_mmu` | 65,119 | 304,394 | 4,557 | TLBs + walker |
| `muserisc_fpu` | 51,448 | 244,190 | 1,391 | multi-cycle FPU, shared by scalar and vector |
| `muserisc_core` pipeline | 95,212 ³ | 203,206 | 2,730 | |
| `muserisc_fpregfile` / `regfile` | ³ | 106,162 / 96,927 | 2,048 / 2,048 | 32×64 flops each |
| `muserisc_alu`, `decoder`, `rvc` | ³ | 31,051 | 0 | |
| `muserisc_muldiv_mc` | 39,147 | 183,755 | 276 | multi-cycle M unit |
| `muserisc_bext` | 27,565 | 139,955 | 0 | bit-manip / scalar crypto |
| `muserisc_vregfile` logic | 5,177 | 27,850 | 707 | v0 shadow + full-word collision bypass |
| `muserisc_dcache` logic | 26,805 ² | 69,953 | 1,299 | |
| `muserisc_icache` logic | 9,221 ² | 16,638 | 270 | |
| `ec_field` | 43,708 | 197,387 | 1,291 | crypto field unit |
| `sha256_block` | ⁴ | 159,156 | 2,569 | |
| `muse_crypto_top` + bridge | 45,895 ⁴ | 49,926 | 1,098 | |
| `muserisc_plic` | 5,181 | 23,930 | 198 | 32 sources, tournament tree, 3-bit priorities |
| fabric, arbiter, CLINT, UART, boot ROM, top | 9,334 | 41,690 | 639 | |
| **Total** | **689,218** | **8,712,018** | **26,690** | |

² The Nangate45 D$ / I$ rows include their 4 / 2 tag ways
(macros 4 / 2 × 2,628 µm²). ³ The Nangate45 "pipeline" row includes
the regfiles, ALU, decoder and RVC. ⁴ The Nangate45
`muse_crypto_top` row includes SHA-256.

## SRAM mapping

`muserisc_vrf_bank` (one 256×64 replica per VRF read port, every write
to all three) and `muserisc_sram_sp` (L1 data and tag ways) keep their
behavioural models by default. Two defines, set only by the ORFS
configs, select macro instances: `MUSERISC_SRAM_FAKERAM45` for
nangate45 and `MUSERISC_SRAM_SKY130` for sky130hd. `muserisc_sram_sp`
maps only the two L1 geometries, 512×64 with 8 lanes and 64×44 with
1 lane; any other geometry, such as the small cache unit-test
configurations, stays behavioural. Both ORFS configs read the same
RTL list, `rtl/muserisc_soc_files.mk`.

**Nangate45.** ORFS ships only single-port (1RW) fakeram45 views.
- **VRF banks:** ORFS has no 1R1W view and no 256×64 size, so
  `flow/designs/nangate45/muserisc_soc/sram/gen_fakeram45_1r1w.py`
  generates LEF/Liberty/Verilog views of a 256×64 1R1W macro in the
  fakeram45 style.
  - Footprint 134.71 × 95.20 µm = 12,824 µm². A 256×64 1RW macro
    interpolated between fakeram45_256x48 and 256x96 is ~9,751 µm²;
    ×1.3 for the dual-port bit cell and second decoder gives
    12,677 µm²; that is rounded up 1.2 % to a site- and row-aligned
    footprint.
  - Clk→q 0.27 ns on the rising edge.
- **L1 data ways:** the stock `fakeram45_512x64` (1RW, per-bit mask).
- **L1 tags:** the same script (`--ports 1rw`) generates
  `fakeram45_64x44`. Its footprint, 46.93 × 56.0 µm = 2,628 µm²,
  interpolates the stock 64x32 and 64x62 by width.
- **Write masks:** the wrappers drive each byte or lane enable onto
  the per-bit mask.

**sky130hd.** The OpenRAM macros prebuilt in ORFS's `sky130ram`, all
1RW+1R with a byte write mask and active-low selects:
- **VRF banks:** `sky130_sram_1rw1r_64x256_8`. Port 0 writes, port 1
  reads.
- **L1 data ways:** ORFS has no 512×64 single-port macro. Each way
  uses `sky130_sram_1rw1r_128x256_8` as 256×128: address bit 0
  selects the 64-bit half through the upper or lower 8 mask lanes on
  writes and a registered half select on reads. Port 1 is unused.
- **L1 tags:** `sky130_sram_1rw1r_44x64_8` (port 0 only).

**Read hold.** Neither macro family holds its read data.
- OpenRAM sets `dout` to X on every rising edge and reloads it on the
  falling edge only when that port reads; the .lib `dout` arcs are
  `falling_edge`.
- fakeram returns X after a non-read edge.

The RTL contracts expect held data: the VRF holds while `re` is low,
and `muserisc_sram_sp` holds until the next read. So every macro
wrapper has a capture register: `rd_q` marks a read in the previous
cycle, `hold_q` takes the macro output in the cycle after a read, and
`rdata = rd_q ? macro_out : hold_q`. Latency is unchanged.

The vector unit depends on the hold: without it, both macro families
fail the vector TB.

The caches do not depend on it today. Every reader of
`muserisc_sram_sp` data samples it exactly one cycle after the read,
and the full directed suite passes without the register. It is kept
anyway, so that `muserisc_sram_sp` has the same documented hold
contract in every build, and a later cache change cannot break only
on silicon. The cost:
- 666 flops: 6 × 66 + 6 × 45, counting `rd_q` and the half select.
- About 0.027 mm² on sky130 (1.1 % of std cells) and ~4,000 µm² on
  Nangate45.
- One 2:1 mux (a few hundred ps) on the L1 half-cycle `dout0` path,
  which is the limit once the VRF outputs are registered.

**Half-cycle paths on sky130.** OpenRAM read data arrives ~0.3–0.4 ns
after the falling edge. So everything from `dout` through the capture
mux to the first flop gets half a clock period, and the period must be
at least 2 × (clk→q + logic + setup + uncertainty).
- The VRF read into the FPU operand enables is 38.4 ns of logic,
  which gives 12.3 MHz.
- The L1 tag read into the same enables is 24.9 ns, which gives
  18.4 MHz once the VRF outputs are registered.

A full cycle would need a read pipeline stage (one more cycle of
latency) or a macro with rising-edge output.

**Same-address read and write.** OpenRAM documents a read and a write
of the same address in the same cycle as unsupported; the vendor model
prints a warning. So the design never issues one to a macro.

- **VRF** (the only dual-port macro use). The vector unit issues
  ~136 k same-row read+write cycles in the vector TB. Almost all of
  them are a port-C read of the old vd word while S3 writes the
  previous element into that word, which used to be a partial
  (byte-masked) write. Two changes, both in the RTL every build
  simulates:
  1. **Write combining** in `muserisc_vec`. Element writes become
     full-word writes (`wbe = FF`) whenever S3 knows the whole current
     word. That is the case when the previous S3 write was a full-word
     write of the same row, or when the element's own port-C read was
     of that row and no write touched the row since. That read is
     tracked through S1/S2 and invalidated by any write to the row
     (defensive today; see the mutations below).
     A read that collides with a full-word write is not sent to the
     replica. `muserisc_vregfile` returns the write data instead (a
     full-word, write-first bypass) and holds it like a read.
  2. **Retry.** A read that would collide with a partial write is not
     issued; S0 or the gather issue retries it the next cycle. The
     write is older, so S3 drains and the retry cannot deadlock.

  The core's vector load/store sequencer never reads and writes in the
  same cycle. `muserisc_vregfile` asserts (in simulation, every build)
  that no read ever collides with a partial write.

  In the vector TB:
  - all 136,168 collisions hit full-word writes (array not read);
  - 12 cycles were retries;
  - 375,165 of 378,358 element writes were full-word;
  - the cycle count went from 13,232,156 to 13,232,168 (+12).

  With combining disabled (retry only) it is +1.07 % overall, and
  ~+48 % on single-cycle integer ops. The added hardware is 164 flops
  in `muserisc_vec`, while `muserisc_vregfile` loses 24 bypass flops.
- **L1 arrays:** single-port use (OpenRAM port 1 tied off, fakeram45
  1RW), so a read and a write can never coincide.
- **fakeram45 1R1W (Nangate45 VRF):** same RTL, so the same guarantee
  applies. Its generated model also returns whole-word garbage for a
  same-address read and write.

**Signoff assumption (sky130).**
- The OpenRAM `.lib` has only a falling-edge arc on `dout`: no
  rising-edge invalidation or min-delay arc.
- So no STA checks that `dout` stays valid past the rising edge at the
  flops that sample it there: the capture register and, in the cycle
  after a read, every downstream consumer.
- The design assumes the macro's clk→dout-invalid delay exceeds those
  flops' hold time plus clock skew. This must be confirmed with the
  macro's characterization, or a timed gate-level simulation, at
  signoff.
- In zero-delay RTL simulation the vendor model's blocking posedge
  `dout = 'bx` races the capture flop.
  `flow/designs/sky130hd/muserisc_soc/sram/vendor_model_check.sh`
  reproduces both cases:
  - with `dout <= 'bx` (the assumption): PASS;
  - `--as-shipped`: FAIL.

**Simulation.** `make -C sim srammacro` (part of `make core-test`)
builds each macro family's behavioural models and runs:
- the vector unit TB;
- every directed core test on `muserisc_cpu`, with the real cache
  geometry and random bus latency (36 runs);
- the RTL SoC crypto firmware.

The models are
`flow/designs/nangate45/muserisc_soc/sram/*.v` (generated) and
`flow/designs/sky130hd/muserisc_soc/sram/gen_openram_models.py`. They
follow the vendor read behaviour:
- undefined data after a non-read edge (pseudo-random garbage, because
  2-state Verilator would turn X into 0);
- on sky130, data only after the falling edge;
- whole-word garbage for a same-address read and write on the
  dual-port macros, permanently, so any reliance on that mode fails
  `srammacro`.

An earlier revision of this change, whose bypass covered only the
written bytes, fails
the vector TB on these models: 566 failures on fakeram45 and 565 on
sky130. The current RTL passes.

Results are bit-exact, with cycle counts identical to the behavioural
build in every directed test, the SoC crypto run and OpenSBI.

Separate checks:
- Removing the VRF capture register fails the vector TB on both
  families.
- Breaking the sky130 half select fails the cache tests.
- Mutations of the collision handling, run on the sky130 models:
  - sending colliding reads to the macro → VEC TB FAIL (568 failures);
  - no write combining, retry only → PASS at +1.07 % cycles;
  - no retry → the partial-collision assertion fires;
  - ignoring the old-vd validity flag altogether (`w_cw_hit` on a row
    match alone, so slots that never read port C, such as a
    reduction's final write, merge into a stale word) → VEC TB FAIL
    (7 failures);
  - removing only the four write-invalidation clauses (the
    `s1_crow_hit` / `s2_crow_hit` terms) → PASS. They are unreachable
    today: within an instruction the S3 write rows never decrease, so
    a write landing on an element's old-vd row after its read is
    either the previous S3 write (a full-word comb hit, which has
    priority) or partial. A simulation-only check in `muserisc_vec`
    asserts that invariant. The clauses are kept as protection for a
    future non-monotonic writer.
- The vendor OpenRAM `.v` files themselves pass the vector TB (3
  X-randomization seeds) and the full directed suite.
  `vendor_model_check.sh` runs them, with the per-access `$display`s
  stripped and the posedge `dout = 'bx` made non-blocking (the
  signoff assumption above).
  - It keeps the vendor's same-address read/write WARNING and fails
    if it ever prints. The count is 0 for this design. With the
    colliding reads sent to the macro (mutation above) it is 136,168.
  - The vendor model itself returns the newly written data on such a
    collision, so it cannot catch the bug by value. That is why the
    `srammacro` models return whole-word garbage instead.

`make lint` lints the SoC under both defines.

**Memory guard.** With all 15 arrays on macros, no inferred memory
exceeds ORFS's default 4096-bit guard. The largest are the 32×64
int/FP regfiles and SHA-256 `w`, at 2048 bits each. So
`SYNTH_MEMORY_MAX_BITS` is no longer overridden: #38 set 16384 and
#44 set 32768.

## RTL fix needed for synthesis

The core loaded its reset PC from the `boot_pc_i` port under the async
reset (`pc_q <= boot_pc_i`). That is an async-load flop
(`$_ALDFFE_`), and neither library can map it, so ORFS failed
`check -assert` with 64 unmapped `pc_q` bits.

Now `pc_r` resets to 0, and an async-set `boot_q` flag selects
`boot_pc_i` until the first PC update. The architectural behaviour
and cycle counts are unchanged, provided `boot_pc_i` is a static
strap: it is now read combinationally until the first PC update
rather than sampled at reset, so it must be stable through that cycle
(see the SoC SDCs).

Follow-up: like every async-reset flop in the SoC, `boot_q` needs a
synchronized reset release, and `muserisc_soc_top` has no reset
synchronizer yet.

## Timing findings

These are pure synthesis results, before any repair, with delays from
the liberty wire-load model and no placement. The sky130hd numbers in
particular are pessimistic, so read them as relative depth rather
than as an achievable fmax.

1. **Earlier limiters are fixed on main.**
   - The vector FP element step (128 ns combinational `fp_eval`) went
     multi-cycle on the shared FPU in #47.
   - The CSR VLMAX divider (39 ns) became a shift in #45.
   - PLIC arbitration became a log-depth tree in #45.
2. **Nangate45: 162 MHz unrepaired.** The worst paths run from
   `vls_started_q` (vector load/store sequencing) into the vector
   unit and the D$ read capture, ~5.7 ns. Every block has at least
   3.8 ns of slack at 100 MHz (`u_vec` 3.84 ns).
3. **sky130hd: the OpenRAM half-cycle reads limit fmax.**

   | Registered macro outputs | Fmax | Limiting path |
   |---|---:|---|
   | none | 12.3 MHz | VRF read into the FPU operand enables |
   | the 3 VRF macros (VRF read pipeline stage) | 18.4 MHz | L1 tag read into the same enables |
   | all 15 macros | 23.0 MHz | full-cycle FPU-enable path |

   Most of the FPU-enable delay is one 145-fanout gate that repair
   would buffer.
4. **sky130hd full-cycle paths of 20 ns or more:** FPU result and
   status, vector scalar/FP result capture, and CSR (~32–45 ns). All
   are FPU-adjacent wide muxing.

## sky130 chip-size estimate (rough)

- **Synthesized (flat):** 2.36 mm² std cells + 6.23 mm² SRAM macros.
- **Placed std-cell region:** 3.9–4.7 mm² at 50–60 % utilization.
  Timing repair and CTS typically add another 0–20 %, giving
  3.9–5.7 mm².
- **Macros with a 40 µm halo:** ≈ 7.85 mm² in total.
  - VRF: 3 × 0.541 mm² = 1.62 mm².
  - L1 data: 6 × 0.870 mm² = 5.22 mm².
  - L1 tags: 6 × 0.167 mm² = 1.00 mm².
- **Core with caches ≈ 11.8–13.5 mm².** That is above Caravel's
  ~10 mm². Without the L1 arrays (VRF only, caches' logic kept) the
  figure is ~5.6–7.3 mm².

Assumptions: typical-corner libraries (sky130 tt 1.8 V / 25 °C);
utilization as in typical ORFS sky130hd designs (50–60 %); no IO
ring.

The prebuilt OpenRAM macros cost 22–38 µm² per bit, and the 6 L1 data
ways alone take 4.3 mm² synthesized and 5.2 mm² placed. The levers
are:
- smaller caches, e.g. 4 KiB + 4 KiB, which saves ~4 mm² placed;
- denser or fewer, larger macros: a custom OpenRAM single-port config
  instead of the 1rw1r ones, or DFFRAM;
- fewer VRF replicas (each 256×64 is 0.54 mm² placed).

On Nangate45 (for comparison, not a target) the same SoC is 0.66 mm²
synthesized and reaches 162 MHz before repair.

## Reproduce

```sh
DESIGN=muserisc_soc ./scripts/openroad_docker.sh synth                    # nangate45, flat
DESIGN=muserisc_soc PLATFORM=sky130hd ./scripts/openroad_docker.sh synth  # sky130hd, flat
DESIGN=muserisc_soc ./scripts/openroad_docker.sh "FLOW_VARIANT=hier SYNTH_HIERARCHICAL=1 synth"
# post-synthesis STA (inside the image, ORFS env loaded):
#   STA_LIBS="<std-cell lib> <macro libs>" STA_ODB=results/<plat>/muserisc_soc_top/base/1_synth.odb \
#   STA_SDC=results/<plat>/muserisc_soc_top/base/1_synth.sdc STA_PREFIXES="u_cpu/u_core/u_vec ..." \
#   openroad -exit -no_init designs/nangate45/muserisc_soc/sta_synth.tcl
# regenerate the generated macro views / models:
python3 flow/designs/nangate45/muserisc_soc/sram/gen_fakeram45_1r1w.py flow/designs/nangate45/muserisc_soc/sram
python3 flow/designs/nangate45/muserisc_soc/sram/gen_fakeram45_1r1w.py --ports 1rw --depth 64 --width 44 \
  --w 46.93 --h 56.0 --tcq 0.21 flow/designs/nangate45/muserisc_soc/sram
python3 flow/designs/nangate45/muserisc_soc/sram/gen_fakeram45_1r1w.py --ports 1rw --model-only \
  --depth 512 --width 64 flow/designs/nangate45/muserisc_soc/sram
python3 flow/designs/sky130hd/muserisc_soc/sram/gen_openram_models.py flow/designs/sky130hd/muserisc_soc/sram
# vendor OpenRAM models (needs docker + the ORFS image):
flow/designs/sky130hd/muserisc_soc/sram/vendor_model_check.sh [--as-shipped]
```

Each flat synthesis takes ~1 h on a loaded host, mostly in ABC.
Floorplan, placement and repair were not run; the numbers above stop
at synthesis.
