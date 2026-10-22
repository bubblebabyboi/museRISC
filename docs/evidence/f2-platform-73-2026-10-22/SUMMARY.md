# Sigil Linux platform on a real AWS F2: 64 GiB DDR4 + 16 GiB HBM (#65 #66 #67 #62 #63, 2026-10-22)

- **AFI `afi-035809e576d7ea8d5` / AGFI `agfi-0a1fd54ef68bdc754` (public)**, shell
  `0x10212415`, PCI `0x1D0F:0xF054` (subsystem `0x5160:0x1D0F`). Built from
  branch `73-f2-memory-platform` commit `e641930` (RTL unchanged since), aws-fpga
  v2.3.5, Vivado 2025.2, unencrypted DCP `2026_10_22-070909.Developer_CL.tar`
  (sha256 `69307c69…86b0cd`, manifest `dcp_hash=2475a285…ab805`), recipes
  A1 / **B1 (core 62.5 MHz)** / C0 / **H0 (HBM AXI 250 MHz)** — [`vivado/`](vivado/).
- Timing (post-route, all constraints met): WNS **+0.150 ns** (DDR4 controller
  clock), core clock (16 ns) **+0.635 ns**, `clk_main_a0` +0.166 ns, HBM AXI
  (4 ns) +0.336 ns, WHS +0.010 ns. Build 1 h 03 min on the r7iz.8xlarge.
- Utilization (CL, post-route): 131,694 LUTs (10.1 %), 116,956 FFs, 75 RAMB36,
  3 RAMB18, 32 DSP. SoC + OCL block 82,676 LUTs (+2,147 vs. the #54 build: memory
  engine, error capture, finisher, RTC, UART TX FIFO); HBM subsystem 3,199;
  SmartConnect 10,180; five SLR register slices ≈ 600–670 each; `sh_ddr` 23,632.
- Instance: `f2.6xlarge` `i-0172708b8206bb63d`, us-east-1a, FPGA Developer AMI
  1.19.2, AMD EPYC 7R13, kernel 6.8.0-1021-aws; `sigil_host` built there against
  the v2.3.5 SDK. Session script: `fpga/scripts/f2_platform_tests.sh`
  (`hw/results.txt`, per step `hw/*.host` = host stderr, `hw/*.uart` = UART).

## Results

