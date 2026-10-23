# Sigil performance report

- Date (UTC): 2026-10-22T11:11:11Z
- Commit: `662bad7146e7f29ec2972169050ab60a4e03a853` (56-perf-harness); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
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
| default | axi | `fpga_top_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |
| default | soc | `soc_rtl_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Net cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| coremark [scalar] | default | axi | 20 | 14,339,056 | 5,246,413 | 0.366 | 2.733 | 716,952.80 | - | 1.395 CoreMark/MHz | 14,339,027 |
| coremark [scalar] | default | soc | 20 | 14,337,806 | 5,246,413 | 0.366 | 2.733 | 716,890.30 | - | 1.395 CoreMark/MHz | 14,337,777 |
| coremark [sdk] | default | axi | 20 | 14,573,757 | 5,238,336 | 0.359 | 2.782 | 728,687.85 | - | 1.372 CoreMark/MHz | 14,573,725 |
| coremark [sdk] | default | soc | 20 | 14,572,507 | 5,238,336 | 0.359 | 2.782 | 728,625.35 | - | 1.372 CoreMark/MHz | 14,572,475 |
| coremark [validation] | default | axi | 20 | 14,366,037 | 5,253,779 | 0.366 | 2.734 | 718,301.85 | - | 1.392 CoreMark/MHz | 14,366,008 |
| coremark [validation] | default | soc | 20 | 14,364,787 | 5,253,779 | 0.366 | 2.734 | 718,239.35 | - | 1.392 CoreMark/MHz | 14,364,758 |
| dhrystone [scalar] | default | axi | 2000 | 3,070,652 | 1,036,022 | 0.337 | 2.964 | 1,535.33 | - | 0.371 DMIPS/MHz | 3,070,621 |
| dhrystone [scalar] | default | soc | 2000 | 3,070,244 | 1,036,022 | 0.337 | 2.963 | 1,535.12 | - | 0.371 DMIPS/MHz | 3,070,213 |
| dhrystone [sdk] | default | axi | 2000 | 3,482,658 | 1,022,022 | 0.293 | 3.408 | 1,741.33 | - | 0.327 DMIPS/MHz | 3,482,595 |
| dhrystone [sdk] | default | soc | 2000 | 3,482,242 | 1,022,022 | 0.293 | 3.407 | 1,741.12 | - | 0.327 DMIPS/MHz | 3,482,204 |
| kernels [autovec] vadd_i32 C | default | axi | 4 | 51,500 | 2,654 | 0.052 | 19.405 | 12,875.00 | - | 0.0795 elem/cycle | 51,389 |
| kernels [autovec] vadd_i32 C | default | soc | 4 | 50,438 | 2,654 | 0.053 | 19.005 | 12,609.50 | - | 0.0812 elem/cycle | 50,385 |
| kernels [autovec] vadd_i32 RVV | default | axi | 4 | 45,814 | 372 | 0.008 | 123.156 | 11,453.50 | - | 0.0894 elem/cycle | 45,718 |
| kernels [autovec] vadd_i32 RVV | default | soc | 4 | 43,277 | 372 | 0.009 | 116.336 | 10,819.25 | - | 0.0946 elem/cycle | 43,231 |
| kernels [autovec] vadd_i64 C | default | axi | 4 | 29,413 | 2,652 | 0.090 | 11.091 | 7,353.25 | - | 0.0696 elem/cycle | 29,302 |
| kernels [autovec] vadd_i64 C | default | soc | 4 | 28,567 | 2,652 | 0.093 | 10.772 | 7,141.75 | - | 0.0717 elem/cycle | 28,514 |
| kernels [autovec] vadd_i64 RVV | default | axi | 4 | 23,356 | 372 | 0.016 | 62.785 | 5,839.00 | - | 0.0877 elem/cycle | 23,210 |
| kernels [autovec] vadd_i64 RVV | default | soc | 4 | 22,146 | 372 | 0.017 | 59.532 | 5,536.50 | - | 0.0925 elem/cycle | 22,083 |
| kernels [autovec] daxpy C | default | axi | 4 | 43,252 | 2,656 | 0.061 | 16.285 | 10,813.00 | - | 0.0474 elem/cycle | 43,131 |
| kernels [autovec] daxpy C | default | soc | 4 | 42,771 | 2,656 | 0.062 | 16.104 | 10,692.75 | - | 0.0479 elem/cycle | 42,708 |
| kernels [autovec] daxpy RVV | default | axi | 4 | 37,088 | 340 | 0.009 | 109.082 | 9,272.00 | - | 0.0552 elem/cycle | 36,985 |
| kernels [autovec] daxpy RVV | default | soc | 4 | 36,242 | 340 | 0.009 | 106.594 | 9,060.50 | - | 0.0565 elem/cycle | 36,189 |
| kernels [autovec] saxpy C | default | axi | 4 | 79,165 | 2,652 | 0.033 | 29.851 | 19,791.25 | - | 0.0517 elem/cycle | 79,069 |
| kernels [autovec] saxpy C | default | soc | 4 | 78,833 | 2,652 | 0.034 | 29.726 | 19,708.25 | - | 0.0520 elem/cycle | 78,787 |
| kernels [autovec] saxpy RVV | default | axi | 4 | 71,805 | 340 | 0.005 | 211.191 | 17,951.25 | - | 0.0570 elem/cycle | 71,771 |
| kernels [autovec] saxpy RVV | default | soc | 4 | 71,025 | 340 | 0.005 | 208.897 | 17,756.25 | - | 0.0577 elem/cycle | 70,991 |
| kernels [autovec] ddot C | default | axi | 4 | 51,728 | 3,384 | 0.065 | 15.286 | 12,932.00 | - | 0.0396 elem/cycle | 51,607 |
| kernels [autovec] ddot C | default | soc | 4 | 51,645 | 3,384 | 0.066 | 15.262 | 12,911.25 | - | 0.0397 elem/cycle | 51,582 |
| kernels [autovec] ddot RVV | default | axi | 4 | 31,667 | 332 | 0.010 | 95.383 | 7,916.75 | - | 0.0647 elem/cycle | 31,643 |
| kernels [autovec] ddot RVV | default | soc | 4 | 31,617 | 332 | 0.011 | 95.232 | 7,904.25 | - | 0.0648 elem/cycle | 31,593 |
| kernels [autovec] idot_i32 C | default | axi | 4 | 62,879 | 4,172 | 0.066 | 15.072 | 15,719.75 | - | 0.0651 elem/cycle | 62,819 |
| kernels [autovec] idot_i32 C | default | soc | 4 | 62,854 | 4,172 | 0.066 | 15.066 | 15,713.50 | - | 0.0652 elem/cycle | 62,819 |
| kernels [autovec] idot_i32 RVV | default | axi | 4 | 51,661 | 588 | 0.011 | 87.859 | 12,915.25 | - | 0.0793 elem/cycle | 51,591 |
| kernels [autovec] idot_i32 RVV | default | soc | 4 | 51,636 | 588 | 0.011 | 87.816 | 12,909.00 | - | 0.0793 elem/cycle | 51,591 |
| kernels [autovec] memcpy C | default | axi | 4 | 33,176 | 10,355 | 0.312 | 3.204 | 8,294.00 | - | 0.4939 byte/cycle | 33,063 |
| kernels [autovec] memcpy C | default | soc | 4 | 33,093 | 10,355 | 0.313 | 3.196 | 8,273.25 | - | 0.4951 byte/cycle | 33,038 |
| kernels [autovec] memcpy RVV | default | axi | 4 | 13,176 | 275 | 0.021 | 47.913 | 3,294.00 | - | 1.2435 byte/cycle | 13,027 |
| kernels [autovec] memcpy RVV | default | soc | 4 | 13,093 | 275 | 0.021 | 47.611 | 3,273.25 | - | 1.2514 byte/cycle | 13,027 |
| kernels [autovec] memcpy RVV-e8 | default | axi | 4 | 99,357 | 271 | 0.003 | 366.631 | 24,839.25 | - | 0.1649 byte/cycle | 99,209 |
| kernels [autovec] memcpy RVV-e8 | default | soc | 4 | 99,158 | 271 | 0.003 | 365.897 | 24,789.50 | - | 0.1652 byte/cycle | 99,093 |
| kernels [autovec] memset C | default | axi | 4 | 21,001 | 6,264 | 0.298 | 3.353 | 5,250.25 | - | 0.7802 byte/cycle | 20,850 |
| kernels [autovec] memset C | default | soc | 4 | 20,860 | 6,264 | 0.300 | 3.330 | 5,215.00 | - | 0.7854 byte/cycle | 20,792 |
| kernels [autovec] memset RVV | default | axi | 4 | 7,063 | 241 | 0.034 | 29.307 | 1,765.75 | - | 2.3197 byte/cycle | 7,031 |
| kernels [autovec] memset RVV | default | soc | 4 | 7,038 | 241 | 0.034 | 29.203 | 1,759.50 | - | 2.3279 byte/cycle | 7,006 |
| kernels [autovec] memset RVV-e8 | default | axi | 4 | 51,897 | 215 | 0.004 | 241.381 | 12,974.25 | - | 0.3157 byte/cycle | 51,835 |
| kernels [autovec] memset RVV-e8 | default | soc | 4 | 51,872 | 215 | 0.004 | 241.265 | 12,968.00 | - | 0.3159 byte/cycle | 51,835 |
| kernels [autovec] dgemm C | default | axi | 4 | 2,940,424 | 828,348 | 0.282 | 3.550 | 735,106.00 | - | 0.0446 mac/cycle | 2,940,292 |
| kernels [autovec] dgemm C | default | soc | 4 | 2,887,312 | 828,348 | 0.287 | 3.486 | 721,828.00 | - | 0.0454 mac/cycle | 2,887,255 |
| kernels [autovec] dgemm RVV | default | axi | 4 | 1,607,697 | 26,692 | 0.017 | 60.231 | 401,924.25 | - | 0.0815 mac/cycle | 1,607,591 |
| kernels [autovec] dgemm RVV | default | soc | 4 | 1,560,786 | 26,692 | 0.017 | 58.474 | 390,196.50 | - | 0.0840 mac/cycle | 1,560,730 |
| kernels [autovec] sgemm C | default | axi | 4 | 3,239,215 | 828,348 | 0.256 | 3.910 | 809,803.75 | - | 0.0405 mac/cycle | 3,239,022 |
| kernels [autovec] sgemm C | default | soc | 4 | 3,238,444 | 828,348 | 0.256 | 3.910 | 809,611.00 | - | 0.0405 mac/cycle | 3,238,359 |
| kernels [autovec] sgemm RVV | default | axi | 4 | 1,563,198 | 26,692 | 0.017 | 58.564 | 390,799.50 | - | 0.0838 mac/cycle | 1,563,174 |
| kernels [autovec] sgemm RVV | default | soc | 4 | 1,563,001 | 26,692 | 0.017 | 58.557 | 390,750.25 | - | 0.0839 mac/cycle | 1,562,977 |
| kernels [autovec] fir_f32 C | default | axi | 4 | 1,495,420 | 86,081 | 0.058 | 17.372 | 373,855.00 | - | 0.0438 mac/cycle | 1,495,301 |
| kernels [autovec] fir_f32 C | default | soc | 4 | 1,495,279 | 86,081 | 0.058 | 17.371 | 373,819.75 | - | 0.0438 mac/cycle | 1,495,218 |
| kernels [autovec] fir_f32 RVV | default | axi | 4 | 748,169 | 3,487 | 0.005 | 214.560 | 187,042.25 | - | 0.0876 mac/cycle | 748,108 |
| kernels [autovec] fir_f32 RVV | default | soc | 4 | 747,738 | 3,487 | 0.005 | 214.436 | 186,934.50 | - | 0.0876 mac/cycle | 747,702 |
| kernels [autovec] mac_i8 C | default | axi | 4 | 246,320 | 11,339 | 0.046 | 21.723 | 61,580.00 | - | 0.0665 mac/cycle | 246,207 |
| kernels [autovec] mac_i8 C | default | soc | 4 | 246,237 | 11,339 | 0.046 | 21.716 | 61,559.25 | - | 0.0665 mac/cycle | 246,182 |
| kernels [autovec] mac_i8 RVV | default | axi | 4 | 199,256 | 709 | 0.004 | 281.038 | 49,814.00 | - | 0.0822 mac/cycle | 199,224 |
| kernels [autovec] mac_i8 RVV | default | soc | 4 | 199,173 | 709 | 0.004 | 280.921 | 49,793.25 | - | 0.0823 mac/cycle | 199,141 |
| kernels [autovec] mac_i16 C | default | axi | 4 | 103,903 | 4,172 | 0.040 | 24.905 | 25,975.75 | - | 0.0788 mac/cycle | 103,879 |
| kernels [autovec] mac_i16 C | default | soc | 4 | 103,878 | 4,172 | 0.040 | 24.899 | 25,969.50 | - | 0.0789 mac/cycle | 103,854 |
| kernels [autovec] mac_i16 RVV | default | axi | 4 | 93,132 | 588 | 0.006 | 158.388 | 23,283.00 | - | 0.0880 mac/cycle | 93,063 |
| kernels [autovec] mac_i16 RVV | default | soc | 4 | 93,107 | 588 | 0.006 | 158.345 | 23,276.75 | - | 0.0880 mac/cycle | 93,063 |
| kernels [scalar] vadd_i32 C | default | axi | 4 | 78,277 | 32,826 | 0.419 | 2.385 | 19,569.25 | - | 0.0523 elem/cycle | 78,166 |
| kernels [scalar] vadd_i32 C | default | soc | 4 | 78,078 | 32,826 | 0.420 | 2.379 | 19,519.50 | - | 0.0525 elem/cycle | 78,025 |
| kernels [scalar] vadd_i32 RVV | default | axi | 4 | 45,625 | 372 | 0.008 | 122.648 | 11,406.25 | - | 0.0898 elem/cycle | 45,478 |
| kernels [scalar] vadd_i32 RVV | default | soc | 4 | 43,212 | 372 | 0.009 | 116.161 | 10,803.00 | - | 0.0948 elem/cycle | 43,148 |
| kernels [scalar] vadd_i64 C | default | axi | 4 | 39,992 | 16,440 | 0.411 | 2.433 | 9,998.00 | - | 0.0512 elem/cycle | 39,881 |
| kernels [scalar] vadd_i64 C | default | soc | 4 | 39,370 | 16,440 | 0.418 | 2.395 | 9,842.50 | - | 0.0520 elem/cycle | 39,317 |
| kernels [scalar] vadd_i64 RVV | default | axi | 4 | 23,827 | 372 | 0.016 | 64.051 | 5,956.75 | - | 0.0860 elem/cycle | 23,768 |
| kernels [scalar] vadd_i64 RVV | default | soc | 4 | 22,302 | 372 | 0.017 | 59.952 | 5,575.50 | - | 0.0918 elem/cycle | 22,268 |
| kernels [scalar] daxpy C | default | axi | 4 | 60,747 | 14,392 | 0.237 | 4.221 | 15,186.75 | - | 0.0337 elem/cycle | 60,626 |
| kernels [scalar] daxpy C | default | soc | 4 | 59,951 | 14,392 | 0.240 | 4.166 | 14,987.75 | - | 0.0342 elem/cycle | 59,888 |
| kernels [scalar] daxpy RVV | default | axi | 4 | 36,619 | 340 | 0.009 | 107.703 | 9,154.75 | - | 0.0559 elem/cycle | 36,550 |
| kernels [scalar] daxpy RVV | default | soc | 4 | 36,088 | 340 | 0.009 | 106.141 | 9,022.00 | - | 0.0568 elem/cycle | 36,044 |
| kernels [scalar] saxpy C | default | axi | 4 | 132,419 | 28,728 | 0.217 | 4.609 | 33,104.75 | - | 0.0309 elem/cycle | 132,272 |
| kernels [scalar] saxpy C | default | soc | 4 | 131,614 | 28,728 | 0.218 | 4.581 | 32,903.50 | - | 0.0311 elem/cycle | 131,550 |
| kernels [scalar] saxpy RVV | default | axi | 4 | 71,523 | 340 | 0.005 | 210.362 | 17,880.75 | - | 0.0573 elem/cycle | 71,489 |
| kernels [scalar] saxpy RVV | default | soc | 4 | 70,934 | 340 | 0.005 | 208.629 | 17,733.50 | - | 0.0577 elem/cycle | 70,900 |
| kernels [scalar] ddot C | default | axi | 4 | 51,560 | 12,348 | 0.239 | 4.176 | 12,890.00 | - | 0.0397 elem/cycle | 51,490 |
| kernels [scalar] ddot C | default | soc | 4 | 51,427 | 12,348 | 0.240 | 4.165 | 12,856.75 | - | 0.0398 elem/cycle | 51,382 |
| kernels [scalar] ddot RVV | default | axi | 4 | 31,667 | 332 | 0.010 | 95.383 | 7,916.75 | - | 0.0647 elem/cycle | 31,643 |
| kernels [scalar] ddot RVV | default | soc | 4 | 31,617 | 332 | 0.011 | 95.232 | 7,904.25 | - | 0.0648 elem/cycle | 31,593 |
| kernels [scalar] idot_i32 C | default | axi | 4 | 78,027 | 28,732 | 0.368 | 2.716 | 19,506.75 | - | 0.0525 elem/cycle | 77,967 |
| kernels [scalar] idot_i32 C | default | soc | 4 | 78,002 | 28,732 | 0.368 | 2.715 | 19,500.50 | - | 0.0525 elem/cycle | 77,967 |
| kernels [scalar] idot_i32 RVV | default | axi | 4 | 51,697 | 588 | 0.011 | 87.920 | 12,924.25 | - | 0.0792 elem/cycle | 51,627 |
| kernels [scalar] idot_i32 RVV | default | soc | 4 | 51,647 | 588 | 0.011 | 87.835 | 12,911.75 | - | 0.0793 elem/cycle | 51,602 |
| kernels [scalar] memcpy C | default | axi | 4 | 33,263 | 10,355 | 0.311 | 3.212 | 8,315.75 | - | 0.4926 byte/cycle | 33,150 |
| kernels [scalar] memcpy C | default | soc | 4 | 33,122 | 10,355 | 0.313 | 3.199 | 8,280.50 | - | 0.4947 byte/cycle | 33,067 |
| kernels [scalar] memcpy RVV | default | axi | 4 | 13,524 | 275 | 0.020 | 49.178 | 3,381.00 | - | 1.2115 byte/cycle | 13,462 |
| kernels [scalar] memcpy RVV | default | soc | 4 | 13,209 | 275 | 0.021 | 48.033 | 3,302.25 | - | 1.2404 byte/cycle | 13,172 |
| kernels [scalar] memcpy RVV-e8 | default | axi | 4 | 99,270 | 271 | 0.003 | 366.310 | 24,817.50 | - | 0.1650 byte/cycle | 99,122 |
| kernels [scalar] memcpy RVV-e8 | default | soc | 4 | 99,129 | 271 | 0.003 | 365.790 | 24,782.25 | - | 0.1653 byte/cycle | 99,064 |
| kernels [scalar] memset C | default | axi | 4 | 20,914 | 6,264 | 0.300 | 3.339 | 5,228.50 | - | 0.7834 byte/cycle | 20,763 |
| kernels [scalar] memset C | default | soc | 4 | 20,831 | 6,264 | 0.301 | 3.326 | 5,207.75 | - | 0.7865 byte/cycle | 20,763 |
| kernels [scalar] memset RVV | default | axi | 4 | 7,063 | 241 | 0.034 | 29.307 | 1,765.75 | - | 2.3197 byte/cycle | 7,031 |
| kernels [scalar] memset RVV | default | soc | 4 | 7,038 | 241 | 0.034 | 29.203 | 1,759.50 | - | 2.3279 byte/cycle | 7,006 |
| kernels [scalar] memset RVV-e8 | default | axi | 4 | 51,897 | 215 | 0.004 | 241.381 | 12,974.25 | - | 0.3157 byte/cycle | 51,835 |
| kernels [scalar] memset RVV-e8 | default | soc | 4 | 51,872 | 215 | 0.004 | 241.265 | 12,968.00 | - | 0.3159 byte/cycle | 51,835 |
| kernels [scalar] dgemm C | default | axi | 4 | 2,936,230 | 828,348 | 0.282 | 3.545 | 734,057.50 | - | 0.0446 mac/cycle | 2,936,098 |
| kernels [scalar] dgemm C | default | soc | 4 | 2,886,016 | 828,348 | 0.287 | 3.484 | 721,504.00 | - | 0.0454 mac/cycle | 2,885,959 |
| kernels [scalar] dgemm RVV | default | axi | 4 | 1,611,153 | 26,692 | 0.017 | 60.361 | 402,788.25 | - | 0.0814 mac/cycle | 1,610,996 |
| kernels [scalar] dgemm RVV | default | soc | 4 | 1,561,900 | 26,692 | 0.017 | 58.516 | 390,475.00 | - | 0.0839 mac/cycle | 1,561,826 |
| kernels [scalar] sgemm C | default | axi | 4 | 3,238,621 | 828,348 | 0.256 | 3.910 | 809,655.25 | - | 0.0405 mac/cycle | 3,238,464 |
| kernels [scalar] sgemm C | default | soc | 4 | 3,238,248 | 828,348 | 0.256 | 3.909 | 809,562.00 | - | 0.0405 mac/cycle | 3,238,174 |
| kernels [scalar] sgemm RVV | default | axi | 4 | 1,563,716 | 26,692 | 0.017 | 58.584 | 390,929.00 | - | 0.0838 mac/cycle | 1,563,692 |
| kernels [scalar] sgemm RVV | default | soc | 4 | 1,563,177 | 26,692 | 0.017 | 58.564 | 390,794.25 | - | 0.0838 mac/cycle | 1,563,153 |
| kernels [scalar] fir_f32 C | default | axi | 4 | 1,917,344 | 426,053 | 0.222 | 4.500 | 479,336.00 | - | 0.0342 mac/cycle | 1,917,225 |
| kernels [scalar] fir_f32 C | default | soc | 4 | 1,917,178 | 426,053 | 0.222 | 4.500 | 479,294.50 | - | 0.0342 mac/cycle | 1,917,117 |
| kernels [scalar] fir_f32 RVV | default | axi | 4 | 747,857 | 3,487 | 0.005 | 214.470 | 186,964.25 | - | 0.0876 mac/cycle | 747,796 |
| kernels [scalar] fir_f32 RVV | default | soc | 4 | 747,633 | 3,487 | 0.005 | 214.406 | 186,908.25 | - | 0.0877 mac/cycle | 747,597 |
| kernels [scalar] mac_i8 C | default | axi | 4 | 344,261 | 114,747 | 0.333 | 3.000 | 86,065.25 | - | 0.0476 mac/cycle | 344,235 |
| kernels [scalar] mac_i8 C | default | soc | 4 | 344,236 | 114,747 | 0.333 | 3.000 | 86,059.00 | - | 0.0476 mac/cycle | 344,210 |
| kernels [scalar] mac_i8 RVV | default | axi | 4 | 199,169 | 709 | 0.004 | 280.915 | 49,792.25 | - | 0.0823 mac/cycle | 199,137 |
| kernels [scalar] mac_i8 RVV | default | soc | 4 | 199,144 | 709 | 0.004 | 280.880 | 49,786.00 | - | 0.0823 mac/cycle | 199,112 |
| kernels [scalar] mac_i16 C | default | axi | 4 | 172,235 | 57,404 | 0.333 | 3.000 | 43,058.75 | - | 0.0476 mac/cycle | 172,211 |
| kernels [scalar] mac_i16 C | default | soc | 4 | 172,210 | 57,404 | 0.333 | 3.000 | 43,052.50 | - | 0.0476 mac/cycle | 172,186 |
| kernels [scalar] mac_i16 RVV | default | axi | 4 | 93,132 | 588 | 0.006 | 158.388 | 23,283.00 | - | 0.0880 mac/cycle | 93,063 |
| kernels [scalar] mac_i16 RVV | default | soc | 4 | 93,107 | 588 | 0.006 | 158.345 | 23,276.75 | - | 0.0880 mac/cycle | 93,063 |
| micro_dmem [default] empty | default | axi | 4096 | 92 | 21 | 0.228 | 4.381 | 0.02 | (window) | - | 60 |
| micro_dmem [default] empty | default | soc | 4096 | 67 | 21 | 0.313 | 3.190 | 0.02 | (window) | - | 35 |
| micro_dmem [default] chase_rand_1k | default | axi | 4096 | 12,701 | 4,247 | 0.334 | 2.991 | 3.10 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_1k | default | soc | 4096 | 12,676 | 4,247 | 0.335 | 2.985 | 3.09 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_2k | default | axi | 4096 | 12,701 | 4,247 | 0.334 | 2.991 | 3.10 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_2k | default | soc | 4096 | 12,676 | 4,247 | 0.335 | 2.985 | 3.09 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_4k | default | axi | 4096 | 12,701 | 4,247 | 0.334 | 2.991 | 3.10 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_4k | default | soc | 4096 | 12,676 | 4,247 | 0.335 | 2.985 | 3.09 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_8k | default | axi | 4096 | 12,701 | 4,247 | 0.334 | 2.991 | 3.10 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_8k | default | soc | 4096 | 12,676 | 4,247 | 0.335 | 2.985 | 3.09 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_12k | default | axi | 4096 | 12,701 | 4,247 | 0.334 | 2.991 | 3.10 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_12k | default | soc | 4096 | 12,676 | 4,247 | 0.335 | 2.985 | 3.09 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_rand_16k | default | axi | 4096 | 13,040 | 4,247 | 0.326 | 3.070 | 3.18 | 3.16 | - | 12,903 |
| micro_dmem [default] chase_rand_16k | default | soc | 4096 | 12,782 | 4,247 | 0.332 | 3.010 | 3.12 | 3.10 | - | 12,720 |
| micro_dmem [default] chase_rand_20k | default | axi | 4096 | 71,396 | 4,247 | 0.059 | 16.811 | 17.43 | 17.41 | - | 71,259 |
| micro_dmem [default] chase_rand_20k | default | soc | 4096 | 30,613 | 4,247 | 0.139 | 7.208 | 7.47 | 7.46 | - | 30,551 |
| micro_dmem [default] chase_rand_24k | default | axi | 4096 | 104,336 | 4,247 | 0.041 | 24.567 | 25.47 | 25.45 | - | 104,199 |
| micro_dmem [default] chase_rand_24k | default | soc | 4096 | 40,678 | 4,247 | 0.104 | 9.578 | 9.93 | 9.91 | - | 40,616 |
| micro_dmem [default] chase_rand_32k | default | axi | 4096 | 135,296 | 4,247 | 0.031 | 31.857 | 33.03 | 33.01 | - | 135,159 |
| micro_dmem [default] chase_rand_32k | default | soc | 4096 | 50,138 | 4,247 | 0.085 | 11.806 | 12.24 | 12.22 | - | 50,076 |
| micro_dmem [default] chase_rand_64k | default | axi | 4096 | 158,372 | 4,247 | 0.027 | 37.290 | 38.67 | 38.64 | - | 158,235 |
| micro_dmem [default] chase_rand_64k | default | soc | 4096 | 57,189 | 4,247 | 0.074 | 13.466 | 13.96 | 13.95 | - | 57,127 |
| micro_dmem [default] chase_rand_128k | default | axi | 4096 | 160,352 | 4,247 | 0.026 | 37.757 | 39.15 | 39.13 | - | 160,215 |
| micro_dmem [default] chase_rand_128k | default | soc | 4096 | 57,794 | 4,247 | 0.073 | 13.608 | 14.11 | 14.09 | - | 57,732 |
| micro_dmem [default] chase_rand_256k | default | axi | 4096 | 160,352 | 4,247 | 0.026 | 37.757 | 39.15 | 39.13 | - | 160,215 |
| micro_dmem [default] chase_rand_256k | default | soc | 4096 | 57,794 | 4,247 | 0.073 | 13.608 | 14.11 | 14.09 | - | 57,732 |
| micro_dmem [default] chase_seq_4k | default | axi | 4096 | 12,701 | 4,247 | 0.334 | 2.991 | 3.10 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_seq_4k | default | soc | 4096 | 12,676 | 4,247 | 0.335 | 2.985 | 3.09 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_seq_8k | default | axi | 4096 | 12,737 | 4,247 | 0.333 | 2.999 | 3.11 | 3.09 | - | 12,636 |
| micro_dmem [default] chase_seq_8k | default | soc | 4096 | 12,687 | 4,247 | 0.335 | 2.987 | 3.10 | 3.08 | - | 12,636 |
| micro_dmem [default] chase_seq_16k | default | axi | 4096 | 13,040 | 4,247 | 0.326 | 3.070 | 3.18 | 3.16 | - | 12,903 |
| micro_dmem [default] chase_seq_16k | default | soc | 4096 | 12,782 | 4,247 | 0.332 | 3.010 | 3.12 | 3.10 | - | 12,720 |
| micro_dmem [default] chase_seq_32k | default | axi | 4096 | 111,716 | 4,247 | 0.038 | 26.305 | 27.27 | 27.25 | - | 111,579 |
| micro_dmem [default] chase_seq_32k | default | soc | 4096 | 42,933 | 4,247 | 0.099 | 10.109 | 10.48 | 10.47 | - | 42,871 |
| micro_dmem [default] stream_ld | default | axi | 4096 | 30,352 | 4,830 | 0.159 | 6.284 | 7.41 | 7.39 | - | 30,285 |
| micro_dmem [default] stream_ld | default | soc | 4096 | 17,502 | 4,830 | 0.276 | 3.624 | 4.27 | 4.26 | - | 17,460 |
| micro_dmem [default] stream_st | default | axi | 4096 | 53,328 | 4,825 | 0.090 | 11.052 | 13.02 | 13.00 | - | 53,179 |
| micro_dmem [default] stream_st | default | soc | 4096 | 25,603 | 4,825 | 0.188 | 5.306 | 6.25 | 6.23 | - | 25,537 |
| micro_imem [default] empty | default | axi | 49152 | 91 | 19 | 0.209 | 4.789 | 0.00 | (window) | - | 29 |
| micro_imem [default] empty | default | soc | 49152 | 66 | 19 | 0.288 | 3.474 | 0.00 | (window) | - | 29 |
| micro_imem [default] ifoot_1k | default | axi | 49152 | 101,043 | 49,942 | 0.494 | 2.023 | 2.06 | 2.05 | - | 101,021 |
| micro_imem [default] ifoot_1k | default | soc | 49152 | 101,043 | 49,942 | 0.494 | 2.023 | 2.06 | 2.05 | - | 101,021 |
| micro_imem [default] ifoot_2k | default | axi | 49152 | 99,699 | 49,558 | 0.497 | 2.012 | 2.03 | 2.03 | - | 99,677 |
| micro_imem [default] ifoot_2k | default | soc | 49152 | 99,699 | 49,558 | 0.497 | 2.012 | 2.03 | 2.03 | - | 99,677 |
| micro_imem [default] ifoot_3k | default | axi | 49152 | 99,251 | 49,430 | 0.498 | 2.008 | 2.02 | 2.02 | - | 99,229 |
| micro_imem [default] ifoot_3k | default | soc | 49152 | 99,251 | 49,430 | 0.498 | 2.008 | 2.02 | 2.02 | - | 99,229 |
| micro_imem [default] ifoot_4k | default | axi | 49152 | 99,027 | 49,366 | 0.499 | 2.006 | 2.01 | 2.01 | - | 99,005 |
| micro_imem [default] ifoot_4k | default | soc | 49152 | 99,027 | 49,366 | 0.499 | 2.006 | 2.01 | 2.01 | - | 99,005 |
| micro_imem [default] ifoot_6k | default | axi | 49152 | 103,699 | 49,302 | 0.475 | 2.103 | 2.11 | 2.11 | - | 103,677 |
| micro_imem [default] ifoot_6k | default | soc | 49152 | 100,299 | 49,302 | 0.492 | 2.034 | 2.04 | 2.04 | - | 100,277 |
| micro_imem [default] ifoot_8k | default | axi | 49152 | 102,579 | 49,270 | 0.480 | 2.082 | 2.09 | 2.09 | - | 102,557 |
| micro_imem [default] ifoot_8k | default | soc | 49152 | 99,879 | 49,270 | 0.493 | 2.027 | 2.03 | 2.03 | - | 99,857 |
| micro_imem [default] ifoot_12k | default | axi | 49152 | 172,811 | 49,238 | 0.285 | 3.510 | 3.52 | 3.51 | - | 172,789 |
| micro_imem [default] ifoot_12k | default | soc | 49152 | 121,261 | 49,238 | 0.406 | 2.463 | 2.47 | 2.47 | - | 121,239 |
| micro_imem [default] ifoot_16k | default | axi | 49152 | 182,439 | 49,222 | 0.270 | 3.706 | 3.71 | 3.71 | - | 182,417 |
| micro_imem [default] ifoot_16k | default | soc | 49152 | 124,164 | 49,222 | 0.396 | 2.523 | 2.53 | 2.52 | - | 124,142 |
| micro_imem [default] ifoot_24k | default | axi | 49152 | 191,311 | 49,206 | 0.257 | 3.888 | 3.89 | 3.89 | - | 191,289 |
| micro_imem [default] ifoot_24k | default | soc | 49152 | 126,836 | 49,206 | 0.388 | 2.578 | 2.58 | 2.58 | - | 126,814 |
| micro_imem [default] ifoot_32k | default | axi | 49152 | 195,675 | 49,198 | 0.251 | 3.977 | 3.98 | 3.98 | - | 195,653 |
| micro_imem [default] ifoot_32k | default | soc | 49152 | 128,150 | 49,198 | 0.384 | 2.605 | 2.61 | 2.61 | - | 128,128 |
| micro_pipe [default] empty | default | axi | 4096 | 91 | 19 | 0.209 | 4.789 | 0.02 | (window) | - | 29 |
| micro_pipe [default] empty | default | soc | 4096 | 66 | 19 | 0.288 | 3.474 | 0.02 | (window) | - | 29 |
| micro_pipe [default] loop | default | axi | 4096 | 24,668 | 8,211 | 0.333 | 3.004 | 6.02 | 6.00 | - | 24,599 |
| micro_pipe [default] loop | default | soc | 4096 | 24,643 | 8,211 | 0.333 | 3.001 | 6.02 | 6.00 | - | 24,599 |
| micro_pipe [default] alu32_dep | default | axi | 4096 | 8,397 | 4,154 | 0.495 | 2.021 | 2.05 | 2.03 | - | 8,328 |
| micro_pipe [default] alu32_dep | default | soc | 4096 | 8,372 | 4,154 | 0.496 | 2.015 | 2.04 | 2.03 | - | 8,328 |
| micro_pipe [default] alu32_indep | default | axi | 4096 | 8,401 | 4,156 | 0.495 | 2.021 | 2.05 | 2.03 | - | 8,332 |
| micro_pipe [default] alu32_indep | default | soc | 4096 | 8,376 | 4,156 | 0.496 | 2.015 | 2.04 | 2.03 | - | 8,332 |
| micro_pipe [default] alu16_dep | default | axi | 4096 | 8,398 | 4,154 | 0.495 | 2.022 | 2.05 | 2.03 | - | 8,328 |
| micro_pipe [default] alu16_dep | default | soc | 4096 | 8,373 | 4,154 | 0.496 | 2.016 | 2.04 | 2.03 | - | 8,328 |
| micro_pipe [default] alu32_straddle | default | axi | 4096 | 16,658 | 4,155 | 0.249 | 4.009 | 4.07 | 4.04 | - | 16,624 |
| micro_pipe [default] alu32_straddle | default | soc | 4096 | 16,633 | 4,155 | 0.250 | 4.003 | 4.06 | 4.04 | - | 16,599 |
| micro_pipe [default] br_nt | default | axi | 4096 | 8,396 | 4,153 | 0.495 | 2.022 | 2.05 | 2.03 | - | 8,362 |
| micro_pipe [default] br_nt | default | soc | 4096 | 8,371 | 4,153 | 0.496 | 2.016 | 2.04 | 2.03 | - | 8,337 |
| micro_pipe [default] br_taken | default | axi | 4096 | 16,590 | 4,154 | 0.250 | 3.994 | 4.05 | 4.03 | - | 16,556 |
| micro_pipe [default] br_taken | default | soc | 4096 | 16,565 | 4,154 | 0.251 | 3.988 | 4.04 | 4.03 | - | 16,531 |
| micro_pipe [default] jal | default | axi | 4096 | 16,565 | 4,149 | 0.250 | 3.993 | 4.04 | 4.02 | - | 16,541 |
| micro_pipe [default] jal | default | soc | 4096 | 16,540 | 4,149 | 0.251 | 3.987 | 4.04 | 4.02 | - | 16,516 |
| micro_pipe [default] call_ret | default | axi | 4096 | 41,155 | 12,342 | 0.300 | 3.335 | 10.05 | 10.03 | - | 41,085 |
| micro_pipe [default] call_ret | default | soc | 4096 | 41,130 | 12,342 | 0.300 | 3.333 | 10.04 | 10.03 | - | 41,085 |
| micro_pipe [default] jalr_call_ret | default | axi | 4096 | 41,123 | 12,344 | 0.300 | 3.331 | 10.04 | 10.02 | - | 41,089 |
| micro_pipe [default] jalr_call_ret | default | soc | 4096 | 41,123 | 12,344 | 0.300 | 3.331 | 10.04 | 10.02 | - | 41,089 |
| micro_pipe [default] brpat_never | default | axi | 4096 | 35,299 | 17,558 | 0.497 | 2.010 | 8.62 | 8.60 | - | 35,231 |
| micro_pipe [default] brpat_never | default | soc | 4096 | 35,274 | 17,558 | 0.498 | 2.009 | 8.61 | 8.60 | - | 35,231 |
| micro_pipe [default] brpat_always | default | axi | 4096 | 43,455 | 17,558 | 0.404 | 2.475 | 10.61 | 10.59 | - | 43,423 |
| micro_pipe [default] brpat_always | default | soc | 4096 | 43,455 | 17,558 | 0.404 | 2.475 | 10.61 | 10.59 | - | 43,423 |
| micro_pipe [default] brpat_alt | default | axi | 4096 | 39,359 | 17,558 | 0.446 | 2.242 | 9.61 | 9.59 | - | 39,327 |
| micro_pipe [default] brpat_alt | default | soc | 4096 | 39,359 | 17,558 | 0.446 | 2.242 | 9.61 | 9.59 | - | 39,327 |
| micro_pipe [default] brpat_rand | default | axi | 4096 | 39,359 | 17,558 | 0.446 | 2.242 | 9.61 | 9.59 | - | 39,327 |
| micro_pipe [default] brpat_rand | default | soc | 4096 | 39,359 | 17,558 | 0.446 | 2.242 | 9.61 | 9.59 | - | 39,327 |
| micro_pipe [default] ld_dep | default | axi | 4096 | 12,421 | 4,149 | 0.334 | 2.994 | 3.03 | 3.01 | - | 12,393 |
| micro_pipe [default] ld_dep | default | soc | 4096 | 12,421 | 4,149 | 0.334 | 2.994 | 3.03 | 3.02 | - | 12,393 |
| micro_pipe [default] ld_indep | default | axi | 4096 | 10,432 | 4,155 | 0.398 | 2.511 | 2.55 | 2.52 | - | 10,408 |
| micro_pipe [default] ld_indep | default | soc | 4096 | 10,407 | 4,155 | 0.399 | 2.505 | 2.54 | 2.52 | - | 10,383 |
| micro_pipe [default] ld_use1 | default | axi | 4096 | 16,566 | 8,247 | 0.498 | 2.009 | 4.04 | 4.02 | - | 16,507 |
| micro_pipe [default] ld_use1 | default | soc | 4096 | 16,541 | 8,247 | 0.499 | 2.006 | 4.04 | 4.02 | - | 16,507 |
| micro_pipe [default] ld_use2 | default | axi | 4096 | 16,569 | 8,247 | 0.498 | 2.009 | 4.05 | 4.02 | - | 16,510 |
| micro_pipe [default] ld_use2 | default | soc | 4096 | 16,544 | 8,247 | 0.498 | 2.006 | 4.04 | 4.02 | - | 16,510 |
| micro_pipe [default] st | default | axi | 4096 | 10,434 | 4,152 | 0.398 | 2.513 | 2.55 | 2.53 | - | 10,408 |
| micro_pipe [default] st | default | soc | 4096 | 10,409 | 4,152 | 0.399 | 2.507 | 2.54 | 2.53 | - | 10,383 |
| micro_pipe [default] rdcycle | default | axi | 4096 | 8,408 | 4,150 | 0.494 | 2.026 | 2.05 | 2.03 | - | 8,313 |
| micro_pipe [default] rdcycle | default | soc | 4096 | 8,358 | 4,150 | 0.497 | 2.014 | 2.04 | 2.02 | - | 8,313 |
| micro_pipe [default] rdtime | default | axi | 4096 | 8,384 | 4,149 | 0.495 | 2.021 | 2.05 | 2.02 | - | 8,315 |
| micro_pipe [default] rdtime | default | soc | 4096 | 8,359 | 4,149 | 0.496 | 2.015 | 2.04 | 2.02 | - | 8,315 |
| micro_pipe [default] csrr | default | axi | 4096 | 8,373 | 4,148 | 0.495 | 2.019 | 2.04 | 2.02 | - | 8,349 |
| micro_pipe [default] csrr | default | soc | 4096 | 8,348 | 4,148 | 0.497 | 2.013 | 2.04 | 2.02 | - | 8,324 |
| micro_pipe [default] csrw | default | axi | 4096 | 8,395 | 4,153 | 0.495 | 2.021 | 2.05 | 2.03 | - | 8,326 |
| micro_pipe [default] csrw | default | soc | 4096 | 8,370 | 4,153 | 0.496 | 2.015 | 2.04 | 2.03 | - | 8,326 |
| micro_pipe [default] csrrw | default | axi | 4096 | 8,380 | 4,150 | 0.495 | 2.019 | 2.05 | 2.02 | - | 8,313 |
| micro_pipe [default] csrrw | default | soc | 4096 | 8,355 | 4,150 | 0.497 | 2.013 | 2.04 | 2.02 | - | 8,313 |
| micro_pipe [default] fence | default | axi | 4096 | 8,347 | 4,148 | 0.497 | 2.012 | 2.04 | 2.02 | - | 8,313 |
| micro_pipe [default] fence | default | soc | 4096 | 8,347 | 4,148 | 0.497 | 2.012 | 2.04 | 2.02 | - | 8,313 |
| micro_units [default] empty | default | axi | 1024 | 92 | 21 | 0.228 | 4.381 | 0.09 | (window) | - | 25 |
| micro_units [default] empty | default | soc | 1024 | 67 | 21 | 0.313 | 3.190 | 0.07 | (window) | - | 25 |
| micro_units [default] mul_dep | default | axi | 1024 | 4,327 | 1,086 | 0.251 | 3.984 | 4.23 | 4.14 | - | 4,293 |
| micro_units [default] mul_dep | default | soc | 1024 | 4,302 | 1,086 | 0.252 | 3.961 | 4.20 | 4.14 | - | 4,268 |
| micro_units [default] mul_indep | default | axi | 1024 | 4,367 | 1,086 | 0.249 | 4.021 | 4.26 | 4.17 | - | 4,235 |
| micro_units [default] mul_indep | default | soc | 1024 | 4,292 | 1,086 | 0.253 | 3.952 | 4.19 | 4.13 | - | 4,235 |
| micro_units [default] div_dep | default | axi | 1024 | 37,100 | 1,083 | 0.029 | 34.257 | 36.23 | 36.14 | - | 37,004 |
| micro_units [default] div_dep | default | soc | 1024 | 37,050 | 1,083 | 0.029 | 34.211 | 36.18 | 36.12 | - | 37,004 |
| micro_units [default] div_indep | default | axi | 1024 | 37,072 | 1,083 | 0.029 | 34.231 | 36.20 | 36.11 | - | 37,038 |
| micro_units [default] div_indep | default | soc | 1024 | 37,047 | 1,083 | 0.029 | 34.208 | 36.18 | 36.11 | - | 37,013 |
| micro_units [default] div_short | default | axi | 1024 | 4,279 | 1,078 | 0.252 | 3.969 | 4.18 | 4.09 | - | 4,255 |
| micro_units [default] div_short | default | soc | 1024 | 4,254 | 1,078 | 0.253 | 3.946 | 4.15 | 4.09 | - | 4,230 |
| micro_units [default] divw_dep | default | axi | 1024 | 20,709 | 1,079 | 0.052 | 19.193 | 20.22 | 20.13 | - | 20,605 |
| micro_units [default] divw_dep | default | soc | 1024 | 20,659 | 1,079 | 0.052 | 19.146 | 20.17 | 20.11 | - | 20,605 |
| micro_units [default] rem_indep | default | axi | 1024 | 36,036 | 1,081 | 0.030 | 33.336 | 35.19 | 35.10 | - | 36,010 |
| micro_units [default] rem_indep | default | soc | 1024 | 36,011 | 1,081 | 0.030 | 33.313 | 35.17 | 35.10 | - | 35,985 |
| micro_units [default] fadd_d_dep | default | axi | 1024 | 6,447 | 1,080 | 0.168 | 5.969 | 6.30 | 6.21 | - | 6,386 |
| micro_units [default] fadd_d_dep | default | soc | 1024 | 6,347 | 1,080 | 0.170 | 5.877 | 6.20 | 6.13 | - | 6,311 |
| micro_units [default] fadd_d_indep | default | axi | 1024 | 6,333 | 1,077 | 0.170 | 5.880 | 6.18 | 6.09 | - | 6,307 |
| micro_units [default] fadd_d_indep | default | soc | 1024 | 6,308 | 1,077 | 0.171 | 5.857 | 6.16 | 6.09 | - | 6,282 |
| micro_units [default] fmul_d_dep | default | axi | 1024 | 6,381 | 1,080 | 0.169 | 5.908 | 6.23 | 6.14 | - | 6,278 |
| micro_units [default] fmul_d_dep | default | soc | 1024 | 6,331 | 1,080 | 0.171 | 5.862 | 6.18 | 6.12 | - | 6,278 |
| micro_units [default] fmadd_d_dep | default | axi | 1024 | 8,416 | 1,084 | 0.129 | 7.764 | 8.22 | 8.13 | - | 8,384 |
| micro_units [default] fmadd_d_dep | default | soc | 1024 | 8,391 | 1,084 | 0.129 | 7.741 | 8.19 | 8.13 | - | 8,359 |
| micro_units [default] fdiv_d_dep | default | axi | 1024 | 33,994 | 1,080 | 0.032 | 31.476 | 33.20 | 33.11 | - | 33,926 |
| micro_units [default] fdiv_d_dep | default | soc | 1024 | 33,969 | 1,080 | 0.032 | 31.453 | 33.17 | 33.11 | - | 33,926 |
| micro_units [default] fdiv_d_indep | default | axi | 1024 | 33,987 | 1,079 | 0.032 | 31.499 | 33.19 | 33.10 | - | 33,955 |
| micro_units [default] fdiv_d_indep | default | soc | 1024 | 33,962 | 1,079 | 0.032 | 31.475 | 33.17 | 33.10 | - | 33,930 |
| micro_units [default] fsqrt_d_dep | default | axi | 1024 | 34,012 | 1,076 | 0.032 | 31.610 | 33.21 | 33.12 | - | 33,914 |
| micro_units [default] fsqrt_d_dep | default | soc | 1024 | 33,962 | 1,076 | 0.032 | 31.563 | 33.17 | 33.10 | - | 33,914 |
| micro_units [default] fsqrt_d_indep | default | axi | 1024 | 33,950 | 1,077 | 0.032 | 31.523 | 33.15 | 33.06 | - | 33,922 |
| micro_units [default] fsqrt_d_indep | default | soc | 1024 | 33,950 | 1,077 | 0.032 | 31.523 | 33.15 | 33.09 | - | 33,922 |
| micro_units [default] fdiv_s_dep | default | axi | 1024 | 18,640 | 1,082 | 0.058 | 17.227 | 18.20 | 18.11 | - | 18,608 |
| micro_units [default] fdiv_s_dep | default | soc | 1024 | 18,615 | 1,082 | 0.058 | 17.204 | 18.18 | 18.11 | - | 18,583 |
| micro_units [default] fsqrt_s_dep | default | axi | 1024 | 18,628 | 1,078 | 0.058 | 17.280 | 18.19 | 18.10 | - | 18,596 |
| micro_units [default] fsqrt_s_dep | default | soc | 1024 | 18,603 | 1,078 | 0.058 | 17.257 | 18.17 | 18.10 | - | 18,571 |
| micro_vec [default] empty | default | axi | 256 | 131 | 22 | 0.168 | 5.955 | 0.51 | (window) | - | 27 |
| micro_vec [default] empty | default | soc | 256 | 81 | 22 | 0.272 | 3.682 | 0.32 | (window) | - | 27 |
| micro_vec [default] vsetvli_same | default | axi | 256 | 648 | 293 | 0.452 | 2.212 | 2.53 | 2.02 | - | 588 |
| micro_vec [default] vsetvli_same | default | soc | 256 | 623 | 293 | 0.470 | 2.126 | 2.43 | 2.12 | - | 588 |
| micro_vec [default] vsetvli_toggle | default | axi | 256 | 662 | 293 | 0.443 | 2.259 | 2.59 | 2.07 | - | 625 |
| micro_vec [default] vsetvli_toggle | default | soc | 256 | 637 | 293 | 0.460 | 2.174 | 2.49 | 2.17 | - | 600 |
| micro_vec [default] vadd_e8_vl1 | default | axi | 256 | 1,928 | 292 | 0.151 | 6.603 | 7.53 | 7.02 | - | 1,861 |
| micro_vec [default] vadd_e8_vl1 | default | soc | 256 | 1,903 | 292 | 0.153 | 6.517 | 7.43 | 7.12 | - | 1,861 |
| micro_vec [default] vadd_e8_vl2 | default | axi | 256 | 2,149 | 292 | 0.136 | 7.360 | 8.39 | 7.88 | - | 2,117 |
| micro_vec [default] vadd_e8_vl2 | default | soc | 256 | 2,149 | 292 | 0.136 | 7.360 | 8.39 | 8.08 | - | 2,117 |
| micro_vec [default] vadd_e8_vl4 | default | axi | 256 | 2,661 | 292 | 0.110 | 9.113 | 10.39 | 9.88 | - | 2,629 |
| micro_vec [default] vadd_e8_vl4 | default | soc | 256 | 2,661 | 292 | 0.110 | 9.113 | 10.39 | 10.08 | - | 2,629 |
| micro_vec [default] vadd_e8_vl8 | default | axi | 256 | 3,685 | 292 | 0.079 | 12.620 | 14.39 | 13.88 | - | 3,653 |
| micro_vec [default] vadd_e8_vl8 | default | soc | 256 | 3,685 | 292 | 0.079 | 12.620 | 14.39 | 14.08 | - | 3,653 |
| micro_vec [default] vadd_e8_vl16 | default | axi | 256 | 5,733 | 292 | 0.051 | 19.634 | 22.39 | 21.88 | - | 5,701 |
| micro_vec [default] vadd_e8_vl16 | default | soc | 256 | 5,733 | 292 | 0.051 | 19.634 | 22.39 | 22.08 | - | 5,701 |
| micro_vec [default] vadd_e8_vl32 | default | axi | 256 | 9,829 | 292 | 0.030 | 33.661 | 38.39 | 37.88 | - | 9,797 |
| micro_vec [default] vadd_e8_vl32 | default | soc | 256 | 9,829 | 292 | 0.030 | 33.661 | 38.39 | 38.08 | - | 9,797 |
| micro_vec [default] vadd_e8_vl64 | default | axi | 256 | 18,021 | 292 | 0.016 | 61.716 | 70.39 | 69.88 | - | 17,989 |
| micro_vec [default] vadd_e8_vl64 | default | soc | 256 | 18,021 | 292 | 0.016 | 61.716 | 70.39 | 70.08 | - | 17,989 |
| micro_vec [default] vadd_e8_vl128 | default | axi | 256 | 34,405 | 292 | 0.008 | 117.825 | 134.39 | 133.88 | - | 34,373 |
| micro_vec [default] vadd_e8_vl128 | default | soc | 256 | 34,405 | 292 | 0.008 | 117.825 | 134.39 | 134.08 | - | 34,373 |
| micro_vec [default] vadd_e8_vl256 | default | axi | 256 | 67,173 | 292 | 0.004 | 230.045 | 262.39 | 261.88 | - | 67,141 |
| micro_vec [default] vadd_e8_vl256 | default | soc | 256 | 67,173 | 292 | 0.004 | 230.045 | 262.39 | 262.08 | - | 67,141 |
| micro_vec [default] vadd_e8_vl512 | default | axi | 256 | 132,709 | 292 | 0.002 | 454.483 | 518.39 | 517.88 | - | 132,677 |
| micro_vec [default] vadd_e8_vl512 | default | soc | 256 | 132,709 | 292 | 0.002 | 454.483 | 518.39 | 518.08 | - | 132,677 |
| micro_vec [default] vle8_vl1 | default | axi | 256 | 1,295 | 292 | 0.225 | 4.435 | 5.06 | 4.55 | - | 1,264 |
| micro_vec [default] vle8_vl1 | default | soc | 256 | 1,270 | 292 | 0.230 | 4.349 | 4.96 | 4.64 | - | 1,239 |
| micro_vec [default] vle8_vl2 | default | axi | 256 | 2,027 | 292 | 0.144 | 6.942 | 7.92 | 7.41 | - | 1,996 |
| micro_vec [default] vle8_vl2 | default | soc | 256 | 2,027 | 292 | 0.144 | 6.942 | 7.92 | 7.60 | - | 1,996 |
| micro_vec [default] vle8_vl4 | default | axi | 256 | 3,563 | 292 | 0.082 | 12.202 | 13.92 | 13.41 | - | 3,532 |
| micro_vec [default] vle8_vl4 | default | soc | 256 | 3,563 | 292 | 0.082 | 12.202 | 13.92 | 13.60 | - | 3,532 |
| micro_vec [default] vle8_vl8 | default | axi | 256 | 6,635 | 292 | 0.044 | 22.723 | 25.92 | 25.41 | - | 6,604 |
| micro_vec [default] vle8_vl8 | default | soc | 256 | 6,635 | 292 | 0.044 | 22.723 | 25.92 | 25.60 | - | 6,604 |
| micro_vec [default] vle8_vl16 | default | axi | 256 | 12,779 | 292 | 0.023 | 43.764 | 49.92 | 49.41 | - | 12,748 |
| micro_vec [default] vle8_vl16 | default | soc | 256 | 12,779 | 292 | 0.023 | 43.764 | 49.92 | 49.60 | - | 12,748 |
| micro_vec [default] vle8_vl32 | default | axi | 256 | 25,067 | 292 | 0.012 | 85.846 | 97.92 | 97.41 | - | 25,036 |
| micro_vec [default] vle8_vl32 | default | soc | 256 | 25,067 | 292 | 0.012 | 85.846 | 97.92 | 97.60 | - | 25,036 |
| micro_vec [default] vle8_vl64 | default | axi | 256 | 49,643 | 292 | 0.006 | 170.010 | 193.92 | 193.41 | - | 49,612 |
| micro_vec [default] vle8_vl64 | default | soc | 256 | 49,643 | 292 | 0.006 | 170.010 | 193.92 | 193.60 | - | 49,612 |
| micro_vec [default] vle8_vl128 | default | axi | 256 | 98,795 | 292 | 0.003 | 338.339 | 385.92 | 385.41 | - | 98,764 |
| micro_vec [default] vle8_vl128 | default | soc | 256 | 98,795 | 292 | 0.003 | 338.339 | 385.92 | 385.60 | - | 98,764 |
| micro_vec [default] vle8_vl256 | default | axi | 256 | 197,099 | 292 | 0.001 | 674.997 | 769.92 | 769.41 | - | 197,068 |
| micro_vec [default] vle8_vl256 | default | soc | 256 | 197,099 | 292 | 0.001 | 674.997 | 769.92 | 769.60 | - | 197,068 |
| micro_vec [default] vle8_vl512 | default | axi | 256 | 393,707 | 292 | 0.001 | 1348.312 | 1,537.92 | 1,537.41 | - | 393,676 |
| micro_vec [default] vle8_vl512 | default | soc | 256 | 393,707 | 292 | 0.001 | 1348.312 | 1,537.92 | 1,537.60 | - | 393,676 |
| micro_vec [default] vse8_vl1 | default | axi | 256 | 1,299 | 294 | 0.226 | 4.418 | 5.07 | 4.56 | - | 1,228 |
| micro_vec [default] vse8_vl1 | default | soc | 256 | 1,274 | 294 | 0.231 | 4.333 | 4.98 | 4.66 | - | 1,228 |
| micro_vec [default] vse8_vl8 | default | axi | 256 | 6,639 | 294 | 0.044 | 22.582 | 25.93 | 25.42 | - | 6,604 |
| micro_vec [default] vse8_vl8 | default | soc | 256 | 6,639 | 294 | 0.044 | 22.582 | 25.93 | 25.62 | - | 6,604 |
| micro_vec [default] vse8_vl64 | default | axi | 256 | 49,647 | 294 | 0.006 | 168.867 | 193.93 | 193.42 | - | 49,612 |
| micro_vec [default] vse8_vl64 | default | soc | 256 | 49,647 | 294 | 0.006 | 168.867 | 193.93 | 193.62 | - | 49,612 |
| micro_vec [default] vse8_vl512 | default | axi | 256 | 393,711 | 294 | 0.001 | 1339.153 | 1,537.93 | 1,537.42 | - | 393,676 |
| micro_vec [default] vse8_vl512 | default | soc | 256 | 393,711 | 294 | 0.001 | 1339.153 | 1,537.93 | 1,537.62 | - | 393,676 |
| micro_vec [default] vadd_e64_vl8 | default | axi | 256 | 3,715 | 290 | 0.078 | 12.810 | 14.51 | 14.00 | - | 3,653 |
| micro_vec [default] vadd_e64_vl8 | default | soc | 256 | 3,690 | 290 | 0.079 | 12.724 | 14.41 | 14.10 | - | 3,653 |
| micro_vec [default] vmul_e64_vl8 | default | axi | 256 | 18,052 | 290 | 0.016 | 62.248 | 70.52 | 70.00 | - | 18,026 |
| micro_vec [default] vmul_e64_vl8 | default | soc | 256 | 18,027 | 290 | 0.016 | 62.162 | 70.42 | 70.10 | - | 18,001 |
| micro_vec [default] vfadd_e64_vl8 | default | axi | 256 | 13,969 | 292 | 0.021 | 47.839 | 54.57 | 54.05 | - | 13,934 |
| micro_vec [default] vfadd_e64_vl8 | default | soc | 256 | 13,944 | 292 | 0.021 | 47.753 | 54.47 | 54.15 | - | 13,909 |
| micro_vec [default] vredsum_e64_vl8 | default | axi | 256 | 4,240 | 292 | 0.069 | 14.521 | 16.56 | 16.05 | - | 4,170 |
| micro_vec [default] vredsum_e64_vl8 | default | soc | 256 | 4,215 | 292 | 0.069 | 14.435 | 16.46 | 16.15 | - | 4,170 |
| sha256chain [sdk] sha256 plain C | default | axi | 1024 | 10,156,468 | 3,714,106 | 0.366 | 2.735 | 9,918.43 | - | 0.0032 B/cycle | 10,156,440 |
| sha256chain [sdk] sha256 plain C | default | soc | 1024 | 10,156,268 | 3,714,106 | 0.366 | 2.735 | 9,918.23 | - | 0.0032 B/cycle | 10,156,240 |
| sha256chain [sdk] sha256 Zknh | default | axi | 1024 | 6,915,525 | 2,731,068 | 0.395 | 2.532 | 6,753.44 | - | 0.0047 B/cycle | 6,915,490 |
| sha256chain [sdk] sha256 Zknh | default | soc | 1024 | 6,915,325 | 2,731,068 | 0.395 | 2.532 | 6,753.25 | - | 0.0047 B/cycle | 6,915,290 |
| sha256chain [sdk] sha256 RVV x16 (multi-buffer) | default | axi | 1024 | 4,754,072 | 219,780 | 0.046 | 21.631 | 4,642.65 | - | 0.0069 B/cycle | 4,753,975 |
| sha256chain [sdk] sha256 RVV x16 (multi-buffer) | default | soc | 1024 | 4,753,403 | 219,780 | 0.046 | 21.628 | 4,642.00 | - | 0.0069 B/cycle | 4,753,356 |
| sha256chain [sdk] sha256 accel sigil_sha256_block | default | axi | 1024 | 585,847 | 162,844 | 0.278 | 3.598 | 572.12 | - | 0.0559 B/cycle | 585,812 |
| sha256chain [sdk] sha256 accel sigil_sha256_block | default | soc | 1024 | 585,822 | 162,844 | 0.278 | 3.597 | 572.09 | - | 0.0559 B/cycle | 585,787 |
| sha256chain [sdk] sha256 accel sigil_sha256 | default | axi | 1024 | 2,860,326 | 1,029,153 | 0.360 | 2.779 | 2,793.29 | - | 0.0115 B/cycle | 2,860,302 |
| sha256chain [sdk] sha256 accel sigil_sha256 | default | soc | 1024 | 2,860,176 | 1,029,153 | 0.360 | 2.779 | 2,793.14 | - | 0.0115 B/cycle | 2,860,152 |
| sha256chain [sdk] sha512 accel sigil_hash | default | axi | 1024 | 2,531,644 | 1,011,743 | 0.400 | 2.502 | 2,472.31 | - | 0.0259 B/cycle | 2,531,583 |
| sha256chain [sdk] sha512 accel sigil_hash | default | soc | 1024 | 2,531,505 | 1,011,752 | 0.400 | 2.502 | 2,472.17 | - | 0.0259 B/cycle | 2,531,469 |
| sha256chain [sdk] sha3-256 accel sigil_hash | default | axi | 1024 | 1,403,055 | 555,048 | 0.396 | 2.528 | 1,370.17 | - | 0.0234 B/cycle | 1,403,029 |
| sha256chain [sdk] sha3-256 accel sigil_hash | default | soc | 1024 | 1,403,005 | 555,048 | 0.396 | 2.528 | 1,370.12 | - | 0.0234 B/cycle | 1,402,979 |
| sha256chain_bulk [sdk] sha256 plain C | default | axi | 64 | 10,145,679 | 3,701,941 | 0.365 | 2.741 | 158,526.23 | - | 0.0065 B/cycle | 10,145,581 |
| sha256chain_bulk [sdk] sha256 plain C | default | soc | 64 | 10,114,258 | 3,701,941 | 0.366 | 2.732 | 158,035.28 | - | 0.0065 B/cycle | 10,114,210 |
| sha256chain_bulk [sdk] sha256 Zknh | default | axi | 64 | 6,931,283 | 2,735,418 | 0.395 | 2.534 | 108,301.30 | - | 0.0095 B/cycle | 6,931,154 |
| sha256chain_bulk [sdk] sha256 Zknh | default | soc | 64 | 6,903,194 | 2,735,418 | 0.396 | 2.524 | 107,862.41 | - | 0.0095 B/cycle | 6,903,140 |
| sha256chain_bulk [sdk] sha256 RVV x16 (16 segments) | default | axi | 64 | 5,049,593 | 224,331 | 0.044 | 22.510 | 78,899.89 | - | 0.0130 B/cycle | 5,049,462 |
| sha256chain_bulk [sdk] sha256 RVV x16 (16 segments) | default | soc | 64 | 4,996,705 | 224,331 | 0.045 | 22.274 | 78,073.52 | - | 0.0131 B/cycle | 4,996,649 |
| sha256chain_bulk [sdk] sha512 accel sigil_hash | default | axi | 64 | 297,276 | 66,472 | 0.224 | 4.472 | 4,644.94 | - | 0.2205 B/cycle | 297,203 |
| sha256chain_bulk [sdk] sha512 accel sigil_hash | default | soc | 64 | 274,480 | 66,472 | 0.242 | 4.129 | 4,288.75 | - | 0.2388 B/cycle | 274,432 |
| sha256chain_bulk [sdk] sha3-256 accel sigil_hash | default | axi | 64 | 295,850 | 66,055 | 0.223 | 4.479 | 4,622.66 | - | 0.2215 B/cycle | 295,826 |
| sha256chain_bulk [sdk] sha3-256 accel sigil_hash | default | soc | 64 | 273,326 | 66,055 | 0.242 | 4.138 | 4,270.72 | - | 0.2398 B/cycle | 273,302 |

