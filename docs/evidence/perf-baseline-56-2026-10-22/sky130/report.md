# Sigil performance report

- Date (UTC): 2026-10-22T11:35:34Z
- Commit: `8d15410a5b525016ba4a877b50572e4f42f06293` (56-perf-harness); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Host: ip-172-31-65-164 Linux 7.0.0-1014-aws x86_64
- Memory model `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`
- Memory model `axi`: `--axi-lat 24:24 --axi-gap 0 --axi-ready 100 --uart-pop 100`
- Repeats: 2; deterministic: yes (identical counts)
- Image `coremark-scalar`: sha256 `c56fb68ce74d117d`, performance seeds 0,0,0x66; scalar ISA -march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
- Image `coremark-sdk`: sha256 `400c9a3ccba55f2a`, performance seeds 0,0,0x66; SDK default -march (with V)
- Image `coremark-validation`: sha256 `d0bf2ae1cf5c4d9b`, validation seeds 0x3415,0x3415,0x66 (EEMBC run rule 2), scalar ISA; a correctness run, not the score
- Image `dhrystone-scalar`: sha256 `b7173e4e26bda6dc`, scalar ISA, -march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh (the DMIPS/MHz headline)
- Image `dhrystone-sdk`: sha256 `d15a6c7161f7cfdf`, SDK default -march (with V): GCC expands the 56-byte struct copy into a vle8/vse8 loop
- Image `kernels-autovec`: sha256 `44822b77c88564db`, C kernels with the SDK -march (with V) at -O3: C = GCC 16 auto-vectorization (at -O2 it vectorizes only the FIR inner loop)
- Image `kernels-scalar`: sha256 `afc146321f9cc028`, C kernels for the scalar ISA (-march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh, -O2): C = scalar baseline
- Image `micro_dmem-default`: sha256 `9b4694a0e1414d13`, SDK flags
- Image `micro_imem-default`: sha256 `45f135d297d3a19e`, SDK flags
- Image `micro_pipe-default`: sha256 `2ba45578d87e87af`, SDK flags
- Image `micro_units-default`: sha256 `4f75e144b097a1a9`, SDK flags
- Image `micro_vec-default`: sha256 `7702b22c9da8d92b`, SDK flags
- Image `sha256chain-sdk`: sha256 `4df1e870f74f325b`, SDK default -march (rv64gcv + B, Zbc, Zcb, Zicond, Zbk*, Zkn*): every implementation is in the one image
- Image `sha256chain_bulk-sdk`: sha256 `1bbffc8acf82cbeb`, SDK default -march (rv64gcv + B, Zbc, Zcb, Zicond, Zbk*, Zkn*): every implementation is in the one image

## Configurations (as reported by the counter records)

| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |
|---|---|---|---|---|---:|---:|---:|
| sky130 | axi | `fpga_top_tb_sky130` | 64x1x64 | 64x1x64 | 1 | 1 | 1 |
| sky130 | soc | `soc_rtl_tb_sky130` | 64x1x64 | 64x1x64 | 1 | 1 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Net cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| coremark [scalar] | sky130 | axi | 20 | 23,060,820 | 5,246,413 | 0.228 | 4.396 | 1,153,041.00 | - | 0.867 CoreMark/MHz | 23,060,770 |
| coremark [scalar] | sky130 | soc | 20 | 23,030,662 | 5,246,413 | 0.228 | 4.390 | 1,151,533.10 | - | 0.868 CoreMark/MHz | 23,030,612 |
| coremark [sdk] | sky130 | axi | 20 | 23,400,453 | 5,238,336 | 0.224 | 4.467 | 1,170,022.65 | - | 0.855 CoreMark/MHz | 23,400,400 |
| coremark [sdk] | sky130 | soc | 20 | 23,365,328 | 5,238,336 | 0.224 | 4.460 | 1,168,266.40 | - | 0.856 CoreMark/MHz | 23,365,275 |
| coremark [validation] | sky130 | axi | 20 | 23,110,518 | 5,253,779 | 0.227 | 4.399 | 1,155,525.90 | - | 0.865 CoreMark/MHz | 23,110,468 |
| coremark [validation] | sky130 | soc | 20 | 23,079,360 | 5,253,779 | 0.228 | 4.393 | 1,153,968.00 | - | 0.867 CoreMark/MHz | 23,079,310 |
| dhrystone [scalar] | sky130 | axi | 2000 | 5,670,943 | 1,036,022 | 0.183 | 5.474 | 2,835.47 | - | 0.201 DMIPS/MHz | 5,670,890 |
| dhrystone [scalar] | sky130 | soc | 2000 | 5,272,386 | 1,036,022 | 0.196 | 5.089 | 2,636.19 | - | 0.216 DMIPS/MHz | 5,272,333 |
| dhrystone [sdk] | sky130 | axi | 2000 | 6,596,705 | 1,022,022 | 0.155 | 6.455 | 3,298.35 | - | 0.173 DMIPS/MHz | 6,596,623 |
| dhrystone [sdk] | sky130 | soc | 2000 | 5,966,289 | 1,022,022 | 0.171 | 5.838 | 2,983.14 | - | 0.191 DMIPS/MHz | 5,966,232 |
| kernels [autovec] vadd_i32 C | sky130 | axi | 4 | 110,966 | 2,654 | 0.024 | 41.811 | 27,741.50 | - | 0.0369 elem/cycle | 110,851 |
| kernels [autovec] vadd_i32 C | sky130 | soc | 4 | 84,561 | 2,654 | 0.031 | 31.862 | 21,140.25 | - | 0.0484 elem/cycle | 84,496 |
| kernels [autovec] vadd_i32 RVV | sky130 | axi | 4 | 100,701 | 372 | 0.004 | 270.702 | 25,175.25 | - | 0.0407 elem/cycle | 100,497 |
| kernels [autovec] vadd_i32 RVV | sky130 | soc | 4 | 73,125 | 372 | 0.005 | 196.573 | 18,281.25 | - | 0.0560 elem/cycle | 73,029 |
| kernels [autovec] vadd_i64 C | sky130 | axi | 4 | 80,767 | 2,652 | 0.033 | 30.455 | 20,191.75 | - | 0.0254 elem/cycle | 80,652 |
| kernels [autovec] vadd_i64 C | sky130 | soc | 4 | 54,337 | 2,652 | 0.049 | 20.489 | 13,584.25 | - | 0.0377 elem/cycle | 54,272 |
| kernels [autovec] vadd_i64 RVV | sky130 | axi | 4 | 72,029 | 372 | 0.005 | 193.626 | 18,007.25 | - | 0.0284 elem/cycle | 71,825 |
| kernels [autovec] vadd_i64 RVV | sky130 | soc | 4 | 44,453 | 372 | 0.008 | 119.497 | 11,113.25 | - | 0.0461 elem/cycle | 44,357 |
| kernels [autovec] daxpy C | sky130 | axi | 4 | 87,562 | 2,656 | 0.030 | 32.968 | 21,890.50 | - | 0.0234 elem/cycle | 87,432 |
| kernels [autovec] daxpy C | sky130 | soc | 4 | 66,247 | 2,656 | 0.040 | 24.942 | 16,561.75 | - | 0.0309 elem/cycle | 66,167 |
| kernels [autovec] daxpy RVV | sky130 | axi | 4 | 76,185 | 340 | 0.004 | 224.074 | 19,046.25 | - | 0.0269 elem/cycle | 75,971 |
| kernels [autovec] daxpy RVV | sky130 | soc | 4 | 55,365 | 340 | 0.006 | 162.838 | 13,841.25 | - | 0.0370 elem/cycle | 55,259 |
| kernels [autovec] saxpy C | sky130 | axi | 4 | 132,190 | 2,652 | 0.020 | 49.845 | 33,047.50 | - | 0.0310 elem/cycle | 132,038 |
| kernels [autovec] saxpy C | sky130 | soc | 4 | 110,850 | 2,652 | 0.024 | 41.799 | 27,712.50 | - | 0.0370 elem/cycle | 110,773 |
| kernels [autovec] saxpy RVV | sky130 | axi | 4 | 119,198 | 340 | 0.003 | 350.582 | 29,799.50 | - | 0.0344 elem/cycle | 119,016 |
| kernels [autovec] saxpy RVV | sky130 | soc | 4 | 98,378 | 340 | 0.003 | 289.347 | 24,594.50 | - | 0.0416 elem/cycle | 98,279 |
| kernels [autovec] ddot C | sky130 | axi | 4 | 80,914 | 3,384 | 0.042 | 23.911 | 20,228.50 | - | 0.0253 elem/cycle | 80,784 |
| kernels [autovec] ddot C | sky130 | soc | 4 | 67,749 | 3,384 | 0.050 | 20.020 | 16,937.25 | - | 0.0302 elem/cycle | 67,669 |
| kernels [autovec] ddot RVV | sky130 | axi | 4 | 55,757 | 332 | 0.006 | 167.943 | 13,939.25 | - | 0.0367 elem/cycle | 55,642 |
| kernels [autovec] ddot RVV | sky130 | soc | 4 | 42,592 | 332 | 0.008 | 128.289 | 10,648.00 | - | 0.0481 elem/cycle | 42,527 |
| kernels [autovec] idot_i32 C | sky130 | axi | 4 | 97,792 | 4,172 | 0.043 | 23.440 | 24,448.00 | - | 0.0419 elem/cycle | 97,677 |
| kernels [autovec] idot_i32 C | sky130 | soc | 4 | 84,652 | 4,172 | 0.049 | 20.291 | 21,163.00 | - | 0.0484 elem/cycle | 84,587 |
| kernels [autovec] idot_i32 RVV | sky130 | axi | 4 | 80,293 | 588 | 0.007 | 136.553 | 20,073.25 | - | 0.0510 elem/cycle | 80,163 |
| kernels [autovec] idot_i32 RVV | sky130 | soc | 4 | 67,153 | 588 | 0.009 | 114.206 | 16,788.25 | - | 0.0610 elem/cycle | 67,073 |
| kernels [autovec] memcpy C | sky130 | axi | 4 | 88,030 | 10,356 | 0.118 | 8.500 | 22,007.50 | - | 0.1861 byte/cycle | 87,912 |
| kernels [autovec] memcpy C | sky130 | soc | 4 | 68,141 | 10,356 | 0.152 | 6.580 | 17,035.25 | - | 0.2404 byte/cycle | 68,073 |
| kernels [autovec] memcpy RVV | sky130 | axi | 4 | 51,155 | 276 | 0.005 | 185.344 | 12,788.75 | - | 0.3203 byte/cycle | 50,948 |
| kernels [autovec] memcpy RVV | sky130 | soc | 4 | 30,441 | 276 | 0.009 | 110.293 | 7,610.25 | - | 0.5382 byte/cycle | 30,342 |
| kernels [autovec] memcpy RVV-e8 | sky130 | axi | 4 | 179,647 | 272 | 0.002 | 660.467 | 44,911.75 | - | 0.0912 byte/cycle | 179,442 |
| kernels [autovec] memcpy RVV-e8 | sky130 | soc | 4 | 159,283 | 272 | 0.002 | 585.599 | 39,820.75 | - | 0.1029 byte/cycle | 159,186 |
| kernels [autovec] memset C | sky130 | axi | 4 | 35,675 | 6,264 | 0.176 | 5.695 | 8,918.75 | - | 0.4593 byte/cycle | 35,413 |
| kernels [autovec] memset C | sky130 | soc | 4 | 35,418 | 6,264 | 0.177 | 5.654 | 8,854.50 | - | 0.4626 byte/cycle | 35,297 |
| kernels [autovec] memset RVV | sky130 | axi | 4 | 11,869 | 240 | 0.020 | 49.454 | 2,967.25 | - | 1.3804 byte/cycle | 11,638 |
| kernels [autovec] memset RVV | sky130 | soc | 4 | 11,612 | 240 | 0.021 | 48.383 | 2,903.00 | - | 1.4110 byte/cycle | 11,497 |
| kernels [autovec] memset RVV-e8 | sky130 | axi | 4 | 85,400 | 216 | 0.003 | 395.370 | 21,350.00 | - | 0.1919 byte/cycle | 85,141 |
| kernels [autovec] memset RVV-e8 | sky130 | soc | 4 | 85,143 | 216 | 0.003 | 394.181 | 21,285.75 | - | 0.1924 byte/cycle | 85,025 |
| kernels [autovec] dgemm C | sky130 | axi | 4 | 9,236,265 | 828,348 | 0.090 | 11.150 | 2,309,066.25 | - | 0.0142 mac/cycle | 9,236,113 |
| kernels [autovec] dgemm C | sky130 | soc | 4 | 5,770,390 | 828,348 | 0.144 | 6.966 | 1,442,597.50 | - | 0.0227 mac/cycle | 5,770,313 |
| kernels [autovec] dgemm RVV | sky130 | axi | 4 | 2,400,358 | 26,692 | 0.011 | 89.928 | 600,089.50 | - | 0.0546 mac/cycle | 2,400,228 |
| kernels [autovec] dgemm RVV | sky130 | soc | 4 | 1,940,549 | 26,692 | 0.014 | 72.702 | 485,137.25 | - | 0.0675 mac/cycle | 1,940,469 |
| kernels [autovec] sgemm C | sky130 | axi | 4 | 5,708,712 | 828,348 | 0.145 | 6.892 | 1,427,178.00 | - | 0.0230 mac/cycle | 5,708,545 |
| kernels [autovec] sgemm C | sky130 | soc | 4 | 5,147,715 | 828,348 | 0.161 | 6.214 | 1,286,928.75 | - | 0.0255 mac/cycle | 5,147,623 |
| kernels [autovec] sgemm RVV | sky130 | axi | 4 | 1,820,161 | 26,692 | 0.015 | 68.191 | 455,040.25 | - | 0.0720 mac/cycle | 1,820,046 |
| kernels [autovec] sgemm RVV | sky130 | soc | 4 | 1,776,462 | 26,692 | 0.015 | 66.554 | 444,115.50 | - | 0.0738 mac/cycle | 1,776,397 |
| kernels [autovec] fir_f32 C | sky130 | axi | 4 | 1,812,975 | 86,080 | 0.047 | 21.062 | 453,243.75 | - | 0.0361 mac/cycle | 1,812,848 |
| kernels [autovec] fir_f32 C | sky130 | soc | 4 | 1,781,668 | 86,080 | 0.048 | 20.698 | 445,417.00 | - | 0.0368 mac/cycle | 1,781,591 |
| kernels [autovec] fir_f32 RVV | sky130 | axi | 4 | 863,381 | 3,488 | 0.004 | 247.529 | 215,845.25 | - | 0.0759 mac/cycle | 863,228 |
| kernels [autovec] fir_f32 RVV | sky130 | soc | 4 | 838,936 | 3,488 | 0.004 | 240.521 | 209,734.00 | - | 0.0781 mac/cycle | 838,858 |
| kernels [autovec] mac_i8 C | sky130 | axi | 4 | 315,999 | 11,340 | 0.036 | 27.866 | 78,999.75 | - | 0.0518 mac/cycle | 315,881 |
| kernels [autovec] mac_i8 C | sky130 | soc | 4 | 302,834 | 11,340 | 0.037 | 26.705 | 75,708.50 | - | 0.0541 mac/cycle | 302,766 |
| kernels [autovec] mac_i8 RVV | sky130 | axi | 4 | 252,524 | 708 | 0.003 | 356.672 | 63,131.00 | - | 0.0649 mac/cycle | 252,397 |
| kernels [autovec] mac_i8 RVV | sky130 | soc | 4 | 239,359 | 708 | 0.003 | 338.078 | 59,839.75 | - | 0.0684 mac/cycle | 239,282 |
| kernels [autovec] mac_i16 C | sky130 | axi | 4 | 147,008 | 4,172 | 0.028 | 35.237 | 36,752.00 | - | 0.0557 mac/cycle | 146,930 |
| kernels [autovec] mac_i16 C | sky130 | soc | 4 | 133,868 | 4,172 | 0.031 | 32.087 | 33,467.00 | - | 0.0612 mac/cycle | 133,815 |
| kernels [autovec] mac_i16 RVV | sky130 | axi | 4 | 129,955 | 588 | 0.005 | 221.012 | 32,488.75 | - | 0.0630 mac/cycle | 129,827 |
| kernels [autovec] mac_i16 RVV | sky130 | soc | 4 | 116,815 | 588 | 0.005 | 198.665 | 29,203.75 | - | 0.0701 mac/cycle | 116,737 |
| kernels [scalar] vadd_i32 C | sky130 | axi | 4 | 175,310 | 32,826 | 0.187 | 5.341 | 43,827.50 | - | 0.0234 elem/cycle | 175,195 |
| kernels [scalar] vadd_i32 C | sky130 | soc | 4 | 148,905 | 32,826 | 0.220 | 4.536 | 37,226.25 | - | 0.0275 elem/cycle | 148,840 |
| kernels [scalar] vadd_i32 RVV | sky130 | axi | 4 | 100,701 | 372 | 0.004 | 270.702 | 25,175.25 | - | 0.0407 elem/cycle | 100,497 |
| kernels [scalar] vadd_i32 RVV | sky130 | soc | 4 | 73,125 | 372 | 0.005 | 196.573 | 18,281.25 | - | 0.0560 elem/cycle | 73,029 |
| kernels [scalar] vadd_i64 C | sky130 | axi | 4 | 107,759 | 16,440 | 0.153 | 6.555 | 26,939.75 | - | 0.0190 elem/cycle | 107,644 |
| kernels [scalar] vadd_i64 C | sky130 | soc | 4 | 81,329 | 16,440 | 0.202 | 4.947 | 20,332.25 | - | 0.0252 elem/cycle | 81,264 |
| kernels [scalar] vadd_i64 RVV | sky130 | axi | 4 | 72,029 | 372 | 0.005 | 193.626 | 18,007.25 | - | 0.0284 elem/cycle | 71,825 |
| kernels [scalar] vadd_i64 RVV | sky130 | soc | 4 | 44,453 | 372 | 0.008 | 119.497 | 11,113.25 | - | 0.0461 elem/cycle | 44,357 |
| kernels [scalar] daxpy C | sky130 | axi | 4 | 122,759 | 14,392 | 0.117 | 8.530 | 30,689.75 | - | 0.0167 elem/cycle | 122,629 |
| kernels [scalar] daxpy C | sky130 | soc | 4 | 101,419 | 14,392 | 0.142 | 7.047 | 25,354.75 | - | 0.0202 elem/cycle | 101,339 |
| kernels [scalar] daxpy RVV | sky130 | axi | 4 | 76,185 | 340 | 0.004 | 224.074 | 19,046.25 | - | 0.0269 elem/cycle | 75,971 |
| kernels [scalar] daxpy RVV | sky130 | soc | 4 | 55,365 | 340 | 0.006 | 162.838 | 13,841.25 | - | 0.0370 elem/cycle | 55,259 |
| kernels [scalar] saxpy C | sky130 | axi | 4 | 237,389 | 28,728 | 0.121 | 8.263 | 59,347.25 | - | 0.0173 elem/cycle | 237,237 |
| kernels [scalar] saxpy C | sky130 | soc | 4 | 216,074 | 28,728 | 0.133 | 7.521 | 54,018.50 | - | 0.0190 elem/cycle | 215,997 |
| kernels [scalar] saxpy RVV | sky130 | axi | 4 | 119,198 | 340 | 0.003 | 350.582 | 29,799.50 | - | 0.0344 elem/cycle | 119,016 |
| kernels [scalar] saxpy RVV | sky130 | soc | 4 | 98,378 | 340 | 0.003 | 289.347 | 24,594.50 | - | 0.0416 elem/cycle | 98,279 |
| kernels [scalar] ddot C | sky130 | axi | 4 | 93,482 | 12,348 | 0.132 | 7.571 | 23,370.50 | - | 0.0219 elem/cycle | 93,352 |
| kernels [scalar] ddot C | sky130 | soc | 4 | 80,317 | 12,348 | 0.154 | 6.504 | 20,079.25 | - | 0.0255 elem/cycle | 80,237 |
| kernels [scalar] ddot RVV | sky130 | axi | 4 | 55,757 | 332 | 0.006 | 167.943 | 13,939.25 | - | 0.0367 elem/cycle | 55,642 |
| kernels [scalar] ddot RVV | sky130 | soc | 4 | 42,592 | 332 | 0.008 | 128.289 | 10,648.00 | - | 0.0481 elem/cycle | 42,527 |
| kernels [scalar] idot_i32 C | sky130 | axi | 4 | 138,504 | 28,732 | 0.207 | 4.821 | 34,626.00 | - | 0.0296 elem/cycle | 138,389 |
| kernels [scalar] idot_i32 C | sky130 | soc | 4 | 125,364 | 28,732 | 0.229 | 4.363 | 31,341.00 | - | 0.0327 elem/cycle | 125,299 |
| kernels [scalar] idot_i32 RVV | sky130 | axi | 4 | 80,293 | 588 | 0.007 | 136.553 | 20,073.25 | - | 0.0510 elem/cycle | 80,163 |
| kernels [scalar] idot_i32 RVV | sky130 | soc | 4 | 67,153 | 588 | 0.009 | 114.206 | 16,788.25 | - | 0.0610 elem/cycle | 67,073 |
| kernels [scalar] memcpy C | sky130 | axi | 4 | 88,030 | 10,356 | 0.118 | 8.500 | 22,007.50 | - | 0.1861 byte/cycle | 87,912 |
| kernels [scalar] memcpy C | sky130 | soc | 4 | 68,141 | 10,356 | 0.152 | 6.580 | 17,035.25 | - | 0.2404 byte/cycle | 68,073 |
| kernels [scalar] memcpy RVV | sky130 | axi | 4 | 51,155 | 276 | 0.005 | 185.344 | 12,788.75 | - | 0.3203 byte/cycle | 50,948 |
| kernels [scalar] memcpy RVV | sky130 | soc | 4 | 30,441 | 276 | 0.009 | 110.293 | 7,610.25 | - | 0.5382 byte/cycle | 30,342 |
| kernels [scalar] memcpy RVV-e8 | sky130 | axi | 4 | 179,647 | 272 | 0.002 | 660.467 | 44,911.75 | - | 0.0912 byte/cycle | 179,442 |
| kernels [scalar] memcpy RVV-e8 | sky130 | soc | 4 | 159,283 | 272 | 0.002 | 585.599 | 39,820.75 | - | 0.1029 byte/cycle | 159,186 |
| kernels [scalar] memset C | sky130 | axi | 4 | 35,675 | 6,264 | 0.176 | 5.695 | 8,918.75 | - | 0.4593 byte/cycle | 35,413 |
| kernels [scalar] memset C | sky130 | soc | 4 | 35,418 | 6,264 | 0.177 | 5.654 | 8,854.50 | - | 0.4626 byte/cycle | 35,297 |
| kernels [scalar] memset RVV | sky130 | axi | 4 | 11,869 | 240 | 0.020 | 49.454 | 2,967.25 | - | 1.3804 byte/cycle | 11,638 |
| kernels [scalar] memset RVV | sky130 | soc | 4 | 11,612 | 240 | 0.021 | 48.383 | 2,903.00 | - | 1.4110 byte/cycle | 11,497 |
| kernels [scalar] memset RVV-e8 | sky130 | axi | 4 | 85,400 | 216 | 0.003 | 395.370 | 21,350.00 | - | 0.1919 byte/cycle | 85,141 |
| kernels [scalar] memset RVV-e8 | sky130 | soc | 4 | 85,143 | 216 | 0.003 | 394.181 | 21,285.75 | - | 0.1924 byte/cycle | 85,025 |
| kernels [scalar] dgemm C | sky130 | axi | 4 | 9,236,265 | 828,348 | 0.090 | 11.150 | 2,309,066.25 | - | 0.0142 mac/cycle | 9,236,113 |
| kernels [scalar] dgemm C | sky130 | soc | 4 | 5,770,390 | 828,348 | 0.144 | 6.966 | 1,442,597.50 | - | 0.0227 mac/cycle | 5,770,313 |
| kernels [scalar] dgemm RVV | sky130 | axi | 4 | 2,400,358 | 26,692 | 0.011 | 89.928 | 600,089.50 | - | 0.0546 mac/cycle | 2,400,228 |
| kernels [scalar] dgemm RVV | sky130 | soc | 4 | 1,940,549 | 26,692 | 0.014 | 72.702 | 485,137.25 | - | 0.0675 mac/cycle | 1,940,469 |
| kernels [scalar] sgemm C | sky130 | axi | 4 | 5,708,712 | 828,348 | 0.145 | 6.892 | 1,427,178.00 | - | 0.0230 mac/cycle | 5,708,545 |
| kernels [scalar] sgemm C | sky130 | soc | 4 | 5,147,715 | 828,348 | 0.161 | 6.214 | 1,286,928.75 | - | 0.0255 mac/cycle | 5,147,623 |
| kernels [scalar] sgemm RVV | sky130 | axi | 4 | 1,820,161 | 26,692 | 0.015 | 68.191 | 455,040.25 | - | 0.0720 mac/cycle | 1,820,046 |
| kernels [scalar] sgemm RVV | sky130 | soc | 4 | 1,776,462 | 26,692 | 0.015 | 66.554 | 444,115.50 | - | 0.0738 mac/cycle | 1,776,397 |
| kernels [scalar] fir_f32 C | sky130 | axi | 4 | 2,997,783 | 426,052 | 0.142 | 7.036 | 749,445.75 | - | 0.0219 mac/cycle | 2,997,656 |
| kernels [scalar] fir_f32 C | sky130 | soc | 4 | 2,921,476 | 426,052 | 0.146 | 6.857 | 730,369.00 | - | 0.0224 mac/cycle | 2,921,399 |
| kernels [scalar] fir_f32 RVV | sky130 | axi | 4 | 863,381 | 3,488 | 0.004 | 247.529 | 215,845.25 | - | 0.0759 mac/cycle | 863,228 |
| kernels [scalar] fir_f32 RVV | sky130 | soc | 4 | 838,936 | 3,488 | 0.004 | 240.521 | 209,734.00 | - | 0.0781 mac/cycle | 838,858 |
| kernels [scalar] mac_i8 C | sky130 | axi | 4 | 544,039 | 114,748 | 0.211 | 4.741 | 136,009.75 | - | 0.0301 mac/cycle | 543,921 |
| kernels [scalar] mac_i8 C | sky130 | soc | 4 | 530,874 | 114,748 | 0.216 | 4.626 | 132,718.50 | - | 0.0309 mac/cycle | 530,806 |
| kernels [scalar] mac_i8 RVV | sky130 | axi | 4 | 252,524 | 708 | 0.003 | 356.672 | 63,131.00 | - | 0.0649 mac/cycle | 252,397 |
| kernels [scalar] mac_i8 RVV | sky130 | soc | 4 | 239,359 | 708 | 0.003 | 338.078 | 59,839.75 | - | 0.0684 mac/cycle | 239,282 |
| kernels [scalar] mac_i16 C | sky130 | axi | 4 | 282,160 | 57,404 | 0.203 | 4.915 | 70,540.00 | - | 0.0290 mac/cycle | 282,082 |
| kernels [scalar] mac_i16 C | sky130 | soc | 4 | 268,820 | 57,404 | 0.214 | 4.683 | 67,205.00 | - | 0.0305 mac/cycle | 268,767 |
| kernels [scalar] mac_i16 RVV | sky130 | axi | 4 | 129,955 | 588 | 0.005 | 221.012 | 32,488.75 | - | 0.0630 mac/cycle | 129,827 |
| kernels [scalar] mac_i16 RVV | sky130 | soc | 4 | 116,815 | 588 | 0.005 | 198.665 | 29,203.75 | - | 0.0701 mac/cycle | 116,737 |
| micro_dmem [default] empty | sky130 | axi | 4096 | 130 | 20 | 0.154 | 6.500 | 0.03 | (window) | - | 77 |
| micro_dmem [default] empty | sky130 | soc | 4096 | 105 | 20 | 0.190 | 5.250 | 0.03 | (window) | - | 52 |
| micro_dmem [default] chase_rand_1k | sky130 | axi | 4096 | 21,188 | 4,246 | 0.200 | 4.990 | 5.17 | 5.14 | - | 21,101 |
| micro_dmem [default] chase_rand_1k | sky130 | soc | 4096 | 21,163 | 4,246 | 0.201 | 4.984 | 5.17 | 5.14 | - | 21,101 |
| micro_dmem [default] chase_rand_2k | sky130 | axi | 4096 | 21,188 | 4,246 | 0.200 | 4.990 | 5.17 | 5.14 | - | 21,101 |
| micro_dmem [default] chase_rand_2k | sky130 | soc | 4096 | 21,163 | 4,246 | 0.201 | 4.984 | 5.17 | 5.14 | - | 21,101 |
| micro_dmem [default] chase_rand_4k | sky130 | axi | 4096 | 21,425 | 4,246 | 0.198 | 5.046 | 5.23 | 5.20 | - | 21,264 |
| micro_dmem [default] chase_rand_4k | sky130 | soc | 4096 | 21,242 | 4,246 | 0.200 | 5.003 | 5.19 | 5.16 | - | 21,156 |
| micro_dmem [default] chase_rand_8k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_8k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_rand_12k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_12k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_rand_16k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_16k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_rand_20k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_20k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_rand_24k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_24k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_rand_32k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_32k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_rand_64k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_64k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_rand_128k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_128k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_rand_256k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_rand_256k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_seq_4k | sky130 | axi | 4096 | 21,425 | 4,246 | 0.198 | 5.046 | 5.23 | 5.20 | - | 21,264 |
| micro_dmem [default] chase_seq_4k | sky130 | soc | 4096 | 21,242 | 4,246 | 0.200 | 5.003 | 5.19 | 5.16 | - | 21,156 |
| micro_dmem [default] chase_seq_8k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_seq_8k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_seq_16k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_seq_16k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] chase_seq_32k | sky130 | axi | 4096 | 172,940 | 4,246 | 0.025 | 40.730 | 42.22 | 42.19 | - | 172,779 |
| micro_dmem [default] chase_seq_32k | sky130 | soc | 4096 | 70,382 | 4,246 | 0.060 | 16.576 | 17.18 | 17.16 | - | 70,296 |
| micro_dmem [default] stream_ld | sky130 | axi | 4096 | 42,040 | 4,829 | 0.115 | 8.706 | 10.26 | 10.23 | - | 41,881 |
| micro_dmem [default] stream_ld | sky130 | soc | 4096 | 29,107 | 4,829 | 0.166 | 6.028 | 7.11 | 7.08 | - | 29,023 |
| micro_dmem [default] stream_st | sky130 | axi | 4096 | 68,758 | 4,826 | 0.070 | 14.247 | 16.79 | 16.75 | - | 68,499 |
| micro_dmem [default] stream_st | sky130 | soc | 4096 | 38,863 | 4,826 | 0.124 | 8.053 | 9.49 | 9.46 | - | 38,745 |
| micro_imem [default] empty | sky130 | axi | 49152 | 216 | 20 | 0.093 | 10.800 | 0.00 | (window) | - | 135 |
| micro_imem [default] empty | sky130 | soc | 49152 | 133 | 20 | 0.150 | 6.650 | 0.00 | (window) | - | 77 |
| micro_imem [default] ifoot_1k | sky130 | axi | 49152 | 165,891 | 49,943 | 0.301 | 3.322 | 3.38 | 3.37 | - | 165,853 |
| micro_imem [default] ifoot_1k | sky130 | soc | 49152 | 156,216 | 49,943 | 0.320 | 3.128 | 3.18 | 3.18 | - | 156,178 |
| micro_imem [default] ifoot_2k | sky130 | axi | 49152 | 156,771 | 49,559 | 0.316 | 3.163 | 3.19 | 3.19 | - | 156,733 |
| micro_imem [default] ifoot_2k | sky130 | soc | 49152 | 151,896 | 49,559 | 0.326 | 3.065 | 3.09 | 3.09 | - | 151,858 |
| micro_imem [default] ifoot_3k | sky130 | axi | 49152 | 153,731 | 49,431 | 0.322 | 3.110 | 3.13 | 3.12 | - | 153,693 |
| micro_imem [default] ifoot_3k | sky130 | soc | 49152 | 150,456 | 49,431 | 0.329 | 3.044 | 3.06 | 3.06 | - | 150,418 |
| micro_imem [default] ifoot_4k | sky130 | axi | 49152 | 155,800 | 49,367 | 0.317 | 3.156 | 3.17 | 3.17 | - | 155,725 |
| micro_imem [default] ifoot_4k | sky130 | soc | 49152 | 150,900 | 49,367 | 0.327 | 3.057 | 3.07 | 3.07 | - | 150,850 |
| micro_imem [default] ifoot_6k | sky130 | axi | 49152 | 227,614 | 49,303 | 0.217 | 4.617 | 4.63 | 4.63 | - | 227,539 |
| micro_imem [default] ifoot_6k | sky130 | soc | 49152 | 173,964 | 49,303 | 0.283 | 3.528 | 3.54 | 3.54 | - | 173,914 |
| micro_imem [default] ifoot_8k | sky130 | axi | 49152 | 263,558 | 49,271 | 0.187 | 5.349 | 5.36 | 5.36 | - | 263,483 |
| micro_imem [default] ifoot_8k | sky130 | soc | 49152 | 185,508 | 49,271 | 0.266 | 3.765 | 3.77 | 3.77 | - | 185,458 |
| micro_imem [default] ifoot_12k | sky130 | axi | 49152 | 262,798 | 49,239 | 0.187 | 5.337 | 5.35 | 5.34 | - | 262,723 |
| micro_imem [default] ifoot_12k | sky130 | soc | 49152 | 185,148 | 49,239 | 0.266 | 3.760 | 3.77 | 3.76 | - | 185,098 |
| micro_imem [default] ifoot_16k | sky130 | axi | 49152 | 262,418 | 49,223 | 0.188 | 5.331 | 5.34 | 5.33 | - | 262,343 |
| micro_imem [default] ifoot_16k | sky130 | soc | 49152 | 184,968 | 49,223 | 0.266 | 3.758 | 3.76 | 3.76 | - | 184,918 |
| micro_imem [default] ifoot_24k | sky130 | axi | 49152 | 262,038 | 49,207 | 0.188 | 5.325 | 5.33 | 5.33 | - | 261,963 |
| micro_imem [default] ifoot_24k | sky130 | soc | 49152 | 184,788 | 49,207 | 0.266 | 3.755 | 3.76 | 3.76 | - | 184,738 |
| micro_imem [default] ifoot_32k | sky130 | axi | 49152 | 261,811 | 49,199 | 0.188 | 5.321 | 5.33 | 5.32 | - | 261,773 |
| micro_imem [default] ifoot_32k | sky130 | soc | 49152 | 184,686 | 49,199 | 0.266 | 3.754 | 3.76 | 3.75 | - | 184,648 |
| micro_pipe [default] empty | sky130 | axi | 4096 | 179 | 20 | 0.112 | 8.950 | 0.04 | (window) | - | 46 |
| micro_pipe [default] empty | sky130 | soc | 4096 | 121 | 20 | 0.165 | 6.050 | 0.03 | (window) | - | 46 |
| micro_pipe [default] loop | sky130 | axi | 4096 | 37,081 | 8,211 | 0.221 | 4.516 | 9.05 | 9.01 | - | 36,901 |
| micro_pipe [default] loop | sky130 | soc | 4096 | 36,998 | 8,211 | 0.222 | 4.506 | 9.03 | 9.00 | - | 36,901 |
| micro_pipe [default] alu32_dep | sky130 | axi | 4096 | 12,660 | 4,154 | 0.328 | 3.048 | 3.09 | 3.05 | - | 12,493 |
| micro_pipe [default] alu32_dep | sky130 | soc | 4096 | 12,580 | 4,154 | 0.330 | 3.028 | 3.07 | 3.04 | - | 12,493 |
| micro_pipe [default] alu32_indep | sky130 | axi | 4096 | 12,681 | 4,156 | 0.328 | 3.051 | 3.10 | 3.05 | - | 12,499 |
| micro_pipe [default] alu32_indep | sky130 | soc | 4096 | 12,598 | 4,156 | 0.330 | 3.031 | 3.08 | 3.05 | - | 12,499 |
| micro_pipe [default] alu16_dep | sky130 | axi | 4096 | 12,675 | 4,154 | 0.328 | 3.051 | 3.09 | 3.05 | - | 12,493 |
| micro_pipe [default] alu16_dep | sky130 | soc | 4096 | 12,592 | 4,154 | 0.330 | 3.031 | 3.07 | 3.04 | - | 12,493 |
| micro_pipe [default] alu32_straddle | sky130 | axi | 4096 | 25,179 | 4,155 | 0.165 | 6.060 | 6.15 | 6.10 | - | 25,034 |
| micro_pipe [default] alu32_straddle | sky130 | soc | 4096 | 25,021 | 4,155 | 0.166 | 6.022 | 6.11 | 6.08 | - | 24,934 |
| micro_pipe [default] br_nt | sky130 | axi | 4096 | 12,672 | 4,153 | 0.328 | 3.051 | 3.09 | 3.05 | - | 12,527 |
| micro_pipe [default] br_nt | sky130 | soc | 4096 | 12,589 | 4,153 | 0.330 | 3.031 | 3.07 | 3.04 | - | 12,502 |
| micro_pipe [default] br_taken | sky130 | axi | 4096 | 24,963 | 4,154 | 0.166 | 6.009 | 6.09 | 6.05 | - | 24,818 |
| micro_pipe [default] br_taken | sky130 | soc | 4096 | 24,880 | 4,154 | 0.167 | 5.989 | 6.07 | 6.04 | - | 24,793 |
| micro_pipe [default] jal | sky130 | axi | 4096 | 25,001 | 4,149 | 0.166 | 6.026 | 6.10 | 6.06 | - | 24,871 |
| micro_pipe [default] jal | sky130 | soc | 4096 | 24,868 | 4,149 | 0.167 | 5.994 | 6.07 | 6.04 | - | 24,796 |
| micro_pipe [default] call_ret | sky130 | axi | 4096 | 61,812 | 12,342 | 0.200 | 5.008 | 15.09 | 15.05 | - | 61,630 |
| micro_pipe [default] call_ret | sky130 | soc | 4096 | 61,729 | 12,342 | 0.200 | 5.002 | 15.07 | 15.04 | - | 61,630 |
| micro_pipe [default] jalr_call_ret | sky130 | axi | 4096 | 61,781 | 12,344 | 0.200 | 5.005 | 15.08 | 15.04 | - | 61,636 |
| micro_pipe [default] jalr_call_ret | sky130 | soc | 4096 | 61,723 | 12,344 | 0.200 | 5.000 | 15.07 | 15.04 | - | 61,636 |
| micro_pipe [default] brpat_never | sky130 | axi | 4096 | 54,215 | 17,559 | 0.324 | 3.088 | 13.24 | 13.19 | - | 54,051 |
| micro_pipe [default] brpat_never | sky130 | soc | 4096 | 54,024 | 17,559 | 0.325 | 3.077 | 13.19 | 13.16 | - | 53,935 |
| micro_pipe [default] brpat_always | sky130 | axi | 4096 | 66,503 | 17,559 | 0.264 | 3.787 | 16.24 | 16.19 | - | 66,339 |
| micro_pipe [default] brpat_always | sky130 | soc | 4096 | 66,312 | 17,559 | 0.265 | 3.777 | 16.19 | 16.16 | - | 66,223 |
| micro_pipe [default] brpat_alt | sky130 | axi | 4096 | 60,359 | 17,559 | 0.291 | 3.437 | 14.74 | 14.69 | - | 60,195 |
| micro_pipe [default] brpat_alt | sky130 | soc | 4096 | 60,168 | 17,559 | 0.292 | 3.427 | 14.69 | 14.66 | - | 60,079 |
| micro_pipe [default] brpat_rand | sky130 | axi | 4096 | 60,359 | 17,559 | 0.291 | 3.437 | 14.74 | 14.69 | - | 60,195 |
| micro_pipe [default] brpat_rand | sky130 | soc | 4096 | 60,168 | 17,559 | 0.292 | 3.427 | 14.69 | 14.66 | - | 60,079 |
| micro_pipe [default] ld_dep | sky130 | axi | 4096 | 20,872 | 4,149 | 0.199 | 5.031 | 5.10 | 5.05 | - | 20,736 |
| micro_pipe [default] ld_dep | sky130 | soc | 4096 | 20,764 | 4,149 | 0.200 | 5.005 | 5.07 | 5.04 | - | 20,686 |
| micro_pipe [default] ld_indep | sky130 | axi | 4096 | 20,847 | 4,155 | 0.199 | 5.017 | 5.09 | 5.05 | - | 20,717 |
| micro_pipe [default] ld_indep | sky130 | soc | 4096 | 20,764 | 4,155 | 0.200 | 4.997 | 5.07 | 5.04 | - | 20,692 |
| micro_pipe [default] ld_use1 | sky130 | axi | 4096 | 33,122 | 8,246 | 0.249 | 4.017 | 8.09 | 8.04 | - | 32,955 |
| micro_pipe [default] ld_use1 | sky130 | soc | 4096 | 33,039 | 8,246 | 0.250 | 4.007 | 8.07 | 8.04 | - | 32,955 |
| micro_pipe [default] ld_use2 | sky130 | axi | 4096 | 33,199 | 8,247 | 0.248 | 4.026 | 8.11 | 8.06 | - | 33,034 |
| micro_pipe [default] ld_use2 | sky130 | soc | 4096 | 33,066 | 8,247 | 0.249 | 4.009 | 8.07 | 8.04 | - | 32,984 |
| micro_pipe [default] st | sky130 | axi | 4096 | 20,849 | 4,153 | 0.199 | 5.020 | 5.09 | 5.05 | - | 20,716 |
| micro_pipe [default] st | sky130 | soc | 4096 | 20,766 | 4,153 | 0.200 | 5.000 | 5.07 | 5.04 | - | 20,691 |
| micro_pipe [default] rdcycle | sky130 | axi | 4096 | 12,639 | 4,149 | 0.328 | 3.046 | 3.09 | 3.04 | - | 12,472 |
| micro_pipe [default] rdcycle | sky130 | soc | 4096 | 12,556 | 4,149 | 0.330 | 3.026 | 3.07 | 3.04 | - | 12,472 |
| micro_pipe [default] rdtime | sky130 | axi | 4096 | 12,568 | 4,149 | 0.330 | 3.029 | 3.07 | 3.02 | - | 12,475 |
| micro_pipe [default] rdtime | sky130 | soc | 4096 | 12,543 | 4,149 | 0.331 | 3.023 | 3.06 | 3.03 | - | 12,475 |
| micro_pipe [default] csrr | sky130 | axi | 4096 | 12,624 | 4,149 | 0.329 | 3.043 | 3.08 | 3.04 | - | 12,583 |
| micro_pipe [default] csrr | sky130 | soc | 4096 | 12,549 | 4,149 | 0.331 | 3.025 | 3.06 | 3.03 | - | 12,508 |
| micro_pipe [default] csrw | sky130 | axi | 4096 | 12,584 | 4,153 | 0.330 | 3.030 | 3.07 | 3.03 | - | 12,493 |
| micro_pipe [default] csrw | sky130 | soc | 4096 | 12,559 | 4,153 | 0.331 | 3.024 | 3.07 | 3.04 | - | 12,493 |
| micro_pipe [default] csrrw | sky130 | axi | 4096 | 12,562 | 4,149 | 0.330 | 3.028 | 3.07 | 3.02 | - | 12,472 |
| micro_pipe [default] csrrw | sky130 | soc | 4096 | 12,537 | 4,149 | 0.331 | 3.022 | 3.06 | 3.03 | - | 12,472 |
| micro_pipe [default] fence | sky130 | axi | 4096 | 12,528 | 4,148 | 0.331 | 3.020 | 3.06 | 3.01 | - | 12,472 |
| micro_pipe [default] fence | sky130 | soc | 4096 | 12,528 | 4,148 | 0.331 | 3.020 | 3.06 | 3.03 | - | 12,472 |
| micro_units [default] empty | sky130 | axi | 1024 | 219 | 20 | 0.091 | 10.950 | 0.21 | (window) | - | 129 |
| micro_units [default] empty | sky130 | soc | 1024 | 136 | 20 | 0.147 | 6.800 | 0.13 | (window) | - | 71 |
| micro_units [default] mul_dep | sky130 | axi | 1024 | 4,433 | 1,086 | 0.245 | 4.082 | 4.33 | 4.12 | - | 4,377 |
| micro_units [default] mul_dep | sky130 | soc | 1024 | 4,408 | 1,086 | 0.246 | 4.059 | 4.30 | 4.17 | - | 4,352 |
| micro_units [default] mul_indep | sky130 | axi | 1024 | 4,459 | 1,086 | 0.244 | 4.106 | 4.35 | 4.14 | - | 4,307 |
| micro_units [default] mul_indep | sky130 | soc | 1024 | 4,384 | 1,086 | 0.248 | 4.037 | 4.28 | 4.15 | - | 4,307 |
| micro_units [default] div_dep | sky130 | axi | 1024 | 37,193 | 1,083 | 0.029 | 34.343 | 36.32 | 36.11 | - | 37,078 |
| micro_units [default] div_dep | sky130 | soc | 1024 | 37,143 | 1,083 | 0.029 | 34.296 | 36.27 | 36.14 | - | 37,078 |
| micro_units [default] div_indep | sky130 | axi | 1024 | 37,165 | 1,083 | 0.029 | 34.317 | 36.29 | 36.08 | - | 37,109 |
| micro_units [default] div_indep | sky130 | soc | 1024 | 37,140 | 1,083 | 0.029 | 34.294 | 36.27 | 36.14 | - | 37,084 |
| micro_units [default] div_short | sky130 | axi | 1024 | 4,361 | 1,078 | 0.247 | 4.045 | 4.26 | 4.04 | - | 4,320 |
| micro_units [default] div_short | sky130 | soc | 1024 | 4,336 | 1,078 | 0.249 | 4.022 | 4.23 | 4.10 | - | 4,295 |
| micro_units [default] divw_dep | sky130 | axi | 1024 | 20,797 | 1,079 | 0.052 | 19.274 | 20.31 | 20.10 | - | 20,670 |
| micro_units [default] divw_dep | sky130 | soc | 1024 | 20,747 | 1,079 | 0.052 | 19.228 | 20.26 | 20.13 | - | 20,670 |
| micro_units [default] rem_indep | sky130 | axi | 1024 | 36,126 | 1,082 | 0.030 | 33.388 | 35.28 | 35.07 | - | 36,082 |
| micro_units [default] rem_indep | sky130 | soc | 1024 | 36,101 | 1,082 | 0.030 | 33.365 | 35.25 | 35.12 | - | 36,057 |
| micro_units [default] fadd_d_dep | sky130 | axi | 1024 | 6,749 | 1,081 | 0.160 | 6.243 | 6.59 | 6.38 | - | 6,670 |
| micro_units [default] fadd_d_dep | sky130 | soc | 1024 | 6,508 | 1,081 | 0.166 | 6.020 | 6.36 | 6.22 | - | 6,454 |
| micro_units [default] fadd_d_indep | sky130 | axi | 1024 | 6,523 | 1,078 | 0.165 | 6.051 | 6.37 | 6.16 | - | 6,479 |
| micro_units [default] fadd_d_indep | sky130 | soc | 1024 | 6,423 | 1,078 | 0.168 | 5.958 | 6.27 | 6.14 | - | 6,379 |
| micro_units [default] fmul_d_dep | sky130 | axi | 1024 | 6,476 | 1,079 | 0.167 | 6.002 | 6.32 | 6.11 | - | 6,351 |
| micro_units [default] fmul_d_dep | sky130 | soc | 1024 | 6,426 | 1,079 | 0.168 | 5.956 | 6.28 | 6.14 | - | 6,351 |
| micro_units [default] fmadd_d_dep | sky130 | axi | 1024 | 8,563 | 1,084 | 0.127 | 7.899 | 8.36 | 8.15 | - | 8,473 |
| micro_units [default] fmadd_d_dep | sky130 | soc | 1024 | 8,513 | 1,084 | 0.127 | 7.853 | 8.31 | 8.18 | - | 8,448 |
| micro_units [default] fdiv_d_dep | sky130 | axi | 1024 | 34,200 | 1,079 | 0.032 | 31.696 | 33.40 | 33.18 | - | 34,073 |
| micro_units [default] fdiv_d_dep | sky130 | soc | 1024 | 34,100 | 1,079 | 0.032 | 31.603 | 33.30 | 33.17 | - | 34,023 |
| micro_units [default] fdiv_d_indep | sky130 | axi | 1024 | 34,112 | 1,078 | 0.032 | 31.644 | 33.31 | 33.10 | - | 34,022 |
| micro_units [default] fdiv_d_indep | sky130 | soc | 1024 | 34,062 | 1,078 | 0.032 | 31.597 | 33.26 | 33.13 | - | 33,997 |
| micro_units [default] fsqrt_d_dep | sky130 | axi | 1024 | 34,096 | 1,077 | 0.032 | 31.658 | 33.30 | 33.08 | - | 33,978 |
| micro_units [default] fsqrt_d_dep | sky130 | soc | 1024 | 34,046 | 1,077 | 0.032 | 31.612 | 33.25 | 33.12 | - | 33,978 |
| micro_units [default] fsqrt_d_indep | sky130 | axi | 1024 | 34,040 | 1,078 | 0.032 | 31.577 | 33.24 | 33.03 | - | 33,993 |
| micro_units [default] fsqrt_d_indep | sky130 | soc | 1024 | 34,040 | 1,078 | 0.032 | 31.577 | 33.24 | 33.11 | - | 33,993 |
| micro_units [default] fdiv_s_dep | sky130 | axi | 1024 | 18,742 | 1,081 | 0.058 | 17.338 | 18.30 | 18.09 | - | 18,689 |
| micro_units [default] fdiv_s_dep | sky130 | soc | 1024 | 18,717 | 1,081 | 0.058 | 17.315 | 18.28 | 18.15 | - | 18,664 |
| micro_units [default] fsqrt_s_dep | sky130 | axi | 1024 | 18,722 | 1,077 | 0.058 | 17.383 | 18.28 | 18.07 | - | 18,669 |
| micro_units [default] fsqrt_s_dep | sky130 | soc | 1024 | 18,697 | 1,077 | 0.058 | 17.360 | 18.26 | 18.13 | - | 18,644 |
| micro_vec [default] empty | sky130 | axi | 256 | 213 | 21 | 0.099 | 10.143 | 0.83 | (window) | - | 43 |
| micro_vec [default] empty | sky130 | soc | 256 | 133 | 21 | 0.158 | 6.333 | 0.52 | (window) | - | 43 |
| micro_vec [default] vsetvli_same | sky130 | axi | 256 | 1,001 | 293 | 0.293 | 3.416 | 3.91 | 3.08 | - | 886 |
| micro_vec [default] vsetvli_same | sky130 | soc | 256 | 951 | 293 | 0.308 | 3.246 | 3.71 | 3.20 | - | 886 |
| micro_vec [default] vsetvli_toggle | sky130 | axi | 256 | 1,022 | 293 | 0.287 | 3.488 | 3.99 | 3.16 | - | 923 |
| micro_vec [default] vsetvli_toggle | sky130 | soc | 256 | 972 | 293 | 0.301 | 3.317 | 3.80 | 3.28 | - | 898 |
| micro_vec [default] vadd_e8_vl1 | sky130 | axi | 256 | 2,281 | 292 | 0.128 | 7.812 | 8.91 | 8.08 | - | 2,154 |
| micro_vec [default] vadd_e8_vl1 | sky130 | soc | 256 | 2,231 | 292 | 0.131 | 7.640 | 8.71 | 8.20 | - | 2,154 |
| micro_vec [default] vadd_e8_vl2 | sky130 | axi | 256 | 2,500 | 292 | 0.117 | 8.562 | 9.77 | 8.93 | - | 2,410 |
| micro_vec [default] vadd_e8_vl2 | sky130 | soc | 256 | 2,475 | 292 | 0.118 | 8.476 | 9.67 | 9.15 | - | 2,410 |
| micro_vec [default] vadd_e8_vl4 | sky130 | axi | 256 | 3,012 | 292 | 0.097 | 10.315 | 11.77 | 10.93 | - | 2,922 |
| micro_vec [default] vadd_e8_vl4 | sky130 | soc | 256 | 2,987 | 292 | 0.098 | 10.229 | 11.67 | 11.15 | - | 2,922 |
| micro_vec [default] vadd_e8_vl8 | sky130 | axi | 256 | 4,036 | 292 | 0.072 | 13.822 | 15.77 | 14.93 | - | 3,946 |
| micro_vec [default] vadd_e8_vl8 | sky130 | soc | 256 | 4,011 | 292 | 0.073 | 13.736 | 15.67 | 15.15 | - | 3,946 |
| micro_vec [default] vadd_e8_vl16 | sky130 | axi | 256 | 6,084 | 292 | 0.048 | 20.836 | 23.77 | 22.93 | - | 5,994 |
| micro_vec [default] vadd_e8_vl16 | sky130 | soc | 256 | 6,059 | 292 | 0.048 | 20.750 | 23.67 | 23.15 | - | 5,994 |
| micro_vec [default] vadd_e8_vl32 | sky130 | axi | 256 | 10,180 | 292 | 0.029 | 34.863 | 39.77 | 38.93 | - | 10,090 |
| micro_vec [default] vadd_e8_vl32 | sky130 | soc | 256 | 10,155 | 292 | 0.029 | 34.777 | 39.67 | 39.15 | - | 10,090 |
| micro_vec [default] vadd_e8_vl64 | sky130 | axi | 256 | 18,372 | 292 | 0.016 | 62.918 | 71.77 | 70.93 | - | 18,282 |
| micro_vec [default] vadd_e8_vl64 | sky130 | soc | 256 | 18,347 | 292 | 0.016 | 62.832 | 71.67 | 71.15 | - | 18,282 |
| micro_vec [default] vadd_e8_vl128 | sky130 | axi | 256 | 34,756 | 292 | 0.008 | 119.027 | 135.77 | 134.93 | - | 34,666 |
| micro_vec [default] vadd_e8_vl128 | sky130 | soc | 256 | 34,731 | 292 | 0.008 | 118.942 | 135.67 | 135.15 | - | 34,666 |
| micro_vec [default] vadd_e8_vl256 | sky130 | axi | 256 | 67,524 | 292 | 0.004 | 231.247 | 263.77 | 262.93 | - | 67,434 |
| micro_vec [default] vadd_e8_vl256 | sky130 | soc | 256 | 67,499 | 292 | 0.004 | 231.161 | 263.67 | 263.15 | - | 67,434 |
| micro_vec [default] vadd_e8_vl512 | sky130 | axi | 256 | 133,060 | 292 | 0.002 | 455.685 | 519.77 | 518.93 | - | 132,970 |
| micro_vec [default] vadd_e8_vl512 | sky130 | soc | 256 | 133,035 | 292 | 0.002 | 455.599 | 519.67 | 519.15 | - | 132,970 |
| micro_vec [default] vle8_vl1 | sky130 | axi | 256 | 2,070 | 291 | 0.141 | 7.113 | 8.09 | 7.25 | - | 1,980 |
| micro_vec [default] vle8_vl1 | sky130 | soc | 256 | 1,995 | 291 | 0.146 | 6.856 | 7.79 | 7.27 | - | 1,930 |
| micro_vec [default] vle8_vl2 | sky130 | axi | 256 | 3,053 | 291 | 0.095 | 10.491 | 11.93 | 11.09 | - | 2,963 |
| micro_vec [default] vle8_vl2 | sky130 | soc | 256 | 3,003 | 291 | 0.097 | 10.320 | 11.73 | 11.21 | - | 2,938 |
| micro_vec [default] vle8_vl4 | sky130 | axi | 256 | 5,093 | 291 | 0.057 | 17.502 | 19.89 | 19.06 | - | 5,003 |
| micro_vec [default] vle8_vl4 | sky130 | soc | 256 | 5,047 | 291 | 0.058 | 17.344 | 19.71 | 19.20 | - | 4,982 |
| micro_vec [default] vle8_vl8 | sky130 | axi | 256 | 9,173 | 291 | 0.032 | 31.522 | 35.83 | 35.00 | - | 9,083 |
| micro_vec [default] vle8_vl8 | sky130 | soc | 256 | 9,143 | 291 | 0.032 | 31.419 | 35.71 | 35.20 | - | 9,078 |
| micro_vec [default] vle8_vl16 | sky130 | axi | 256 | 17,360 | 291 | 0.017 | 59.656 | 67.81 | 66.98 | - | 17,270 |
| micro_vec [default] vle8_vl16 | sky130 | soc | 256 | 17,335 | 291 | 0.017 | 59.570 | 67.71 | 67.20 | - | 17,270 |
| micro_vec [default] vle8_vl32 | sky130 | axi | 256 | 33,744 | 291 | 0.009 | 115.959 | 131.81 | 130.98 | - | 33,654 |
| micro_vec [default] vle8_vl32 | sky130 | soc | 256 | 33,719 | 291 | 0.009 | 115.873 | 131.71 | 131.20 | - | 33,654 |
| micro_vec [default] vle8_vl64 | sky130 | axi | 256 | 66,512 | 291 | 0.004 | 228.564 | 259.81 | 258.98 | - | 66,422 |
| micro_vec [default] vle8_vl64 | sky130 | soc | 256 | 66,487 | 291 | 0.004 | 228.478 | 259.71 | 259.20 | - | 66,422 |
| micro_vec [default] vle8_vl128 | sky130 | axi | 256 | 132,137 | 291 | 0.002 | 454.079 | 516.16 | 515.33 | - | 132,047 |
| micro_vec [default] vle8_vl128 | sky130 | soc | 256 | 132,054 | 291 | 0.002 | 453.794 | 515.84 | 515.32 | - | 131,989 |
| micro_vec [default] vle8_vl256 | sky130 | axi | 256 | 263,120 | 291 | 0.001 | 904.192 | 1,027.81 | 1,026.98 | - | 263,030 |
| micro_vec [default] vle8_vl256 | sky130 | soc | 256 | 263,095 | 291 | 0.001 | 904.107 | 1,027.71 | 1,027.20 | - | 263,030 |
| micro_vec [default] vle8_vl512 | sky130 | axi | 256 | 525,338 | 291 | 0.001 | 1805.285 | 2,052.10 | 2,051.27 | - | 525,248 |
| micro_vec [default] vle8_vl512 | sky130 | soc | 256 | 525,263 | 291 | 0.001 | 1805.027 | 2,051.81 | 2,051.29 | - | 525,198 |
| micro_vec [default] vse8_vl1 | sky130 | axi | 256 | 2,299 | 293 | 0.127 | 7.846 | 8.98 | 8.15 | - | 2,166 |
| micro_vec [default] vse8_vl1 | sky130 | soc | 256 | 2,249 | 293 | 0.130 | 7.676 | 8.79 | 8.27 | - | 2,166 |
| micro_vec [default] vse8_vl8 | sky130 | axi | 256 | 11,222 | 293 | 0.026 | 38.300 | 43.84 | 43.00 | - | 11,126 |
| micro_vec [default] vse8_vl8 | sky130 | soc | 256 | 11,197 | 293 | 0.026 | 38.215 | 43.74 | 43.22 | - | 11,126 |
| micro_vec [default] vse8_vl64 | sky130 | axi | 256 | 82,902 | 293 | 0.004 | 282.942 | 323.84 | 323.00 | - | 82,806 |
| micro_vec [default] vse8_vl64 | sky130 | soc | 256 | 82,877 | 293 | 0.004 | 282.857 | 323.74 | 323.22 | - | 82,806 |
| micro_vec [default] vse8_vl512 | sky130 | axi | 256 | 656,342 | 293 | 0.000 | 2240.075 | 2,563.84 | 2,563.00 | - | 656,246 |
| micro_vec [default] vse8_vl512 | sky130 | soc | 256 | 656,317 | 293 | 0.000 | 2239.990 | 2,563.74 | 2,563.22 | - | 656,246 |
| micro_vec [default] vadd_e64_vl8 | sky130 | axi | 256 | 4,064 | 291 | 0.072 | 13.966 | 15.88 | 15.04 | - | 3,946 |
| micro_vec [default] vadd_e64_vl8 | sky130 | soc | 256 | 4,014 | 291 | 0.072 | 13.794 | 15.68 | 15.16 | - | 3,946 |
| micro_vec [default] vmul_e64_vl8 | sky130 | axi | 256 | 18,398 | 291 | 0.016 | 63.223 | 71.87 | 71.04 | - | 18,317 |
| micro_vec [default] vmul_e64_vl8 | sky130 | soc | 256 | 18,348 | 291 | 0.016 | 63.052 | 71.67 | 71.15 | - | 18,292 |
| micro_vec [default] vfadd_e64_vl8 | sky130 | axi | 256 | 14,291 | 291 | 0.020 | 49.110 | 55.82 | 54.99 | - | 14,232 |
| micro_vec [default] vfadd_e64_vl8 | sky130 | soc | 256 | 14,266 | 291 | 0.020 | 49.024 | 55.73 | 55.21 | - | 14,207 |
| micro_vec [default] vredsum_e64_vl8 | sky130 | axi | 256 | 4,563 | 291 | 0.064 | 15.680 | 17.82 | 16.99 | - | 4,467 |
| micro_vec [default] vredsum_e64_vl8 | sky130 | soc | 256 | 4,538 | 291 | 0.064 | 15.595 | 17.73 | 17.21 | - | 4,467 |
| sha256chain [sdk] sha256 plain C | sky130 | axi | 1024 | 16,009,889 | 3,714,106 | 0.232 | 4.311 | 15,634.66 | - | 0.0020 B/cycle | 16,009,842 |
| sha256chain [sdk] sha256 plain C | sky130 | soc | 1024 | 16,009,614 | 3,714,106 | 0.232 | 4.310 | 15,634.39 | - | 0.0020 B/cycle | 16,009,567 |
| sha256chain [sdk] sha256 Zknh | sky130 | axi | 1024 | 11,005,592 | 2,731,067 | 0.248 | 4.030 | 10,747.65 | - | 0.0030 B/cycle | 11,005,533 |
| sha256chain [sdk] sha256 Zknh | sky130 | soc | 1024 | 11,005,342 | 2,731,067 | 0.248 | 4.030 | 10,747.40 | - | 0.0030 B/cycle | 11,005,283 |
| sha256chain [sdk] sha256 RVV x16 (multi-buffer) | sky130 | axi | 1024 | 5,069,073 | 219,780 | 0.043 | 23.064 | 4,950.27 | - | 0.0065 B/cycle | 5,068,955 |
| sha256chain [sdk] sha256 RVV x16 (multi-buffer) | sky130 | soc | 1024 | 5,067,923 | 219,780 | 0.043 | 23.059 | 4,949.14 | - | 0.0065 B/cycle | 5,067,855 |
| sha256chain [sdk] sha256 accel sigil_sha256_block | sky130 | axi | 1024 | 811,263 | 159,772 | 0.197 | 5.078 | 792.25 | - | 0.0404 B/cycle | 811,204 |
| sha256chain [sdk] sha256 accel sigil_sha256_block | sky130 | soc | 1024 | 811,188 | 159,772 | 0.197 | 5.077 | 792.18 | - | 0.0404 B/cycle | 811,129 |
| sha256chain [sdk] sha256 accel sigil_sha256 | sky130 | axi | 1024 | 4,528,598 | 1,026,081 | 0.227 | 4.413 | 4,422.46 | - | 0.0072 B/cycle | 4,528,557 |
| sha256chain [sdk] sha256 accel sigil_sha256 | sky130 | soc | 1024 | 4,528,373 | 1,026,081 | 0.227 | 4.413 | 4,422.24 | - | 0.0072 B/cycle | 4,528,332 |
| sha256chain [sdk] sha512 accel sigil_hash | sky130 | axi | 1024 | 3,866,185 | 1,005,603 | 0.260 | 3.845 | 3,775.57 | - | 0.0170 B/cycle | 3,866,106 |
| sha256chain [sdk] sha512 accel sigil_hash | sky130 | soc | 1024 | 3,865,902 | 1,005,606 | 0.260 | 3.844 | 3,775.29 | - | 0.0170 B/cycle | 3,865,848 |
| sha256chain [sdk] sha3-256 accel sigil_hash | sky130 | axi | 1024 | 2,171,208 | 555,049 | 0.256 | 3.912 | 2,120.32 | - | 0.0151 B/cycle | 2,171,164 |
| sha256chain [sdk] sha3-256 accel sigil_hash | sky130 | soc | 1024 | 2,171,108 | 555,049 | 0.256 | 3.912 | 2,120.22 | - | 0.0151 B/cycle | 2,171,064 |
| sha256chain_bulk [sdk] sha256 plain C | sky130 | axi | 64 | 15,982,379 | 3,701,940 | 0.232 | 4.317 | 249,724.67 | - | 0.0041 B/cycle | 15,982,261 |
| sha256chain_bulk [sdk] sha256 plain C | sky130 | soc | 64 | 15,924,174 | 3,701,940 | 0.232 | 4.302 | 248,815.22 | - | 0.0041 B/cycle | 15,924,106 |
| sha256chain_bulk [sdk] sha256 Zknh | sky130 | axi | 64 | 10,991,147 | 2,735,418 | 0.249 | 4.018 | 171,736.67 | - | 0.0060 B/cycle | 10,990,997 |
| sha256chain_bulk [sdk] sha256 Zknh | sky130 | soc | 64 | 10,935,355 | 2,735,418 | 0.250 | 3.998 | 170,864.92 | - | 0.0060 B/cycle | 10,935,280 |
| sha256chain_bulk [sdk] sha256 RVV x16 (16 segments) | sky130 | axi | 64 | 5,474,071 | 224,332 | 0.041 | 24.402 | 85,532.36 | - | 0.0120 B/cycle | 5,473,918 |
| sha256chain_bulk [sdk] sha256 RVV x16 (16 segments) | sky130 | soc | 64 | 5,420,459 | 224,332 | 0.041 | 24.163 | 84,694.67 | - | 0.0121 B/cycle | 5,420,381 |
| sha256chain_bulk [sdk] sha512 accel sigil_hash | sky130 | axi | 64 | 402,982 | 66,457 | 0.165 | 6.064 | 6,296.59 | - | 0.1626 B/cycle | 402,883 |
| sha256chain_bulk [sdk] sha512 accel sigil_hash | sky130 | soc | 64 | 376,620 | 66,460 | 0.176 | 5.667 | 5,884.69 | - | 0.1740 B/cycle | 376,546 |
| sha256chain_bulk [sdk] sha3-256 accel sigil_hash | sky130 | axi | 64 | 400,954 | 66,055 | 0.165 | 6.070 | 6,264.91 | - | 0.1635 B/cycle | 400,876 |
| sha256chain_bulk [sdk] sha3-256 accel sigil_hash | sky130 | soc | 64 | 374,940 | 66,055 | 0.176 | 5.676 | 5,858.44 | - | 0.1748 B/cycle | 374,887 |

