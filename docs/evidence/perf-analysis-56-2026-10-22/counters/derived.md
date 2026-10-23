# Counter-derived quantities (perf-baseline-56-2026-10-22, rep 0)

I$ port occupancy = ic_access x hit cycles (2, or 3 with SRAM_OREG) / cycles. Average instruction size = (2 x ret_rvc + 4 x (instret - ret_rvc)) / instret. Redirects = br_taken + jal_redir + jalr_redir.

## default / soc

| Region | cycles | instret | IPC | ic_access | I$ port busy | fetches/instr | RVC % | bytes/instr | redirects | redirects/instr | D$ accesses | stk_dc_lat/access | uncached | cycles/uncached | stk_io | stk_vls | ret_vls | bus busy | muldiv_busy |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| CoreMark scalar | 14,337,806 | 5,246,413 | 0.366 | 6,806,626 | 94.9% | 1.297 | 51.4 | 2.97 | 744,296 | 0.142 | 1,365,092 | 1.000 | 0 | 0.00 | 0 | 0 | 0 | 0.0% | 375,840 |
| CoreMark sdk | 14,572,507 | 5,238,336 | 0.359 | 6,901,046 | 94.7% | 1.317 | 51.2 | 2.98 | 743,736 | 0.142 | 1,364,935 | 0.992 | 0 | 0.00 | 0 | 30,732 | 4,801 | 0.0% | 375,840 |
| Dhrystone scalar | 3,070,244 | 1,036,022 | 0.337 | 1,502,031 | 97.8% | 1.450 | 73.7 | 2.53 | 179,999 | 0.174 | 390,006 | 1.000 | 0 | 0.00 | 0 | 0 | 0 | 0.0% | 6,000 |
| Dhrystone sdk | 3,482,242 | 1,022,022 | 0.293 | 1,384,025 | 79.5% | 1.354 | 73.2 | 2.54 | 179,999 | 0.176 | 584,006 | 0.616 | 0 | 0.00 | 0 | 672,000 | 4,000 | 0.0% | 6,000 |
| SHA-256 C | 10,156,268 | 3,714,106 | 0.366 | 5,020,738 | 98.9% | 1.352 | 37.4 | 3.25 | 146,433 | 0.039 | 475,170 | 1.000 | 0 | 0.00 | 0 | 0 | 0 | 0.0% | 0 |
| SHA-256 Zknh | 6,915,325 | 2,731,068 | 0.395 | 3,368,012 | 97.4% | 1.233 | 55.0 | 2.90 | 146,433 | 0.054 | 475,171 | 1.000 | 0 | 0.00 | 0 | 0 | 0 | 0.0% | 0 |
| SHA-256 RVV x16 | 4,753,403 | 219,780 | 0.046 | 221,240 | 9.3% | 1.007 | 0.2 | 4.00 | 321 | 0.001 | 37,542 | 0.110 | 0 | 0.00 | 0 | 100,224 | 534 | 0.0% | 130 |
| SHA-256 accel block | 585,822 | 162,844 | 0.278 | 229,416 | 78.3% | 1.409 | 64.1 | 2.72 | 30,721 | 0.189 | 56,332 | 1.000 | 31,744 | 5.00 | 126,976 | 0 | 0 | 21.7% | 0 |
| SHA-256 accel byte API | 2,860,176 | 1,029,153 | 0.360 | 1,347,621 | 94.2% | 1.309 | 42.9 | 3.14 | 104,449 | 0.101 | 238,606 | 1.000 | 31,744 | 5.00 | 126,976 | 0 | 0 | 4.4% | 2,048 |
| SHA-512 accel chain | 2,531,505 | 1,011,752 | 0.400 | 1,181,744 | 93.4% | 1.168 | 33.1 | 3.34 | 94,209 | 0.093 | 139,282 | 1.000 | 40,960 | 5.00 | 163,840 | 0 | 0 | 6.5% | 0 |
| SHA3-256 accel chain | 1,403,005 | 555,048 | 0.396 | 658,480 | 93.9% | 1.186 | 33.4 | 3.33 | 48,129 | 0.087 | 77,842 | 1.000 | 20,480 | 5.00 | 81,920 | 0 | 0 | 5.8% | 0 |
| bulk SHA-512 accel | 274,480 | 66,472 | 0.242 | 99,383 | 72.4% | 1.495 | 74.4 | 2.51 | 16,460 | 0.248 | 32,879 | 1.000 | 16,409 | 5.00 | 65,636 | 0 | 0 | 26.9% | 0 |
| bulk SHA3-256 accel | 273,326 | 66,055 | 0.242 | 98,907 | 72.4% | 1.497 | 74.6 | 2.51 | 16,422 | 0.249 | 32,834 | 1.000 | 16,396 | 5.00 | 65,584 | 0 | 0 | 27.0% | 0 |

