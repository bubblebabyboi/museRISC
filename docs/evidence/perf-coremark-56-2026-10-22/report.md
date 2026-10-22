# Sigil performance report

- Date (UTC): 2026-10-22T09:39:42Z
- Commit: `320cf57ed828aab9e7c9c3082dcd4942a0fe6da3` (56-perf-coremark); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Host: ip-172-31-65-164 Linux 7.0.0-1014-aws x86_64
- Memory model `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`
- Memory model `axi`: `--axi-lat 24:24 --axi-gap 0 --axi-ready 100 --uart-pop 100`
- Repeats: 2; deterministic: yes (identical counts)
- Image `coremark-scalar`: sha256 `c56fb68ce74d117d`, performance seeds 0,0,0x66; scalar ISA -march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
- Image `coremark-sdk`: sha256 `400c9a3ccba55f2a`, performance seeds 0,0,0x66; SDK default -march (with V)
- Image `coremark-validation`: sha256 `d0bf2ae1cf5c4d9b`, validation seeds 0x3415,0x3415,0x66 (EEMBC run rule 2), scalar ISA; a correctness run, not the score

## Configurations (as reported by the counter records)

| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |
|---|---|---|---|---|---:|---:|---:|
| default | axi | `fpga_top_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |
| default | soc | `soc_rtl_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| coremark [scalar] | default | axi | 20 | 14,339,056 | 5,246,413 | 0.366 | 2.733 | 716,952.8 | 1.395 CoreMark/MHz | 14,339,027 |
| coremark [scalar] | default | soc | 20 | 14,337,806 | 5,246,413 | 0.366 | 2.733 | 716,890.3 | 1.395 CoreMark/MHz | 14,337,777 |
| coremark [sdk] | default | axi | 20 | 14,573,757 | 5,238,336 | 0.359 | 2.782 | 728,687.8 | 1.372 CoreMark/MHz | 14,573,725 |
| coremark [sdk] | default | soc | 20 | 14,572,507 | 5,238,336 | 0.359 | 2.782 | 728,625.3 | 1.372 CoreMark/MHz | 14,572,475 |
| coremark [validation] | default | axi | 20 | 14,366,037 | 5,253,779 | 0.366 | 2.734 | 718,301.8 | 1.392 CoreMark/MHz | 14,366,008 |
| coremark [validation] | default | soc | 20 | 14,364,787 | 5,253,779 | 0.366 | 2.734 | 718,239.3 | 1.392 CoreMark/MHz | 14,364,758 |

## Where the cycles go (% of cycles in the measured region)

| Category | coremark[scalar] default/axi | coremark[scalar] default/soc | coremark[sdk] default/axi | coremark[sdk] default/soc | coremark[validation] default/axi | coremark[validation] default/soc |
|---|---:|---:|---:|---:|---:|---:|
| retire (base) | 36.6 | 36.6 | 35.9 | 35.9 | 36.6 | 36.6 |
| fetch: I$ hit latency / issue gap | 40.4 | 40.4 | 40.5 | 40.5 | 40.4 | 40.4 |
| fetch: 32-bit instr straddles a word | 5.4 | 5.4 | 5.9 | 5.9 | 5.4 | 5.4 |
| fetch: I$ miss | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: taken branch | 4.1 | 4.1 | 4.0 | 4.0 | 4.1 | 4.1 |
| squashed: jal | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 |
| squashed: jalr | 0.2 | 0.2 | 0.3 | 0.3 | 0.2 | 0.2 |
| load-use interlock | 0.7 | 0.7 | 0.7 | 0.7 | 0.7 | 0.7 |
| EX: M unit (mul/div) | 2.6 | 2.6 | 2.6 | 2.6 | 2.6 | 2.6 |
| EX: vector unit | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 |
| MEM: D$ hit latency | 9.5 | 9.5 | 9.3 | 9.3 | 9.6 | 9.6 |
| MEM: D$ miss | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| MEM: vector load/store | 0.0 | 0.0 | 0.2 | 0.2 | 0.0 | 0.0 |

## Events

| Event | coremark[scalar] default/axi | coremark[scalar] default/soc | coremark[sdk] default/axi | coremark[sdk] default/soc | coremark[validation] default/axi | coremark[validation] default/soc |
|---|---:|---:|---:|---:|---:|---:|
| retired alu (% of instret) | 47.9 | 47.9 | 47.9 | 47.9 | 47.8 | 47.8 |
| retired load (% of instret) | 20.6 | 20.6 | 20.6 | 20.6 | 20.8 | 20.8 |
| retired store (% of instret) | 5.4 | 5.4 | 5.3 | 5.3 | 5.4 | 5.4 |
| retired branch (% of instret) | 20.1 | 20.1 | 20.1 | 20.1 | 20.1 | 20.1 |
| retired jal (% of instret) | 1.6 | 1.6 | 1.6 | 1.6 | 1.6 | 1.6 |
| retired jalr (% of instret) | 0.8 | 0.8 | 0.8 | 0.8 | 0.8 | 0.8 |
| retired mul (% of instret) | 3.6 | 3.6 | 3.6 | 3.6 | 3.6 | 3.6 |
| retired vec (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired vls (% of instret) | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 |
| retired vset (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired csr (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| compressed (RVC, % of instret) | 51.4 | 51.4 | 51.2 | 51.2 | 51.5 | 51.5 |
| taken branches (% of branches) | 58.6 | 58.6 | 58.6 | 58.6 | 58.5 | 58.5 |
| redirects per 1000 instr | 141.9 | 141.9 | 142.0 | 142.0 | 141.7 | 141.7 |
| squashed wrong-path instr | 683,136 | 683,136 | 695,117 | 695,117 | 677,757 | 677,757 |
| I$ fetch accesses per instr | 1.297 | 1.297 | 1.317 | 1.317 | 1.298 | 1.298 |
| I$ misses (per 1000 instr) | 39 (0.007) | 39 (0.007) | 40 (0.008) | 40 (0.008) | 39 (0.007) | 39 (0.007) |
| D$ loads / stores | 1,082,027 / 283,065 | 1,082,027 / 283,065 | 1,081,947 / 282,988 | 1,081,947 / 282,988 | 1,090,995 / 281,121 | 1,090,995 / 281,121 |
| D$ misses (% of accesses) | 11 (0.0) | 11 (0.0) | 10 (0.0) | 10 (0.0) | 11 (0.0) | 11 (0.0) |
| D$ write-backs | 0 | 0 | 0 | 0 | 0 | 0 |
| uncached D accesses | 0 | 0 | 0 | 0 | 0 | 0 |
| bus transactions (I fill / D fill / D wb / uncached) | 39/11/0/0 | 39/11/0/0 | 40/10/0/0 | 40/10/0/0 | 39/11/0/0 | 39/11/0/0 |
| bus busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| bus waiting on memory (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| M unit busy (% of cycles) | 2.6 | 2.6 | 2.6 | 2.6 | 2.6 | 2.6 |
| FPU busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| vector unit busy (% of cycles) | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 |
| vector LS in MEM (% of cycles) | 0.0 | 0.0 | 0.2 | 0.2 | 0.0 | 0.0 |
| traps (exceptions / interrupts) | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