Net cycles/iter: the region's cycles minus those of the bench's window region (an empty measurement window, `(window)`) in the same simulation, divided by the iterations.

## Speedups over the baseline region (same image, configuration and memory)

| Run | Baseline region | Baseline cycles | Cycles | Speedup |
|---|---|---:|---:|---:|
| kernels[autovec] vadd_i32 RVV default/axi | 10 vadd_i32 C | 51,500 | 45,814 | 1.12x |
| kernels[autovec] vadd_i32 RVV default/soc | 10 vadd_i32 C | 50,438 | 43,277 | 1.17x |
| kernels[autovec] vadd_i64 RVV default/axi | 20 vadd_i64 C | 29,413 | 23,356 | 1.26x |
| kernels[autovec] vadd_i64 RVV default/soc | 20 vadd_i64 C | 28,567 | 22,146 | 1.29x |
| kernels[autovec] daxpy RVV default/axi | 30 daxpy C | 43,252 | 37,088 | 1.17x |
| kernels[autovec] daxpy RVV default/soc | 30 daxpy C | 42,771 | 36,242 | 1.18x |
| kernels[autovec] saxpy RVV default/axi | 40 saxpy C | 79,165 | 71,805 | 1.10x |
| kernels[autovec] saxpy RVV default/soc | 40 saxpy C | 78,833 | 71,025 | 1.11x |
| kernels[autovec] ddot RVV default/axi | 50 ddot C | 51,728 | 31,667 | 1.63x |
| kernels[autovec] ddot RVV default/soc | 50 ddot C | 51,645 | 31,617 | 1.63x |
| kernels[autovec] idot_i32 RVV default/axi | 60 idot_i32 C | 62,879 | 51,661 | 1.22x |
| kernels[autovec] idot_i32 RVV default/soc | 60 idot_i32 C | 62,854 | 51,636 | 1.22x |
| kernels[autovec] memcpy RVV default/axi | 70 memcpy C | 33,176 | 13,176 | 2.52x |
| kernels[autovec] memcpy RVV default/soc | 70 memcpy C | 33,093 | 13,093 | 2.53x |
| kernels[autovec] memcpy RVV-e8 default/axi | 70 memcpy C | 33,176 | 99,357 | 0.33x |
| kernels[autovec] memcpy RVV-e8 default/soc | 70 memcpy C | 33,093 | 99,158 | 0.33x |
| kernels[autovec] memset RVV default/axi | 80 memset C | 21,001 | 7,063 | 2.97x |
| kernels[autovec] memset RVV default/soc | 80 memset C | 20,860 | 7,038 | 2.96x |
| kernels[autovec] memset RVV-e8 default/axi | 80 memset C | 21,001 | 51,897 | 0.40x |
| kernels[autovec] memset RVV-e8 default/soc | 80 memset C | 20,860 | 51,872 | 0.40x |
| kernels[autovec] dgemm RVV default/axi | 90 dgemm C | 2,940,424 | 1,607,697 | 1.83x |
| kernels[autovec] dgemm RVV default/soc | 90 dgemm C | 2,887,312 | 1,560,786 | 1.85x |
| kernels[autovec] sgemm RVV default/axi | 100 sgemm C | 3,239,215 | 1,563,198 | 2.07x |
| kernels[autovec] sgemm RVV default/soc | 100 sgemm C | 3,238,444 | 1,563,001 | 2.07x |
| kernels[autovec] fir_f32 RVV default/axi | 110 fir_f32 C | 1,495,420 | 748,169 | 2.00x |
| kernels[autovec] fir_f32 RVV default/soc | 110 fir_f32 C | 1,495,279 | 747,738 | 2.00x |
| kernels[autovec] mac_i8 RVV default/axi | 120 mac_i8 C | 246,320 | 199,256 | 1.24x |
| kernels[autovec] mac_i8 RVV default/soc | 120 mac_i8 C | 246,237 | 199,173 | 1.24x |
| kernels[autovec] mac_i16 RVV default/axi | 130 mac_i16 C | 103,903 | 93,132 | 1.12x |
| kernels[autovec] mac_i16 RVV default/soc | 130 mac_i16 C | 103,878 | 93,107 | 1.12x |
| kernels[scalar] vadd_i32 RVV default/axi | 10 vadd_i32 C | 78,277 | 45,625 | 1.72x |
| kernels[scalar] vadd_i32 RVV default/soc | 10 vadd_i32 C | 78,078 | 43,212 | 1.81x |
| kernels[scalar] vadd_i64 RVV default/axi | 20 vadd_i64 C | 39,992 | 23,827 | 1.68x |
| kernels[scalar] vadd_i64 RVV default/soc | 20 vadd_i64 C | 39,370 | 22,302 | 1.77x |
| kernels[scalar] daxpy RVV default/axi | 30 daxpy C | 60,747 | 36,619 | 1.66x |
| kernels[scalar] daxpy RVV default/soc | 30 daxpy C | 59,951 | 36,088 | 1.66x |
| kernels[scalar] saxpy RVV default/axi | 40 saxpy C | 132,419 | 71,523 | 1.85x |
| kernels[scalar] saxpy RVV default/soc | 40 saxpy C | 131,614 | 70,934 | 1.86x |
| kernels[scalar] ddot RVV default/axi | 50 ddot C | 51,560 | 31,667 | 1.63x |
| kernels[scalar] ddot RVV default/soc | 50 ddot C | 51,427 | 31,617 | 1.63x |
| kernels[scalar] idot_i32 RVV default/axi | 60 idot_i32 C | 78,027 | 51,697 | 1.51x |
| kernels[scalar] idot_i32 RVV default/soc | 60 idot_i32 C | 78,002 | 51,647 | 1.51x |
| kernels[scalar] memcpy RVV default/axi | 70 memcpy C | 33,263 | 13,524 | 2.46x |
| kernels[scalar] memcpy RVV default/soc | 70 memcpy C | 33,122 | 13,209 | 2.51x |
| kernels[scalar] memcpy RVV-e8 default/axi | 70 memcpy C | 33,263 | 99,270 | 0.34x |
| kernels[scalar] memcpy RVV-e8 default/soc | 70 memcpy C | 33,122 | 99,129 | 0.33x |
| kernels[scalar] memset RVV default/axi | 80 memset C | 20,914 | 7,063 | 2.96x |
| kernels[scalar] memset RVV default/soc | 80 memset C | 20,831 | 7,038 | 2.96x |
| kernels[scalar] memset RVV-e8 default/axi | 80 memset C | 20,914 | 51,897 | 0.40x |
| kernels[scalar] memset RVV-e8 default/soc | 80 memset C | 20,831 | 51,872 | 0.40x |
| kernels[scalar] dgemm RVV default/axi | 90 dgemm C | 2,936,230 | 1,611,153 | 1.82x |
| kernels[scalar] dgemm RVV default/soc | 90 dgemm C | 2,886,016 | 1,561,900 | 1.85x |
| kernels[scalar] sgemm RVV default/axi | 100 sgemm C | 3,238,621 | 1,563,716 | 2.07x |
| kernels[scalar] sgemm RVV default/soc | 100 sgemm C | 3,238,248 | 1,563,177 | 2.07x |
| kernels[scalar] fir_f32 RVV default/axi | 110 fir_f32 C | 1,917,344 | 747,857 | 2.56x |
| kernels[scalar] fir_f32 RVV default/soc | 110 fir_f32 C | 1,917,178 | 747,633 | 2.56x |
| kernels[scalar] mac_i8 RVV default/axi | 120 mac_i8 C | 344,261 | 199,169 | 1.73x |
| kernels[scalar] mac_i8 RVV default/soc | 120 mac_i8 C | 344,236 | 199,144 | 1.73x |
| kernels[scalar] mac_i16 RVV default/axi | 130 mac_i16 C | 172,235 | 93,132 | 1.85x |
| kernels[scalar] mac_i16 RVV default/soc | 130 mac_i16 C | 172,210 | 93,107 | 1.85x |
| sha256chain[sdk] sha256 Zknh default/axi | 0 sha256 plain C | 10,156,468 | 6,915,525 | 1.47x |
| sha256chain[sdk] sha256 Zknh default/soc | 0 sha256 plain C | 10,156,268 | 6,915,325 | 1.47x |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/axi | 0 sha256 plain C | 10,156,468 | 4,754,072 | 2.14x |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | 0 sha256 plain C | 10,156,268 | 4,753,403 | 2.14x |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/axi | 0 sha256 plain C | 10,156,468 | 585,847 | 17.34x |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | 0 sha256 plain C | 10,156,268 | 585,822 | 17.34x |
| sha256chain[sdk] sha256 accel sigil_sha256 default/axi | 0 sha256 plain C | 10,156,468 | 2,860,326 | 3.55x |
| sha256chain[sdk] sha256 accel sigil_sha256 default/soc | 0 sha256 plain C | 10,156,268 | 2,860,176 | 3.55x |
| sha256chain_bulk[sdk] sha256 Zknh default/axi | 0 sha256 plain C | 10,145,679 | 6,931,283 | 1.46x |
| sha256chain_bulk[sdk] sha256 Zknh default/soc | 0 sha256 plain C | 10,114,258 | 6,903,194 | 1.47x |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/axi | 0 sha256 plain C | 10,145,679 | 5,049,593 | 2.01x |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | 0 sha256 plain C | 10,114,258 | 4,996,705 | 2.02x |

