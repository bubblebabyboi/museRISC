# Programming the Sigil SoC

This guide covers writing bare-metal C programs for the Sigil SoC, running
them in the RTL simulator, and running them on an AWS EC2 F2 FPGA with
the host runtime and Sigil's public AFI. Programs use the
small SDK in `sw/sdk/`. The examples in `sw/examples/` are short,
commented templates. Each one checks its own results, so they also
serve as regression tests (`make -C sim examples`).

Everything below matches the code in this repository. Every cycle count
quoted here comes from running the examples on `soc_rtl_tb`, the
cycle-accurate Verilator model of the real SoC RTL, unless a number is
marked as measured on the F2. For Linux (Debian with gcc and glibc) on
the same hardware, see [`LINUX.md`](LINUX.md).

## Contents

1. [What a program sees](#1-what-a-program-sees)
2. [Toolchain](#2-toolchain)
3. [Quick start](#3-quick-start)
4. [Memory map](#4-memory-map)
5. [SDK reference](#5-sdk-reference)
6. [Pass/fail convention](#6-passfail-convention)
7. [Running in simulation](#7-running-in-simulation)
8. [Running on AWS F2](#8-running-on-aws-f2) — [the F2 memory map: 64 GiB DDR4 and 16 GiB HBM](#81-the-f2-memory-map-64-gib-ddr4-and-16-gib-hbm)
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
- **Memory:** RAM from `0x8000_0000`, the only cacheable region: 128
  MiB in the simulators and in the SDK's link script; on the F2, 64 GiB
  of DDR4 and 16 GiB of HBM ([section 8.1](#81-the-f2-memory-map-64-gib-ddr4-and-16-gib-hbm)).
  The core has an 8 KiB L1 I$ and a 16 KiB write-back L1 D$.
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
| `0x0010_0000` | 4 KiB | test finisher (32-bit write: `0x5555` power off, `0x7777` reboot, `(code << 16) \| 0x3333` fail); on the F2 `sigil_host` ends the run on power off (exit 0) or fail (exit 1); a reboot reloads the boot images and restarts (`--on-reboot rerun`, the default) or exits 5 (`--on-reboot exit`) | — |
| `0x0010_1000` | 4 KiB | RTC (`google,goldfish-rtc` registers; set to the host's wall clock by `sigil_host`) | — |
| `0x0200_0000` | 64 KiB | CLINT: `msip` +0x0, `mtimecmp` +0x4000, `mtime` +0xBFF8 | `SIGIL_CLINT_*` |
| `0x0C00_0000` | 64 MiB | PLIC | `SIGIL_PLIC_BASE` |
| `0x1000_0000` | 256 B | 16550 UART (byte registers; THR/RBR +0, LSR +5) | `SIGIL_UART_*` |
| `0x2000_0000` | registers 0x00–0xA0 | crypto accelerator (`docs/SPEC.md` section 3, `sw/sigil_crypto.h`) | `SIGIL_CRYPTO_BASE`, `SIGIL_*` |
| `0x8000_0000` | 128 MiB (simulators, SDK); F2: 80 GiB, [section 8.1](#81-the-f2-memory-map-64-gib-ddr4-and-16-gib-hbm) | RAM (cacheable) | `SIGIL_RAM_BASE`, `SIGIL_RAM_SIZE` |

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
| `make -C sim fpgatop-f2-examples` | the F2-map examples (`hbm_touch`) on `fpga_top_tb_f2` (the F2's 80 GiB window over a sparse memory model) | 19 s run on the Linux build instance |
| `make core-test` | includes `examples`, `fpgatop-example-hello` / `-timer_irq` and `fpgatop-f2-examples` | adds ~30 s, plus the `hbm_touch` run, to a ~34 min suite |

Logs are written to `build/examples/<name>.log`. Add a new example by
creating `sw/examples/<name>/{<name>.c,Makefile}` and adding the name
to `EXAMPLES` in `sim/Makefile` (or to `F2_EXAMPLES` if it needs the F2
memory map). `make -C sim examples-bins` builds all of them without
running them.

## 8. Running on AWS F2

The F2 build (`docs/FPGA_F2.md`) wraps the same SoC. Its RAM window is
80 GiB: all 64 GiB of the FPGA's DDR4 and its 16 GiB of HBM
([section 8.1](#81-the-f2-memory-map-64-gib-ddr4-and-16-gib-hbm)). The
UART is a virtual UART, which the host reads and writes through the OCL
register BAR. The core clock is interim: **62.5 MHz** (`AWS_CLK_GEN`
recipe B1) until timing closes at 100 MHz. The public AFI is
**`agfi-0c8aa56fde1a48495`** (it supersedes `agfi-0a1fd54ef68bdc754`,
whose core has the MMU walker race,
[#74](https://github.com/bubblebabyboi/sigil/issues/74)).

The quickest start is the playground setup on a new `f2.6xlarge`
(FPGA Developer AMI), which installs the SDK, a RISC-V GCC and
`sigil_host`, loads the AFI and adds `sigil-run`:

```sh
curl -fsSL https://raw.githubusercontent.com/bubblebabyboi/sigil/main/fpga/scripts/f2_playground_setup.sh | bash
~/bin/sigil-run ~/hello/hello.c   # build with the SDK template, run on the FPGA
~/bin/sigil-run prog.bin          # or run an image you built
```

The host runtime is `fpga/host/sigil_host.c`. Build it on the F2
instance against the aws-fpga SDK (setup steps in
[`FPGA_F2.md`](FPGA_F2.md#flash-sigil-on-your-own-f2)):

```sh
make -C fpga/host SDK_DIR=<aws-fpga>/sdk
```

To run an SDK program:

```sh
sudo fpga-load-local-image -S 0 -I agfi-0c8aa56fde1a48495 -H     # if the slot does not have it (fpga-describe-local-image -S 0 -H)
sudo fpga/host/sigil_host --bin build/myprog.bin --timeout 30
```

What `sigil_host` does:

1. Loads the AFI if you pass `--afi agfi-...`. Leave it out when the AFI
   is already loaded: every load resets the FPGA, and the next run zeroes
   DDR4 again (step 4).
2. Releases the CL resets with the AFI's build clock recipe (B1 =
   62.5 MHz); `--recipe-b N` programs another recipe instead.
3. Holds the SoC in reset and waits for DDR4 and HBM.
4. Zeroes all 64 GiB of DDR4 once per AFI load (about 17 s). DDR4 has
   ECC, and reading memory that was never written is an error
   ([#62](https://github.com/bubblebabyboi/sigil/issues/62)).
5. Copies the `.bin` to DDR4 at SoC address `0x8000_0000`
   (`--bin F` = `--load 0x80000000=F`; load addresses must be 64-byte
   aligned).
6. Sets the RTC to the host's wall clock and releases reset. The boot
   ROM jumps to `0x8000_0000`.
7. Streams the UART to stdout until a pass marker (exit 0), a fail
   marker (exit 1), a test-finisher write (power off: exit 0, fail code:
   exit 1), a memory error (exit 1) or `--timeout` seconds (default 60;
   exit 2).
8. Prints the measured core clock, the trap counters and any memory
   error it captured.

Other useful options:

| Option | Effect |
|---|---|
| `--stdin` | forwards your terminal to the UART receiver (`sigil_getc()`) |
| `--console` | interactive raw terminal (no markers, no timeout); Ctrl-] detaches |
| `--load 0xADDR=F` | an extra image anywhere in DDR4 or HBM, e.g. input data |
| `--save 0xADDR=F:SIZE` | after the run, writes SIZE bytes (K/M/G) of memory to a file |
| `--log F` | also writes the UART stream to a file |
| `--no-cache` | runs with the L1 caches off |
| `--keep-running` | leaves the SoC running when the tool exits |
| `--memtest all` | full-range DDR4 + HBM test with the FPGA's memory engine |
| `-q` | prints only the UART output |

`--ignore-mem-err` is no longer needed with this AFI (#62 is fixed by
the DDR4 zeroing); it only matters for the first public AFI,
`agfi-035116450e0a0d093` (#55, 128 MiB, no HBM), which still works with
the current `sigil_host`; its core also has the walker race (#74), so
use it for bare-metal programs only.

`sigil_host` recognises `SIGIL TEST PASS` (and the older `SOC CRYPTO
PASS`, ... markers) by default, and its default fail marker `FAIL`
matches `SIGIL TEST FAIL`; `--exit` / `--fail` override them.

Status: on a real `f2.6xlarge` at a measured 62.5 MHz, the platform AFI
`agfi-0a1fd54ef68bdc754` ran the firmware tests and all 7 SDK examples
without `--ignore-mem-err`, and full-range memory tests of DDR4 and HBM
(2026-10-22, [`evidence/f2-platform-73-2026-10-22/`](evidence/f2-platform-73-2026-10-22/SUMMARY.md)).
The current AFI `agfi-0c8aa56fde1a48495` is the same CL with the core's
walker-race fix and atomic A/D update (#74); on it Debian passed 22/22 checks
([`evidence/linux-debian-73-2026-10-22/f2-boot-fixed/`](evidence/linux-debian-73-2026-10-22/f2-boot-fixed/));
the first AFI ran the 7 examples too
([`evidence/f2-sdk-examples-2026-10-22/`](evidence/f2-sdk-examples-2026-10-22/SUMMARY.md):
`ed25519_verify`, the slowest at 15.9M cycles, took 0.255 s). At 62.5
MHz, 1M cycles take 16 ms.

### 8.1 The F2 memory map: 64 GiB DDR4 and 16 GiB HBM

On the F2 the SoC's RAM is all of the FPGA's memory
([`LINUX_PLATFORM.md`](LINUX_PLATFORM.md)):

| SoC physical address | Size | Memory | Notes |
|---|---|---|---|
| `0x0_8000_0000` – `0x10_7FFF_FFFF` | 64 GiB | DDR4 | ECC; zeroed by `sigil_host` once per AFI load |
| `0x10_8000_0000` – `0x14_7FFF_FFFF` | 16 GiB | HBM | no ECC; **not** zeroed (`--scrub-hbm` does it): write before you read |
| above `0x14_8000_0000` | — | none | reads return 0, writes are dropped, and `sigil_host` stops with a memory error |

Both are ordinary cacheable memory: a pointer is all it takes. The SDK
uses only the first 128 MiB (`SIGIL_RAM_SIZE`, `sw/sdk/link.ld`,
`sigil_alloc()`), the window every simulator has, so the rest of DDR4
and all of HBM are yours to manage. The example
[`hbm_touch`](../sw/examples/hbm_touch/hbm_touch.c) does it with a
bump allocator over HBM:

```c
#define F2_HBM_BASE 0x1080000000UL
#define F2_HBM_SIZE 0x0400000000UL /* 16 GiB */

static uintptr_t hbm_next = F2_HBM_BASE;
static void *hbm_alloc(size_t n, size_t align) {    /* no free */
  uintptr_t p = (hbm_next + align - 1) & ~(uintptr_t)(align - 1);
  if (p + n > F2_HBM_BASE + F2_HBM_SIZE) return NULL;
  hbm_next = p + n;
  return (void *)p;
}

int main(void) {
  uint64_t *buf = hbm_alloc(256 * 1024, 64);                  /* 256 KiB in HBM */
  uint64_t *big = (uint64_t *)(0x80000000UL + (32UL << 30));  /* DDR4 + 32 GiB */
  /* ... */
}
```

`hbm_touch` writes and reads back 256 KiB (16 × the D$, so the reads
come from memory) at the start of HBM, at its last 256 KiB and in DDR4
at +32 GiB, checks the first buffer again (no aliasing) and prints the
cycles per 64-byte line of each pass. It passes on `fpga_top_tb_f2`
(`make -C sim fpgatop-f2-examples`; 5.37M cycles with simulated AXI
timing, which says nothing about F2 latency; built with GCC 16.1 and
with Ubuntu's GCC 13.2, which `sigil-run` uses;
[`evidence/linux-user-docs-73-2026-10-22/`](evidence/linux-user-docs-73-2026-10-22/hbm_touch-gcc16.fpgatop-f2.log)). It needs the F2 map, so
it does not run on `soc_rtl_tb` or `fpga_top_tb` (128 MiB). On the F2:
`~/bin/sigil-run ~/sigil/sw/examples/hbm_touch/hbm_touch.c` (not yet
run on the F2 itself). The same kinds of accesses from the core
(`sw/fpga-tests/f2_memtest.c`, a sparse test over all of DDR4 and HBM)
passed on the F2 with 0 errors.

Things to know:

- **Latency** (measured on the F2, cold 64-byte refill from the core):
  DDR4 45.6 cycles = 729 ns, HBM 50.8 cycles = 813 ns; L1 hit about 9
  cycles including the `rdcycle`. The core has one memory request in
  flight, so a sequential read runs at 77 MB/s (DDR4) and 70 MB/s
  (HBM): HBM gives this core more memory, not more speed.
- **Big inputs and outputs:** put data into memory before the run and
  read results back after it, at PCIe speed (3.6 GB/s load, about
  1 GB/s save):
  `sudo fpga/host/sigil_host --bin prog.bin --load 0x1080000000=input.bin --save 0x1100000000=out.bin:64M`.
- **The D$ is write-back** and the host's view of memory does not see
  dirty lines: data the program wrote reaches DDR4/HBM when the line is
  evicted or after `sigil_fence_i()` (which writes back the whole D$).
  Call it before the program ends if the host will `--save` that data.
- Between AFI loads, DDR4 keeps what earlier runs wrote (it is zeroed
  only once per load); HBM is zeroed only with `--scrub-hbm`.

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

For a benchmark, use `sigil_perf_begin()` / `sigil_perf_end()` instead.
They read the same counters, print
`SIGIL PERF region=0 cycles=<n> instret=<n>`, and also mark the region
for the simulation-only event counters. The markers are writes to
`mhpmevent31`, which the core ignores. In simulation those counters
break every cycle of the region down by cause (fetch, branches, D$,
multi-cycle units, ...). The performance harness (`make -C sim perf`,
benchmarks in `sw/bench/`) runs and validates such programs; see
[`docs/PERFORMANCE.md`](PERFORMANCE.md).

## 14. Limits and gotchas

- **No OS services.** The SDK provides only what is in `sigil.h`: no
  libc beyond `mem*`/`strlen`/`strcmp`, no `malloc`/`free` (use
  `sigil_alloc`), no files, no libm, no C++ runtime (constructors are
  not run).
- **Memory:** 128 MiB of RAM in the SDK (on the F2, the rest of DDR4
  and the HBM are there too: [section 8.1](#81-the-f2-memory-map-64-gib-ddr4-and-16-gib-hbm)),
  64 KiB of stack by default (`STACK_SIZE=`). Nothing detects a stack overflow: it silently
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
  The 100 MHz AFI of #53 ([`FPGA_F2.md`](FPGA_F2.md#100-mhz-core-clock-53-afi-built-not-yet-run-on-an-f2))
  runs the core and `mtime` at 100 MHz; `sigil_host` prints the core
  clock of the loaded AFI on every run.
  Cycle counts on F2 differ from simulation, because DDR latency is
  real: a line fill takes ~8–40 bus cycles in `fpga_top_tb`, but about
  46 core cycles from DDR4 and 51 from HBM on the F2.
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
| [`hbm_touch`](../sw/examples/hbm_touch/hbm_touch.c) | **F2 memory map only** ([section 8.1](#81-the-f2-memory-map-64-gib-ddr4-and-16-gib-hbm)): a bump allocator over HBM, 256 KiB written and read back at the start and end of HBM and in DDR4 at +32 GiB, no aliasing | `fpga_top_tb_f2`: ~190 cycles per line written, 180 read (simulated AXI timing, not F2 latency) | 5.37M (`fpga_top_tb_f2`, GCC 16.1; 6.15M with Ubuntu's GCC 13.2) |
| [`fp_math`](../sw/examples/fp_math/fp_math.c) | correctly rounded `fsqrt.d`/`fsqrt.s`, Newton sqrt(2) within 1 ulp in ≤ 6 steps (takes 5), e from its series within 2 ulp, exact dot product, `fmadd` rounds once, `frm` round-up and the NX flag, conversions | 100-element dot: ~2.5k cycles | 47k |

The starting point for your own code is `sw/sdk/template/`. For lower-level
references, see `sw/soc-tests/` (secp256k1 ECDSA, Ed25519 with
software SHA-512) and `sw/hash-tests/hash_soc_test.c` (raw register
programming of the streaming hash engine).
