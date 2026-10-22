# Micro benchmarks: cycles per operation

- Date (UTC): 2026-10-22T09:54:30Z; commit `904d59eb3081c0f6e91c8902473def5519eb06a4` (56-perf-micro); rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Repeats: 2; deterministic: yes
- Memory models: `soc` --mem-lat 1:1 --mem-gap 0 --mem-ready 100; `axi` --axi-lat 24:24 --axi-gap 0 --axi-ready 100 --uart-pop 100

### micro_dmem

Microbenchmarks: pointer-chase latency over working sets 1 KiB..256 KiB (random and address order), load and store streams (cycles per load/store)

Operations per region: 4,096. Breakdown and events per operation from default/soc.

| Region | One operation | cycles/op default/soc | cycles/op default/axi | net of window default/soc | instr/op | where the cycles go per op (default/soc) | I$ miss/op | D$ miss/op |
|---|---|---:|---:|---:|---:|---|---:|---:|
| empty | region overhead: call + return of an empty kernel (cycles/iter is not per-op) | 67 cycles | 92 cycles | - | 21 instr | (window overhead, not per op) | 1 | 0 |
| chase_rand_1k | dependent ld, random cyclic order over 1 KiB (one node per 64-byte line) | 3.095 | 3.101 | 3.078 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0000 |
| chase_rand_2k | dependent ld, random cyclic order over 2 KiB (one node per 64-byte line) | 3.095 | 3.101 | 3.078 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0000 |
| chase_rand_4k | dependent ld, random cyclic order over 4 KiB (one node per 64-byte line) | 3.095 | 3.101 | 3.078 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0000 |
| chase_rand_8k | dependent ld, random cyclic order over 8 KiB (one node per 64-byte line) | 3.095 | 3.101 | 3.078 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0000 |
| chase_rand_12k | dependent ld, random cyclic order over 12 KiB (one node per 64-byte line) | 3.095 | 3.101 | 3.078 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0000 |
| chase_rand_16k | dependent ld, random cyclic order over 16 KiB (one node per 64-byte line) | 3.121 | 3.184 | 3.104 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0020 |
| chase_rand_20k | dependent ld, random cyclic order over 20 KiB (one node per 64-byte line) | 7.474 | 17.431 | 7.458 | 1.037 | dc_miss 4.38, retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.3977 |
| chase_rand_24k | dependent ld, random cyclic order over 24 KiB (one node per 64-byte line) | 9.931 | 25.473 | 9.915 | 1.037 | dc_miss 6.84, retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.6211 |
| chase_rand_32k | dependent ld, random cyclic order over 32 KiB (one node per 64-byte line) | 12.241 | 33.031 | 12.224 | 1.037 | dc_miss 9.15, retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.8311 |
| chase_rand_64k | dependent ld, random cyclic order over 64 KiB (one node per 64-byte line) | 13.962 | 38.665 | 13.946 | 1.037 | dc_miss 10.87, retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.9875 |
| chase_rand_128k | dependent ld, random cyclic order over 128 KiB (one node per 64-byte line) | 14.110 | 39.148 | 14.094 | 1.037 | dc_miss 11.02, retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 1.0010 |
| chase_rand_256k | dependent ld, random cyclic order over 256 KiB (one node per 64-byte line) | 14.110 | 39.148 | 14.094 | 1.037 | dc_miss 11.02, retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 1.0010 |
| chase_seq_4k | dependent ld, address order over 4 KiB (one node per 64-byte line) | 3.095 | 3.101 | 3.078 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0000 |
| chase_seq_8k | dependent ld, address order over 8 KiB (one node per 64-byte line) | 3.097 | 3.110 | 3.081 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0002 |
| chase_seq_16k | dependent ld, address order over 16 KiB (one node per 64-byte line) | 3.121 | 3.184 | 3.104 | 1.037 | retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.0020 |
| chase_seq_32k | dependent ld, address order over 32 KiB (one node per 64-byte line) | 10.482 | 27.274 | 10.465 | 1.037 | dc_miss 7.39, retire 1.04, dc_lat 1.00, loaduse 0.97, fetch_lat 0.07 | 0.0002 | 0.6711 |
| stream_ld | ld, sequential over a 64 KiB buffer, every doubleword (8 per line), no consumer | 4.273 | 7.410 | 4.257 | 1.179 | dc_miss 1.38, retire 1.18, dc_lat 1.00, fetch_lat 0.70 | 0.0002 | 0.1252 |
| stream_st | sd, sequential over a 64 KiB buffer whose lines are all dirty, every doubleword | 6.251 | 13.020 | 6.234 | 1.178 | dc_miss 3.36, retire 1.18, dc_lat 1.00, fetch_lat 0.69 | 0.0002 | 0.1255 |