## sky130 / soc

| Region | cycles | instret | IPC | ic_access | I$ port busy | fetches/instr | RVC % | bytes/instr | redirects | redirects/instr | D$ accesses | stk_dc_lat/access | uncached | cycles/uncached | stk_io | stk_vls | ret_vls | bus busy | muldiv_busy |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| CoreMark scalar | 23,030,662 | 5,246,413 | 0.228 | 6,699,401 | 87.3% | 1.277 | 51.4 | 2.97 | 744,296 | 0.142 | 1,365,092 | 2.000 | 0 | 0.00 | 0 | 0 | 0 | 0.0% | 375,840 |
| CoreMark sdk | 23,365,328 | 5,238,336 | 0.224 | 6,796,902 | 87.3% | 1.298 | 51.2 | 2.98 | 743,736 | 0.142 | 1,364,935 | 1.985 | 0 | 0.00 | 0 | 46,740 | 4,801 | 0.1% | 375,840 |
| Dhrystone scalar | 5,272,386 | 1,036,022 | 0.196 | 1,426,032 | 81.1% | 1.376 | 73.7 | 2.53 | 179,999 | 0.174 | 390,006 | 2.000 | 0 | 0.00 | 0 | 0 | 0 | 2.4% | 6,000 |
| Dhrystone sdk | 5,966,289 | 1,022,022 | 0.171 | 1,300,025 | 65.4% | 1.272 | 73.2 | 2.54 | 179,999 | 0.176 | 584,006 | 1.233 | 0 | 0.00 | 0 | 1,008,000 | 4,000 | 3.3% | 6,000 |
| SHA-256 C | 16,009,614 | 3,714,106 | 0.232 | 5,019,714 | 94.1% | 1.352 | 37.4 | 3.25 | 146,433 | 0.039 | 475,170 | 2.000 | 0 | 0.00 | 0 | 0 | 0 | 0.0% | 0 |
| SHA-256 Zknh | 11,005,342 | 2,731,067 | 0.248 | 3,351,628 | 91.4% | 1.227 | 55.0 | 2.90 | 146,433 | 0.054 | 475,171 | 2.000 | 0 | 0.00 | 0 | 0 | 0 | 0.0% | 0 |
| SHA-256 RVV x16 | 5,067,923 | 219,780 | 0.043 | 221,240 | 13.1% | 1.007 | 0.2 | 4.00 | 321 | 0.001 | 37,542 | 0.220 | 0 | 0.00 | 0 | 138,252 | 534 | 0.0% | 130 |
| SHA-256 accel block | 811,188 | 159,772 | 0.197 | 202,792 | 75.0% | 1.269 | 63.5 | 2.73 | 29,697 | 0.186 | 55,308 | 1.445 | 30,720 | 5.00 | 122,880 | 0 | 0 | 15.2% | 0 |
| SHA-256 accel byte API | 4,528,373 | 1,026,081 | 0.227 | 1,319,973 | 87.4% | 1.286 | 42.7 | 3.15 | 103,425 | 0.101 | 237,582 | 1.871 | 30,720 | 5.00 | 122,880 | 0 | 0 | 2.7% | 2,048 |
| SHA-512 accel chain | 3,865,902 | 1,005,606 | 0.260 | 1,158,188 | 89.9% | 1.152 | 32.7 | 3.35 | 92,160 | 0.092 | 137,233 | 1.716 | 38,911 | 5.00 | 155,644 | 0 | 0 | 4.0% | 0 |
| SHA3-256 accel chain | 2,171,108 | 555,049 | 0.256 | 651,312 | 90.0% | 1.173 | 33.4 | 3.33 | 48,129 | 0.087 | 77,842 | 1.737 | 20,480 | 5.00 | 81,920 | 0 | 0 | 3.8% | 0 |
| bulk SHA-512 accel | 376,620 | 66,460 | 0.176 | 82,984 | 66.1% | 1.249 | 74.4 | 2.51 | 16,456 | 0.248 | 32,875 | 1.501 | 16,405 | 5.00 | 65,620 | 0 | 0 | 19.9% | 0 |
| bulk SHA3-256 accel | 374,940 | 66,055 | 0.176 | 82,524 | 66.0% | 1.249 | 74.6 | 2.51 | 16,422 | 0.249 | 32,834 | 1.501 | 16,396 | 5.00 | 65,584 | 0 | 0 | 20.0% | 0 |

