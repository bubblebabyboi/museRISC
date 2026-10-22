# First run of the whole Sigil SoC on an AWS F2 FPGA (#55, 2026-10-22)

- AFI: `afi-019aabf5d4a815ae5` / **`agfi-035116450e0a0d093`** (public), shell `0x10212415`,
  PCI `0x1D0F:0xF054`, built from commit `4058108` (unencrypted DCP
  `2026_10_21-092135.Developer_CL.tar`, sha256 `9a8ecf4a…c112`), aws-fpga v2.3.5,
  core clock AWS_CLK_GEN recipe B1 = **62.5 MHz (interim)**.
- Instance: `f2.6xlarge` (1× VU47P), us-east-1a, F2 Developer AMI 1.19.2; about
  10 minutes of F2 time; instance terminated afterwards.
- Host runtime: `fpga/host/sigil_host` built on the instance against the aws-fpga
  v2.3.5 SDK. Payload checksums in `instance-info.txt`.

| Run | Result | Core cycles | Wall |
|---|---|---:|---:|
| `hash_soc_test.bin` | **SOC HASH PASS** (SHA-512 of 1000 B in 22,606 cycles) | 106,440 | 0.002 s |
| `fpga_smoke_test.bin` (512 KiB DDR4 test + UART RX line from host) | **FPGA SMOKE PASS** | 11,721,423 | 0.188 s |
| `crypto_soc_test.bin` (secp256k1 ECDSA verify + tamper reject) | **SOC CRYPTO PASS** | 27,701,149 | 0.443 s |
| `ed25519_soc_test.bin` (RFC 8032 TEST 1/2 + tamper/non-canonical reject) | **SOC CRYPTO PASS** | 28,618,172 | 0.458 s |
| OpenSBI v1.9 `fw_jump` + `s_hello` | **HELLO FROM S-MODE** | 11,462,064 | 0.183 s |
| OpenSBI v1.9 + **Linux 6.6** + initramfs | **userspace reached**: `init: userspace alive`, `uname` riscv64, `MUSERISC_LINUX_BOOT_OK` (pre-rename payload marker) | — | < 300 s |

Measured core clock (cycle counter / wall time): **62.500 MHz** on every run
(62.498 MHz on the first, shortest run).

Known issues found on hardware (not seen in XSIM):
- `STATUS.mem_err` is set early in every run without affecting results; the runs
  above used `--ignore-mem-err` (first attempts without it stop at the host's
  first status poll, ~16 ms: `*.host` / `*.uart` without `-ign`). Issue #62.
- The virtual UART dropped characters during bursty Linux console output. Issue #63.
- Pre-rename Linux payloads (marker, DTB, 10 MHz timebase; kernel time ran ~1.28×
  wall time). Issue #64.
- Caches-off runs (`*-nc`) also hit the `mem_err` stop before finishing.