### micro_imem

Microbenchmarks: instruction fetch over straight-line code footprints 1..32 KiB (cycles per instruction)

Operations per region: 49,152. Breakdown and events per operation from default/soc.

| Region | One operation | cycles/op default/soc | cycles/op default/axi | net of window default/soc | instr/op | where the cycles go per op (default/soc) | I$ miss/op | D$ miss/op |
|---|---|---:|---:|---:|---:|---|---:|---:|
| empty | region overhead: call + return of an empty kernel (cycles/iter is not per-op) | 66 cycles | 91 cycles | - | 19 instr | (window overhead, not per op) | 1 | 0 |
| ifoot_1k | addi (32-bit) of a 1 KiB straight-line footprint, run repeatedly | 2.056 | 2.056 | 2.054 | 1.016 | fetch_lat 1.03, retire 1.02 | 0.0000 | 0.0000 |
| ifoot_2k | addi (32-bit) of a 2 KiB straight-line footprint, run repeatedly | 2.028 | 2.028 | 2.027 | 1.008 | fetch_lat 1.01, retire 1.01 | 0.0000 | 0.0000 |
| ifoot_3k | addi (32-bit) of a 3 KiB straight-line footprint, run repeatedly | 2.019 | 2.019 | 2.018 | 1.006 | fetch_lat 1.01, retire 1.01 | 0.0000 | 0.0000 |
| ifoot_4k | addi (32-bit) of a 4 KiB straight-line footprint, run repeatedly | 2.015 | 2.015 | 2.013 | 1.004 | fetch_lat 1.01, retire 1.00 | 0.0000 | 0.0000 |
| ifoot_6k | addi (32-bit) of a 6 KiB straight-line footprint, run repeatedly | 2.041 | 2.110 | 2.039 | 1.003 | fetch_lat 1.00, retire 1.00 | 0.0028 | 0.0000 |
| ifoot_8k | addi (32-bit) of a 8 KiB straight-line footprint, run repeatedly | 2.032 | 2.087 | 2.031 | 1.002 | fetch_lat 1.00, retire 1.00 | 0.0022 | 0.0000 |
| ifoot_12k | addi (32-bit) of a 12 KiB straight-line footprint, run repeatedly | 2.467 | 3.516 | 2.466 | 1.002 | fetch_lat 1.00, retire 1.00, fetch_miss 0.46 | 0.0420 | 0.0000 |
| ifoot_16k | addi (32-bit) of a 16 KiB straight-line footprint, run repeatedly | 2.526 | 3.712 | 2.525 | 1.001 | fetch_lat 1.00, retire 1.00, fetch_miss 0.52 | 0.0474 | 0.0000 |
| ifoot_24k | addi (32-bit) of a 24 KiB straight-line footprint, run repeatedly | 2.580 | 3.892 | 2.579 | 1.001 | fetch_lat 1.00, retire 1.00, fetch_miss 0.58 | 0.0525 | 0.0000 |
| ifoot_32k | addi (32-bit) of a 32 KiB straight-line footprint, run repeatedly | 2.607 | 3.981 | 2.606 | 1.001 | fetch_lat 1.00, retire 1.00, fetch_miss 0.60 | 0.0550 | 0.0000 |

### micro_pipe

Microbenchmarks: fetch/ALU, branches and jumps, L1 load/store hits, load-use, CSR access (cycles per operation)

Operations per region: 4,096. Breakdown and events per operation from default/soc.