## Per-operation figures

- SHA-256 accelerator block API: 159.0 instructions/hash, 31.0 uncached accesses/hash, stk_io 124.0 cycles/hash, stk_io share 21.7%.
- SHA-256 accelerator byte API: 1005.0 instructions/hash, 846.0 more than the block API; same uncached accesses (31.0/hash).
- Bulk SHA-512 accelerator (soc): 16.75 cycles per 32-bit word; per word: retire 4.06, fetch_lat 5.06, branch 1.00, dc_lat 2.01, io 4.01, dc_miss 0.61; dc_miss 894 at 12.2 cycles; bus busy 26.9%.
- Bulk SHA-512 accelerator (axi): 18.14 cycles per 32-bit word; per word: retire 4.06, fetch_lat 5.06, branch 1.00, dc_lat 2.01, io 4.01, dc_miss 2.00; dc_miss 894 at 37.7 cycles; bus busy 32.5%.
- SHA-256 RVV x16: 213,131 vector arithmetic instructions, stk_vec 4,257,501 = 19.98 EX cycles each; region cycles per vector instruction 22.30.
- Dhrystone sdk (default): stk_vls 672,000 over 4,000 vector LS instructions = 168 cycles each (19.3% of cycles); sdk minus scalar = 411,998 cycles.
- Dhrystone sdk (fpga): stk_vls 784,000 over 4,000 vector LS instructions = 196 cycles each (21.8% of cycles); sdk minus scalar = 523,998 cycles.
- Dhrystone sdk (sky130): stk_vls 1,008,000 over 4,000 vector LS instructions = 252 cycles each (16.9% of cycles); sdk minus scalar = 693,903 cycles.

## Kernels: where the cycles go (default / soc, % of cycles)

| Region | cycles | stk_vec % | stk_vls % | stk_fpu % | stk_muldiv % | I$ port busy |
|---|---:|---:|---:|---:|---:|---:|
| vadd_i32 C | 78,078 | 0.0 | 0.0 | 0.0 | 0.0 | 94.6% |
| vadd_i32 RVV | 43,212 | 9.8 | 87.9 | 0.0 | 0.0 | 2.4% |
| vadd_i64 C | 39,370 | 0.0 | 0.0 | 0.0 | 0.0 | 94.0% |
| vadd_i64 RVV | 22,302 | 9.8 | 86.0 | 0.0 | 0.0 | 4.6% |
| daxpy C | 59,951 | 0.0 | 0.0 | 20.5 | 0.0 | 75.4% |
| daxpy RVV | 36,088 | 45.8 | 51.8 | 0.0 | 0.0 | 2.7% |
| saxpy C | 131,614 | 0.0 | 0.0 | 18.7 | 0.0 | 81.0% |
| saxpy RVV | 70,934 | 46.4 | 52.4 | 0.0 | 0.0 | 1.4% |
| ddot C | 51,427 | 0.0 | 0.0 | 23.9 | 0.0 | 72.0% |
| ddot RVV | 31,617 | 58.1 | 38.9 | 0.0 | 0.0 | 3.1% |
| idot_i32 C | 78,002 | 0.0 | 0.0 | 0.0 | 10.5 | 84.2% |
| idot_i32 RVV | 51,647 | 49.2 | 47.6 | 0.0 | 0.0 | 3.4% |
| memcpy C | 33,122 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8% |
| memcpy RVV | 13,209 | 0.0 | 94.1 | 0.0 | 0.0 | 6.3% |
| memcpy RVV-e8 | 99,129 | 0.0 | 99.2 | 0.0 | 0.0 | 0.8% |
| memset C | 20,831 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8% |
| memset RVV | 7,038 | 3.9 | 87.3 | 0.0 | 0.1 | 9.0% |
| memset RVV-e8 | 51,872 | 4.0 | 94.8 | 0.0 | 0.0 | 1.3% |
| dgemm C | 2,886,016 | 0.0 | 0.0 | 27.2 | 0.0 | 67.4% |
| dgemm RVV | 1,561,900 | 68.5 | 27.0 | 0.0 | 0.0 | 4.1% |
| sgemm C | 3,238,248 | 0.0 | 0.0 | 24.3 | 0.0 | 75.7% |
| sgemm RVV | 1,563,177 | 68.4 | 26.0 | 0.0 | 0.0 | 5.6% |
| fir_f32 C | 1,917,178 | 0.0 | 0.0 | 20.5 | 0.0 | 79.5% |
| fir_f32 RVV | 747,633 | 71.0 | 28.0 | 0.0 | 0.0 | 1.1% |
| mac_i8 C | 344,236 | 0.0 | 0.0 | 0.0 | 9.5 | 85.7% |
| mac_i8 RVV | 199,144 | 49.7 | 49.4 | 0.0 | 0.0 | 1.0% |
| mac_i16 C | 172,210 | 0.0 | 0.0 | 0.0 | 9.5 | 85.7% |
| mac_i16 RVV | 93,107 | 45.4 | 52.8 | 0.0 | 0.0 | 1.9% |