| Step | Result |
|---|---|
| **#62 root cause** (`ecc62-noscrub`: fresh AFI, DDR4 not scrubbed, `hash_soc_test`) | first memory error = **read of PA `0x8000_0900` (line refill), SLVERR** — the line just past the 2,104-byte image, never written → DDR4 uncorrectable ECC; 4 errors in the first 7,182 cycles |
| **#62 fix** (`hash-scrub`): DDR4 zeroed once by the CL memory engine, then the same program | **64 GiB scrubbed in 17.2 s (4.00 GB/s)**; `SOC HASH PASS`, STATUS without `mem_err` |
| **Full-range memory test, engine** (`memtest-engine`, `--memtest all`) | DDR4 64 GiB and HBM 16 GiB: address pattern written and checked with two seeds — **0 mismatches, 0 error responses**, 4.00 GB/s (= 64 B × 62.5 MHz, the engine's core-clock limit), 86 s for 4 × 80 GiB |
| **Sparse test from the core** (`memtest-core`, `f2_memtest`, 64 KiB stride) | **DDR4 1,048,576 lines** over all 64 GiB (first 16 MiB skipped: image/stack) and **HBM 262,144 lines** over all 16 GiB, address-unique words written then verified through the L1s — **0 errors** (also at 16 MiB, 1 MiB, 256 KiB strides) |
| **Latency from the core** (cold 64-byte refill, `rdcycle` around a blocking load, 4096 samples) | **DDR4: avg 45.6, min 42, max 78 cycles = 729 ns avg** (16 ns cycle); **HBM: avg 50.8, min 49, max 61 cycles = 813 ns avg**; L1 hit 9 cycles (incl. `rdcycle`). Sequential 4 MiB read, one load per line: DDR4 52 cycles/line (76.7 MB/s), HBM 57 (69.8 MB/s) — one outstanding request, latency-bound (perf epic #61) |
| Window edges (`platform`, `f2_platform_test`) | lines at DDR4 `0x8080_0000`, 256 MiB, the 4 GiB edge, 32 GiB, the last DDR4 line `0x10_7FFF_FFC0`, HBM `0x10_8000_0000`, `+64`, 8 GiB and the last line `0x14_7FFF_FFC0` written, evicted, read back — PASS |
| Out-of-window read (`platform-oob`) | PA `0x14_8000_0000` returns 0; capture: "read of SoC PA `0x14_8000_0000` … outside the RAM window (no AXI transaction)" |
| **Test finisher** | power off `0x5555` → exit 0; fail `(42 << 16) \| 0x3333` → exit 1, "finisher fail code 42"; **reboot `0x7777`** → host reloads only the boot images and keeps the pmem window: the second boot finds what the first wrote at `0xC_8000_0000` (`REBOOTED`, written back by `FENCE.I`), powers off, `--save` returns it (`platform-reboot`) |
| **RTC** | reads the host's wall clock (e.g. `0x18e0ce5718b6895d` ns = 2026-10-22 08:58 UTC), advances, guest write, alarm → PLIC source 11 pending → cleared |
| **#63** (`linux`: the #55 OpenSBI v1.9 + Linux 6.6 payload, `ns16550a`) | every console line intact — `Freeing unused kernel image (initmem) memory: 2476K`, `Run /init as init process`, `MUSERISC_LINUX_BOOT_OK` after 64 s (4.02 G cycles); in #55 these lines were mangled. UART bursts in `f2_platform_test` (16 bytes per THRE, like Linux's 8250 driver): 64 × 62 bytes byte-exact |
| **Console** (`console.typescript`) | `--console` in a pty: the smoke test's RX line typed in, `FPGA SMOKE PASS`, Ctrl-] → detached (exit 4), SoC left running with the UART in drop mode |
| Firmware, **no `--ignore-mem-err`** | `hash`, `smoke` (512 KiB D$ test + RX line), `crypto` (secp256k1), `ed25519`, OpenSBI → `s_hello`, all 7 SDK examples — PASS; measured core clock **62.500 MHz** on every run |
| **Bulk load/save** (`bulk-t1/8`, `bulk8g`) | 4 GiB random file to DDR4 (`0x1_0000_0000`) and HBM (`0x11_0000_0000`), saved back: sha256 identical. PCIS write (mmap'd WC BAR4, AVX2 non-temporal stores) **3.61 GB/s DDR4, 2.4–3.9 GB/s HBM**; PCIS read (streaming loads) **1.04 GB/s with 8 threads** (0.37 with 1, 0.86 with 4, 0.70 with 16, 0.55 with 24). 8 GiB pmem-window round trip (`0xC_8000_0000`, the OS disk layout): load 2.38 s (3.61 GB/s), save 12.4 s at 16 threads, sha256 identical. Saving to the root EBS volume is disk-bound (≈130 MB/s); `/dev/shm` or the instance NVMe is not |
| Old public AFI with the new host (`hw/old-afi-v3-compat.log`) | v3 CL detected (128 MiB window, no scrub/HBM), `SOC HASH PASS` with `--ignore-mem-err`; `sigil-run` keeps working with it |

Notes:
- `hw/results.txt` is the first pass of the session script. Its
  `platform-failcode` / `platform-reboot` rows ended at the `F2 PLATFORM PASS`
  marker before the finisher write, and `memtest-core` read the previous step's
  mailbox (64-byte stride, timed out). The script now passes `--no-markers` and
  `--mailbox 0`; the `platform*.{host,uart}` and `memtest-core.*` files are the
  re-runs (results as in the table). The reboot check is keyed off the
  host-loaded pmem marker (stale DDR4 state from the first pass had faked a
  second boot).
- F2 time: instance launched 08:37 UTC, tests finished ≈09:05 UTC; the instance
  was then handed to the OS agent for the first Debian boot (they terminate it).