| Region | One operation | cycles/op default/soc | cycles/op default/axi | net of window default/soc | instr/op | where the cycles go per op (default/soc) | I$ miss/op | D$ miss/op |
|---|---|---:|---:|---:|---:|---|---:|---:|
| empty | region overhead: call + return of an empty kernel (cycles/iter is not per-op) | 66 cycles | 91 cycles | - | 19 instr | (window overhead, not per op) | 0 | 1 |
| loop | one trip of a bare loop: addi + taken bnez | 6.016 | 6.022 | 6.000 | 2.005 | fetch_lat 3.01, retire 2.00, branch 1.00 | 0.0002 | 0.0000 |
| alu32_dep | add (32-bit), each dependent on the previous | 2.044 | 2.050 | 2.028 | 1.014 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0000 |
| alu32_indep | add (32-bit), independent | 2.045 | 2.051 | 2.029 | 1.015 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0000 |
| alu16_dep | c.add (16-bit), dependent; two per fetch word | 2.044 | 2.050 | 2.028 | 1.014 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0000 |
| alu32_straddle | add (32-bit), dependent, every one straddling two fetch words | 4.061 | 4.067 | 4.045 | 1.014 | fetch_lat 2.03, retire 1.01, fetch_straddle 1.01 | 0.0002 | 0.0000 |
| br_nt | bne, not taken | 2.044 | 2.050 | 2.028 | 1.014 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0000 |
| br_taken | beq, taken (skips one instruction) | 4.044 | 4.050 | 4.028 | 1.014 | fetch_lat 2.02, retire 1.01, branch 1.00 | 0.0002 | 0.0000 |
| jal | jal x0 (j), skips one instruction | 4.038 | 4.044 | 4.022 | 1.013 | fetch_lat 2.02, retire 1.01, jal 1.00 | 0.0002 | 0.0000 |
| call_ret | jal ra to a callee + its addi + ret | 10.042 | 10.048 | 10.025 | 3.013 | fetch_lat 5.02, retire 3.01, jalr 1.00, jal 1.00 | 0.0002 | 0.0000 |
| jalr_call_ret | jalr ra to a callee + its addi + ret | 10.040 | 10.040 | 10.024 | 3.014 | fetch_lat 5.02, retire 3.01, jalr 2.00 | 0.0000 | 0.0000 |
| brpat_never | data-dependent beqz to the next instruction, never taken: andi + srli + add + beqz, plus 1/8 of ld + addi | 8.612 | 8.618 | 8.596 | 4.287 | retire 4.29, fetch_lat 4.18, dc_lat 0.13 | 0.0002 | 0.0000 |
| brpat_always | as brpat_never, always taken | 10.609 | 10.609 | 10.593 | 4.287 | fetch_lat 5.18, retire 4.29, branch 1.02, dc_lat 0.13 | 0.0000 | 0.0000 |
| brpat_alt | as brpat_never, alternating taken / not taken | 9.609 | 9.609 | 9.593 | 4.287 | fetch_lat 4.68, retire 4.29, branch 0.52, dc_lat 0.13 | 0.0000 | 0.0000 |
| brpat_rand | as brpat_never, random order with exactly half taken | 9.609 | 9.609 | 9.593 | 4.287 | fetch_lat 4.68, retire 4.29, branch 0.52, dc_lat 0.13 | 0.0000 | 0.0000 |
| ld_dep | ld hitting L1, dependent chain (load-to-load latency) | 3.032 | 3.032 | 3.016 | 1.013 | retire 1.01, dc_lat 1.00, loaduse 0.99 | 0.0000 | 0.0000 |
| ld_indep | ld hitting L1, independent, no consumer | 2.541 | 2.547 | 2.525 | 1.014 | retire 1.01, dc_lat 1.00, fetch_lat 0.52 | 0.0002 | 0.0000 |
| ld_use1 | ld + add that uses it (distance 1) | 4.038 | 4.044 | 4.022 | 2.013 | retire 2.01, fetch_lat 1.02, dc_lat 1.00 | 0.0002 | 0.0000 |
| ld_use2 | ld + add, consumer at distance 2 | 4.039 | 4.045 | 4.023 | 2.013 | retire 2.01, fetch_lat 1.02, dc_lat 1.00 | 0.0002 | 0.0000 |
| st | sd hitting L1 | 2.541 | 2.547 | 2.525 | 1.014 | retire 1.01, dc_lat 1.00, fetch_lat 0.52 | 0.0002 | 0.0000 |
| rdcycle | rdcycle | 2.041 | 2.053 | 2.024 | 1.013 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0002 |
| rdtime | rdtime | 2.041 | 2.047 | 2.025 | 1.013 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0000 |
| csrr | csrr mscratch | 2.038 | 2.044 | 2.022 | 1.013 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0000 |
| csrw | csrw mscratch | 2.043 | 2.050 | 2.027 | 1.014 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0000 |
| csrrw | csrrw mscratch (swap) | 2.040 | 2.046 | 2.024 | 1.013 | fetch_lat 1.02, retire 1.01 | 0.0002 | 0.0000 |
| fence | fence | 2.038 | 2.038 | 2.022 | 1.013 | fetch_lat 1.02, retire 1.01 | 0.0000 | 0.0000 |

