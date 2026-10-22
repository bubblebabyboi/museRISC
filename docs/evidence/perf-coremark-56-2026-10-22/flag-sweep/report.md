# Sigil performance report

- Date (UTC): 2026-10-22T09:43:35Z
- Commit: `320cf57ed828aab9e7c9c3082dcd4942a0fe6da3` (56-perf-coremark); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Host: ip-172-31-65-164 Linux 7.0.0-1014-aws x86_64
- Memory model `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`
- Repeats: 1
- Image `coremark-O3`: sha256 `a13d684e7a8973c5`, scalar ISA, OPT=-O3
- Image `coremark-O3-unroll`: sha256 `1b0cb0930e2e9777`, scalar ISA, OPT=-O3 -funroll-loops
- Image `coremark-Os`: sha256 `bd042bef73ba05f1`, scalar ISA, OPT=-Os
- Image `coremark-scalar`: sha256 `c56fb68ce74d117d`, performance seeds 0,0,0x66; scalar ISA -march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh

## Configurations (as reported by the counter records)

| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |
|---|---|---|---|---|---:|---:|---:|
| default | soc | `soc_rtl_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| coremark [O3] | default | soc | 20 | 17,062,942 | 5,423,950 | 0.318 | 3.146 | 853,147.1 | 1.172 CoreMark/MHz | 17,062,913 |
| coremark [O3-unroll] | default | soc | 20 | 17,291,002 | 5,446,598 | 0.315 | 3.175 | 864,550.1 | 1.157 CoreMark/MHz | 17,290,964 |
| coremark [Os] | default | soc | 20 | 20,238,586 | 6,557,699 | 0.324 | 3.086 | 1,011,929.3 | 0.988 CoreMark/MHz | 20,238,556 |
| coremark [scalar] | default | soc | 20 | 14,337,806 | 5,246,413 | 0.366 | 2.733 | 716,890.3 | 1.395 CoreMark/MHz | 14,337,777 |

## Where the cycles go (% of cycles in the measured region)

| Category | coremark[O3] default/soc | coremark[O3-unroll] default/soc | coremark[Os] default/soc | coremark[scalar] default/soc |
|---|---:|---:|---:|---:|
| retire (base) | 31.8 | 31.5 | 32.4 | 36.6 |
| fetch: I$ hit latency / issue gap | 41.8 | 41.9 | 43.0 | 40.4 |
| fetch: 32-bit instr straddles a word | 11.5 | 12.8 | 9.2 | 5.4 |
| fetch: I$ miss | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: taken branch | 3.1 | 2.5 | 3.1 | 4.1 |
| squashed: jal | 0.3 | 0.3 | 1.6 | 0.5 |
| squashed: jalr | 0.2 | 0.1 | 0.6 | 0.2 |
| load-use interlock | 0.6 | 0.2 | 0.1 | 0.7 |
| EX: M unit (mul/div) | 2.2 | 2.2 | 1.9 | 2.6 |
| MEM: D$ hit latency | 8.6 | 8.5 | 8.0 | 9.5 |
| MEM: D$ miss | 0.0 | 0.0 | 0.0 | 0.0 |

## Events

| Event | coremark[O3] default/soc | coremark[O3-unroll] default/soc | coremark[Os] default/soc | coremark[scalar] default/soc |
|---|---:|---:|---:|---:|
| retired alu (% of instret) | 48.1 | 48.2 | 45.4 | 47.9 |
| retired load (% of instret) | 20.9 | 20.8 | 19.5 | 20.6 |
| retired store (% of instret) | 6.2 | 6.2 | 5.3 | 5.4 |
| retired branch (% of instret) | 19.3 | 19.2 | 19.6 | 20.1 |
| retired jal (% of instret) | 1.5 | 1.5 | 5.4 | 1.6 |
| retired jalr (% of instret) | 0.5 | 0.5 | 2.0 | 0.8 |
| retired mul (% of instret) | 3.5 | 3.5 | 2.9 | 3.6 |
| retired csr (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 |
| compressed (RVC, % of instret) | 50.7 | 31.7 | 54.3 | 51.4 |
| taken branches (% of branches) | 58.9 | 57.5 | 57.8 | 58.6 |
| redirects per 1000 instr | 134.2 | 131.0 | 187.0 | 141.9 |
| squashed wrong-path instr | 600,885 | 504,808 | 1,079,457 | 683,136 |
| I$ fetch accesses per instr | 1.501 | 1.512 | 1.485 | 1.297 |
| I$ misses (per 1000 instr) | 49 (0.009) | 290 (0.053) | 25 (0.004) | 39 (0.007) |
| D$ loads / stores | 1,132,607 / 335,764 | 1,135,527 / 338,684 | 1,276,284 / 345,282 | 1,082,027 / 283,065 |
| D$ misses (% of accesses) | 10 (0.0) | 10 (0.0) | 10 (0.0) | 11 (0.0) |
| D$ write-backs | 0 | 0 | 0 | 0 |
| uncached D accesses | 0 | 0 | 0 | 0 |
| bus transactions (I fill / D fill / D wb / uncached) | 49/10/0/0 | 290/10/0/0 | 25/10/0/0 | 39/11/0/0 |
| bus busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 |
| bus waiting on memory (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 |
| M unit busy (% of cycles) | 2.2 | 2.2 | 1.9 | 2.6 |
| FPU busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 |
| vector unit busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 |
| vector LS in MEM (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 |
| traps (exceptions / interrupts) | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