Net cycles/iter: the region's cycles minus those of the bench's window region (an empty measurement window, `(window)`) in the same simulation, divided by the iterations.

## Speedups over the baseline region (same image, configuration and memory)

| Run | Baseline region | Baseline cycles | Cycles | Speedup |
|---|---|---:|---:|---:|
| kernels[autovec] vadd_i32 RVV sky130/axi | 10 vadd_i32 C | 110,966 | 100,701 | 1.10x |
| kernels[autovec] vadd_i32 RVV sky130/soc | 10 vadd_i32 C | 84,561 | 73,125 | 1.16x |
| kernels[autovec] vadd_i64 RVV sky130/axi | 20 vadd_i64 C | 80,767 | 72,029 | 1.12x |
| kernels[autovec] vadd_i64 RVV sky130/soc | 20 vadd_i64 C | 54,337 | 44,453 | 1.22x |
| kernels[autovec] daxpy RVV sky130/axi | 30 daxpy C | 87,562 | 76,185 | 1.15x |
| kernels[autovec] daxpy RVV sky130/soc | 30 daxpy C | 66,247 | 55,365 | 1.20x |
| kernels[autovec] saxpy RVV sky130/axi | 40 saxpy C | 132,190 | 119,198 | 1.11x |
| kernels[autovec] saxpy RVV sky130/soc | 40 saxpy C | 110,850 | 98,378 | 1.13x |
| kernels[autovec] ddot RVV sky130/axi | 50 ddot C | 80,914 | 55,757 | 1.45x |
| kernels[autovec] ddot RVV sky130/soc | 50 ddot C | 67,749 | 42,592 | 1.59x |
| kernels[autovec] idot_i32 RVV sky130/axi | 60 idot_i32 C | 97,792 | 80,293 | 1.22x |
| kernels[autovec] idot_i32 RVV sky130/soc | 60 idot_i32 C | 84,652 | 67,153 | 1.26x |
| kernels[autovec] memcpy RVV sky130/axi | 70 memcpy C | 88,030 | 51,155 | 1.72x |
| kernels[autovec] memcpy RVV sky130/soc | 70 memcpy C | 68,141 | 30,441 | 2.24x |
| kernels[autovec] memcpy RVV-e8 sky130/axi | 70 memcpy C | 88,030 | 179,647 | 0.49x |
| kernels[autovec] memcpy RVV-e8 sky130/soc | 70 memcpy C | 68,141 | 159,283 | 0.43x |
| kernels[autovec] memset RVV sky130/axi | 80 memset C | 35,675 | 11,869 | 3.01x |
| kernels[autovec] memset RVV sky130/soc | 80 memset C | 35,418 | 11,612 | 3.05x |
| kernels[autovec] memset RVV-e8 sky130/axi | 80 memset C | 35,675 | 85,400 | 0.42x |
| kernels[autovec] memset RVV-e8 sky130/soc | 80 memset C | 35,418 | 85,143 | 0.42x |
| kernels[autovec] dgemm RVV sky130/axi | 90 dgemm C | 9,236,265 | 2,400,358 | 3.85x |
| kernels[autovec] dgemm RVV sky130/soc | 90 dgemm C | 5,770,390 | 1,940,549 | 2.97x |
| kernels[autovec] sgemm RVV sky130/axi | 100 sgemm C | 5,708,712 | 1,820,161 | 3.14x |
| kernels[autovec] sgemm RVV sky130/soc | 100 sgemm C | 5,147,715 | 1,776,462 | 2.90x |
| kernels[autovec] fir_f32 RVV sky130/axi | 110 fir_f32 C | 1,812,975 | 863,381 | 2.10x |
| kernels[autovec] fir_f32 RVV sky130/soc | 110 fir_f32 C | 1,781,668 | 838,936 | 2.12x |
| kernels[autovec] mac_i8 RVV sky130/axi | 120 mac_i8 C | 315,999 | 252,524 | 1.25x |
| kernels[autovec] mac_i8 RVV sky130/soc | 120 mac_i8 C | 302,834 | 239,359 | 1.27x |
| kernels[autovec] mac_i16 RVV sky130/axi | 130 mac_i16 C | 147,008 | 129,955 | 1.13x |
| kernels[autovec] mac_i16 RVV sky130/soc | 130 mac_i16 C | 133,868 | 116,815 | 1.15x |
| kernels[scalar] vadd_i32 RVV sky130/axi | 10 vadd_i32 C | 175,310 | 100,701 | 1.74x |
| kernels[scalar] vadd_i32 RVV sky130/soc | 10 vadd_i32 C | 148,905 | 73,125 | 2.04x |
| kernels[scalar] vadd_i64 RVV sky130/axi | 20 vadd_i64 C | 107,759 | 72,029 | 1.50x |
| kernels[scalar] vadd_i64 RVV sky130/soc | 20 vadd_i64 C | 81,329 | 44,453 | 1.83x |
| kernels[scalar] daxpy RVV sky130/axi | 30 daxpy C | 122,759 | 76,185 | 1.61x |
| kernels[scalar] daxpy RVV sky130/soc | 30 daxpy C | 101,419 | 55,365 | 1.83x |
| kernels[scalar] saxpy RVV sky130/axi | 40 saxpy C | 237,389 | 119,198 | 1.99x |
| kernels[scalar] saxpy RVV sky130/soc | 40 saxpy C | 216,074 | 98,378 | 2.20x |
| kernels[scalar] ddot RVV sky130/axi | 50 ddot C | 93,482 | 55,757 | 1.68x |
| kernels[scalar] ddot RVV sky130/soc | 50 ddot C | 80,317 | 42,592 | 1.89x |
| kernels[scalar] idot_i32 RVV sky130/axi | 60 idot_i32 C | 138,504 | 80,293 | 1.72x |
| kernels[scalar] idot_i32 RVV sky130/soc | 60 idot_i32 C | 125,364 | 67,153 | 1.87x |
| kernels[scalar] memcpy RVV sky130/axi | 70 memcpy C | 88,030 | 51,155 | 1.72x |
| kernels[scalar] memcpy RVV sky130/soc | 70 memcpy C | 68,141 | 30,441 | 2.24x |
| kernels[scalar] memcpy RVV-e8 sky130/axi | 70 memcpy C | 88,030 | 179,647 | 0.49x |
| kernels[scalar] memcpy RVV-e8 sky130/soc | 70 memcpy C | 68,141 | 159,283 | 0.43x |
| kernels[scalar] memset RVV sky130/axi | 80 memset C | 35,675 | 11,869 | 3.01x |
| kernels[scalar] memset RVV sky130/soc | 80 memset C | 35,418 | 11,612 | 3.05x |
| kernels[scalar] memset RVV-e8 sky130/axi | 80 memset C | 35,675 | 85,400 | 0.42x |
| kernels[scalar] memset RVV-e8 sky130/soc | 80 memset C | 35,418 | 85,143 | 0.42x |
| kernels[scalar] dgemm RVV sky130/axi | 90 dgemm C | 9,236,265 | 2,400,358 | 3.85x |
| kernels[scalar] dgemm RVV sky130/soc | 90 dgemm C | 5,770,390 | 1,940,549 | 2.97x |
| kernels[scalar] sgemm RVV sky130/axi | 100 sgemm C | 5,708,712 | 1,820,161 | 3.14x |
| kernels[scalar] sgemm RVV sky130/soc | 100 sgemm C | 5,147,715 | 1,776,462 | 2.90x |
| kernels[scalar] fir_f32 RVV sky130/axi | 110 fir_f32 C | 2,997,783 | 863,381 | 3.47x |
| kernels[scalar] fir_f32 RVV sky130/soc | 110 fir_f32 C | 2,921,476 | 838,936 | 3.48x |
| kernels[scalar] mac_i8 RVV sky130/axi | 120 mac_i8 C | 544,039 | 252,524 | 2.15x |
| kernels[scalar] mac_i8 RVV sky130/soc | 120 mac_i8 C | 530,874 | 239,359 | 2.22x |
| kernels[scalar] mac_i16 RVV sky130/axi | 130 mac_i16 C | 282,160 | 129,955 | 2.17x |
| kernels[scalar] mac_i16 RVV sky130/soc | 130 mac_i16 C | 268,820 | 116,815 | 2.30x |
| sha256chain[sdk] sha256 Zknh sky130/axi | 0 sha256 plain C | 16,009,889 | 11,005,592 | 1.45x |
| sha256chain[sdk] sha256 Zknh sky130/soc | 0 sha256 plain C | 16,009,614 | 11,005,342 | 1.45x |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) sky130/axi | 0 sha256 plain C | 16,009,889 | 5,069,073 | 3.16x |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) sky130/soc | 0 sha256 plain C | 16,009,614 | 5,067,923 | 3.16x |
| sha256chain[sdk] sha256 accel sigil_sha256_block sky130/axi | 0 sha256 plain C | 16,009,889 | 811,263 | 19.73x |
| sha256chain[sdk] sha256 accel sigil_sha256_block sky130/soc | 0 sha256 plain C | 16,009,614 | 811,188 | 19.74x |
| sha256chain[sdk] sha256 accel sigil_sha256 sky130/axi | 0 sha256 plain C | 16,009,889 | 4,528,598 | 3.54x |
| sha256chain[sdk] sha256 accel sigil_sha256 sky130/soc | 0 sha256 plain C | 16,009,614 | 4,528,373 | 3.54x |
| sha256chain_bulk[sdk] sha256 Zknh sky130/axi | 0 sha256 plain C | 15,982,379 | 10,991,147 | 1.45x |
| sha256chain_bulk[sdk] sha256 Zknh sky130/soc | 0 sha256 plain C | 15,924,174 | 10,935,355 | 1.46x |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) sky130/axi | 0 sha256 plain C | 15,982,379 | 5,474,071 | 2.92x |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) sky130/soc | 0 sha256 plain C | 15,924,174 | 5,420,459 | 2.94x |

## Projected throughput at a given clock (simulation cycles; not a hardware measurement)