### micro_units

Microbenchmarks: M unit and FPU latency (dependent chains) and back-to-back throughput (cycles per operation)

Operations per region: 1,024. Breakdown and events per operation from default/soc.

| Region | One operation | cycles/op default/soc | cycles/op default/axi | net of window default/soc | instr/op | where the cycles go per op (default/soc) | I$ miss/op | D$ miss/op |
|---|---|---:|---:|---:|---:|---|---:|---:|
| empty | region overhead: call + return of an empty kernel (cycles/iter is not per-op) | 67 cycles | 92 cycles | - | 21 instr | (window overhead, not per op) | 1 | 0 |
| mul_dep | mul, dependent chain (latency) | 4.201 | 4.226 | 4.136 | 1.061 | muldiv 2.00, fetch_lat 1.09, retire 1.06 | 0.0010 | 0.0000 |
| mul_indep | mul, independent (back-to-back throughput) | 4.191 | 4.265 | 4.126 | 1.061 | muldiv 2.00, fetch_lat 1.08, retire 1.06 | 0.0020 | 0.0010 |
| div_dep | div, dependent, 63 significant quotient bits (x / 1) | 36.182 | 36.230 | 36.116 | 1.058 | muldiv 34.00, fetch_lat 1.08, retire 1.06 | 0.0020 | 0.0000 |
| div_indep | div, independent, 63 significant quotient bits | 36.179 | 36.203 | 36.113 | 1.058 | muldiv 34.00, fetch_lat 1.08, retire 1.06 | 0.0010 | 0.0000 |
| div_short | div, independent, \|dividend\| < \|divisor\| (3 / 7) | 4.154 | 4.179 | 4.089 | 1.053 | muldiv 2.00, fetch_lat 1.07, retire 1.05 | 0.0010 | 0.0000 |
| divw_dep | divw, dependent, 31 significant quotient bits | 20.175 | 20.224 | 20.109 | 1.054 | muldiv 18.00, fetch_lat 1.07, retire 1.05 | 0.0010 | 0.0010 |
| rem_indep | rem, independent, 62 significant quotient bits (x % 3) | 35.167 | 35.191 | 35.102 | 1.056 | muldiv 33.00, fetch_lat 1.07, retire 1.06 | 0.0010 | 0.0000 |
| fadd_d_dep | fadd.d, dependent | 6.198 | 6.296 | 6.133 | 1.055 | fpu 4.00, fetch_lat 1.07, retire 1.05 | 0.0020 | 0.0020 |
| fadd_d_indep | fadd.d, independent | 6.160 | 6.185 | 6.095 | 1.052 | fpu 4.00, fetch_lat 1.07, retire 1.05 | 0.0010 | 0.0000 |
| fmul_d_dep | fmul.d, dependent | 6.183 | 6.231 | 6.117 | 1.055 | fpu 4.00, fetch_lat 1.08, retire 1.05 | 0.0010 | 0.0010 |
| fmadd_d_dep | fmadd.d, dependent (x = x * a + b) | 8.194 | 8.219 | 8.129 | 1.059 | fpu 6.00, fetch_lat 1.08, retire 1.06 | 0.0010 | 0.0000 |
| fdiv_d_dep | fdiv.d, dependent | 33.173 | 33.197 | 33.107 | 1.055 | fpu 31.00, fetch_lat 1.08, retire 1.05 | 0.0010 | 0.0000 |
| fdiv_d_indep | fdiv.d, independent | 33.166 | 33.190 | 33.101 | 1.054 | fpu 31.00, fetch_lat 1.07, retire 1.05 | 0.0010 | 0.0000 |
| fsqrt_d_dep | fsqrt.d, dependent | 33.166 | 33.215 | 33.101 | 1.051 | fpu 31.00, fetch_lat 1.07, retire 1.05 | 0.0010 | 0.0010 |
| fsqrt_d_indep | fsqrt.d, independent | 33.154 | 33.154 | 33.089 | 1.052 | fpu 31.00, fetch_lat 1.07, retire 1.05 | 0.0000 | 0.0000 |
| fdiv_s_dep | fdiv.s, dependent | 18.179 | 18.203 | 18.113 | 1.057 | fpu 16.00, fetch_lat 1.08, retire 1.06 | 0.0010 | 0.0000 |
| fsqrt_s_dep | fsqrt.s, dependent | 18.167 | 18.191 | 18.102 | 1.053 | fpu 16.00, fetch_lat 1.07, retire 1.05 | 0.0010 | 0.0000 |