## Projected throughput at a given clock (simulation cycles; not a hardware measurement)

| Run | Iter/s @ 62.5 MHz | Iter/s @ 100 MHz | Work/s @ 62.5 MHz | Work/s @ 100 MHz |
|---|---:|---:|---:|---:|
| coremark[scalar] default/axi | 87.2 | 139.5 | - | - |
| coremark[scalar] default/soc | 87.2 | 139.5 | - | - |
| coremark[sdk] default/axi | 85.8 | 137.2 | - | - |
| coremark[sdk] default/soc | 85.8 | 137.2 | - | - |
| coremark[validation] default/axi | 87.0 | 139.2 | - | - |
| coremark[validation] default/soc | 87.0 | 139.2 | - | - |
| dhrystone[scalar] default/axi | 40,708.0 | 65,132.7 | - | - |
| dhrystone[scalar] default/soc | 40,713.4 | 65,141.4 | - | - |
| dhrystone[sdk] default/axi | 35,892.1 | 57,427.4 | - | - |
| dhrystone[sdk] default/soc | 35,896.4 | 57,434.3 | - | - |
| kernels[autovec] vadd_i32 C default/axi | 4,854.4 | 7,767.0 | 4,970,874 elem/s | 7,953,398 elem/s |
| kernels[autovec] vadd_i32 C default/soc | 4,956.6 | 7,930.5 | 5,075,538 elem/s | 8,120,861 elem/s |
| kernels[autovec] vadd_i32 RVV default/axi | 5,456.8 | 8,731.0 | 5,587,812 elem/s | 8,940,499 elem/s |
| kernels[autovec] vadd_i32 RVV default/soc | 5,776.7 | 9,242.8 | 5,915,382 elem/s | 9,464,612 elem/s |
| kernels[autovec] vadd_i64 C default/axi | 8,499.6 | 13,599.4 | 4,351,817 elem/s | 6,962,908 elem/s |
| kernels[autovec] vadd_i64 C default/soc | 8,751.4 | 14,002.2 | 4,480,695 elem/s | 7,169,111 elem/s |
| kernels[autovec] vadd_i64 RVV default/axi | 10,703.9 | 17,126.2 | 5,480,390 elem/s | 8,768,625 elem/s |
| kernels[autovec] vadd_i64 RVV default/soc | 11,288.7 | 18,062.0 | 5,779,825 elem/s | 9,247,720 elem/s |
| kernels[autovec] daxpy C default/axi | 5,780.1 | 9,248.1 | 2,959,401 elem/s | 4,735,041 elem/s |
| kernels[autovec] daxpy C default/soc | 5,845.1 | 9,352.1 | 2,992,682 elem/s | 4,788,291 elem/s |
| kernels[autovec] daxpy RVV default/axi | 6,740.7 | 10,785.2 | 3,451,251 elem/s | 5,522,002 elem/s |
| kernels[autovec] daxpy RVV default/soc | 6,898.1 | 11,036.9 | 3,531,814 elem/s | 5,650,902 elem/s |
| kernels[autovec] saxpy C default/axi | 3,158.0 | 5,052.7 | 3,233,752 elem/s | 5,174,004 elem/s |
| kernels[autovec] saxpy C default/soc | 3,171.3 | 5,074.0 | 3,247,371 elem/s | 5,195,794 elem/s |
| kernels[autovec] saxpy RVV default/axi | 3,481.7 | 5,570.6 | 3,565,211 elem/s | 5,704,338 elem/s |
| kernels[autovec] saxpy RVV default/soc | 3,519.9 | 5,631.8 | 3,604,365 elem/s | 5,766,983 elem/s |
| kernels[autovec] ddot C default/axi | 4,833.0 | 7,732.8 | 2,474,482 elem/s | 3,959,171 elem/s |
| kernels[autovec] ddot C default/soc | 4,840.7 | 7,745.2 | 2,478,459 elem/s | 3,965,534 elem/s |
| kernels[autovec] ddot RVV default/axi | 7,894.7 | 12,631.4 | 4,042,063 elem/s | 6,467,300 elem/s |
| kernels[autovec] ddot RVV default/soc | 7,907.1 | 12,651.4 | 4,048,455 elem/s | 6,477,528 elem/s |
| kernels[autovec] idot_i32 C default/axi | 3,975.9 | 6,361.4 | 4,071,312 elem/s | 6,514,099 elem/s |
| kernels[autovec] idot_i32 C default/soc | 3,977.5 | 6,364.0 | 4,072,931 elem/s | 6,516,689 elem/s |
| kernels[autovec] idot_i32 RVV default/axi | 4,839.2 | 7,742.8 | 4,955,382 elem/s | 7,928,612 elem/s |
| kernels[autovec] idot_i32 RVV default/soc | 4,841.6 | 7,746.5 | 4,957,781 elem/s | 7,932,450 elem/s |
| kernels[autovec] memcpy C default/axi | 7,535.6 | 12,056.9 | 30,865,686 byte/s | 49,385,098 byte/s |
| kernels[autovec] memcpy C default/soc | 7,554.5 | 12,087.1 | 30,943,100 byte/s | 49,508,960 byte/s |
| kernels[autovec] memcpy RVV default/axi | 18,973.9 | 30,358.2 | 77,717,061 byte/s | 124,347,298 byte/s |
| kernels[autovec] memcpy RVV default/soc | 19,094.2 | 30,550.7 | 78,209,730 byte/s | 125,135,569 byte/s |
| kernels[autovec] memcpy RVV-e8 default/axi | 2,516.2 | 4,025.9 | 10,306,269 byte/s | 16,490,031 byte/s |
| kernels[autovec] memcpy RVV-e8 default/soc | 2,521.2 | 4,034.0 | 10,326,953 byte/s | 16,523,125 byte/s |
| kernels[autovec] memset C default/axi | 11,904.2 | 19,046.7 | 48,759,583 byte/s | 78,015,333 byte/s |
| kernels[autovec] memset C default/soc | 11,984.7 | 19,175.5 | 49,089,166 byte/s | 78,542,665 byte/s |
| kernels[autovec] memset RVV default/axi | 35,395.7 | 56,633.2 | 144,980,886 byte/s | 231,969,418 byte/s |
| kernels[autovec] memset RVV default/soc | 35,521.5 | 56,834.3 | 145,495,880 byte/s | 232,793,407 byte/s |
| kernels[autovec] memset RVV-e8 default/axi | 4,817.2 | 7,707.6 | 19,731,391 byte/s | 31,570,226 byte/s |
| kernels[autovec] memset RVV-e8 default/soc | 4,819.6 | 7,711.3 | 19,740,901 byte/s | 31,585,441 byte/s |
| kernels[autovec] dgemm C default/axi | 85.0 | 136.0 | 2,785,993 mac/s | 4,457,588 mac/s |
| kernels[autovec] dgemm C default/soc | 86.6 | 138.5 | 2,837,241 mac/s | 4,539,586 mac/s |
| kernels[autovec] dgemm RVV default/axi | 155.5 | 248.8 | 5,095,488 mac/s | 8,152,780 mac/s |
| kernels[autovec] dgemm RVV default/soc | 160.2 | 256.3 | 5,248,638 mac/s | 8,397,820 mac/s |
| kernels[autovec] sgemm C default/axi | 77.2 | 123.5 | 2,529,008 mac/s | 4,046,412 mac/s |
| kernels[autovec] sgemm C default/soc | 77.2 | 123.5 | 2,529,610 mac/s | 4,047,376 mac/s |
| kernels[autovec] sgemm RVV default/axi | 159.9 | 255.9 | 5,240,539 mac/s | 8,384,862 mac/s |
| kernels[autovec] sgemm RVV default/soc | 159.9 | 255.9 | 5,241,199 mac/s | 8,385,919 mac/s |
| kernels[autovec] fir_f32 C default/axi | 167.2 | 267.5 | 2,739,030 mac/s | 4,382,448 mac/s |
| kernels[autovec] fir_f32 C default/soc | 167.2 | 267.5 | 2,739,288 mac/s | 4,382,861 mac/s |
| kernels[autovec] fir_f32 RVV default/axi | 334.1 | 534.6 | 5,474,699 mac/s | 8,759,518 mac/s |
| kernels[autovec] fir_f32 RVV default/soc | 334.3 | 534.9 | 5,477,855 mac/s | 8,764,567 mac/s |
| kernels[autovec] mac_i8 C default/axi | 1,014.9 | 1,623.9 | 4,157,194 mac/s | 6,651,510 mac/s |
| kernels[autovec] mac_i8 C default/soc | 1,015.3 | 1,624.5 | 4,158,595 mac/s | 6,653,752 mac/s |
| kernels[autovec] mac_i8 RVV default/axi | 1,254.7 | 2,007.5 | 5,139,118 mac/s | 8,222,588 mac/s |
| kernels[autovec] mac_i8 RVV default/soc | 1,255.2 | 2,008.3 | 5,141,259 mac/s | 8,226,015 mac/s |
| kernels[autovec] mac_i16 C default/axi | 2,406.1 | 3,849.7 | 4,927,673 mac/s | 7,884,277 mac/s |
| kernels[autovec] mac_i16 C default/soc | 2,406.7 | 3,850.7 | 4,928,859 mac/s | 7,886,174 mac/s |
| kernels[autovec] mac_i16 RVV default/axi | 2,684.4 | 4,295.0 | 5,497,573 mac/s | 8,796,117 mac/s |
| kernels[autovec] mac_i16 RVV default/soc | 2,685.1 | 4,296.1 | 5,499,049 mac/s | 8,798,479 mac/s |
| kernels[scalar] vadd_i32 C default/axi | 3,193.8 | 5,110.1 | 3,270,437 elem/s | 5,232,699 elem/s |
| kernels[scalar] vadd_i32 C default/soc | 3,201.9 | 5,123.1 | 3,278,773 elem/s | 5,246,036 elem/s |
| kernels[scalar] vadd_i32 RVV default/axi | 5,479.5 | 8,767.1 | 5,610,959 elem/s | 8,977,534 elem/s |
| kernels[scalar] vadd_i32 RVV default/soc | 5,785.4 | 9,256.7 | 5,924,280 elem/s | 9,478,848 elem/s |
| kernels[scalar] vadd_i64 C default/axi | 6,251.3 | 10,002.0 | 3,200,640 elem/s | 5,121,024 elem/s |
| kernels[scalar] vadd_i64 C default/soc | 6,350.0 | 10,160.0 | 3,251,207 elem/s | 5,201,930 elem/s |
| kernels[scalar] vadd_i64 RVV default/axi | 10,492.3 | 16,787.7 | 5,372,057 elem/s | 8,595,291 elem/s |
| kernels[scalar] vadd_i64 RVV default/soc | 11,209.8 | 17,935.6 | 5,739,396 elem/s | 9,183,033 elem/s |
| kernels[scalar] daxpy C default/axi | 4,115.4 | 6,584.7 | 2,107,100 elem/s | 3,371,360 elem/s |
| kernels[scalar] daxpy C default/soc | 4,170.1 | 6,672.1 | 2,135,077 elem/s | 3,416,123 elem/s |
| kernels[scalar] daxpy RVV default/axi | 6,827.1 | 10,923.3 | 3,495,453 elem/s | 5,592,725 elem/s |
| kernels[scalar] daxpy RVV default/soc | 6,927.5 | 11,084.0 | 3,546,885 elem/s | 5,675,017 elem/s |
| kernels[scalar] saxpy C default/axi | 1,887.9 | 3,020.7 | 1,933,257 elem/s | 3,093,212 elem/s |
| kernels[scalar] saxpy C default/soc | 1,899.5 | 3,039.2 | 1,945,082 elem/s | 3,112,131 elem/s |
| kernels[scalar] saxpy RVV default/axi | 3,495.4 | 5,592.6 | 3,579,268 elem/s | 5,726,829 elem/s |
| kernels[scalar] saxpy RVV default/soc | 3,524.4 | 5,639.0 | 3,608,989 elem/s | 5,774,382 elem/s |
| kernels[scalar] ddot C default/axi | 4,848.7 | 7,758.0 | 2,482,545 elem/s | 3,972,071 elem/s |
| kernels[scalar] ddot C default/soc | 4,861.3 | 7,778.0 | 2,488,965 elem/s | 3,982,344 elem/s |
| kernels[scalar] ddot RVV default/axi | 7,894.7 | 12,631.4 | 4,042,063 elem/s | 6,467,300 elem/s |
| kernels[scalar] ddot RVV default/soc | 7,907.1 | 12,651.4 | 4,048,455 elem/s | 6,477,528 elem/s |
| kernels[scalar] idot_i32 C default/axi | 3,204.0 | 5,126.4 | 3,280,916 elem/s | 5,249,465 elem/s |
| kernels[scalar] idot_i32 C default/soc | 3,205.0 | 5,128.1 | 3,281,967 elem/s | 5,251,147 elem/s |
| kernels[scalar] idot_i32 RVV default/axi | 4,835.9 | 7,737.4 | 4,951,931 elem/s | 7,923,090 elem/s |
| kernels[scalar] idot_i32 RVV default/soc | 4,840.6 | 7,744.9 | 4,956,725 elem/s | 7,930,761 elem/s |
| kernels[scalar] memcpy C default/axi | 7,515.9 | 12,025.4 | 30,784,956 byte/s | 49,255,930 byte/s |
| kernels[scalar] memcpy C default/soc | 7,547.9 | 12,076.6 | 30,916,007 byte/s | 49,465,612 byte/s |
| kernels[scalar] memcpy RVV default/axi | 18,485.7 | 29,577.0 | 75,717,243 byte/s | 121,147,589 byte/s |
| kernels[scalar] memcpy RVV default/soc | 18,926.5 | 30,282.4 | 77,522,901 byte/s | 124,036,642 byte/s |
| kernels[scalar] memcpy RVV-e8 default/axi | 2,518.4 | 4,029.4 | 10,315,302 byte/s | 16,504,483 byte/s |
| kernels[scalar] memcpy RVV-e8 default/soc | 2,522.0 | 4,035.1 | 10,329,974 byte/s | 16,527,959 byte/s |
| kernels[scalar] memset C default/axi | 11,953.7 | 19,125.9 | 48,962,418 byte/s | 78,339,868 byte/s |
| kernels[scalar] memset C default/soc | 12,001.3 | 19,202.2 | 49,157,506 byte/s | 78,652,009 byte/s |
| kernels[scalar] memset RVV default/axi | 35,395.7 | 56,633.2 | 144,980,886 byte/s | 231,969,418 byte/s |
| kernels[scalar] memset RVV default/soc | 35,521.5 | 56,834.3 | 145,495,880 byte/s | 232,793,407 byte/s |
| kernels[scalar] memset RVV-e8 default/axi | 4,817.2 | 7,707.6 | 19,731,391 byte/s | 31,570,226 byte/s |
| kernels[scalar] memset RVV-e8 default/soc | 4,819.6 | 7,711.3 | 19,740,901 byte/s | 31,585,441 byte/s |
| kernels[scalar] dgemm C default/axi | 85.1 | 136.2 | 2,789,972 mac/s | 4,463,955 mac/s |
| kernels[scalar] dgemm C default/soc | 86.6 | 138.6 | 2,838,515 mac/s | 4,541,624 mac/s |
| kernels[scalar] dgemm RVV default/axi | 155.2 | 248.3 | 5,084,557 mac/s | 8,135,292 mac/s |
| kernels[scalar] dgemm RVV default/soc | 160.1 | 256.1 | 5,244,894 mac/s | 8,391,830 mac/s |
| kernels[scalar] sgemm C default/axi | 77.2 | 123.5 | 2,529,472 mac/s | 4,047,155 mac/s |
| kernels[scalar] sgemm C default/soc | 77.2 | 123.5 | 2,529,763 mac/s | 4,047,621 mac/s |
| kernels[scalar] sgemm RVV default/axi | 159.9 | 255.8 | 5,238,803 mac/s | 8,382,085 mac/s |
| kernels[scalar] sgemm RVV default/soc | 159.9 | 255.9 | 5,240,609 mac/s | 8,384,975 mac/s |
| kernels[scalar] fir_f32 C default/axi | 130.4 | 208.6 | 2,136,289 mac/s | 3,418,062 mac/s |
| kernels[scalar] fir_f32 C default/soc | 130.4 | 208.6 | 2,136,474 mac/s | 3,418,358 mac/s |
| kernels[scalar] fir_f32 RVV default/axi | 334.3 | 534.9 | 5,476,983 mac/s | 8,763,173 mac/s |
| kernels[scalar] fir_f32 RVV default/soc | 334.4 | 535.0 | 5,478,624 mac/s | 8,765,798 mac/s |
| kernels[scalar] mac_i8 C default/axi | 726.2 | 1,161.9 | 2,974,487 mac/s | 4,759,180 mac/s |
| kernels[scalar] mac_i8 C default/soc | 726.2 | 1,162.0 | 2,974,703 mac/s | 4,759,525 mac/s |
| kernels[scalar] mac_i8 RVV default/axi | 1,255.2 | 2,008.3 | 5,141,362 mac/s | 8,226,180 mac/s |
| kernels[scalar] mac_i8 RVV default/soc | 1,255.4 | 2,008.6 | 5,142,008 mac/s | 8,227,212 mac/s |
| kernels[scalar] mac_i16 C default/axi | 1,451.5 | 2,322.4 | 2,972,683 mac/s | 4,756,292 mac/s |
| kernels[scalar] mac_i16 C default/soc | 1,451.7 | 2,322.7 | 2,973,114 mac/s | 4,756,983 mac/s |
| kernels[scalar] mac_i16 RVV default/axi | 2,684.4 | 4,295.0 | 5,497,573 mac/s | 8,796,117 mac/s |
| kernels[scalar] mac_i16 RVV default/soc | 2,685.1 | 4,296.1 | 5,499,049 mac/s | 8,798,479 mac/s |
| micro_dmem[default] empty default/axi | 2,782,608,695.7 | 4,452,173,913.0 | - | - |
| micro_dmem[default] empty default/soc | 3,820,895,522.4 | 6,113,432,835.8 | - | - |
| micro_dmem[default] chase_rand_1k default/axi | 20,155,893.2 | 32,249,429.2 | - | - |
| micro_dmem[default] chase_rand_1k default/soc | 20,195,645.3 | 32,313,032.5 | - | - |
| micro_dmem[default] chase_rand_2k default/axi | 20,155,893.2 | 32,249,429.2 | - | - |
| micro_dmem[default] chase_rand_2k default/soc | 20,195,645.3 | 32,313,032.5 | - | - |
| micro_dmem[default] chase_rand_4k default/axi | 20,155,893.2 | 32,249,429.2 | - | - |
| micro_dmem[default] chase_rand_4k default/soc | 20,195,645.3 | 32,313,032.5 | - | - |
| micro_dmem[default] chase_rand_8k default/axi | 20,155,893.2 | 32,249,429.2 | - | - |
| micro_dmem[default] chase_rand_8k default/soc | 20,195,645.3 | 32,313,032.5 | - | - |
| micro_dmem[default] chase_rand_12k default/axi | 20,155,893.2 | 32,249,429.2 | - | - |
| micro_dmem[default] chase_rand_12k default/soc | 20,195,645.3 | 32,313,032.5 | - | - |
| micro_dmem[default] chase_rand_16k default/axi | 19,631,901.8 | 31,411,042.9 | - | - |
| micro_dmem[default] chase_rand_16k default/soc | 20,028,164.6 | 32,045,063.4 | - | - |
| micro_dmem[default] chase_rand_20k default/axi | 3,585,635.0 | 5,737,016.1 | - | - |
| micro_dmem[default] chase_rand_20k default/soc | 8,362,460.4 | 13,379,936.6 | - | - |
| micro_dmem[default] chase_rand_24k default/axi | 2,453,611.4 | 3,925,778.3 | - | - |
| micro_dmem[default] chase_rand_24k default/soc | 6,293,328.1 | 10,069,324.9 | - | - |
| micro_dmem[default] chase_rand_32k default/axi | 1,892,147.6 | 3,027,436.1 | - | - |
| micro_dmem[default] chase_rand_32k default/soc | 5,105,907.7 | 8,169,452.3 | - | - |
| micro_dmem[default] chase_rand_64k default/axi | 1,616,447.4 | 2,586,315.8 | - | - |
| micro_dmem[default] chase_rand_64k default/soc | 4,476,385.3 | 7,162,216.5 | - | - |
| micro_dmem[default] chase_rand_128k default/axi | 1,596,487.7 | 2,554,380.4 | - | - |
| micro_dmem[default] chase_rand_128k default/soc | 4,429,525.6 | 7,087,240.9 | - | - |
| micro_dmem[default] chase_rand_256k default/axi | 1,596,487.7 | 2,554,380.4 | - | - |
| micro_dmem[default] chase_rand_256k default/soc | 4,429,525.6 | 7,087,240.9 | - | - |
| micro_dmem[default] chase_seq_4k default/axi | 20,155,893.2 | 32,249,429.2 | - | - |
| micro_dmem[default] chase_seq_4k default/soc | 20,195,645.3 | 32,313,032.5 | - | - |
| micro_dmem[default] chase_seq_8k default/axi | 20,098,924.4 | 32,158,279.0 | - | - |
| micro_dmem[default] chase_seq_8k default/soc | 20,178,135.1 | 32,285,016.2 | - | - |
| micro_dmem[default] chase_seq_16k default/axi | 19,631,901.8 | 31,411,042.9 | - | - |
| micro_dmem[default] chase_seq_16k default/soc | 20,028,164.6 | 32,045,063.4 | - | - |
| micro_dmem[default] chase_seq_32k default/axi | 2,291,524.9 | 3,666,439.9 | - | - |
| micro_dmem[default] chase_seq_32k default/soc | 5,962,779.2 | 9,540,446.7 | - | - |
| micro_dmem[default] stream_ld default/axi | 8,434,370.1 | 13,494,992.1 | - | - |
| micro_dmem[default] stream_ld default/soc | 14,626,899.8 | 23,403,039.7 | - | - |
| micro_dmem[default] stream_st default/axi | 4,800,480.0 | 7,680,768.1 | - | - |
| micro_dmem[default] stream_st default/soc | 9,998,828.3 | 15,998,125.2 | - | - |
| micro_imem[default] empty default/axi | 33,758,241,758.2 | 54,013,186,813.2 | - | - |
| micro_imem[default] empty default/soc | 46,545,454,545.5 | 74,472,727,272.7 | - | - |
| micro_imem[default] ifoot_1k default/axi | 30,402,897.8 | 48,644,636.4 | - | - |
| micro_imem[default] ifoot_1k default/soc | 30,402,897.8 | 48,644,636.4 | - | - |
| micro_imem[default] ifoot_2k default/axi | 30,812,746.4 | 49,300,394.2 | - | - |
| micro_imem[default] ifoot_2k default/soc | 30,812,746.4 | 49,300,394.2 | - | - |
| micro_imem[default] ifoot_3k default/axi | 30,951,829.2 | 49,522,926.7 | - | - |
| micro_imem[default] ifoot_3k default/soc | 30,951,829.2 | 49,522,926.7 | - | - |
| micro_imem[default] ifoot_4k default/axi | 31,021,842.5 | 49,634,948.0 | - | - |
| micro_imem[default] ifoot_4k default/soc | 31,021,842.5 | 49,634,948.0 | - | - |
| micro_imem[default] ifoot_6k default/axi | 29,624,200.8 | 47,398,721.3 | - | - |
| micro_imem[default] ifoot_6k default/soc | 30,628,421.0 | 49,005,473.6 | - | - |
| micro_imem[default] ifoot_8k default/axi | 29,947,650.1 | 47,916,240.2 | - | - |
| micro_imem[default] ifoot_8k default/soc | 30,757,216.2 | 49,211,546.0 | - | - |
| micro_imem[default] ifoot_12k default/axi | 17,776,646.2 | 28,442,633.9 | - | - |
| micro_imem[default] ifoot_12k default/soc | 25,333,784.2 | 40,534,054.6 | - | - |
| micro_imem[default] ifoot_16k default/axi | 16,838,504.9 | 26,941,607.9 | - | - |
| micro_imem[default] ifoot_16k default/soc | 24,741,471.0 | 39,586,353.5 | - | - |
| micro_imem[default] ifoot_24k default/axi | 16,057,623.5 | 25,692,197.5 | - | - |
| micro_imem[default] ifoot_24k default/soc | 24,220,252.9 | 38,752,404.7 | - | - |
| micro_imem[default] ifoot_32k default/axi | 15,699,501.7 | 25,119,202.8 | - | - |
| micro_imem[default] ifoot_32k default/soc | 23,971,907.9 | 38,355,052.7 | - | - |
| micro_pipe[default] empty default/axi | 2,813,186,813.2 | 4,501,098,901.1 | - | - |
| micro_pipe[default] empty default/soc | 3,878,787,878.8 | 6,206,060,606.1 | - | - |
| micro_pipe[default] loop default/axi | 10,377,817.4 | 16,604,507.9 | - | - |
| micro_pipe[default] loop default/soc | 10,388,345.6 | 16,621,352.9 | - | - |
| micro_pipe[default] alu32_dep default/axi | 30,487,078.7 | 48,779,325.9 | - | - |
| micro_pipe[default] alu32_dep default/soc | 30,578,117.5 | 48,924,988.1 | - | - |
| micro_pipe[default] alu32_indep default/axi | 30,472,562.8 | 48,756,100.5 | - | - |
| micro_pipe[default] alu32_indep default/soc | 30,563,514.8 | 48,901,623.7 | - | - |
| micro_pipe[default] alu16_dep default/axi | 30,483,448.4 | 48,773,517.5 | - | - |
| micro_pipe[default] alu16_dep default/soc | 30,574,465.5 | 48,919,144.9 | - | - |
| micro_pipe[default] alu32_straddle default/axi | 15,367,991.4 | 24,588,786.2 | - | - |
| micro_pipe[default] alu32_straddle default/soc | 15,391,090.0 | 24,625,744.0 | - | - |
| micro_pipe[default] br_nt default/axi | 30,490,709.9 | 48,785,135.8 | - | - |
| micro_pipe[default] br_nt default/soc | 30,581,770.4 | 48,930,832.6 | - | - |
| micro_pipe[default] br_taken default/axi | 15,430,982.5 | 24,689,572.0 | - | - |
| micro_pipe[default] br_taken default/soc | 15,454,271.1 | 24,726,833.7 | - | - |
| micro_pipe[default] jal default/axi | 15,454,271.1 | 24,726,833.7 | - | - |
| micro_pipe[default] jal default/soc | 15,477,630.0 | 24,764,208.0 | - | - |
| micro_pipe[default] call_ret default/axi | 6,220,386.3 | 9,952,618.2 | - | - |
| micro_pipe[default] call_ret default/soc | 6,224,167.3 | 9,958,667.6 | - | - |
| micro_pipe[default] jalr_call_ret default/axi | 6,225,226.8 | 9,960,362.8 | - | - |
| micro_pipe[default] jalr_call_ret default/soc | 6,225,226.8 | 9,960,362.8 | - | - |
| micro_pipe[default] brpat_never default/axi | 7,252,330.1 | 11,603,728.2 | - | - |
| micro_pipe[default] brpat_never default/soc | 7,257,470.1 | 11,611,952.1 | - | - |
| micro_pipe[default] brpat_always default/axi | 5,891,151.8 | 9,425,842.8 | - | - |
| micro_pipe[default] brpat_always default/soc | 5,891,151.8 | 9,425,842.8 | - | - |
| micro_pipe[default] brpat_alt default/axi | 6,504,230.3 | 10,406,768.5 | - | - |
| micro_pipe[default] brpat_alt default/soc | 6,504,230.3 | 10,406,768.5 | - | - |
| micro_pipe[default] brpat_rand default/axi | 6,504,230.3 | 10,406,768.5 | - | - |
| micro_pipe[default] brpat_rand default/soc | 6,504,230.3 | 10,406,768.5 | - | - |
| micro_pipe[default] ld_dep default/axi | 20,610,256.8 | 32,976,410.9 | - | - |
| micro_pipe[default] ld_dep default/soc | 20,610,256.8 | 32,976,410.9 | - | - |
| micro_pipe[default] ld_indep default/axi | 24,539,877.3 | 39,263,803.7 | - | - |
| micro_pipe[default] ld_indep default/soc | 24,598,827.7 | 39,358,124.3 | - | - |
| micro_pipe[default] ld_use1 default/axi | 15,453,338.2 | 24,725,341.1 | - | - |
| micro_pipe[default] ld_use1 default/soc | 15,476,694.3 | 24,762,710.8 | - | - |
| micro_pipe[default] ld_use2 default/axi | 15,450,540.2 | 24,720,864.3 | - | - |
| micro_pipe[default] ld_use2 default/soc | 15,473,887.8 | 24,758,220.5 | - | - |
| micro_pipe[default] st default/axi | 24,535,173.5 | 39,256,277.6 | - | - |
| micro_pipe[default] st default/soc | 24,594,101.3 | 39,350,562.0 | - | - |
| micro_pipe[default] rdcycle default/axi | 30,447,193.1 | 48,715,509.0 | - | - |
| micro_pipe[default] rdcycle default/soc | 30,629,337.2 | 49,006,939.5 | - | - |
| micro_pipe[default] rdtime default/axi | 30,534,351.1 | 48,854,961.8 | - | - |
| micro_pipe[default] rdtime default/soc | 30,625,672.9 | 49,001,076.7 | - | - |
| micro_pipe[default] csrr default/axi | 30,574,465.5 | 48,919,144.9 | - | - |
| micro_pipe[default] csrr default/soc | 30,666,027.8 | 49,065,644.5 | - | - |
| micro_pipe[default] csrw default/axi | 30,494,341.9 | 48,790,947.0 | - | - |
| micro_pipe[default] csrw default/soc | 30,585,424.1 | 48,936,678.6 | - | - |
| micro_pipe[default] csrrw default/axi | 30,548,926.0 | 48,878,281.6 | - | - |
| micro_pipe[default] csrrw default/soc | 30,640,335.1 | 49,024,536.2 | - | - |
| micro_pipe[default] fence default/axi | 30,669,701.7 | 49,071,522.7 | - | - |
| micro_pipe[default] fence default/soc | 30,669,701.7 | 49,071,522.7 | - | - |
| micro_units[default] empty default/axi | 695,652,173.9 | 1,113,043,478.3 | - | - |
| micro_units[default] empty default/soc | 955,223,880.6 | 1,528,358,209.0 | - | - |
| micro_units[default] mul_dep default/axi | 14,790,848.2 | 23,665,357.1 | - | - |
| micro_units[default] mul_dep default/soc | 14,876,801.5 | 23,802,882.4 | - | - |
| micro_units[default] mul_indep default/axi | 14,655,369.8 | 23,448,591.7 | - | - |
| micro_units[default] mul_indep default/soc | 14,911,463.2 | 23,858,341.1 | - | - |
| micro_units[default] div_dep default/axi | 1,725,067.4 | 2,760,107.8 | - | - |
| micro_units[default] div_dep default/soc | 1,727,395.4 | 2,763,832.7 | - | - |
| micro_units[default] div_indep default/axi | 1,726,370.3 | 2,762,192.5 | - | - |
| micro_units[default] div_indep default/soc | 1,727,535.3 | 2,764,056.5 | - | - |
| micro_units[default] div_short default/axi | 14,956,765.6 | 23,930,825.0 | - | - |
| micro_units[default] div_short default/soc | 15,044,663.8 | 24,071,462.2 | - | - |
| micro_units[default] divw_dep default/axi | 3,090,443.8 | 4,944,710.0 | - | - |
| micro_units[default] divw_dep default/soc | 3,097,923.4 | 4,956,677.5 | - | - |
| micro_units[default] rem_indep default/axi | 1,776,001.8 | 2,841,602.8 | - | - |
| micro_units[default] rem_indep default/soc | 1,777,234.7 | 2,843,575.6 | - | - |
| micro_units[default] fadd_d_dep default/axi | 9,927,097.9 | 15,883,356.6 | - | - |
| micro_units[default] fadd_d_dep default/soc | 10,083,504.0 | 16,133,606.4 | - | - |
| micro_units[default] fadd_d_indep default/axi | 10,105,795.0 | 16,169,272.1 | - | - |
| micro_units[default] fadd_d_indep default/soc | 10,145,846.5 | 16,233,354.5 | - | - |
| micro_units[default] fmul_d_dep default/axi | 10,029,775.9 | 16,047,641.4 | - | - |
| micro_units[default] fmul_d_dep default/soc | 10,108,987.5 | 16,174,380.0 | - | - |
| micro_units[default] fmadd_d_dep default/axi | 7,604,562.7 | 12,167,300.4 | - | - |
| micro_units[default] fmadd_d_dep default/soc | 7,627,219.6 | 12,203,551.4 | - | - |
| micro_units[default] fdiv_d_dep default/axi | 1,882,685.2 | 3,012,296.3 | - | - |
| micro_units[default] fdiv_d_dep default/soc | 1,884,070.8 | 3,014,513.2 | - | - |
| micro_units[default] fdiv_d_indep default/axi | 1,883,072.9 | 3,012,916.7 | - | - |
| micro_units[default] fdiv_d_indep default/soc | 1,884,459.1 | 3,015,134.6 | - | - |
| micro_units[default] fsqrt_d_dep default/axi | 1,881,688.8 | 3,010,702.1 | - | - |
| micro_units[default] fsqrt_d_dep default/soc | 1,884,459.1 | 3,015,134.6 | - | - |
| micro_units[default] fsqrt_d_indep default/axi | 1,885,125.2 | 3,016,200.3 | - | - |
| micro_units[default] fsqrt_d_indep default/soc | 1,885,125.2 | 3,016,200.3 | - | - |
| micro_units[default] fdiv_s_dep default/axi | 3,433,476.4 | 5,493,562.2 | - | - |
| micro_units[default] fdiv_s_dep default/soc | 3,438,087.6 | 5,500,940.1 | - | - |
| micro_units[default] fsqrt_s_dep default/axi | 3,435,688.2 | 5,497,101.1 | - | - |
| micro_units[default] fsqrt_s_dep default/soc | 3,440,305.3 | 5,504,488.5 | - | - |
| micro_vec[default] empty default/axi | 122,137,404.6 | 195,419,847.3 | - | - |
| micro_vec[default] empty default/soc | 197,530,864.2 | 316,049,382.7 | - | - |
| micro_vec[default] vsetvli_same default/axi | 24,691,358.0 | 39,506,172.8 | - | - |
| micro_vec[default] vsetvli_same default/soc | 25,682,183.0 | 41,091,492.8 | - | - |
| micro_vec[default] vsetvli_toggle default/axi | 24,169,184.3 | 38,670,694.9 | - | - |
| micro_vec[default] vsetvli_toggle default/soc | 25,117,739.4 | 40,188,383.0 | - | - |
| micro_vec[default] vadd_e8_vl1 default/axi | 8,298,755.2 | 13,278,008.3 | - | - |
| micro_vec[default] vadd_e8_vl1 default/soc | 8,407,777.2 | 13,452,443.5 | - | - |
| micro_vec[default] vadd_e8_vl2 default/axi | 7,445,323.4 | 11,912,517.4 | - | - |
| micro_vec[default] vadd_e8_vl2 default/soc | 7,445,323.4 | 11,912,517.4 | - | - |
| micro_vec[default] vadd_e8_vl4 default/axi | 6,012,777.2 | 9,620,443.4 | - | - |
| micro_vec[default] vadd_e8_vl4 default/soc | 6,012,777.2 | 9,620,443.4 | - | - |
| micro_vec[default] vadd_e8_vl8 default/axi | 4,341,926.7 | 6,947,082.8 | - | - |
| micro_vec[default] vadd_e8_vl8 default/soc | 4,341,926.7 | 6,947,082.8 | - | - |
| micro_vec[default] vadd_e8_vl16 default/axi | 2,790,859.9 | 4,465,375.9 | - | - |
| micro_vec[default] vadd_e8_vl16 default/soc | 2,790,859.9 | 4,465,375.9 | - | - |
| micro_vec[default] vadd_e8_vl32 default/axi | 1,627,836.0 | 2,604,537.6 | - | - |
| micro_vec[default] vadd_e8_vl32 default/soc | 1,627,836.0 | 2,604,537.6 | - | - |
| micro_vec[default] vadd_e8_vl64 default/axi | 887,853.1 | 1,420,564.9 | - | - |
| micro_vec[default] vadd_e8_vl64 default/soc | 887,853.1 | 1,420,564.9 | - | - |
| micro_vec[default] vadd_e8_vl128 default/axi | 465,048.7 | 744,077.9 | - | - |
| micro_vec[default] vadd_e8_vl128 default/soc | 465,048.7 | 744,077.9 | - | - |
| micro_vec[default] vadd_e8_vl256 default/axi | 238,190.9 | 381,105.5 | - | - |
| micro_vec[default] vadd_e8_vl256 default/soc | 238,190.9 | 381,105.5 | - | - |
| micro_vec[default] vadd_e8_vl512 default/axi | 120,564.5 | 192,903.3 | - | - |
| micro_vec[default] vadd_e8_vl512 default/soc | 120,564.5 | 192,903.3 | - | - |
| micro_vec[default] vle8_vl1 default/axi | 12,355,212.4 | 19,768,339.8 | - | - |
| micro_vec[default] vle8_vl1 default/soc | 12,598,425.2 | 20,157,480.3 | - | - |
| micro_vec[default] vle8_vl2 default/axi | 7,893,438.6 | 12,629,501.7 | - | - |
| micro_vec[default] vle8_vl2 default/soc | 7,893,438.6 | 12,629,501.7 | - | - |
| micro_vec[default] vle8_vl4 default/axi | 4,490,597.8 | 7,184,956.5 | - | - |
| micro_vec[default] vle8_vl4 default/soc | 4,490,597.8 | 7,184,956.5 | - | - |
| micro_vec[default] vle8_vl8 default/axi | 2,411,454.4 | 3,858,327.1 | - | - |
| micro_vec[default] vle8_vl8 default/soc | 2,411,454.4 | 3,858,327.1 | - | - |
| micro_vec[default] vle8_vl16 default/axi | 1,252,054.2 | 2,003,286.6 | - | - |
| micro_vec[default] vle8_vl16 default/soc | 1,252,054.2 | 2,003,286.6 | - | - |
| micro_vec[default] vle8_vl32 default/axi | 638,289.4 | 1,021,263.0 | - | - |
| micro_vec[default] vle8_vl32 default/soc | 638,289.4 | 1,021,263.0 | - | - |
| micro_vec[default] vle8_vl64 default/axi | 322,301.2 | 515,682.0 | - | - |
| micro_vec[default] vle8_vl64 default/soc | 322,301.2 | 515,682.0 | - | - |
| micro_vec[default] vle8_vl128 default/axi | 161,951.5 | 259,122.4 | - | - |
| micro_vec[default] vle8_vl128 default/soc | 161,951.5 | 259,122.4 | - | - |
| micro_vec[default] vle8_vl256 default/axi | 81,177.5 | 129,884.0 | - | - |
| micro_vec[default] vle8_vl256 default/soc | 81,177.5 | 129,884.0 | - | - |
| micro_vec[default] vle8_vl512 default/axi | 40,639.4 | 65,023.0 | - | - |
| micro_vec[default] vle8_vl512 default/soc | 40,639.4 | 65,023.0 | - | - |
| micro_vec[default] vse8_vl1 default/axi | 12,317,167.1 | 19,707,467.3 | - | - |
| micro_vec[default] vse8_vl1 default/soc | 12,558,869.7 | 20,094,191.5 | - | - |
| micro_vec[default] vse8_vl8 default/axi | 2,410,001.5 | 3,856,002.4 | - | - |
| micro_vec[default] vse8_vl8 default/soc | 2,410,001.5 | 3,856,002.4 | - | - |
| micro_vec[default] vse8_vl64 default/axi | 322,275.3 | 515,640.4 | - | - |
| micro_vec[default] vse8_vl64 default/soc | 322,275.3 | 515,640.4 | - | - |
| micro_vec[default] vse8_vl512 default/axi | 40,638.9 | 65,022.3 | - | - |
| micro_vec[default] vse8_vl512 default/soc | 40,638.9 | 65,022.3 | - | - |
| micro_vec[default] vadd_e64_vl8 default/axi | 4,306,864.1 | 6,890,982.5 | - | - |
| micro_vec[default] vadd_e64_vl8 default/soc | 4,336,043.4 | 6,937,669.4 | - | - |
| micro_vec[default] vmul_e64_vl8 default/axi | 886,328.4 | 1,418,125.4 | - | - |
| micro_vec[default] vmul_e64_vl8 default/soc | 887,557.6 | 1,420,092.1 | - | - |
| micro_vec[default] vfadd_e64_vl8 default/axi | 1,145,393.4 | 1,832,629.4 | - | - |
| micro_vec[default] vfadd_e64_vl8 default/soc | 1,147,446.9 | 1,835,915.1 | - | - |
| micro_vec[default] vredsum_e64_vl8 default/axi | 3,773,584.9 | 6,037,735.8 | - | - |
| micro_vec[default] vredsum_e64_vl8 default/soc | 3,795,966.8 | 6,073,546.9 | - | - |
| sha256chain[sdk] sha256 plain C default/axi | 6,301.4 | 10,082.2 | 0.20 MB/s | 0.32 MB/s |
| sha256chain[sdk] sha256 plain C default/soc | 6,301.5 | 10,082.4 | 0.20 MB/s | 0.32 MB/s |
| sha256chain[sdk] sha256 Zknh default/axi | 9,254.5 | 14,807.3 | 0.30 MB/s | 0.47 MB/s |
| sha256chain[sdk] sha256 Zknh default/soc | 9,254.8 | 14,807.7 | 0.30 MB/s | 0.47 MB/s |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/axi | 13,462.1 | 21,539.4 | 0.43 MB/s | 0.69 MB/s |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | 13,464.0 | 21,542.5 | 0.43 MB/s | 0.69 MB/s |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/axi | 109,243.5 | 174,789.7 | 3.50 MB/s | 5.59 MB/s |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | 109,248.2 | 174,797.1 | 3.50 MB/s | 5.59 MB/s |
| sha256chain[sdk] sha256 accel sigil_sha256 default/axi | 22,375.1 | 35,800.1 | 0.72 MB/s | 1.15 MB/s |
| sha256chain[sdk] sha256 accel sigil_sha256 default/soc | 22,376.2 | 35,802.0 | 0.72 MB/s | 1.15 MB/s |
| sha256chain[sdk] sha512 accel sigil_hash default/axi | 25,280.0 | 40,448.0 | 1.62 MB/s | 2.59 MB/s |
| sha256chain[sdk] sha512 accel sigil_hash default/soc | 25,281.4 | 40,450.2 | 1.62 MB/s | 2.59 MB/s |
| sha256chain[sdk] sha3-256 accel sigil_hash default/axi | 45,614.7 | 72,983.6 | 1.46 MB/s | 2.34 MB/s |
| sha256chain[sdk] sha3-256 accel sigil_hash default/soc | 45,616.4 | 72,986.2 | 1.46 MB/s | 2.34 MB/s |
| sha256chain_bulk[sdk] sha256 plain C default/axi | 394.3 | 630.8 | 0.40 MB/s | 0.65 MB/s |
| sha256chain_bulk[sdk] sha256 plain C default/soc | 395.5 | 632.8 | 0.40 MB/s | 0.65 MB/s |
| sha256chain_bulk[sdk] sha256 Zknh default/axi | 577.1 | 923.3 | 0.59 MB/s | 0.95 MB/s |
| sha256chain_bulk[sdk] sha256 Zknh default/soc | 579.4 | 927.1 | 0.59 MB/s | 0.95 MB/s |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/axi | 792.1 | 1,267.4 | 0.81 MB/s | 1.30 MB/s |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | 800.5 | 1,280.8 | 0.82 MB/s | 1.31 MB/s |
| sha256chain_bulk[sdk] sha512 accel sigil_hash default/axi | 13,455.5 | 21,528.8 | 13.78 MB/s | 22.05 MB/s |
| sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | 14,573.0 | 23,316.8 | 14.92 MB/s | 23.88 MB/s |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/axi | 13,520.4 | 21,632.6 | 13.84 MB/s | 22.15 MB/s |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc | 14,634.5 | 23,415.3 | 14.99 MB/s | 23.98 MB/s |