| Run | Iter/s @ 62.5 MHz | Iter/s @ 100 MHz | Work/s @ 62.5 MHz | Work/s @ 100 MHz |
|---|---:|---:|---:|---:|
| coremark[scalar] sky130/axi | 54.2 | 86.7 | - | - |
| coremark[scalar] sky130/soc | 54.3 | 86.8 | - | - |
| coremark[sdk] sky130/axi | 53.4 | 85.5 | - | - |
| coremark[sdk] sky130/soc | 53.5 | 85.6 | - | - |
| coremark[validation] sky130/axi | 54.1 | 86.5 | - | - |
| coremark[validation] sky130/soc | 54.2 | 86.7 | - | - |
| dhrystone[scalar] sky130/axi | 22,042.2 | 35,267.5 | - | - |
| dhrystone[scalar] sky130/soc | 23,708.4 | 37,933.5 | - | - |
| dhrystone[sdk] sky130/axi | 18,948.9 | 30,318.2 | - | - |
| dhrystone[sdk] sky130/soc | 20,951.0 | 33,521.7 | - | - |
| kernels[autovec] vadd_i32 C sky130/axi | 2,252.9 | 3,604.7 | 2,307,013 elem/s | 3,691,221 elem/s |
| kernels[autovec] vadd_i32 C sky130/soc | 2,956.4 | 4,730.3 | 3,027,400 elem/s | 4,843,841 elem/s |
| kernels[autovec] vadd_i32 RVV sky130/axi | 2,482.6 | 3,972.2 | 2,542,179 elem/s | 4,067,487 elem/s |
| kernels[autovec] vadd_i32 RVV sky130/soc | 3,418.8 | 5,470.1 | 3,500,855 elem/s | 5,601,368 elem/s |
| kernels[autovec] vadd_i64 C sky130/axi | 3,095.3 | 4,952.5 | 1,584,806 elem/s | 2,535,689 elem/s |
| kernels[autovec] vadd_i64 C sky130/soc | 4,600.9 | 7,361.5 | 2,355,669 elem/s | 3,769,071 elem/s |
| kernels[autovec] vadd_i64 RVV sky130/axi | 3,470.8 | 5,553.3 | 1,777,062 elem/s | 2,843,299 elem/s |
| kernels[autovec] vadd_i64 RVV sky130/soc | 5,623.9 | 8,998.3 | 2,879,446 elem/s | 4,607,113 elem/s |
| kernels[autovec] daxpy C sky130/axi | 2,855.1 | 4,568.2 | 1,461,821 elem/s | 2,338,914 elem/s |
| kernels[autovec] daxpy C sky130/soc | 3,773.8 | 6,038.0 | 1,932,163 elem/s | 3,091,461 elem/s |
| kernels[autovec] daxpy RVV sky130/axi | 3,281.5 | 5,250.4 | 1,680,121 elem/s | 2,688,193 elem/s |
| kernels[autovec] daxpy RVV sky130/soc | 4,515.5 | 7,224.8 | 2,311,930 elem/s | 3,699,088 elem/s |
| kernels[autovec] saxpy C sky130/axi | 1,891.2 | 3,025.9 | 1,936,606 elem/s | 3,098,570 elem/s |
| kernels[autovec] saxpy C sky130/soc | 2,255.3 | 3,608.5 | 2,309,427 elem/s | 3,695,083 elem/s |
| kernels[autovec] saxpy RVV sky130/axi | 2,097.4 | 3,355.8 | 2,147,687 elem/s | 3,436,299 elem/s |
| kernels[autovec] saxpy RVV sky130/soc | 2,541.2 | 4,065.9 | 2,602,208 elem/s | 4,163,532 elem/s |
| kernels[autovec] ddot C sky130/axi | 3,089.7 | 4,943.5 | 1,581,926 elem/s | 2,531,082 elem/s |
| kernels[autovec] ddot C sky130/soc | 3,690.1 | 5,904.1 | 1,889,327 elem/s | 3,022,923 elem/s |
| kernels[autovec] ddot RVV sky130/axi | 4,483.7 | 7,174.0 | 2,295,676 elem/s | 3,673,081 elem/s |
| kernels[autovec] ddot RVV sky130/soc | 5,869.6 | 9,391.4 | 3,005,259 elem/s | 4,808,415 elem/s |
| kernels[autovec] idot_i32 C sky130/axi | 2,556.4 | 4,090.3 | 2,617,801 elem/s | 4,188,482 elem/s |
| kernels[autovec] idot_i32 C sky130/soc | 2,953.3 | 4,725.2 | 3,024,146 elem/s | 4,838,633 elem/s |
| kernels[autovec] idot_i32 RVV sky130/axi | 3,113.6 | 4,981.8 | 3,188,323 elem/s | 5,101,316 elem/s |
| kernels[autovec] idot_i32 RVV sky130/soc | 3,722.8 | 5,956.5 | 3,812,190 elem/s | 6,099,504 elem/s |
| kernels[autovec] memcpy C sky130/axi | 2,839.9 | 4,543.9 | 11,632,398 byte/s | 18,611,837 byte/s |
| kernels[autovec] memcpy C sky130/soc | 3,668.9 | 5,870.2 | 15,027,663 byte/s | 24,044,261 byte/s |
| kernels[autovec] memcpy RVV sky130/axi | 4,887.1 | 7,819.4 | 20,017,594 byte/s | 32,028,150 byte/s |
| kernels[autovec] memcpy RVV sky130/soc | 8,212.6 | 13,140.2 | 33,638,842 byte/s | 53,822,148 byte/s |
| kernels[autovec] memcpy RVV-e8 sky130/axi | 1,391.6 | 2,226.6 | 5,700,067 byte/s | 9,120,108 byte/s |
| kernels[autovec] memcpy RVV-e8 sky130/soc | 1,569.5 | 2,511.3 | 6,428,809 byte/s | 10,286,095 byte/s |
| kernels[autovec] memset C sky130/axi | 7,007.7 | 11,212.3 | 28,703,574 byte/s | 45,925,718 byte/s |
| kernels[autovec] memset C sky130/soc | 7,058.6 | 11,293.7 | 28,911,853 byte/s | 46,258,964 byte/s |
| kernels[autovec] memset RVV sky130/axi | 21,063.3 | 33,701.2 | 86,275,171 byte/s | 138,040,273 byte/s |
| kernels[autovec] memset RVV sky130/soc | 21,529.5 | 34,447.1 | 88,184,637 byte/s | 141,095,419 byte/s |
| kernels[autovec] memset RVV-e8 sky130/axi | 2,927.4 | 4,683.8 | 11,990,632 byte/s | 19,185,012 byte/s |
| kernels[autovec] memset RVV-e8 sky130/soc | 2,936.2 | 4,698.0 | 12,026,825 byte/s | 19,242,921 byte/s |
| kernels[autovec] dgemm C sky130/axi | 27.1 | 43.3 | 886,939 mac/s | 1,419,102 mac/s |
| kernels[autovec] dgemm C sky130/soc | 43.3 | 69.3 | 1,419,661 mac/s | 2,271,458 mac/s |
| kernels[autovec] dgemm RVV sky130/axi | 104.2 | 166.6 | 3,412,824 mac/s | 5,460,519 mac/s |
| kernels[autovec] dgemm RVV sky130/soc | 128.8 | 206.1 | 4,221,486 mac/s | 6,754,377 mac/s |
| kernels[autovec] sgemm C sky130/axi | 43.8 | 70.1 | 1,435,000 mac/s | 2,296,000 mac/s |
| kernels[autovec] sgemm C sky130/soc | 48.6 | 77.7 | 1,591,386 mac/s | 2,546,217 mac/s |
| kernels[autovec] sgemm RVV sky130/axi | 137.4 | 219.8 | 4,500,701 mac/s | 7,201,121 mac/s |
| kernels[autovec] sgemm RVV sky130/soc | 140.7 | 225.2 | 4,611,413 mac/s | 7,378,261 mac/s |
| kernels[autovec] fir_f32 C sky130/axi | 137.9 | 220.6 | 2,259,270 mac/s | 3,614,832 mac/s |
| kernels[autovec] fir_f32 C sky130/soc | 140.3 | 224.5 | 2,298,969 mac/s | 3,678,351 mac/s |
| kernels[autovec] fir_f32 RVV sky130/axi | 289.6 | 463.3 | 4,744,140 mac/s | 7,590,623 mac/s |
| kernels[autovec] fir_f32 RVV sky130/soc | 298.0 | 476.8 | 4,882,375 mac/s | 7,811,800 mac/s |
| kernels[autovec] mac_i8 C sky130/axi | 791.1 | 1,265.8 | 3,240,517 mac/s | 5,184,827 mac/s |
| kernels[autovec] mac_i8 C sky130/soc | 825.5 | 1,320.9 | 3,381,390 mac/s | 5,410,225 mac/s |
| kernels[autovec] mac_i8 RVV sky130/axi | 990.0 | 1,584.0 | 4,055,060 mac/s | 6,488,096 mac/s |
| kernels[autovec] mac_i8 RVV sky130/soc | 1,044.5 | 1,671.1 | 4,278,093 mac/s | 6,844,948 mac/s |
| kernels[autovec] mac_i16 C sky130/axi | 1,700.6 | 2,720.9 | 3,482,804 mac/s | 5,572,486 mac/s |
| kernels[autovec] mac_i16 C sky130/soc | 1,867.5 | 2,988.0 | 3,824,663 mac/s | 6,119,461 mac/s |
| kernels[autovec] mac_i16 RVV sky130/axi | 1,923.7 | 3,078.0 | 3,939,825 mac/s | 6,303,721 mac/s |
| kernels[autovec] mac_i16 RVV sky130/soc | 2,140.1 | 3,424.2 | 4,382,999 mac/s | 7,012,798 mac/s |
| kernels[scalar] vadd_i32 C sky130/axi | 1,426.0 | 2,281.7 | 1,460,270 elem/s | 2,336,433 elem/s |
| kernels[scalar] vadd_i32 C sky130/soc | 1,678.9 | 2,686.3 | 1,719,217 elem/s | 2,750,747 elem/s |
| kernels[scalar] vadd_i32 RVV sky130/axi | 2,482.6 | 3,972.2 | 2,542,179 elem/s | 4,067,487 elem/s |
| kernels[scalar] vadd_i32 RVV sky130/soc | 3,418.8 | 5,470.1 | 3,500,855 elem/s | 5,601,368 elem/s |
| kernels[scalar] vadd_i64 C sky130/axi | 2,320.0 | 3,712.0 | 1,187,836 elem/s | 1,900,537 elem/s |
| kernels[scalar] vadd_i64 C sky130/soc | 3,073.9 | 4,918.3 | 1,573,854 elem/s | 2,518,167 elem/s |
| kernels[scalar] vadd_i64 RVV sky130/axi | 3,470.8 | 5,553.3 | 1,777,062 elem/s | 2,843,299 elem/s |
| kernels[scalar] vadd_i64 RVV sky130/soc | 5,623.9 | 8,998.3 | 2,879,446 elem/s | 4,607,113 elem/s |
| kernels[scalar] daxpy C sky130/axi | 2,036.5 | 3,258.4 | 1,042,693 elem/s | 1,668,309 elem/s |
| kernels[scalar] daxpy C sky130/soc | 2,465.0 | 3,944.0 | 1,262,091 elem/s | 2,019,345 elem/s |
| kernels[scalar] daxpy RVV sky130/axi | 3,281.5 | 5,250.4 | 1,680,121 elem/s | 2,688,193 elem/s |
| kernels[scalar] daxpy RVV sky130/soc | 4,515.5 | 7,224.8 | 2,311,930 elem/s | 3,699,088 elem/s |
| kernels[scalar] saxpy C sky130/axi | 1,053.1 | 1,685.0 | 1,078,399 elem/s | 1,725,438 elem/s |
| kernels[scalar] saxpy C sky130/soc | 1,157.0 | 1,851.2 | 1,184,779 elem/s | 1,895,647 elem/s |
| kernels[scalar] saxpy RVV sky130/axi | 2,097.4 | 3,355.8 | 2,147,687 elem/s | 3,436,299 elem/s |
| kernels[scalar] saxpy RVV sky130/soc | 2,541.2 | 4,065.9 | 2,602,208 elem/s | 4,163,532 elem/s |
| kernels[scalar] ddot C sky130/axi | 2,674.3 | 4,278.9 | 1,369,248 elem/s | 2,190,796 elem/s |
| kernels[scalar] ddot C sky130/soc | 3,112.7 | 4,980.3 | 1,593,685 elem/s | 2,549,896 elem/s |
| kernels[scalar] ddot RVV sky130/axi | 4,483.7 | 7,174.0 | 2,295,676 elem/s | 3,673,081 elem/s |
| kernels[scalar] ddot RVV sky130/soc | 5,869.6 | 9,391.4 | 3,005,259 elem/s | 4,808,415 elem/s |
| kernels[scalar] idot_i32 C sky130/axi | 1,805.0 | 2,888.0 | 1,848,322 elem/s | 2,957,315 elem/s |
| kernels[scalar] idot_i32 C sky130/soc | 1,994.2 | 3,190.7 | 2,042,054 elem/s | 3,267,286 elem/s |
| kernels[scalar] idot_i32 RVV sky130/axi | 3,113.6 | 4,981.8 | 3,188,323 elem/s | 5,101,316 elem/s |
| kernels[scalar] idot_i32 RVV sky130/soc | 3,722.8 | 5,956.5 | 3,812,190 elem/s | 6,099,504 elem/s |
| kernels[scalar] memcpy C sky130/axi | 2,839.9 | 4,543.9 | 11,632,398 byte/s | 18,611,837 byte/s |
| kernels[scalar] memcpy C sky130/soc | 3,668.9 | 5,870.2 | 15,027,663 byte/s | 24,044,261 byte/s |
| kernels[scalar] memcpy RVV sky130/axi | 4,887.1 | 7,819.4 | 20,017,594 byte/s | 32,028,150 byte/s |
| kernels[scalar] memcpy RVV sky130/soc | 8,212.6 | 13,140.2 | 33,638,842 byte/s | 53,822,148 byte/s |
| kernels[scalar] memcpy RVV-e8 sky130/axi | 1,391.6 | 2,226.6 | 5,700,067 byte/s | 9,120,108 byte/s |
| kernels[scalar] memcpy RVV-e8 sky130/soc | 1,569.5 | 2,511.3 | 6,428,809 byte/s | 10,286,095 byte/s |
| kernels[scalar] memset C sky130/axi | 7,007.7 | 11,212.3 | 28,703,574 byte/s | 45,925,718 byte/s |
| kernels[scalar] memset C sky130/soc | 7,058.6 | 11,293.7 | 28,911,853 byte/s | 46,258,964 byte/s |
| kernels[scalar] memset RVV sky130/axi | 21,063.3 | 33,701.2 | 86,275,171 byte/s | 138,040,273 byte/s |
| kernels[scalar] memset RVV sky130/soc | 21,529.5 | 34,447.1 | 88,184,637 byte/s | 141,095,419 byte/s |
| kernels[scalar] memset RVV-e8 sky130/axi | 2,927.4 | 4,683.8 | 11,990,632 byte/s | 19,185,012 byte/s |
| kernels[scalar] memset RVV-e8 sky130/soc | 2,936.2 | 4,698.0 | 12,026,825 byte/s | 19,242,921 byte/s |
| kernels[scalar] dgemm C sky130/axi | 27.1 | 43.3 | 886,939 mac/s | 1,419,102 mac/s |
| kernels[scalar] dgemm C sky130/soc | 43.3 | 69.3 | 1,419,661 mac/s | 2,271,458 mac/s |
| kernels[scalar] dgemm RVV sky130/axi | 104.2 | 166.6 | 3,412,824 mac/s | 5,460,519 mac/s |
| kernels[scalar] dgemm RVV sky130/soc | 128.8 | 206.1 | 4,221,486 mac/s | 6,754,377 mac/s |
| kernels[scalar] sgemm C sky130/axi | 43.8 | 70.1 | 1,435,000 mac/s | 2,296,000 mac/s |
| kernels[scalar] sgemm C sky130/soc | 48.6 | 77.7 | 1,591,386 mac/s | 2,546,217 mac/s |
| kernels[scalar] sgemm RVV sky130/axi | 137.4 | 219.8 | 4,500,701 mac/s | 7,201,121 mac/s |
| kernels[scalar] sgemm RVV sky130/soc | 140.7 | 225.2 | 4,611,413 mac/s | 7,378,261 mac/s |
| kernels[scalar] fir_f32 C sky130/axi | 83.4 | 133.4 | 1,366,343 mac/s | 2,186,149 mac/s |
| kernels[scalar] fir_f32 C sky130/soc | 85.6 | 136.9 | 1,402,031 mac/s | 2,243,250 mac/s |
| kernels[scalar] fir_f32 RVV sky130/axi | 289.6 | 463.3 | 4,744,140 mac/s | 7,590,623 mac/s |
| kernels[scalar] fir_f32 RVV sky130/soc | 298.0 | 476.8 | 4,882,375 mac/s | 7,811,800 mac/s |
| kernels[scalar] mac_i8 C sky130/axi | 459.5 | 735.2 | 1,882,218 mac/s | 3,011,549 mac/s |
| kernels[scalar] mac_i8 C sky130/soc | 470.9 | 753.5 | 1,928,895 mac/s | 3,086,231 mac/s |
| kernels[scalar] mac_i8 RVV sky130/axi | 990.0 | 1,584.0 | 4,055,060 mac/s | 6,488,096 mac/s |
| kernels[scalar] mac_i8 RVV sky130/soc | 1,044.5 | 1,671.1 | 4,278,093 mac/s | 6,844,948 mac/s |
| kernels[scalar] mac_i16 C sky130/axi | 886.0 | 1,417.6 | 1,814,573 mac/s | 2,903,317 mac/s |
| kernels[scalar] mac_i16 C sky130/soc | 930.0 | 1,488.0 | 1,904,620 mac/s | 3,047,392 mac/s |
| kernels[scalar] mac_i16 RVV sky130/axi | 1,923.7 | 3,078.0 | 3,939,825 mac/s | 6,303,721 mac/s |
| kernels[scalar] mac_i16 RVV sky130/soc | 2,140.1 | 3,424.2 | 4,382,999 mac/s | 7,012,798 mac/s |
| micro_dmem[default] empty sky130/axi | 1,969,230,769.2 | 3,150,769,230.8 | - | - |
| micro_dmem[default] empty sky130/soc | 2,438,095,238.1 | 3,900,952,381.0 | - | - |
| micro_dmem[default] chase_rand_1k sky130/axi | 12,082,310.7 | 19,331,697.2 | - | - |
| micro_dmem[default] chase_rand_1k sky130/soc | 12,096,583.7 | 19,354,533.9 | - | - |
| micro_dmem[default] chase_rand_2k sky130/axi | 12,082,310.7 | 19,331,697.2 | - | - |
| micro_dmem[default] chase_rand_2k sky130/soc | 12,096,583.7 | 19,354,533.9 | - | - |
| micro_dmem[default] chase_rand_4k sky130/axi | 11,948,658.1 | 19,117,853.0 | - | - |
| micro_dmem[default] chase_rand_4k sky130/soc | 12,051,595.9 | 19,282,553.4 | - | - |
| micro_dmem[default] chase_rand_8k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_8k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_rand_12k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_12k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_rand_16k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_16k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_rand_20k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_20k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_rand_24k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_24k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_rand_32k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_32k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_rand_64k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_64k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_rand_128k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_128k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_rand_256k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_rand_256k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_seq_4k sky130/axi | 11,948,658.1 | 19,117,853.0 | - | - |
| micro_dmem[default] chase_seq_4k sky130/soc | 12,051,595.9 | 19,282,553.4 | - | - |
| micro_dmem[default] chase_seq_8k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_seq_8k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_seq_16k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_seq_16k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] chase_seq_32k sky130/axi | 1,480,282.2 | 2,368,451.5 | - | - |
| micro_dmem[default] chase_seq_32k sky130/soc | 3,637,293.6 | 5,819,669.8 | - | - |
| micro_dmem[default] stream_ld sky130/axi | 6,089,438.6 | 9,743,101.8 | - | - |
| micro_dmem[default] stream_ld sky130/soc | 8,795,135.2 | 14,072,216.3 | - | - |
| micro_dmem[default] stream_st sky130/axi | 3,723,203.1 | 5,957,125.0 | - | - |
| micro_dmem[default] stream_st sky130/soc | 6,587,242.4 | 10,539,587.8 | - | - |
| micro_imem[default] empty sky130/axi | 14,222,222,222.2 | 22,755,555,555.6 | - | - |
| micro_imem[default] empty sky130/soc | 23,097,744,360.9 | 36,956,390,977.4 | - | - |
| micro_imem[default] ifoot_1k sky130/axi | 18,518,183.6 | 29,629,093.8 | - | - |
| micro_imem[default] ifoot_1k sky130/soc | 19,665,079.1 | 31,464,126.6 | - | - |
| micro_imem[default] ifoot_2k sky130/axi | 19,595,460.9 | 31,352,737.4 | - | - |
| micro_imem[default] ifoot_2k sky130/soc | 20,224,364.0 | 32,358,982.5 | - | - |
| micro_imem[default] ifoot_3k sky130/axi | 19,982,957.2 | 31,972,731.6 | - | - |
| micro_imem[default] ifoot_3k sky130/soc | 20,417,929.5 | 32,668,687.2 | - | - |
| micro_imem[default] ifoot_4k sky130/axi | 19,717,586.6 | 31,548,138.6 | - | - |
| micro_imem[default] ifoot_4k sky130/soc | 20,357,852.9 | 32,572,564.6 | - | - |
| micro_imem[default] ifoot_6k sky130/axi | 13,496,533.6 | 21,594,453.8 | - | - |
| micro_imem[default] ifoot_6k sky130/soc | 17,658,826.0 | 28,254,121.5 | - | - |
| micro_imem[default] ifoot_8k sky130/axi | 11,655,878.4 | 18,649,405.4 | - | - |
| micro_imem[default] ifoot_8k sky130/soc | 16,559,932.7 | 26,495,892.4 | - | - |
| micro_imem[default] ifoot_12k sky130/axi | 11,689,586.7 | 18,703,338.7 | - | - |
| micro_imem[default] ifoot_12k sky130/soc | 16,592,131.7 | 26,547,410.7 | - | - |
| micro_imem[default] ifoot_16k sky130/axi | 11,706,514.0 | 18,730,422.5 | - | - |
| micro_imem[default] ifoot_16k sky130/soc | 16,608,278.2 | 26,573,245.1 | - | - |
| micro_imem[default] ifoot_24k sky130/axi | 11,723,490.5 | 18,757,584.8 | - | - |
| micro_imem[default] ifoot_24k sky130/soc | 16,624,456.1 | 26,599,129.8 | - | - |
| micro_imem[default] ifoot_32k sky130/axi | 11,733,655.2 | 18,773,848.3 | - | - |
| micro_imem[default] ifoot_32k sky130/soc | 16,633,637.6 | 26,613,820.2 | - | - |
| micro_pipe[default] empty sky130/axi | 1,430,167,597.8 | 2,288,268,156.4 | - | - |
| micro_pipe[default] empty sky130/soc | 2,115,702,479.3 | 3,385,123,966.9 | - | - |
| micro_pipe[default] loop sky130/axi | 6,903,805.2 | 11,046,088.3 | - | - |
| micro_pipe[default] loop sky130/soc | 6,919,292.9 | 11,070,868.7 | - | - |
| micro_pipe[default] alu32_dep sky130/axi | 20,221,169.0 | 32,353,870.5 | - | - |
| micro_pipe[default] alu32_dep sky130/soc | 20,349,761.5 | 32,559,618.4 | - | - |
| micro_pipe[default] alu32_indep sky130/axi | 20,187,682.4 | 32,300,291.8 | - | - |
| micro_pipe[default] alu32_indep sky130/soc | 20,320,685.8 | 32,513,097.3 | - | - |
| micro_pipe[default] alu16_dep sky130/axi | 20,197,238.7 | 32,315,581.9 | - | - |
| micro_pipe[default] alu16_dep sky130/soc | 20,330,368.5 | 32,528,589.6 | - | - |
| micro_pipe[default] alu32_straddle sky130/axi | 10,167,202.8 | 16,267,524.5 | - | - |
| micro_pipe[default] alu32_straddle sky130/soc | 10,231,405.6 | 16,370,249.0 | - | - |
| micro_pipe[default] br_nt sky130/axi | 20,202,020.2 | 32,323,232.3 | - | - |
| micro_pipe[default] br_nt sky130/soc | 20,335,213.3 | 32,536,341.3 | - | - |
| micro_pipe[default] br_taken sky130/axi | 10,255,177.7 | 16,408,284.3 | - | - |
| micro_pipe[default] br_taken sky130/soc | 10,289,389.1 | 16,463,022.5 | - | - |
| micro_pipe[default] jal sky130/axi | 10,239,590.4 | 16,383,344.7 | - | - |
| micro_pipe[default] jal sky130/soc | 10,294,354.2 | 16,470,966.7 | - | - |
| micro_pipe[default] call_ret sky130/axi | 4,141,590.6 | 6,626,545.0 | - | - |
| micro_pipe[default] call_ret sky130/soc | 4,147,159.4 | 6,635,455.0 | - | - |
| micro_pipe[default] jalr_call_ret sky130/axi | 4,143,668.8 | 6,629,870.0 | - | - |
| micro_pipe[default] jalr_call_ret sky130/soc | 4,147,562.5 | 6,636,100.0 | - | - |
| micro_pipe[default] brpat_never sky130/axi | 4,721,940.4 | 7,555,104.7 | - | - |
| micro_pipe[default] brpat_never sky130/soc | 4,738,634.7 | 7,581,815.5 | - | - |
| micro_pipe[default] brpat_always sky130/axi | 3,849,450.4 | 6,159,120.6 | - | - |
| micro_pipe[default] brpat_always sky130/soc | 3,860,538.1 | 6,176,860.9 | - | - |
| micro_pipe[default] brpat_alt sky130/axi | 4,241,289.6 | 6,786,063.4 | - | - |
| micro_pipe[default] brpat_alt sky130/soc | 4,254,753.4 | 6,807,605.4 | - | - |
| micro_pipe[default] brpat_rand sky130/axi | 4,241,289.6 | 6,786,063.4 | - | - |
| micro_pipe[default] brpat_rand sky130/soc | 4,254,753.4 | 6,807,605.4 | - | - |
| micro_pipe[default] ld_dep sky130/axi | 12,265,235.7 | 19,624,377.2 | - | - |
| micro_pipe[default] ld_dep sky130/soc | 12,329,031.0 | 19,726,449.6 | - | - |
| micro_pipe[default] ld_indep sky130/axi | 12,279,944.4 | 19,647,911.0 | - | - |
| micro_pipe[default] ld_indep sky130/soc | 12,329,031.0 | 19,726,449.6 | - | - |
| micro_pipe[default] ld_use1 sky130/axi | 7,729,001.9 | 12,366,403.0 | - | - |
| micro_pipe[default] ld_use1 sky130/soc | 7,748,418.5 | 12,397,469.7 | - | - |
| micro_pipe[default] ld_use2 sky130/axi | 7,711,075.6 | 12,337,721.0 | - | - |
| micro_pipe[default] ld_use2 sky130/soc | 7,742,091.6 | 12,387,346.5 | - | - |
| micro_pipe[default] st sky130/axi | 12,278,766.4 | 19,646,026.2 | - | - |
| micro_pipe[default] st sky130/soc | 12,327,843.6 | 19,724,549.7 | - | - |
| micro_pipe[default] rdcycle sky130/axi | 20,254,767.0 | 32,407,627.2 | - | - |
| micro_pipe[default] rdcycle sky130/soc | 20,388,658.8 | 32,621,854.1 | - | - |
| micro_pipe[default] rdtime sky130/axi | 20,369,191.6 | 32,590,706.6 | - | - |
| micro_pipe[default] rdtime sky130/soc | 20,409,790.3 | 32,655,664.5 | - | - |
| micro_pipe[default] csrr sky130/axi | 20,278,834.0 | 32,446,134.3 | - | - |
| micro_pipe[default] csrr sky130/soc | 20,400,031.9 | 32,640,051.0 | - | - |
| micro_pipe[default] csrw sky130/axi | 20,343,293.1 | 32,549,268.9 | - | - |
| micro_pipe[default] csrw sky130/soc | 20,383,788.5 | 32,614,061.6 | - | - |
| micro_pipe[default] csrrw sky130/axi | 20,378,920.6 | 32,606,272.9 | - | - |
| micro_pipe[default] csrrw sky130/soc | 20,419,558.1 | 32,671,293.0 | - | - |
| micro_pipe[default] fence sky130/axi | 20,434,227.3 | 32,694,763.7 | - | - |
| micro_pipe[default] fence sky130/soc | 20,434,227.3 | 32,694,763.7 | - | - |
| micro_units[default] empty sky130/axi | 292,237,442.9 | 467,579,908.7 | - | - |
| micro_units[default] empty sky130/soc | 470,588,235.3 | 752,941,176.5 | - | - |
| micro_units[default] mul_dep sky130/axi | 14,437,175.7 | 23,099,481.2 | - | - |
| micro_units[default] mul_dep sky130/soc | 14,519,056.3 | 23,230,490.0 | - | - |
| micro_units[default] mul_indep sky130/axi | 14,352,993.9 | 22,964,790.3 | - | - |
| micro_units[default] mul_indep sky130/soc | 14,598,540.1 | 23,357,664.2 | - | - |
| micro_units[default] div_dep sky130/axi | 1,720,753.9 | 2,753,206.2 | - | - |
| micro_units[default] div_dep sky130/soc | 1,723,070.3 | 2,756,912.5 | - | - |
| micro_units[default] div_indep sky130/axi | 1,722,050.3 | 2,755,280.5 | - | - |
| micro_units[default] div_indep sky130/soc | 1,723,209.5 | 2,757,135.2 | - | - |
| micro_units[default] div_short sky130/axi | 14,675,533.1 | 23,480,853.0 | - | - |
| micro_units[default] div_short sky130/soc | 14,760,147.6 | 23,616,236.2 | - | - |
| micro_units[default] divw_dep sky130/axi | 3,077,366.9 | 4,923,787.1 | - | - |
| micro_units[default] divw_dep sky130/soc | 3,084,783.3 | 4,935,653.3 | - | - |
| micro_units[default] rem_indep sky130/axi | 1,771,577.3 | 2,834,523.6 | - | - |
| micro_units[default] rem_indep sky130/soc | 1,772,804.1 | 2,836,486.5 | - | - |
| micro_units[default] fadd_d_dep sky130/axi | 9,482,886.4 | 15,172,618.2 | - | - |
| micro_units[default] fadd_d_dep sky130/soc | 9,834,050.4 | 15,734,480.6 | - | - |
| micro_units[default] fadd_d_indep sky130/axi | 9,811,436.5 | 15,698,298.3 | - | - |
| micro_units[default] fadd_d_indep sky130/soc | 9,964,191.2 | 15,942,705.9 | - | - |
| micro_units[default] fmul_d_dep sky130/axi | 9,882,643.6 | 15,812,229.8 | - | - |
| micro_units[default] fmul_d_dep sky130/soc | 9,959,539.4 | 15,935,263.0 | - | - |
| micro_units[default] fmadd_d_dep sky130/axi | 7,474,016.1 | 11,958,425.8 | - | - |
| micro_units[default] fmadd_d_dep sky130/soc | 7,517,913.8 | 12,028,662.0 | - | - |
| micro_units[default] fdiv_d_dep sky130/axi | 1,871,345.0 | 2,994,152.0 | - | - |
| micro_units[default] fdiv_d_dep sky130/soc | 1,876,832.8 | 3,002,932.6 | - | - |
| micro_units[default] fdiv_d_indep sky130/axi | 1,876,172.6 | 3,001,876.2 | - | - |
| micro_units[default] fdiv_d_indep sky130/soc | 1,878,926.7 | 3,006,282.7 | - | - |
| micro_units[default] fsqrt_d_dep sky130/axi | 1,877,053.0 | 3,003,284.8 | - | - |
| micro_units[default] fsqrt_d_dep sky130/soc | 1,879,809.7 | 3,007,695.5 | - | - |
| micro_units[default] fsqrt_d_indep sky130/axi | 1,880,141.0 | 3,008,225.6 | - | - |
| micro_units[default] fsqrt_d_indep sky130/soc | 1,880,141.0 | 3,008,225.6 | - | - |
| micro_units[default] fdiv_s_dep sky130/axi | 3,414,790.3 | 5,463,664.5 | - | - |
| micro_units[default] fdiv_s_dep sky130/soc | 3,419,351.4 | 5,470,962.2 | - | - |
| micro_units[default] fsqrt_s_dep sky130/axi | 3,418,438.2 | 5,469,501.1 | - | - |
| micro_units[default] fsqrt_s_dep sky130/soc | 3,423,009.0 | 5,476,814.5 | - | - |
| micro_vec[default] empty sky130/axi | 75,117,370.9 | 120,187,793.4 | - | - |
| micro_vec[default] empty sky130/soc | 120,300,751.9 | 192,481,203.0 | - | - |
| micro_vec[default] vsetvli_same sky130/axi | 15,984,016.0 | 25,574,425.6 | - | - |
| micro_vec[default] vsetvli_same sky130/soc | 16,824,395.4 | 26,919,032.6 | - | - |
| micro_vec[default] vsetvli_toggle sky130/axi | 15,655,577.3 | 25,048,923.7 | - | - |
| micro_vec[default] vsetvli_toggle sky130/soc | 16,460,905.3 | 26,337,448.6 | - | - |
| micro_vec[default] vadd_e8_vl1 sky130/axi | 7,014,467.3 | 11,223,147.7 | - | - |
| micro_vec[default] vadd_e8_vl1 sky130/soc | 7,171,671.9 | 11,474,675.0 | - | - |
| micro_vec[default] vadd_e8_vl2 sky130/axi | 6,400,000.0 | 10,240,000.0 | - | - |
| micro_vec[default] vadd_e8_vl2 sky130/soc | 6,464,646.5 | 10,343,434.3 | - | - |
| micro_vec[default] vadd_e8_vl4 sky130/axi | 5,312,085.0 | 8,499,336.0 | - | - |
| micro_vec[default] vadd_e8_vl4 sky130/soc | 5,356,545.0 | 8,570,472.0 | - | - |
| micro_vec[default] vadd_e8_vl8 sky130/axi | 3,964,321.1 | 6,342,913.8 | - | - |
| micro_vec[default] vadd_e8_vl8 sky130/soc | 3,989,030.2 | 6,382,448.3 | - | - |
| micro_vec[default] vadd_e8_vl16 sky130/axi | 2,629,848.8 | 4,207,758.1 | - | - |
| micro_vec[default] vadd_e8_vl16 sky130/soc | 2,640,699.8 | 4,225,119.7 | - | - |
| micro_vec[default] vadd_e8_vl32 sky130/axi | 1,571,709.2 | 2,514,734.8 | - | - |
| micro_vec[default] vadd_e8_vl32 sky130/soc | 1,575,578.5 | 2,520,925.7 | - | - |
| micro_vec[default] vadd_e8_vl64 sky130/axi | 870,890.5 | 1,393,424.8 | - | - |
| micro_vec[default] vadd_e8_vl64 sky130/soc | 872,077.2 | 1,395,323.5 | - | - |
| micro_vec[default] vadd_e8_vl128 sky130/axi | 460,352.2 | 736,563.5 | - | - |
| micro_vec[default] vadd_e8_vl128 sky130/soc | 460,683.5 | 737,093.7 | - | - |
| micro_vec[default] vadd_e8_vl256 sky130/axi | 236,952.8 | 379,124.5 | - | - |
| micro_vec[default] vadd_e8_vl256 sky130/soc | 237,040.5 | 379,264.9 | - | - |
| micro_vec[default] vadd_e8_vl512 sky130/axi | 120,246.5 | 192,394.4 | - | - |
| micro_vec[default] vadd_e8_vl512 sky130/soc | 120,269.1 | 192,430.6 | - | - |
| micro_vec[default] vle8_vl1 sky130/axi | 7,729,468.6 | 12,367,149.8 | - | - |
| micro_vec[default] vle8_vl1 sky130/soc | 8,020,050.1 | 12,832,080.2 | - | - |
| micro_vec[default] vle8_vl2 sky130/axi | 5,240,746.8 | 8,385,194.9 | - | - |
| micro_vec[default] vle8_vl2 sky130/soc | 5,328,005.3 | 8,524,808.5 | - | - |
| micro_vec[default] vle8_vl4 sky130/axi | 3,141,566.9 | 5,026,507.0 | - | - |
| micro_vec[default] vle8_vl4 sky130/soc | 3,170,200.1 | 5,072,320.2 | - | - |
| micro_vec[default] vle8_vl8 sky130/axi | 1,744,249.4 | 2,790,799.1 | - | - |
| micro_vec[default] vle8_vl8 sky130/soc | 1,749,972.7 | 2,799,956.3 | - | - |
| micro_vec[default] vle8_vl16 sky130/axi | 921,659.0 | 1,474,654.4 | - | - |
| micro_vec[default] vle8_vl16 sky130/soc | 922,988.2 | 1,476,781.1 | - | - |
| micro_vec[default] vle8_vl32 sky130/axi | 474,158.4 | 758,653.4 | - | - |
| micro_vec[default] vle8_vl32 sky130/soc | 474,509.9 | 759,215.9 | - | - |
| micro_vec[default] vle8_vl64 sky130/axi | 240,558.1 | 384,893.0 | - | - |
| micro_vec[default] vle8_vl64 sky130/soc | 240,648.5 | 385,037.7 | - | - |
| micro_vec[default] vle8_vl128 sky130/axi | 121,086.4 | 193,738.3 | - | - |
| micro_vec[default] vle8_vl128 sky130/soc | 121,162.6 | 193,860.1 | - | - |
| micro_vec[default] vle8_vl256 sky130/axi | 60,808.8 | 97,294.0 | - | - |
| micro_vec[default] vle8_vl256 sky130/soc | 60,814.5 | 97,303.3 | - | - |
| micro_vec[default] vle8_vl512 sky130/axi | 30,456.6 | 48,730.5 | - | - |
| micro_vec[default] vle8_vl512 sky130/soc | 30,460.9 | 48,737.5 | - | - |
| micro_vec[default] vse8_vl1 sky130/axi | 6,959,547.6 | 11,135,276.2 | - | - |
| micro_vec[default] vse8_vl1 sky130/soc | 7,114,273.0 | 11,382,836.8 | - | - |
| micro_vec[default] vse8_vl8 sky130/axi | 1,425,770.8 | 2,281,233.3 | - | - |
| micro_vec[default] vse8_vl8 sky130/soc | 1,428,954.2 | 2,286,326.7 | - | - |
| micro_vec[default] vse8_vl64 sky130/axi | 192,999.0 | 308,798.3 | - | - |
| micro_vec[default] vse8_vl64 sky130/soc | 193,057.2 | 308,891.5 | - | - |
| micro_vec[default] vse8_vl512 sky130/axi | 24,377.5 | 39,004.1 | - | - |
| micro_vec[default] vse8_vl512 sky130/soc | 24,378.5 | 39,005.5 | - | - |
| micro_vec[default] vadd_e64_vl8 sky130/axi | 3,937,007.9 | 6,299,212.6 | - | - |
| micro_vec[default] vadd_e64_vl8 sky130/soc | 3,986,048.8 | 6,377,678.1 | - | - |
| micro_vec[default] vmul_e64_vl8 sky130/axi | 869,659.7 | 1,391,455.6 | - | - |
| micro_vec[default] vmul_e64_vl8 sky130/soc | 872,029.6 | 1,395,247.4 | - | - |
| micro_vec[default] vfadd_e64_vl8 sky130/axi | 1,119,585.8 | 1,791,337.2 | - | - |
| micro_vec[default] vfadd_e64_vl8 sky130/soc | 1,121,547.7 | 1,794,476.4 | - | - |
| micro_vec[default] vredsum_e64_vl8 sky130/axi | 3,506,465.0 | 5,610,344.1 | - | - |
| micro_vec[default] vredsum_e64_vl8 sky130/soc | 3,525,782.3 | 5,641,251.7 | - | - |
| sha256chain[sdk] sha256 plain C sky130/axi | 3,997.5 | 6,396.0 | 0.13 MB/s | 0.20 MB/s |
| sha256chain[sdk] sha256 plain C sky130/soc | 3,997.6 | 6,396.2 | 0.13 MB/s | 0.20 MB/s |
| sha256chain[sdk] sha256 Zknh sky130/axi | 5,815.2 | 9,304.4 | 0.19 MB/s | 0.30 MB/s |
| sha256chain[sdk] sha256 Zknh sky130/soc | 5,815.4 | 9,304.6 | 0.19 MB/s | 0.30 MB/s |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) sky130/axi | 12,625.6 | 20,200.9 | 0.40 MB/s | 0.65 MB/s |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) sky130/soc | 12,628.4 | 20,205.5 | 0.40 MB/s | 0.65 MB/s |
| sha256chain[sdk] sha256 accel sigil_sha256_block sky130/axi | 78,889.3 | 126,222.9 | 2.52 MB/s | 4.04 MB/s |
| sha256chain[sdk] sha256 accel sigil_sha256_block sky130/soc | 78,896.6 | 126,234.6 | 2.52 MB/s | 4.04 MB/s |
| sha256chain[sdk] sha256 accel sigil_sha256 sky130/axi | 14,132.4 | 22,611.9 | 0.45 MB/s | 0.72 MB/s |
| sha256chain[sdk] sha256 accel sigil_sha256 sky130/soc | 14,133.1 | 22,613.0 | 0.45 MB/s | 0.72 MB/s |
| sha256chain[sdk] sha512 accel sigil_hash sky130/axi | 16,553.8 | 26,486.1 | 1.06 MB/s | 1.70 MB/s |
| sha256chain[sdk] sha512 accel sigil_hash sky130/soc | 16,555.0 | 26,488.0 | 1.06 MB/s | 1.70 MB/s |
| sha256chain[sdk] sha3-256 accel sigil_hash sky130/axi | 29,476.7 | 47,162.7 | 0.94 MB/s | 1.51 MB/s |
| sha256chain[sdk] sha3-256 accel sigil_hash sky130/soc | 29,478.0 | 47,164.9 | 0.94 MB/s | 1.51 MB/s |
| sha256chain_bulk[sdk] sha256 plain C sky130/axi | 250.3 | 400.4 | 0.26 MB/s | 0.41 MB/s |
| sha256chain_bulk[sdk] sha256 plain C sky130/soc | 251.2 | 401.9 | 0.26 MB/s | 0.41 MB/s |
| sha256chain_bulk[sdk] sha256 Zknh sky130/axi | 363.9 | 582.3 | 0.37 MB/s | 0.60 MB/s |
| sha256chain_bulk[sdk] sha256 Zknh sky130/soc | 365.8 | 585.3 | 0.37 MB/s | 0.60 MB/s |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) sky130/axi | 730.7 | 1,169.1 | 0.75 MB/s | 1.20 MB/s |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) sky130/soc | 737.9 | 1,180.7 | 0.76 MB/s | 1.21 MB/s |
| sha256chain_bulk[sdk] sha512 accel sigil_hash sky130/axi | 9,926.0 | 15,881.6 | 10.16 MB/s | 16.26 MB/s |
| sha256chain_bulk[sdk] sha512 accel sigil_hash sky130/soc | 10,620.8 | 16,993.3 | 10.88 MB/s | 17.40 MB/s |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash sky130/axi | 9,976.2 | 15,961.9 | 10.22 MB/s | 16.35 MB/s |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash sky130/soc | 10,668.4 | 17,069.4 | 10.92 MB/s | 17.48 MB/s |

## Where the cycles go (% of cycles in the measured region)

