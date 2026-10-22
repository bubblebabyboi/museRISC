# Sigil performance report

- Date (UTC): 2026-10-22T09:52:59Z
- Commit: `2b8e1aebfb1599320ccb8b05114c80134f24be79` (56-perf-sha256chain); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Host: ip-172-31-65-164 Linux 7.0.0-1014-aws x86_64
- Memory model `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`
- Repeats: 1
- Image `sha256chain-sdk`: sha256 `8e3c1158cf6bf225`, SDK default -march (rv64gcv + B, Zbc, Zcb, Zicond, Zbk*, Zkn*): every implementation is in the one image
- Image `sha256chain_bulk-sdk`: sha256 `2db62b709459c764`, SDK default -march (rv64gcv + B, Zbc, Zcb, Zicond, Zbk*, Zkn*): every implementation is in the one image

## Configurations (as reported by the counter records)

| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |
|---|---|---|---|---|---:|---:|---:|
| default | soc | `soc_rtl_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| sha256chain [sdk] sha256 plain C | default | soc | 40 | 396,956 | 145,138 | 0.366 | 2.735 | 9,923.9 | - | 396,928 |
| sha256chain [sdk] sha256 Zknh | default | soc | 40 | 270,362 | 106,738 | 0.395 | 2.533 | 6,759.1 | - | 270,336 |
| sha256chain [sdk] sha256 RVV x16 (multi-buffer) | default | soc | 40 | 200,695 | 10,545 | 0.053 | 19.032 | 5,017.4 | - | 200,647 |
| sha256chain [sdk] sha256 accel sigil_sha256_block | default | soc | 40 | 22,984 | 6,389 | 0.278 | 3.597 | 574.6 | - | 22,939 |
| sha256chain [sdk] sha256 accel sigil_sha256 | default | soc | 40 | 111,876 | 40,233 | 0.360 | 2.781 | 2,796.9 | - | 111,828 |
| sha256chain [sdk] sha512 accel sigil_hash | default | soc | 40 | 99,058 | 39,560 | 0.399 | 2.504 | 2,476.4 | - | 99,021 |
| sha256chain [sdk] sha3-256 accel sigil_hash | default | soc | 40 | 54,925 | 21,720 | 0.395 | 2.529 | 1,373.1 | - | 54,888 |
| sha256chain_bulk [sdk] sha256 plain C | default | soc | 40 | 6,326,637 | 2,315,317 | 0.366 | 2.733 | 158,165.9 | 0.0065 B/cycle | 6,326,589 |
| sha256chain_bulk [sdk] sha256 Zknh | default | soc | 40 | 4,317,523 | 1,710,906 | 0.396 | 2.524 | 107,938.1 | 0.0095 B/cycle | 4,317,469 |
| sha256chain_bulk [sdk] sha256 RVV x16 (16 segments) | default | soc | 40 | 3,148,252 | 141,532 | 0.045 | 22.244 | 78,706.3 | 0.0130 B/cycle | 3,148,205 |
| sha256chain_bulk [sdk] sha512 accel sigil_hash | default | soc | 40 | 172,830 | 41,896 | 0.242 | 4.125 | 4,320.8 | 0.2370 B/cycle | 172,782 |
| sha256chain_bulk [sdk] sha3-256 accel sigil_hash | default | soc | 40 | 171,338 | 41,480 | 0.242 | 4.131 | 4,283.4 | 0.2391 B/cycle | 171,293 |

## Where the cycles go (% of cycles in the measured region)

| Category | sha256chain[sdk] sha256 plain C default/soc | sha256chain[sdk] sha256 Zknh default/soc | sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | sha256chain[sdk] sha256 accel sigil_sha256 default/soc | sha256chain[sdk] sha512 accel sigil_hash default/soc | sha256chain[sdk] sha3-256 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha256 plain C default/soc | sha256chain_bulk[sdk] sha256 Zknh default/soc | sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| retire (base) | 36.6 | 39.5 | 5.3 | 27.8 | 36.0 | 39.9 | 39.5 | 36.6 | 39.6 | 4.5 | 24.2 | 24.2 |
| fetch: I$ hit latency / issue gap | 45.9 | 44.6 | 4.1 | 33.4 | 40.8 | 41.9 | 42.2 | 46.0 | 44.9 | 3.0 | 30.2 | 30.2 |
| fetch: 32-bit instr straddles a word | 11.4 | 6.9 | 0.1 | 3.4 | 7.9 | 2.4 | 3.5 | 11.4 | 6.5 | 0.0 | 0.0 | 0.0 |
| fetch: I$ miss | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: taken branch | 1.4 | 2.1 | 0.0 | 4.0 | 2.2 | 3.5 | 3.0 | 1.4 | 2.1 | 0.0 | 6.0 | 6.0 |
| squashed: jal | 0.0 | 0.0 | 0.0 | 0.2 | 0.1 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: jalr | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| EX: M unit (mul/div) | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| EX: vector unit | 0.0 | 0.0 | 86.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.2 | 0.0 | 0.0 |
| MEM: D$ hit latency | 4.7 | 6.9 | 0.1 | 9.6 | 8.3 | 5.5 | 5.6 | 4.4 | 6.7 | 0.1 | 11.9 | 12.0 |
| MEM: D$ miss | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.2 | 0.0 | 3.9 | 3.6 |
| MEM: uncached device access | 0.0 | 0.0 | 0.0 | 21.6 | 4.4 | 6.5 | 5.8 | 0.0 | 0.0 | 0.0 | 23.8 | 23.9 |
| MEM: vector load/store | 0.0 | 0.0 | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 3.1 | 0.0 | 0.0 |

## Events

| Event | sha256chain[sdk] sha256 plain C default/soc | sha256chain[sdk] sha256 Zknh default/soc | sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | sha256chain[sdk] sha256 accel sigil_sha256 default/soc | sha256chain[sdk] sha512 accel sigil_hash default/soc | sha256chain[sdk] sha3-256 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha256 plain C default/soc | sha256chain_bulk[sdk] sha256 Zknh default/soc | sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| retired alu (% of instret) | 83.1 | 77.0 | 1.3 | 44.6 | 65.3 | 72.8 | 72.6 | 83.8 | 77.6 | 0.3 | 26.1 | 25.6 |
| retired load (% of instret) | 10.1 | 13.8 | 2.2 | 18.9 | 12.9 | 4.7 | 4.8 | 9.8 | 13.6 | 1.9 | 24.5 | 24.7 |
| retired store (% of instret) | 2.7 | 3.6 | 0.3 | 15.8 | 10.3 | 9.1 | 9.3 | 2.3 | 3.3 | 0.0 | 24.6 | 24.8 |
| retired branch (% of instret) | 4.0 | 5.4 | 0.2 | 19.4 | 10.7 | 12.8 | 12.3 | 4.0 | 5.5 | 0.2 | 24.7 | 24.8 |
| retired jal (% of instret) | 0.1 | 0.1 | 0.1 | 0.6 | 0.3 | 0.3 | 0.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| retired jalr (% of instret) | 0.0 | 0.0 | 0.0 | 0.6 | 0.3 | 0.2 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired mul (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired vec (% of instret) | 0.0 | 0.0 | 94.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.7 | 0.0 | 0.0 |
| retired vls (% of instret) | 0.0 | 0.0 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.7 | 0.0 | 0.0 |
| retired vset (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| retired csr (% of instret) | 0.0 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| compressed (RVC, % of instret) | 37.4 | 55.0 | 0.8 | 64.1 | 42.9 | 33.1 | 33.5 | 37.1 | 55.1 | 0.0 | 74.0 | 74.4 |
| taken branches (% of branches) | 96.5 | 96.5 | 15.4 | 90.2 | 88.9 | 68.5 | 62.6 | 96.6 | 96.6 | 24.2 | 99.6 | 99.8 |
| redirects per 1000 instr | 39.4 | 53.6 | 1.6 | 188.0 | 101.4 | 93.0 | 86.6 | 39.4 | 53.3 | 1.5 | 246.2 | 247.8 |
| squashed wrong-path instr | 5,681 | 5,681 | 15 | 960 | 2,641 | 3,640 | 1,840 | 91,015 | 91,053 | 206 | 10,315 | 10,277 |
| I$ fetch accesses per instr | 1.352 | 1.233 | 1.017 | 1.409 | 1.309 | 1.168 | 1.186 | 1.350 | 1.228 | 1.009 | 1.492 | 1.496 |
| I$ misses (per 1000 instr) | 8 (0.055) | 8 (0.075) | 37 (3.509) | 2 (0.313) | 6 (0.149) | 7 (0.177) | 2 (0.092) | 15 (0.006) | 18 (0.011) | 57 (0.403) | 2 (0.048) | 2 (0.048) |
| D$ loads / stores | 14,694 / 3,900 | 14,734 / 3,861 | 1,770 / 1,180 | 1,205 / 1,007 | 5,206 / 4,128 | 1,848 / 3,610 | 1,048 / 2,010 | 227,603 / 52,686 | 232,096 / 57,170 | 22,966 / 5,256 | 10,273 / 10,318 | 10,260 / 10,286 |
| D$ misses (% of accesses) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 534 (0.2) | 613 (0.2) | 927 (3.3) | 580 (2.8) | 552 (2.7) |
| D$ write-backs | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 231 | 19 | 32 | 18 | 8 |
| uncached D accesses | 0 | 0 | 0 | 1,240 | 1,240 | 1,600 | 800 | 0 | 0 | 0 | 10,265 | 10,252 |
| bus transactions (I fill / D fill / D wb / uncached) | 8/0/0/0 | 8/0/0/0 | 37/0/0/0 | 2/0/0/1240 | 6/0/0/1240 | 7/0/0/1600 | 2/0/0/800 | 15/534/231/0 | 18/613/19/0 | 57/927/32/0 | 2/580/18/10265 | 2/552/8/10252 |
| bus busy (% of cycles) | 0.0 | 0.0 | 0.2 | 21.7 | 4.5 | 6.5 | 5.9 | 0.1 | 0.1 | 0.3 | 26.9 | 26.9 |
| bus waiting on memory (% of cycles) | 0.0 | 0.0 | 0.0 | 10.8 | 2.2 | 3.2 | 2.9 | 0.0 | 0.0 | 0.0 | 11.9 | 12.0 |
| M unit busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| FPU busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| vector unit busy (% of cycles) | 0.0 | 0.0 | 86.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.2 | 0.0 | 0.0 |
| vector LS in MEM (% of cycles) | 0.0 | 0.0 | 4.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 3.1 | 0.0 | 0.0 |
| traps (exceptions / interrupts) | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