## Where the cycles go (% of cycles in the measured region)

| Run | retire | fetch_lat | fetch_straddle | fetch_miss | branch | jal | jalr | loaduse | muldiv | fpu | vec | dc_lat | dc_miss | io | vls |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| coremark[scalar] default/axi | 36.6 | 40.4 | 5.4 | 0.0 | 4.1 | 0.5 | 0.2 | 0.7 | 2.6 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 |
| coremark[scalar] default/soc | 36.6 | 40.4 | 5.4 | 0.0 | 4.1 | 0.5 | 0.2 | 0.7 | 2.6 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 |
| coremark[sdk] default/axi | 35.9 | 40.5 | 5.9 | 0.0 | 4.0 | 0.5 | 0.3 | 0.7 | 2.6 | 0.0 | 0.1 | 9.3 | 0.0 | 0.0 | 0.2 |
| coremark[sdk] default/soc | 35.9 | 40.5 | 5.9 | 0.0 | 4.0 | 0.5 | 0.3 | 0.7 | 2.6 | 0.0 | 0.1 | 9.3 | 0.0 | 0.0 | 0.2 |
| coremark[validation] default/axi | 36.6 | 40.4 | 5.4 | 0.0 | 4.1 | 0.5 | 0.2 | 0.7 | 2.6 | 0.0 | 0.0 | 9.6 | 0.0 | 0.0 | 0.0 |
| coremark[validation] default/soc | 36.6 | 40.4 | 5.4 | 0.0 | 4.1 | 0.5 | 0.2 | 0.7 | 2.6 | 0.0 | 0.0 | 9.6 | 0.0 | 0.0 | 0.0 |
| dhrystone[scalar] default/axi | 33.7 | 40.6 | 8.9 | 0.0 | 2.3 | 0.7 | 0.7 | 0.1 | 0.2 | 0.0 | 0.0 | 12.7 | 0.0 | 0.0 | 0.0 |
| dhrystone[scalar] default/soc | 33.7 | 40.6 | 8.9 | 0.0 | 2.3 | 0.7 | 0.7 | 0.1 | 0.2 | 0.0 | 0.0 | 12.7 | 0.0 | 0.0 | 0.0 |
| dhrystone[sdk] default/axi | 29.3 | 32.8 | 4.4 | 0.0 | 2.1 | 0.8 | 0.7 | 0.0 | 0.2 | 0.0 | 0.0 | 10.3 | 0.0 | 0.0 | 19.3 |
| dhrystone[sdk] default/soc | 29.3 | 32.9 | 4.4 | 0.0 | 2.1 | 0.8 | 0.7 | 0.0 | 0.2 | 0.0 | 0.0 | 10.3 | 0.0 | 0.0 | 19.3 |
| kernels[autovec] vadd_i32 C default/axi | 5.2 | 7.2 | 2.6 | 0.0 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.9 | 0.0 | 0.4 | 0.0 | 74.2 |
| kernels[autovec] vadd_i32 C default/soc | 5.3 | 7.4 | 2.6 | 0.0 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 10.2 | 0.0 | 0.1 | 0.0 | 74.0 |
| kernels[autovec] vadd_i32 RVV default/axi | 0.8 | 0.9 | 0.2 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.2 | 0.0 | 0.3 | 0.0 | 88.4 |
| kernels[autovec] vadd_i32 RVV default/soc | 0.9 | 1.0 | 0.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.0 | 0.1 | 0.0 | 88.0 |
| kernels[autovec] vadd_i64 C default/axi | 9.0 | 10.0 | 2.7 | 0.1 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 10.4 | 0.0 | 0.3 | 0.0 | 66.5 |
| kernels[autovec] vadd_i64 C default/soc | 9.3 | 10.3 | 2.8 | 0.0 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 10.8 | 0.0 | 0.1 | 0.0 | 65.8 |
| kernels[autovec] vadd_i64 RVV default/axi | 1.6 | 1.8 | 0.4 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.3 | 0.0 | 0.7 | 0.0 | 85.8 |
| kernels[autovec] vadd_i64 RVV default/soc | 1.7 | 1.9 | 0.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.0 | 0.3 | 0.0 | 85.6 |
| kernels[autovec] daxpy C default/axi | 6.1 | 6.8 | 1.8 | 0.1 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 40.4 | 0.0 | 0.4 | 0.0 | 43.8 |
| kernels[autovec] daxpy C default/soc | 6.2 | 6.9 | 1.9 | 0.0 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 40.8 | 0.0 | 0.1 | 0.0 | 43.5 |
| kernels[autovec] daxpy RVV default/axi | 0.9 | 1.1 | 0.3 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 44.5 | 0.0 | 0.2 | 0.0 | 52.9 |
| kernels[autovec] daxpy RVV default/soc | 0.9 | 1.1 | 0.3 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.6 | 0.0 | 0.0 | 0.0 | 51.9 |
| kernels[autovec] saxpy C default/axi | 3.3 | 4.7 | 1.7 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.8 | 0.0 | 0.1 | 0.0 | 47.1 |
| kernels[autovec] saxpy C default/soc | 3.4 | 4.7 | 1.7 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 43.0 | 0.0 | 0.0 | 0.0 | 46.9 |
| kernels[autovec] saxpy RVV default/axi | 0.5 | 0.5 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.8 | 0.0 | 0.1 | 0.0 | 52.9 |
| kernels[autovec] saxpy RVV default/soc | 0.5 | 0.6 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 46.3 | 0.0 | 0.0 | 0.0 | 52.4 |
| kernels[autovec] ddot C default/axi | 6.5 | 9.0 | 3.0 | 0.1 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 56.9 | 0.0 | 0.2 | 0.0 | 23.8 |
| kernels[autovec] ddot C default/soc | 6.6 | 9.1 | 3.0 | 0.0 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.0 | 0.0 | 0.1 | 0.0 | 23.8 |
| kernels[autovec] ddot RVV default/axi | 1.0 | 1.3 | 0.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 58.0 | 0.0 | 0.0 | 0.0 | 38.9 |
| kernels[autovec] ddot RVV default/soc | 1.1 | 1.3 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 58.1 | 0.0 | 0.0 | 0.0 | 38.9 |
| kernels[autovec] idot_i32 C default/axi | 6.6 | 8.3 | 3.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.6 | 0.0 | 0.0 | 0.0 | 39.1 |
| kernels[autovec] idot_i32 C default/soc | 6.6 | 8.3 | 3.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.6 | 0.0 | 0.0 | 0.0 | 39.1 |
| kernels[autovec] idot_i32 RVV default/axi | 1.1 | 1.4 | 0.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.2 | 0.0 | 0.0 | 0.0 | 47.6 |
| kernels[autovec] idot_i32 RVV default/soc | 1.1 | 1.4 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.2 | 0.0 | 0.0 | 0.0 | 47.6 |
| kernels[autovec] memcpy C default/axi | 31.2 | 37.5 | 18.6 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.4 | 0.3 | 0.0 | 0.0 |
| kernels[autovec] memcpy C default/soc | 31.3 | 37.5 | 18.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.4 | 0.1 | 0.0 | 0.0 |
| kernels[autovec] memcpy RVV default/axi | 2.1 | 2.6 | 0.8 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.7 | 0.0 | 93.3 |
| kernels[autovec] memcpy RVV default/soc | 2.1 | 2.6 | 0.8 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.0 | 93.9 |
| kernels[autovec] memcpy RVV-e8 default/axi | 0.3 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 99.1 |
| kernels[autovec] memcpy RVV-e8 default/soc | 0.3 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.2 |
| kernels[autovec] memset C default/axi | 29.8 | 39.7 | 9.9 | 0.2 | 9.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.8 | 0.0 | 0.0 |
| kernels[autovec] memset C default/soc | 30.0 | 40.0 | 9.9 | 0.1 | 9.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.3 | 0.0 | 0.0 |
| kernels[autovec] memset RVV default/axi | 3.4 | 4.0 | 0.6 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 3.9 | 0.1 | 0.0 | 0.0 | 87.0 |
| kernels[autovec] memset RVV default/soc | 3.4 | 4.0 | 0.6 | 0.2 | 0.4 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 3.9 | 0.1 | 0.0 | 0.0 | 87.3 |
| kernels[autovec] memset RVV-e8 default/axi | 0.4 | 0.6 | 0.2 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.0 | 0.0 | 0.0 | 0.0 | 94.7 |
| kernels[autovec] memset RVV-e8 default/soc | 0.4 | 0.6 | 0.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.0 | 0.0 | 0.0 | 0.0 | 94.8 |
| kernels[autovec] dgemm C default/axi | 28.2 | 28.5 | 0.6 | 0.0 | 4.3 | 0.0 | 0.0 | 0.0 | 0.0 | 26.7 | 0.0 | 9.1 | 2.7 | 0.0 | 0.0 |
| kernels[autovec] dgemm C default/soc | 28.7 | 29.0 | 0.6 | 0.0 | 4.4 | 0.0 | 0.0 | 0.0 | 0.0 | 27.2 | 0.0 | 9.2 | 0.9 | 0.0 | 0.0 |
| kernels[autovec] dgemm RVV default/axi | 1.7 | 1.7 | 0.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 66.5 | 0.3 | 1.4 | 0.0 | 28.1 |
| kernels[autovec] dgemm RVV default/soc | 1.7 | 1.8 | 0.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.5 | 0.3 | 0.5 | 0.0 | 26.9 |
| kernels[autovec] sgemm C default/axi | 25.6 | 29.6 | 8.2 | 0.0 | 3.9 | 0.1 | 0.0 | 0.0 | 0.0 | 24.3 | 0.0 | 8.2 | 0.0 | 0.0 | 0.0 |
| kernels[autovec] sgemm C default/soc | 25.6 | 29.6 | 8.2 | 0.0 | 3.9 | 0.1 | 0.0 | 0.0 | 0.0 | 24.3 | 0.0 | 8.2 | 0.0 | 0.0 | 0.0 |
| kernels[autovec] sgemm RVV default/axi | 1.7 | 2.5 | 1.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.4 | 0.3 | 0.0 | 0.0 | 26.0 |
| kernels[autovec] sgemm RVV default/soc | 1.7 | 2.5 | 1.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.4 | 0.3 | 0.0 | 0.0 | 25.9 |
| kernels[autovec] fir_f32 C default/axi | 5.8 | 7.4 | 2.2 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.8 | 0.3 | 0.0 | 0.0 | 26.3 |
| kernels[autovec] fir_f32 C default/soc | 5.8 | 7.4 | 2.2 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.8 | 0.3 | 0.0 | 0.0 | 26.3 |
| kernels[autovec] fir_f32 RVV default/axi | 0.5 | 0.5 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 70.9 | 0.1 | 0.0 | 0.0 | 28.0 |
| kernels[autovec] fir_f32 RVV default/soc | 0.5 | 0.5 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.0 | 0.1 | 0.0 | 0.0 | 28.0 |
| kernels[autovec] mac_i8 C default/axi | 4.6 | 5.4 | 1.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 48.3 | 0.0 | 0.0 | 0.0 | 39.9 |
| kernels[autovec] mac_i8 C default/soc | 4.6 | 5.5 | 1.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 48.3 | 0.0 | 0.0 | 0.0 | 39.9 |
| kernels[autovec] mac_i8 RVV default/axi | 0.4 | 0.4 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.7 | 0.0 | 0.0 | 0.0 | 49.4 |
| kernels[autovec] mac_i8 RVV default/soc | 0.4 | 0.4 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.7 | 0.0 | 0.0 | 0.0 | 49.4 |
| kernels[autovec] mac_i16 C default/axi | 4.0 | 5.0 | 2.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 41.6 | 0.0 | 0.0 | 0.0 | 47.3 |
| kernels[autovec] mac_i16 C default/soc | 4.0 | 5.0 | 2.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 41.6 | 0.0 | 0.0 | 0.0 | 47.3 |
| kernels[autovec] mac_i16 RVV default/axi | 0.6 | 0.8 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.4 | 0.0 | 0.0 | 0.0 | 52.8 |
| kernels[autovec] mac_i16 RVV default/soc | 0.6 | 0.8 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.4 | 0.0 | 0.0 | 0.0 | 52.8 |
| kernels[scalar] vadd_i32 C default/axi | 41.9 | 36.7 | 0.0 | 0.0 | 5.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.7 | 0.3 | 0.0 | 0.0 |
| kernels[scalar] vadd_i32 C default/soc | 42.0 | 36.8 | 0.0 | 0.0 | 5.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.7 | 0.1 | 0.0 | 0.0 |
| kernels[scalar] vadd_i32 RVV default/axi | 0.8 | 0.9 | 0.2 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.3 | 0.0 | 0.4 | 0.0 | 88.2 |
| kernels[scalar] vadd_i32 RVV default/soc | 0.9 | 1.0 | 0.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.0 | 0.1 | 0.0 | 87.9 |
| kernels[scalar] vadd_i64 C default/axi | 41.1 | 36.0 | 0.0 | 0.1 | 5.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.4 | 2.2 | 0.0 | 0.0 |
| kernels[scalar] vadd_i64 C default/soc | 41.8 | 36.6 | 0.0 | 0.0 | 5.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.6 | 0.7 | 0.0 | 0.0 |
| kernels[scalar] vadd_i64 RVV default/axi | 1.6 | 1.7 | 0.4 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.1 | 0.0 | 0.0 | 0.0 | 86.8 |
| kernels[scalar] vadd_i64 RVV default/soc | 1.7 | 1.9 | 0.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.0 | 0.0 | 0.0 | 86.0 |
| kernels[scalar] daxpy C default/axi | 23.7 | 30.5 | 10.2 | 0.1 | 3.4 | 0.0 | 0.0 | 0.0 | 0.0 | 20.2 | 0.0 | 10.1 | 1.9 | 0.0 | 0.0 |
| kernels[scalar] daxpy C default/soc | 24.0 | 30.9 | 10.3 | 0.0 | 3.4 | 0.0 | 0.0 | 0.0 | 0.0 | 20.5 | 0.0 | 10.3 | 0.6 | 0.0 | 0.0 |
| kernels[scalar] daxpy RVV default/axi | 0.9 | 1.1 | 0.3 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.1 | 0.0 | 0.0 | 0.0 | 52.4 |
| kernels[scalar] daxpy RVV default/soc | 0.9 | 1.1 | 0.3 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.8 | 0.0 | 0.0 | 0.0 | 51.8 |
| kernels[scalar] saxpy C default/axi | 21.7 | 31.0 | 15.5 | 0.0 | 3.1 | 0.0 | 0.0 | 0.0 | 0.0 | 18.6 | 0.0 | 9.3 | 0.9 | 0.0 | 0.0 |
| kernels[scalar] saxpy C default/soc | 21.8 | 31.2 | 15.6 | 0.0 | 3.1 | 0.0 | 0.0 | 0.0 | 0.0 | 18.7 | 0.0 | 9.3 | 0.3 | 0.0 | 0.0 |
| kernels[scalar] saxpy RVV default/axi | 0.5 | 0.5 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 46.0 | 0.0 | 0.0 | 0.0 | 52.7 |
| kernels[scalar] saxpy RVV default/soc | 0.5 | 0.6 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 46.4 | 0.0 | 0.0 | 0.0 | 52.4 |
| kernels[scalar] ddot C default/axi | 23.9 | 31.9 | 8.0 | 0.1 | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.8 | 0.0 | 8.0 | 0.3 | 0.0 | 0.0 |
| kernels[scalar] ddot C default/soc | 24.0 | 32.0 | 8.0 | 0.0 | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.9 | 0.0 | 8.0 | 0.1 | 0.0 | 0.0 |
| kernels[scalar] ddot RVV default/axi | 1.0 | 1.3 | 0.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 58.0 | 0.0 | 0.0 | 0.0 | 38.9 |
| kernels[scalar] ddot RVV default/soc | 1.1 | 1.3 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 58.1 | 0.0 | 0.0 | 0.0 | 38.9 |
| kernels[scalar] idot_i32 C default/axi | 36.8 | 36.8 | 0.0 | 0.0 | 5.2 | 0.0 | 0.0 | 0.0 | 10.5 | 0.0 | 0.0 | 10.5 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] idot_i32 C default/soc | 36.8 | 36.9 | 0.0 | 0.0 | 5.2 | 0.0 | 0.0 | 0.0 | 10.5 | 0.0 | 0.0 | 10.5 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] idot_i32 RVV default/axi | 1.1 | 1.4 | 0.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.2 | 0.0 | 0.0 | 0.0 | 47.6 |
| kernels[scalar] idot_i32 RVV default/soc | 1.1 | 1.4 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.2 | 0.0 | 0.0 | 0.0 | 47.6 |
| kernels[scalar] memcpy C default/axi | 31.1 | 37.4 | 18.5 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.3 | 0.5 | 0.0 | 0.0 |
| kernels[scalar] memcpy C default/soc | 31.3 | 37.5 | 18.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.4 | 0.2 | 0.0 | 0.0 |
| kernels[scalar] memcpy RVV default/axi | 2.0 | 2.6 | 0.8 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 94.1 |
| kernels[scalar] memcpy RVV default/soc | 2.1 | 2.6 | 0.8 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 94.1 |
| kernels[scalar] memcpy RVV-e8 default/axi | 0.3 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 99.1 |
| kernels[scalar] memcpy RVV-e8 default/soc | 0.3 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.2 |
| kernels[scalar] memset C default/axi | 30.0 | 39.9 | 9.9 | 0.2 | 9.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.8 | 0.4 | 0.0 | 0.0 |
| kernels[scalar] memset C default/soc | 30.1 | 40.0 | 9.9 | 0.1 | 9.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.9 | 0.1 | 0.0 | 0.0 |
| kernels[scalar] memset RVV default/axi | 3.4 | 4.0 | 0.6 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 3.9 | 0.1 | 0.0 | 0.0 | 87.0 |
| kernels[scalar] memset RVV default/soc | 3.4 | 4.0 | 0.6 | 0.2 | 0.4 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 3.9 | 0.1 | 0.0 | 0.0 | 87.3 |
| kernels[scalar] memset RVV-e8 default/axi | 0.4 | 0.6 | 0.2 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.0 | 0.0 | 0.0 | 0.0 | 94.7 |
| kernels[scalar] memset RVV-e8 default/soc | 0.4 | 0.6 | 0.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.0 | 0.0 | 0.0 | 0.0 | 94.8 |
| kernels[scalar] dgemm C default/axi | 28.2 | 28.5 | 0.6 | 0.0 | 4.3 | 0.0 | 0.0 | 0.0 | 0.0 | 26.8 | 0.0 | 9.1 | 2.5 | 0.0 | 0.0 |
| kernels[scalar] dgemm C default/soc | 28.7 | 29.0 | 0.6 | 0.0 | 4.4 | 0.0 | 0.0 | 0.0 | 0.0 | 27.2 | 0.0 | 9.2 | 0.8 | 0.0 | 0.0 |
| kernels[scalar] dgemm RVV default/axi | 1.7 | 1.7 | 0.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 66.4 | 0.3 | 1.4 | 0.0 | 28.3 |
| kernels[scalar] dgemm RVV default/soc | 1.7 | 1.8 | 0.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.5 | 0.3 | 0.5 | 0.0 | 27.0 |
| kernels[scalar] sgemm C default/axi | 25.6 | 29.6 | 8.2 | 0.0 | 3.9 | 0.1 | 0.0 | 0.0 | 0.0 | 24.3 | 0.0 | 8.2 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] sgemm C default/soc | 25.6 | 29.6 | 8.2 | 0.0 | 3.9 | 0.1 | 0.0 | 0.0 | 0.0 | 24.3 | 0.0 | 8.2 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] sgemm RVV default/axi | 1.7 | 2.5 | 1.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.4 | 0.3 | 0.0 | 0.0 | 26.0 |
| kernels[scalar] sgemm RVV default/soc | 1.7 | 2.5 | 1.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.4 | 0.3 | 0.0 | 0.0 | 26.0 |
| kernels[scalar] fir_f32 C default/axi | 22.2 | 32.7 | 17.3 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 20.5 | 0.0 | 7.1 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] fir_f32 C default/soc | 22.2 | 32.7 | 17.3 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 20.5 | 0.0 | 7.1 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] fir_f32 RVV default/axi | 0.5 | 0.5 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 70.9 | 0.1 | 0.0 | 0.0 | 28.0 |
| kernels[scalar] fir_f32 RVV default/soc | 0.5 | 0.5 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.0 | 0.1 | 0.0 | 0.0 | 28.0 |
| kernels[scalar] mac_i8 C default/axi | 33.3 | 38.1 | 4.8 | 0.0 | 4.8 | 0.0 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] mac_i8 C default/soc | 33.3 | 38.1 | 4.8 | 0.0 | 4.8 | 0.0 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] mac_i8 RVV default/axi | 0.4 | 0.4 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.7 | 0.0 | 0.0 | 0.0 | 49.4 |
| kernels[scalar] mac_i8 RVV default/soc | 0.4 | 0.4 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.7 | 0.0 | 0.0 | 0.0 | 49.4 |
| kernels[scalar] mac_i16 C default/axi | 33.3 | 38.1 | 4.8 | 0.0 | 4.8 | 0.0 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] mac_i16 C default/soc | 33.3 | 38.1 | 4.8 | 0.0 | 4.8 | 0.0 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 |
| kernels[scalar] mac_i16 RVV default/axi | 0.6 | 0.8 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.4 | 0.0 | 0.0 | 0.0 | 52.8 |
| kernels[scalar] mac_i16 RVV default/soc | 0.6 | 0.8 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.4 | 0.0 | 0.0 | 0.0 | 52.8 |
| micro_dmem[default] empty default/axi | 22.8 | 26.1 | 4.3 | 39.1 | 0.0 | 0.0 | 1.1 | 0.0 | 0.0 | 0.0 | 0.0 | 6.5 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] empty default/soc | 31.3 | 35.8 | 6.0 | 16.4 | 0.0 | 0.0 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 9.0 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_1k default/axi | 33.4 | 2.2 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 31.2 | 0.0 | 0.0 | 0.0 | 32.3 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_1k default/soc | 33.5 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.3 | 0.0 | 0.0 | 0.0 | 32.4 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_2k default/axi | 33.4 | 2.2 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 31.2 | 0.0 | 0.0 | 0.0 | 32.3 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_2k default/soc | 33.5 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.3 | 0.0 | 0.0 | 0.0 | 32.4 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_4k default/axi | 33.4 | 2.2 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 31.2 | 0.0 | 0.0 | 0.0 | 32.3 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_4k default/soc | 33.5 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.3 | 0.0 | 0.0 | 0.0 | 32.4 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_8k default/axi | 33.4 | 2.2 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 31.2 | 0.0 | 0.0 | 0.0 | 32.3 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_8k default/soc | 33.5 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.3 | 0.0 | 0.0 | 0.0 | 32.4 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_12k default/axi | 33.4 | 2.2 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 31.2 | 0.0 | 0.0 | 0.0 | 32.3 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_12k default/soc | 33.5 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.3 | 0.0 | 0.0 | 0.0 | 32.4 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_16k default/axi | 32.6 | 2.1 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 30.4 | 0.0 | 0.0 | 0.0 | 31.5 | 2.6 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_16k default/soc | 33.2 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.0 | 0.0 | 0.0 | 0.0 | 32.1 | 0.8 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_20k default/axi | 5.9 | 0.4 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 5.6 | 0.0 | 0.0 | 0.0 | 5.7 | 82.2 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_20k default/soc | 13.9 | 0.9 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 13.0 | 0.0 | 0.0 | 0.0 | 13.4 | 58.6 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_24k default/axi | 4.1 | 0.3 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 3.8 | 0.0 | 0.0 | 0.0 | 3.9 | 87.8 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_24k default/soc | 10.4 | 0.7 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 9.8 | 0.0 | 0.0 | 0.0 | 10.1 | 68.8 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_32k default/axi | 3.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 2.9 | 0.0 | 0.0 | 0.0 | 3.0 | 90.6 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_32k default/soc | 8.5 | 0.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 7.9 | 0.0 | 0.0 | 0.0 | 8.2 | 74.7 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_64k default/axi | 2.7 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 2.5 | 0.0 | 0.0 | 0.0 | 2.6 | 92.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_64k default/soc | 7.4 | 0.5 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 6.9 | 0.0 | 0.0 | 0.0 | 7.2 | 77.8 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_128k default/axi | 2.6 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 2.5 | 0.0 | 0.0 | 0.0 | 2.6 | 92.1 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_128k default/soc | 7.3 | 0.5 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 6.9 | 0.0 | 0.0 | 0.0 | 7.1 | 78.1 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_256k default/axi | 2.6 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 2.5 | 0.0 | 0.0 | 0.0 | 2.6 | 92.1 | 0.0 | 0.0 |
| micro_dmem[default] chase_rand_256k default/soc | 7.3 | 0.5 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 6.9 | 0.0 | 0.0 | 0.0 | 7.1 | 78.1 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_4k default/axi | 33.4 | 2.2 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 31.2 | 0.0 | 0.0 | 0.0 | 32.3 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_4k default/soc | 33.5 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.3 | 0.0 | 0.0 | 0.0 | 32.4 | 0.0 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_8k default/axi | 33.3 | 2.2 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 31.2 | 0.0 | 0.0 | 0.0 | 32.2 | 0.3 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_8k default/soc | 33.5 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.3 | 0.0 | 0.0 | 0.0 | 32.3 | 0.1 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_16k default/axi | 32.6 | 2.1 | 0.0 | 0.3 | 0.5 | 0.0 | 0.0 | 30.4 | 0.0 | 0.0 | 0.0 | 31.5 | 2.6 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_16k default/soc | 33.2 | 2.2 | 0.0 | 0.1 | 0.5 | 0.0 | 0.0 | 31.0 | 0.0 | 0.0 | 0.0 | 32.1 | 0.8 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_32k default/axi | 3.8 | 0.2 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 3.6 | 0.0 | 0.0 | 0.0 | 3.7 | 88.6 | 0.0 | 0.0 |
| micro_dmem[default] chase_seq_32k default/soc | 9.9 | 0.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 9.2 | 0.0 | 0.0 | 0.0 | 9.6 | 70.5 | 0.0 | 0.0 |
| micro_dmem[default] stream_ld default/axi | 15.9 | 9.4 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 13.5 | 60.8 | 0.0 | 0.0 |
| micro_dmem[default] stream_ld default/soc | 27.6 | 16.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.4 | 32.2 | 0.0 | 0.0 |
| micro_dmem[default] stream_st default/axi | 9.0 | 5.3 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 7.7 | 77.7 | 0.0 | 0.0 |
| micro_dmem[default] stream_st default/soc | 18.8 | 11.1 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 16.0 | 53.7 | 0.0 | 0.0 |
| micro_imem[default] empty default/axi | 20.9 | 25.3 | 5.5 | 39.6 | 0.0 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 0.0 | 6.6 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] empty default/soc | 28.8 | 34.8 | 7.6 | 16.7 | 0.0 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 9.1 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_1k default/axi | 49.4 | 50.0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_1k default/soc | 49.4 | 50.0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_2k default/axi | 49.7 | 50.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_2k default/soc | 49.7 | 50.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_3k default/axi | 49.8 | 50.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_3k default/soc | 49.8 | 50.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_4k default/axi | 49.9 | 50.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_4k default/soc | 49.9 | 50.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_6k default/axi | 47.5 | 47.6 | 0.0 | 4.7 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_6k default/soc | 49.2 | 49.2 | 0.0 | 1.5 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_8k default/axi | 48.0 | 48.1 | 0.0 | 3.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_8k default/soc | 49.3 | 49.4 | 0.0 | 1.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_12k default/axi | 28.5 | 28.5 | 0.0 | 43.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_12k default/soc | 40.6 | 40.6 | 0.0 | 18.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_16k default/axi | 27.0 | 27.0 | 0.0 | 46.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_16k default/soc | 39.6 | 39.7 | 0.0 | 20.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_24k default/axi | 25.7 | 25.7 | 0.0 | 48.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_24k default/soc | 38.8 | 38.8 | 0.0 | 22.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_32k default/axi | 25.1 | 25.2 | 0.0 | 49.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_imem[default] ifoot_32k default/soc | 38.4 | 38.4 | 0.0 | 23.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] empty default/axi | 20.9 | 24.2 | 4.4 | 2.2 | 0.0 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 0.0 | 6.6 | 39.6 | 0.0 | 0.0 |
| micro_pipe[default] empty default/soc | 28.8 | 33.3 | 6.1 | 3.0 | 0.0 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 9.1 | 16.7 | 0.0 | 0.0 |
| micro_pipe[default] loop default/axi | 33.3 | 49.9 | 0.0 | 0.1 | 16.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] loop default/soc | 33.3 | 50.0 | 0.0 | 0.0 | 16.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] alu32_dep default/axi | 49.5 | 49.7 | 0.1 | 0.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] alu32_dep default/soc | 49.6 | 49.9 | 0.1 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] alu32_indep default/axi | 49.5 | 49.7 | 0.1 | 0.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] alu32_indep default/soc | 49.6 | 49.9 | 0.1 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] alu16_dep default/axi | 49.5 | 49.7 | 0.1 | 0.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] alu16_dep default/soc | 49.6 | 49.9 | 0.1 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] alu32_straddle default/axi | 24.9 | 49.9 | 24.9 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] alu32_straddle default/soc | 25.0 | 49.9 | 25.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] br_nt default/axi | 49.5 | 49.7 | 0.1 | 0.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] br_nt default/soc | 49.6 | 49.9 | 0.1 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] br_taken default/axi | 25.0 | 49.9 | 0.0 | 0.2 | 24.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] br_taken default/soc | 25.1 | 49.9 | 0.0 | 0.1 | 24.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] jal default/axi | 25.0 | 49.9 | 0.0 | 0.2 | 0.1 | 24.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] jal default/soc | 25.1 | 49.9 | 0.0 | 0.1 | 0.1 | 24.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] call_ret default/axi | 30.0 | 49.9 | 0.0 | 0.1 | 0.0 | 10.0 | 10.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] call_ret default/soc | 30.0 | 50.0 | 0.0 | 0.0 | 0.0 | 10.0 | 10.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] jalr_call_ret default/axi | 30.0 | 50.0 | 0.0 | 0.0 | 0.0 | 0.0 | 19.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] jalr_call_ret default/soc | 30.0 | 50.0 | 0.0 | 0.0 | 0.0 | 0.0 | 19.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] brpat_never default/axi | 49.7 | 48.5 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.5 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] brpat_never default/soc | 49.8 | 48.5 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.5 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] brpat_always default/axi | 40.4 | 48.8 | 0.0 | 0.0 | 9.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.2 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] brpat_always default/soc | 40.4 | 48.8 | 0.0 | 0.0 | 9.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.2 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] brpat_alt default/axi | 44.6 | 48.7 | 0.0 | 0.0 | 5.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.3 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] brpat_alt default/soc | 44.6 | 48.7 | 0.0 | 0.0 | 5.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.3 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] brpat_rand default/axi | 44.6 | 48.7 | 0.0 | 0.0 | 5.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.3 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] brpat_rand default/soc | 44.6 | 48.7 | 0.0 | 0.0 | 5.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.3 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] ld_dep default/axi | 33.4 | 0.7 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 32.7 | 0.0 | 0.0 | 0.0 | 33.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] ld_dep default/soc | 33.4 | 0.7 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 32.7 | 0.0 | 0.0 | 0.0 | 33.0 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] ld_indep default/axi | 39.8 | 20.3 | 0.0 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 39.3 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] ld_indep default/soc | 39.9 | 20.4 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 39.4 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] ld_use1 default/axi | 49.8 | 25.1 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 24.8 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] ld_use1 default/soc | 49.9 | 25.2 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 24.8 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] ld_use2 default/axi | 49.8 | 25.1 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 24.8 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] ld_use2 default/soc | 49.8 | 25.2 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 24.8 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] st default/axi | 39.8 | 20.3 | 0.0 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 39.3 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] st default/soc | 39.9 | 20.4 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 39.4 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] rdcycle default/axi | 49.4 | 49.5 | 0.0 | 0.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 |
| micro_pipe[default] rdcycle default/soc | 49.7 | 49.8 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 |
| micro_pipe[default] rdtime default/axi | 49.5 | 49.7 | 0.1 | 0.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] rdtime default/soc | 49.6 | 49.9 | 0.1 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrr default/axi | 49.5 | 49.7 | 0.0 | 0.5 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrr default/soc | 49.7 | 49.9 | 0.0 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrw default/axi | 49.5 | 49.7 | 0.1 | 0.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrw default/soc | 49.6 | 49.9 | 0.1 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrrw default/axi | 49.5 | 49.7 | 0.0 | 0.4 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] csrrw default/soc | 49.7 | 49.9 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] fence default/axi | 49.7 | 49.9 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_pipe[default] fence default/soc | 49.7 | 49.9 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] empty default/axi | 22.8 | 26.1 | 4.3 | 38.0 | 0.0 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 0.0 | 6.5 | 0.0 | 0.0 | 0.0 |
| micro_units[default] empty default/soc | 31.3 | 35.8 | 6.0 | 14.9 | 0.0 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 9.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] mul_dep default/axi | 25.1 | 25.8 | 0.4 | 0.8 | 0.3 | 0.0 | 0.0 | 0.0 | 47.3 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] mul_dep default/soc | 25.2 | 26.0 | 0.4 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 47.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] mul_indep default/axi | 24.9 | 25.2 | 0.0 | 1.6 | 0.3 | 0.0 | 0.0 | 0.0 | 46.9 | 0.0 | 0.0 | 0.1 | 0.8 | 0.0 | 0.0 |
| micro_units[default] mul_indep default/soc | 25.3 | 25.7 | 0.0 | 0.5 | 0.3 | 0.0 | 0.0 | 0.0 | 47.7 | 0.0 | 0.0 | 0.1 | 0.3 | 0.0 | 0.0 |
| micro_units[default] div_dep default/axi | 2.9 | 3.0 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_dep default/soc | 2.9 | 3.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 94.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_indep default/axi | 2.9 | 3.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 93.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_indep default/soc | 2.9 | 3.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 94.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_short default/axi | 25.2 | 25.5 | 0.0 | 0.8 | 0.4 | 0.0 | 0.0 | 0.0 | 47.9 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] div_short default/soc | 25.3 | 25.7 | 0.0 | 0.3 | 0.4 | 0.0 | 0.0 | 0.0 | 48.1 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] divw_dep default/axi | 5.2 | 5.3 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 89.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 |
| micro_units[default] divw_dep default/soc | 5.2 | 5.3 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 89.2 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_units[default] rem_indep default/axi | 3.0 | 3.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] rem_indep default/soc | 3.0 | 3.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fadd_d_dep default/axi | 16.8 | 17.0 | 0.1 | 1.1 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 63.5 | 0.0 | 0.1 | 1.1 | 0.0 | 0.0 |
| micro_units[default] fadd_d_dep default/soc | 17.0 | 17.3 | 0.1 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 64.5 | 0.0 | 0.1 | 0.3 | 0.0 | 0.0 |
| micro_units[default] fadd_d_indep default/axi | 17.0 | 17.3 | 0.1 | 0.6 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 64.7 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fadd_d_indep default/soc | 17.1 | 17.4 | 0.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 64.9 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fmul_d_dep default/axi | 16.9 | 17.3 | 0.2 | 0.5 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 64.2 | 0.0 | 0.1 | 0.6 | 0.0 | 0.0 |
| micro_units[default] fmul_d_dep default/soc | 17.1 | 17.4 | 0.2 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 64.7 | 0.0 | 0.1 | 0.2 | 0.0 | 0.0 |
| micro_units[default] fmadd_d_dep default/axi | 12.9 | 13.2 | 0.2 | 0.5 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 73.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fmadd_d_dep default/soc | 12.9 | 13.2 | 0.2 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 73.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_d_dep default/axi | 3.2 | 3.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_d_dep default/soc | 3.2 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_d_indep default/axi | 3.2 | 3.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_d_indep default/soc | 3.2 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_d_dep default/axi | 3.2 | 3.2 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.3 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 |
| micro_units[default] fsqrt_d_dep default/soc | 3.2 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_d_indep default/axi | 3.2 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_d_indep default/soc | 3.2 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_s_dep default/axi | 5.8 | 5.9 | 0.1 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 87.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fdiv_s_dep default/soc | 5.8 | 5.9 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_s_dep default/axi | 5.8 | 5.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_units[default] fsqrt_s_dep default/soc | 5.8 | 5.9 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 88.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] empty default/axi | 16.8 | 19.8 | 4.6 | 0.8 | 0.0 | 0.8 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 4.6 | 51.9 | 0.0 | 0.0 |
| micro_vec[default] empty default/soc | 27.2 | 32.1 | 7.4 | 1.2 | 0.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 0.0 | 7.4 | 22.2 | 0.0 | 0.0 |
| micro_vec[default] vsetvli_same default/axi | 45.2 | 46.5 | 0.5 | 5.6 | 1.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.9 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vsetvli_same default/soc | 47.0 | 48.3 | 0.5 | 1.8 | 1.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 1.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vsetvli_toggle default/axi | 44.3 | 46.5 | 1.5 | 5.4 | 1.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.9 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vsetvli_toggle default/soc | 46.0 | 48.4 | 1.6 | 1.7 | 1.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.9 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl1 default/axi | 15.1 | 15.7 | 0.2 | 1.8 | 0.4 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 66.4 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl1 default/soc | 15.3 | 15.9 | 0.2 | 0.5 | 0.4 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 67.3 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl2 default/axi | 13.6 | 14.1 | 0.2 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.5 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl2 default/soc | 13.6 | 14.1 | 0.2 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.5 | 0.3 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl4 default/axi | 11.0 | 11.3 | 0.2 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 77.0 | 0.2 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl4 default/soc | 11.0 | 11.3 | 0.2 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 77.0 | 0.2 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl8 default/axi | 7.9 | 8.2 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.4 | 0.2 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl8 default/soc | 7.9 | 8.2 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.4 | 0.2 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl16 default/axi | 5.1 | 5.3 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.3 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl16 default/soc | 5.1 | 5.3 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.3 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl32 default/axi | 3.0 | 3.1 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl32 default/soc | 3.0 | 3.1 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl64 default/axi | 1.6 | 1.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.6 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl64 default/soc | 1.6 | 1.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.6 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl128 default/axi | 0.8 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.2 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl128 default/soc | 0.8 | 0.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.2 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl256 default/axi | 0.4 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.1 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl256 default/soc | 0.4 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.1 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl512 default/axi | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e8_vl512 default/soc | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vle8_vl1 default/axi | 22.5 | 13.6 | 0.7 | 2.8 | 0.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.0 | 59.3 |
| micro_vec[default] vle8_vl1 default/soc | 23.0 | 13.9 | 0.7 | 0.9 | 0.6 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.0 | 60.5 |
| micro_vec[default] vle8_vl2 default/axi | 14.4 | 8.7 | 0.4 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.3 | 0.0 | 0.0 | 75.8 |
| micro_vec[default] vle8_vl2 default/soc | 14.4 | 8.7 | 0.4 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.3 | 0.0 | 0.0 | 75.8 |
| micro_vec[default] vle8_vl4 default/axi | 8.2 | 4.9 | 0.3 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 86.2 |
| micro_vec[default] vle8_vl4 default/soc | 8.2 | 4.9 | 0.3 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 86.2 |
| micro_vec[default] vle8_vl8 default/axi | 4.4 | 2.7 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 92.6 |
| micro_vec[default] vle8_vl8 default/soc | 4.4 | 2.7 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 92.6 |
| micro_vec[default] vle8_vl16 default/axi | 2.3 | 1.4 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.2 |
| micro_vec[default] vle8_vl16 default/soc | 2.3 | 1.4 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.2 |
| micro_vec[default] vle8_vl32 default/axi | 1.2 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.0 |
| micro_vec[default] vle8_vl32 default/soc | 1.2 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.0 |
| micro_vec[default] vle8_vl64 default/axi | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 |
| micro_vec[default] vle8_vl64 default/soc | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 |
| micro_vec[default] vle8_vl128 default/axi | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 |
| micro_vec[default] vle8_vl128 default/soc | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 |
| micro_vec[default] vle8_vl256 default/axi | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8 |
| micro_vec[default] vle8_vl256 default/soc | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8 |
| micro_vec[default] vle8_vl512 default/axi | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 |
| micro_vec[default] vle8_vl512 default/soc | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 |
| micro_vec[default] vse8_vl1 default/axi | 22.6 | 13.7 | 0.7 | 2.8 | 0.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.0 | 59.1 |
| micro_vec[default] vse8_vl1 default/soc | 23.1 | 14.0 | 0.7 | 0.9 | 0.5 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.0 | 60.3 |
| micro_vec[default] vse8_vl8 default/axi | 4.4 | 2.7 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 92.5 |
| micro_vec[default] vse8_vl8 default/soc | 4.4 | 2.7 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 92.5 |
| micro_vec[default] vse8_vl64 default/axi | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 |
| micro_vec[default] vse8_vl64 default/soc | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 |
| micro_vec[default] vse8_vl512 default/axi | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 |
| micro_vec[default] vse8_vl512 default/soc | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 |
| micro_vec[default] vadd_e64_vl8 default/axi | 7.8 | 8.0 | 0.1 | 1.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 82.7 | 0.2 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vadd_e64_vl8 default/soc | 7.9 | 8.1 | 0.1 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.3 | 0.2 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vmul_e64_vl8 default/axi | 1.6 | 1.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.4 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vmul_e64_vl8 default/soc | 1.6 | 1.7 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.6 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vfadd_e64_vl8 default/axi | 2.1 | 2.2 | 0.1 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 95.3 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vfadd_e64_vl8 default/soc | 2.1 | 2.2 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 95.5 | 0.0 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vredsum_e64_vl8 default/axi | 6.9 | 7.2 | 0.2 | 0.8 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 84.5 | 0.1 | 0.0 | 0.0 | 0.0 |
| micro_vec[default] vredsum_e64_vl8 default/soc | 6.9 | 7.2 | 0.2 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 85.0 | 0.1 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 plain C default/axi | 36.6 | 45.9 | 11.4 | 0.0 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 plain C default/soc | 36.6 | 45.9 | 11.4 | 0.0 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.7 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 Zknh default/axi | 39.5 | 44.7 | 6.9 | 0.0 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 6.9 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 Zknh default/soc | 39.5 | 44.7 | 6.9 | 0.0 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 6.9 | 0.0 | 0.0 | 0.0 |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/axi | 4.6 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.6 | 0.1 | 0.0 | 0.0 | 2.1 |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | 4.6 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.6 | 0.1 | 0.0 | 0.0 | 2.1 |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/axi | 27.8 | 33.4 | 3.3 | 0.0 | 4.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.6 | 0.0 | 21.7 | 0.0 |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | 27.8 | 33.4 | 3.3 | 0.0 | 4.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.6 | 0.0 | 21.7 | 0.0 |
| sha256chain[sdk] sha256 accel sigil_sha256 default/axi | 36.0 | 40.8 | 7.9 | 0.0 | 2.2 | 0.1 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 8.3 | 0.0 | 4.4 | 0.0 |
| sha256chain[sdk] sha256 accel sigil_sha256 default/soc | 36.0 | 40.9 | 7.9 | 0.0 | 2.2 | 0.1 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 8.3 | 0.0 | 4.4 | 0.0 |
| sha256chain[sdk] sha512 accel sigil_hash default/axi | 40.0 | 41.9 | 2.4 | 0.0 | 3.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 5.5 | 0.0 | 6.5 | 0.0 |
| sha256chain[sdk] sha512 accel sigil_hash default/soc | 40.0 | 41.9 | 2.4 | 0.0 | 3.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 5.5 | 0.0 | 6.5 | 0.0 |
| sha256chain[sdk] sha3-256 accel sigil_hash default/axi | 39.6 | 42.2 | 3.5 | 0.0 | 3.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 5.5 | 0.0 | 5.8 | 0.0 |
| sha256chain[sdk] sha3-256 accel sigil_hash default/soc | 39.6 | 42.2 | 3.5 | 0.0 | 3.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 5.5 | 0.0 | 5.8 | 0.0 |
| sha256chain_bulk[sdk] sha256 plain C default/axi | 36.5 | 45.9 | 11.4 | 0.0 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.4 | 0.4 | 0.0 | 0.0 |
| sha256chain_bulk[sdk] sha256 plain C default/soc | 36.6 | 46.0 | 11.4 | 0.0 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.4 | 0.1 | 0.0 | 0.0 |
| sha256chain_bulk[sdk] sha256 Zknh default/axi | 39.5 | 44.7 | 6.4 | 0.0 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 6.7 | 0.6 | 0.0 | 0.0 |
| sha256chain_bulk[sdk] sha256 Zknh default/soc | 39.6 | 44.9 | 6.5 | 0.0 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 6.7 | 0.2 | 0.0 | 0.0 |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/axi | 4.4 | 3.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 88.2 | 0.1 | 0.0 | 0.0 | 4.2 |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | 4.5 | 3.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.1 | 0.1 | 0.0 | 0.0 | 3.2 |
| sha256chain_bulk[sdk] sha512 accel sigil_hash default/axi | 22.4 | 27.9 | 0.0 | 0.0 | 5.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.1 | 11.0 | 22.1 | 0.0 |
| sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | 24.2 | 30.2 | 0.0 | 0.0 | 6.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.0 | 3.7 | 23.9 | 0.0 |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/axi | 22.3 | 27.9 | 0.0 | 0.0 | 5.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 11.1 | 11.0 | 22.2 | 0.0 |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc | 24.2 | 30.2 | 0.0 | 0.0 | 6.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.0 | 3.6 | 24.0 | 0.0 |