| Run | retire | fetch_lat | fetch_straddle | fetch_miss | muldiv | fpu | vec | dc_lat | dc_miss | io | vls |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| coremark[scalar] sky130/axi | 22.8 | 60.5 | 3.1 | 0.2 | 1.6 | 0.0 | 0.0 | 11.8 | 0.0 | 0.0 | 0.0 |
| coremark[scalar] sky130/soc | 22.8 | 60.6 | 3.1 | 0.1 | 1.6 | 0.0 | 0.0 | 11.9 | 0.0 | 0.0 | 0.0 |
| coremark[sdk] sky130/axi | 22.4 | 60.5 | 3.5 | 0.2 | 1.6 | 0.0 | 0.1 | 11.6 | 0.0 | 0.0 | 0.2 |
| coremark[sdk] sky130/soc | 22.4 | 60.5 | 3.5 | 0.1 | 1.6 | 0.0 | 0.1 | 11.6 | 0.0 | 0.0 | 0.2 |
| coremark[validation] sky130/axi | 22.7 | 60.5 | 3.1 | 0.2 | 1.6 | 0.0 | 0.0 | 11.9 | 0.0 | 0.0 | 0.0 |
| coremark[validation] sky130/soc | 22.8 | 60.6 | 3.1 | 0.1 | 1.6 | 0.0 | 0.0 | 11.9 | 0.0 | 0.0 | 0.0 |
| dhrystone[scalar] sky130/axi | 18.3 | 53.4 | 3.7 | 0.0 | 0.1 | 0.0 | 0.0 | 13.8 | 10.7 | 0.0 | 0.0 |
| dhrystone[scalar] sky130/soc | 19.6 | 57.5 | 4.0 | 0.0 | 0.1 | 0.0 | 0.0 | 14.8 | 4.0 | 0.0 | 0.0 |
| dhrystone[sdk] sky130/axi | 15.5 | 42.1 | 1.5 | 0.0 | 0.1 | 0.0 | 0.0 | 10.9 | 14.6 | 0.0 | 15.3 |
| dhrystone[sdk] sky130/soc | 17.1 | 46.6 | 1.6 | 0.0 | 0.1 | 0.0 | 0.0 | 12.1 | 5.6 | 0.0 | 16.9 |
| kernels[autovec] vadd_i32 C sky130/axi | 2.4 | 7.6 | 1.2 | 0.0 | 0.0 | 0.0 | 4.8 | 0.0 | 0.1 | 0.0 | 83.8 |
| kernels[autovec] vadd_i32 C sky130/soc | 3.1 | 10.0 | 1.6 | 0.0 | 0.0 | 0.0 | 6.4 | 0.0 | 0.1 | 0.0 | 78.9 |
| kernels[autovec] vadd_i32 RVV sky130/axi | 0.4 | 1.0 | 0.1 | 0.0 | 0.0 | 0.0 | 4.2 | 0.0 | 0.2 | 0.0 | 94.0 |
| kernels[autovec] vadd_i32 RVV sky130/soc | 0.5 | 1.4 | 0.1 | 0.0 | 0.0 | 0.0 | 5.8 | 0.0 | 0.1 | 0.0 | 92.0 |
| kernels[autovec] vadd_i64 C sky130/axi | 3.3 | 9.2 | 1.0 | 0.1 | 0.0 | 0.0 | 4.1 | 0.0 | 0.2 | 0.0 | 82.1 |
| kernels[autovec] vadd_i64 C sky130/soc | 4.9 | 13.7 | 1.5 | 0.0 | 0.0 | 0.0 | 6.1 | 0.0 | 0.1 | 0.0 | 73.7 |
| kernels[autovec] vadd_i64 RVV sky130/axi | 0.5 | 1.4 | 0.1 | 0.1 | 0.0 | 0.0 | 3.1 | 0.0 | 0.3 | 0.0 | 94.5 |
| kernels[autovec] vadd_i64 RVV sky130/soc | 0.8 | 2.3 | 0.2 | 0.0 | 0.0 | 0.0 | 5.0 | 0.0 | 0.2 | 0.0 | 91.4 |
| kernels[autovec] daxpy C sky130/axi | 3.0 | 8.5 | 0.9 | 0.0 | 0.0 | 0.0 | 20.2 | 0.0 | 0.1 | 0.0 | 67.2 |
| kernels[autovec] daxpy C sky130/soc | 4.0 | 11.2 | 1.2 | 0.0 | 0.0 | 0.0 | 26.7 | 0.0 | 0.1 | 0.0 | 56.8 |
| kernels[autovec] daxpy RVV sky130/axi | 0.4 | 1.3 | 0.1 | 0.0 | 0.0 | 0.0 | 21.7 | 0.0 | 0.3 | 0.0 | 76.1 |
| kernels[autovec] daxpy RVV sky130/soc | 0.6 | 1.8 | 0.2 | 0.0 | 0.0 | 0.0 | 29.9 | 0.0 | 0.1 | 0.0 | 67.4 |
| kernels[autovec] saxpy C sky130/axi | 2.0 | 6.4 | 1.0 | 0.1 | 0.0 | 0.0 | 25.8 | 0.0 | 0.1 | 0.0 | 64.6 |
| kernels[autovec] saxpy C sky130/soc | 2.4 | 7.6 | 1.2 | 0.0 | 0.0 | 0.0 | 30.8 | 0.0 | 0.0 | 0.0 | 57.9 |
| kernels[autovec] saxpy RVV sky130/axi | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 27.6 | 0.0 | 0.1 | 0.0 | 71.0 |
| kernels[autovec] saxpy RVV sky130/soc | 0.3 | 1.0 | 0.1 | 0.0 | 0.0 | 0.0 | 33.5 | 0.0 | 0.1 | 0.0 | 65.0 |
| kernels[autovec] ddot C sky130/axi | 4.2 | 11.9 | 1.9 | 0.0 | 0.0 | 0.0 | 37.6 | 0.0 | 0.3 | 0.0 | 44.0 |
| kernels[autovec] ddot C sky130/soc | 5.0 | 14.2 | 2.3 | 0.0 | 0.0 | 0.0 | 45.0 | 0.0 | 0.1 | 0.0 | 33.4 |
| kernels[autovec] ddot RVV sky130/axi | 0.6 | 1.7 | 0.2 | 0.1 | 0.0 | 0.0 | 33.1 | 0.0 | 0.5 | 0.0 | 63.8 |
| kernels[autovec] ddot RVV sky130/soc | 0.8 | 2.3 | 0.3 | 0.0 | 0.0 | 0.0 | 43.3 | 0.0 | 0.2 | 0.0 | 53.1 |
| kernels[autovec] idot_i32 C sky130/axi | 4.3 | 12.8 | 1.6 | 0.0 | 0.0 | 0.0 | 27.9 | 0.0 | 0.2 | 0.0 | 53.1 |
| kernels[autovec] idot_i32 C sky130/soc | 4.9 | 14.8 | 1.9 | 0.0 | 0.0 | 0.0 | 32.2 | 0.0 | 0.1 | 0.0 | 46.1 |
| kernels[autovec] idot_i32 RVV sky130/axi | 0.7 | 2.2 | 0.3 | 0.0 | 0.0 | 0.0 | 31.8 | 0.0 | 0.3 | 0.0 | 64.7 |
| kernels[autovec] idot_i32 RVV sky130/soc | 0.9 | 2.6 | 0.3 | 0.0 | 0.0 | 0.0 | 38.0 | 0.0 | 0.1 | 0.0 | 58.1 |
| kernels[autovec] memcpy C sky130/axi | 11.8 | 39.9 | 4.7 | 0.0 | 0.0 | 0.0 | 0.0 | 9.3 | 34.3 | 0.0 | 0.0 |
| kernels[autovec] memcpy C sky130/soc | 15.2 | 51.5 | 6.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.0 | 15.2 | 0.0 | 0.0 |
| kernels[autovec] memcpy RVV sky130/axi | 0.5 | 1.7 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 | 0.0 | 97.1 |
| kernels[autovec] memcpy RVV sky130/soc | 0.9 | 2.8 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.0 | 95.6 |
| kernels[autovec] memcpy RVV-e8 sky130/axi | 0.2 | 0.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 99.2 |
| kernels[autovec] memcpy RVV-e8 sky130/soc | 0.2 | 0.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.2 |
| kernels[autovec] memset C sky130/axi | 17.6 | 64.0 | 5.8 | 0.1 | 0.0 | 0.0 | 0.0 | 11.5 | 1.0 | 0.0 | 0.0 |
| kernels[autovec] memset C sky130/soc | 17.7 | 64.5 | 5.8 | 0.0 | 0.0 | 0.0 | 0.0 | 11.6 | 0.4 | 0.0 | 0.0 |
| kernels[autovec] memset RVV sky130/axi | 2.0 | 5.6 | 0.3 | 0.3 | 0.1 | 0.0 | 2.3 | 0.1 | 2.2 | 0.0 | 87.0 |
| kernels[autovec] memset RVV sky130/soc | 2.1 | 5.7 | 0.3 | 0.1 | 0.1 | 0.0 | 2.4 | 0.1 | 0.8 | 0.0 | 88.5 |
| kernels[autovec] memset RVV-e8 sky130/axi | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 2.4 | 0.0 | 0.3 | 0.0 | 96.0 |
| kernels[autovec] memset RVV-e8 sky130/soc | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 2.4 | 0.0 | 0.1 | 0.0 | 96.3 |
| kernels[autovec] dgemm C sky130/axi | 9.0 | 21.1 | 0.1 | 0.0 | 0.0 | 8.5 | 0.0 | 5.8 | 55.6 | 0.0 | 0.0 |
| kernels[autovec] dgemm C sky130/soc | 14.4 | 33.7 | 0.2 | 0.0 | 0.0 | 13.6 | 0.0 | 9.2 | 28.9 | 0.0 | 0.0 |
| kernels[autovec] dgemm RVV sky130/axi | 1.1 | 2.6 | 0.0 | 0.0 | 0.0 | 0.0 | 44.7 | 0.3 | 1.1 | 0.0 | 50.0 |
| kernels[autovec] dgemm RVV sky130/soc | 1.4 | 3.3 | 0.1 | 0.0 | 0.0 | 0.0 | 55.3 | 0.4 | 0.5 | 0.0 | 39.1 |
| kernels[autovec] sgemm C sky130/axi | 14.5 | 42.9 | 4.7 | 0.0 | 0.0 | 13.8 | 0.0 | 9.3 | 14.8 | 0.0 | 0.0 |
| kernels[autovec] sgemm C sky130/soc | 16.1 | 47.6 | 5.2 | 0.0 | 0.0 | 15.3 | 0.0 | 10.3 | 5.5 | 0.0 | 0.0 |
| kernels[autovec] sgemm RVV sky130/axi | 1.5 | 4.8 | 0.7 | 0.0 | 0.0 | 0.0 | 59.0 | 0.5 | 0.8 | 0.0 | 32.8 |
| kernels[autovec] sgemm RVV sky130/soc | 1.5 | 4.9 | 0.7 | 0.0 | 0.0 | 0.0 | 60.4 | 0.5 | 0.3 | 0.0 | 31.6 |
| kernels[autovec] fir_f32 C sky130/axi | 4.7 | 12.9 | 1.8 | 0.0 | 0.0 | 0.0 | 48.6 | 0.5 | 0.5 | 0.0 | 31.0 |
| kernels[autovec] fir_f32 C sky130/soc | 4.8 | 13.1 | 1.8 | 0.0 | 0.0 | 0.0 | 49.4 | 0.5 | 0.2 | 0.0 | 30.1 |
| kernels[autovec] fir_f32 RVV sky130/axi | 0.4 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 61.5 | 0.1 | 0.3 | 0.0 | 36.7 |
| kernels[autovec] fir_f32 RVV sky130/soc | 0.4 | 1.0 | 0.0 | 0.0 | 0.0 | 0.0 | 63.3 | 0.1 | 0.1 | 0.0 | 35.1 |
| kernels[autovec] mac_i8 C sky130/axi | 3.6 | 9.1 | 1.0 | 0.0 | 0.0 | 0.0 | 38.6 | 0.0 | 0.1 | 0.0 | 47.6 |
| kernels[autovec] mac_i8 C sky130/soc | 3.7 | 9.5 | 1.0 | 0.0 | 0.0 | 0.0 | 40.3 | 0.0 | 0.0 | 0.0 | 45.3 |
| kernels[autovec] mac_i8 RVV sky130/axi | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 39.3 | 0.0 | 0.1 | 0.0 | 59.5 |
| kernels[autovec] mac_i8 RVV sky130/soc | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 41.4 | 0.0 | 0.0 | 0.0 | 57.4 |
| kernels[autovec] mac_i16 C sky130/axi | 2.8 | 8.5 | 1.1 | 0.0 | 0.0 | 0.0 | 29.8 | 0.0 | 0.2 | 0.0 | 57.6 |
| kernels[autovec] mac_i16 C sky130/soc | 3.1 | 9.3 | 1.2 | 0.0 | 0.0 | 0.0 | 32.7 | 0.0 | 0.1 | 0.0 | 53.6 |
| kernels[autovec] mac_i16 RVV sky130/axi | 0.5 | 1.3 | 0.2 | 0.0 | 0.0 | 0.0 | 32.6 | 0.0 | 0.2 | 0.0 | 65.2 |
| kernels[autovec] mac_i16 RVV sky130/soc | 0.5 | 1.5 | 0.2 | 0.0 | 0.0 | 0.0 | 36.3 | 0.0 | 0.1 | 0.0 | 61.4 |
| kernels[scalar] vadd_i32 C sky130/axi | 18.7 | 44.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 14.0 | 22.7 | 0.0 | 0.0 |
| kernels[scalar] vadd_i32 C sky130/soc | 22.0 | 52.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 16.5 | 9.1 | 0.0 | 0.0 |
| kernels[scalar] vadd_i32 RVV sky130/axi | 0.4 | 1.0 | 0.1 | 0.0 | 0.0 | 0.0 | 4.2 | 0.0 | 0.2 | 0.0 | 94.0 |
| kernels[scalar] vadd_i32 RVV sky130/soc | 0.5 | 1.4 | 0.1 | 0.0 | 0.0 | 0.0 | 5.8 | 0.0 | 0.1 | 0.0 | 92.0 |
| kernels[scalar] vadd_i64 C sky130/axi | 15.3 | 36.3 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 11.4 | 37.0 | 0.0 | 0.0 |
| kernels[scalar] vadd_i64 C sky130/soc | 20.2 | 48.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.1 | 16.6 | 0.0 | 0.0 |
| kernels[scalar] vadd_i64 RVV sky130/axi | 0.5 | 1.4 | 0.1 | 0.1 | 0.0 | 0.0 | 3.1 | 0.0 | 0.3 | 0.0 | 94.5 |
| kernels[scalar] vadd_i64 RVV sky130/soc | 0.8 | 2.3 | 0.2 | 0.0 | 0.0 | 0.0 | 5.0 | 0.0 | 0.2 | 0.0 | 91.4 |
| kernels[scalar] daxpy C sky130/axi | 11.7 | 36.8 | 5.0 | 0.1 | 0.0 | 10.0 | 0.0 | 10.0 | 26.3 | 0.0 | 0.0 |
| kernels[scalar] daxpy C sky130/soc | 14.2 | 44.6 | 6.1 | 0.0 | 0.0 | 12.1 | 0.0 | 12.1 | 10.9 | 0.0 | 0.0 |
| kernels[scalar] daxpy RVV sky130/axi | 0.4 | 1.3 | 0.1 | 0.0 | 0.0 | 0.0 | 21.7 | 0.0 | 0.3 | 0.0 | 76.1 |
| kernels[scalar] daxpy RVV sky130/soc | 0.6 | 1.8 | 0.2 | 0.0 | 0.0 | 0.0 | 29.9 | 0.0 | 0.1 | 0.0 | 67.4 |
| kernels[scalar] saxpy C sky130/axi | 12.1 | 44.9 | 8.6 | 0.0 | 0.0 | 10.4 | 0.0 | 10.4 | 13.6 | 0.0 | 0.0 |
| kernels[scalar] saxpy C sky130/soc | 13.3 | 49.4 | 9.5 | 0.0 | 0.0 | 11.4 | 0.0 | 11.4 | 5.1 | 0.0 | 0.0 |
| kernels[scalar] saxpy RVV sky130/axi | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 27.6 | 0.0 | 0.1 | 0.0 | 71.0 |
| kernels[scalar] saxpy RVV sky130/soc | 0.3 | 1.0 | 0.1 | 0.0 | 0.0 | 0.0 | 33.5 | 0.0 | 0.1 | 0.0 | 65.0 |
| kernels[scalar] ddot C sky130/axi | 13.2 | 39.6 | 4.4 | 0.0 | 0.0 | 13.1 | 0.0 | 8.8 | 20.8 | 0.0 | 0.0 |
| kernels[scalar] ddot C sky130/soc | 15.4 | 46.1 | 5.1 | 0.0 | 0.0 | 15.3 | 0.0 | 10.2 | 7.9 | 0.0 | 0.0 |
| kernels[scalar] ddot RVV sky130/axi | 0.6 | 1.7 | 0.2 | 0.1 | 0.0 | 0.0 | 33.1 | 0.0 | 0.5 | 0.0 | 63.8 |
| kernels[scalar] ddot RVV sky130/soc | 0.8 | 2.3 | 0.3 | 0.0 | 0.0 | 0.0 | 43.3 | 0.0 | 0.2 | 0.0 | 53.1 |
| kernels[scalar] idot_i32 C sky130/axi | 20.7 | 47.4 | 0.0 | 0.0 | 5.9 | 0.0 | 0.0 | 11.8 | 14.0 | 0.0 | 0.0 |
| kernels[scalar] idot_i32 C sky130/soc | 22.9 | 52.4 | 0.0 | 0.0 | 6.5 | 0.0 | 0.0 | 13.1 | 5.0 | 0.0 | 0.0 |
| kernels[scalar] idot_i32 RVV sky130/axi | 0.7 | 2.2 | 0.3 | 0.0 | 0.0 | 0.0 | 31.8 | 0.0 | 0.3 | 0.0 | 64.7 |
| kernels[scalar] idot_i32 RVV sky130/soc | 0.9 | 2.6 | 0.3 | 0.0 | 0.0 | 0.0 | 38.0 | 0.0 | 0.1 | 0.0 | 58.1 |
| kernels[scalar] memcpy C sky130/axi | 11.8 | 39.9 | 4.7 | 0.0 | 0.0 | 0.0 | 0.0 | 9.3 | 34.3 | 0.0 | 0.0 |
| kernels[scalar] memcpy C sky130/soc | 15.2 | 51.5 | 6.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.0 | 15.2 | 0.0 | 0.0 |
| kernels[scalar] memcpy RVV sky130/axi | 0.5 | 1.7 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 | 0.0 | 97.1 |
| kernels[scalar] memcpy RVV sky130/soc | 0.9 | 2.8 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.0 | 95.6 |
| kernels[scalar] memcpy RVV-e8 sky130/axi | 0.2 | 0.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 99.2 |
| kernels[scalar] memcpy RVV-e8 sky130/soc | 0.2 | 0.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.2 |
| kernels[scalar] memset C sky130/axi | 17.6 | 64.0 | 5.8 | 0.1 | 0.0 | 0.0 | 0.0 | 11.5 | 1.0 | 0.0 | 0.0 |
| kernels[scalar] memset C sky130/soc | 17.7 | 64.5 | 5.8 | 0.0 | 0.0 | 0.0 | 0.0 | 11.6 | 0.4 | 0.0 | 0.0 |
| kernels[scalar] memset RVV sky130/axi | 2.0 | 5.6 | 0.3 | 0.3 | 0.1 | 0.0 | 2.3 | 0.1 | 2.2 | 0.0 | 87.0 |
| kernels[scalar] memset RVV sky130/soc | 2.1 | 5.7 | 0.3 | 0.1 | 0.1 | 0.0 | 2.4 | 0.1 | 0.8 | 0.0 | 88.5 |
| kernels[scalar] memset RVV-e8 sky130/axi | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 2.4 | 0.0 | 0.3 | 0.0 | 96.0 |
| kernels[scalar] memset RVV-e8 sky130/soc | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 2.4 | 0.0 | 0.1 | 0.0 | 96.3 |
| kernels[scalar] dgemm C sky130/axi | 9.0 | 21.1 | 0.1 | 0.0 | 0.0 | 8.5 | 0.0 | 5.8 | 55.6 | 0.0 | 0.0 |
| kernels[scalar] dgemm C sky130/soc | 14.4 | 33.7 | 0.2 | 0.0 | 0.0 | 13.6 | 0.0 | 9.2 | 28.9 | 0.0 | 0.0 |
| kernels[scalar] dgemm RVV sky130/axi | 1.1 | 2.6 | 0.0 | 0.0 | 0.0 | 0.0 | 44.7 | 0.3 | 1.1 | 0.0 | 50.0 |
| kernels[scalar] dgemm RVV sky130/soc | 1.4 | 3.3 | 0.1 | 0.0 | 0.0 | 0.0 | 55.3 | 0.4 | 0.5 | 0.0 | 39.1 |
| kernels[scalar] sgemm C sky130/axi | 14.5 | 42.9 | 4.7 | 0.0 | 0.0 | 13.8 | 0.0 | 9.3 | 14.8 | 0.0 | 0.0 |
| kernels[scalar] sgemm C sky130/soc | 16.1 | 47.6 | 5.2 | 0.0 | 0.0 | 15.3 | 0.0 | 10.3 | 5.5 | 0.0 | 0.0 |
| kernels[scalar] sgemm RVV sky130/axi | 1.5 | 4.8 | 0.7 | 0.0 | 0.0 | 0.0 | 59.0 | 0.5 | 0.8 | 0.0 | 32.8 |
| kernels[scalar] sgemm RVV sky130/soc | 1.5 | 4.9 | 0.7 | 0.0 | 0.0 | 0.0 | 60.4 | 0.5 | 0.3 | 0.0 | 31.6 |
| kernels[scalar] fir_f32 C sky130/axi | 14.2 | 50.8 | 9.0 | 0.0 | 0.0 | 13.1 | 0.0 | 9.0 | 3.8 | 0.0 | 0.0 |
| kernels[scalar] fir_f32 C sky130/soc | 14.6 | 52.2 | 9.3 | 0.0 | 0.0 | 13.5 | 0.0 | 9.3 | 1.3 | 0.0 | 0.0 |
| kernels[scalar] fir_f32 RVV sky130/axi | 0.4 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 61.5 | 0.1 | 0.3 | 0.0 | 36.7 |
| kernels[scalar] fir_f32 RVV sky130/soc | 0.4 | 1.0 | 0.0 | 0.0 | 0.0 | 0.0 | 63.3 | 0.1 | 0.1 | 0.0 | 35.1 |
| kernels[scalar] mac_i8 C sky130/axi | 21.1 | 54.2 | 3.0 | 0.0 | 6.0 | 0.0 | 0.0 | 12.0 | 3.6 | 0.0 | 0.0 |
| kernels[scalar] mac_i8 C sky130/soc | 21.6 | 55.6 | 3.1 | 0.0 | 6.2 | 0.0 | 0.0 | 12.3 | 1.2 | 0.0 | 0.0 |
| kernels[scalar] mac_i8 RVV sky130/axi | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 39.3 | 0.0 | 0.1 | 0.0 | 59.5 |
| kernels[scalar] mac_i8 RVV sky130/soc | 0.3 | 0.8 | 0.1 | 0.0 | 0.0 | 0.0 | 41.4 | 0.0 | 0.0 | 0.0 | 57.4 |
| kernels[scalar] mac_i16 C sky130/axi | 20.3 | 52.3 | 2.9 | 0.1 | 5.8 | 0.0 | 0.0 | 11.6 | 6.9 | 0.0 | 0.0 |
| kernels[scalar] mac_i16 C sky130/soc | 21.4 | 54.9 | 3.1 | 0.0 | 6.1 | 0.0 | 0.0 | 12.2 | 2.3 | 0.0 | 0.0 |
| kernels[scalar] mac_i16 RVV sky130/axi | 0.5 | 1.3 | 0.2 | 0.0 | 0.0 | 0.0 | 32.6 | 0.0 | 0.2 | 0.0 | 65.2 |
| kernels[scalar] mac_i16 RVV sky130/soc | 0.5 | 1.5 | 0.2 | 0.0 | 0.0 | 0.0 | 36.3 | 0.0 | 0.1 | 0.0 | 61.4 |
| micro_dmem[default] empty sky130/axi | 15.4 | 42.3 | 3.8 | 29.2 | 0.0 | 0.0 | 0.0 | 9.2 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] empty sky130/soc | 19.0 | 52.4 | 4.8 | 12.4 | 0.0 | 0.0 | 0.0 | 11.4 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_1k sky130/axi | 20.0 | 41.0 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 38.7 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_1k sky130/soc | 20.1 | 41.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 38.8 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_2k sky130/axi | 20.0 | 41.0 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 38.7 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_2k sky130/soc | 20.1 | 41.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 38.8 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_4k sky130/axi | 19.8 | 40.6 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 38.3 | 1.1 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_4k sky130/soc | 20.0 | 40.9 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 38.6 | 0.4 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_8k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_8k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_12k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_12k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_16k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_16k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_20k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_20k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_24k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_24k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_32k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_32k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_64k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_64k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_128k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_128k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_256k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_256k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_4k sky130/axi | 19.8 | 40.6 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 38.3 | 1.1 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_4k sky130/soc | 20.0 | 40.9 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 38.6 | 0.4 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_8k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_8k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_16k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_16k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_32k sky130/axi | 2.5 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 87.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_32k sky130/soc | 6.0 | 12.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.7 | 69.9 | 0.0 | 0.0 |
| micro_dmem[default] stream_ld sky130/axi | 11.5 | 23.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 19.5 | 45.5 | 0.0 | 0.0 |
| micro_dmem[default] stream_ld sky130/soc | 16.6 | 33.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 28.2 | 21.3 | 0.0 | 0.0 |
| micro_dmem[default] stream_st sky130/axi | 7.0 | 14.3 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 11.9 | 66.7 | 0.0 | 0.0 |
| micro_dmem[default] stream_st sky130/soc | 12.4 | 25.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 21.1 | 41.1 | 0.0 | 0.0 |
| micro_imem[default] empty sky130/axi | 9.3 | 25.0 | 1.9 | 17.1 | 0.0 | 0.0 | 0.0 | 5.6 | 41.2 | 0.0 | 0.0 |
| micro_imem[default] empty sky130/soc | 15.0 | 40.6 | 3.0 | 9.0 | 0.0 | 0.0 | 0.0 | 9.0 | 23.3 | 0.0 | 0.0 |
| micro_imem[default] ifoot_1k sky130/axi | 30.1 | 61.3 | 0.0 | 8.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_1k sky130/soc | 32.0 | 65.0 | 0.0 | 3.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_2k sky130/axi | 31.6 | 63.8 | 0.0 | 4.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_2k sky130/soc | 32.6 | 65.8 | 0.0 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_3k sky130/axi | 32.2 | 64.7 | 0.0 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_3k sky130/soc | 32.9 | 66.1 | 0.0 | 1.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_4k sky130/axi | 31.7 | 63.7 | 0.0 | 4.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_4k sky130/soc | 32.7 | 65.7 | 0.0 | 1.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_6k sky130/axi | 21.7 | 43.4 | 0.0 | 34.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_6k sky130/soc | 28.3 | 56.8 | 0.0 | 14.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_8k sky130/axi | 18.7 | 37.5 | 0.0 | 43.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_8k sky130/soc | 26.6 | 53.2 | 0.0 | 20.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_12k sky130/axi | 18.7 | 37.5 | 0.0 | 43.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_12k sky130/soc | 26.6 | 53.3 | 0.0 | 20.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_16k sky130/axi | 18.8 | 37.6 | 0.0 | 43.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_16k sky130/soc | 26.6 | 53.3 | 0.0 | 20.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_24k sky130/axi | 18.8 | 37.6 | 0.0 | 43.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_24k sky130/soc | 26.6 | 53.3 | 0.0 | 20.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_32k sky130/axi | 18.8 | 37.6 | 0.0 | 43.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_32k sky130/soc | 26.6 | 53.3 | 0.0 | 20.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] empty sky130/axi | 11.2 | 29.1 | 2.2 | 1.1 | 0.0 | 0.0 | 0.0 | 6.7 | 49.7 | 0.0 | 0.0 |
| micro_pipe[default] empty sky130/soc | 16.5 | 43.0 | 3.3 | 1.7 | 0.0 | 0.0 | 0.0 | 9.9 | 25.6 | 0.0 | 0.0 |
| micro_pipe[default] loop sky130/axi | 22.1 | 77.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 |
| micro_pipe[default] loop sky130/soc | 22.2 | 77.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] alu32_dep sky130/axi | 32.8 | 66.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.9 | 0.0 | 0.0 |
| micro_pipe[default] alu32_dep sky130/soc | 33.0 | 66.6 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_pipe[default] alu32_indep sky130/axi | 32.8 | 66.1 | 0.1 | 0.3 | 0.0 | 0.0 | 0.0 | 0.1 | 0.7 | 0.0 | 0.0 |
| micro_pipe[default] alu32_indep sky130/soc | 33.0 | 66.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_pipe[default] alu16_dep sky130/axi | 32.8 | 66.1 | 0.1 | 0.3 | 0.0 | 0.0 | 0.0 | 0.1 | 0.7 | 0.0 | 0.0 |
| micro_pipe[default] alu16_dep sky130/soc | 33.0 | 66.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_pipe[default] alu32_straddle sky130/axi | 16.5 | 66.1 | 16.4 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] alu32_straddle sky130/soc | 16.6 | 66.5 | 16.5 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] br_nt sky130/axi | 32.8 | 66.1 | 0.1 | 0.3 | 0.0 | 0.0 | 0.0 | 0.1 | 0.7 | 0.0 | 0.0 |
| micro_pipe[default] br_nt sky130/soc | 33.0 | 66.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_pipe[default] br_taken sky130/axi | 16.6 | 82.8 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] br_taken sky130/soc | 16.7 | 83.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] jal sky130/axi | 16.6 | 82.5 | 0.0 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] jal sky130/soc | 16.7 | 83.0 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] call_ret sky130/axi | 20.0 | 79.8 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] call_ret sky130/soc | 20.0 | 79.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] jalr_call_ret sky130/axi | 20.0 | 79.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] jalr_call_ret sky130/soc | 20.0 | 79.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] brpat_never sky130/axi | 32.4 | 65.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 1.9 | 0.5 | 0.0 | 0.0 |
| micro_pipe[default] brpat_never sky130/soc | 32.5 | 65.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.9 | 0.2 | 0.0 | 0.0 |
| micro_pipe[default] brpat_always sky130/axi | 26.4 | 71.6 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 1.6 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] brpat_always sky130/soc | 26.5 | 71.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.6 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] brpat_alt sky130/axi | 29.1 | 68.7 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 1.7 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] brpat_alt sky130/soc | 29.2 | 68.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.7 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] brpat_rand sky130/axi | 29.1 | 68.7 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 1.7 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] brpat_rand sky130/soc | 29.2 | 68.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.7 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] ld_dep sky130/axi | 19.9 | 40.0 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 39.3 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] ld_dep sky130/soc | 20.0 | 40.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 39.5 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] ld_indep sky130/axi | 19.9 | 40.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 39.4 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] ld_indep sky130/soc | 20.0 | 40.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 39.5 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] ld_use1 sky130/axi | 24.9 | 50.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 24.8 | 0.3 | 0.0 | 0.0 |
| micro_pipe[default] ld_use1 sky130/soc | 25.0 | 50.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 24.8 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] ld_use2 sky130/axi | 24.8 | 49.8 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 24.7 | 0.3 | 0.0 | 0.0 |
| micro_pipe[default] ld_use2 sky130/soc | 24.9 | 50.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 24.8 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] st sky130/axi | 19.9 | 40.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 39.3 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] st sky130/soc | 20.0 | 40.3 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 39.5 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] rdcycle sky130/axi | 32.8 | 66.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.1 | 0.7 | 0.0 | 0.0 |
| micro_pipe[default] rdcycle sky130/soc | 33.0 | 66.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_pipe[default] rdtime sky130/axi | 33.0 | 66.5 | 0.1 | 0.3 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] rdtime sky130/soc | 33.1 | 66.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrr sky130/axi | 32.9 | 66.1 | 0.0 | 0.9 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrr sky130/soc | 33.1 | 66.5 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrw sky130/axi | 33.0 | 66.6 | 0.1 | 0.3 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrw sky130/soc | 33.1 | 66.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrrw sky130/axi | 33.0 | 66.5 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrrw sky130/soc | 33.1 | 66.7 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] fence sky130/axi | 33.1 | 66.7 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] fence sky130/soc | 33.1 | 66.7 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] empty sky130/axi | 9.1 | 25.6 | 2.3 | 16.9 | 0.0 | 0.0 | 0.0 | 5.5 | 40.6 | 0.0 | 0.0 |
| micro_units[default] empty sky130/soc | 14.7 | 41.2 | 3.7 | 8.8 | 0.0 | 0.0 | 0.0 | 8.8 | 22.8 | 0.0 | 0.0 |
| micro_units[default] mul_dep sky130/axi | 24.5 | 27.8 | 0.4 | 0.8 | 46.2 | 0.0 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_units[default] mul_dep sky130/soc | 24.6 | 28.0 | 0.4 | 0.3 | 46.5 | 0.0 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_units[default] mul_indep sky130/axi | 24.4 | 26.9 | 0.0 | 1.7 | 45.9 | 0.0 | 0.0 | 0.3 | 0.8 | 0.0 | 0.0 |
| micro_units[default] mul_indep sky130/soc | 24.8 | 27.4 | 0.0 | 0.5 | 46.7 | 0.0 | 0.0 | 0.3 | 0.3 | 0.0 | 0.0 |
| micro_units[default] div_dep sky130/axi | 2.9 | 3.2 | 0.0 | 0.2 | 93.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_dep sky130/soc | 2.9 | 3.2 | 0.0 | 0.1 | 93.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_indep sky130/axi | 2.9 | 3.3 | 0.0 | 0.1 | 93.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_indep sky130/soc | 2.9 | 3.3 | 0.0 | 0.0 | 93.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_short sky130/axi | 24.7 | 27.2 | 0.0 | 0.8 | 47.0 | 0.0 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_short sky130/soc | 24.9 | 27.3 | 0.0 | 0.3 | 47.2 | 0.0 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_units[default] divw_dep sky130/axi | 5.2 | 5.7 | 0.0 | 0.2 | 88.6 | 0.0 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_units[default] divw_dep sky130/soc | 5.2 | 5.8 | 0.0 | 0.1 | 88.8 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 |
| micro_units[default] rem_indep sky130/axi | 3.0 | 3.3 | 0.0 | 0.1 | 93.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] rem_indep sky130/soc | 3.0 | 3.3 | 0.0 | 0.0 | 93.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fadd_d_dep sky130/axi | 16.0 | 17.7 | 0.1 | 2.6 | 0.0 | 60.7 | 0.0 | 0.2 | 2.6 | 0.0 | 0.0 |
| micro_units[default] fadd_d_dep sky130/soc | 16.6 | 18.4 | 0.1 | 0.8 | 0.0 | 62.9 | 0.0 | 0.2 | 1.0 | 0.0 | 0.0 |
| micro_units[default] fadd_d_indep sky130/axi | 16.5 | 18.3 | 0.1 | 2.2 | 0.0 | 62.8 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fadd_d_indep sky130/soc | 16.8 | 18.5 | 0.1 | 0.7 | 0.0 | 63.8 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fmul_d_dep sky130/axi | 16.7 | 18.6 | 0.2 | 0.5 | 0.0 | 63.2 | 0.0 | 0.2 | 0.6 | 0.0 | 0.0 |
| micro_units[default] fmul_d_dep sky130/soc | 16.8 | 18.8 | 0.2 | 0.2 | 0.0 | 63.7 | 0.0 | 0.2 | 0.2 | 0.0 | 0.0 |
| micro_units[default] fmadd_d_dep sky130/axi | 12.7 | 14.3 | 0.2 | 0.5 | 0.0 | 71.8 | 0.0 | 0.2 | 0.4 | 0.0 | 0.0 |
| micro_units[default] fmadd_d_dep sky130/soc | 12.7 | 14.4 | 0.2 | 0.2 | 0.0 | 72.2 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 |
| micro_units[default] fdiv_d_dep sky130/axi | 3.2 | 3.5 | 0.0 | 0.3 | 0.0 | 92.8 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_units[default] fdiv_d_dep sky130/soc | 3.2 | 3.5 | 0.0 | 0.1 | 0.0 | 93.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_d_indep sky130/axi | 3.2 | 3.5 | 0.0 | 0.1 | 0.0 | 93.1 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_units[default] fdiv_d_indep sky130/soc | 3.2 | 3.5 | 0.0 | 0.0 | 0.0 | 93.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_d_dep sky130/axi | 3.2 | 3.5 | 0.0 | 0.1 | 0.0 | 93.1 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_units[default] fsqrt_d_dep sky130/soc | 3.2 | 3.5 | 0.0 | 0.0 | 0.0 | 93.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_d_indep sky130/axi | 3.2 | 3.5 | 0.0 | 0.0 | 0.0 | 93.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_d_indep sky130/soc | 3.2 | 3.5 | 0.0 | 0.0 | 0.0 | 93.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_s_dep sky130/axi | 5.8 | 6.5 | 0.1 | 0.2 | 0.0 | 87.4 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_s_dep sky130/soc | 5.8 | 6.5 | 0.1 | 0.1 | 0.0 | 87.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_s_dep sky130/axi | 5.8 | 6.4 | 0.0 | 0.2 | 0.0 | 87.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_s_dep sky130/soc | 5.8 | 6.4 | 0.0 | 0.1 | 0.0 | 87.6 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] empty sky130/axi | 9.9 | 29.1 | 3.3 | 0.0 | 0.0 | 0.0 | 0.0 | 5.6 | 52.1 | 0.0 | 0.0 |
| micro_vec[default] empty sky130/soc | 15.8 | 46.6 | 5.3 | 0.0 | 0.0 | 0.0 | 0.0 | 9.0 | 23.3 | 0.0 | 0.0 |
| micro_vec[default] vsetvli_same sky130/axi | 29.3 | 61.8 | 0.3 | 3.7 | 0.0 | 0.0 | 0.0 | 1.2 | 3.7 | 0.0 | 0.0 |
| micro_vec[default] vsetvli_same sky130/soc | 30.8 | 65.1 | 0.3 | 1.3 | 0.0 | 0.0 | 0.0 | 1.3 | 1.3 | 0.0 | 0.0 |
| micro_vec[default] vsetvli_toggle sky130/axi | 28.7 | 61.9 | 1.0 | 3.6 | 0.0 | 0.0 | 0.0 | 1.2 | 3.6 | 0.0 | 0.0 |
| micro_vec[default] vsetvli_toggle sky130/soc | 30.1 | 65.1 | 1.0 | 1.2 | 0.0 | 0.0 | 0.0 | 1.2 | 1.2 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl1 sky130/axi | 12.8 | 15.9 | 0.2 | 1.6 | 0.0 | 0.0 | 67.3 | 0.5 | 1.6 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl1 sky130/soc | 13.1 | 16.3 | 0.2 | 0.5 | 0.0 | 0.0 | 68.8 | 0.5 | 0.5 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl2 sky130/axi | 11.7 | 14.5 | 0.2 | 0.0 | 0.0 | 0.0 | 71.7 | 0.5 | 1.5 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl2 sky130/soc | 11.8 | 14.7 | 0.2 | 0.0 | 0.0 | 0.0 | 72.4 | 0.5 | 0.5 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl4 sky130/axi | 9.7 | 12.1 | 0.1 | 0.0 | 0.0 | 0.0 | 76.5 | 0.4 | 1.2 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl4 sky130/soc | 9.8 | 12.2 | 0.1 | 0.0 | 0.0 | 0.0 | 77.1 | 0.4 | 0.4 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl8 sky130/axi | 7.2 | 9.0 | 0.1 | 0.0 | 0.0 | 0.0 | 82.5 | 0.3 | 0.9 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl8 sky130/soc | 7.3 | 9.1 | 0.1 | 0.0 | 0.0 | 0.0 | 83.0 | 0.3 | 0.3 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl16 sky130/axi | 4.8 | 6.0 | 0.1 | 0.0 | 0.0 | 0.0 | 88.4 | 0.2 | 0.6 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl16 sky130/soc | 4.8 | 6.0 | 0.1 | 0.0 | 0.0 | 0.0 | 88.7 | 0.2 | 0.2 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl32 sky130/axi | 2.9 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 93.0 | 0.1 | 0.4 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl32 sky130/soc | 2.9 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 93.3 | 0.1 | 0.1 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl64 sky130/axi | 1.6 | 2.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.1 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl64 sky130/soc | 1.6 | 2.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.3 | 0.1 | 0.1 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl128 sky130/axi | 0.8 | 1.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl128 sky130/soc | 0.8 | 1.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl256 sky130/axi | 0.4 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl256 sky130/soc | 0.4 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl512 sky130/axi | 0.2 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl512 sky130/soc | 0.2 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vle8_vl1 sky130/axi | 14.1 | 30.3 | 0.4 | 3.4 | 0.0 | 0.0 | 0.0 | 0.6 | 1.8 | 0.0 | 49.5 |
| micro_vec[default] vle8_vl1 sky130/soc | 14.6 | 31.4 | 0.5 | 1.0 | 0.0 | 0.0 | 0.0 | 0.6 | 0.6 | 0.0 | 51.3 |
| micro_vec[default] vle8_vl2 sky130/axi | 9.5 | 20.5 | 0.3 | 0.9 | 0.0 | 0.0 | 0.0 | 0.4 | 1.2 | 0.0 | 67.1 |
| micro_vec[default] vle8_vl2 sky130/soc | 9.7 | 20.9 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.4 | 0.4 | 0.0 | 68.2 |
| micro_vec[default] vle8_vl4 sky130/axi | 5.7 | 12.3 | 0.2 | 0.4 | 0.0 | 0.0 | 0.0 | 0.2 | 0.7 | 0.0 | 80.4 |
| micro_vec[default] vle8_vl4 sky130/soc | 5.8 | 12.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.2 | 0.0 | 81.2 |
| micro_vec[default] vle8_vl8 sky130/axi | 3.2 | 6.8 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.1 | 0.4 | 0.0 | 89.3 |
| micro_vec[default] vle8_vl8 sky130/soc | 3.2 | 6.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 89.6 |
| micro_vec[default] vle8_vl16 sky130/axi | 1.7 | 3.6 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.2 | 0.0 | 94.4 |
| micro_vec[default] vle8_vl16 sky130/soc | 1.7 | 3.6 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 94.5 |
| micro_vec[default] vle8_vl32 sky130/axi | 0.9 | 1.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 97.1 |
| micro_vec[default] vle8_vl32 sky130/soc | 0.9 | 1.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 97.2 |
| micro_vec[default] vle8_vl64 sky130/axi | 0.4 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 98.5 |
| micro_vec[default] vle8_vl64 sky130/soc | 0.4 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.6 |
| micro_vec[default] vle8_vl128 sky130/axi | 0.2 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.3 |
| micro_vec[default] vle8_vl128 sky130/soc | 0.2 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.3 |
| micro_vec[default] vle8_vl256 sky130/axi | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.6 |
| micro_vec[default] vle8_vl256 sky130/soc | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.6 |
| micro_vec[default] vle8_vl512 sky130/axi | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8 |
| micro_vec[default] vle8_vl512 sky130/soc | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8 |
| micro_vec[default] vse8_vl1 sky130/axi | 12.7 | 27.4 | 0.4 | 1.6 | 0.0 | 0.0 | 0.0 | 0.5 | 1.6 | 0.0 | 55.7 |
| micro_vec[default] vse8_vl1 sky130/soc | 13.0 | 28.1 | 0.4 | 0.5 | 0.0 | 0.0 | 0.0 | 0.5 | 0.5 | 0.0 | 56.9 |
| micro_vec[default] vse8_vl8 sky130/axi | 2.6 | 5.6 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.3 | 0.0 | 91.2 |
| micro_vec[default] vse8_vl8 sky130/soc | 2.6 | 5.6 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 91.5 |
| micro_vec[default] vse8_vl64 sky130/axi | 0.4 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 |
| micro_vec[default] vse8_vl64 sky130/soc | 0.4 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 |
| micro_vec[default] vse8_vl512 sky130/axi | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 |
| micro_vec[default] vse8_vl512 sky130/soc | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 |
| micro_vec[default] vadd_e64_vl8 sky130/axi | 7.2 | 8.8 | 0.0 | 0.9 | 0.0 | 0.0 | 81.9 | 0.3 | 0.9 | 0.0 | 0.0 |
| micro_vec[default] vadd_e64_vl8 sky130/soc | 7.2 | 8.9 | 0.0 | 0.3 | 0.0 | 0.0 | 82.9 | 0.3 | 0.3 | 0.0 | 0.0 |
| micro_vec[default] vmul_e64_vl8 sky130/axi | 1.6 | 1.9 | 0.0 | 0.2 | 0.0 | 0.0 | 96.0 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_vec[default] vmul_e64_vl8 sky130/soc | 1.6 | 1.9 | 0.0 | 0.1 | 0.0 | 0.0 | 96.3 | 0.1 | 0.1 | 0.0 | 0.0 |
| micro_vec[default] vfadd_e64_vl8 sky130/axi | 2.0 | 2.6 | 0.1 | 0.3 | 0.0 | 0.0 | 94.9 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vfadd_e64_vl8 sky130/soc | 2.0 | 2.6 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vredsum_e64_vl8 sky130/axi | 6.4 | 8.2 | 0.2 | 0.8 | 0.0 | 0.0 | 84.2 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vredsum_e64_vl8 sky130/soc | 6.4 | 8.2 | 0.2 | 0.3 | 0.0 | 0.0 | 84.6 | 0.3 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 plain C sky130/axi | 23.2 | 63.6 | 7.2 | 0.0 | 0.0 | 0.0 | 0.0 | 5.9 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 plain C sky130/soc | 23.2 | 63.6 | 7.2 | 0.0 | 0.0 | 0.0 | 0.0 | 5.9 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 Zknh sky130/axi | 24.8 | 62.2 | 4.3 | 0.0 | 0.0 | 0.0 | 0.0 | 8.6 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 Zknh sky130/soc | 24.8 | 62.2 | 4.3 | 0.0 | 0.0 | 0.0 | 0.0 | 8.6 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) sky130/axi | 4.3 | 4.5 | 0.0 | 0.0 | 0.0 | 0.0 | 88.2 | 0.2 | 0.0 | 0.0 | 2.7 |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) sky130/soc | 4.3 | 4.5 | 0.0 | 0.0 | 0.0 | 0.0 | 88.2 | 0.2 | 0.0 | 0.0 | 2.7 |
| sha256chain[sdk] sha256 accel sigil_sha256_block sky130/axi | 19.7 | 53.7 | 1.6 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.0 | 15.1 | 0.0 |
| sha256chain[sdk] sha256 accel sigil_sha256_block sky130/soc | 19.7 | 53.7 | 1.6 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.0 | 15.1 | 0.0 |
| sha256chain[sdk] sha256 accel sigil_sha256 sky130/axi | 22.7 | 60.6 | 4.2 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.0 | 2.7 | 0.0 |
| sha256chain[sdk] sha256 accel sigil_sha256 sky130/soc | 22.7 | 60.6 | 4.2 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.0 | 2.7 | 0.0 |
| sha256chain[sdk] sha512 accel sigil_hash sky130/axi | 26.0 | 62.3 | 1.6 | 0.0 | 0.0 | 0.0 | 0.0 | 6.1 | 0.0 | 4.0 | 0.0 |
| sha256chain[sdk] sha512 accel sigil_hash sky130/soc | 26.0 | 62.3 | 1.6 | 0.0 | 0.0 | 0.0 | 0.0 | 6.1 | 0.0 | 4.0 | 0.0 |
| sha256chain[sdk] sha3-256 accel sigil_hash sky130/axi | 25.6 | 62.2 | 2.2 | 0.0 | 0.0 | 0.0 | 0.0 | 6.2 | 0.0 | 3.8 | 0.0 |
| sha256chain[sdk] sha3-256 accel sigil_hash sky130/soc | 25.6 | 62.2 | 2.2 | 0.0 | 0.0 | 0.0 | 0.0 | 6.2 | 0.0 | 3.8 | 0.0 |
| sha256chain_bulk[sdk] sha256 plain C sky130/axi | 23.2 | 63.5 | 7.2 | 0.0 | 0.0 | 0.0 | 0.0 | 5.6 | 0.5 | 0.0 | 0.0 |
| sha256chain_bulk[sdk] sha256 plain C sky130/soc | 23.2 | 63.7 | 7.2 | 0.0 | 0.0 | 0.0 | 0.0 | 5.6 | 0.2 | 0.0 | 0.0 |
| sha256chain_bulk[sdk] sha256 Zknh sky130/axi | 24.9 | 61.9 | 4.1 | 0.0 | 0.0 | 0.0 | 0.0 | 8.4 | 0.8 | 0.0 | 0.0 |
| sha256chain_bulk[sdk] sha256 Zknh sky130/soc | 25.0 | 62.2 | 4.1 | 0.0 | 0.0 | 0.0 | 0.0 | 8.5 | 0.3 | 0.0 | 0.0 |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) sky130/axi | 4.1 | 4.3 | 0.0 | 0.0 | 0.0 | 0.0 | 86.5 | 0.2 | 0.0 | 0.0 | 4.8 |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) sky130/soc | 4.1 | 4.4 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.2 | 0.0 | 0.0 | 3.9 |
| sha256chain_bulk[sdk] sha512 accel sigil_hash sky130/axi | 16.5 | 45.3 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 12.2 | 9.6 | 16.3 | 0.0 |
| sha256chain_bulk[sdk] sha512 accel sigil_hash sky130/soc | 17.6 | 48.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 13.1 | 3.3 | 17.4 | 0.0 |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash sky130/axi | 16.5 | 45.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.3 | 9.6 | 16.4 | 0.0 |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash sky130/soc | 17.6 | 48.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 13.1 | 3.3 | 17.5 | 0.0 |

