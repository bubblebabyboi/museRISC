# Sigil performance report

- Date (UTC): 2026-10-22T10:51:49Z
- Commit: `320cf57ed828aab9e7c9c3082dcd4942a0fe6da3` (56-perf-coremark); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Host: ip-172-31-65-164 Linux 7.0.0-1014-aws x86_64
- Memory model `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`
- Repeats: 2; deterministic: yes (identical counts)
- Image `coremark-scalar`: sha256 `7c50d3fccc16ad26`, performance seeds 0,0,0x66; scalar ISA -march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
- Image `coremark-validation`: sha256 `fbb0d2f1ac92ac4c`, validation seeds 0x3415,0x3415,0x66 (EEMBC run rule 2), scalar ISA; a correctness run, not the score

## Configurations (as reported by the counter records)

| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |
|---|---|---|---|---|---:|---:|---:|
| default | soc | `soc_rtl_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| coremark [scalar] | default | soc | 1000 | 716,834,078 | 262,309,888 | 0.366 | 2.733 | 716,834.1 | 1.395 CoreMark/MHz | 716,834,049 |
| coremark [validation] | default | soc | 1000 | 718,245,526 | 262,700,093 | 0.366 | 2.734 | 718,245.5 | 1.392 CoreMark/MHz | 718,245,497 |

## Where the cycles go (% of cycles in the measured region)

| Category | coremark[scalar] default/soc | coremark[validation] default/soc |
|---|---:|---:|
| retire (base) | 36.6 | 36.6 |
| fetch: I$ hit latency / issue gap | 40.5 | 40.4 |
| fetch: 32-bit instr straddles a word | 5.4 | 5.4 |
| fetch: I$ miss | 0.0 | 0.0 |
| squashed: taken branch | 4.1 | 4.1 |
| squashed: jal | 0.5 | 0.5 |
| squashed: jalr | 0.2 | 0.2 |
| load-use interlock | 0.7 | 0.7 |
| EX: M unit (mul/div) | 2.6 | 2.6 |
| MEM: D$ hit latency | 9.5 | 9.6 |
| MEM: D$ miss | 0.0 | 0.0 |

## Events

| Event | coremark[scalar] default/soc | coremark[validation] default/soc |
|---|---:|---:|
| retired alu (% of instret) | 47.9 | 47.8 |
| retired load (% of instret) | 20.6 | 20.8 |
| retired store (% of instret) | 5.4 | 5.4 |
| retired branch (% of instret) | 20.1 | 20.1 |
| retired jal (% of instret) | 1.6 | 1.6 |
| retired jalr (% of instret) | 0.8 | 0.8 |
| retired mul (% of instret) | 3.6 | 3.6 |
| retired csr (% of instret) | 0.0 | 0.0 |
| compressed (RVC, % of instret) | 51.4 | 51.5 |
| taken branches (% of branches) | 58.6 | 58.5 |
| redirects per 1000 instr | 141.9 | 141.7 |
| squashed wrong-path instr | 34,154,948 | 33,890,983 |
| I$ fetch accesses per instr | 1.297 | 1.298 |
| I$ misses (per 1000 instr) | 39 (0.000) | 39 (0.000) |
| D$ loads / stores | 54,098,959 / 14,151,417 | 54,552,487 / 14,056,985 |
| D$ misses (% of accesses) | 11 (0.0) | 11 (0.0) |
| D$ write-backs | 0 | 0 |
| uncached D accesses | 0 | 0 |
| bus transactions (I fill / D fill / D wb / uncached) | 39/11/0/0 | 39/11/0/0 |
| bus busy (% of cycles) | 0.0 | 0.0 |
| bus waiting on memory (% of cycles) | 0.0 | 0.0 |
| M unit busy (% of cycles) | 2.6 | 2.6 |
| FPU busy (% of cycles) | 0.0 | 0.0 |
| vector unit busy (% of cycles) | 0.0 | 0.0 |
| vector LS in MEM (% of cycles) | 0.0 | 0.0 |
| traps (exceptions / interrupts) | 0 / 0 | 0 / 0 |

