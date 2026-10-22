# Sigil performance report

- Date (UTC): 2026-10-22T09:55:45Z
- Commit: `2b8e1aebfb1599320ccb8b05114c80134f24be79` (56-perf-sha256chain); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Host: ip-172-31-65-164 Linux 7.0.0-1014-aws x86_64
- Memory model `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`
- Memory model `axi`: `--axi-lat 24:24 --axi-gap 0 --axi-ready 100 --uart-pop 100`
- Repeats: 2; deterministic: yes (identical counts)
- Image `sha256chain-sdk`: sha256 `4df1e870f74f325b`, SDK default -march (rv64gcv + B, Zbc, Zcb, Zicond, Zbk*, Zkn*): every implementation is in the one image
- Image `sha256chain_bulk-sdk`: sha256 `1bbffc8acf82cbeb`, SDK default -march (rv64gcv + B, Zbc, Zcb, Zicond, Zbk*, Zkn*): every implementation is in the one image

## Configurations (as reported by the counter records)

| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |
|---|---|---|---|---|---:|---:|---:|
| default | axi | `fpga_top_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |
| default | soc | `soc_rtl_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| sha256chain [sdk] sha256 plain C | default | axi | 1024 | 10,156,468 | 3,714,106 | 0.366 | 2.735 | 9,918.4 | - | 10,156,440 |
| sha256chain [sdk] sha256 plain C | default | soc | 1024 | 10,156,268 | 3,714,106 | 0.366 | 2.735 | 9,918.2 | - | 10,156,240 |
| sha256chain [sdk] sha256 Zknh | default | axi | 1024 | 6,915,525 | 2,731,068 | 0.395 | 2.532 | 6,753.4 | - | 6,915,490 |
| sha256chain [sdk] sha256 Zknh | default | soc | 1024 | 6,915,325 | 2,731,068 | 0.395 | 2.532 | 6,753.2 | - | 6,915,290 |
| sha256chain [sdk] sha256 RVV x16 (multi-buffer) | default | axi | 1024 | 4,754,072 | 219,780 | 0.046 | 21.631 | 4,642.6 | - | 4,753,975 |
| sha256chain [sdk] sha256 RVV x16 (multi-buffer) | default | soc | 1024 | 4,753,403 | 219,780 | 0.046 | 21.628 | 4,642.0 | - | 4,753,356 |
| sha256chain [sdk] sha256 accel sigil_sha256_block | default | axi | 1024 | 585,847 | 162,844 | 0.278 | 3.598 | 572.1 | - | 585,812 |
| sha256chain [sdk] sha256 accel sigil_sha256_block | default | soc | 1024 | 585,822 | 162,844 | 0.278 | 3.597 | 572.1 | - | 585,787 |
| sha256chain [sdk] sha256 accel sigil_sha256 | default | axi | 1024 | 2,860,326 | 1,029,153 | 0.360 | 2.779 | 2,793.3 | - | 2,860,302 |
| sha256chain [sdk] sha256 accel sigil_sha256 | default | soc | 1024 | 2,860,176 | 1,029,153 | 0.360 | 2.779 | 2,793.1 | - | 2,860,152 |
| sha256chain [sdk] sha512 accel sigil_hash | default | axi | 1024 | 2,531,644 | 1,011,743 | 0.400 | 2.502 | 2,472.3 | - | 2,531,583 |
| sha256chain [sdk] sha512 accel sigil_hash | default | soc | 1024 | 2,531,505 | 1,011,752 | 0.400 | 2.502 | 2,472.2 | - | 2,531,469 |
| sha256chain [sdk] sha3-256 accel sigil_hash | default | axi | 1024 | 1,403,055 | 555,048 | 0.396 | 2.528 | 1,370.2 | - | 1,403,029 |
| sha256chain [sdk] sha3-256 accel sigil_hash | default | soc | 1024 | 1,403,005 | 555,048 | 0.396 | 2.528 | 1,370.1 | - | 1,402,979 |
| sha256chain_bulk [sdk] sha256 plain C | default | axi | 64 | 10,145,679 | 3,701,941 | 0.365 | 2.741 | 158,526.2 | 0.0065 B/cycle | 10,145,581 |
| sha256chain_bulk [sdk] sha256 plain C | default | soc | 64 | 10,114,258 | 3,701,941 | 0.366 | 2.732 | 158,035.3 | 0.0065 B/cycle | 10,114,210 |
| sha256chain_bulk [sdk] sha256 Zknh | default | axi | 64 | 6,931,283 | 2,735,418 | 0.395 | 2.534 | 108,301.3 | 0.0095 B/cycle | 6,931,154 |
| sha256chain_bulk [sdk] sha256 Zknh | default | soc | 64 | 6,903,194 | 2,735,418 | 0.396 | 2.524 | 107,862.4 | 0.0095 B/cycle | 6,903,140 |
| sha256chain_bulk [sdk] sha256 RVV x16 (16 segments) | default | axi | 64 | 5,049,593 | 224,331 | 0.044 | 22.510 | 78,899.9 | 0.0130 B/cycle | 5,049,462 |
| sha256chain_bulk [sdk] sha256 RVV x16 (16 segments) | default | soc | 64 | 4,996,705 | 224,331 | 0.045 | 22.274 | 78,073.5 | 0.0131 B/cycle | 4,996,649 |
| sha256chain_bulk [sdk] sha512 accel sigil_hash | default | axi | 64 | 297,276 | 66,472 | 0.224 | 4.472 | 4,644.9 | 0.2205 B/cycle | 297,203 |
| sha256chain_bulk [sdk] sha512 accel sigil_hash | default | soc | 64 | 274,480 | 66,472 | 0.242 | 4.129 | 4,288.8 | 0.2388 B/cycle | 274,432 |
| sha256chain_bulk [sdk] sha3-256 accel sigil_hash | default | axi | 64 | 295,850 | 66,055 | 0.223 | 4.479 | 4,622.7 | 0.2215 B/cycle | 295,826 |
| sha256chain_bulk [sdk] sha3-256 accel sigil_hash | default | soc | 64 | 273,326 | 66,055 | 0.242 | 4.138 | 4,270.7 | 0.2398 B/cycle | 273,302 |

