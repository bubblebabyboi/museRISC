# Sigil performance report

- Date (UTC): 2026-10-22T09:58:49Z
- Commit: `c7bd3b7d8dfea7a0ebab264b8eaebbb092967376` (HEAD); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Host: ip-172-31-65-164 Linux 7.0.0-1014-aws x86_64
- Memory model `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`
- Repeats: 1
- Image `sha256chain-sdk`: sha256 `aeb4e5a41c38287f`, SDK default -march (rv64gcv + B, Zbc, Zcb, Zicond, Zbk*, Zkn*): every implementation is in the one image
- Image `sha256chain_bulk-sdk`: sha256 `fd0cf899150a3b3f`, SDK default -march (rv64gcv + B, Zbc, Zcb, Zicond, Zbk*, Zkn*): every implementation is in the one image

## Configurations (as reported by the counter records)

| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |
|---|---|---|---|---|---:|---:|---:|
| default | soc | `soc_rtl_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| sha256chain [sdk] sha256 plain C | default | soc | 1024 | 10,208,495 | 3,714,106 | 0.364 | 2.749 | 9,969.2 | - | 10,208,453 |
| sha256chain [sdk] sha256 Zknh | default | soc | 1024 | 7,385,318 | 2,731,066 | 0.370 | 2.704 | 7,212.2 | - | 7,385,282 |
| sha256chain [sdk] sha256 RVV x16 (multi-buffer) | default | soc | 1024 | 4,753,409 | 219,781 | 0.046 | 21.628 | 4,642.0 | - | 4,753,374 |
| sha256chain [sdk] sha256 accel sigil_sha256_block | default | soc | 1024 | 602,189 | 162,832 | 0.270 | 3.698 | 588.1 | - | 602,152 |
| sha256chain [sdk] sha256 accel sigil_sha256 | default | soc | 1024 | 2,876,530 | 1,029,138 | 0.358 | 2.795 | 2,809.1 | - | 2,876,495 |
| sha256chain [sdk] sha512 accel sigil_hash | default | soc | 1024 | 3,609,723 | 1,010,703 | 0.280 | 3.571 | 3,525.1 | - | 3,609,666 |
| sha256chain [sdk] sha3-256 accel sigil_hash | default | soc | 1024 | 1,920,058 | 550,930 | 0.287 | 3.485 | 1,875.1 | - | 1,920,023 |
| sha256chain_bulk [sdk] sha256 plain C | default | soc | 64 | 10,115,438 | 3,701,940 | 0.366 | 2.732 | 158,053.7 | 0.0065 B/cycle | 10,115,383 |
| sha256chain_bulk [sdk] sha256 Zknh | default | soc | 64 | 6,903,364 | 2,735,418 | 0.396 | 2.524 | 107,865.1 | 0.0095 B/cycle | 6,903,295 |
| sha256chain_bulk [sdk] sha256 RVV x16 (16 segments) | default | soc | 64 | 5,509,491 | 224,334 | 0.041 | 24.559 | 86,085.8 | 0.0119 B/cycle | 5,509,423 |
| sha256chain_bulk [sdk] sha512 accel sigil_hash | default | soc | 64 | 275,406 | 66,479 | 0.241 | 4.143 | 4,303.2 | 0.2380 B/cycle | 275,382 |
| sha256chain_bulk [sdk] sha3-256 accel sigil_hash | default | soc | 64 | 274,201 | 66,065 | 0.241 | 4.150 | 4,284.4 | 0.2390 B/cycle | 274,153 |

## Where the cycles go (% of cycles in the measured region)

| Category | sha256chain[sdk] sha256 plain C default/soc | sha256chain[sdk] sha256 Zknh default/soc | sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | sha256chain[sdk] sha256 accel sigil_sha256 default/soc | sha256chain[sdk] sha512 accel sigil_hash default/soc | sha256chain[sdk] sha3-256 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha256 plain C default/soc | sha256chain_bulk[sdk] sha256 Zknh default/soc | sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| retire (base) | 36.4 | 37.0 | 4.6 | 27.0 | 35.8 | 28.0 | 28.7 | 36.6 | 39.6 | 4.1 | 24.1 | 24.1 |
| fetch: I$ hit latency / issue gap | 46.1 | 44.4 | 3.6 | 30.1 | 40.1 | 43.9 | 43.9 | 46.0 | 44.9 | 8.0 | 24.3 | 24.2 |
| fetch: 32-bit instr straddles a word | 11.4 | 11.2 | 0.0 | 7.5 | 8.8 | 17.6 | 17.1 | 11.4 | 6.5 | 4.0 | 6.2 | 6.1 |
| fetch: I$ miss | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: taken branch | 1.4 | 1.0 | 0.0 | 4.6 | 2.3 | 1.9 | 1.8 | 1.4 | 2.1 | 0.0 | 6.0 | 6.0 |
| squashed: jal | 0.0 | 0.0 | 0.0 | 0.2 | 0.1 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: jalr | 0.0 | 0.0 | 0.0 | 0.2 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| load-use interlock | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| EX: M unit (mul/div) | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| EX: vector unit | 0.0 | 0.0 | 89.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 80.8 | 0.0 | 0.0 |
| MEM: D$ hit latency | 4.7 | 6.4 | 0.1 | 9.4 | 8.3 | 3.9 | 4.1 | 4.4 | 6.7 | 0.1 | 11.9 | 12.0 |
| MEM: D$ miss | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.2 | 0.0 | 3.6 | 3.7 |
| MEM: uncached device access | 0.0 | 0.0 | 0.0 | 21.1 | 4.4 | 4.7 | 4.3 | 0.0 | 0.0 | 0.0 | 23.8 | 23.9 |
| MEM: vector load/store | 0.0 | 0.0 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 2.9 | 0.0 | 0.0 |

## Events

| Event | sha256chain[sdk] sha256 plain C default/soc | sha256chain[sdk] sha256 Zknh default/soc | sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | sha256chain[sdk] sha256 accel sigil_sha256 default/soc | sha256chain[sdk] sha512 accel sigil_hash default/soc | sha256chain[sdk] sha3-256 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha256 plain C default/soc | sha256chain_bulk[sdk] sha256 Zknh default/soc | sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| retired alu (% of instret) | 83.1 | 77.1 | 0.5 | 44.7 | 65.4 | 72.6 | 72.5 | 83.8 | 77.6 | 0.3 | 25.7 | 25.4 |
| retired load (% of instret) | 10.1 | 13.8 | 1.9 | 18.9 | 12.9 | 4.8 | 4.8 | 9.8 | 13.6 | 1.9 | 24.7 | 24.8 |
| retired store (% of instret) | 2.7 | 3.6 | 0.0 | 15.7 | 10.2 | 9.1 | 9.3 | 2.3 | 3.3 | 0.0 | 24.8 | 24.9 |
| retired branch (% of instret) | 4.0 | 5.4 | 0.2 | 19.5 | 10.7 | 13.0 | 12.5 | 4.0 | 5.5 | 0.2 | 24.8 | 24.9 |
| retired jal (% of instret) | 0.1 | 0.1 | 0.1 | 0.6 | 0.3 | 0.3 | 0.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| retired jalr (% of instret) | 0.0 | 0.0 | 0.0 | 0.6 | 0.3 | 0.2 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired mul (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired vec (% of instret) | 0.0 | 0.0 | 97.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.7 | 0.0 | 0.0 |
| retired vls (% of instret) | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.7 | 0.0 | 0.0 |
| retired vset (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| retired csr (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| compressed (RVC, % of instret) | 37.4 | 55.0 | 0.2 | 64.1 | 42.9 | 33.3 | 33.5 | 37.1 | 55.1 | 0.0 | 74.4 | 74.6 |
| taken branches (% of branches) | 96.6 | 96.6 | 24.8 | 90.3 | 88.9 | 68.7 | 62.7 | 96.6 | 96.6 | 24.5 | 99.8 | 99.8 |
| redirects per 1000 instr | 39.4 | 53.6 | 1.5 | 188.7 | 101.5 | 94.2 | 87.4 | 39.3 | 53.2 | 1.5 | 247.6 | 248.6 |
| squashed wrong-path instr | 146,431 | 74,752 | 257 | 29,695 | 72,703 | 71,680 | 37,888 | 145,541 | 145,581 | 66 | 16,438 | 16,413 |
| I$ fetch accesses per instr | 1.358 | 1.330 | 1.007 | 1.459 | 1.317 | 1.700 | 1.664 | 1.351 | 1.228 | 1.994 | 1.503 | 1.501 |
| I$ misses (per 1000 instr) | 8 (0.002) | 8 (0.003) | 42 (0.191) | 2 (0.012) | 6 (0.006) | 8 (0.008) | 1 (0.002) | 19 (0.005) | 18 (0.007) | 55 (0.245) | 5 (0.075) | 1 (0.015) |
| D$ loads / stores | 375,822 / 99,348 | 376,846 / 98,325 | 32,918 / 4,624 | 30,722 / 25,604 | 133,122 / 105,476 | 48,129 / 92,164 | 26,626 / 51,204 | 363,923 / 84,174 | 371,104 / 91,346 | 36,406 / 8,328 | 16,416 / 16,462 | 16,404 / 16,430 |
| D$ misses (% of accesses) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 983 (0.2) | 1,077 (0.2) | 2,065 (4.6) | 895 (2.7) | 907 (2.8) |
| D$ write-backs | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 266 | 32 | 23 | 3 | 14 |
| uncached D accesses | 0 | 0 | 0 | 31,744 | 31,744 | 41,983 | 20,480 | 0 | 0 | 0 | 16,408 | 16,396 |
| bus transactions (I fill / D fill / D wb / uncached) | 8/0/0/0 | 8/0/0/0 | 42/0/0/0 | 2/0/0/31744 | 6/0/0/31744 | 8/0/0/41983 | 1/0/0/20480 | 19/983/266/0 | 18/1077/32/0 | 55/2065/23/0 | 5/895/3/16408 | 1/907/14/16396 |
| bus busy (% of cycles) | 0.0 | 0.0 | 0.0 | 21.1 | 4.4 | 4.7 | 4.3 | 0.1 | 0.1 | 0.4 | 26.8 | 26.9 |
| bus waiting on memory (% of cycles) | 0.0 | 0.0 | 0.0 | 10.5 | 2.2 | 2.3 | 2.1 | 0.0 | 0.0 | 0.0 | 11.9 | 12.0 |
| M unit busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| FPU busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| vector unit busy (% of cycles) | 0.0 | 0.0 | 89.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 80.8 | 0.0 | 0.0 |
| vector LS in MEM (% of cycles) | 0.0 | 0.0 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 3.0 | 0.0 | 0.0 |
| traps (exceptions / interrupts) | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