Columns: `retire` = retire (base); `fetch_lat` = fetch: I$ hit latency / issue gap; `fetch_straddle` = fetch: 32-bit instr straddles a word; `fetch_miss` = fetch: I$ miss; `branch` = squashed: taken branch; `jal` = squashed: jal; `jalr` = squashed: jalr; `loaduse` = load-use interlock; `muldiv` = EX: M unit (mul/div); `fpu` = EX: FPU; `vec` = EX: vector unit; `dc_lat` = MEM: D$ hit latency; `dc_miss` = MEM: D$ miss; `io` = MEM: uncached device access; `vls` = MEM: vector load/store.

## Events

| Run | alu % | load % | store % | branch % | jal % | jalr % | mul % | div % | fp % | vec % | vls % | vset % | csr % | fence % | rvc % | taken % | redir/ki | squashed | I$ acc/i | I$ miss (/ki) | D$ ld / st | D$ miss (%) | D$ wb | D unc | bus if/df/wb/unc | bus % | bus wait % | M % | FPU % | vec % | vls % | traps |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| coremark[scalar] default/axi | 47.9 | 20.6 | 5.4 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.4 | 58.6 | 141.9 | 683,136 | 1.297 | 39 (0.007) | 1,082,027 / 283,065 | 11 (0.0) | 0 | 0 | 39/11/0/0 | 0.0 | 0.0 | 2.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| coremark[scalar] default/soc | 47.9 | 20.6 | 5.4 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.4 | 58.6 | 141.9 | 683,136 | 1.297 | 39 (0.007) | 1,082,027 / 283,065 | 11 (0.0) | 0 | 0 | 39/11/0/0 | 0.0 | 0.0 | 2.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| coremark[sdk] default/axi | 47.9 | 20.6 | 5.3 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 51.2 | 58.6 | 142.0 | 695,117 | 1.317 | 40 (0.008) | 1,081,947 / 282,988 | 10 (0.0) | 0 | 0 | 40/10/0/0 | 0.0 | 0.0 | 2.6 | 0.0 | 0.1 | 0.2 | 0 / 0 |
| coremark[sdk] default/soc | 47.9 | 20.6 | 5.3 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 51.2 | 58.6 | 142.0 | 695,117 | 1.317 | 40 (0.008) | 1,081,947 / 282,988 | 10 (0.0) | 0 | 0 | 40/10/0/0 | 0.0 | 0.0 | 2.6 | 0.0 | 0.1 | 0.2 | 0 / 0 |
| coremark[validation] default/axi | 47.8 | 20.8 | 5.4 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.5 | 58.5 | 141.7 | 677,757 | 1.298 | 39 (0.007) | 1,090,995 / 281,121 | 11 (0.0) | 0 | 0 | 39/11/0/0 | 0.0 | 0.0 | 2.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| coremark[validation] default/soc | 47.8 | 20.8 | 5.4 | 20.1 | 1.6 | 0.8 | 3.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.5 | 58.5 | 141.7 | 677,757 | 1.298 | 39 (0.007) | 1,090,995 / 281,121 | 11 (0.0) | 0 | 0 | 39/11/0/0 | 0.0 | 0.0 | 2.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| dhrystone[scalar] default/axi | 39.2 | 22.8 | 14.9 | 16.6 | 3.5 | 2.9 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 73.7 | 66.3 | 173.7 | 115,999 | 1.450 | 13 (0.013) | 236,002 / 154,004 | 2 (0.0) | 1 | 0 | 13/2/1/0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| dhrystone[scalar] default/soc | 39.2 | 22.8 | 14.9 | 16.6 | 3.5 | 2.9 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 73.7 | 66.3 | 173.7 | 115,999 | 1.450 | 13 (0.013) | 236,002 / 154,004 | 2 (0.0) | 1 | 0 | 13/2/1/0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| dhrystone[sdk] default/axi | 40.5 | 21.7 | 13.5 | 17.0 | 3.5 | 2.9 | 0.0 | 0.2 | 0.0 | 0.0 | 0.4 | 0.2 | 0.0 | 0.0 | 73.2 | 65.5 | 176.1 | 125,999 | 1.354 | 12 (0.012) | 334,002 / 250,004 | 2 (0.0) | 2 | 0 | 12/2/2/0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 19.4 | 0 / 0 |
| dhrystone[sdk] default/soc | 40.5 | 21.7 | 13.5 | 17.0 | 3.5 | 2.9 | 0.0 | 0.2 | 0.0 | 0.0 | 0.4 | 0.2 | 0.0 | 0.0 | 73.2 | 65.5 | 176.1 | 125,999 | 1.354 | 12 (0.012) | 334,002 / 250,004 | 2 (0.0) | 2 | 0 | 12/2/2/0 | 0.0 | 0.0 | 0.2 | 0.0 | 0.0 | 19.4 | 0 / 0 |
| kernels[autovec] vadd_i32 C default/axi | 40.8 | 0.1 | 0.2 | 10.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 9.6 | 28.9 | 9.6 | 0.3 | 0.0 | 21.1 | 95.1 | 99.1 | 259 | 1.593 | 1 (0.377) | 8,194 / 4,100 | 23 (0.2) | 14 | 0 | 1/23/14/0 | 2.7 | 2.1 | 0.0 | 0.0 | 9.9 | 75.7 | 0 / 0 |
| kernels[autovec] vadd_i32 C default/soc | 40.8 | 0.1 | 0.2 | 10.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 9.6 | 28.9 | 9.6 | 0.3 | 0.0 | 21.1 | 95.1 | 99.1 | 259 | 1.593 | 1 (0.377) | 8,194 / 4,100 | 23 (0.2) | 14 | 0 | 1/23/14/0 | 0.7 | 0.0 | 0.0 | 0.0 | 10.2 | 75.5 | 0 / 0 |
| kernels[autovec] vadd_i32 RVV default/axi | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 39 | 1.384 | 1 (2.688) | 8,194 / 4,100 | 49 (0.4) | 39 | 0 | 1/49/39/0 | 7.3 | 5.5 | 0.0 | 0.0 | 9.2 | 88.6 | 0 / 0 |
| kernels[autovec] vadd_i32 RVV default/soc | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 39 | 1.384 | 1 (2.688) | 8,194 / 4,100 | 49 (0.4) | 39 | 0 | 1/49/39/0 | 1.9 | 0.0 | 0.0 | 0.0 | 9.8 | 88.2 | 0 / 0 |
| kernels[autovec] vadd_i64 C default/axi | 40.6 | 0.1 | 0.2 | 10.3 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 9.7 | 29.0 | 9.7 | 0.3 | 0.0 | 21.0 | 93.8 | 99.2 | 263 | 1.398 | 1 (0.377) | 4,098 / 2,052 | 17 (0.3) | 12 | 0 | 1/17/12/0 | 3.8 | 2.9 | 0.0 | 0.0 | 10.4 | 69.1 | 0 / 0 |
| kernels[autovec] vadd_i64 C default/soc | 40.6 | 0.1 | 0.2 | 10.3 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 9.7 | 29.0 | 9.7 | 0.3 | 0.0 | 21.0 | 93.8 | 99.2 | 263 | 1.398 | 1 (0.377) | 4,098 / 2,052 | 17 (0.3) | 12 | 0 | 1/17/12/0 | 0.9 | 0.0 | 0.0 | 0.0 | 10.8 | 68.5 | 0 / 0 |
| kernels[autovec] vadd_i64 RVV default/axi | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 39 | 1.384 | 1 (2.688) | 4,098 / 2,052 | 21 (0.3) | 20 | 0 | 1/21/20/0 | 6.8 | 5.2 | 0.0 | 0.0 | 9.3 | 86.2 | 0 / 0 |
| kernels[autovec] vadd_i64 RVV default/soc | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 39 | 1.384 | 1 (2.688) | 4,098 / 2,052 | 21 (0.3) | 20 | 0 | 1/21/20/0 | 1.7 | 0.0 | 0.0 | 0.0 | 9.8 | 86.1 | 0 / 0 |
| kernels[autovec] daxpy C default/axi | 40.2 | 0.1 | 0.2 | 10.2 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 9.8 | 28.9 | 9.8 | 0.3 | 0.0 | 21.0 | 93.8 | 99.0 | 256 | 1.395 | 1 (0.377) | 4,098 / 2,052 | 9 (0.1) | 7 | 0 | 1/9/7/0 | 1.5 | 1.1 | 0.0 | 0.0 | 40.4 | 45.6 | 0 / 0 |
| kernels[autovec] daxpy C default/soc | 40.2 | 0.1 | 0.2 | 10.2 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 9.8 | 28.9 | 9.8 | 0.3 | 0.0 | 21.0 | 93.8 | 99.0 | 256 | 1.395 | 1 (0.377) | 4,098 / 2,052 | 9 (0.1) | 7 | 0 | 1/9/7/0 | 0.4 | 0.0 | 0.0 | 0.0 | 40.8 | 45.3 | 0 / 0 |
| kernels[autovec] daxpy RVV default/axi | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 32 | 1.441 | 1 (2.941) | 4,098 / 2,052 | 17 (0.3) | 12 | 0 | 1/17/12/0 | 3.0 | 2.3 | 0.0 | 0.0 | 44.5 | 53.2 | 0 / 0 |
| kernels[autovec] daxpy RVV default/soc | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 32 | 1.441 | 1 (2.941) | 4,098 / 2,052 | 17 (0.3) | 12 | 0 | 1/17/12/0 | 0.7 | 0.0 | 0.0 | 0.0 | 45.6 | 52.2 | 0 / 0 |
| kernels[autovec] saxpy C default/axi | 40.3 | 0.1 | 0.2 | 10.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 9.8 | 29.0 | 9.8 | 0.3 | 0.0 | 21.2 | 95.1 | 99.2 | 259 | 1.592 | 1 (0.377) | 8,194 / 4,100 | 7 (0.1) | 4 | 0 | 1/7/4/0 | 0.6 | 0.4 | 0.0 | 0.0 | 42.8 | 48.0 | 0 / 0 |
| kernels[autovec] saxpy C default/soc | 40.3 | 0.1 | 0.2 | 10.1 | 0.2 | 0.2 | 0.0 | 0.0 | 0.2 | 9.8 | 29.0 | 9.8 | 0.3 | 0.0 | 21.2 | 95.1 | 99.2 | 259 | 1.592 | 1 (0.377) | 8,194 / 4,100 | 7 (0.1) | 4 | 0 | 1/7/4/0 | 0.1 | 0.0 | 0.0 | 0.0 | 43.0 | 47.9 | 0 / 0 |
| kernels[autovec] saxpy RVV default/axi | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 32 | 1.441 | 1 (2.941) | 8,194 / 4,100 | 17 (0.1) | 10 | 0 | 1/17/10/0 | 1.4 | 1.1 | 0.0 | 0.0 | 45.8 | 53.0 | 0 / 0 |
| kernels[autovec] saxpy RVV default/soc | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 32 | 1.441 | 1 (2.941) | 8,194 / 4,100 | 17 (0.1) | 10 | 0 | 1/17/10/0 | 0.4 | 0.0 | 0.0 | 0.0 | 46.3 | 52.5 | 0 / 0 |
| kernels[autovec] ddot C default/axi | 23.3 | 0.1 | 0.2 | 7.8 | 0.1 | 0.1 | 0.0 | 0.0 | 0.1 | 30.3 | 15.1 | 22.7 | 0.1 | 0.0 | 16.2 | 96.6 | 77.7 | 260 | 1.535 | 1 (0.296) | 4,098 / 8 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.2 | 0.2 | 0.0 | 0.0 | 56.9 | 24.7 | 0 / 0 |
| kernels[autovec] ddot C default/soc | 23.3 | 0.1 | 0.2 | 7.8 | 0.1 | 0.1 | 0.0 | 0.0 | 0.1 | 30.3 | 15.1 | 22.7 | 0.1 | 0.0 | 16.2 | 96.6 | 77.7 | 260 | 1.535 | 1 (0.296) | 4,098 / 8 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 57.0 | 24.8 | 0 / 0 |
| kernels[autovec] ddot RVV default/axi | 35.2 | 0.6 | 2.4 | 12.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 14.5 | 19.3 | 12.0 | 1.5 | 0.0 | 30.4 | 77.5 | 117.5 | 11 | 1.488 | 1 (3.012) | 4,098 / 8 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 58.0 | 39.1 | 0 / 0 |
| kernels[autovec] ddot RVV default/soc | 35.2 | 0.6 | 2.4 | 12.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 14.5 | 19.3 | 12.0 | 1.5 | 0.0 | 30.4 | 77.5 | 117.5 | 11 | 1.488 | 1 (3.012) | 4,098 / 8 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 58.1 | 39.1 | 0 / 0 |
| kernels[autovec] idot_i32 C default/axi | 37.3 | 0.0 | 0.2 | 12.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 12.7 | 24.5 | 12.5 | 0.1 | 0.0 | 25.4 | 98.3 | 124.4 | 11 | 1.501 | 1 (0.240) | 8,194 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 42.6 | 40.7 | 0 / 0 |
| kernels[autovec] idot_i32 C default/soc | 37.3 | 0.0 | 0.2 | 12.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 12.7 | 24.5 | 12.5 | 0.1 | 0.0 | 25.4 | 98.3 | 124.4 | 11 | 1.501 | 1 (0.240) | 8,194 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.6 | 40.7 | 0 / 0 |
| kernels[autovec] idot_i32 RVV default/axi | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 8 | 1.491 | 1 (1.701) | 8,194 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 49.2 | 47.8 | 0 / 0 |
| kernels[autovec] idot_i32 RVV default/soc | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 8 | 1.491 | 1 (1.701) | 8,194 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.2 | 47.8 | 0 / 0 |
| kernels[autovec] memcpy C default/axi | 40.3 | 19.8 | 19.8 | 19.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 | 99.2 | 198.8 | 15 | 1.596 | 1 (0.097) | 2,050 / 2,052 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] memcpy C default/soc | 40.3 | 19.8 | 19.8 | 19.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 | 99.2 | 198.8 | 15 | 1.596 | 1 (0.097) | 2,050 / 2,052 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] memcpy RVV default/axi | 43.6 | 0.7 | 1.5 | 14.5 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.3 | 11.6 | 1.8 | 0.0 | 36.7 | 77.5 | 141.8 | 35 | 1.502 | 1 (3.636) | 2,050 / 2,052 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.8 | 0.6 | 0.0 | 0.0 | 0.0 | 93.7 | 0 / 0 |
| kernels[autovec] memcpy RVV default/soc | 43.6 | 0.7 | 1.5 | 14.5 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.3 | 11.6 | 1.8 | 0.0 | 36.7 | 77.5 | 141.8 | 35 | 1.502 | 1 (3.636) | 2,050 / 2,052 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 94.3 | 0 / 0 |
| kernels[autovec] memcpy RVV-e8 default/axi | 42.8 | 0.7 | 1.5 | 14.8 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.6 | 11.8 | 1.8 | 0.0 | 59.4 | 77.5 | 143.9 | 39 | 1.509 | 1 (3.690) | 16,386 / 16,388 | 3 (0.0) | 3 | 0 | 1/3/3/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 99.2 | 0 / 0 |
| kernels[autovec] memcpy RVV-e8 default/soc | 42.8 | 0.7 | 1.5 | 14.8 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.6 | 11.8 | 1.8 | 0.0 | 59.4 | 77.5 | 143.9 | 39 | 1.509 | 1 (3.690) | 16,386 / 16,388 | 3 (0.0) | 3 | 0 | 1/3/3/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 99.3 | 0 / 0 |
| kernels[autovec] memset C default/axi | 33.9 | 0.0 | 32.8 | 33.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 33.5 | 99.2 | 328.7 | 2,056 | 1.659 | 1 (0.160) | 2 / 2,052 | 2 (0.1) | 2 | 0 | 1/2/2/0 | 0.9 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] memset C default/soc | 33.9 | 0.0 | 32.8 | 33.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 33.5 | 99.2 | 328.7 | 2,056 | 1.659 | 1 (0.160) | 2 / 2,052 | 2 (0.1) | 2 | 0 | 1/2/2/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] memset RVV default/axi | 44.0 | 0.8 | 1.7 | 16.6 | 1.7 | 1.7 | 1.7 | 0.0 | 0.0 | 1.7 | 13.3 | 14.9 | 2.1 | 0.0 | 45.2 | 77.5 | 161.8 | 31 | 1.311 | 1 (4.149) | 2 / 2,052 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.5 | 0.4 | 0.1 | 0.0 | 3.9 | 87.4 | 0 / 0 |
| kernels[autovec] memset RVV default/soc | 44.0 | 0.8 | 1.7 | 16.6 | 1.7 | 1.7 | 1.7 | 0.0 | 0.0 | 1.7 | 13.3 | 14.9 | 2.1 | 0.0 | 45.2 | 77.5 | 161.8 | 31 | 1.311 | 1 (4.149) | 2 / 2,052 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.1 | 0.0 | 3.9 | 87.8 | 0 / 0 |
| kernels[autovec] memset RVV-e8 default/axi | 39.1 | 0.9 | 1.9 | 18.6 | 1.9 | 1.9 | 0.0 | 0.0 | 0.0 | 1.9 | 14.9 | 16.7 | 2.3 | 0.0 | 60.0 | 77.5 | 181.4 | 35 | 1.567 | 1 (4.651) | 2 / 16,388 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 4.0 | 94.8 | 0 / 0 |
| kernels[autovec] memset RVV-e8 default/soc | 39.1 | 0.9 | 1.9 | 18.6 | 1.9 | 1.9 | 0.0 | 0.0 | 0.0 | 1.9 | 14.9 | 16.7 | 2.3 | 0.0 | 60.0 | 77.5 | 181.4 | 35 | 1.567 | 1 (4.651) | 2 / 16,388 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.0 | 94.8 | 0 / 0 |
| kernels[autovec] dgemm C default/axi | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.0 | 93.9 | 158.4 | 127,243 | 1.174 | 1 (0.001) | 262,146 / 4,100 | 1,478 (0.6) | 489 | 0 | 1/1478/489/0 | 2.4 | 1.8 | 0.0 | 26.7 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] dgemm C default/soc | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.0 | 93.9 | 158.4 | 127,243 | 1.174 | 1 (0.001) | 262,146 / 4,100 | 1,478 (0.6) | 489 | 0 | 1/1478/489/0 | 0.6 | 0.0 | 0.0 | 27.2 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] dgemm RVV default/axi | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 33.3 | 93.9 | 153.7 | 4,100 | 1.192 | 1 (0.037) | 135,170 / 4,100 | 1,292 (0.9) | 442 | 0 | 1/1292/442/0 | 3.9 | 2.9 | 0.0 | 0.0 | 66.5 | 28.3 | 0 / 0 |
| kernels[autovec] dgemm RVV default/soc | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 33.3 | 93.9 | 153.7 | 4,100 | 1.192 | 1 (0.037) | 135,170 / 4,100 | 1,292 (0.9) | 442 | 0 | 1/1292/442/0 | 1.0 | 0.0 | 0.0 | 0.0 | 68.5 | 27.2 | 0 / 0 |
| kernels[autovec] sgemm C default/axi | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 18.8 | 93.9 | 158.4 | 131,204 | 1.480 | 1 (0.001) | 262,146 / 4,100 | 14 (0.0) | 12 | 0 | 1/14/12/0 | 0.0 | 0.0 | 0.0 | 24.3 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] sgemm C default/soc | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 18.8 | 93.9 | 158.4 | 131,204 | 1.480 | 1 (0.001) | 262,146 / 4,100 | 14 (0.0) | 12 | 0 | 1/14/12/0 | 0.0 | 0.0 | 0.0 | 24.3 | 0.0 | 0.0 | 0 / 0 |
| kernels[autovec] sgemm RVV default/axi | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 17.9 | 93.9 | 153.7 | 131 | 1.648 | 1 (0.037) | 135,170 / 4,100 | 3 (0.0) | 3 | 0 | 1/3/3/0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.4 | 26.2 | 0 / 0 |
| kernels[autovec] sgemm RVV default/soc | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 17.9 | 93.9 | 153.7 | 131 | 1.648 | 1 (0.037) | 135,170 / 4,100 | 3 (0.0) | 3 | 0 | 1/3/3/0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.4 | 26.2 | 0 / 0 |
| kernels[autovec] fir_f32 C default/axi | 38.1 | 0.0 | 4.8 | 9.5 | 0.0 | 0.0 | 0.0 | 0.0 | 4.8 | 19.0 | 9.5 | 14.3 | 0.0 | 0.0 | 33.4 | 49.9 | 47.7 | 4,100 | 1.428 | 1 (0.012) | 131,074 / 4,100 | 2 (0.0) | 2 | 0 | 1/2/2/0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.8 | 26.8 | 0 / 0 |
| kernels[autovec] fir_f32 C default/soc | 38.1 | 0.0 | 4.8 | 9.5 | 0.0 | 0.0 | 0.0 | 0.0 | 4.8 | 19.0 | 9.5 | 14.3 | 0.0 | 0.0 | 33.4 | 49.9 | 47.7 | 4,100 | 1.428 | 1 (0.012) | 131,074 / 4,100 | 2 (0.0) | 2 | 0 | 1/2/2/0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.8 | 26.8 | 0 / 0 |
| kernels[autovec] fir_f32 RVV default/axi | 35.9 | 14.7 | 0.1 | 16.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 15.6 | 15.6 | 0.9 | 0.1 | 0.0 | 33.4 | 87.5 | 148.8 | 519 | 1.161 | 1 (0.287) | 66,050 / 4,100 | 7 (0.0) | 7 | 0 | 1/7/7/0 | 0.1 | 0.1 | 0.0 | 0.0 | 70.9 | 28.1 | 0 / 0 |
| kernels[autovec] fir_f32 RVV default/soc | 35.9 | 14.7 | 0.1 | 16.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 15.6 | 15.6 | 0.9 | 0.1 | 0.0 | 33.4 | 87.5 | 148.8 | 519 | 1.161 | 1 (0.287) | 66,050 / 4,100 | 7 (0.0) | 7 | 0 | 1/7/7/0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.0 | 28.0 | 0 / 0 |
| kernels[autovec] mac_i8 C default/axi | 27.3 | 0.0 | 0.1 | 9.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 27.2 | 18.1 | 18.1 | 0.0 | 0.0 | 36.5 | 99.1 | 90.9 | 10 | 1.365 | 1 (0.088) | 32,770 / 8 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.0 | 0.0 | 0.0 | 0.0 | 48.3 | 40.7 | 0 / 0 |
| kernels[autovec] mac_i8 C default/soc | 27.3 | 0.0 | 0.1 | 9.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 27.2 | 18.1 | 18.1 | 0.0 | 0.0 | 36.5 | 99.1 | 90.9 | 10 | 1.365 | 1 (0.088) | 32,770 / 8 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.0 | 0.0 | 0.0 | 0.0 | 48.3 | 40.8 | 0 / 0 |
| kernels[autovec] mac_i8 RVV default/axi | 30.2 | 0.3 | 1.1 | 10.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 19.2 | 18.1 | 19.2 | 0.7 | 0.0 | 41.9 | 87.5 | 100.1 | 8 | 1.392 | 1 (1.410) | 32,770 / 8 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 49.7 | 49.4 | 0 / 0 |
| kernels[autovec] mac_i8 RVV default/soc | 30.2 | 0.3 | 1.1 | 10.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 19.2 | 18.1 | 19.2 | 0.7 | 0.0 | 41.9 | 87.5 | 100.1 | 8 | 1.392 | 1 (1.410) | 32,770 / 8 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.7 | 49.4 | 0 / 0 |
| kernels[autovec] mac_i16 C default/axi | 37.3 | 0.0 | 0.2 | 12.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 12.7 | 24.5 | 12.5 | 0.1 | 0.0 | 25.4 | 98.3 | 124.4 | 11 | 1.501 | 1 (0.240) | 16,386 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 41.6 | 48.3 | 0 / 0 |
| kernels[autovec] mac_i16 C default/soc | 37.3 | 0.0 | 0.2 | 12.5 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 12.7 | 24.5 | 12.5 | 0.1 | 0.0 | 25.4 | 98.3 | 124.4 | 11 | 1.501 | 1 (0.240) | 16,386 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 41.6 | 48.3 | 0 / 0 |
| kernels[autovec] mac_i16 RVV default/axi | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 8 | 1.491 | 1 (1.701) | 16,386 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.4 | 52.9 | 0 / 0 |
| kernels[autovec] mac_i16 RVV default/soc | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 8 | 1.491 | 1 (1.701) | 16,386 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.4 | 52.9 | 0 / 0 |
| kernels[scalar] vadd_i32 C default/axi | 50.0 | 25.0 | 12.5 | 12.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.5 | 99.8 | 125.0 | 4,099 | 1.125 | 1 (0.030) | 8,194 / 4,100 | 3 (0.0) | 3 | 0 | 1/3/3/0 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] vadd_i32 C default/soc | 50.0 | 25.0 | 12.5 | 12.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.5 | 99.8 | 125.0 | 4,099 | 1.125 | 1 (0.030) | 8,194 / 4,100 | 3 (0.0) | 3 | 0 | 1/3/3/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] vadd_i32 RVV default/axi | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 39 | 1.384 | 1 (2.688) | 8,194 / 4,100 | 48 (0.4) | 36 | 0 | 1/48/36/0 | 7.0 | 5.3 | 0.0 | 0.0 | 9.3 | 88.4 | 0 / 0 |
| kernels[scalar] vadd_i32 RVV default/soc | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 39 | 1.384 | 1 (2.688) | 8,194 / 4,100 | 48 (0.4) | 36 | 0 | 1/48/36/0 | 1.8 | 0.0 | 0.0 | 0.0 | 9.8 | 88.1 | 0 / 0 |
| kernels[scalar] vadd_i64 C default/axi | 50.0 | 24.9 | 12.5 | 12.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 99.6 | 125.0 | 2,051 | 1.126 | 1 (0.061) | 4,098 / 2,052 | 12 (0.2) | 9 | 0 | 1/12/9/0 | 2.1 | 1.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] vadd_i64 C default/soc | 50.0 | 24.9 | 12.5 | 12.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 99.6 | 125.0 | 2,051 | 1.126 | 1 (0.061) | 4,098 / 2,052 | 12 (0.2) | 9 | 0 | 1/12/9/0 | 0.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] vadd_i64 RVV default/axi | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 39 | 1.384 | 1 (2.688) | 4,098 / 2,052 | 27 (0.4) | 25 | 0 | 1/27/25/0 | 8.4 | 6.4 | 0.0 | 0.0 | 9.1 | 87.2 | 0 / 0 |
| kernels[scalar] vadd_i64 RVV default/soc | 41.1 | 0.5 | 1.1 | 10.8 | 1.1 | 1.1 | 0.0 | 0.0 | 0.0 | 8.6 | 25.8 | 8.6 | 1.3 | 0.0 | 27.2 | 77.5 | 104.8 | 39 | 1.384 | 1 (2.688) | 4,098 / 2,052 | 27 (0.4) | 25 | 0 | 1/27/25/0 | 2.1 | 0.0 | 0.0 | 0.0 | 9.8 | 86.4 | 0 / 0 |
| kernels[scalar] daxpy C default/axi | 28.6 | 28.5 | 14.3 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.1 | 99.6 | 142.8 | 2,048 | 1.571 | 1 (0.069) | 4,098 / 2,052 | 15 (0.2) | 12 | 0 | 1/15/12/0 | 1.7 | 1.3 | 0.0 | 20.2 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] daxpy C default/soc | 28.6 | 28.5 | 14.3 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 57.1 | 99.6 | 142.8 | 2,048 | 1.571 | 1 (0.069) | 4,098 / 2,052 | 15 (0.2) | 12 | 0 | 1/15/12/0 | 0.4 | 0.0 | 0.0 | 20.5 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] daxpy RVV default/axi | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 32 | 1.441 | 1 (2.941) | 4,098 / 2,052 | 11 (0.2) | 7 | 0 | 1/11/7/0 | 1.9 | 1.5 | 0.0 | 0.0 | 45.1 | 52.7 | 0 / 0 |
| kernels[scalar] daxpy RVV default/soc | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 32 | 1.441 | 1 (2.941) | 4,098 / 2,052 | 11 (0.2) | 7 | 0 | 1/11/7/0 | 0.5 | 0.0 | 0.0 | 0.0 | 45.8 | 52.0 | 0 / 0 |
| kernels[scalar] saxpy C default/axi | 28.6 | 28.5 | 14.3 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 28.6 | 99.8 | 142.8 | 4,103 | 1.856 | 1 (0.035) | 8,194 / 4,100 | 18 (0.1) | 10 | 0 | 1/18/10/0 | 0.8 | 0.6 | 0.0 | 18.6 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] saxpy C default/soc | 28.6 | 28.5 | 14.3 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 28.6 | 99.8 | 142.8 | 4,103 | 1.856 | 1 (0.035) | 8,194 / 4,100 | 18 (0.1) | 10 | 0 | 1/18/10/0 | 0.2 | 0.0 | 0.0 | 18.7 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] saxpy RVV default/axi | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 32 | 1.441 | 1 (2.941) | 8,194 / 4,100 | 12 (0.1) | 8 | 0 | 1/12/8/0 | 1.1 | 0.8 | 0.0 | 0.0 | 46.0 | 52.9 | 0 / 0 |
| kernels[scalar] saxpy RVV default/soc | 34.4 | 0.6 | 1.2 | 11.8 | 1.2 | 1.2 | 0.0 | 0.0 | 1.2 | 9.4 | 28.2 | 9.4 | 1.5 | 0.0 | 27.4 | 77.5 | 114.7 | 32 | 1.441 | 1 (2.941) | 8,194 / 4,100 | 12 (0.1) | 8 | 0 | 1/12/8/0 | 0.3 | 0.0 | 0.0 | 0.0 | 46.4 | 52.5 | 0 / 0 |
| kernels[scalar] ddot C default/axi | 33.4 | 33.2 | 0.1 | 16.7 | 0.0 | 0.0 | 0.0 | 0.0 | 16.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 66.6 | 99.6 | 166.4 | 2,052 | 1.499 | 1 (0.081) | 4,098 / 8 | 3 (0.1) | 1 | 0 | 1/3/1/0 | 0.3 | 0.3 | 0.0 | 23.8 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] ddot C default/soc | 33.4 | 33.2 | 0.1 | 16.7 | 0.0 | 0.0 | 0.0 | 0.0 | 16.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 66.6 | 99.6 | 166.4 | 2,052 | 1.499 | 1 (0.081) | 4,098 / 8 | 3 (0.1) | 1 | 0 | 1/3/1/0 | 0.1 | 0.0 | 0.0 | 23.9 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] ddot RVV default/axi | 35.2 | 0.6 | 2.4 | 12.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 14.5 | 19.3 | 12.0 | 1.5 | 0.0 | 30.4 | 77.5 | 117.5 | 11 | 1.488 | 1 (3.012) | 4,098 / 8 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 58.0 | 39.1 | 0 / 0 |
| kernels[scalar] ddot RVV default/soc | 35.2 | 0.6 | 2.4 | 12.0 | 1.2 | 1.2 | 0.0 | 0.0 | 0.0 | 14.5 | 19.3 | 12.0 | 1.5 | 0.0 | 30.4 | 77.5 | 117.5 | 11 | 1.488 | 1 (3.012) | 4,098 / 8 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 58.1 | 39.1 | 0 / 0 |
| kernels[scalar] idot_i32 C default/axi | 42.9 | 28.5 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 85.7 | 99.8 | 142.8 | 4,099 | 1.143 | 1 (0.035) | 8,194 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 10.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] idot_i32 C default/soc | 42.9 | 28.5 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 85.7 | 99.8 | 142.8 | 4,099 | 1.143 | 1 (0.035) | 8,194 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 10.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] idot_i32 RVV default/axi | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 8 | 1.491 | 1 (1.701) | 8,194 / 8 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.1 | 0.1 | 0.0 | 0.0 | 49.2 | 47.9 | 0 / 0 |
| kernels[scalar] idot_i32 RVV default/soc | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 8 | 1.491 | 1 (1.701) | 8,194 / 8 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.2 | 47.9 | 0 / 0 |
| kernels[scalar] memcpy C default/axi | 40.3 | 19.8 | 19.8 | 19.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 | 99.2 | 198.8 | 15 | 1.596 | 1 (0.097) | 2,050 / 2,052 | 2 (0.0) | 2 | 0 | 1/2/2/0 | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] memcpy C default/soc | 40.3 | 19.8 | 19.8 | 19.9 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 | 99.2 | 198.8 | 15 | 1.596 | 1 (0.097) | 2,050 / 2,052 | 2 (0.0) | 2 | 0 | 1/2/2/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] memcpy RVV default/axi | 43.6 | 0.7 | 1.5 | 14.5 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.3 | 11.6 | 1.8 | 0.0 | 36.7 | 77.5 | 141.8 | 35 | 1.502 | 1 (3.636) | 2,050 / 2,052 | 5 (0.1) | 5 | 0 | 1/5/5/0 | 3.1 | 2.3 | 0.0 | 0.0 | 0.0 | 94.6 | 0 / 0 |
| kernels[scalar] memcpy RVV default/soc | 43.6 | 0.7 | 1.5 | 14.5 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.3 | 11.6 | 1.8 | 0.0 | 36.7 | 77.5 | 141.8 | 35 | 1.502 | 1 (3.636) | 2,050 / 2,052 | 5 (0.1) | 5 | 0 | 1/5/5/0 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 94.6 | 0 / 0 |
| kernels[scalar] memcpy RVV-e8 default/axi | 42.8 | 0.7 | 1.5 | 14.8 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.6 | 11.8 | 1.8 | 0.0 | 59.4 | 77.5 | 143.9 | 39 | 1.509 | 1 (3.690) | 16,386 / 16,388 | 2 (0.0) | 2 | 0 | 1/2/2/0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 99.2 | 0 / 0 |
| kernels[scalar] memcpy RVV-e8 default/soc | 42.8 | 0.7 | 1.5 | 14.8 | 1.5 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 23.6 | 11.8 | 1.8 | 0.0 | 59.4 | 77.5 | 143.9 | 39 | 1.509 | 1 (3.690) | 16,386 / 16,388 | 2 (0.0) | 2 | 0 | 1/2/2/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.3 | 0 / 0 |
| kernels[scalar] memset C default/axi | 33.9 | 0.0 | 32.8 | 33.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 33.5 | 99.2 | 328.7 | 2,056 | 1.659 | 1 (0.160) | 2 / 2,052 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] memset C default/soc | 33.9 | 0.0 | 32.8 | 33.0 | 0.1 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 33.5 | 99.2 | 328.7 | 2,056 | 1.659 | 1 (0.160) | 2 / 2,052 | 1 (0.0) | 1 | 0 | 1/1/1/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] memset RVV default/axi | 44.0 | 0.8 | 1.7 | 16.6 | 1.7 | 1.7 | 1.7 | 0.0 | 0.0 | 1.7 | 13.3 | 14.9 | 2.1 | 0.0 | 45.2 | 77.5 | 161.8 | 31 | 1.311 | 1 (4.149) | 2 / 2,052 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.5 | 0.4 | 0.1 | 0.0 | 3.9 | 87.4 | 0 / 0 |
| kernels[scalar] memset RVV default/soc | 44.0 | 0.8 | 1.7 | 16.6 | 1.7 | 1.7 | 1.7 | 0.0 | 0.0 | 1.7 | 13.3 | 14.9 | 2.1 | 0.0 | 45.2 | 77.5 | 161.8 | 31 | 1.311 | 1 (4.149) | 2 / 2,052 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.1 | 0.0 | 3.9 | 87.8 | 0 / 0 |
| kernels[scalar] memset RVV-e8 default/axi | 39.1 | 0.9 | 1.9 | 18.6 | 1.9 | 1.9 | 0.0 | 0.0 | 0.0 | 1.9 | 14.9 | 16.7 | 2.3 | 0.0 | 60.0 | 77.5 | 181.4 | 35 | 1.567 | 1 (4.651) | 2 / 16,388 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 4.0 | 94.8 | 0 / 0 |
| kernels[scalar] memset RVV-e8 default/soc | 39.1 | 0.9 | 1.9 | 18.6 | 1.9 | 1.9 | 0.0 | 0.0 | 0.0 | 1.9 | 14.9 | 16.7 | 2.3 | 0.0 | 60.0 | 77.5 | 181.4 | 35 | 1.567 | 1 (4.651) | 2 / 16,388 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 4.0 | 94.8 | 0 / 0 |
| kernels[scalar] dgemm C default/axi | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.0 | 93.9 | 158.4 | 127,243 | 1.174 | 1 (0.001) | 262,146 / 4,100 | 1,370 (0.5) | 483 | 0 | 1/1370/483/0 | 2.3 | 1.7 | 0.0 | 26.8 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] dgemm C default/soc | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 51.0 | 93.9 | 158.4 | 127,243 | 1.174 | 1 (0.001) | 262,146 / 4,100 | 1,370 (0.5) | 483 | 0 | 1/1370/483/0 | 0.6 | 0.0 | 0.0 | 27.2 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] dgemm RVV default/axi | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 33.3 | 93.9 | 153.7 | 4,100 | 1.192 | 1 (0.037) | 135,170 / 4,100 | 1,354 (1.0) | 466 | 0 | 1/1354/466/0 | 4.1 | 3.1 | 0.0 | 0.0 | 66.4 | 28.5 | 0 / 0 |
| kernels[scalar] dgemm RVV default/soc | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 33.3 | 93.9 | 153.7 | 4,100 | 1.192 | 1 (0.037) | 135,170 / 4,100 | 1,354 (1.0) | 466 | 0 | 1/1354/466/0 | 1.0 | 0.0 | 0.0 | 0.0 | 68.5 | 27.3 | 0 / 0 |
| kernels[scalar] sgemm C default/axi | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 18.8 | 93.9 | 158.4 | 131,204 | 1.480 | 1 (0.001) | 262,146 / 4,100 | 6 (0.0) | 6 | 0 | 1/6/6/0 | 0.0 | 0.0 | 0.0 | 24.3 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] sgemm C default/soc | 34.7 | 31.6 | 0.5 | 16.3 | 0.5 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 18.8 | 93.9 | 158.4 | 131,204 | 1.480 | 1 (0.001) | 262,146 / 4,100 | 6 (0.0) | 6 | 0 | 1/6/6/0 | 0.0 | 0.0 | 0.0 | 24.3 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] sgemm RVV default/axi | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 17.9 | 93.9 | 153.7 | 131 | 1.648 | 1 (0.037) | 135,170 / 4,100 | 10 (0.0) | 8 | 0 | 1/10/8/0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.4 | 26.2 | 0 / 0 |
| kernels[scalar] sgemm RVV default/soc | 36.1 | 15.4 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 15.8 | 15.8 | 0.5 | 0.0 | 0.0 | 17.9 | 93.9 | 153.7 | 131 | 1.648 | 1 (0.037) | 135,170 / 4,100 | 10 (0.0) | 8 | 0 | 1/10/8/0 | 0.0 | 0.0 | 0.0 | 0.0 | 68.4 | 26.2 | 0 / 0 |
| kernels[scalar] fir_f32 C default/axi | 35.6 | 30.8 | 1.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 35.6 | 94.1 | 153.8 | 4,096 | 1.788 | 1 (0.002) | 131,074 / 4,100 | 3 (0.0) | 2 | 0 | 1/3/2/0 | 0.0 | 0.0 | 0.0 | 20.5 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] fir_f32 C default/soc | 35.6 | 30.8 | 1.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 16.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 35.6 | 94.1 | 153.8 | 4,096 | 1.788 | 1 (0.002) | 131,074 / 4,100 | 3 (0.0) | 2 | 0 | 1/3/2/0 | 0.0 | 0.0 | 0.0 | 20.5 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] fir_f32 RVV default/axi | 35.9 | 14.7 | 0.1 | 16.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 15.6 | 15.6 | 0.9 | 0.1 | 0.0 | 33.4 | 87.5 | 148.8 | 519 | 1.161 | 1 (0.287) | 66,050 / 4,100 | 4 (0.0) | 3 | 0 | 1/4/3/0 | 0.0 | 0.0 | 0.0 | 0.0 | 70.9 | 28.0 | 0 / 0 |
| kernels[scalar] fir_f32 RVV default/soc | 35.9 | 14.7 | 0.1 | 16.7 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 15.6 | 15.6 | 0.9 | 0.1 | 0.0 | 33.4 | 87.5 | 148.8 | 519 | 1.161 | 1 (0.287) | 66,050 / 4,100 | 4 (0.0) | 3 | 0 | 1/4/3/0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.0 | 28.0 | 0 / 0 |
| kernels[scalar] mac_i8 C default/axi | 42.9 | 28.6 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.9 | 99.9 | 142.8 | 16,390 | 1.286 | 1 (0.009) | 32,770 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] mac_i8 C default/soc | 42.9 | 28.6 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.9 | 99.9 | 142.8 | 16,390 | 1.286 | 1 (0.009) | 32,770 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] mac_i8 RVV default/axi | 30.2 | 0.3 | 1.1 | 10.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 19.2 | 18.1 | 19.2 | 0.7 | 0.0 | 41.9 | 87.5 | 100.1 | 8 | 1.392 | 1 (1.410) | 32,770 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.7 | 49.4 | 0 / 0 |
| kernels[scalar] mac_i8 RVV default/soc | 30.2 | 0.3 | 1.1 | 10.2 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 19.2 | 18.1 | 19.2 | 0.7 | 0.0 | 41.9 | 87.5 | 100.1 | 8 | 1.392 | 1 (1.410) | 32,770 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 49.7 | 49.4 | 0 / 0 |
| kernels[scalar] mac_i16 C default/axi | 42.9 | 28.5 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.4 | 99.9 | 142.8 | 8,199 | 1.286 | 1 (0.017) | 16,386 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] mac_i16 C default/soc | 42.9 | 28.5 | 0.0 | 14.3 | 0.0 | 0.0 | 14.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.4 | 99.9 | 142.8 | 8,199 | 1.286 | 1 (0.017) | 16,386 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 9.5 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| kernels[scalar] mac_i16 RVV default/axi | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 8 | 1.491 | 1 (1.701) | 16,386 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.4 | 52.9 | 0 / 0 |
| kernels[scalar] mac_i16 RVV default/soc | 36.2 | 0.3 | 1.4 | 12.2 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 13.6 | 21.8 | 12.2 | 0.9 | 0.0 | 28.1 | 87.5 | 120.7 | 8 | 1.491 | 1 (1.701) | 16,386 / 8 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 45.4 | 52.9 | 0 / 0 |
| micro_dmem[default] empty default/axi | 38.1 | 9.5 | 19.0 | 0.0 | 4.8 | 4.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.8 | 0.0 | 42.9 | - | 95.2 | 1 | 1.286 | 1 (47.619) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 37.0 | 27.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] empty default/soc | 38.1 | 9.5 | 19.0 | 0.0 | 4.8 | 4.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.8 | 0.0 | 42.9 | - | 95.2 | 1 | 1.286 | 1 (47.619) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 13.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_1k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_1k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_2k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_2k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_4k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_4k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_8k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_8k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_12k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_12k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_16k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 8 (0.2) | 1 | 0 | 1/8/1/0 | 2.7 | 2.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_16k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 8 (0.2) | 1 | 0 | 1/8/1/0 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_20k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 1,629 (39.7) | 1 | 0 | 1/1629/1/0 | 77.7 | 57.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_20k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 1,629 (39.7) | 1 | 0 | 1/1629/1/0 | 48.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_24k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 2,544 (62.0) | 1 | 0 | 1/2544/1/0 | 83.0 | 61.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_24k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 2,544 (62.0) | 1 | 0 | 1/2544/1/0 | 56.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_32k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 3,404 (83.0) | 1 | 0 | 1/3404/1/0 | 85.6 | 62.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_32k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 3,404 (83.0) | 1 | 0 | 1/3404/1/0 | 61.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_64k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 4,045 (98.6) | 1 | 0 | 1/4045/1/0 | 86.9 | 63.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_64k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 4,045 (98.6) | 1 | 0 | 1/4045/1/0 | 63.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_128k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 87.0 | 64.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_128k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 63.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_256k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 87.0 | 64.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_rand_256k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 4,100 (99.9) | 1 | 0 | 1/4100/1/0 | 63.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_4k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_4k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_8k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_8k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 1 (0.0) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_16k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 8 (0.2) | 1 | 0 | 1/8/1/0 | 2.7 | 2.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_16k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 8 (0.2) | 1 | 0 | 1/8/1/0 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_32k default/axi | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 2,749 (67.0) | 1 | 0 | 1/2749/1/0 | 83.7 | 61.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] chase_seq_32k default/soc | 1.7 | 96.5 | 0.1 | 1.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 98.4 | 15.3 | 65 | 1.016 | 1 (0.235) | 4,098 / 5 | 2,749 (67.0) | 1 | 0 | 1/2749/1/0 | 57.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] stream_ld default/axi | 12.3 | 84.8 | 0.1 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 49.2 | 13.5 | 65 | 1.014 | 1 (0.207) | 4,098 / 4 | 513 (12.5) | 0 | 0 | 1/513/0/0 | 57.6 | 42.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] stream_ld default/soc | 12.3 | 84.8 | 0.1 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 49.2 | 13.5 | 65 | 1.014 | 1 (0.207) | 4,098 / 4 | 513 (12.5) | 0 | 0 | 1/513/0/0 | 26.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] stream_st default/axi | 12.2 | 0.0 | 85.0 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 49.2 | 13.5 | 65 | 1.014 | 1 (0.207) | 2 / 4,100 | 514 (12.5) | 450 | 0 | 1/514/450/0 | 68.3 | 52.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_dmem[default] stream_st default/soc | 12.2 | 0.0 | 85.0 | 2.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 49.2 | 13.5 | 65 | 1.014 | 1 (0.207) | 2 / 4,100 | 514 (12.5) | 450 | 0 | 1/514/450/0 | 33.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] empty default/axi | 31.6 | 10.5 | 21.1 | 0.0 | 5.3 | 5.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 26.3 | 0.0 | 47.4 | - | 105.3 | 2 | 1.368 | 1 (52.632) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 37.4 | 27.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] empty default/soc | 31.6 | 10.5 | 21.1 | 0.0 | 5.3 | 5.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 26.3 | 0.0 | 47.4 | - | 105.3 | 2 | 1.368 | 1 (52.632) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 13.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_1k default/axi | 98.8 | 0.0 | 0.0 | 0.4 | 0.0 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 11.6 | 577 | 1.012 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_1k default/soc | 98.8 | 0.0 | 0.0 | 0.4 | 0.0 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 11.6 | 577 | 1.012 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_2k default/axi | 99.4 | 0.0 | 0.0 | 0.2 | 0.0 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 | 5.8 | 289 | 1.006 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_2k default/soc | 99.4 | 0.0 | 0.0 | 0.2 | 0.0 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.0 | 5.8 | 289 | 1.006 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_3k default/axi | 99.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.4 | 3.9 | 193 | 1.004 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_3k default/soc | 99.6 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.4 | 3.9 | 193 | 1.004 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_4k default/axi | 99.7 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 97.9 | 2.9 | 145 | 1.003 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_4k default/soc | 99.7 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 97.9 | 2.9 | 145 | 1.003 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_6k default/axi | 99.8 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.9 | 2.0 | 97 | 1.002 | 136 (2.759) | 2 / 4 | 0 (0.0) | 0 | 0 | 136/0/0/0 | 4.5 | 3.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_6k default/soc | 99.8 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.9 | 2.0 | 97 | 1.002 | 136 (2.759) | 2 / 4 | 0 (0.0) | 0 | 0 | 136/0/0/0 | 1.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_8k default/axi | 99.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 95.8 | 1.5 | 73 | 1.002 | 108 (2.192) | 2 / 4 | 0 (0.0) | 0 | 0 | 108/0/0/0 | 3.6 | 2.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_8k default/soc | 99.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 95.8 | 1.5 | 73 | 1.002 | 108 (2.192) | 2 / 4 | 0 (0.0) | 0 | 0 | 108/0/0/0 | 1.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_12k default/axi | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 1.0 | 49 | 1.001 | 2,062 (41.878) | 2 / 4 | 0 (0.0) | 0 | 0 | 2062/0/0/0 | 40.6 | 29.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_12k default/soc | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 1.0 | 49 | 1.001 | 2,062 (41.878) | 2 / 4 | 0 (0.0) | 0 | 0 | 2062/0/0/0 | 15.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_16k default/axi | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 91.7 | 0.8 | 37 | 1.001 | 2,331 (47.357) | 2 / 4 | 0 (0.0) | 0 | 0 | 2331/0/0/0 | 43.4 | 31.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_16k default/soc | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 91.7 | 0.8 | 37 | 1.001 | 2,331 (47.357) | 2 / 4 | 0 (0.0) | 0 | 0 | 2331/0/0/0 | 16.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_24k default/axi | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.5 | 0.5 | 25 | 1.001 | 2,579 (52.412) | 2 / 4 | 0 (0.0) | 0 | 0 | 2579/0/0/0 | 45.8 | 33.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_24k default/soc | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.5 | 0.5 | 25 | 1.001 | 2,579 (52.412) | 2 / 4 | 0 (0.0) | 0 | 0 | 2579/0/0/0 | 18.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_32k default/axi | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.3 | 0.4 | 19 | 1.000 | 2,701 (54.901) | 2 / 4 | 0 (0.0) | 0 | 0 | 2701/0/0/0 | 46.9 | 34.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_imem[default] ifoot_32k default/soc | 99.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.3 | 0.4 | 19 | 1.000 | 2,701 (54.901) | 2 / 4 | 0 (0.0) | 0 | 0 | 2701/0/0/0 | 19.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] empty default/axi | 31.6 | 10.5 | 21.1 | 0.0 | 5.3 | 5.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 26.3 | 0.0 | 47.4 | - | 105.3 | 2 | 1.368 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 37.4 | 27.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] empty default/soc | 31.6 | 10.5 | 21.1 | 0.0 | 5.3 | 5.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 26.3 | 0.0 | 47.4 | - | 105.3 | 2 | 1.368 | 0 (0.000) | 2 / 4 | 1 (16.7) | 0 | 0 | 0/1/0/0 | 13.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] loop default/axi | 50.0 | 0.0 | 0.0 | 49.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 100.0 | 499.0 | 4,097 | 1.500 | 1 (0.122) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] loop default/soc | 50.0 | 0.0 | 0.0 | 49.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 100.0 | 499.0 | 4,097 | 1.500 | 1 (0.122) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_dep default/axi | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_dep default/soc | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_indep default/axi | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_indep default/soc | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu16_dep default/axi | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 98.8 | 93.8 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu16_dep default/soc | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 98.8 | 93.8 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_straddle default/axi | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 93.8 | 4.1 | 0 | 2.000 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] alu32_straddle default/soc | 99.3 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 93.8 | 4.1 | 0 | 2.000 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] br_nt default/axi | 0.7 | 0.0 | 0.1 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.4 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] br_nt default/soc | 0.7 | 0.0 | 0.1 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 0.4 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] br_taken default/axi | 0.7 | 0.0 | 0.1 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 100.0 | 990.1 | 4,113 | 1.992 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] br_taken default/soc | 0.7 | 0.0 | 0.1 | 99.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 100.0 | 990.1 | 4,113 | 1.992 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] jal default/axi | 0.6 | 0.0 | 0.1 | 0.4 | 98.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 991.3 | 4,112 | 1.992 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] jal default/soc | 0.6 | 0.0 | 0.1 | 0.4 | 98.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 991.3 | 4,112 | 1.992 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] call_ret default/axi | 33.4 | 0.0 | 0.0 | 0.1 | 33.2 | 33.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 93.8 | 665.1 | 8,209 | 1.666 | 1 (0.081) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] call_ret default/soc | 33.4 | 0.0 | 0.0 | 0.1 | 33.2 | 33.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 93.8 | 665.1 | 8,209 | 1.666 | 1 (0.081) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] jalr_call_ret default/axi | 33.4 | 0.0 | 0.0 | 0.1 | 0.0 | 66.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 93.8 | 665.0 | 8,209 | 1.666 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] jalr_call_ret default/soc | 33.4 | 0.0 | 0.0 | 0.1 | 0.0 | 66.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 93.8 | 665.0 | 8,209 | 1.666 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_never default/axi | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 1.5 | 3.7 | 65 | 1.004 | 1 (0.057) | 514 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_never default/soc | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 1.5 | 3.7 | 65 | 1.004 | 1 (0.057) | 514 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_always default/axi | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 100.0 | 237.0 | 4,161 | 1.237 | 0 (0.000) | 514 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_always default/soc | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 100.0 | 237.0 | 4,161 | 1.237 | 0 (0.000) | 514 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_alt default/axi | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 50.7 | 120.3 | 2,113 | 1.121 | 0 (0.000) | 514 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_alt default/soc | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 50.7 | 120.3 | 2,113 | 1.121 | 0 (0.000) | 514 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_rand default/axi | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 50.7 | 120.3 | 2,113 | 1.121 | 0 (0.000) | 514 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] brpat_rand default/soc | 73.3 | 2.9 | 0.0 | 23.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 50.7 | 120.3 | 2,113 | 1.121 | 0 (0.000) | 514 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_dep default/axi | 0.6 | 98.8 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 93.8 | 4.1 | 17 | 1.005 | 0 (0.000) | 4,098 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_dep default/soc | 0.6 | 98.8 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.3 | 93.8 | 4.1 | 17 | 1.005 | 0 (0.000) | 4,098 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_indep default/axi | 0.7 | 98.6 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.004 | 1 (0.241) | 4,098 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_indep default/soc | 0.7 | 98.6 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.004 | 1 (0.241) | 4,098 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_use1 default/axi | 50.0 | 49.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 93.8 | 2.1 | 17 | 1.002 | 1 (0.121) | 4,098 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_use1 default/soc | 50.0 | 49.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 93.8 | 2.1 | 17 | 1.002 | 1 (0.121) | 4,098 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_use2 default/axi | 50.0 | 49.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 93.8 | 2.1 | 17 | 1.002 | 1 (0.121) | 4,099 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] ld_use2 default/soc | 50.0 | 49.7 | 0.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.1 | 93.8 | 2.1 | 17 | 1.002 | 1 (0.121) | 4,099 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] st default/axi | 0.7 | 0.0 | 98.7 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.005 | 1 (0.241) | 2 / 4,100 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] st default/soc | 0.7 | 0.0 | 98.7 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.005 | 1 (0.241) | 2 / 4,100 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] rdcycle default/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.004 | 1 (0.241) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.8 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] rdcycle default/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.004 | 1 (0.241) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] rdtime default/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] rdtime default/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrr default/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.005 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrr default/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 | 0.0 | 0.2 | 93.8 | 4.1 | 17 | 1.005 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrw default/axi | 0.7 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.7 | 0.0 | 0.2 | 93.8 | 4.1 | 16 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrw default/soc | 0.7 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.7 | 0.0 | 0.2 | 93.8 | 4.1 | 16 | 1.006 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrrw default/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 | 0.0 | 0.3 | 93.8 | 4.1 | 17 | 1.005 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] csrrw default/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.8 | 0.0 | 0.3 | 93.8 | 4.1 | 17 | 1.005 | 1 (0.241) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] fence default/axi | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 98.7 | 0.2 | 93.8 | 4.1 | 17 | 1.006 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_pipe[default] fence default/soc | 0.6 | 0.0 | 0.1 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 98.7 | 0.2 | 93.8 | 4.1 | 17 | 1.006 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] empty default/axi | 38.1 | 9.5 | 19.0 | 0.0 | 4.8 | 4.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.8 | 0.0 | 42.9 | - | 95.2 | 2 | 1.286 | 1 (47.619) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 37.0 | 27.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] empty default/soc | 38.1 | 9.5 | 19.0 | 0.0 | 4.8 | 4.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 23.8 | 0.0 | 42.9 | - | 95.2 | 2 | 1.286 | 1 (47.619) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 13.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] mul_dep default/axi | 3.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 94.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.7 | 17 | 1.031 | 1 (0.921) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.8 | 0.6 | 47.3 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] mul_dep default/soc | 3.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 94.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.7 | 17 | 1.031 | 1 (0.921) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.0 | 47.6 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] mul_indep default/axi | 3.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 94.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.7 | 17 | 1.017 | 2 (1.842) | 2 / 4 | 1 (16.7) | 0 | 0 | 2/1/0/0 | 2.3 | 1.7 | 46.9 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] mul_indep default/soc | 3.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 94.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.9 | 93.8 | 15.7 | 17 | 1.017 | 2 (1.842) | 2 / 4 | 1 (16.7) | 0 | 0 | 2/1/0/0 | 0.6 | 0.0 | 47.7 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_dep default/axi | 2.8 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.7 | 17 | 1.020 | 2 (1.847) | 2 / 4 | 0 (0.0) | 0 | 0 | 2/0/0/0 | 0.2 | 0.1 | 93.8 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_dep default/soc | 2.8 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.7 | 17 | 1.020 | 2 (1.847) | 2 / 4 | 0 (0.0) | 0 | 0 | 2/0/0/0 | 0.0 | 0.0 | 94.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_indep default/axi | 2.8 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.7 | 17 | 1.024 | 1 (0.923) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 93.9 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_indep default/soc | 2.8 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.7 | 17 | 1.024 | 1 (0.923) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 94.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_short default/axi | 2.3 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 95.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.8 | 17 | 1.017 | 1 (0.928) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.8 | 0.6 | 47.9 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] div_short default/soc | 2.3 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 95.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.1 | 93.8 | 15.8 | 17 | 1.017 | 1 (0.928) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.0 | 48.1 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] divw_dep default/axi | 2.4 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.0 | 93.8 | 15.8 | 17 | 1.020 | 1 (0.927) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.3 | 0.2 | 89.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] divw_dep default/soc | 2.4 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.0 | 93.8 | 15.8 | 17 | 1.020 | 1 (0.927) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 89.2 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] rem_indep default/axi | 2.6 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.0 | 93.8 | 15.7 | 17 | 1.020 | 1 (0.925) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 93.8 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] rem_indep default/soc | 2.6 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 94.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 1.0 | 93.8 | 15.7 | 17 | 1.020 | 1 (0.925) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 93.8 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fadd_d_dep default/axi | 2.0 | 0.4 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 17 | 1.021 | 2 (1.852) | 4 / 4 | 2 (25.0) | 0 | 0 | 2/2/0/0 | 2.1 | 1.6 | 0.0 | 63.5 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fadd_d_dep default/soc | 2.0 | 0.4 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 17 | 1.021 | 2 (1.852) | 4 / 4 | 2 (25.0) | 0 | 0 | 2/2/0/0 | 0.6 | 0.0 | 0.0 | 64.5 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fadd_d_indep default/axi | 1.9 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.5 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 17 | 1.020 | 1 (0.929) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.5 | 0.4 | 0.0 | 64.7 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fadd_d_indep default/soc | 1.9 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.5 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 17 | 1.020 | 1 (0.929) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 64.9 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fmul_d_dep default/axi | 2.1 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 16 | 1.024 | 1 (0.926) | 3 / 4 | 1 (14.3) | 0 | 0 | 1/1/0/0 | 1.1 | 0.8 | 0.0 | 64.2 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fmul_d_dep default/soc | 2.1 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 16 | 1.024 | 1 (0.926) | 3 / 4 | 1 (14.3) | 0 | 0 | 1/1/0/0 | 0.3 | 0.0 | 0.0 | 64.7 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fmadd_d_dep default/axi | 2.2 | 0.5 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 94.8 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 16 | 1.030 | 1 (0.923) | 5 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.4 | 0.3 | 0.0 | 73.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fmadd_d_dep default/soc | 2.2 | 0.5 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 94.8 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 16 | 1.030 | 1 (0.923) | 5 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 73.2 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_d_dep default/axi | 2.1 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 16 | 1.024 | 1 (0.926) | 3 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 0.0 | 93.4 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_d_dep default/soc | 2.1 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.1 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 16 | 1.024 | 1 (0.926) | 3 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 93.4 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_d_indep default/axi | 2.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.3 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 16 | 1.021 | 1 (0.927) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.1 | 0.0 | 93.4 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_d_indep default/soc | 2.0 | 0.2 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.3 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 16 | 1.021 | 1 (0.927) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 93.5 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_d_dep default/axi | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.3 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 17 | 1.020 | 1 (0.929) | 3 / 4 | 1 (14.3) | 0 | 0 | 1/1/0/0 | 0.2 | 0.1 | 0.0 | 93.3 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_d_dep default/soc | 2.0 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.3 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 17 | 1.020 | 1 (0.929) | 3 / 4 | 1 (14.3) | 0 | 0 | 1/1/0/0 | 0.1 | 0.0 | 0.0 | 93.5 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_d_indep default/axi | 1.9 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.3 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 16 | 1.023 | 0 (0.000) | 3 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 93.5 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_d_indep default/soc | 1.9 | 0.3 | 0.4 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.3 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 16 | 1.023 | 0 (0.000) | 3 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 93.5 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_s_dep default/axi | 2.2 | 0.4 | 0.5 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 94.8 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 16 | 1.025 | 1 (0.924) | 4 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.1 | 0.0 | 87.9 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fdiv_s_dep default/soc | 2.2 | 0.4 | 0.5 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 94.8 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.7 | 16 | 1.025 | 1 (0.924) | 4 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 88.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_s_dep default/axi | 2.1 | 0.3 | 0.5 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 16 | 1.023 | 1 (0.928) | 3 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.1 | 0.0 | 88.0 | 0.0 | 0.0 | 0 / 0 |
| micro_units[default] fsqrt_s_dep default/soc | 2.1 | 0.3 | 0.5 | 1.5 | 0.1 | 0.1 | 0.0 | 0.0 | 95.0 | 0.0 | 0.0 | 0.0 | 0.5 | 0.0 | 0.8 | 93.8 | 15.8 | 16 | 1.023 | 1 (0.928) | 3 / 5 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 88.1 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] empty default/axi | 40.9 | 9.1 | 18.2 | 0.0 | 4.5 | 4.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 22.7 | 0.0 | 22.7 | - | 90.9 | 2 | 1.364 | 1 (45.455) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 51.9 | 38.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] empty default/soc | 40.9 | 9.1 | 18.2 | 0.0 | 4.5 | 4.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 22.7 | 0.0 | 22.7 | - | 90.9 | 2 | 1.364 | 1 (45.455) | 2 / 4 | 1 (16.7) | 0 | 0 | 1/1/0/0 | 22.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vsetvli_same default/axi | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 1.7 | 0.0 | 2.0 | 87.5 | 30.7 | 9 | 1.041 | 1 (3.413) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 5.2 | 3.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vsetvli_same default/soc | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 1.7 | 0.0 | 2.0 | 87.5 | 30.7 | 9 | 1.041 | 1 (3.413) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vsetvli_toggle default/axi | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 1.7 | 0.0 | 2.0 | 87.5 | 30.7 | 9 | 1.065 | 1 (3.413) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 5.1 | 3.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vsetvli_toggle default/soc | 5.5 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 87.4 | 1.7 | 0.0 | 2.0 | 87.5 | 30.7 | 9 | 1.065 | 1 (3.413) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 1.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl1 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 1 (3.425) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 1.8 | 1.3 | 0.0 | 0.0 | 66.4 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl1 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 1 (3.425) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.5 | 0.0 | 0.0 | 0.0 | 67.3 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl2 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.5 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl2 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 71.5 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl4 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 77.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl4 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 77.0 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl8 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.4 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl8 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 83.4 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl16 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.3 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl16 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.3 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl32 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl32 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.8 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl64 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.6 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl64 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.6 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl128 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.2 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl128 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.2 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl256 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.1 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl256 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.1 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl512 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e8_vl512 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 2.1 | 87.5 | 30.8 | 9 | 1.045 | 0 (0.000) | 2 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0.0 | 0 / 0 |
| micro_vec[default] vle8_vl1 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 1 (3.425) | 258 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 2.6 | 1.9 | 0.0 | 0.0 | 0.0 | 79.1 | 0 / 0 |
| micro_vec[default] vle8_vl1 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 1 (3.425) | 258 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 80.6 | 0 / 0 |
| micro_vec[default] vle8_vl2 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 514 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 88.4 | 0 / 0 |
| micro_vec[default] vle8_vl2 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 514 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 88.4 | 0 / 0 |
| micro_vec[default] vle8_vl4 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 1,026 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.4 | 0 / 0 |
| micro_vec[default] vle8_vl4 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 1,026 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 93.4 | 0 / 0 |
| micro_vec[default] vle8_vl8 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 2,050 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.5 | 0 / 0 |
| micro_vec[default] vle8_vl8 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 2,050 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.5 | 0 / 0 |
| micro_vec[default] vle8_vl16 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 4,098 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.2 | 0 / 0 |
| micro_vec[default] vle8_vl16 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 4,098 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.2 | 0 / 0 |
| micro_vec[default] vle8_vl32 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 8,194 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.1 | 0 / 0 |
| micro_vec[default] vle8_vl32 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 8,194 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.1 | 0 / 0 |
| micro_vec[default] vle8_vl64 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 16,386 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0 / 0 |
| micro_vec[default] vle8_vl64 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 16,386 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0 / 0 |
| micro_vec[default] vle8_vl128 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 32,770 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8 | 0 / 0 |
| micro_vec[default] vle8_vl128 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 32,770 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8 | 0 / 0 |
| micro_vec[default] vle8_vl256 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 65,538 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vle8_vl256 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 65,538 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vle8_vl512 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 131,074 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vle8_vl512 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.058 | 0 (0.000) | 131,074 / 4 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vse8_vl1 default/axi | 5.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.1 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.6 | 8 | 1.058 | 1 (3.401) | 2 / 260 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 2.6 | 1.9 | 0.0 | 0.0 | 0.0 | 78.8 | 0 / 0 |
| micro_vec[default] vse8_vl1 default/soc | 5.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.1 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.6 | 8 | 1.058 | 1 (3.401) | 2 / 260 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 80.4 | 0 / 0 |
| micro_vec[default] vse8_vl8 default/axi | 5.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.1 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.6 | 8 | 1.058 | 0 (0.000) | 2 / 2,052 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.4 | 0 / 0 |
| micro_vec[default] vse8_vl8 default/soc | 5.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.1 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.6 | 8 | 1.058 | 0 (0.000) | 2 / 2,052 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.4 | 0 / 0 |
| micro_vec[default] vse8_vl64 default/axi | 5.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.1 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.6 | 8 | 1.058 | 0 (0.000) | 2 / 16,388 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0 / 0 |
| micro_vec[default] vse8_vl64 default/soc | 5.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.1 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.6 | 8 | 1.058 | 0 (0.000) | 2 / 16,388 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.5 | 0 / 0 |
| micro_vec[default] vse8_vl512 default/axi | 5.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.1 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.6 | 8 | 1.058 | 0 (0.000) | 2 / 131,076 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vse8_vl512 default/soc | 5.8 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 87.1 | 0.0 | 1.7 | 0.0 | 2.4 | 87.5 | 30.6 | 8 | 1.058 | 0 (0.000) | 2 / 131,076 | 0 (0.0) | 0 | 0 | 0/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.9 | 0 / 0 |
| micro_vec[default] vadd_e64_vl8 default/axi | 4.5 | 0.7 | 1.4 | 2.8 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.3 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 31.0 | 9 | 1.041 | 1 (3.448) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.9 | 0.7 | 0.0 | 0.0 | 82.7 | 0.0 | 0 / 0 |
| micro_vec[default] vadd_e64_vl8 default/soc | 4.5 | 0.7 | 1.4 | 2.8 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.3 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 31.0 | 9 | 1.041 | 1 (3.448) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.0 | 0.0 | 0.0 | 83.3 | 0.0 | 0 / 0 |
| micro_vec[default] vmul_e64_vl8 default/axi | 4.5 | 0.7 | 1.4 | 2.8 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.3 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 31.0 | 9 | 1.045 | 1 (3.448) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.1 | 0.0 | 0.0 | 96.4 | 0.0 | 0 / 0 |
| micro_vec[default] vmul_e64_vl8 default/soc | 4.5 | 0.7 | 1.4 | 2.8 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 88.3 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 31.0 | 9 | 1.045 | 1 (3.448) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.6 | 0.0 | 0 / 0 |
| micro_vec[default] vfadd_e64_vl8 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.062 | 1 (3.425) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.2 | 0.0 | 0.0 | 95.3 | 0.0 | 0 / 0 |
| micro_vec[default] vfadd_e64_vl8 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.062 | 1 (3.425) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.1 | 0.0 | 0.0 | 0.0 | 95.5 | 0.0 | 0 / 0 |
| micro_vec[default] vredsum_e64_vl8 default/axi | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.062 | 1 (3.425) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.8 | 0.6 | 0.0 | 0.0 | 84.5 | 0.0 | 0 / 0 |
| micro_vec[default] vredsum_e64_vl8 default/soc | 5.1 | 0.7 | 1.4 | 2.7 | 0.3 | 0.3 | 0.0 | 0.0 | 0.0 | 87.7 | 0.0 | 0.0 | 1.7 | 0.0 | 1.7 | 87.5 | 30.8 | 8 | 1.062 | 1 (3.425) | 2 / 4 | 0 (0.0) | 0 | 0 | 1/0/0/0 | 0.2 | 0.0 | 0.0 | 0.0 | 85.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 plain C default/axi | 83.1 | 10.1 | 2.7 | 4.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.4 | 96.6 | 39.4 | 145,409 | 1.352 | 8 (0.002) | 375,822 / 99,348 | 0 (0.0) | 0 | 0 | 8/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 plain C default/soc | 83.1 | 10.1 | 2.7 | 4.0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.4 | 96.6 | 39.4 | 145,409 | 1.352 | 8 (0.002) | 375,822 / 99,348 | 0 (0.0) | 0 | 0 | 8/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 Zknh default/axi | 77.1 | 13.8 | 3.6 | 5.4 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 55.0 | 96.6 | 53.6 | 145,408 | 1.233 | 8 (0.003) | 376,846 / 98,325 | 0 (0.0) | 0 | 0 | 8/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 Zknh default/soc | 77.1 | 13.8 | 3.6 | 5.4 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 55.0 | 96.6 | 53.6 | 145,408 | 1.233 | 8 (0.003) | 376,846 / 98,325 | 0 (0.0) | 0 | 0 | 8/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/axi | 0.5 | 1.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 97.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.2 | 24.8 | 1.5 | 258 | 1.007 | 38 (0.173) | 32,918 / 4,624 | 0 (0.0) | 0 | 0 | 38/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.6 | 2.1 | 0 / 0 |
| sha256chain[sdk] sha256 RVV x16 (multi-buffer) default/soc | 0.5 | 1.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 97.0 | 0.2 | 0.0 | 0.0 | 0.0 | 0.2 | 24.8 | 1.5 | 258 | 1.007 | 38 (0.173) | 32,918 / 4,624 | 0 (0.0) | 0 | 0 | 38/0/0/0 | 0.0 | 0.0 | 0.0 | 0.0 | 89.6 | 2.1 | 0 / 0 |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/axi | 44.7 | 18.9 | 15.7 | 19.5 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 64.1 | 90.3 | 188.7 | 24,576 | 1.409 | 1 (0.006) | 30,725 / 25,607 | 0 (0.0) | 0 | 31,744 | 1/0/0/31744 | 21.7 | 10.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 accel sigil_sha256_block default/soc | 44.7 | 18.9 | 15.7 | 19.5 | 0.6 | 0.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 64.1 | 90.3 | 188.7 | 24,576 | 1.409 | 1 (0.006) | 30,725 / 25,607 | 0 (0.0) | 0 | 31,744 | 1/0/0/31744 | 21.7 | 10.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 accel sigil_sha256 default/axi | 65.4 | 12.9 | 10.2 | 10.7 | 0.3 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.9 | 88.9 | 101.5 | 67,585 | 1.309 | 6 (0.006) | 133,126 / 105,480 | 0 (0.0) | 0 | 31,744 | 6/0/0/31744 | 4.4 | 2.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha256 accel sigil_sha256 default/soc | 65.4 | 12.9 | 10.2 | 10.7 | 0.3 | 0.3 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 42.9 | 88.9 | 101.5 | 67,585 | 1.309 | 6 (0.006) | 133,126 / 105,480 | 0 (0.0) | 0 | 31,744 | 6/0/0/31744 | 4.4 | 2.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha512 accel sigil_hash default/axi | 72.9 | 4.7 | 9.1 | 12.9 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 33.1 | 68.5 | 93.1 | 93,181 | 1.168 | 7 (0.007) | 47,109 / 92,170 | 0 (0.0) | 0 | 40,957 | 7/0/0/40957 | 6.5 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha512 accel sigil_hash default/soc | 72.9 | 4.7 | 9.1 | 12.9 | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 33.1 | 68.5 | 93.1 | 93,184 | 1.168 | 7 (0.007) | 47,112 / 92,170 | 0 (0.0) | 0 | 40,960 | 7/0/0/40960 | 6.5 | 3.2 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha3-256 accel sigil_hash default/axi | 72.7 | 4.8 | 9.2 | 12.4 | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 33.4 | 62.7 | 86.7 | 47,104 | 1.186 | 2 (0.004) | 26,632 / 51,210 | 0 (0.0) | 0 | 20,480 | 2/0/0/20480 | 5.8 | 2.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain[sdk] sha3-256 accel sigil_hash default/soc | 72.7 | 4.8 | 9.2 | 12.4 | 0.6 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 33.4 | 62.7 | 86.7 | 47,104 | 1.186 | 2 (0.004) | 26,632 / 51,210 | 0 (0.0) | 0 | 20,480 | 2/0/0/20480 | 5.8 | 2.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 plain C default/axi | 83.8 | 9.8 | 2.3 | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.1 | 96.6 | 39.3 | 145,543 | 1.351 | 15 (0.004) | 363,923 / 84,174 | 929 (0.2) | 237 | 0 | 15/929/237/0 | 0.4 | 0.3 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 plain C default/soc | 83.8 | 9.8 | 2.3 | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 37.1 | 96.6 | 39.3 | 145,543 | 1.351 | 15 (0.004) | 363,923 / 84,174 | 929 (0.2) | 237 | 0 | 15/929/237/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 Zknh default/axi | 77.6 | 13.6 | 3.3 | 5.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 55.1 | 96.6 | 53.2 | 145,581 | 1.228 | 18 (0.007) | 371,104 / 91,346 | 1,062 (0.2) | 33 | 0 | 18/1062/33/0 | 0.5 | 0.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 Zknh default/soc | 77.6 | 13.6 | 3.3 | 5.5 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 55.1 | 96.6 | 53.2 | 145,581 | 1.228 | 18 (0.007) | 371,104 / 91,346 | 1,062 (0.2) | 33 | 0 | 18/1062/33/0 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/axi | 0.3 | 1.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 96.7 | 0.7 | 0.1 | 0.0 | 0.0 | 0.0 | 24.5 | 1.5 | 326 | 1.008 | 57 (0.254) | 36,406 / 8,328 | 2,044 (4.6) | 28 | 0 | 57/2044/28/0 | 1.4 | 1.1 | 0.0 | 0.0 | 88.2 | 4.3 | 0 / 0 |
| sha256chain_bulk[sdk] sha256 RVV x16 (16 segments) default/soc | 0.3 | 1.9 | 0.0 | 0.2 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 96.7 | 0.7 | 0.1 | 0.0 | 0.0 | 0.0 | 24.5 | 1.5 | 326 | 1.008 | 57 (0.254) | 36,406 / 8,328 | 2,044 (4.6) | 28 | 0 | 57/2044/28/0 | 0.4 | 0.0 | 0.0 | 0.0 | 89.1 | 3.3 | 0 / 0 |
| sha256chain_bulk[sdk] sha512 accel sigil_hash default/axi | 25.7 | 24.7 | 24.8 | 24.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 74.4 | 99.8 | 247.6 | 16,458 | 1.495 | 2 (0.030) | 16,417 / 16,462 | 894 (2.7) | 12 | 16,409 | 2/894/12/16409 | 32.5 | 18.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha512 accel sigil_hash default/soc | 25.7 | 24.7 | 24.8 | 24.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 74.4 | 99.8 | 247.6 | 16,458 | 1.495 | 2 (0.030) | 16,417 / 16,462 | 894 (2.7) | 12 | 16,409 | 2/894/12/16409 | 26.9 | 12.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/axi | 25.4 | 24.8 | 24.9 | 24.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 74.6 | 99.8 | 248.6 | 16,421 | 1.497 | 1 (0.015) | 16,404 / 16,430 | 896 (2.7) | 3 | 16,396 | 1/896/3/16396 | 32.5 | 18.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |
| sha256chain_bulk[sdk] sha3-256 accel sigil_hash default/soc | 25.4 | 24.8 | 24.9 | 24.9 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 74.6 | 99.8 | 248.6 | 16,421 | 1.497 | 1 (0.015) | 16,404 / 16,430 | 896 (2.7) | 3 | 16,396 | 1/896/3/16396 | 27.0 | 12.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0 / 0 |