## Where the cycles go (% of cycles in the measured region)

| Category | sha256chain[sdk] sha256 plain C default/axi | sha256chain[sdk] sha256 plain C default/soc | sha256chain[sdk] sha256 Zknh default/axi | sha256chain[sdk] sha256 Zknh default/soc | sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/axi | sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | sha256chain[sdk] sha256 accel sigil_sha256_block default/axi | sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | sha256chain[sdk] sha256 accel sigil_sha256 default/axi | sha256chain[sdk] sha256 accel sigil_sha256 default/soc | sha256chain[sdk] sha512 accel sigil_hash default/axi | sha256chain[sdk] sha512 accel sigil_hash default/soc | sha256chain[sdk] sha3-256 accel sigil_hash default/axi | sha256chain[sdk] sha3-256 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha256 plain C default/axi | sha256chain_bulk[sdk] sha256 plain C default/soc | sha256chain_bulk[sdk] sha256 Zknh default/axi | sha256chain_bulk[sdk] sha256 Zknh default/soc | sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/axi | sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | sha256chain_bulk[sdk] sha512 accel sigil_hash default/axi | sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/axi | sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| retire (base) | 36.6 | 36.6 | 39.5 | 39.5 | 4.6 | 4.6 | 27.8 | 27.8 | 36.0 | 36.0 | 40.0 | 40.0 | 39.6 | 39.6 | 36.5 | 36.6 | 39.5 | 39.6 | 4.4 | 4.5 | 22.4 | 24.2 | 22.3 | 24.2 |
| fetch: I$ hit latency / issue gap | 45.9 | 45.9 | 44.7 | 44.7 | 3.6 | 3.6 | 33.4 | 33.4 | 40.8 | 40.9 | 41.9 | 41.9 | 42.2 | 42.2 | 45.9 | 46.0 | 44.7 | 44.9 | 3.0 | 3.0 | 27.9 | 30.2 | 27.9 | 30.2 |
| fetch: 32-bit instr straddles a word | 11.4 | 11.4 | 6.9 | 6.9 | 0.0 | 0.0 | 3.3 | 3.3 | 7.9 | 7.9 | 2.4 | 2.4 | 3.5 | 3.5 | 11.4 | 11.4 | 6.4 | 6.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| fetch: I$ miss | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: taken branch | 1.4 | 1.4 | 2.1 | 2.1 | 0.0 | 0.0 | 4.0 | 4.0 | 2.2 | 2.2 | 3.5 | 3.5 | 3.0 | 3.0 | 1.4 | 1.4 | 2.1 | 2.1 | 0.0 | 0.0 | 5.5 | 6.0 | 5.5 | 6.0 |
| squashed: jal | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.2 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: jalr | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| EX: M unit (mul/div) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| EX: vector unit | 0.0 | 0.0 | 0.0 | 0.0 | 89.6 | 89.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 88.2 | 89.1 | 0.0 | 0.0 | 0.0 | 0.0 |
| MEM: D$ hit latency | 4.7 | 4.7 | 6.9 | 6.9 | 0.1 | 0.1 | 9.6 | 9.6 | 8.3 | 8.3 | 5.5 | 5.5 | 5.5 | 5.5 | 4.4 | 4.4 | 6.7 | 6.7 | 0.1 | 0.1 | 11.1 | 12.0 | 11.1 | 12.0 |
| MEM: D$ miss | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 | 0.1 | 0.6 | 0.2 | 0.0 | 0.0 | 11.0 | 3.7 | 11.0 | 3.6 |
| MEM: uncached device access | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 21.7 | 21.7 | 4.4 | 4.4 | 6.5 | 6.5 | 5.8 | 5.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 22.1 | 23.9 | 22.2 | 24.0 |
| MEM: vector load/store | 0.0 | 0.0 | 0.0 | 0.0 | 2.1 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.2 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 |

