# Programming the Sigil SoC

This guide covers writing bare-metal C programs for the Sigil SoC, running
them in the RTL simulator today, and running them on an AWS EC2 F2 FPGA
with the host runtime once the Sigil AFI is available. Programs use the
small SDK in `sw/sdk/`. The examples in `sw/examples/` are short,
commented templates. Each one checks its own results, so they also
serve as regression tests (`make -C sim examples`).

Everything below matches the code in this repository. Every cycle count
quoted here comes from running the examples on `soc_rtl_tb`, the
cycle-accurate Verilator model of the real SoC RTL.

## Contents

1. [What a program sees](#1-what-a-program-sees)
2. [Toolchain](#2-toolchain)
3. [Quick start](#3-quick-start)
4. [Memory map](#4-memory-map)
5. [SDK reference](#5-sdk-reference)
6. [Pass/fail convention](#6-passfail-convention)
7. [Running in simulation](#7-running-in-simulation)
8. [Running on AWS F2](#8-running-on-aws-f2)
9. [Crypto and hash accelerator](#9-crypto-and-hash-accelerator)
10. [Interrupts and the timer](#10-interrupts-and-the-timer)
11. [Vector code](#11-vector-code)
12. [Floating point](#12-floating-point)
13. [Performance counters](#13-performance-counters)
14. [Limits and gotchas](#14-limits-and-gotchas)
15. [Examples](#15-examples)

## 1. What a program sees

- **One hart, machine mode, no OS.** Your program is the only software
  running. It is linked at `0x8000_0000`. After reset, the boot ROM at
  `0x1000` jumps there. The core implements M/S/U modes and Sv39, but the
  SDK stays in M-mode with translation off.
- **ISA:** RV64GC (IMAFDC, Zicsr, Zifencei), B (Zba/Zbb/Zbs), Zbc, Zcb,
  Zicond, scalar crypto Zbkb/Zbkx/Zkne/Zknd/Zknh, and the vector
  extension RVV 1.0 with VLEN = 512 and ELEN = 64. `misa` reads
  `0x8000_0000_0034_11AF` (RV64 ABCDFHIMSUV). See `docs/CORE.md`.
- **Memory:** 128 MiB of RAM at `0x8000_0000`, the only cacheable
  region. The core has an 8 KiB L1 I$ and a 16 KiB write-back L1 D$.
  Devices (CLINT, PLIC, UART, crypto) are uncached, and each access is a
  single bus transaction.
- **Startup** (`sw/sdk/lib/crt0.S`): sets gp and sp, turns on the FPU and
  the vector unit (`mstatus.FS`/`VS` = Initial; both reset to Off, and FP
  or vector instructions trap while they are Off), installs the SDK trap
  vector, clears `.bss`, calls `main()`, and passes its return value to
  `sigil_exit()`.

## 2. Toolchain

You need a RISC-V bare-metal GCC and, to simulate, Verilator.

**macOS (Homebrew):**

```sh
brew install riscv64-elf-gcc verilator
```

This gives `riscv64-elf-gcc`. Homebrew's GCC 16.2 is the toolchain
every example was built and run with.

**Ubuntu / Debian:**

```sh
./scripts/install_deps.sh          # apt packages incl. gcc-riscv64-unknown-elf,
                                   # pinned Verilator in deps/, SoftFloat, riscv-tests
./scripts/install_deps.sh --gcc15  # optional: pinned GCC 15+ RISC-V toolchain (x86_64)
source deps/env.sh                 # every shell: puts deps/ tools first on PATH
```

`scripts/install_deps.sh` also supports macOS: it uses Homebrew and
installs the same packages as above.

The SDK finds `riscv64-unknown-elf-gcc` first and falls back to
`riscv64-elf-gcc`. Override the choice with `RISCV_PREFIX=...`.
Ubuntu 24.04's packaged `gcc-riscv64-unknown-elf` is GCC 13. It builds
the repository's assembly tests in CI, but the SDK examples have only
been built with GCC 16. The vector intrinsics (`vector_dot`) need GCC
13 or newer.

Compiler flags (`sw/sdk/sdk.mk`):

```text
-march=rv64gcv_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
-mabi=lp64d -mcmodel=medany -mstrict-align -O2
-ffreestanding -fno-math-errno -ffunction-sections -fdata-sections
-nostdlib -nostartfiles -T sw/sdk/link.ld -Wl,--gc-sections -lgcc
```

The flags do the following:

- `-mstrict-align`: misaligned accesses trap on this core.
- `-fno-math-errno`: lets `__builtin_sqrt` compile to `fsqrt.d`
  without a libm call.
- `-mcmodel=medany`: the image runs at `0x8000_0000`.

## 3. Quick start

Build and run an example on the RTL simulator. The first `make run`
also builds the simulator, `build/sim/soc_rtl_tb`, from the RTL.

```sh
make -C sw/examples/hello run
```

Output:

```text
Hello from Sigil!
misa = 0x80000000003411af: RV64ABCDFHIMSUV
loop of 1000 iterations: 2002 instructions, 8037 cycles
5000-cycle delay: mtime +5035, mcycle +5034, time CSR 34290
total: 44391 cycles, 11755 instructions retired
SIGIL TEST PASS hello
SOC RTL TB PASS (exit string at 55920 cycles)
```

To write your own program, copy the template:

```sh
cp -r sw/sdk/template sw/myprog
$EDITOR sw/myprog/main.c
make -C sw/myprog          # build/myprog.elf, .bin (flat image), .dis (disassembly)
make -C sw/myprog run      # run on soc_rtl_tb to its PASS/FAIL line
```

The template's `Makefile` uses the folder name as the program name. It
finds `sw/sdk` when the folder is in `sw/` or at the repository root.
From anywhere else, run `make SIGIL_SDK=/path/to/sigil/sw/sdk`. A
minimal Makefile:

```make
PROG      := myprog            # image and test name
SRCS      := myprog.c util.c   # optional; default: every *.c and *.S in the folder
SIGIL_SDK := ../sdk            # path to sw/sdk
include $(SIGIL_SDK)/sdk.mk
```

Variables you can set: `OUT` (build directory), `OPT` (default `-O2`),
`EXTRA_CFLAGS`, `STACK_SIZE` (bytes, default 64 KiB), `RISCV_PREFIX`,
`MAX_CYCLES` (default 200M for `make run`), and `SIM_ARGS` (extra
`soc_rtl_tb` arguments, e.g. `--no-cache`). The SDK is four source
files, compiled together with your program on every build, so it has
no separate library to keep up to date.

## 4. Memory map

The same map is used by the RTL SoC (`rtl/soc/sigil_soc_top.sv`),
`sw/linux/sigil.dts` and the FPGA build. Constants are in `sigil.h`.

| Address | Size | Device | SDK constant |
|---|---|---|---|
| `0x0000_1000` | 4 KiB | boot ROM (jumps to `0x8000_0000`) | `SIGIL_BOOTROM_BASE` |
| `0x0200_0000` | 64 KiB | CLINT: `msip` +0x0, `mtimecmp` +0x4000, `mtime` +0xBFF8 | `SIGIL_CLINT_*` |
| `0x0C00_0000` | 64 MiB | PLIC | `SIGIL_PLIC_BASE` |
| `0x1000_0000` | 256 B | 16550 UART (byte registers; THR/RBR +0, LSR +5) | `SIGIL_UART_*` |
| `0x2000_0000` | registers 0x00–0xA0 | crypto accelerator (`docs/SPEC.md` section 3, `sw/sigil_crypto.h`) | `SIGIL_CRYPTO_BASE`, `SIGIL_*` |
| `0x8000_0000` | 128 MiB | RAM (cacheable) | `SIGIL_RAM_BASE`, `SIGIL_RAM_SIZE` |

Image layout (`sw/sdk/link.ld`): `.text` (startup code first), then
`.rodata`, `.data`, `.bss`, and a 64 KiB stack. The flat `.bin` file
holds `.text` through `.data` and is loaded at `0x8000_0000`. `.bss`
and the stack take no space in the file. `sigil_alloc()` hands out the
RAM between the end of the stack (`_end`) and the end of RAM.

## 5. SDK reference

Include `sigil.h` and nothing else. It includes `sw/sigil_crypto.h`,
the accelerator register map. The SDK sources are:

| File | Contents |
|---|---|
| `sw/sdk/include/sigil.h` | the whole API (documented inline) |
| `sw/sdk/lib/crt0.S` | `_start`, trap vector `sigil_trap_entry` |
| `sw/sdk/lib/runtime.c` | UART, printf-lite, pass/fail, trap dispatch, delays, allocator, `memcpy`/`memset`/`memmove`/`memcmp`/`strlen`/`strcmp` |
| `sw/sdk/lib/accel.c` | SHA-256, streaming hash and field-unit drivers |
| `sw/sdk/lib/ed25519.c` | `sigil_ed25519_verify()` |
| `sw/sdk/link.ld`, `sw/sdk/sdk.mk` | link script, build rules |
| `sw/sdk/template/` | starting point for a new program |

**Console:**

| Function | Notes |
|---|---|
| `sigil_putc(c)`, `sigil_puts(s)` | blocking UART output; `'\n'` is sent as `"\r\n"` |
| `sigil_getc()` | next received byte or -1 (non-blocking) |
| `sigil_printf(fmt, ...)` | `%c %s %d %i %u %x %X %p %%`, `l`/`ll`/`z` modifiers, `0` and `-` flags, width. No floating point. |
| `sigil_print_fixed(x, decimals)` | prints a double in fixed-point notation |
| `sigil_print_hex(buf, n)` | prints bytes as lowercase hex |

**Pass/fail and halting:** `sigil_pass()`, `sigil_fail(why)`,
`sigil_exit(code)`, `SIGIL_CHECK(cond)`, `sigil_set_test_name(name)`,
`sigil_halt()`. See [section 6](#6-passfail-convention).

**CSRs, counters and barriers:** `sigil_csr_read(csr)`,
`sigil_csr_write/set/clear(csr, v)` (names such as `mstatus`, `mie`,
`frm`, `vlenb`), `sigil_rdcycle()`, `sigil_rdinstret()`,
`sigil_rdtime()`, `sigil_perf_now()` / `sigil_perf_since()`,
`sigil_delay_cycles(n)`, `sigil_fence()`, `sigil_fence_i()`,
`sigil_wfi()`.

**Timer and interrupts:** `sigil_mtime()`, `sigil_set_mtimecmp(t)`,
`sigil_timer_after(ticks)`, `sigil_timer_off()`,
`sigil_irq_enable(SIGIL_MIE_MTIE | ...)`, `sigil_irq_global_enable()`
/ `_disable()`, `sigil_set_irq_handler(fn)`,
`sigil_set_exc_handler(fn)`, `sigil_next_pc(pc)`. See
[section 10](#10-interrupts-and-the-timer).

**Memory:** `sigil_alloc(n, align)` is a bump allocator with no
free. The `SIGIL_REG8/32/64(addr)` macros give volatile MMIO access.

**Accelerator:** `sigil_sha256()`, `sigil_sha256_block()`,
`sigil_hash()`, `sigil_hash_init/update/final()`,
`sigil_fe_modsel()`, `sigil_fe_set_modulus()`,
`sigil_fe_add/sub/mul/pow()`, `sigil_ed25519_verify()`. See
[section 9](#9-crypto-and-hash-accelerator).

## 6. Pass/fail convention

Every SDK program ends with exactly one of these lines on the UART:

```text
SIGIL TEST PASS <name>
SIGIL TEST FAIL <name>: <reason>
```

`<name>` is `PROG` from the Makefile (or `sigil_set_test_name()`). The
following produce these lines:

- **Return from `main()`:** 0 prints PASS. Anything else prints
  `FAIL ...: exit code N`.
- **`sigil_pass()` / `sigil_fail(why)`:** call these from anywhere.
- **`SIGIL_CHECK(cond)`:** prints `check failed at file.c:LINE: cond`,
  then FAIL.
- **An unhandled exception:** prints
  `SIGIL TRAP mcause=0x2 (illegal instruction) mepc=0x... mtval=0x...`,
  then FAIL.
- **An interrupt with no handler installed:** prints FAIL.

The reason is also printed on a line of its own (`error: ...`) before
the FAIL line. The F2 host runtime stops reading at the marker, so
anything after it on the same line may not be shown. After the line,
the hart disables interrupts and sleeps in `wfi`.

The harnesses detect these markers:

| Harness | Pass | Fail |
|---|---|---|
| `soc_rtl_tb`, `fpga_top_tb` | `--exit-string "SIGIL TEST PASS <name>"`: exit 0 | `--fail-string "SIGIL TEST FAIL"`: exit 1 (after the rest of that line) |
| `sigil_host` (F2) | `SIGIL TEST PASS` is a default pass marker: exit 0 | its default fail marker `FAIL` matches `SIGIL TEST FAIL`: exit 1 |

Neither simulator harness recognizes a halted hart, so a program that
hangs instead of printing a marker ends at the cycle limit (exit 2,
`TIMEOUT`). Don't print `FAIL` in normal output: `sigil_host`'s
default fail marker is any occurrence of `FAIL`.

## 7. Running in simulation

### soc_rtl_tb (RTL SoC)

`build/sim/soc_rtl_tb` is the Verilated `sigil_soc_top`. Core, caches,
fabric, boot ROM, CLINT, PLIC, UART and crypto are all RTL. The
harness provides only the RAM behind the SoC's memory port and captures
the UART. Build it with `make -C sim ../build/sim/soc_rtl_tb` (the
SDK's `make run` does this for you).

```sh
build/sim/soc_rtl_tb [max_cycles] --load 0x80000000=build/myprog.bin \
    --exit-string "SIGIL TEST PASS myprog" --fail-string "SIGIL TEST FAIL" \
    [--uart-log FILE] [--uart-in FILE] [--trace-traps] [--no-cache] \
    [--mem-lat A:B] [--mem-gap N] [--mem-ready PCT] [--mem-seed S] [--boot 0xADDR]
```

| Option | Meaning |
|---|---|
| `max_cycles` | cycle limit (default 100M), then `SOC RTL TB TIMEOUT`, exit 2 |
| `--load ADDR=FILE` | copy a flat binary into RAM (repeatable) |
| `--exit-string` / `--fail-string` | UART text that ends the run: exit 0 / 1 |
| `--uart-in FILE` | bytes fed to the UART receiver (read with `sigil_getc()`) |
| `--uart-log FILE` | also write the UART output to a file |
| `--trace-traps` | log every trap the core takes (cycle, mcause, PC) to stderr, interrupts included |
| `--no-cache` | L1 caches off; every access goes to the bus |
| `--mem-lat 1:6 --mem-gap 2 --mem-ready 70` | random RAM latency, gaps and backpressure (what `make -C sim examples` uses) |
| `--boot 0xADDR` | reset PC (default `0x1000`, the boot ROM, which jumps to `0x8000_0000`) |

UART output goes to stdout as it arrives. The harness prints its own
status lines to stderr. On an Apple-silicon laptop, the simulator runs
about 0.5 million SoC cycles per second, so a 15M-cycle program
(`ed25519_verify`) takes about 25 s.

### fpga_top_tb (FPGA top)

`build/sim/fpga_top_tb` simulates `rtl/fpga/sigil_fpga_top.sv`, the
wrapper the F2 build uses. The SoC sits behind an AXI4 DDR bridge, and
the UART is a FIFO that the host drains. It takes the same `--load`,
`--exit-string` and `--fail-string` arguments, plus DDR-like AXI
timing (`--axi-lat 8:40 --axi-gap 2 --axi-ready 70`). If your program
passes here, the same `.bin` should behave the same on F2, apart from
the real DDR timing and clock.

### Regression targets

| Target | What it runs | Wall time (M-series Mac) |
|---|---|---|
| `make -C sim examples` | every example on `soc_rtl_tb`, random memory latency, 60M-cycle limit each; fails on any FAIL, trap or timeout | ~28 s sequential |
| `make -C sim fpgatop-examples` | every example on `fpga_top_tb` (DDR-like AXI timing) | ~22 s with `-j4` |
| `make core-test` | includes `examples` and `fpgatop-example-hello` / `-timer_irq` | adds ~30 s to a ~34 min suite |

Logs are written to `build/examples/<name>.log`. Add a new example by
creating `sw/examples/<name>/{<name>.c,Makefile}` and adding the name
to `EXAMPLES` in `sim/Makefile`.

## 8. Running on AWS F2

The F2 build (`docs/FPGA_F2.md`) wraps the same SoC. The 128 MiB RAM
window maps to FPGA DDR4. The UART is a virtual UART, which the host
reads and writes through the OCL register BAR. The core clock is
interim: **62.5 MHz** (`AWS_CLK_GEN` recipe B1) until timing closes at
100 MHz.

The host runtime is `fpga/host/sigil_host.c`. Build it on the F2
instance against the aws-fpga SDK (setup steps in
[`FPGA_F2.md`](FPGA_F2.md#flash-sigil-on-your-own-f2)):

```sh
make -C fpga/host SDK_DIR=<aws-fpga>/sdk
```

To run an SDK program:

```sh
sudo fpga/host/sigil_host --afi agfi-035116450e0a0d093 --ignore-mem-err \
    --bin build/myprog.bin --timeout 30
```

What `sigil_host` does:

1. Loads the AFI (`--afi`). Leave it out if the AFI is already loaded.
2. Sets the clock recipe.
3. Holds the SoC in reset.
4. Copies the `.bin` to DDR at SoC address `0x8000_0000`
   (`--bin F` = `--load 0x80000000=F`; load addresses must be 64-byte
   aligned).
5. Releases reset. The boot ROM jumps to `0x8000_0000`.
6. Streams the UART to stdout until a pass marker (exit 0), a fail
   marker (exit 1), or `--timeout` seconds (default 60; exit 2).
7. Prints the measured core clock and the trap counters.

Other useful options:

| Option | Effect |
|---|---|
| `--stdin` | forwards your terminal to the UART receiver (`sigil_getc()`) |
| `--log F` | also writes the UART stream to a file |
| `--no-cache` | runs with the L1 caches off |
| `--keep-running` | leaves the SoC running when the tool exits |
| `-q` | prints only the UART output |
| `--ignore-mem-err` | required with the current public AFI: it sets a spurious sticky AXI error flag early in every run without affecting results ([#62](https://github.com/bubblebabyboi/sigil/issues/62)) |

`sigil_host` recognises `SIGIL TEST PASS` (and the older `SOC CRYPTO
PASS`, ... markers) by default, and its default fail marker `FAIL`
matches `SIGIL TEST FAIL`; `--exit` / `--fail` override them.

Status: the public AFI `agfi-035116450e0a0d093` ran the existing
firmware, OpenSBI and Linux 6.6 to userspace on a real `f2.6xlarge` at a
measured 62.5 MHz (2026-10-22, `docs/evidence/f2-first-boot-55-2026-10-22/`).
The SDK examples have passed on `fpga_top_tb`, the closest
simulation of the F2 top. At 62.5 MHz, 1M cycles take 16 ms. The
slowest example (`ed25519_verify`, ~15M cycles) would take about
0.25 s.

## 9. Crypto and hash accelerator

The accelerator at `0x2000_0000` has three engines. Register-level
details are in `docs/SPEC.md` section 3. Phase 0 is a functional
accelerator, **not** side-channel hardened, and the SDK code is
variable-time. Do not use it with private keys.

**SHA-256** (`sigil_sha256(msg, len, digest)`): the engine compresses
**one 512-bit block from the IV per start, with no chaining**. The
driver pads in software, so a message can be at most 55 bytes
(`SIGIL_SHA256_MAX_LEN`). For a longer message the driver returns -1.
Hash longer messages in software (`sw/examples/sha256_accel` has a
compact C version, plus a Zknh version), or use SHA-512 / SHA3 on the
streaming engine. Measured on a 55-byte message: accelerator 3,688
cycles (most of it MMIO register traffic and byte packing), plain C
16,271 cycles, C with Zknh instructions 12,484 cycles.

**Streaming hash** (SHA-512, SHA3-256, Keccak-256, SHAKE256): accepts
messages of any length, and the hardware does the padding.

```c
uint8_t d[64];
sigil_hash(SIGIL_HASH_SHA512, msg, len, d, 64);   /* one shot */

sigil_hash_init(SIGIL_HASH_SHA3_256);              /* or in pieces */
sigil_hash_update(part1, n1);
sigil_hash_update(part2, n2);                      /* any sizes */
sigil_hash_final(d, 32);
```

Output lengths: SHA-512 gives 64 bytes, SHA3-256 and Keccak-256 give
32, and SHAKE256 gives any length (the driver squeezes for you). The
engine is a single instance, so hash one message at a time. Throughput
for a 1,000-byte message: SHA-512 7.3 cycles/byte, SHA3-256 5.8
cycles/byte (`hash_stream`). Message stores never need status polling:
the bus stalls a store while the engine's buffer is full.

**Field unit** (256-bit add, sub and mul mod p):

```c
sigil_fe_modsel(SIGIL_MOD_CURVE25519);   /* or SIGIL_MOD_SECP256K1 */
sigil_fe_t a, b, r;                      /* 4 little-endian 64-bit limbs */
sigil_fe_mul(&a, &b, &r);
sigil_fe_set_modulus(&n);                /* any odd modulus, e.g. a group order */
sigil_fe_pow(&a, &e, &r);
```

**Ed25519 verify** (`sigil_ed25519_verify(pub, msg, len, sig)`): RFC
8032 verify. The field ops run on the field unit and SHA-512(R‖A‖M)
runs on the streaming engine. It returns `SIGIL_ED25519_OK` or a
reason (`_BAD_KEY`, `_BAD_S`, `_MISMATCH`). One verify takes about 7.4M
cycles (`ed25519_verify`). secp256k1 ECDSA verify over the same field
unit is in `sw/soc-tests/crypto_soc_test.c`; it is not in the SDK yet.

## 10. Interrupts and the timer

The CLINT's `mtime` counts **one tick per core clock**. In simulation
it matches `mcycle`, and on F2 it runs at 62.5 MHz. The `time` CSR
reads the same counter. The machine timer interrupt is pending while
`mtime >= mtimecmp`. `mtimecmp` resets to 0, so it is pending from
reset; enabling `MTIE` without first setting `mtimecmp` interrupts
immediately.

```c
static void on_irq(uint64_t irq) {          /* mcause without bit 63 */
  if (irq == SIGIL_IRQ_M_TIMER) sigil_timer_after(1000);   /* re-arm = clear */
}

sigil_set_irq_handler(on_irq);
sigil_timer_after(1000);
sigil_irq_enable(SIGIL_MIE_MTIE);
sigil_irq_global_enable();
while (!done) sigil_wfi();
```

How the trap vector behaves:

- It saves every integer register, the caller-saved FP registers and
  `fcsr`, so handlers are plain C functions.
- It does **not** save vector state. Do not use vector instructions in
  a handler, and that includes loops GCC may auto-vectorize. Mark the
  handler `__attribute__((optimize("no-tree-vectorize")))` if in doubt.
- A handler must clear its source before it returns: move `mtimecmp`,
  write 0 to `msip`, or claim/complete at the PLIC.
- Interrupts are taken only between instructions. A long vector
  instruction delays them by at most its own length (up to ~5k cycles,
  `docs/CORE.md`).

Measured in `timer_irq`: from the deadline to the handler's first
instruction takes about 200 cycles, mostly the register save. For
software interrupts, write 1 to `SIGIL_CLINT_MSIP` and enable
`SIGIL_MIE_MSIE`.

Exceptions call `sigil_set_exc_handler(fn)` if one is set. Return the
PC to resume at: `sigil_next_pc(mepc)` skips the faulting instruction,
which may be 2 or 4 bytes because of the C extension. Return 0 to fall
back to the default, which prints `SIGIL TRAP ...` and fails. The
external interrupt (PLIC, `SIGIL_MIE_MEIE`) is wired, but the SDK has
no PLIC helpers yet. The register layout is the standard RISC-V PLIC
at `0x0C00_0000`.

## 11. Vector code

The startup code enables the vector unit, and the SDK's `-march`
includes `v`. You can write vector code in three ways:

- **Intrinsics** (`#include <riscv_vector.h>`): the recommended way;
  see `sw/examples/vector_dot`.
- **Inline assembly.**
- **GCC auto-vectorization:** on by default at `-O2` with this
  `-march`. Add `-fno-tree-vectorize` to `EXTRA_CFLAGS` to turn it off.

Write strip-mined loops with `vsetvl`. They don't depend on VLEN, but
on this core VLEN is 512 bits: `vlenb` = 64, and an `e32,m1` register
holds 16 elements.

The vector unit is **element-serial**. It processes one element per
cycle for simple ops, more for multiplies, divides and FP, and two
cycles per element for vector loads and stores (`docs/CORE.md`,
"Vector unit"). Vector code is correct and needs far fewer
instructions, but it is not dramatically faster yet. Measured in
`vector_dot`:

| Work | Vector | Scalar |
|---|---|---|
| int32 dot product, n = 1000 (`vwmacc` into 64-bit lanes) | 12,692 cycles, 145 instructions | 19,036 cycles, 7,012 instructions |
| copy 4096 bytes | 24,816 cycles (`vle8`/`vse8`) | 7,262 cycles (SDK `memcpy`, 8 bytes per `ld`/`sd`) |

## 12. Floating point

F and D are enabled at startup, and the ABI is `lp64d`. The FPU
implements IEEE 754 with all rounding modes, verified with the ACT F/D
suites (`docs/CORE.md`). Latencies: `fadd`/`fmul`
5 cycles, `fmadd` 7, `fdiv.d`/`fsqrt.d` 32. There is no libm. Use
`__builtin_sqrt`, `__builtin_fma` and `__builtin_fabs`, which compile
to single instructions. Write anything else (exp, sin, ...) yourself;
`fp_math` computes e from its series.

GCC does not treat `frm` or `fflags` as inputs or outputs of FP
instructions. It may move an FP operation across a `csrw frm` or a
`csrr fflags`. When rounding mode or flags matter, do the operation in
`asm volatile`, as `fp_math` does with `fdiv_ordered()`.

## 13. Performance counters

`sigil_rdcycle()` and `sigil_rdinstret()` read the 64-bit `mcycle` and
`minstret` counters, which count from reset. Measure a region like
this:

```c
sigil_perf_t p = sigil_perf_now();
work();
sigil_perf_t t = sigil_perf_since(p);   /* t.cycles, t.instret */
```

Reading `instret` doesn't count the reading instruction itself. In
`hello`, a 2-instruction loop of N iterations between two reads gives
exactly 2N + 2. Today's pipeline is in-order and single-issue with
blocking caches. A cache hit costs 2 cycles, and a taken branch flushes
2 slots, so a tight loop runs at about 4 cycles per instruction.

## 14. Limits and gotchas

- **No OS services.** The SDK provides only what is in `sigil.h`: no
  libc beyond `mem*`/`strlen`/`strcmp`, no `malloc`/`free` (use
  `sigil_alloc`), no files, no libm, no C++ runtime (constructors are
  not run).
- **Memory:** 128 MiB of RAM, 64 KiB of stack by default
  (`STACK_SIZE=`). Nothing detects a stack overflow: it silently
  overwrites `.bss`. Large buffers belong in static storage or
  `sigil_alloc`, not on the stack.
- **Misaligned loads and stores trap** (cause 4 or 6). The SDK builds
  with `-mstrict-align`. Pointer casts (`*(uint32_t *)p` on a byte
  buffer) are still your responsibility.
- **Self-modifying or loaded code:** the D$ is write-back and the I$
  doesn't snoop. After writing instructions, run `sigil_fence_i()`
  before executing them. The fence writes back the whole D$ (256+
  cycles) and invalidates the I$.
- **Devices are uncached and slow next to the core:** each MMIO access
  is a single bus round trip (one 32-bit register per access on the
  accelerator). The SHA-256 driver spends far more time on register
  traffic than in the hash core.
- **DMA:** the accelerator has no DMA. Data moves through MMIO stores,
  so cache coherence is never an issue.
- **Clock on F2:** the interim F2 core clock is **62.5 MHz**, with
  `mtime` at the same rate. Divide cycle counts by 62.5e6 for seconds.
  Cycle counts on F2 will differ a little from simulation, because DDR
  latency is real (~8–40 bus cycles per line fill in `fpga_top_tb`).
- **One hart, M-mode only** in the SDK. Supervisor and user mode, Sv39
  and the hypervisor extension exist in the core, but using them means
  writing your own trap and page-table setup (as OpenSBI and Linux do;
  see `docs/CORE.md`).
- **Timeouts:** the simulators stop at the cycle limit (default 100M
  for `soc_rtl_tb`, 200M with `make run`) and `sigil_host` at
  `--timeout` seconds. Raise them for long programs.

## 15. Examples

All examples are in `sw/examples/<name>/<name>.c`. Each checks known
answers or compares two independent computations, and ends with
`SIGIL TEST PASS <name>`. Cycle counts are from `make -C sim examples`
(`soc_rtl_tb`, random memory latency). The last column is the cycle at
which PASS was printed, including startup and UART output.

| Example | What it shows and checks | Key numbers | Total cycles |
|---|---|---|---|
| [`hello`](../sw/examples/hello/hello.c) | UART, `misa` (RV64 IMAFDC+V present), exact `instret` of a known loop (2N+2), cycles ≥ instructions, `mtime` tracks `mcycle` | 1000-iteration loop: 2,002 instructions, 8,037 cycles | 56k |
| [`timer_irq`](../sw/examples/timer_irq/timer_irq.c) | CLINT timer: pending but not taken while masked, exactly 10 periodic interrupts while sleeping in `wfi`, none after `sigil_timer_off()`, one `msip` software interrupt | latency ~206 cycles, 10 ticks in 18,312 cycles (9 × 2000 period) | 51k |
| [`sha256_accel`](../sw/examples/sha256_accel/sha256_accel.c) | SHA-256: FIPS vectors in software (C and Zknh), accelerator == known answers, accelerator == software for every length 0..55, 4-block software vs hashlib, 56 bytes rejected | 55 B: accel 3,688 / C 16,271 / Zknh 12,484 cycles | 1.4M |
| [`hash_stream`](../sw/examples/hash_stream/hash_stream.c) | streaming engine: SHA-512 at 9 lengths around the block size, SHA3-256 at 7 lengths around the rate (vs hashlib), FIPS "abc", piecewise == one-shot, SHAKE256 300-byte output | 1000 B: SHA-512 7.3 cycles/B, SHA3-256 5.8 cycles/B | 277k |
| [`ed25519_verify`](../sw/examples/ed25519_verify/ed25519_verify.c) | `sigil_ed25519_verify()` on RFC 8032 TEST 2: accept; changed message rejected; S ≥ L rejected | 7.4M cycles per verify | 14.9M |
| [`vector_dot`](../sw/examples/vector_dot/vector_dot.c) | RVV intrinsics: VLEN = 512, int32 dot product == scalar for lengths 0..100 and 1000, vector byte copy at unaligned offsets with guard bytes intact | see [section 11](#11-vector-code) | 811k |
| [`fp_math`](../sw/examples/fp_math/fp_math.c) | correctly rounded `fsqrt.d`/`fsqrt.s`, Newton sqrt(2) within 1 ulp in ≤ 6 steps (takes 5), e from its series within 2 ulp, exact dot product, `fmadd` rounds once, `frm` round-up and the NX flag, conversions | 100-element dot: ~2.5k cycles | 47k |

The starting point for your own code is `sw/sdk/template/`. For lower-level
references, see `sw/soc-tests/` (secp256k1 ECDSA, Ed25519 with
software SHA-512) and `sw/hash-tests/hash_soc_test.c` (raw register
programming of the streaming hash engine).