### micro_vec

Microbenchmarks: vsetvli cost, vadd/vle8/vse8 versus VL (1..512), e64 vadd/vmul/vfadd/vredsum (cycles per vector instruction)

Operations per region: 256. Breakdown and events per operation from default/soc.

| Region | One operation | cycles/op default/soc | cycles/op default/axi | net of window default/soc | instr/op | where the cycles go per op (default/soc) | I$ miss/op | D$ miss/op |
|---|---|---:|---:|---:|---:|---|---:|---:|
| empty | region overhead: call + return of an empty kernel (cycles/iter is not per-op) | 81 cycles | 131 cycles | - | 22 instr | (window overhead, not per op) | 1 | 1 |
| vsetvli_same | vsetvli e8 m8 with the same AVL and vtype as the previous one | 2.434 | 2.531 | 2.117 | 1.145 | fetch_lat 1.18, retire 1.14 | 0.0039 | 0.0000 |
| vsetvli_toggle | vsetvli alternating e8/m8 and e32/m1 (vtype changes every time) | 2.488 | 2.586 | 2.172 | 1.145 | fetch_lat 1.20, retire 1.14 | 0.0039 | 0.0000 |
| vadd_e8_vl1 | vadd.vv e8 m8, vl=1, dependent through vd | 7.434 | 7.531 | 7.117 | 1.141 | vec 5.00, fetch_lat 1.18, retire 1.14 | 0.0039 | 0.0000 |
| vadd_e8_vl2 | vadd.vv e8 m8, vl=2, dependent through vd | 8.395 | 8.395 | 8.078 | 1.141 | vec 6.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vadd_e8_vl4 | vadd.vv e8 m8, vl=4, dependent through vd | 10.395 | 10.395 | 10.078 | 1.141 | vec 8.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vadd_e8_vl8 | vadd.vv e8 m8, vl=8, dependent through vd | 14.395 | 14.395 | 14.078 | 1.141 | vec 12.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vadd_e8_vl16 | vadd.vv e8 m8, vl=16, dependent through vd | 22.395 | 22.395 | 22.078 | 1.141 | vec 20.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vadd_e8_vl32 | vadd.vv e8 m8, vl=32, dependent through vd | 38.395 | 38.395 | 38.078 | 1.141 | vec 36.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vadd_e8_vl64 | vadd.vv e8 m8, vl=64, dependent through vd | 70.395 | 70.395 | 70.078 | 1.141 | vec 68.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vadd_e8_vl128 | vadd.vv e8 m8, vl=128, dependent through vd | 134.395 | 134.395 | 134.078 | 1.141 | vec 132.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vadd_e8_vl256 | vadd.vv e8 m8, vl=256, dependent through vd | 262.395 | 262.395 | 262.078 | 1.141 | vec 260.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vadd_e8_vl512 | vadd.vv e8 m8, vl=512, dependent through vd | 518.395 | 518.395 | 518.078 | 1.141 | vec 516.00, fetch_lat 1.18, retire 1.14 | 0.0000 | 0.0000 |
| vle8_vl1 | vle8.v (unit stride, L1 hit), vl=1 | 4.961 | 5.059 | 4.645 | 1.141 | vls 3.00, retire 1.14, fetch_lat 0.69 | 0.0039 | 0.0000 |
| vle8_vl2 | vle8.v (unit stride, L1 hit), vl=2 | 7.918 | 7.918 | 7.602 | 1.141 | vls 6.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vle8_vl4 | vle8.v (unit stride, L1 hit), vl=4 | 13.918 | 13.918 | 13.602 | 1.141 | vls 12.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vle8_vl8 | vle8.v (unit stride, L1 hit), vl=8 | 25.918 | 25.918 | 25.602 | 1.141 | vls 24.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vle8_vl16 | vle8.v (unit stride, L1 hit), vl=16 | 49.918 | 49.918 | 49.602 | 1.141 | vls 48.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vle8_vl32 | vle8.v (unit stride, L1 hit), vl=32 | 97.918 | 97.918 | 97.602 | 1.141 | vls 96.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vle8_vl64 | vle8.v (unit stride, L1 hit), vl=64 | 193.918 | 193.918 | 193.602 | 1.141 | vls 192.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vle8_vl128 | vle8.v (unit stride, L1 hit), vl=128 | 385.918 | 385.918 | 385.602 | 1.141 | vls 384.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vle8_vl256 | vle8.v (unit stride, L1 hit), vl=256 | 769.918 | 769.918 | 769.602 | 1.141 | vls 768.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vle8_vl512 | vle8.v (unit stride, L1 hit), vl=512 | 1,537.918 | 1,537.918 | 1,537.602 | 1.141 | vls 1536.00, retire 1.14, fetch_lat 0.69 | 0.0000 | 0.0000 |
| vse8_vl1 | vse8.v (unit stride, L1 hit), vl=1 | 4.977 | 5.074 | 4.660 | 1.148 | vls 3.00, retire 1.15, fetch_lat 0.70 | 0.0039 | 0.0000 |
| vse8_vl8 | vse8.v (unit stride, L1 hit), vl=8 | 25.934 | 25.934 | 25.617 | 1.148 | vls 24.00, retire 1.15, fetch_lat 0.70 | 0.0000 | 0.0000 |
| vse8_vl64 | vse8.v (unit stride, L1 hit), vl=64 | 193.934 | 193.934 | 193.617 | 1.148 | vls 192.00, retire 1.15, fetch_lat 0.70 | 0.0000 | 0.0000 |
| vse8_vl512 | vse8.v (unit stride, L1 hit), vl=512 | 1,537.934 | 1,537.934 | 1,537.617 | 1.148 | vls 1536.00, retire 1.15, fetch_lat 0.70 | 0.0000 | 0.0000 |
| vadd_e64_vl8 | vadd.vv e64 m1, vl=8 | 14.414 | 14.512 | 14.098 | 1.133 | vec 12.00, fetch_lat 1.17, retire 1.13 | 0.0039 | 0.0000 |
| vmul_e64_vl8 | vmul.vv e64 m1, vl=8 | 70.418 | 70.516 | 70.102 | 1.133 | vec 68.00, fetch_lat 1.18, retire 1.13 | 0.0039 | 0.0000 |
| vfadd_e64_vl8 | vfadd.vv e64 m1, vl=8 | 54.469 | 54.566 | 54.152 | 1.141 | vec 52.00, fetch_lat 1.19, retire 1.14 | 0.0039 | 0.0000 |
| vredsum_e64_vl8 | vredsum.vs e64 m1, vl=8, dependent through vs1/vd | 16.465 | 16.562 | 16.148 | 1.141 | vec 14.00, fetch_lat 1.19, retire 1.14 | 0.0039 | 0.0000 |

### Derived cache parameters

| Config | Memory | D$ miss penalty (cycles, chase 256 KiB) | D$ load miss cost (cycles/op, chase 256 KiB - chase 1 KiB) | largest chase that hits (miss/op < 0.01) | I$ miss penalty (cycles, footprint 32 KiB) | largest footprint that hits (I$ miss/instr < 0.001) |
|---|---|---:|---:|---:|---:|---:|
| default | soc | 12.0 | 11.02 | 16 KiB | 12.0 | 4 KiB |
| default | axi | 37.0 | 36.05 | 16 KiB | 37.0 | 4 KiB |