## Events

| Event | sha256chain[sdk] sha256 plain C default/axi | sha256chain[sdk] sha256 plain C default/soc | sha256chain[sdk] sha256 Zknh default/axi | sha256chain[sdk] sha256 Zknh default/soc | sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/axi | sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | sha256chain[sdk] sha256 accel sigil_sha256_block default/axi | sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | sha256chain[sdk] sha256 accel sigil_sha256 default/axi | sha256chain[sdk] sha256 accel sigil_sha256 default/soc | sha256chain[sdk] sha512 accel sigil_hash default/axi | sha256chain[sdk] sha512 accel sigil_hash default/soc | sha256chain[sdk] sha3-256 accel sigil_hash default/axi | sha256chain[sdk] sha3-256 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha256 plain C default/axi | sha256chain_bulk[sdk] sha256 plain C default/soc | sha256chain_bulk[sdk] sha256 Zknh default/axi | sha256chain_bulk[sdk] sha256 Zknh default/soc | sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/axi | sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | sha256chain_bulk[sdk] sha512 accel sigil_hash default/axi | sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/axi | sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| retired alu (% of instret) | 83.1 | 83.1 | 77.1 | 77.1 | 0.5 | 0.5 | 44.7 | 44.7 | 65.4 | 65.4 | 72.9 | 72.9 | 72.7 | 72.7 | 83.8 | 83.8 | 77.6 | 77.6 | 0.3 | 0.3 | 25.7 | 25.7 | 25.4 | 25.4 |
| retired load (% of instret) | 10.1 | 10.1 | 13.8 | 13.8 | 1.9 | 1.9 | 18.9 | 18.9 | 12.9 | 12.9 | 4.7 | 4.7 | 4.8 | 4.8 | 9.8 | 9.8 | 13.6 | 13.6 | 1.9 | 1.9 | 24.7 | 24.7 | 24.8 | 24.8 |
| retired store (% of instret) | 2.7 | 2.7 | 3.6 | 3.6 | 0.0 | 0.0 | 15.7 | 15.7 | 10.2 | 10.2 | 9.1 | 9.1 | 9.2 | 9.2 | 2.3 | 2.3 | 3.3 | 3.3 | 0.0 | 0.0 | 24.8 | 24.8 | 24.9 | 24.9 |
| retired branch (% of instret) | 4.0 | 4.0 | 5.4 | 5.4 | 0.2 | 0.2 | 19.5 | 19.5 | 10.7 | 10.7 | 12.9 | 12.9 | 12.4 | 12.4 | 4.0 | 4.0 | 5.5 | 5.5 | 0.2 | 0.2 | 24.8 | 24.8 | 24.9 | 24.9 |
| retired jal (% of instret) | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.1 | 0.6 | 0.6 | 0.3 | 0.3 | 0.3 | 0.3 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired jalr (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.6 | 0.6 | 0.3 | 0.3 | 0.2 | 0.2 | 0.4 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired mul (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired vec (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 97.0 | 97.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.7 | 96.7 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired vls (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired vset (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 |
| retired csr (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| compressed (RVC, % of instret) | 37.4 | 37.4 | 55.0 | 55.0 | 0.2 | 0.2 | 64.1 | 64.1 | 42.9 | 42.9 | 33.1 | 33.1 | 33.4 | 33.4 | 37.1 | 37.1 | 55.1 | 55.1 | 0.0 | 0.0 | 74.4 | 74.4 | 74.6 | 74.6 |
| taken branches (% of branches) | 96.6 | 96.6 | 96.6 | 96.6 | 24.8 | 24.8 | 90.3 | 90.3 | 88.9 | 88.9 | 68.5 | 68.5 | 62.7 | 62.7 | 96.6 | 96.6 | 96.6 | 96.6 | 24.5 | 24.5 | 99.8 | 99.8 | 99.8 | 99.8 |
| redirects per 1000 instr | 39.4 | 39.4 | 53.6 | 53.6 | 1.5 | 1.5 | 188.7 | 188.7 | 101.5 | 101.5 | 93.1 | 93.1 | 86.7 | 86.7 | 39.3 | 39.3 | 53.2 | 53.2 | 1.5 | 1.5 | 247.6 | 247.6 | 248.6 | 248.6 |
| squashed wrong-path instr | 145,409 | 145,409 | 145,408 | 145,408 | 258 | 258 | 24,576 | 24,576 | 67,585 | 67,585 | 93,181 | 93,184 | 47,104 | 47,104 | 145,543 | 145,543 | 145,581 | 145,581 | 326 | 326 | 16,458 | 16,458 | 16,421 | 16,421 |
| I$ fetch accesses per instr | 1.352 | 1.352 | 1.233 | 1.233 | 1.007 | 1.007 | 1.409 | 1.409 | 1.309 | 1.309 | 1.168 | 1.168 | 1.186 | 1.186 | 1.351 | 1.351 | 1.228 | 1.228 | 1.008 | 1.008 | 1.495 | 1.495 | 1.497 | 1.497 |
| I$ misses (per 1000 instr) | 8 (0.002) | 8 (0.002) | 8 (0.003) | 8 (0.003) | 38 (0.173) | 38 (0.173) | 1 (0.006) | 1 (0.006) | 6 (0.006) | 6 (0.006) | 7 (0.007) | 7 (0.007) | 2 (0.004) | 2 (0.004) | 15 (0.004) | 15 (0.004) | 18 (0.007) | 18 (0.007) | 57 (0.254) | 57 (0.254) | 2 (0.030) | 2 (0.030) | 1 (0.015) | 1 (0.015) |
| D$ loads / stores | 375,822 / 99,348 | 375,822 / 99,348 | 376,846 / 98,325 | 376,846 / 98,325 | 32,918 / 4,624 | 32,918 / 4,624 | 30,725 / 25,607 | 30,725 / 25,607 | 133,126 / 105,480 | 133,126 / 105,480 | 47,109 / 92,170 | 47,112 / 92,170 | 26,632 / 51,210 | 26,632 / 51,210 | 363,923 / 84,174 | 363,923 / 84,174 | 371,104 / 91,346 | 371,104 / 91,346 | 36,406 / 8,328 | 36,406 / 8,328 | 16,417 / 16,462 | 16,417 / 16,462 | 16,404 / 16,430 | 16,404 / 16,430 |
| D$ misses (% of accesses) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 0 (0.0) | 929 (0.2) | 929 (0.2) | 1,062 (0.2) | 1,062 (0.2) | 2,044 (4.6) | 2,044 (4.6) | 894 (2.7) | 894 (2.7) | 896 (2.7) | 896 (2.7) |
| D$ write-backs | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 237 | 237 | 33 | 33 | 28 | 28 | 12 | 12 | 3 | 3 |
| uncached D accesses | 0 | 0 | 0 | 0 | 0 | 0 | 31,744 | 31,744 | 31,744 | 31,744 | 40,957 | 40,960 | 20,480 | 20,480 | 0 | 0 | 0 | 0 | 0 | 0 | 16,409 | 16,409 | 16,396 | 16,396 |
| bus transactions (I fill / D fill / D wb / uncached) | 8/0/0/0 | 8/0/0/0 | 8/0/0/0 | 8/0/0/0 | 38/0/0/0 | 38/0/0/0 | 1/0/0/31744 | 1/0/0/31744 | 6/0/0/31744 | 6/0/0/31744 | 7/0/0/40957 | 7/0/0/40960 | 2/0/0/20480 | 2/0/0/20480 | 15/929/237/0 | 15/929/237/0 | 18/1062/33/0 | 18/1062/33/0 | 57/2044/28/0 | 57/2044/28/0 | 2/894/12/16409 | 2/894/12/16409 | 1/896/3/16396 | 1/896/3/16396 |
| bus busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 21.7 | 21.7 | 4.4 | 4.4 | 6.5 | 6.5 | 5.8 | 5.8 | 0.4 | 0.1 | 0.5 | 0.1 | 1.4 | 0.4 | 32.5 | 26.9 | 32.5 | 27.0 |
| bus waiting on memory (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 10.8 | 10.8 | 2.2 | 2.2 | 3.2 | 3.2 | 2.9 | 2.9 | 0.3 | 0.0 | 0.4 | 0.0 | 1.1 | 0.0 | 18.7 | 12.0 | 18.7 | 12.0 |
| M unit busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| FPU busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| vector unit busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 89.6 | 89.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 88.2 | 89.1 | 0.0 | 0.0 | 0.0 | 0.0 |
| vector LS in MEM (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 2.1 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.3 | 3.3 | 0.0 | 0.0 | 0.0 | 0.0 |
| traps (exceptions / interrupts) | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

