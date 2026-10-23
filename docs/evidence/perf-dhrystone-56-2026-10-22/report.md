# Sigil performance report

- Date (UTC): 2026-10-22T08:34:51Z
- Commit: `534f846e0ea26f7d5be4e882e3149a3e6d36c324` (HEAD); merge-base with main `eeaa33299d7b`; rtl/ tree `89b98cb227c6`
- Simulator: Verilator 5.048 2026-04-26 rev v5.048; compiler: riscv64-unknown-elf-gcc (g6afcc4f6d) 16.1.0
- Host: ip-172-31-65-164 Linux 7.0.0-1014-aws x86_64
- Memory model `soc`: `--mem-lat 1:1 --mem-gap 0 --mem-ready 100`
- Memory model `axi`: `--axi-lat 24:24 --axi-gap 0 --axi-ready 100 --uart-pop 100`
- Repeats: 2; deterministic: yes (identical counts)
- Image `dhrystone-scalar`: sha256 `b7173e4e26bda6dc`, scalar ISA, -march=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh (the DMIPS/MHz headline)
- Image `dhrystone-sdk`: sha256 `d15a6c7161f7cfdf`, SDK default -march (with V): GCC expands the 56-byte struct copy into a vle8/vse8 loop

## Configurations (as reported by the counter records)

| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |
|---|---|---|---|---|---:|---:|---:|
| default | axi | `fpga_top_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |
| default | soc | `soc_rtl_tb` | 64x2x64 | 64x4x64 | 0 | 0 | 1 |
| sky130 | axi | `fpga_top_tb_sky130` | 64x1x64 | 64x1x64 | 1 | 1 | 1 |
| sky130 | soc | `soc_rtl_tb_sky130` | 64x1x64 | 64x1x64 | 1 | 1 | 1 |
| oreg | axi | `fpga_top_tb_oreg` | 64x2x64 | 64x4x64 | 1 | 1 | 1 |
| oreg | soc | `soc_rtl_tb_oreg` | 64x2x64 | 64x4x64 | 1 | 1 | 1 |
| fpga | axi | `fpga_top_tb_vrforeg` | 64x2x64 | 64x4x64 | 0 | 1 | 1 |
| fpga | soc | `soc_rtl_tb_vrforeg` | 64x2x64 | 64x4x64 | 0 | 1 | 1 |

## Summary

| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Metric | HW-counter cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|
| dhrystone [scalar] | default | axi | 2000 | 3,070,652 | 1,036,022 | 0.337 | 2.964 | 1,535.3 | 0.371 DMIPS/MHz | 3,070,621 |
| dhrystone [scalar] | default | soc | 2000 | 3,070,244 | 1,036,022 | 0.337 | 2.963 | 1,535.1 | 0.371 DMIPS/MHz | 3,070,213 |
| dhrystone [scalar] | sky130 | axi | 2000 | 5,670,943 | 1,036,022 | 0.183 | 5.474 | 2,835.5 | 0.201 DMIPS/MHz | 5,670,890 |
| dhrystone [scalar] | sky130 | soc | 2000 | 5,272,386 | 1,036,022 | 0.196 | 5.089 | 2,636.2 | 0.216 DMIPS/MHz | 5,272,333 |
| dhrystone [scalar] | oreg | axi | 2000 | 5,062,713 | 1,036,022 | 0.205 | 4.887 | 2,531.4 | 0.225 DMIPS/MHz | 5,062,660 |
| dhrystone [scalar] | oreg | soc | 2000 | 5,062,305 | 1,036,022 | 0.205 | 4.886 | 2,531.2 | 0.225 DMIPS/MHz | 5,062,252 |
| dhrystone [scalar] | fpga | axi | 2000 | 3,070,652 | 1,036,022 | 0.337 | 2.964 | 1,535.3 | 0.371 DMIPS/MHz | 3,070,621 |
| dhrystone [scalar] | fpga | soc | 2000 | 3,070,244 | 1,036,022 | 0.337 | 2.963 | 1,535.1 | 0.371 DMIPS/MHz | 3,070,213 |
| dhrystone [sdk] | default | axi | 2000 | 3,482,658 | 1,022,022 | 0.293 | 3.408 | 1,741.3 | 0.327 DMIPS/MHz | 3,482,595 |
| dhrystone [sdk] | default | soc | 2000 | 3,482,242 | 1,022,022 | 0.293 | 3.407 | 1,741.1 | 0.327 DMIPS/MHz | 3,482,204 |
| dhrystone [sdk] | sky130 | axi | 2000 | 6,596,705 | 1,022,022 | 0.155 | 6.455 | 3,298.4 | 0.173 DMIPS/MHz | 6,596,623 |
| dhrystone [sdk] | sky130 | soc | 2000 | 5,966,289 | 1,022,022 | 0.171 | 5.838 | 2,983.1 | 0.191 DMIPS/MHz | 5,966,232 |
| dhrystone [sdk] | oreg | axi | 2000 | 5,632,705 | 1,022,022 | 0.181 | 5.511 | 2,816.4 | 0.202 DMIPS/MHz | 5,632,623 |
| dhrystone [sdk] | oreg | soc | 2000 | 5,632,289 | 1,022,022 | 0.181 | 5.511 | 2,816.1 | 0.202 DMIPS/MHz | 5,632,232 |
| dhrystone [sdk] | fpga | axi | 2000 | 3,594,658 | 1,022,022 | 0.284 | 3.517 | 1,797.3 | 0.317 DMIPS/MHz | 3,594,595 |
| dhrystone [sdk] | fpga | soc | 2000 | 3,594,242 | 1,022,022 | 0.284 | 3.517 | 1,797.1 | 0.317 DMIPS/MHz | 3,594,204 |

## Where the cycles go (% of cycles in the measured region)

| Category | dhrystone[scalar] default/axi | dhrystone[scalar] default/soc | dhrystone[scalar] sky130/axi | dhrystone[scalar] sky130/soc | dhrystone[scalar] oreg/axi | dhrystone[scalar] oreg/soc | dhrystone[scalar] fpga/axi | dhrystone[scalar] fpga/soc | dhrystone[sdk] default/axi | dhrystone[sdk] default/soc | dhrystone[sdk] sky130/axi | dhrystone[sdk] sky130/soc | dhrystone[sdk] oreg/axi | dhrystone[sdk] oreg/soc | dhrystone[sdk] fpga/axi | dhrystone[sdk] fpga/soc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| retire (base) | 33.7 | 33.7 | 18.3 | 19.6 | 20.5 | 20.5 | 33.7 | 33.7 | 29.3 | 29.3 | 15.5 | 17.1 | 18.1 | 18.1 | 28.4 | 28.4 |
| fetch: I$ hit latency / issue gap | 40.6 | 40.6 | 53.4 | 57.5 | 59.9 | 59.9 | 40.6 | 40.6 | 32.8 | 32.9 | 42.1 | 46.6 | 49.3 | 49.3 | 31.8 | 31.8 |
| fetch: 32-bit instr straddles a word | 8.9 | 8.9 | 3.7 | 4.0 | 4.1 | 4.1 | 8.9 | 8.9 | 4.4 | 4.4 | 1.5 | 1.6 | 1.7 | 1.7 | 4.2 | 4.2 |
| fetch: I$ miss | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| squashed: taken branch | 2.3 | 2.3 | 0.0 | 0.0 | 0.0 | 0.0 | 2.3 | 2.3 | 2.1 | 2.1 | 0.0 | 0.0 | 0.0 | 0.0 | 2.1 | 2.1 |
| squashed: jal | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.7 | 0.7 | 0.8 | 0.8 | 0.0 | 0.0 | 0.0 | 0.0 | 0.8 | 0.8 |
| squashed: jalr | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.7 | 0.7 | 0.7 | 0.7 | 0.0 | 0.0 | 0.0 | 0.0 | 0.7 | 0.7 |
| load-use interlock | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.1 | 0.1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| EX: M unit (mul/div) | 0.2 | 0.2 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 0.2 | 0.2 | 0.2 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 0.2 |
| MEM: D$ hit latency | 12.7 | 12.7 | 13.8 | 14.8 | 15.4 | 15.4 | 12.7 | 12.7 | 10.3 | 10.3 | 10.9 | 12.1 | 12.8 | 12.8 | 10.0 | 10.0 |
| MEM: D$ miss | 0.0 | 0.0 | 10.7 | 4.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 14.6 | 5.6 | 0.0 | 0.0 | 0.0 | 0.0 |
| MEM: vector load/store | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 19.3 | 19.3 | 15.3 | 16.9 | 17.9 | 17.9 | 21.8 | 21.8 |

## Events

| Event | dhrystone[scalar] default/axi | dhrystone[scalar] default/soc | dhrystone[scalar] sky130/axi | dhrystone[scalar] sky130/soc | dhrystone[scalar] oreg/axi | dhrystone[scalar] oreg/soc | dhrystone[scalar] fpga/axi | dhrystone[scalar] fpga/soc | dhrystone[sdk] default/axi | dhrystone[sdk] default/soc | dhrystone[sdk] sky130/axi | dhrystone[sdk] sky130/soc | dhrystone[sdk] oreg/axi | dhrystone[sdk] oreg/soc | dhrystone[sdk] fpga/axi | dhrystone[sdk] fpga/soc |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| retired alu (% of instret) | 39.2 | 39.2 | 39.2 | 39.2 | 39.2 | 39.2 | 39.2 | 39.2 | 40.5 | 40.5 | 40.5 | 40.5 | 40.5 | 40.5 | 40.5 | 40.5 |
| retired load (% of instret) | 22.8 | 22.8 | 22.8 | 22.8 | 22.8 | 22.8 | 22.8 | 22.8 | 21.7 | 21.7 | 21.7 | 21.7 | 21.7 | 21.7 | 21.7 | 21.7 |
| retired store (% of instret) | 14.9 | 14.9 | 14.9 | 14.9 | 14.9 | 14.9 | 14.9 | 14.9 | 13.5 | 13.5 | 13.5 | 13.5 | 13.5 | 13.5 | 13.5 | 13.5 |
| retired branch (% of instret) | 16.6 | 16.6 | 16.6 | 16.6 | 16.6 | 16.6 | 16.6 | 16.6 | 17.0 | 17.0 | 17.0 | 17.0 | 17.0 | 17.0 | 17.0 | 17.0 |
| retired jal (% of instret) | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 | 3.5 |
| retired jalr (% of instret) | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 | 2.9 |
| retired div (% of instret) | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 |
| retired vls (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 | 0.4 | 0.4 | 0.4 | 0.4 | 0.4 | 0.4 | 0.4 |
| retired vset (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 | 0.2 |
| retired csr (% of instret) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| compressed (RVC, % of instret) | 73.7 | 73.7 | 73.7 | 73.7 | 73.7 | 73.7 | 73.7 | 73.7 | 73.2 | 73.2 | 73.2 | 73.2 | 73.2 | 73.2 | 73.2 | 73.2 |
| taken branches (% of branches) | 66.3 | 66.3 | 66.3 | 66.3 | 66.3 | 66.3 | 66.3 | 66.3 | 65.5 | 65.5 | 65.5 | 65.5 | 65.5 | 65.5 | 65.5 | 65.5 |
| redirects per 1000 instr | 173.7 | 173.7 | 173.7 | 173.7 | 173.7 | 173.7 | 173.7 | 173.7 | 176.1 | 176.1 | 176.1 | 176.1 | 176.1 | 176.1 | 176.1 | 176.1 |
| squashed wrong-path instr | 115,999 | 115,999 | 0 | 0 | 0 | 0 | 115,999 | 115,999 | 125,999 | 125,999 | 0 | 0 | 0 | 0 | 125,999 | 125,999 |
| I$ fetch accesses per instr | 1.450 | 1.450 | 1.376 | 1.376 | 1.376 | 1.376 | 1.450 | 1.450 | 1.354 | 1.354 | 1.272 | 1.272 | 1.272 | 1.272 | 1.354 | 1.354 |
| I$ misses (per 1000 instr) | 13 (0.013) | 13 (0.013) | 13 (0.013) | 13 (0.013) | 13 (0.013) | 13 (0.013) | 13 (0.013) | 13 (0.013) | 12 (0.012) | 12 (0.012) | 12 (0.012) | 12 (0.012) | 12 (0.012) | 12 (0.012) | 12 (0.012) | 12 (0.012) |
| D$ loads / stores | 236,002 / 154,004 | 236,002 / 154,004 | 236,002 / 154,004 | 236,002 / 154,004 | 236,002 / 154,004 | 236,002 / 154,004 | 236,002 / 154,004 | 236,002 / 154,004 | 334,002 / 250,004 | 334,002 / 250,004 | 334,002 / 250,004 | 334,002 / 250,004 | 334,002 / 250,004 | 334,002 / 250,004 | 334,002 / 250,004 | 334,002 / 250,004 |
| D$ misses (% of accesses) | 2 (0.0) | 2 (0.0) | 8,004 (2.1) | 8,004 (2.1) | 2 (0.0) | 2 (0.0) | 2 (0.0) | 2 (0.0) | 2 (0.0) | 2 (0.0) | 12,002 (2.1) | 12,002 (2.1) | 2 (0.0) | 2 (0.0) | 2 (0.0) | 2 (0.0) |
| D$ write-backs | 1 | 1 | 6,004 | 6,004 | 1 | 1 | 1 | 1 | 2 | 2 | 10,002 | 10,002 | 2 | 2 | 2 | 2 |
| uncached D accesses | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| bus transactions (I fill / D fill / D wb / uncached) | 13/2/1/0 | 13/2/1/0 | 13/8004/6004/0 | 13/8004/6004/0 | 13/2/1/0 | 13/2/1/0 | 13/2/1/0 | 13/2/1/0 | 12/2/2/0 | 12/2/2/0 | 12/12002/10002/0 | 12/12002/10002/0 | 12/2/2/0 | 12/2/2/0 | 12/2/2/0 | 12/2/2/0 |
| bus busy (% of cycles) | 0.0 | 0.0 | 9.3 | 2.4 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 12.6 | 3.3 | 0.0 | 0.0 | 0.0 | 0.0 |
| bus waiting on memory (% of cycles) | 0.0 | 0.0 | 7.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 9.6 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| M unit busy (% of cycles) | 0.2 | 0.2 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 0.2 | 0.2 | 0.2 | 0.1 | 0.1 | 0.1 | 0.1 | 0.2 | 0.2 |
| FPU busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| vector unit busy (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| vector LS in MEM (% of cycles) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 19.4 | 19.4 | 15.3 | 17.0 | 18.0 | 18.0 | 21.9 | 21.9 |
| traps (exceptions / interrupts) | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