## Throughput at a clock (arithmetic on simulation cycles; F2 measures 62.5 MHz on hardware)

25 MHz is the clock the W7 sky130 floorplan meets after global routing (docs/SOC_AREA.md); 100 MHz is the #53 FPGA target. Neither is a measured chip or FPGA figure.

| Region | config | cycles/iteration | per second at 25 MHz | at 62.5 MHz | at 100 MHz |
|---|---|---:|---:|---:|---:|
| Dhrystone scalar (DMIPS) | default | 1,535.1 | 9.3 | 23.2 | 37.1 |
| Dhrystone scalar (DMIPS) | fpga | 1,535.1 | 9.3 | 23.2 | 37.1 |
| Dhrystone scalar (DMIPS) | sky130 | 2,636.2 | 5.4 | 13.5 | 21.6 |
| CoreMark scalar (CoreMark) | default | 716,890.3 | 34.87 | 87.18 | 139.49 |
| CoreMark scalar (CoreMark) | fpga | 716,890.3 | 34.87 | 87.18 | 139.49 |
| CoreMark scalar (CoreMark) | sky130 | 1,151,533.1 | 21.71 | 54.28 | 86.84 |
| SHA-256 C (hashes) | default | 9,918.2 | 2,521 | 6,302 | 10,082 |
| SHA-256 C (hashes) | fpga | 9,918.2 | 2,521 | 6,302 | 10,082 |
| SHA-256 C (hashes) | sky130 | 15,634.4 | 1,599 | 3,998 | 6,396 |
| SHA-256 Zknh (hashes) | default | 6,753.2 | 3,702 | 9,255 | 14,808 |
| SHA-256 Zknh (hashes) | fpga | 6,753.2 | 3,702 | 9,255 | 14,808 |
| SHA-256 Zknh (hashes) | sky130 | 10,747.4 | 2,326 | 5,815 | 9,305 |
| SHA-256 RVV x16 (hashes, 16 chains) | default | 4,642.0 | 5,386 | 13,464 | 21,542 |
| SHA-256 RVV x16 (hashes, 16 chains) | fpga | 4,854.6 | 5,150 | 12,874 | 20,599 |
| SHA-256 RVV x16 (hashes, 16 chains) | sky130 | 4,949.1 | 5,051 | 12,628 | 20,206 |
| SHA-256 accel block (hashes) | default | 572.1 | 43,699 | 109,248 | 174,797 |
| SHA-256 accel block (hashes) | fpga | 572.1 | 43,699 | 109,248 | 174,797 |
| SHA-256 accel block (hashes) | sky130 | 792.2 | 31,559 | 78,897 | 126,235 |
| SHA-256 accel byte API (hashes) | default | 2,793.1 | 8,950 | 22,376 | 35,802 |
| SHA-256 accel byte API (hashes) | fpga | 2,793.1 | 8,950 | 22,376 | 35,802 |
| SHA-256 accel byte API (hashes) | sky130 | 4,422.2 | 5,653 | 14,133 | 22,613 |
| SHA-512 accel chain (hashes) | default | 2,472.2 | 10,113 | 25,281 | 40,450 |
| SHA-512 accel chain (hashes) | fpga | 2,472.2 | 10,113 | 25,281 | 40,450 |
| SHA-512 accel chain (hashes) | sky130 | 3,775.3 | 6,622 | 16,555 | 26,488 |
| SHA3-256 accel chain (hashes) | default | 1,370.1 | 18,247 | 45,616 | 72,986 |
| SHA3-256 accel chain (hashes) | fpga | 1,370.1 | 18,247 | 45,616 | 72,986 |
| SHA3-256 accel chain (hashes) | sky130 | 2,120.2 | 11,791 | 29,478 | 47,165 |