Columns: `retire` = retire (base); `fetch_lat` = fetch: I$ hit latency / issue gap; `fetch_straddle` = fetch: 32-bit instr straddles a word; `fetch_miss` = fetch: I$ miss; `muldiv` = EX: M unit (mul/div); `fpu` = EX: FPU; `vec` = EX: vector unit; `dc_lat` = MEM: D$ hit latency; `dc_miss` = MEM: D$ miss; `io` = MEM: uncached device access; `vls` = MEM: vector load/store.

## Events

| Run | alu % | load % | store % | branch % | jal % | jalr % | mul % | div % | fp % | vec % | vls % | vset % | csr % | fence % | rvc % | taken % | redir/ki | squashed | I$ acc/i | I$ miss (/ki) | D$ ld / st | D$ miss (%) | D$ wb | D unc | bus if/df/wb/unc | bus % | bus wait % | M % | FPU % | vec % | vls % | traps |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| coremark[scalar] sky130/axi | 47.9 | 20.6 | 5.4 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.4 | 58.6 | 141.9 | 0 | 1.277 | 1,187 (0.226) | 1,082,027 / 283,065 | 18 (0.0) | 1 | 0 | 1187/18/1/0 | 0.2 | 0.1 | 1.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| coremark[scalar] sky130/soc | 47.9 | 20.6 | 5.4 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.4 | 58.6 | 141.9 | 0 | 1.277 | 1,187 (0.226) | 1,082,027 / 283,065 | 18 (0.0) | 1 | 0 | 1187/18/1/0 | 0.0 | 0.0 | 1.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| coremark[sdk] sky130/axi | 47.9 | 20.6 | 5.3 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 51.2 | 58.6 | 142.0 | 0 | 1.298 | 1,388 (0.265) | 1,081,947 / 282,988 | 17 (0.0) | 0 | 0 | 1388/17/0/0 | 0.2 | 0.2 | 1.6 | 0.0 | 0.1 | 0.2 | 0 / 0 |
| coremark[sdk] sky130/soc | 47.9 | 20.6 | 5.3 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 51.2 | 58.6 | 142.0 | 0 | 1.298 | 1,388 (0.265) | 1,081,947 / 282,988 | 17 (0.0) | 0 | 0 | 1388/17/0/0 | 0.1 | 0.0 | 1.6 | 0.0 | 0.1 | 0.2 | 0 / 0 |
| coremark[validation] sky130/axi | 47.8 | 20.8 | 5.4 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.5 | 58.5 | 141.7 | 0 | 1.277 | 1,227 (0.234) | 1,090,995 / 281,121 | 18 (0.0) | 1 | 0 | 1227/18/1/0 | 0.2 | 0.1 | 1.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| coremark[validation] sky130/soc | 47.8 | 20.8 | 5.4 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.5 | 58.5 | 141.7 | 0 | 1.277 | 1,227 (0.234) | 1,090,995 / 281,121 | 18 (0.0) | 1 | 0 | 1227/18/1/0 | 0.0 | 0.0 | 1.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| dhrystone[scalar] sky130/axi | 39.2 | 22.8 | 14.9 | 16.6 | 3.5 | 2.9 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 73.7 | 66.3 | 173.7 | 0 | 1.376 | 13 (0.013) | 236,002 / 154,004 | 8,004 (2.1) | 6,004 | 0 | 13/8004/6004/0 | 9.3 | 7.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| dhrystone[scalar] sky130/soc | 39.2 | 22.8 | 14.9 | 16.6 | 3.5 | 2.9 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 73.7 | 66.3 | 173.7 | 0 | 1.376 | 13 (0.013) | 236,002 / 154,004 | 8,004 (2.1) | 6,004 | 0 | 13/8004/6004/0 | 2.4 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| dhrystone[sdk] sky130/axi | 40.5 | 21.7 | 13.5 | 17.0 | 3.5 | 2.9 | 0.0 | 0.2 | 0.0 | 0.0 | 0.4 | 0.2 | 0.0 | 0.0 | 73.2 | 65.5 | 176.1 | 0 | 1.272 | 12 (0.012) | 334,002 / 250,004 | 12,002 (2.1) | 10,002 | 0 | 12/12002/10002/0 | 12.6 | 9.6 | 0.1 | 0.0 | 0.0 | 15.3 | 0 / 0 |
| dhrystone[sdk] sky130/soc | 40.5 | 21.7 | 13.5 | 17.0 | 3.5 | 2.9 | 0.0 | 0.2 | 0.0 | 0.0 | 0.4 | 0.2 | 0.0 | 0.0 | 73.2 | 65.5 | 176.1 | 0 | 1.272 | 12 (0.012) | 334,002 / 250,004 | 12,002 (2.1) | 10,002 | 0 | 12/12002/10002/0 | 3.3 | 0.0 | 0.1 | 0.0 | 0.0 | 17.0 | 0 / 0 |
| kernels[autovec] vadd_i32 C sky130/axi | 40.8 | 0.1 | 0.2 | 10.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 9.6 | 28.9 | 9.6 | 0.3 | 0.0 | 21.1 | 95.1 | 99.1 | 0 | 1.593 | 1 (0.377) | 8,194 / 4,100 | 712 (5.8) | 260 | 0 | 1/712/260/0 | 31.7 | 23.8 | 0.0 | 0.0 | 4.8 | 84.5 | 0 / 0 |
| kernels[autovec] vadd_i32 C sky130/soc | 40.8 | 0.1 | 0.2 | 10.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 9.6 | 28.9 | 9.6 | 0.3 | 0.0 | 21.1 | 95.1 | 99.1 | 0 | 1.593 | 1 (0.377) | 8,194 / 4,100 | 712 (5.8) | 260 | 0 | 1/712/260/0 | 10.4 | 0.0 | 0.0 | 0.0 | 6.4 | 79.8 | 0 / 0 |
| kernels[autovec] vadd_i32 RVV sky130/axi | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 0 | 1.384 | 1 (2.688) | 8,194 / 4,100 | 743 (6.0) | 272 | 0 | 1/743/272/0 | 36.5 | 27.4 | 0.0 | 0.0 | 4.2 | 94.1 | 0 / 0 |
| kernels[autovec] vadd_i32 RVV sky130/soc | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 0 | 1.384 | 1 (2.688) | 8,194 / 4,100 | 743 (6.0) | 272 | 0 | 1/743/272/0 | 12.5 | 0.0 | 0.0 | 0.0 | 5.8 | 92.1 | 0 / 0 |
| kernels[autovec] vadd_i64 C sky130/axi | 40.6 | 0.1 | 0.2 | 10.3 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 9.7 | 29.0 | 9.7 | 0.3 | 0.0 | 21.0 | 93.8 | 99.2 | 0 | 1.398 | 2 (0.754) | 4,098 / 2,052 | 712 (11.6) | 260 | 0 | 2/712/260/0 | 43.6 | 32.7 | 0.0 | 0.0 | 4.1 | 83.1 | 0 / 0 |
| kernels[autovec] vadd_i64 C sky130/soc | 40.6 | 0.1 | 0.2 | 10.3 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 9.7 | 29.0 | 9.7 | 0.3 | 0.0 | 21.0 | 93.8 | 99.2 | 0 | 1.398 | 2 (0.754) | 4,098 / 2,052 | 712 (11.6) | 260 | 0 | 2/712/260/0 | 16.1 | 0.0 | 0.0 | 0.0 | 6.1 | 75.1 | 0 / 0 |
| kernels[autovec] vadd_i64 RVV sky130/axi | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 0 | 1.384 | 1 (2.688) | 4,098 / 2,052 | 743 (12.1) | 272 | 0 | 1/743/272/0 | 51.0 | 38.3 | 0.0 | 0.0 | 3.1 | 94.6 | 0 / 0 |
| kernels[autovec] vadd_i64 RVV sky130/soc | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 0 | 1.384 | 1 (2.688) | 4,098 / 2,052 | 743 (12.1) | 272 | 0 | 1/743/272/0 | 20.6 | 0.0 | 0.0 | 0.0 | 5.0 | 91.6 | 0 / 0 |
| kernels[autovec] daxpy C sky130/axi | 40.2 | 0.1 | 0.2 | 10.2 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 9.8 | 28.9 | 9.8 | 0.3 | 0.0 | 21.0 | 93.8 | 99.0 | 0 | 1.395 | 1 (0.377) | 4,098 / 2,052 | 515 (8.4) | 255 | 0 | 1/515/255/0 | 32.3 | 24.3 | 0.0 | 0.0 | 20.2 | 68.1 | 0 / 0 |
| kernels[autovec] daxpy C sky130/soc | 40.2 | 0.1 | 0.2 | 10.2 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 9.8 | 28.9 | 9.8 | 0.3 | 0.0 | 21.0 | 93.8 | 99.0 | 0 | 1.395 | 1 (0.377) | 4,098 / 2,052 | 515 (8.4) | 255 | 0 | 1/515/255/0 | 10.5 | 0.0 | 0.0 | 0.0 | 26.7 | 57.9 | 0 / 0 |
| kernels[autovec] daxpy RVV sky130/axi | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 0 | 1.441 | 1 (2.941) | 4,098 / 2,052 | 515 (8.4) | 240 | 0 | 1/515/240/0 | 36.3 | 27.3 | 0.0 | 0.0 | 21.7 | 76.3 | 0 / 0 |
| kernels[autovec] daxpy RVV sky130/soc | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 0 | 1.441 | 1 (2.941) | 4,098 / 2,052 | 515 (8.4) | 240 | 0 | 1/515/240/0 | 12.3 | 0.0 | 0.0 | 0.0 | 29.9 | 67.6 | 0 / 0 |
| kernels[autovec] saxpy C sky130/axi | 40.3 | 0.1 | 0.2 | 10.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 9.8 | 29.0 | 9.8 | 0.3 | 0.0 | 21.2 | 95.1 | 99.2 | 0 | 1.592 | 2 (0.754) | 8,194 / 4,100 | 515 (4.2) | 255 | 0 | 2/515/255/0 | 21.4 | 16.1 | 0.0 | 0.0 | 25.8 | 65.2 | 0 / 0 |
| kernels[autovec] saxpy C sky130/soc | 40.3 | 0.1 | 0.2 | 10.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 9.8 | 29.0 | 9.8 | 0.3 | 0.0 | 21.2 | 95.1 | 99.2 | 0 | 1.592 | 2 (0.754) | 8,194 / 4,100 | 515 (4.2) | 255 | 0 | 2/515/255/0 | 6.3 | 0.0 | 0.0 | 0.0 | 30.8 | 58.6 | 0 / 0 |
| kernels[autovec] saxpy RVV sky130/axi | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 0 | 1.441 | 1 (2.941) | 8,194 / 4,100 | 515 (4.2) | 240 | 0 | 1/515/240/0 | 23.2 | 17.5 | 0.0 | 0.0 | 27.6 | 71.1 | 0 / 0 |
| kernels[autovec] saxpy RVV sky130/soc | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 0 | 1.441 | 1 (2.941) | 8,194 / 4,100 | 515 (4.2) | 240 | 0 | 1/515/240/0 | 6.9 | 0.0 | 0.0 | 0.0 | 33.5 | 65.1 | 0 / 0 |
| kernels[autovec] ddot C sky130/axi | 23.3 | 0.1 | 0.2 | 7.8 | 0.1 | 0.1 | 0.0 | 0.0 | 0.1 | 30.3 | 15.1 | 22.7 | 0.1 | 0.0 | 16.2 | 96.6 | 77.7 | 0 | 1.534 | 1 (0.296) | 4,098 / 8 | 519 (12.6) | 5 | 0 | 1/519/5/0 | 22.1 | 16.3 | 0.0 | 0.0 | 37.6 | 44.6 | 0 / 0 |
| kernels[autovec] ddot C sky130/soc | 23.3 | 0.1 | 0.2 | 7.8 | 0.1 | 0.1 | 0.0 | 0.0 | 0.1 | 30.3 | 15.1 | 22.7 | 0.1 | 0.0 | 16.2 | 96.6 | 77.7 | 0 | 1.534 | 1 (0.296) | 4,098 / 8 | 519 (12.6) | 5 | 0 | 1/519/5/0 | 7.0 | 0.0 | 0.0 | 0.0 | 45.0 | 34.1 | 0 / 0 |
| kernels[autovec] ddot RVV sky130/axi | 35.2 | 0.6 | 2.4 | 12.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 14.5 | 19.3 | 12.0 | 1.5 | 0.0 | 30.4 | 77.5 | 117.5 | 0 | 1.479 | 1 (3.012) | 4,098 / 8 | 519 (12.6) | 5 | 0 | 1/519/5/0 | 32.1 | 23.6 | 0.0 | 0.0 | 33.1 | 63.9 | 0 / 0 |
| kernels[autovec] ddot RVV sky130/soc | 35.2 | 0.6 | 2.4 | 12.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 14.5 | 19.3 | 12.0 | 1.5 | 0.0 | 30.4 | 77.5 | 117.5 | 0 | 1.479 | 1 (3.012) | 4,098 / 8 | 519 (12.6) | 5 | 0 | 1/519/5/0 | 11.1 | 0.0 | 0.0 | 0.0 | 43.3 | 53.3 | 0 / 0 |
| kernels[autovec] idot_i32 C sky130/axi | 37.3 | 0.0 | 0.2 | 12.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 12.7 | 24.5 | 12.5 | 0.1 | 0.0 | 25.4 | 98.3 | 124.4 | 0 | 1.500 | 1 (0.240) | 8,194 / 8 | 518 (6.3) | 5 | 0 | 1/518/5/0 | 18.3 | 13.4 | 0.0 | 0.0 | 27.9 | 54.2 | 0 / 0 |
| kernels[autovec] idot_i32 C sky130/soc | 37.3 | 0.0 | 0.2 | 12.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 12.7 | 24.5 | 12.5 | 0.1 | 0.0 | 25.4 | 98.3 | 124.4 | 0 | 1.500 | 1 (0.240) | 8,194 / 8 | 518 (6.3) | 5 | 0 | 1/518/5/0 | 5.6 | 0.0 | 0.0 | 0.0 | 32.2 | 47.3 | 0 / 0 |
| kernels[autovec] idot_i32 RVV sky130/axi | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 0 | 1.486 | 1 (1.701) | 8,194 / 8 | 518 (6.3) | 5 | 0 | 1/518/5/0 | 22.2 | 16.4 | 0.0 | 0.0 | 31.8 | 64.9 | 0 / 0 |
| kernels[autovec] idot_i32 RVV sky130/soc | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 0 | 1.486 | 1 (1.701) | 8,194 / 8 | 518 (6.3) | 5 | 0 | 1/518/5/0 | 7.0 | 0.0 | 0.0 | 0.0 | 38.0 | 58.3 | 0 / 0 |
| kernels[autovec] memcpy C sky130/axi | 40.3 | 19.8 | 19.8 | 19.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 | 99.2 | 198.8 | 0 | 1.596 | 1 (0.097) | 2,050 / 2,052 | 454 (11.1) | 258 | 0 | 1/454/258/0 | 29.9 | 22.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] memcpy C sky130/soc | 40.3 | 19.8 | 19.8 | 19.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 | 99.2 | 198.8 | 0 | 1.596 | 1 (0.097) | 2,050 / 2,052 | 454 (11.1) | 258 | 0 | 1/454/258/0 | 9.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] memcpy RVV sky130/axi | 43.8 | 0.7 | 1.4 | 14.5 | 1.4 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 23.2 | 11.6 | 1.8 | 0.0 | 36.6 | 77.5 | 141.3 | 0 | 1.496 | 1 (3.623) | 2,050 / 2,052 | 487 (11.9) | 258 | 0 | 1/487/258/0 | 53.6 | 40.5 | 0.0 | 0.0 | 0.0 | 97.2 | 0 / 0 |
| kernels[autovec] memcpy RVV sky130/soc | 43.8 | 0.7 | 1.4 | 14.5 | 1.4 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 23.2 | 11.6 | 1.8 | 0.0 | 36.6 | 77.5 | 141.3 | 0 | 1.496 | 1 (3.623) | 2,050 / 2,052 | 487 (11.9) | 258 | 0 | 1/487/258/0 | 22.1 | 0.0 | 0.0 | 0.0 | 0.0 | 95.8 | 0 / 0 |
| kernels[autovec] memcpy RVV-e8 sky130/axi | 43.0 | 0.7 | 1.5 | 14.7 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.5 | 11.8 | 1.8 | 0.0 | 59.2 | 77.5 | 143.4 | 0 | 1.504 | 1 (3.676) | 16,386 / 16,388 | 473 (1.4) | 258 | 0 | 1/473/258/0 | 15.0 | 11.3 | 0.0 | 0.0 | 0.0 | 99.2 | 0 / 0 |
| kernels[autovec] memcpy RVV-e8 sky130/soc | 43.0 | 0.7 | 1.5 | 14.7 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.5 | 11.8 | 1.8 | 0.0 | 59.2 | 77.5 | 143.4 | 0 | 1.504 | 1 (3.676) | 16,386 / 16,388 | 473 (1.4) | 258 | 0 | 1/473/258/0 | 4.1 | 0.0 | 0.0 | 0.0 | 0.0 | 99.2 | 0 / 0 |
| kernels[autovec] memset C sky130/axi | 33.9 | 0.0 | 32.8 | 33.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 33.5 | 99.2 | 328.7 | 0 | 1.659 | 1 (0.160) | 2 / 2,052 | 4 (0.2) | 4 | 0 | 1/4/4/0 | 0.9 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] memset C sky130/soc | 33.9 | 0.0 | 32.8 | 33.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 33.5 | 99.2 | 328.7 | 0 | 1.659 | 1 (0.160) | 2 / 2,052 | 4 (0.2) | 4 | 0 | 1/4/4/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] memset RVV sky130/axi | 43.8 | 0.8 | 1.7 | 16.7 | 1.7 | 1.7 | 1.7 | 0.0 | 0.0 | 1.7 | 13.3 | 15.0 | 2.1 | 0.0 | 45.4 | 77.5 | 162.5 | 0 | 1.317 | 1 (4.167) | 2 / 2,052 | 4 (0.2) | 4 | 0 | 1/4/4/0 | 2.8 | 2.2 | 0.1 | 0.0 | 2.3 | 87.3 | 0 / 0 |
| kernels[autovec] memset RVV sky130/soc | 43.8 | 0.8 | 1.7 | 16.7 | 1.7 | 1.7 | 1.7 | 0.0 | 0.0 | 1.7 | 13.3 | 15.0 | 2.1 | 0.0 | 45.4 | 77.5 | 162.5 | 0 | 1.317 | 1 (4.167) | 2 / 2,052 | 4 (0.2) | 4 | 0 | 1/4/4/0 | 0.7 | 0.0 | 0.1 | 0.0 | 2.4 | 88.7 | 0 / 0 |
| kernels[autovec] memset RVV-e8 sky130/axi | 39.4 | 0.9 | 1.9 | 18.5 | 1.9 | 1.9 | 0.0 | 0.0 | 0.0 | 1.9 | 14.8 | 16.7 | 2.3 | 0.0 | 59.7 | 77.5 | 180.6 | 0 | 1.560 | 1 (4.630) | 2 / 16,388 | 4 (0.0) | 4 | 0 | 1/4/4/0 | 0.4 | 0.3 | 0.0 | 0.0 | 2.4 | 96.1 | 0 / 0 |
| kernels[autovec] memset RVV-e8 sky130/soc | 39.4 | 0.9 | 1.9 | 18.5 | 1.9 | 1.9 | 0.0 | 0.0 | 0.0 | 1.9 | 14.8 | 16.7 | 2.3 | 0.0 | 59.7 | 77.5 | 180.6 | 0 | 1.560 | 1 (4.630) | 2 / 16,388 | 4 (0.0) | 4 | 0 | 1/4/4/0 | 0.1 | 0.0 | 0.0 | 0.0 | 2.4 | 96.3 | 0 / 0 |
| kernels[autovec] dgemm C sky130/axi | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.0 | 93.9 | 158.4 | 0 | 1.174 | 1 (0.001) | 262,146 / 4,100 | 137,875 (51.8) | 575 | 0 | 1/137875/575/0 | 51.0 | 37.5 | 0.0 | 8.5 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] dgemm C sky130/soc | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.0 | 93.9 | 158.4 | 0 | 1.174 | 1 (0.001) | 262,146 / 4,100 | 137,875 (51.8) | 575 | 0 | 1/137875/575/0 | 21.6 | 0.0 | 0.0 | 13.6 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] dgemm RVV sky130/axi | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 33.3 | 93.9 | 153.7 | 0 | 1.192 | 1 (0.037) | 135,170 / 4,100 | 17,635 (12.7) | 573 | 0 | 1/17635/573/0 | 26.0 | 19.2 | 0.0 | 0.0 | 44.7 | 50.2 | 0 / 0 |
| kernels[autovec] dgemm RVV sky130/soc | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 33.3 | 93.9 | 153.7 | 0 | 1.192 | 1 (0.037) | 135,170 / 4,100 | 17,635 (12.7) | 573 | 0 | 1/17635/573/0 | 8.4 | 0.0 | 0.0 | 0.0 | 55.3 | 39.3 | 0 / 0 |
| kernels[autovec] sgemm C sky130/axi | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 18.8 | 93.9 | 158.4 | 0 | 1.480 | 1 (0.001) | 262,146 / 4,100 | 16,949 (6.4) | 4,159 | 0 | 1/16949/4159/0 | 13.2 | 9.8 | 0.0 | 13.8 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] sgemm C sky130/soc | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 18.8 | 93.9 | 158.4 | 0 | 1.480 | 1 (0.001) | 262,146 / 4,100 | 16,949 (6.4) | 4,159 | 0 | 1/16949/4159/0 | 3.7 | 0.0 | 0.0 | 15.3 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] sgemm RVV sky130/axi | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 17.9 | 93.9 | 153.7 | 0 | 1.648 | 1 (0.037) | 135,170 / 4,100 | 1,326 (1.0) | 319 | 0 | 1/1326/319/0 | 3.2 | 2.4 | 0.0 | 0.0 | 59.0 | 33.0 | 0 / 0 |
| kernels[autovec] sgemm RVV sky130/soc | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 17.9 | 93.9 | 153.7 | 0 | 1.648 | 1 (0.037) | 135,170 / 4,100 | 1,326 (1.0) | 319 | 0 | 1/1326/319/0 | 0.8 | 0.0 | 0.0 | 0.0 | 60.4 | 31.9 | 0 / 0 |
| kernels[autovec] fir_f32 C sky130/axi | 38.1 | 0.0 | 4.8 | 9.5 | 0.0 | 0.0 | 0.0 | 0.0 | 4.8 | 19.0 | 9.5 | 14.3 | 0.0 | 0.0 | 33.4 | 49.9 | 47.7 | 0 | 1.428 | 1 (0.012) | 131,074 / 4,100 | 829 (0.6) | 320 | 0 | 1/829/320/0 | 2.3 | 1.7 | 0.0 | 0.0 | 48.6 | 31.4 | 0 / 0 |
| kernels[autovec] fir_f32 C sky130/soc | 38.1 | 0.0 | 4.8 | 9.5 | 0.0 | 0.0 | 0.0 | 0.0 | 4.8 | 19.0 | 9.5 | 14.3 | 0.0 | 0.0 | 33.4 | 49.9 | 47.7 | 0 | 1.428 | 1 (0.012) | 131,074 / 4,100 | 829 (0.6) | 320 | 0 | 1/829/320/0 | 0.6 | 0.0 | 0.0 | 0.0 | 49.4 | 30.6 | 0 / 0 |
| kernels[autovec] fir_f32 RVV sky130/axi | 35.9 | 14.7 | 0.1 | 16.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 15.6 | 15.6 | 0.9 | 0.1 | 0.0 | 33.4 | 87.5 | 148.8 | 0 | 1.161 | 1 (0.287) | 66,050 / 4,100 | 627 (0.9) | 265 | 0 | 1/627/265/0 | 3.8 | 2.8 | 0.0 | 0.0 | 61.5 | 36.7 | 0 / 0 |
| kernels[autovec] fir_f32 RVV sky130/soc | 35.9 | 14.7 | 0.1 | 16.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 15.6 | 15.6 | 0.9 | 0.1 | 0.0 | 33.4 | 87.5 | 148.8 | 0 | 1.161 | 1 (0.287) | 66,050 / 4,100 | 627 (0.9) | 265 | 0 | 1/627/265/0 | 1.0 | 0.0 | 0.0 | 0.0 | 63.3 | 35.1 | 0 / 0 |
| kernels[autovec] mac_i8 C sky130/axi | 27.3 | 0.0 | 0.1 | 9.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 27.2 | 18.1 | 18.1 | 0.0 | 0.0 | 36.5 | 99.1 | 90.9 | 0 | 1.364 | 1 (0.088) | 32,770 / 8 | 519 (1.6) | 5 | 0 | 1/519/5/0 | 5.7 | 4.2 | 0.0 | 0.0 | 38.6 | 48.2 | 0 / 0 |
| kernels[autovec] mac_i8 C sky130/soc | 27.3 | 0.0 | 0.1 | 9.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 27.2 | 18.1 | 18.1 | 0.0 | 0.0 | 36.5 | 99.1 | 90.9 | 0 | 1.364 | 1 (0.088) | 32,770 / 8 | 519 (1.6) | 5 | 0 | 1/519/5/0 | 1.6 | 0.0 | 0.0 | 0.0 | 40.3 | 46.0 | 0 / 0 |
| kernels[autovec] mac_i8 RVV sky130/axi | 30.1 | 0.3 | 1.1 | 10.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 19.2 | 18.1 | 19.2 | 0.7 | 0.0 | 41.9 | 87.5 | 100.3 | 0 | 1.390 | 1 (1.412) | 32,770 / 8 | 519 (1.6) | 5 | 0 | 1/519/5/0 | 7.1 | 5.2 | 0.0 | 0.0 | 39.3 | 59.6 | 0 / 0 |
| kernels[autovec] mac_i8 RVV sky130/soc | 30.1 | 0.3 | 1.1 | 10.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 19.2 | 18.1 | 19.2 | 0.7 | 0.0 | 41.9 | 87.5 | 100.3 | 0 | 1.390 | 1 (1.412) | 32,770 / 8 | 519 (1.6) | 5 | 0 | 1/519/5/0 | 2.0 | 0.0 | 0.0 | 0.0 | 41.4 | 57.4 | 0 / 0 |
| kernels[autovec] mac_i16 C sky130/axi | 37.3 | 0.0 | 0.2 | 12.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 12.7 | 24.5 | 12.5 | 0.1 | 0.0 | 25.4 | 98.3 | 124.4 | 0 | 1.500 | 1 (0.240) | 16,386 / 8 | 518 (3.2) | 5 | 0 | 1/518/5/0 | 12.1 | 8.9 | 0.0 | 0.0 | 29.8 | 58.3 | 0 / 0 |
| kernels[autovec] mac_i16 C sky130/soc | 37.3 | 0.0 | 0.2 | 12.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 12.7 | 24.5 | 12.5 | 0.1 | 0.0 | 25.4 | 98.3 | 124.4 | 0 | 1.500 | 1 (0.240) | 16,386 / 8 | 518 (3.2) | 5 | 0 | 1/518/5/0 | 3.5 | 0.0 | 0.0 | 0.0 | 32.7 | 54.4 | 0 / 0 |
| kernels[autovec] mac_i16 RVV sky130/axi | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 0 | 1.486 | 1 (1.701) | 16,386 / 8 | 518 (3.2) | 5 | 0 | 1/518/5/0 | 13.7 | 10.1 | 0.0 | 0.0 | 32.6 | 65.3 | 0 / 0 |
| kernels[autovec] mac_i16 RVV sky130/soc | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 0 | 1.486 | 1 (1.701) | 16,386 / 8 | 518 (3.2) | 5 | 0 | 1/518/5/0 | 4.0 | 0.0 | 0.0 | 0.0 | 36.3 | 61.6 | 0 / 0 |
| kernels[scalar] vadd_i32 C sky130/axi | 50.0 | 25.0 | 12.5 | 12.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.5 | 99.8 | 125.0 | 0 | 1.125 | 1 (0.030) | 8,194 / 4,100 | 712 (5.8) | 260 | 0 | 1/712/260/0 | 20.1 | 15.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] vadd_i32 C sky130/soc | 50.0 | 25.0 | 12.5 | 12.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.5 | 99.8 | 125.0 | 0 | 1.125 | 1 (0.030) | 8,194 / 4,100 | 712 (5.8) | 260 | 0 | 1/712/260/0 | 5.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] vadd_i32 RVV sky130/axi | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 0 | 1.384 | 1 (2.688) | 8,194 / 4,100 | 743 (6.0) | 272 | 0 | 1/743/272/0 | 36.5 | 27.4 | 0.0 | 0.0 | 4.2 | 94.1 | 0 / 0 |
| kernels[scalar] vadd_i32 RVV sky130/soc | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 0 | 1.384 | 1 (2.688) | 8,194 / 4,100 | 743 (6.0) | 272 | 0 | 1/743/272/0 | 12.5 | 0.0 | 0.0 | 0.0 | 5.8 | 92.1 | 0 / 0 |
| kernels[scalar] vadd_i64 C sky130/axi | 50.0 | 24.9 | 12.5 | 12.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 99.6 | 125.0 | 0 | 1.126 | 2 (0.122) | 4,098 / 2,052 | 712 (11.6) | 260 | 0 | 2/712/260/0 | 32.7 | 24.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] vadd_i64 C sky130/soc | 50.0 | 24.9 | 12.5 | 12.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 99.6 | 125.0 | 0 | 1.126 | 2 (0.122) | 4,098 / 2,052 | 712 (11.6) | 260 | 0 | 2/712/260/0 | 10.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] vadd_i64 RVV sky130/axi | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 0 | 1.384 | 1 (2.688) | 4,098 / 2,052 | 743 (12.1) | 272 | 0 | 1/743/272/0 | 51.0 | 38.3 | 0.0 | 0.0 | 3.1 | 94.6 | 0 / 0 |
| kernels[scalar] vadd_i64 RVV sky130/soc | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 0 | 1.384 | 1 (2.688) | 4,098 / 2,052 | 743 (12.1) | 272 | 0 | 1/743/272/0 | 20.6 | 0.0 | 0.0 | 0.0 | 5.0 | 91.6 | 0 / 0 |
| kernels[scalar] daxpy C sky130/axi | 28.6 | 28.5 | 14.3 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.1 | 99.6 | 142.8 | 0 | 1.571 | 2 (0.139) | 4,098 / 2,052 | 515 (8.4) | 255 | 0 | 2/515/255/0 | 23.0 | 17.4 | 0.0 | 10.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] daxpy C sky130/soc | 28.6 | 28.5 | 14.3 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.1 | 99.6 | 142.8 | 0 | 1.571 | 2 (0.139) | 4,098 / 2,052 | 515 (8.4) | 255 | 0 | 2/515/255/0 | 6.9 | 0.0 | 0.0 | 12.1 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] daxpy RVV sky130/axi | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 0 | 1.441 | 1 (2.941) | 4,098 / 2,052 | 515 (8.4) | 240 | 0 | 1/515/240/0 | 36.3 | 27.3 | 0.0 | 0.0 | 21.7 | 76.3 | 0 / 0 |
| kernels[scalar] daxpy RVV sky130/soc | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 0 | 1.441 | 1 (2.941) | 4,098 / 2,052 | 515 (8.4) | 240 | 0 | 1/515/240/0 | 12.3 | 0.0 | 0.0 | 0.0 | 29.9 | 67.6 | 0 / 0 |
| kernels[scalar] saxpy C sky130/axi | 28.6 | 28.5 | 14.3 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 28.6 | 99.8 | 142.8 | 0 | 1.856 | 1 (0.035) | 8,194 / 4,100 | 515 (4.2) | 255 | 0 | 1/515/255/0 | 11.9 | 9.0 | 0.0 | 10.4 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] saxpy C sky130/soc | 28.6 | 28.5 | 14.3 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 28.6 | 99.8 | 142.8 | 0 | 1.856 | 1 (0.035) | 8,194 / 4,100 | 515 (4.2) | 255 | 0 | 1/515/255/0 | 3.2 | 0.0 | 0.0 | 11.4 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] saxpy RVV sky130/axi | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 0 | 1.441 | 1 (2.941) | 8,194 / 4,100 | 515 (4.2) | 240 | 0 | 1/515/240/0 | 23.2 | 17.5 | 0.0 | 0.0 | 27.6 | 71.1 | 0 / 0 |
| kernels[scalar] saxpy RVV sky130/soc | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 0 | 1.441 | 1 (2.941) | 8,194 / 4,100 | 515 (4.2) | 240 | 0 | 1/515/240/0 | 6.9 | 0.0 | 0.0 | 0.0 | 33.5 | 65.1 | 0 / 0 |
| kernels[scalar] ddot C sky130/axi | 33.4 | 33.2 | 0.1 | 16.7 | 0.0 | 0.0 | 0.0 | 0.0 | 16.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 66.6 | 99.6 | 166.4 | 0 | 1.499 | 1 (0.081) | 4,098 / 8 | 519 (12.6) | 5 | 0 | 1/519/5/0 | 19.1 | 14.1 | 0.0 | 13.1 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] ddot C sky130/soc | 33.4 | 33.2 | 0.1 | 16.7 | 0.0 | 0.0 | 0.0 | 0.0 | 16.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 66.6 | 99.6 | 166.4 | 0 | 1.499 | 1 (0.081) | 4,098 / 8 | 519 (12.6) | 5 | 0 | 1/519/5/0 | 5.9 | 0.0 | 0.0 | 15.3 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] ddot RVV sky130/axi | 35.2 | 0.6 | 2.4 | 12.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 14.5 | 19.3 | 12.0 | 1.5 | 0.0 | 30.4 | 77.5 | 117.5 | 0 | 1.479 | 1 (3.012) | 4,098 / 8 | 519 (12.6) | 5 | 0 | 1/519/5/0 | 32.1 | 23.6 | 0.0 | 0.0 | 33.1 | 63.9 | 0 / 0 |
| kernels[scalar] ddot RVV sky130/soc | 35.2 | 0.6 | 2.4 | 12.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 14.5 | 19.3 | 12.0 | 1.5 | 0.0 | 30.4 | 77.5 | 117.5 | 0 | 1.479 | 1 (3.012) | 4,098 / 8 | 519 (12.6) | 5 | 0 | 1/519/5/0 | 11.1 | 0.0 | 0.0 | 0.0 | 43.3 | 53.3 | 0 / 0 |
| kernels[scalar] idot_i32 C sky130/axi | 42.9 | 28.5 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 85.7 | 99.8 | 142.8 | 0 | 1.143 | 1 (0.035) | 8,194 / 8 | 518 (6.3) | 5 | 0 | 1/518/5/0 | 12.9 | 9.5 | 5.9 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] idot_i32 C sky130/soc | 42.9 | 28.5 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 85.7 | 99.8 | 142.8 | 0 | 1.143 | 1 (0.035) | 8,194 / 8 | 518 (6.3) | 5 | 0 | 1/518/5/0 | 3.8 | 0.0 | 6.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] idot_i32 RVV sky130/axi | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 0 | 1.486 | 1 (1.701) | 8,194 / 8 | 518 (6.3) | 5 | 0 | 1/518/5/0 | 22.2 | 16.4 | 0.0 | 0.0 | 31.8 | 64.9 | 0 / 0 |
| kernels[scalar] idot_i32 RVV sky130/soc | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 0 | 1.486 | 1 (1.701) | 8,194 / 8 | 518 (6.3) | 5 | 0 | 1/518/5/0 | 7.0 | 0.0 | 0.0 | 0.0 | 38.0 | 58.3 | 0 / 0 |
| kernels[scalar] memcpy C sky130/axi | 40.3 | 19.8 | 19.8 | 19.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 | 99.2 | 198.8 | 0 | 1.596 | 1 (0.097) | 2,050 / 2,052 | 454 (11.1) | 258 | 0 | 1/454/258/0 | 29.9 | 22.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] memcpy C sky130/soc | 40.3 | 19.8 | 19.8 | 19.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 | 99.2 | 198.8 | 0 | 1.596 | 1 (0.097) | 2,050 / 2,052 | 454 (11.1) | 258 | 0 | 1/454/258/0 | 9.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] memcpy RVV sky130/axi | 43.8 | 0.7 | 1.4 | 14.5 | 1.4 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 23.2 | 11.6 | 1.8 | 0.0 | 36.6 | 77.5 | 141.3 | 0 | 1.496 | 1 (3.623) | 2,050 / 2,052 | 487 (11.9) | 258 | 0 | 1/487/258/0 | 53.6 | 40.5 | 0.0 | 0.0 | 0.0 | 97.2 | 0 / 0 |
| kernels[scalar] memcpy RVV sky130/soc | 43.8 | 0.7 | 1.4 | 14.5 | 1.4 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 23.2 | 11.6 | 1.8 | 0.0 | 36.6 | 77.5 | 141.3 | 0 | 1.496 | 1 (3.623) | 2,050 / 2,052 | 487 (11.9) | 258 | 0 | 1/487/258/0 | 22.1 | 0.0 | 0.0 | 0.0 | 0.0 | 95.8 | 0 / 0 |
| kernels[scalar] memcpy RVV-e8 sky130/axi | 43.0 | 0.7 | 1.5 | 14.7 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.5 | 11.8 | 1.8 | 0.0 | 59.2 | 77.5 | 143.4 | 0 | 1.504 | 1 (3.676) | 16,386 / 16,388 | 473 (1.4) | 258 | 0 | 1/473/258/0 | 15.0 | 11.3 | 0.0 | 0.0 | 0.0 | 99.2 | 0 / 0 |
| kernels[scalar] memcpy RVV-e8 sky130/soc | 43.0 | 0.7 | 1.5 | 14.7 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.5 | 11.8 | 1.8 | 0.0 | 59.2 | 77.5 | 143.4 | 0 | 1.504 | 1 (3.676) | 16,386 / 16,388 | 473 (1.4) | 258 | 0 | 1/473/258/0 | 4.1 | 0.0 | 0.0 | 0.0 | 0.0 | 99.2 | 0 / 0 |
| kernels[scalar] memset C sky130/axi | 33.9 | 0.0 | 32.8 | 33.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 33.5 | 99.2 | 328.7 | 0 | 1.659 | 1 (0.160) | 2 / 2,052 | 4 (0.2) | 4 | 0 | 1/4/4/0 | 0.9 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] memset C sky130/soc | 33.9 | 0.0 | 32.8 | 33.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 33.5 | 99.2 | 328.7 | 0 | 1.659 | 1 (0.160) | 2 / 2,052 | 4 (0.2) | 4 | 0 | 1/4/4/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] memset RVV sky130/axi | 43.8 | 0.8 | 1.7 | 16.7 | 1.7 | 1.7 | 1.7 | 0.0 | 0.0 | 1.7 | 13.3 | 15.0 | 2.1 | 0.0 | 45.4 | 77.5 | 162.5 | 0 | 1.317 | 1 (4.167) | 2 / 2,052 | 4 (0.2) | 4 | 0 | 1/4/4/0 | 2.8 | 2.2 | 0.1 | 0.0 | 2.3 | 87.3 | 0 / 0 |
| kernels[scalar] memset RVV sky130/soc | 43.8 | 0.8 | 1.7 | 16.7 | 1.7 | 1.7 | 1.7 | 0.0 | 0.0 | 1.7 | 13.3 | 15.0 | 2.1 | 0.0 | 45.4 | 77.5 | 162.5 | 0 | 1.317 | 1 (4.167) | 2 / 2,052 | 4 (0.2) | 4 | 0 | 1/4/4/0 | 0.7 | 0.0 | 0.1 | 0.0 | 2.4 | 88.7 | 0 / 0 |
| kernels[scalar] memset RVV-e8 sky130/axi | 39.4 | 0.9 | 1.9 | 18.5 | 1.9 | 1.9 | 0.0 | 0.0 | 0.0 | 1.9 | 14.8 | 16.7 | 2.3 | 0.0 | 59.7 | 77.5 | 180.6 | 0 | 1.560 | 1 (4.630) | 2 / 16,388 | 4 (0.0) | 4 | 0 | 1/4/4/0 | 0.4 | 0.3 | 0.0 | 0.0 | 2.4 | 96.1 | 0 / 0 |
| kernels[scalar] memset RVV-e8 sky130/soc | 39.4 | 0.9 | 1.9 | 18.5 | 1.9 | 1.9 | 0.0 | 0.0 | 0.0 | 1.9 | 14.8 | 16.7 | 2.3 | 0.0 | 59.7 | 77.5 | 180.6 | 0 | 1.560 | 1 (4.630) | 2 / 16,388 | 4 (0.0) | 4 | 0 | 1/4/4/0 | 0.1 | 0.0 | 0.0 | 0.0 | 2.4 | 96.3 | 0 / 0 |
| kernels[scalar] dgemm C sky130/axi | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.0 | 93.9 | 158.4 | 0 | 1.174 | 1 (0.001) | 262,146 / 4,100 | 137,875 (51.8) | 575 | 0 | 1/137875/575/0 | 51.0 | 37.5 | 0.0 | 8.5 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] dgemm C sky130/soc | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.0 | 93.9 | 158.4 | 0 | 1.174 | 1 (0.001) | 262,146 / 4,100 | 137,875 (51.8) | 575 | 0 | 1/137875/575/0 | 21.6 | 0.0 | 0.0 | 13.6 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] dgemm RVV sky130/axi | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 33.3 | 93.9 | 153.7 | 0 | 1.192 | 1 (0.037) | 135,170 / 4,100 | 17,635 (12.7) | 573 | 0 | 1/17635/573/0 | 26.0 | 19.2 | 0.0 | 0.0 | 44.7 | 50.2 | 0 / 0 |
| kernels[scalar] dgemm RVV sky130/soc | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 33.3 | 93.9 | 153.7 | 0 | 1.192 | 1 (0.037) | 135,170 / 4,100 | 17,635 (12.7) | 573 | 0 | 1/17635/573/0 | 8.4 | 0.0 | 0.0 | 0.0 | 55.3 | 39.3 | 0 / 0 |
| kernels[scalar] sgemm C sky130/axi | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 18.8 | 93.9 | 158.4 | 0 | 1.480 | 1 (0.001) | 262,146 / 4,100 | 16,949 (6.4) | 4,159 | 0 | 1/16949/4159/0 | 13.2 | 9.8 | 0.0 | 13.8 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] sgemm C sky130/soc | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 18.8 | 93.9 | 158.4 | 0 | 1.480 | 1 (0.001) | 262,146 / 4,100 | 16,949 (6.4) | 4,159 | 0 | 1/16949/4159/0 | 3.7 | 0.0 | 0.0 | 15.3 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] sgemm RVV sky130/axi | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 17.9 | 93.9 | 153.7 | 0 | 1.648 | 1 (0.037) | 135,170 / 4,100 | 1,326 (1.0) | 319 | 0 | 1/1326/319/0 | 3.2 | 2.4 | 0.0 | 0.0 | 59.0 | 33.0 | 0 / 0 |
| kernels[scalar] sgemm RVV sky130/soc | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 17.9 | 93.9 | 153.7 | 0 | 1.648 | 1 (0.037) | 135,170 / 4,100 | 1,326 (1.0) | 319 | 0 | 1/1326/319/0 | 0.8 | 0.0 | 0.0 | 0.0 | 60.4 | 31.9 | 0 / 0 |
| kernels[scalar] fir_f32 C sky130/axi | 35.6 | 30.8 | 1.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 35.6 | 94.1 | 153.8 | 0 | 1.788 | 1 (0.002) | 131,074 / 4,100 | 2,629 (1.9) | 320 | 0 | 1/2629/320/0 | 3.4 | 2.5 | 0.0 | 13.1 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] fir_f32 C sky130/soc | 35.6 | 30.8 | 1.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 35.6 | 94.1 | 153.8 | 0 | 1.788 | 1 (0.002) | 131,074 / 4,100 | 2,629 (1.9) | 320 | 0 | 1/2629/320/0 | 0.9 | 0.0 | 0.0 | 13.5 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] fir_f32 RVV sky130/axi | 35.9 | 14.7 | 0.1 | 16.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 15.6 | 15.6 | 0.9 | 0.1 | 0.0 | 33.4 | 87.5 | 148.8 | 0 | 1.161 | 1 (0.287) | 66,050 / 4,100 | 627 (0.9) | 265 | 0 | 1/627/265/0 | 3.8 | 2.8 | 0.0 | 0.0 | 61.5 | 36.7 | 0 / 0 |
| kernels[scalar] fir_f32 RVV sky130/soc | 35.9 | 14.7 | 0.1 | 16.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 15.6 | 15.6 | 0.9 | 0.1 | 0.0 | 33.4 | 87.5 | 148.8 | 0 | 1.161 | 1 (0.287) | 66,050 / 4,100 | 627 (0.9) | 265 | 0 | 1/627/265/0 | 1.0 | 0.0 | 0.0 | 0.0 | 63.3 | 35.1 | 0 / 0 |
| kernels[scalar] mac_i8 C sky130/axi | 42.9 | 28.6 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.9 | 99.9 | 142.8 | 0 | 1.286 | 1 (0.009) | 32,770 / 8 | 519 (1.6) | 5 | 0 | 1/519/5/0 | 3.3 | 2.4 | 6.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] mac_i8 C sky130/soc | 42.9 | 28.6 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.9 | 99.9 | 142.8 | 0 | 1.286 | 1 (0.009) | 32,770 / 8 | 519 (1.6) | 5 | 0 | 1/519/5/0 | 0.9 | 0.0 | 6.2 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] mac_i8 RVV sky130/axi | 30.1 | 0.3 | 1.1 | 10.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 19.2 | 18.1 | 19.2 | 0.7 | 0.0 | 41.9 | 87.5 | 100.3 | 0 | 1.390 | 1 (1.412) | 32,770 / 8 | 519 (1.6) | 5 | 0 | 1/519/5/0 | 7.1 | 5.2 | 0.0 | 0.0 | 39.3 | 59.6 | 0 / 0 |
| kernels[scalar] mac_i8 RVV sky130/soc | 30.1 | 0.3 | 1.1 | 10.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 19.2 | 18.1 | 19.2 | 0.7 | 0.0 | 41.9 | 87.5 | 100.3 | 0 | 1.390 | 1 (1.412) | 32,770 / 8 | 519 (1.6) | 5 | 0 | 1/519/5/0 | 2.0 | 0.0 | 0.0 | 0.0 | 41.4 | 57.4 | 0 / 0 |
| kernels[scalar] mac_i16 C sky130/axi | 42.9 | 28.5 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.4 | 99.9 | 142.8 | 0 | 1.286 | 9 (0.157) | 16,386 / 8 | 518 (3.2) | 5 | 0 | 9/518/5/0 | 6.4 | 4.7 | 5.8 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] mac_i16 C sky130/soc | 42.9 | 28.5 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.4 | 99.9 | 142.8 | 0 | 1.286 | 9 (0.157) | 16,386 / 8 | 518 (3.2) | 5 | 0 | 9/518/5/0 | 1.8 | 0.0 | 6.1 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] mac_i16 RVV sky130/axi | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 0 | 1.486 | 1 (1.701) | 16,386 / 8 | 518 (3.2) | 5 | 0 | 1/518/5/0 | 13.7 | 10.1 | 0.0 | 0.0 | 32.6 | 65.3 | 0 / 0 |
| kernels[scalar] mac_i16 RVV sky130/soc | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 0 | 1.486 | 1 (1.701) | 16,386 / 8 | 518 (3.2) | 5 | 0 | 1/518/5/0 | 4.0 | 0.0 | 0.0 | 0.0 | 36.3 | 61.6 | 0 / 0 |
| micro_dmem[default] empty sky130/axi | 35.0 | 10.0 | 20.0 | 0.0 | 5.0 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 25.0 | 0.0 | 45.0 | - | 100.0 | 0 | 1.350 | 1 (50.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 26.2 | 19.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] empty sky130/soc | 35.0 | 10.0 | 20.0 | 0.0 | 5.0 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 25.0 | 0.0 | 45.0 | - | 100.0 | 0 | 1.350 | 1 (50.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 8.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_1k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_1k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_2k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_2k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_4k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 5 (0.1) | 1 | 0 | 1/5/1/0 | 1.1 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_4k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 5 (0.1) | 1 | 0 | 1/5/1/0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_8k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_8k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_12k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_12k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_16k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_16k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_20k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_20k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_24k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_24k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_32k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_32k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_64k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_64k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_128k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_128k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_256k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_256k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_4k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 5 (0.1) | 1 | 0 | 1/5/1/0 | 1.1 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_4k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 5 (0.1) | 1 | 0 | 1/5/1/0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_8k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_8k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_16k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_16k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_32k sky130/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 80.6 | 59.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_32k sky130/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 0 | 1.016 | 1 (0.236) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 52.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] stream_ld sky130/axi | 12.3 | 84.9 | 0.1 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 49.2 | 13.5 | 0 | 1.014 | 1 (0.207) | 4,098 / 4 | 515 (12.6) | 1 | 0 | 1/515/1/0 | 41.8 | 30.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] stream_ld sky130/soc | 12.3 | 84.9 | 0.1 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 49.2 | 13.5 | 0 | 1.014 | 1 (0.207) | 4,098 / 4 | 515 (12.6) | 1 | 0 | 1/515/1/0 | 16.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] stream_st sky130/axi | 12.2 | 0.0 | 85.0 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 49.2 | 13.5 | 0 | 1.014 | 1 (0.207) | 2 / 4,100 | 515 (12.6) | 515 | 0 | 1/515/515/0 | 57.0 | 43.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] stream_st sky130/soc | 12.2 | 0.0 | 85.0 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 49.2 | 13.5 | 0 | 1.014 | 1 (0.207) | 2 / 4,100 | 515 (12.6) | 515 | 0 | 1/515/515/0 | 23.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] empty sky130/axi | 35.0 | 10.0 | 20.0 | 0.0 | 5.0 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 25.0 | 0.0 | 45.0 | - | 100.0 | 0 | 1.300 | 1 (50.000) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 50.9 | 38.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] empty sky130/soc | 35.0 | 10.0 | 20.0 | 0.0 | 5.0 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 25.0 | 0.0 | 45.0 | - | 100.0 | 0 | 1.300 | 1 (50.000) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 20.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_1k sky130/axi | 98.8 | 0.0 | 0.0 | 0.4 | 0.0 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 11.6 | 0 | 1.012 | 387 (7.749) | 2 / 4 | 0 (0.0) | 0 | 0 | 387/0/0/0 | 7.9 | 5.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_1k sky130/soc | 98.8 | 0.0 | 0.0 | 0.4 | 0.0 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 11.6 | 0 | 1.012 | 387 (7.749) | 2 / 4 | 0 (0.0) | 0 | 0 | 387/0/0/0 | 2.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_2k sky130/axi | 99.4 | 0.0 | 0.0 | 0.2 | 0.0 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 | 5.8 | 0 | 1.006 | 195 (3.935) | 2 / 4 | 0 (0.0) | 0 | 0 | 195/0/0/0 | 4.2 | 3.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_2k sky130/soc | 99.4 | 0.0 | 0.0 | 0.2 | 0.0 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 | 5.8 | 0 | 1.006 | 195 (3.935) | 2 / 4 | 0 (0.0) | 0 | 0 | 195/0/0/0 | 1.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_3k sky130/axi | 99.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.4 | 3.9 | 0 | 1.004 | 131 (2.650) | 2 / 4 | 0 (0.0) | 0 | 0 | 131/0/0/0 | 2.9 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_3k sky130/soc | 99.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.4 | 3.9 | 0 | 1.004 | 131 (2.650) | 2 / 4 | 0 (0.0) | 0 | 0 | 131/0/0/0 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_4k sky130/axi | 99.7 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 97.9 | 2.9 | 0 | 1.003 | 195 (3.950) | 2 / 4 | 1 (16.7) | 0 | 0 | 195/1/0/0 | 4.3 | 3.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_4k sky130/soc | 99.7 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 97.9 | 2.9 | 0 | 1.003 | 195 (3.950) | 2 / 4 | 1 (16.7) | 0 | 0 | 195/1/0/0 | 1.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_6k sky130/axi | 99.8 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.9 | 2.0 | 0 | 1.002 | 2,145 (43.506) | 2 / 4 | 1 (16.7) | 0 | 0 | 2145/1/0/0 | 32.1 | 23.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_6k sky130/soc | 99.8 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.9 | 2.0 | 0 | 1.002 | 2,145 (43.506) | 2 / 4 | 1 (16.7) | 0 | 0 | 2145/1/0/0 | 11.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_8k sky130/axi | 99.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 95.8 | 1.5 | 0 | 1.001 | 3,121 (63.344) | 2 / 4 | 1 (16.7) | 0 | 0 | 3121/1/0/0 | 40.3 | 29.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_8k sky130/soc | 99.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 95.8 | 1.5 | 0 | 1.001 | 3,121 (63.344) | 2 / 4 | 1 (16.7) | 0 | 0 | 3121/1/0/0 | 15.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_12k sky130/axi | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 1.0 | 0 | 1.001 | 3,105 (63.060) | 2 / 4 | 1 (16.7) | 0 | 0 | 3105/1/0/0 | 40.2 | 29.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_12k sky130/soc | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 1.0 | 0 | 1.001 | 3,105 (63.060) | 2 / 4 | 1 (16.7) | 0 | 0 | 3105/1/0/0 | 15.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_16k sky130/axi | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 91.7 | 0.8 | 0 | 1.001 | 3,097 (62.918) | 2 / 4 | 1 (16.7) | 0 | 0 | 3097/1/0/0 | 40.1 | 29.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_16k sky130/soc | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 91.7 | 0.8 | 0 | 1.001 | 3,097 (62.918) | 2 / 4 | 1 (16.7) | 0 | 0 | 3097/1/0/0 | 15.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_24k sky130/axi | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.5 | 0.5 | 0 | 1.001 | 3,089 (62.776) | 2 / 4 | 1 (16.7) | 0 | 0 | 3089/1/0/0 | 40.1 | 29.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_24k sky130/soc | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.5 | 0.5 | 0 | 1.001 | 3,089 (62.776) | 2 / 4 | 1 (16.7) | 0 | 0 | 3089/1/0/0 | 15.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_32k sky130/axi | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.3 | 0.4 | 0 | 1.000 | 3,085 (62.705) | 2 / 4 | 0 (0.0) | 0 | 0 | 3085/0/0/0 | 40.1 | 29.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_32k sky130/soc | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.3 | 0.4 | 0 | 1.000 | 3,085 (62.705) | 2 / 4 | 0 (0.0) | 0 | 0 | 3085/0/0/0 | 15.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] empty sky130/axi | 35.0 | 10.0 | 20.0 | 0.0 | 5.0 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 25.0 | 0.0 | 45.0 | - | 100.0 | 0 | 1.300 | 0 (0.000) | 2 / 4 | 1 (16.7) | 1 | 0 | 0/1/1/0 | 42.5 | 32.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] empty sky130/soc | 35.0 | 10.0 | 20.0 | 0.0 | 5.0 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 25.0 | 0.0 | 45.0 | - | 100.0 | 0 | 1.300 | 0 (0.000) | 2 / 4 | 1 (16.7) | 1 | 0 | 0/1/1/0 | 14.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] loop sky130/axi | 50.0 | 0.0 | 0.0 | 49.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 100.0 | 499.0 | 0 | 1.500 | 1 (0.122) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] loop sky130/soc | 50.0 | 0.0 | 0.0 | 49.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 100.0 | 499.0 | 0 | 1.500 | 1 (0.122) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_dep sky130/axi | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.9 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_dep sky130/soc | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_indep sky130/axi | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.9 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_indep sky130/soc | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu16_dep sky130/axi | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 98.8 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.9 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu16_dep sky130/soc | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 98.8 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_straddle sky130/axi | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 93.8 | 4.1 | 0 | 2.000 | 4 (0.963) | 2 / 4 | 1 (16.7) | 1 | 0 | 4/1/1/0 | 0.8 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_straddle sky130/soc | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 93.8 | 4.1 | 0 | 2.000 | 4 (0.963) | 2 / 4 | 1 (16.7) | 1 | 0 | 4/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] br_nt sky130/axi | 0.7 | 0.0 | 0.1 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.4 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.9 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] br_nt sky130/soc | 0.7 | 0.0 | 0.1 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.4 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] br_taken sky130/axi | 0.7 | 0.0 | 0.1 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 100.0 | 990.1 | 0 | 1.992 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] br_taken sky130/soc | 0.7 | 0.0 | 0.1 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 100.0 | 990.1 | 0 | 1.992 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] jal sky130/axi | 0.6 | 0.0 | 0.1 | 0.4 | 98.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 991.3 | 0 | 1.992 | 3 (0.723) | 2 / 4 | 1 (16.7) | 1 | 0 | 3/1/1/0 | 0.7 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] jal sky130/soc | 0.6 | 0.0 | 0.1 | 0.4 | 98.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 991.3 | 0 | 1.992 | 3 (0.723) | 2 / 4 | 1 (16.7) | 1 | 0 | 3/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] call_ret sky130/axi | 33.4 | 0.0 | 0.0 | 0.1 | 33.2 | 33.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 93.8 | 665.1 | 0 | 1.666 | 1 (0.081) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] call_ret sky130/soc | 33.4 | 0.0 | 0.0 | 0.1 | 33.2 | 33.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 93.8 | 665.1 | 0 | 1.666 | 1 (0.081) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] jalr_call_ret sky130/axi | 33.4 | 0.0 | 0.0 | 0.1 | 0.0 | 66.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 93.8 | 665.0 | 0 | 1.666 | 0 (0.000) | 2 / 4 | 1 (16.7) | 1 | 0 | 0/1/1/0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] jalr_call_ret sky130/soc | 33.4 | 0.0 | 0.0 | 0.1 | 0.0 | 66.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 93.8 | 665.0 | 0 | 1.666 | 0 (0.000) | 2 / 4 | 1 (16.7) | 1 | 0 | 0/1/1/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_never sky130/axi | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 1.5 | 3.7 | 0 | 1.004 | 1 (0.057) | 514 / 4 | 4 (0.8) | 2 | 0 | 1/4/2/0 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_never sky130/soc | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 1.5 | 3.7 | 0 | 1.004 | 1 (0.057) | 514 / 4 | 4 (0.8) | 2 | 0 | 1/4/2/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_always sky130/axi | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 100.0 | 237.0 | 0 | 1.237 | 1 (0.057) | 514 / 4 | 4 (0.8) | 2 | 0 | 1/4/2/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_always sky130/soc | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 100.0 | 237.0 | 0 | 1.237 | 1 (0.057) | 514 / 4 | 4 (0.8) | 2 | 0 | 1/4/2/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_alt sky130/axi | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 50.7 | 120.3 | 0 | 1.121 | 1 (0.057) | 514 / 4 | 4 (0.8) | 2 | 0 | 1/4/2/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_alt sky130/soc | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 50.7 | 120.3 | 0 | 1.121 | 1 (0.057) | 514 / 4 | 4 (0.8) | 2 | 0 | 1/4/2/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_rand sky130/axi | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 50.7 | 120.3 | 0 | 1.121 | 1 (0.057) | 514 / 4 | 4 (0.8) | 2 | 0 | 1/4/2/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_rand sky130/soc | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 50.7 | 120.3 | 0 | 1.121 | 1 (0.057) | 514 / 4 | 4 (0.8) | 2 | 0 | 1/4/2/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_dep sky130/axi | 0.6 | 98.8 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 93.8 | 4.1 | 0 | 1.005 | 2 (0.482) | 4,098 / 4 | 1 (0.0) | 1 | 0 | 2/1/1/0 | 0.7 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_dep sky130/soc | 0.6 | 98.8 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 93.8 | 4.1 | 0 | 1.005 | 2 (0.482) | 4,098 / 4 | 1 (0.0) | 1 | 0 | 2/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_indep sky130/axi | 0.7 | 98.6 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.004 | 1 (0.241) | 4,098 / 4 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_indep sky130/soc | 0.7 | 98.6 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.004 | 1 (0.241) | 4,098 / 4 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_use1 sky130/axi | 50.0 | 49.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 93.8 | 2.1 | 0 | 1.002 | 1 (0.121) | 4,098 / 4 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_use1 sky130/soc | 50.0 | 49.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 93.8 | 2.1 | 0 | 1.002 | 1 (0.121) | 4,098 / 4 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_use2 sky130/axi | 50.0 | 49.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 93.8 | 2.1 | 0 | 1.002 | 3 (0.364) | 4,099 / 4 | 1 (0.0) | 1 | 0 | 3/1/1/0 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_use2 sky130/soc | 50.0 | 49.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 93.8 | 2.1 | 0 | 1.002 | 3 (0.364) | 4,099 / 4 | 1 (0.0) | 1 | 0 | 3/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] st sky130/axi | 0.7 | 0.0 | 98.7 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.005 | 1 (0.241) | 2 / 4,100 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] st sky130/soc | 0.7 | 0.0 | 98.7 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.005 | 1 (0.241) | 2 / 4,100 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] rdcycle sky130/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.004 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.9 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] rdcycle sky130/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.004 | 1 (0.241) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] rdtime sky130/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] rdtime sky130/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrr sky130/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.004 | 3 (0.723) | 2 / 4 | 0 (0.0) | 0 | 0 | 3/0/0/0 | 0.8 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrr sky130/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.004 | 3 (0.723) | 2 / 4 | 0 (0.0) | 0 | 0 | 3/0/0/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrw sky130/axi | 0.7 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.7 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrw sky130/soc | 0.7 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.7 | 0.0 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrrw sky130/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 | 0.0 | 0.3 | 93.8 | 4.1 | 0 | 1.005 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrrw sky130/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 | 0.0 | 0.3 | 93.8 | 4.1 | 0 | 1.005 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] fence sky130/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 98.7 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] fence sky130/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 98.7 | 0.2 | 93.8 | 4.1 | 0 | 1.006 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] empty sky130/axi | 35.0 | 10.0 | 20.0 | 0.0 | 5.0 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 25.0 | 0.0 | 45.0 | - | 100.0 | 0 | 1.350 | 1 (50.000) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 50.2 | 37.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] empty sky130/soc | 35.0 | 10.0 | 20.0 | 0.0 | 5.0 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 25.0 | 0.0 | 45.0 | - | 100.0 | 0 | 1.350 | 1 (50.000) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 19.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] mul_dep sky130/axi | 3.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 94.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.7 | 0 | 1.031 | 1 (0.921) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.8 | 0.6 | 46.2 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] mul_dep sky130/soc | 3.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 94.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.7 | 0 | 1.031 | 1 (0.921) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.0 | 46.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] mul_indep sky130/axi | 3.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 94.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.7 | 0 | 1.017 | 2 (1.842) | 2 / 4 | 1 (16.7) | 0 | 0 | 2/1/0/0 | 2.3 | 1.7 | 45.9 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] mul_indep sky130/soc | 3.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 94.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.7 | 0 | 1.017 | 2 (1.842) | 2 / 4 | 1 (16.7) | 0 | 0 | 2/1/0/0 | 0.6 | 0.0 | 46.7 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_dep sky130/axi | 2.8 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.7 | 0 | 1.020 | 2 (1.847) | 2 / 4 | 0 (0.0) | 0 | 0 | 2/0/0/0 | 0.2 | 0.1 | 93.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_dep sky130/soc | 2.8 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.7 | 0 | 1.020 | 2 (1.847) | 2 / 4 | 0 (0.0) | 0 | 0 | 2/0/0/0 | 0.0 | 0.0 | 93.7 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_indep sky130/axi | 2.8 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.7 | 0 | 1.023 | 1 (0.923) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 93.7 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_indep sky130/soc | 2.8 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.7 | 0 | 1.023 | 1 (0.923) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 93.7 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_short sky130/axi | 2.3 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 95.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.8 | 0 | 1.017 | 1 (0.928) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.8 | 0.6 | 47.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_short sky130/soc | 2.3 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 95.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.8 | 0 | 1.017 | 1 (0.928) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.0 | 47.2 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] divw_dep sky130/axi | 2.4 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.0 | 93.8 | 15.8 | 0 | 1.020 | 1 (0.927) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.3 | 0.2 | 88.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] divw_dep sky130/soc | 2.4 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.0 | 93.8 | 15.8 | 0 | 1.020 | 1 (0.927) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 88.8 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] rem_indep sky130/axi | 2.7 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.0 | 93.8 | 15.7 | 0 | 1.019 | 1 (0.924) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 93.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] rem_indep sky130/soc | 2.7 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.0 | 93.8 | 15.7 | 0 | 1.019 | 1 (0.924) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 93.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fadd_d_dep sky130/axi | 2.1 | 0.4 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 0 | 1.019 | 5 (4.625) | 4 / 4 | 2 (25.0) | 2 | 0 | 5/2/2/0 | 4.8 | 3.6 | 0.0 | 60.7 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fadd_d_dep sky130/soc | 2.1 | 0.4 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 0 | 1.019 | 5 (4.625) | 4 / 4 | 2 (25.0) | 2 | 0 | 5/2/2/0 | 1.2 | 0.0 | 0.0 | 62.9 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fadd_d_indep sky130/axi | 1.9 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.4 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.019 | 4 (3.711) | 2 / 4 | 0 (0.0) | 0 | 0 | 4/0/0/0 | 2.1 | 1.5 | 0.0 | 62.8 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fadd_d_indep sky130/soc | 1.9 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.4 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.019 | 4 (3.711) | 2 / 4 | 0 (0.0) | 0 | 0 | 4/0/0/0 | 0.6 | 0.0 | 0.0 | 63.8 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fmul_d_dep sky130/axi | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.2 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.025 | 1 (0.927) | 3 / 4 | 1 (14.3) | 0 | 0 | 1/1/0/0 | 1.1 | 0.8 | 0.0 | 63.2 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fmul_d_dep sky130/soc | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.2 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.025 | 1 (0.927) | 3 / 4 | 1 (14.3) | 0 | 0 | 1/1/0/0 | 0.3 | 0.0 | 0.0 | 63.7 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fmadd_d_dep sky130/axi | 2.2 | 0.5 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 94.8 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 0 | 1.030 | 1 (0.923) | 5 / 4 | 1 (11.1) | 0 | 0 | 1/1/0/0 | 0.8 | 0.6 | 0.0 | 71.8 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fmadd_d_dep sky130/soc | 2.2 | 0.5 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 94.8 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 0 | 1.030 | 1 (0.923) | 5 / 4 | 1 (11.1) | 0 | 0 | 1/1/0/0 | 0.2 | 0.0 | 0.0 | 72.2 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_d_dep sky130/axi | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.2 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.025 | 3 (2.780) | 3 / 4 | 1 (14.3) | 0 | 0 | 3/1/0/0 | 0.4 | 0.3 | 0.0 | 92.8 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_d_dep sky130/soc | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.2 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.025 | 3 (2.780) | 3 / 4 | 1 (14.3) | 0 | 0 | 3/1/0/0 | 0.1 | 0.0 | 0.0 | 93.1 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_d_indep sky130/axi | 1.9 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.4 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.022 | 1 (0.928) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.2 | 0.1 | 0.0 | 93.1 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_d_indep sky130/soc | 1.9 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.4 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.022 | 1 (0.928) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 93.2 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_d_dep sky130/axi | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.2 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.018 | 1 (0.929) | 3 / 4 | 1 (14.3) | 0 | 0 | 1/1/0/0 | 0.2 | 0.1 | 0.0 | 93.1 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_d_dep sky130/soc | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.2 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.018 | 1 (0.929) | 3 / 4 | 1 (14.3) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 93.2 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_d_indep sky130/axi | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.2 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.8 | 0 | 1.022 | 0 (0.000) | 3 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 93.3 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_d_indep sky130/soc | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.2 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.8 | 0 | 1.022 | 0 (0.000) | 3 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 93.3 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_s_dep sky130/axi | 2.1 | 0.4 | 0.5 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 94.9 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 0 | 1.026 | 1 (0.925) | 4 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.1 | 0.0 | 87.4 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_s_dep sky130/soc | 2.1 | 0.4 | 0.5 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 94.9 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 0 | 1.026 | 1 (0.925) | 4 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 87.5 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_s_dep sky130/axi | 2.0 | 0.3 | 0.5 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.024 | 1 (0.929) | 3 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.1 | 0.0 | 87.5 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_s_dep sky130/soc | 2.0 | 0.3 | 0.5 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 0 | 1.024 | 1 (0.929) | 3 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 87.6 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] empty sky130/axi | 38.1 | 9.5 | 19.0 | 0.0 | 4.8 | 4.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.8 | 0.0 | 23.8 | - | 95.2 | 0 | 1.429 | 1 (47.619) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 51.6 | 39.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] empty sky130/soc | 38.1 | 9.5 | 19.0 | 0.0 | 4.8 | 4.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.8 | 0.0 | 23.8 | - | 95.2 | 0 | 1.429 | 1 (47.619) | 2 / 4 | 1 (16.7) | 1 | 0 | 1/1/1/0 | 20.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vsetvli_same sky130/axi | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 1.7 | 0.0 | 2.0 | 87.5 | 30.7 | 0 | 1.041 | 1 (3.413) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 6.8 | 5.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vsetvli_same sky130/soc | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 1.7 | 0.0 | 2.0 | 87.5 | 30.7 | 0 | 1.041 | 1 (3.413) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 1.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vsetvli_toggle sky130/axi | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 1.7 | 0.0 | 2.0 | 87.5 | 30.7 | 0 | 1.065 | 1 (3.413) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 6.7 | 4.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vsetvli_toggle sky130/soc | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 1.7 | 0.0 | 2.0 | 87.5 | 30.7 | 0 | 1.065 | 1 (3.413) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 1.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl1 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 1 (3.425) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 3.0 | 2.2 | 0.0 | 0.0 | 67.3 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl1 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 1 (3.425) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.8 | 0.0 | 0.0 | 0.0 | 68.8 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl2 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 1.4 | 1.0 | 0.0 | 0.0 | 71.7 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl2 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.4 | 0.0 | 0.0 | 0.0 | 72.4 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl4 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 1.1 | 0.8 | 0.0 | 0.0 | 76.5 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl4 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.3 | 0.0 | 0.0 | 0.0 | 77.1 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl8 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.8 | 0.6 | 0.0 | 0.0 | 82.5 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl8 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.2 | 0.0 | 0.0 | 0.0 | 83.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl16 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.6 | 0.4 | 0.0 | 0.0 | 88.4 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl16 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 88.7 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl32 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 93.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl32 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 93.3 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl64 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.2 | 0.1 | 0.0 | 0.0 | 96.1 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl64 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.3 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl128 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.1 | 0.1 | 0.0 | 0.0 | 98.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl128 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl256 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 99.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl256 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl512 sky130/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl512 sky130/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 0 | 1.045 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0.0 | 0 / 0 |
| micro_vec[default] vle8_vl1 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 2 (6.873) | 258 / 4 | 1 (0.4) | 0 | 0 | 2/1/0/0 | 4.9 | 3.6 | 0.0 | 0.0 | 0.0 | 61.8 | 0 / 0 |
| micro_vec[default] vle8_vl1 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 2 (6.873) | 258 / 4 | 1 (0.4) | 0 | 0 | 2/1/0/0 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 64.2 | 0 / 0 |
| micro_vec[default] vle8_vl2 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 514 / 4 | 1 (0.2) | 0 | 0 | 1/1/0/0 | 2.2 | 1.6 | 0.0 | 0.0 | 0.0 | 75.5 | 0 / 0 |
| micro_vec[default] vle8_vl2 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 514 / 4 | 1 (0.2) | 0 | 0 | 1/1/0/0 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 76.7 | 0 / 0 |
| micro_vec[default] vle8_vl4 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 1,026 / 4 | 1 (0.1) | 0 | 0 | 1/1/0/0 | 1.3 | 1.0 | 0.0 | 0.0 | 0.0 | 85.5 | 0 / 0 |
| micro_vec[default] vle8_vl4 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 1,026 / 4 | 1 (0.1) | 0 | 0 | 1/1/0/0 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 86.2 | 0 / 0 |
| micro_vec[default] vle8_vl8 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 2,050 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.7 | 0.5 | 0.0 | 0.0 | 0.0 | 92.1 | 0 / 0 |
| micro_vec[default] vle8_vl8 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 2,050 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 92.4 | 0 / 0 |
| micro_vec[default] vle8_vl16 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 4,098 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 95.9 | 0 / 0 |
| micro_vec[default] vle8_vl16 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 4,098 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 96.0 | 0 / 0 |
| micro_vec[default] vle8_vl32 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 8,194 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 97.9 | 0 / 0 |
| micro_vec[default] vle8_vl32 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 8,194 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 97.9 | 0 / 0 |
| micro_vec[default] vle8_vl64 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 16,386 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 98.9 | 0 / 0 |
| micro_vec[default] vle8_vl64 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 16,386 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 | 0 / 0 |
| micro_vec[default] vle8_vl128 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 32,770 / 4 | 2 (0.0) | 1 | 0 | 1/2/1/0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 99.5 | 0 / 0 |
| micro_vec[default] vle8_vl128 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 32,770 / 4 | 2 (0.0) | 1 | 0 | 1/2/1/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0 / 0 |
| micro_vec[default] vle8_vl256 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 65,538 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.7 | 0 / 0 |
| micro_vec[default] vle8_vl256 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 65,538 / 4 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.7 | 0 / 0 |
| micro_vec[default] vle8_vl512 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 131,074 / 4 | 3 (0.0) | 0 | 0 | 1/3/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vle8_vl512 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.062 | 1 (3.436) | 131,074 / 4 | 3 (0.0) | 0 | 0 | 1/3/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vse8_vl1 sky130/axi | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.7 | 0 | 1.061 | 1 (3.413) | 2 / 260 | 1 (0.4) | 0 | 0 | 1/1/0/0 | 3.0 | 2.2 | 0.0 | 0.0 | 0.0 | 66.8 | 0 / 0 |
| micro_vec[default] vse8_vl1 sky130/soc | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.7 | 0 | 1.061 | 1 (3.413) | 2 / 260 | 1 (0.4) | 0 | 0 | 1/1/0/0 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 68.3 | 0 / 0 |
| micro_vec[default] vse8_vl8 sky130/axi | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.7 | 0 | 1.061 | 0 (0.000) | 2 / 2,052 | 1 (0.0) | 0 | 0 | 0/1/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 93.5 | 0 / 0 |
| micro_vec[default] vse8_vl8 sky130/soc | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.7 | 0 | 1.061 | 0 (0.000) | 2 / 2,052 | 1 (0.0) | 0 | 0 | 0/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 93.7 | 0 / 0 |
| micro_vec[default] vse8_vl64 sky130/axi | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.7 | 0 | 1.061 | 0 (0.000) | 2 / 16,388 | 1 (0.0) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.1 | 0 / 0 |
| micro_vec[default] vse8_vl64 sky130/soc | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.7 | 0 | 1.061 | 0 (0.000) | 2 / 16,388 | 1 (0.0) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.2 | 0 / 0 |
| micro_vec[default] vse8_vl512 sky130/axi | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.7 | 0 | 1.061 | 0 (0.000) | 2 / 131,076 | 1 (0.0) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vse8_vl512 sky130/soc | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.7 | 0 | 1.061 | 0 (0.000) | 2 / 131,076 | 1 (0.0) | 0 | 0 | 0/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vadd_e64_vl8 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.038 | 1 (3.436) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 1.7 | 1.2 | 0.0 | 0.0 | 81.9 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e64_vl8 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.038 | 1 (3.436) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.4 | 0.0 | 0.0 | 0.0 | 82.9 | 0.0 | 0 / 0 |
| micro_vec[default] vmul_e64_vl8 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.038 | 1 (3.436) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 96.0 | 0.0 | 0 / 0 |
| micro_vec[default] vmul_e64_vl8 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.038 | 1 (3.436) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 96.3 | 0.0 | 0 / 0 |
| micro_vec[default] vfadd_e64_vl8 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.065 | 1 (3.436) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 94.9 | 0.0 | 0 / 0 |
| micro_vec[default] vfadd_e64_vl8 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.065 | 1 (3.436) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 95.1 | 0.0 | 0 / 0 |
| micro_vec[default] vredsum_e64_vl8 sky130/axi | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.065 | 1 (3.436) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.7 | 0.5 | 0.0 | 0.0 | 84.2 | 0.0 | 0 / 0 |
| micro_vec[default] vredsum_e64_vl8 sky130/soc | 4.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.9 | 0 | 1.065 | 1 (3.436) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.0 | 0.0 | 0.0 | 84.6 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 plain C sky130/axi | 83.1 | 10.1 | 2.7 | 4.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.4 | 96.6 | 39.4 | 0 | 1.352 | 9 (0.002) | 375,822 / 99,348 | 2 (0.0) | 0 | 0 | 9/2/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 plain C sky130/soc | 83.1 | 10.1 | 2.7 | 4.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.4 | 96.6 | 39.4 | 0 | 1.352 | 9 (0.002) | 375,822 / 99,348 | 2 (0.0) | 0 | 0 | 9/2/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 Zknh sky130/axi | 77.1 | 13.8 | 3.6 | 5.4 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 55.0 | 96.6 | 53.6 | 0 | 1.227 | 8 (0.003) | 376,846 / 98,325 | 2 (0.0) | 0 | 0 | 8/2/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 Zknh sky130/soc | 77.1 | 13.8 | 3.6 | 5.4 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 55.0 | 96.6 | 53.6 | 0 | 1.227 | 8 (0.003) | 376,846 / 98,325 | 2 (0.0) | 0 | 0 | 8/2/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) sky130/axi | 0.5 | 1.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 97.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.2 | 24.8 | 1.5 | 0 | 1.007 | 61 (0.278) | 32,918 / 4,624 | 2 (0.0) | 0 | 0 | 61/2/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 88.2 | 2.7 | 0 / 0 |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) sky130/soc | 0.5 | 1.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 97.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.2 | 24.8 | 1.5 | 0 | 1.007 | 61 (0.278) | 32,918 / 4,624 | 2 (0.0) | 0 | 0 | 61/2/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 88.2 | 2.7 | 0 / 0 |
| sha256chain[sdk] sha256 accel sigil_sha256_block sky130/axi | 44.9 | 18.6 | 16.0 | 19.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 63.5 | 90.0 | 185.9 | 0 | 1.269 | 3 (0.019) | 29,701 / 25,607 | 0 (0.0) | 0 | 30,720 | 3/0/0/30720 | 15.2 | 7.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 accel sigil_sha256_block sky130/soc | 44.9 | 18.6 | 16.0 | 19.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 63.5 | 90.0 | 185.9 | 0 | 1.269 | 3 (0.019) | 29,701 / 25,607 | 0 (0.0) | 0 | 30,720 | 3/0/0/30720 | 15.2 | 7.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 accel sigil_sha256 sky130/axi | 65.5 | 12.9 | 10.3 | 10.7 | 0.3 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.7 | 88.8 | 100.8 | 0 | 1.286 | 8 (0.008) | 132,102 / 105,480 | 1 (0.0) | 0 | 30,720 | 8/1/0/30720 | 2.7 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 accel sigil_sha256 sky130/soc | 65.5 | 12.9 | 10.3 | 10.7 | 0.3 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.7 | 88.8 | 100.8 | 0 | 1.286 | 8 (0.008) | 132,102 / 105,480 | 1 (0.0) | 0 | 30,720 | 8/1/0/30720 | 2.7 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha512 accel sigil_hash sky130/axi | 73.1 | 4.5 | 9.2 | 12.7 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 32.7 | 68.0 | 91.6 | 0 | 1.152 | 11 (0.011) | 45,062 / 92,170 | 1 (0.0) | 0 | 38,910 | 11/1/0/38910 | 4.0 | 2.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha512 accel sigil_hash sky130/soc | 73.1 | 4.5 | 9.2 | 12.7 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 32.7 | 68.0 | 91.6 | 0 | 1.152 | 11 (0.011) | 45,063 / 92,170 | 1 (0.0) | 0 | 38,911 | 11/1/0/38911 | 4.0 | 2.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha3-256 accel sigil_hash sky130/axi | 72.7 | 4.8 | 9.2 | 12.4 | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 33.4 | 62.7 | 86.7 | 0 | 1.173 | 3 (0.005) | 26,632 / 51,210 | 1 (0.0) | 0 | 20,480 | 3/1/0/20480 | 3.8 | 1.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha3-256 accel sigil_hash sky130/soc | 72.7 | 4.8 | 9.2 | 12.4 | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 33.4 | 62.7 | 86.7 | 0 | 1.173 | 3 (0.005) | 26,632 / 51,210 | 1 (0.0) | 0 | 20,480 | 3/1/0/20480 | 3.8 | 1.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 plain C sky130/axi | 83.8 | 9.8 | 2.3 | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.1 | 96.6 | 39.3 | 0 | 1.351 | 20 (0.005) | 363,923 / 84,174 | 1,734 (0.4) | 435 | 0 | 20/1734/435/0 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 plain C sky130/soc | 83.8 | 9.8 | 2.3 | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.1 | 96.6 | 39.3 | 0 | 1.351 | 20 (0.005) | 363,923 / 84,174 | 1,734 (0.4) | 435 | 0 | 20/1734/435/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 Zknh sky130/axi | 77.6 | 13.6 | 3.3 | 5.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 55.1 | 96.6 | 53.2 | 0 | 1.216 | 18 (0.007) | 371,104 / 91,346 | 1,720 (0.4) | 374 | 0 | 18/1720/374/0 | 0.7 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 Zknh sky130/soc | 77.6 | 13.6 | 3.3 | 5.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 55.1 | 96.6 | 53.2 | 0 | 1.216 | 18 (0.007) | 371,104 / 91,346 | 1,720 (0.4) | 374 | 0 | 18/1720/374/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) sky130/axi | 0.3 | 1.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 96.7 | 0.7 | 0.1 | 0.0 | 0.0 | 0.0 | 24.5 | 1.5 | 0 | 1.008 | 69 (0.308) | 36,406 / 8,328 | 2,065 (4.6) | 23 | 0 | 69/2065/23/0 | 1.3 | 1.0 | 0.0 | 0.0 | 86.5 | 4.9 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) sky130/soc | 0.3 | 1.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 96.7 | 0.7 | 0.1 | 0.0 | 0.0 | 0.0 | 24.5 | 1.5 | 0 | 1.008 | 69 (0.308) | 36,406 / 8,328 | 2,065 (4.6) | 23 | 0 | 69/2065/23/0 | 0.4 | 0.0 | 0.0 | 0.0 | 87.4 | 3.9 | 0 / 0 |
| sha256chain_bulk[sdk] sha512 accel sigil_hash sky130/axi | 25.7 | 24.7 | 24.8 | 24.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 74.4 | 99.8 | 247.6 | 0 | 1.249 | 9 (0.135) | 16,412 / 16,462 | 1,029 (3.1) | 13 | 16,404 | 9/1029/13/16404 | 25.2 | 14.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha512 accel sigil_hash sky130/soc | 25.7 | 24.7 | 24.8 | 24.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 74.4 | 99.8 | 247.6 | 0 | 1.249 | 9 (0.135) | 16,413 / 16,462 | 1,029 (3.1) | 13 | 16,405 | 9/1029/13/16405 | 19.9 | 8.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash sky130/axi | 25.4 | 24.8 | 24.9 | 24.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 74.6 | 99.8 | 248.6 | 0 | 1.249 | 1 (0.015) | 16,404 / 16,430 | 1,029 (3.1) | 8 | 16,396 | 1/1029/8/16396 | 25.2 | 14.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash sky130/soc | 25.4 | 24.8 | 24.9 | 24.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 74.6 | 99.8 | 248.6 | 0 | 1.249 | 1 (0.015) | 16,404 / 16,430 | 1,029 (3.1) | 8 | 16,396 | 1/1029/8/16396 | 20.0 | 8.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |

Columns: `alu %` = retired alu (% of instret); `load %` = retired load (% of instret); `store %` = retired store (% of instret); `branch %` = retired branch (% of instret); `jal %` = retired jal (% of instret); `jalr %` = retired jalr (% of instret); `mul %` = retired mul (% of instret); `div %` = retired div (% of instret); `fp %` = retired fp (% of instret); `vec %` = retired vec (% of instret); `vls %` = retired vls (% of instret); `vset %` = retired vset (% of instret); `csr %` = retired csr (% of instret); `fence %` = retired fence (% of instret); `rvc %` = compressed (RVC, % of instret); `taken %` = taken branches (% of branches); `redir/ki` = redirects per 1000 instr; `squashed` = squashed wrong-path instr; `I$ acc/i` = I$ fetch accesses per instr; `I$ miss (/ki)` = I$ misses (per 1000 instr); `D$ ld / st` = D$ loads / stores; `D$ miss (%)` = D$ misses (% of accesses); `D$ wb` = D$ write-backs; `D unc` = uncached D accesses; `bus if/df/wb/unc` = bus transactions (I fill / D fill / D wb / uncached); `bus %` = bus busy (% of cycles); `bus wait %` = bus waiting on memory (% of cycles); `M %` = M unit busy (% of cycles); `FPU %` = FPU busy (% of cycles); `vec %` = vector unit busy (% of cycles); `vls %` = vector LS in MEM (% of cycles); `traps` = traps (exceptions / interrupts).