Columns: `alu %` = retired alu (% of instret); `load %` = retired load (% of instret); `store %` = retired store (% of instret); `branch %` = retired branch (% of instret); `jal %` = retired jal (% of instret); `jalr %` = retired jalr (% of instret); `mul %` = retired mul (% of instret); `div %` = retired div (% of instret); `fp %` = retired fp (% of instret); `vec %` = retired vec (% of instret); `vls %` = retired vls (% of instret); `vset %` = retired vset (% of instret); `csr %` = retired csr (% of instret); `fence %` = retired fence (% of instret); `rvc %` = compressed (RVC, % of instret); `taken %` = taken branches (% of branches); `redir/ki` = redirects per 1000 instr; `squashed` = squashed wrong-path instr; `I$ acc/i` = I$ fetch accesses per instr; `I$ miss (/ki)` = I$ misses (per 1000 instr); `D$ ld / st` = D$ loads / stores; `D$ miss (%)` = D$ misses (% of accesses); `D$ wb` = D$ write-backs; `D unc` = uncached D accesses; `bus if/df/wb/unc` = bus transactions (I fill / D fill / D wb / uncached); `bus %` = bus busy (% of cycles); `bus wait %` = bus waiting on memory (% of cycles); `M %` = M unit busy (% of cycles); `FPU %` = FPU busy (% of cycles); `vec %` = vector unit busy (% of cycles); `vls %` = vector LS in MEM (% of cycles); `traps` = traps (exceptions / interrupts).

