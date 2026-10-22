# SDK examples on a real AWS F2 FPGA (2026-10-22)

Public AFI `agfi-035116450e0a0d093` (62.5 MHz) on an `f2.6xlarge`, each
example built on the instance from `sw/examples/<name>` with Ubuntu's
`riscv64-unknown-elf-gcc` 13.2 through the `sigil-run` helper
(`sw/sdk/template` + `fpga/host/sigil_host --ignore-mem-err --bin`).

| Example | Result | Core cycles | Wall |
|---|---|---:|---:|
| hello | SIGIL TEST PASS | 53,215 | 0.001 s |
| timer_irq | SIGIL TEST PASS | 63,538 | 0.001 s |
| sha256_accel | SIGIL TEST PASS | 1,240,110 | 0.020 s |
| hash_stream | SIGIL TEST PASS | 242,677 | 0.004 s |
| ed25519_verify | SIGIL TEST PASS | 15,934,509 | 0.255 s |
| vector_dot | SIGIL TEST PASS | 822,421 | 0.013 s |
| fp_math | SIGIL TEST PASS | 50,364 | 0.001 s |

Measured core clock 62.5 MHz. Per-example host output and UART capture
in the `.log` files.
