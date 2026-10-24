// Sigil F2 host runtime (issues #54, #62-#67). Runs on an AWS EC2 F2
// instance against the aws-fpga SDK (fpga_mgmt / fpga_pci /
// fpga_clkgen), with the Sigil AFI (fpga/cl_sigil) loaded or loadable.
//
//   sigil_host [options] --linux --fw fw_jump.bin --image Image --dtb sigil.dtb
//   sigil_host [options] --bin firmware.bin          (baremetal at 0x8000_0000)
//   sigil_host [options] --load 0xADDR=FILE ...      (any layout)
//   sigil_host [options] --memtest all               (memory engine only)
//   sigil_host [-S N] --info                         (AFI, core clock, memory)
//
// Memory map (docs/LINUX_PLATFORM.md): SoC PA 0x8000_0000 + x = DDR4
// (x < 64 GiB) and 0x10_8000_0000 + y = HBM (y < 16 GiB); the PCIS
// (AppPF BAR4) offset of PA p is p - 0x8000_0000 for both. The window
// the AFI implements is read from OCL RAM_SIZE_MB.
//
// Flow: (load AFI) -> AWS_CLK_GEN clock recipe / reset release ->
// report the core clock (OCL CLK_KHZ, or --recipe-b), which is also the
// mtime rate a Linux DTB's timebase-frequency must match ->
// hold the SoC in reset (OCL CTRL) -> wait for DDR4 (and HBM) ->
// scrub DDR4 once per AFI load with the CL memory engine (DDR4 has ECC:
// never-written lines read back as SLVERR, issue #62) -> optional
// full-range memory test -> copy the images through PCIS (mmap'd
// write-combining BAR4, several threads) -> set the RTC to wall-clock
// time and the boot PC -> release -> stream the virtual UART (3 bytes
// per OCL read) to stdout, forward stdin (--stdin) or a raw terminal
// (--console, Ctrl-] detaches) -> stop on the test finisher (power
// off / fail code / reboot), an exit or failure marker, the riscv-tests
// tohost word or the timeout -> optional --save of memory ranges to
// files -> report the measured core clock.
//
// Register map: docs/FPGA_F2.md (rtl/fpga/sigil_ocl_regs.sv).
// Exit status: 0 pass (exit marker, tohost = 1, finisher power-off),
// 1 fail (fail marker, tohost != 1, finisher fail code, hardware or
// memory-test error), 2 timeout, 3 setup error, 4 console detached,
// 5 reboot requested (with --on-reboot exit).
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#if defined(__x86_64__)
#include <immintrin.h>
#endif

#include <fpga_clkgen.h>
#include <fpga_mgmt.h>
#include <fpga_pci.h>

// OCL registers (byte offsets in AppPF BAR0).
enum {
  R_ID = 0x000, R_VERSION = 0x004, R_CTRL = 0x008, R_STATUS = 0x00C,
  R_BOOT_PC_LO = 0x010, R_BOOT_PC_HI = 0x014, R_CYCLE_LO = 0x018,
  R_CYCLE_HI = 0x01C, R_TRAP_COUNT = 0x020, R_CLK_KHZ = 0x024,
  R_TRAP_CAUSE_LO = 0x028, R_TRAP_CAUSE_HI = 0x02C, R_TRAP_PC_LO = 0x030,
  R_TRAP_PC_HI = 0x034, R_HOST_FLAGS = 0x038, R_SCRATCH = 0x03C,
  R_TX_DATA = 0x040, R_TX_STATUS = 0x044, R_RX_DATA = 0x048, R_RX_STATUS = 0x04C,
  R_TX_DATA3 = 0x050, R_RAM_SIZE_MB = 0x054, R_CAPS = 0x058,
  R_ERR_ADDR_LO = 0x060, R_ERR_ADDR_HI = 0x064, R_ERR_INFO = 0x068, R_ERR_COUNT = 0x06C,
  R_FIN_STATUS = 0x070, R_FIN_VALUE = 0x074,
  R_RTC_LO = 0x080, R_RTC_HI = 0x084, R_RTC_INC = 0x088,
  R_MEM_CTRL = 0x0A0, R_MEM_BASE_LO = 0x0A4, R_MEM_BASE_HI = 0x0A8,
  R_MEM_SIZE_LO = 0x0AC, R_MEM_SIZE_HI = 0x0B0, R_MEM_SEED_LO = 0x0B4,
  R_MEM_SEED_HI = 0x0B8, R_MEM_MISM = 0x0BC, R_MEM_FADDR_LO = 0x0C0,
  R_MEM_FADDR_HI = 0x0C4, R_MEM_CYC_LO = 0x0C8, R_MEM_CYC_HI = 0x0CC,
  R_MEM_RERR = 0x0D0,
};
enum {
  CTRL_RESET_REQ = 1u << 0, CTRL_CACHE_EN = 1u << 1, CTRL_TX_DROP = 1u << 2,
  CTRL_ERR_CLR = 1u << 3,
  ST_IN_RESET = 1u << 0, ST_MEM_ERR = 1u << 1, ST_TX_OVF = 1u << 2,
  ST_RX_FULL = 1u << 3, ST_TRAP_SEEN = 1u << 4, ST_TX_VALID = 1u << 5,
  ST_DDR_READY = 1u << 6, ST_HBM_READY = 1u << 7, ST_MEM_BUSY = 1u << 8,
  ST_MEM_DONE = 1u << 9, ST_MEM_FAIL = 1u << 10, ST_FIN = 1u << 11,
  HF_DDR_SCRUBBED = 1u << 0, HF_HBM_SCRUBBED = 1u << 1,
};
#define SIGIL_ID 0x5349474Cu  // "SIGL"
#define RAM_BASE 0x80000000ull
#define DDR_SIZE 0x1000000000ull  // 64 GiB at AXI 0
#define HBM_AXI 0x1000000000ull   // HBM at AXI 0x10_0000_0000
#define HBM_SIZE 0x400000000ull   // 16 GiB
// pmem disk window (docs/LINUX_PLATFORM.md): never reloaded on a reboot.
#define PMEM_BASE 0xC80000000ull
#define PMEM_END 0x1080000000ull
#define MAX_LOADS 64
#define MAX_SAVES 16
#define MAX_MARKERS 16
// Core clock = AWS_CLK_GEN clk_extra_b1, in kHz per group-B recipe B0..B5
// (aws-fpga v2.3.5 hdk/docs/Clock_Recipes_User_Guide.md; the same table as
// fpga/cl_sigil/build/scripts/synth_cl_sigil.tcl, which builds the
// recipe's value into OCL CLK_KHZ).
static const uint32_t RECIPE_B_KHZ[6] = {125000, 62500, 225000, 62500, 75000, 100000};

#ifdef SV_TEST
// HDK XSIM co-simulation build (fpga/host/cosim/): the SDK calls are
// served by the Shell BFM through DPI, time is simulation time. No
// mmap: PCIS goes through fpga_pci_write_burst / fpga_pci_peek64.
#include "cosim/sigil_host_cosim.h"
#define main sigil_host_main
#else
static double now_s(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}
#define sigil_exit exit
#define sigil_usleep usleep
#endif

static pci_bar_handle_t ocl = PCI_BAR_HANDLE_INIT;
static pci_bar_handle_t pcis = PCI_BAR_HANDLE_INIT;
static uint8_t *pcis_map;          // mmap'd BAR4 (write combining), NULL = burst API
static uint64_t ram_size;          // SoC RAM window (bytes)
static uint32_t core_khz;          // core clock = mtime rate (0: unknown)
static bool keep_timebase;         // --keep-timebase: load the DTB as it is
static int verbose = 1;
static int nthreads = 8;

static void info(const char *fmt, ...) {
  if (!verbose) return;
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "[sigil_host] ");
  vfprintf(stderr, fmt, ap);
  fputc('\n', stderr);
  va_end(ap);
}
static void restore_tty(void);
static void die(int code, const char *fmt, ...) {
  restore_tty();
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "[sigil_host] ERROR: ");
  vfprintf(stderr, fmt, ap);
  fputc('\n', stderr);
  va_end(ap);
  sigil_exit(code);
}
// File errors name the working directory a relative path was resolved
// against (#75: a driver that had sourced aws-fpga's sdk_setup.sh from
// outside the aws-fpga checkout was left in that checkout, so its
// relative image paths named files that were not there).
static void die_path(const char *what, const char *path, int err) {
  char cwd[PATH_MAX];
  if (path[0] != '/' && getcwd(cwd, sizeof cwd))
    die(3, "%s %s: %s (relative to the working directory %s)", what, path, strerror(err), cwd);
  die(3, "%s %s: %s", what, path, strerror(err));
}

static uint32_t rd(uint64_t off) {
  uint32_t v = 0;
  if (fpga_pci_peek(ocl, off, &v) != 0) die(3, "OCL read 0x%03" PRIx64 " failed", off);
  return v;
}
static void wr(uint64_t off, uint32_t v) {
  if (fpga_pci_poke(ocl, off, v) != 0) die(3, "OCL write 0x%03" PRIx64 " failed", off);
}
static uint64_t rd64(uint64_t lo_off) {
  uint32_t lo = rd(lo_off);
  return ((uint64_t)rd(lo_off + 4) << 32) | lo;
}
static void wr64(uint64_t lo_off, uint64_t v) {
  wr(lo_off, (uint32_t)v);
  wr(lo_off + 4, (uint32_t)(v >> 32));
}
static uint64_t cycles(void) { return rd64(R_CYCLE_LO); }  // LO snapshots HI

// ---- console (raw terminal) -------------------------------------------
static struct termios tty_saved;
static bool tty_raw;
static void restore_tty(void) {
  if (tty_raw) {
    tcsetattr(0, TCSAFLUSH, &tty_saved);
    tty_raw = false;
  }
}
static void on_signal(int sig) {
  restore_tty();
  signal(sig, SIG_DFL);
  raise(sig);
}
static void make_raw(void) {
  if (!isatty(0)) return;
  if (tcgetattr(0, &tty_saved) != 0) return;
  struct termios t = tty_saved;
  cfmakeraw(&t);
  t.c_cc[VMIN] = 0;
  t.c_cc[VTIME] = 0;
  if (tcsetattr(0, TCSAFLUSH, &t) == 0) {
    tty_raw = true;
    atexit(restore_tty);
    signal(SIGTERM, on_signal);
    signal(SIGHUP, on_signal);
  }
}

// ---- bulk PCIS copies ----------------------------------------------------
static uint64_t parse_size(const char *s) {
  char *e;
  uint64_t v = strtoull(s, &e, 0);
  switch (*e) {
    case 'k': case 'K': v <<= 10; break;
    case 'm': case 'M': v <<= 20; break;
    case 'g': case 'G': v <<= 30; break;
    default: break;
  }
  return v;
}

struct copy_job {
  uint8_t *dst;
  const uint8_t *src;
  size_t len;
  bool from_bar;
};

#if defined(__x86_64__) && !defined(SV_TEST)
// Host -> BAR: 32-byte non-temporal stores, combined into 64-byte PCIe
// writes by the write-combining buffers.
__attribute__((target("avx2"))) static void copy_to_bar_avx2(uint8_t *d, const uint8_t *s, size_t n) {
  size_t i = 0;
  for (; i + 64 <= n; i += 64) {
    __m256i a = _mm256_loadu_si256((const __m256i *)(s + i));
    __m256i b = _mm256_loadu_si256((const __m256i *)(s + i + 32));
    _mm256_stream_si256((__m256i *)(d + i), a);
    _mm256_stream_si256((__m256i *)(d + i + 32), b);
  }
  if (i < n) memcpy(d + i, s + i, n - i);
  _mm_sfence();
}
// BAR -> host: streaming loads (MOVNTDQA) from write-combining memory.
__attribute__((target("avx2"))) static void copy_from_bar_avx2(uint8_t *d, const uint8_t *s, size_t n) {
  size_t i = 0;
  for (; i + 128 <= n; i += 128) {
    __m256i a = _mm256_stream_load_si256((const __m256i *)(s + i));
    __m256i b = _mm256_stream_load_si256((const __m256i *)(s + i + 32));
    __m256i c = _mm256_stream_load_si256((const __m256i *)(s + i + 64));
    __m256i e = _mm256_stream_load_si256((const __m256i *)(s + i + 96));
    _mm256_storeu_si256((__m256i *)(d + i), a);
    _mm256_storeu_si256((__m256i *)(d + i + 32), b);
    _mm256_storeu_si256((__m256i *)(d + i + 64), c);
    _mm256_storeu_si256((__m256i *)(d + i + 96), e);
  }
  for (; i + 32 <= n; i += 32) {
    __m256i a = _mm256_stream_load_si256((const __m256i *)(s + i));
    _mm256_storeu_si256((__m256i *)(d + i), a);
  }
  if (i < n) memcpy(d + i, s + i, n - i);
}
#endif

static void *copy_worker(void *arg) {
  struct copy_job *j = arg;
#if defined(__x86_64__) && !defined(SV_TEST)
  if (__builtin_cpu_supports("avx2")) {
    if (j->from_bar) copy_from_bar_avx2(j->dst, j->src, j->len);
    else copy_to_bar_avx2(j->dst, j->src, j->len);
    return NULL;
  }
#endif
  memcpy(j->dst, j->src, j->len);
  __sync_synchronize();
  return NULL;
}

// Copy len bytes between host memory and BAR4 offset off with up to
// nthreads threads (64-byte aligned slices). Returns seconds taken.
static double bar_copy(uint64_t off, uint8_t *host, size_t len, bool from_bar) {
  const double t0 = now_s();
  if (!pcis_map) {
    // Burst API (co-simulation, or --no-mmap): 64-byte lines.
    for (size_t o = 0; o < len; o += 64) {
      uint8_t line[64];
      const size_t n = len - o < 64 ? len - o : 64;
      if (from_bar) {
        for (int k = 0; k < 64; k += 8) {
          uint64_t v;
          if (fpga_pci_peek64(pcis, off + o + k, &v) != 0) die(3, "PCIS read failed");
          memcpy(line + k, &v, 8);
        }
        memcpy(host + o, line, n);
      } else {
        memset(line, 0, sizeof line);
        memcpy(line, host + o, n);
        if (fpga_pci_write_burst(pcis, off + o, (uint32_t *)line, 16) != 0)
          die(3, "PCIS write at 0x%" PRIx64 " failed", off + o);
      }
    }
    return now_s() - t0;
  }
  int nt = nthreads < 1 ? 1 : nthreads > 64 ? 64 : nthreads;
  if (len < (16u << 20)) nt = 1;
  pthread_t th[64];
  struct copy_job jobs[64];
  const size_t slice = ((len / (size_t)nt) + 63) & ~(size_t)63;
  int started = 0;
  for (int t = 0; t < nt; t++) {
    const size_t o = (size_t)t * slice;
    if (o >= len) break;
    const size_t n = len - o < slice ? len - o : slice;
    jobs[t].from_bar = from_bar;
    jobs[t].len = n;
    jobs[t].dst = from_bar ? host + o : pcis_map + off + o;
    jobs[t].src = from_bar ? pcis_map + off + o : host + o;
    if (nt == 1) {
      copy_worker(&jobs[t]);
    } else if (pthread_create(&th[t], NULL, copy_worker, &jobs[t]) != 0) {
      die(3, "pthread_create failed");
    }
    started++;
  }
  if (nt > 1)
    for (int t = 0; t < started; t++) pthread_join(th[t], NULL);
  return now_s() - t0;
}

static void check_range(const char *what, uint64_t addr, uint64_t len) {
  if (addr < RAM_BASE || addr - RAM_BASE > ram_size || len > ram_size - (addr - RAM_BASE) ||
      (addr & 63))
    die(3, "%s: 0x%" PRIx64 "+0x%" PRIx64 " outside the RAM window [0x%llx, 0x%" PRIx64
        ") or not 64-byte aligned", what, addr, len, RAM_BASE, RAM_BASE + ram_size);
}

struct load { uint64_t addr; const char *path; bool dtb; };

// Device tree edits, in place (every property keeps its size).
static uint32_t be32(const uint8_t *p) {
  return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}
// Calls fn for every property of the flattened tree with the names of the
// nodes above it: names[1] is the root (""), names[2] a node below it, ...
// up to depth FDT_MAX_DEPTH. fn returns true to stop the walk.
#define FDT_MAX_DEPTH 8
typedef bool (*fdt_prop_fn)(const char *const *names, int depth, const char *pname,
                            uint8_t *val, uint32_t plen, void *ctx);
static void fdt_walk(uint8_t *fdt, size_t len, fdt_prop_fn fn, void *ctx) {
  if (len < 40 || be32(fdt) != 0xd00dfeedu) return;
  const uint32_t off_struct = be32(fdt + 8), off_strings = be32(fdt + 12);
  const uint32_t size_struct = be32(fdt + 36);
  if ((size_t)off_struct + size_struct > len || off_strings >= len) return;
  const char *names[FDT_MAX_DEPTH + 1] = {0};
  size_t p = off_struct;
  const size_t end = (size_t)off_struct + size_struct;
  int depth = 0;
  while (p + 4 <= end) {
    const uint32_t tok = be32(fdt + p);
    p += 4;
    if (tok == 1) {  // FDT_BEGIN_NODE
      const char *name = (const char *)fdt + p;
      const size_t n = strnlen(name, end - p);
      depth++;
      if (depth <= FDT_MAX_DEPTH) names[depth] = name;
      p += (n + 4) & ~(size_t)3;
    } else if (tok == 2) {  // FDT_END_NODE
      depth--;
    } else if (tok == 3) {  // FDT_PROP
      if (p + 8 > end) return;
      const uint32_t plen = be32(fdt + p), nameoff = be32(fdt + p + 4);
      p += 8;
      if (p + plen > end) return;
      if (depth >= 1 && depth <= FDT_MAX_DEPTH && off_strings + nameoff < len &&
          fn(names, depth, (const char *)fdt + off_strings + nameoff, fdt + p, plen, ctx))
        return;
      p += (plen + 3) & ~(size_t)3;
    } else if (tok != 4) {  // not FDT_NOP: FDT_END or garbage
      return;
    }
  }
}

// Fill /chosen/rng-seed (if the DTB has one) with fresh random bytes, so
// every boot gets its own kernel RNG seed.
static bool fdt_rng_seed_prop(const char *const *names, int depth, const char *pname,
                              uint8_t *val, uint32_t plen, void *ctx) {
  if (depth != 2 || strcmp(names[2], "chosen") || strcmp(pname, "rng-seed")) return false;
#ifndef SV_TEST
  size_t *got = ctx;
  while (*got < plen) {
    ssize_t r = getrandom(val + *got, plen - *got, 0);
    if (r <= 0) break;
    *got += (size_t)r;
  }
#else
  (void)val;
  (void)plen;
  (void)ctx;
#endif
  return true;
}
// Returns the number of bytes written.
static size_t fdt_fill_rng_seed(uint8_t *fdt, size_t len) {
  size_t got = 0;
  fdt_walk(fdt, len, fdt_rng_seed_prop, &got);
  return got;
}

// /cpus/timebase-frequency (and any copy in a /cpus/cpu@N node) is the
// rate of mtime, which on the Sigil CL ticks once per core clock. The
// first value found is reported; with fix, every copy that differs from
// want is rewritten to want.
struct fdt_timebase {
  uint32_t want, found, n_found, n_fixed;
  bool fix;
};
static bool fdt_timebase_prop(const char *const *names, int depth, const char *pname,
                              uint8_t *val, uint32_t plen, void *ctx) {
  struct fdt_timebase *t = ctx;
  if (plen != 4 || strcmp(pname, "timebase-frequency") || depth < 2 || depth > 3 ||
      strcmp(names[2], "cpus") || (depth == 3 && strncmp(names[3], "cpu@", 4)))
    return false;
  const uint32_t v = be32(val);
  if (t->n_found++ == 0) t->found = v;
  if (t->fix && v != t->want) {
    for (int b = 0; b < 4; b++) val[b] = (uint8_t)(t->want >> (24 - 8 * b));
    t->n_fixed++;
  }
  return false;
}
// The DTB for each F2 core clock (sw/linux/dts, scripts/build_dtbs.sh).
static const char *dtb_for_khz(uint32_t khz) {
  return khz == 62500 ? "sigil-f2.dtb" : khz == 100000 ? "sigil-f2-100.dtb" : NULL;
}
// Check the DTB's timebase against the core clock; unless --keep-timebase,
// load it with the core clock instead when they differ.
static void fdt_check_timebase(const char *path, uint8_t *fdt, size_t len) {
  if (!core_khz) return;
  const uint32_t hz = core_khz * 1000u;
  struct fdt_timebase t = {.want = hz, .fix = !keep_timebase};
  fdt_walk(fdt, len, fdt_timebase_prop, &t);
  const char *right = dtb_for_khz(core_khz);
  if (!t.n_found) {
    info("WARNING: %s has no /cpus/timebase-frequency (the core clock is %u Hz)", path, hz);
  } else if (t.found == hz && !t.n_fixed) {
    info("%s: timebase-frequency %u Hz = the core clock", path, t.found);
  } else if (t.n_fixed) {
    info("WARNING: %s: timebase-frequency %u Hz, but the core clock is %u Hz: loaded with %u Hz "
         "(%s%s%s--keep-timebase loads it unchanged)", path, t.found, hz, hz,
         right ? "the DTB for this clock is " : "", right ? right : "", right ? "; " : "");
  } else {
    info("WARNING: %s: timebase-frequency %u Hz, but the core clock is %u Hz (--keep-timebase): "
         "Linux time will run %.3fx real time", path, t.found, hz,
         t.found ? (double)hz / t.found : 0.0);
  }
}
struct save { uint64_t addr; uint64_t size; const char *path; };

// Every image is opened, and every --save / --log directory checked for
// write access, before the FPGA is touched: a bad path used to surface
// only after the AFI setup and the DDR4 scrub (10-17 s). A run with
// relative paths reports the directory they resolve against.
static void check_dir_writable(const char *path) {
  char dir[PATH_MAX];
  const char *slash = strrchr(path, '/');
  if (!slash) snprintf(dir, sizeof dir, ".");
  else if (slash == path) snprintf(dir, sizeof dir, "/");
  else snprintf(dir, sizeof dir, "%.*s", (int)(slash - path), path);
  if (access(dir, W_OK) != 0) die_path("cannot create", path, errno);
}
static void check_paths(const struct load *loads, int nloads, const struct save *saves, int nsaves,
                        const char *log_path) {
  bool relative = log_path && log_path[0] != '/';
  for (int k = 0; k < nloads; k++) {
    const int fd = open(loads[k].path, O_RDONLY);
    if (fd < 0) die_path("cannot open", loads[k].path, errno);
    close(fd);
    relative |= loads[k].path[0] != '/';
  }
  for (int k = 0; k < nsaves; k++) {
    check_dir_writable(saves[k].path);
    relative |= saves[k].path[0] != '/';
  }
  if (log_path) check_dir_writable(log_path);
  char cwd[PATH_MAX];
  if (relative && getcwd(cwd, sizeof cwd)) info("relative paths resolve against %s", cwd);
}

// Map (or read) a file; length rounded up to whole 64-byte lines with
// zero padding (no partial PCIe writes into ECC-protected DDR4).
static uint8_t *map_file(const char *path, size_t *len, size_t *maplen, bool *mapped) {
  int fd = open(path, O_RDONLY);
  if (fd < 0) die_path("cannot open", path, errno);
  struct stat st;
  if (fstat(fd, &st) != 0) die(3, "cannot stat %s", path);
  *len = (size_t)st.st_size;
  const size_t padded = (*len + 63) & ~(size_t)63;
  uint8_t *p = NULL;
#ifndef SV_TEST
  if (*len >= (1u << 20) && *len == padded) {
    p = mmap(NULL, *len, PROT_READ, MAP_PRIVATE | MAP_POPULATE, fd, 0);
    if (p == MAP_FAILED) p = NULL;
    else {
      madvise(p, *len, MADV_SEQUENTIAL);
      *mapped = true;
      *maplen = *len;
    }
  }
#endif
  if (!p) {
    p = calloc(1, padded ? padded : 64);
    if (!p) die(3, "out of memory for %s", path);
    size_t got = 0;
    while (got < *len) {
      ssize_t r = read(fd, p + got, *len - got);
      if (r <= 0) die(3, "cannot read %s", path);
      got += (size_t)r;
    }
    *mapped = false;
    *maplen = padded;
  }
  close(fd);
  return p;
}

static void load_image(const struct load *l, bool verify_all) {
  size_t n, maplen;
  bool mapped = false;
  uint8_t *buf = map_file(l->path, &n, &maplen, &mapped);
  const size_t n64 = (n + 63) & ~(size_t)63;
  if (l->dtb && !mapped) {
    const size_t k = fdt_fill_rng_seed(buf, n);
    if (k) info("%s: /chosen/rng-seed filled with %zu fresh random bytes", l->path, k);
    fdt_check_timebase(l->path, buf, n);
  }
  check_range(l->path, l->addr, n64);
  const uint64_t off = l->addr - RAM_BASE;
  const double dt = bar_copy(off, buf, n64, false);
  // Read back: everything with --verify, else the first and last 4 KiB.
  size_t bad = 0;
  const size_t chunk = verify_all ? n64 : (n64 < 8192 ? n64 : 4096);
  uint8_t *rb = malloc(verify_all ? n64 : 8192);
  if (!rb) die(3, "out of memory");
  const double v0 = now_s();
  bar_copy(off, rb, chunk, true);
  for (size_t i = 0; i < chunk && i < n; i++)
    if (rb[i] != buf[i] && bad++ < 4)
      fprintf(stderr, "[sigil_host] verify %s +0x%zx: %02x != %02x\n", l->path, i, rb[i], buf[i]);
  if (!verify_all && n64 > chunk) {
    const size_t t = n64 - 4096;
    bar_copy(off + t, rb, 4096, true);
    for (size_t i = 0; i < 4096 && t + i < n; i++)
      if (rb[i] != buf[t + i] && bad++ < 4)
        fprintf(stderr, "[sigil_host] verify %s +0x%zx: %02x != %02x\n", l->path, t + i, rb[i],
                buf[t + i]);
  }
  const double vdt = now_s() - v0;
  free(rb);
  if (bad) die(1, "%s: %zu mismatching bytes after load", l->path, bad);
  info("loaded %s: %zu bytes at 0x%" PRIx64 " (PCIS 0x%" PRIx64 ") in %.3f s = %.2f GB/s, "
       "%s verified in %.3f s%s",
       l->path, n, l->addr, off, dt, dt > 0 ? n64 / dt / 1e9 : 0.0,
       verify_all ? "fully" : "head/tail", vdt,
       verify_all && vdt > 0 ? "" : "");
  if (verify_all && vdt > 0) info("  read-back rate %.2f GB/s", n64 / vdt / 1e9);
#ifndef SV_TEST
  if (mapped) munmap(buf, maplen);
  else
#endif
    free(buf);
}

static void save_range(const struct save *s) {
  check_range(s->path, s->addr, s->size);
  const uint64_t off = s->addr - RAM_BASE;
  int fd = open(s->path, O_RDWR | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) die_path("cannot create", s->path, errno);
  uint8_t *dst;
  bool mapped = false;
#ifndef SV_TEST
  if (s->size && ftruncate(fd, (off_t)s->size) == 0) {
    dst = mmap(NULL, s->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    mapped = dst != MAP_FAILED;
    if (!mapped) dst = NULL;
  } else {
    dst = NULL;
  }
#else
  dst = NULL;
  (void)mapped;
#endif
  if (!dst) {
    dst = malloc(s->size ? s->size : 1);
    if (!dst) die(3, "out of memory for %s", s->path);
  }
  const double dt = bar_copy(off, dst, s->size, true);
  const double w0 = now_s();
#ifndef SV_TEST
  if (mapped) {
    msync(dst, s->size, MS_SYNC);
    munmap(dst, s->size);
  } else
#endif
  {
    size_t done = 0;
    while (done < s->size) {
      ssize_t w = write(fd, dst + done, s->size - done);
      if (w <= 0) die(3, "cannot write %s", s->path);
      done += (size_t)w;
    }
    free(dst);
  }
  close(fd);
  info("saved 0x%" PRIx64 "+0x%" PRIx64 " (PCIS 0x%" PRIx64 ") to %s: PCIS read %.3f s = %.2f GB/s, "
       "file write %.3f s", s->addr, s->size, off, s->path, dt, dt > 0 ? s->size / dt / 1e9 : 0.0,
       now_s() - w0);
}

// ---- memory engine (CL, sigil_axi_memeng) ------------------------------
// mode: bit 0 address pattern (else constant seed), bit 1 check.
static uint32_t engine(int mode, uint64_t axi, uint64_t size, uint64_t seed, bool quiet) {
  wr64(R_MEM_BASE_LO, axi);
  wr64(R_MEM_SIZE_LO, size);
  wr64(R_MEM_SEED_LO, seed);
  const double t0 = now_s();
  wr(R_MEM_CTRL, ((uint32_t)mode << 4) | 1u);
  uint32_t c;
  int k = 0;
  while (((c = rd(R_MEM_CTRL)) & 3u) != 2u) {
    if (++k == 20 && !(c & 1u)) die(3, "memory engine did not start (SoC not held?) MEM_CTRL 0x%x", c);
    sigil_usleep(k < 100 ? 10 : 1000);
    if (now_s() - t0 > 600) die(1, "memory engine timeout");
  }
  const double dt = now_s() - t0;
  const uint32_t mism = rd(R_MEM_MISM), rerr = rd(R_MEM_RERR);
  const uint64_t cyc = rd64(R_MEM_CYC_LO);
  if (!quiet || (c & 4u))
    info("  engine %-13s AXI 0x%010" PRIx64 "+0x%" PRIx64 ": %.2f s (%.2f GB/s, %" PRIu64
         " core cycles), mismatches %u, error responses %u%s",
         mode == 0 ? "fill" : mode == 1 ? "write-pattern" : mode == 2 ? "check-fill" : "check-pattern",
         axi, size, dt, dt > 0 ? size / dt / 1e9 : 0.0, cyc, mism, rerr,
         (c & 4u) ? " FAIL" : "");
  if (mism) info("  first mismatch at AXI 0x%" PRIx64 " (SoC PA 0x%" PRIx64 ")",
                 rd64(R_MEM_FADDR_LO), rd64(R_MEM_FADDR_LO) + RAM_BASE);
  return (c & 4u) ? (mism + rerr ? mism + rerr : 1) : 0;
}

// Fill [axi, axi+size) with zeros in 4 GiB steps.
static double scrub(const char *name, uint64_t axi, uint64_t size) {
  const double t0 = now_s();
  for (uint64_t o = 0; o < size; o += 4ull << 30) {
    const uint64_t n = size - o < (4ull << 30) ? size - o : (4ull << 30);
    if (engine(0, axi + o, n, 0, true)) die(1, "%s scrub failed at AXI 0x%" PRIx64, name, axi + o);
  }
  const double dt = now_s() - t0;
  info("scrubbed %s (%" PRIu64 " GiB) in %.1f s = %.2f GB/s", name, size >> 30, dt,
       dt > 0 ? size / dt / 1e9 : 0.0);
  return dt;
}

static int memtest(const char *name, uint64_t axi, uint64_t size) {
  info("memtest %s: AXI 0x%" PRIx64 " + %" PRIu64 " GiB (SoC PA 0x%" PRIx64 "), address patterns, "
       "two seeds", name, axi, size >> 30, axi + RAM_BASE);
  uint32_t errs = 0;
  const uint64_t seeds[2] = {0x0123456789ABCDEFull, 0xFEDCBA9876543210ull};
  const double t0 = now_s();
  for (int i = 0; i < 2; i++) {
    errs += engine(1, axi, size, seeds[i], false);
    errs += engine(3, axi, size, seeds[i], false);
  }
  const double dt = now_s() - t0;
  info("memtest %s: %s, %u errors, %.1f s (%.2f GB/s over 4 passes)", name, errs ? "FAIL" : "PASS",
       errs, dt, dt > 0 ? 4.0 * size / dt / 1e9 : 0.0);
  return errs != 0;
}

static void print_err_capture(void) {
  const uint32_t inf = rd(R_ERR_INFO);
  if (!(inf >> 31)) return;
  static const char *resp[4] = {"OKAY", "EXOKAY", "SLVERR", "DECERR"};
  fprintf(stderr, "[sigil_host] first memory error: %s of SoC PA 0x%016" PRIx64 " (len %u): %s%s%s, "
          "response ID 0x%x; %u error(s) since clear\n",
          (inf >> 30) & 1 ? "write" : "read", rd64(R_ERR_ADDR_LO), (inf >> 16) & 0xFF,
          (inf >> 29) & 1 ? "outside the RAM window (no AXI transaction)" : resp[(inf >> 26) & 3],
          (inf >> 28) & 1 ? ", unexpected ID" : "",
          (inf >> 29) & 1 ? "" : ((inf >> 26) & 3) == 2 && !((inf >> 30) & 1)
                                     ? " (DDR4 uncorrectable ECC: never-written memory?)" : "",
          inf & 0xFFFF, rd(R_ERR_COUNT));
}

static void usage(const char *p) {
  fprintf(stderr,
"usage: %s [options] (--linux --fw F --image F --dtb F | --bin F | --load 0xADDR=F ... |\n"
"                     --memtest WHAT | --info)\n"
"  -S N               FPGA slot (default 0)\n"
"  --afi agfi-...     load this AFI first (else it must already be loaded)\n"
"  --info             print the loaded AFI and its CL (core clock, memory) as\n"
"                     key=value lines on stdout and exit; the SoC is not touched\n"
"  --recipe-b N       program AWS_CLK_GEN group B recipe N (0..5; 1 = 62.5 MHz,\n"
"                     5 = 100 MHz) instead of keeping the AFI's build recipe\n"
"                     (CLK_KHZ); the RTC increment follows\n"
"  --linux            OpenSBI fw_jump (--fw) at 0x80000000, Linux --image at\n"
"                     0x80200000, --dtb at --dtb-addr (0x83000000) [--initrd F\n"
"                     at --initrd-addr (0x84000000)]; a /chosen/rng-seed in the\n"
"                     DTB is filled with fresh random bytes, and a\n"
"                     /cpus/timebase-frequency other than the core clock is\n"
"                     replaced by it (sigil-f2.dtb: 62.5 MHz AFIs,\n"
"                     sigil-f2-100.dtb: 100 MHz AFIs)\n"
"  --keep-timebase    load the --dtb timebase-frequency unchanged\n"
"  --bin F            baremetal image at 0x80000000 (boot ROM jumps there)\n"
"  --load 0xADDR=F    image at SoC address ADDR (repeatable; DDR4 0x80000000..\n"
"                     0x107FFFFFFF, HBM 0x1080000000..0x147FFFFFFF)\n"
"  --save 0xADDR=F:SIZE  after the run, write SIZE bytes (K/M/G suffixes) of SoC\n"
"                     memory at ADDR to file F (repeatable)\n"
"  --boot-pc 0xADDR   reset PC (default 0x1000, the boot ROM)\n"
"  --no-cache         L1 caches off\n"
"  --exit TEXT        pass marker (repeatable; default: LINUX_BOOT_OK, SIGIL TEST\n"
"                     PASS, SOC CRYPTO PASS, SOC HASH PASS, FPGA SMOKE PASS,\n"
"                     HELLO FROM S-MODE, F2 PLATFORM PASS, F2 MEMTEST PASS)\n"
"  --fail TEXT        failure marker (repeatable; default: FAIL, Kernel panic)\n"
"  --no-markers       ignore UART markers (end on the finisher or the timeout)\n"
"  --tohost 0xADDR    riscv-tests HTIF: poll this RAM word (use --no-cache)\n"
"  --timeout S        seconds (default 60; 0 = none)\n"
"  --stdin            forward stdin to the UART RX\n"
"  --console          interactive raw-terminal console (implies --stdin and\n"
"                     --no-markers, no timeout); Ctrl-] detaches (exit 4,\n"
"                     the SoC keeps running with the UART in drop mode)\n"
"  --log F            also write the UART stream to F\n"
"  --verify           read every loaded byte back (default: head/tail)\n"
"  --keep-running     leave the SoC running on exit (default: hold in reset)\n"
"  --on-reboot MODE   finisher reboot (0x7777): rerun (reload the boot images --\n"
"                     not those in the pmem window 0xC80000000..0x107FFFFFFF --\n"
"                     and release again; default) or exit (status 5)\n"
"  --scrub MODE       auto (default: zero all DDR4 once per AFI load -- the\n"
"                     DDR4 has ECC, reading never-written memory is an error),\n"
"                     always, never; --scrub-hbm also zeroes the 16 GiB HBM\n"
"  --memtest WHAT     full-range memory test with the CL memory engine before\n"
"                     the run: ddr, hbm or all (address patterns, 2 seeds)\n"
"  --mailbox 0xVAL    64-bit word at SoC 0x80080000 for the F2 test firmware\n"
"  --rtc-ns N         RTC time (ns since the epoch; default: host wall clock)\n"
"  --threads N        bulk copy threads (default 8)\n"
"  --no-mmap          PCIS through the SDK burst calls instead of mmap\n"
"  --ignore-mem-err   do not stop on STATUS.mem_err (the bridge error capture\n"
"                     is still printed)\n"
"  -q                 quiet (UART output only)\n", p);
  sigil_exit(3);
}

int main(int argc, char **argv) {
  int slot = 0, recipe_b = -1;
  const char *afi = NULL, *fw = NULL, *image = NULL, *dtb = NULL, *initrd = NULL;
  const char *log_path = NULL, *memtest_what = NULL;
  bool linux_mode = false, cache_en = true, use_stdin = false, verify_all = false;
  bool keep_running = false, ignore_mem_err = false, console = false, no_markers = false;
  bool scrub_hbm = false, use_mmap = true, have_rtc = false, have_mailbox = false;
  bool info_only = false;
  int scrub_mode = 0;  // 0 auto, 1 always, 2 never
  bool reboot_rerun = true;
  uint64_t boot_pc = 0x1000, tohost = 0, dtb_addr = 0x83000000ull, initrd_addr = 0x84000000ull;
  uint64_t rtc_ns = 0, mailbox = 0;
  double timeout = 60;
  bool timeout_set = false;
  struct load loads[MAX_LOADS];
  struct save saves[MAX_SAVES];
  int nloads = 0, nsaves = 0;
  const char *exits[MAX_MARKERS], *fails[MAX_MARKERS];
  int nexit = 0, nfail = 0;

  for (int i = 1; i < argc; i++) {
    const char *a = argv[i];
    const char *v = i + 1 < argc ? argv[i + 1] : NULL;
#define NEXT() do { if (!v) usage(argv[0]); i++; } while (0)
    if (!strcmp(a, "-S")) { NEXT(); slot = atoi(v); }
    else if (!strcmp(a, "--afi")) { NEXT(); afi = v; }
    else if (!strcmp(a, "--recipe-b")) {
      NEXT();
      recipe_b = atoi(v);
      if (recipe_b < 0 || recipe_b > 5) usage(argv[0]);
    }
    else if (!strcmp(a, "--info")) info_only = true;
    else if (!strcmp(a, "--keep-timebase")) keep_timebase = true;
    else if (!strcmp(a, "--linux")) linux_mode = true;
    else if (!strcmp(a, "--fw")) { NEXT(); fw = v; }
    else if (!strcmp(a, "--image")) { NEXT(); image = v; }
    else if (!strcmp(a, "--dtb")) { NEXT(); dtb = v; }
    else if (!strcmp(a, "--dtb-addr")) { NEXT(); dtb_addr = strtoull(v, NULL, 0); }
    else if (!strcmp(a, "--initrd")) { NEXT(); initrd = v; }
    else if (!strcmp(a, "--initrd-addr")) { NEXT(); initrd_addr = strtoull(v, NULL, 0); }
    else if (!strcmp(a, "--bin")) {
      NEXT();
      if (nloads == MAX_LOADS) usage(argv[0]);
      loads[nloads++] = (struct load){RAM_BASE, v, false};
    } else if (!strcmp(a, "--load")) {
      NEXT();
      const char *eq = strchr(v, '=');
      if (!eq || nloads == MAX_LOADS) usage(argv[0]);
      loads[nloads++] = (struct load){strtoull(v, NULL, 0), eq + 1, false};
    } else if (!strcmp(a, "--save")) {
      NEXT();
      const char *eq = strchr(v, '='), *colon = strrchr(v, ':');
      if (!eq || !colon || colon < eq || nsaves == MAX_SAVES) usage(argv[0]);
      char *path = strndup(eq + 1, (size_t)(colon - eq - 1));
      saves[nsaves++] = (struct save){strtoull(v, NULL, 0), parse_size(colon + 1), path};
    }
    else if (!strcmp(a, "--boot-pc")) { NEXT(); boot_pc = strtoull(v, NULL, 0); }
    else if (!strcmp(a, "--no-cache")) cache_en = false;
    else if (!strcmp(a, "--exit")) { NEXT(); if (nexit < MAX_MARKERS) exits[nexit++] = v; }
    else if (!strcmp(a, "--fail")) { NEXT(); if (nfail < MAX_MARKERS) fails[nfail++] = v; }
    else if (!strcmp(a, "--no-markers")) no_markers = true;
    else if (!strcmp(a, "--tohost")) { NEXT(); tohost = strtoull(v, NULL, 0); }
    else if (!strcmp(a, "--timeout")) { NEXT(); timeout = atof(v); timeout_set = true; }
    else if (!strcmp(a, "--stdin")) use_stdin = true;
    else if (!strcmp(a, "--console")) console = true;
    else if (!strcmp(a, "--log")) { NEXT(); log_path = v; }
    else if (!strcmp(a, "--verify")) verify_all = true;
    else if (!strcmp(a, "--keep-running")) keep_running = true;
    else if (!strcmp(a, "--ignore-mem-err")) ignore_mem_err = true;
    else if (!strcmp(a, "--on-reboot")) { NEXT(); reboot_rerun = !strcmp(v, "rerun"); }
    else if (!strcmp(a, "--scrub")) {
      NEXT();
      scrub_mode = !strcmp(v, "always") ? 1 : !strcmp(v, "never") ? 2 : 0;
    }
    else if (!strcmp(a, "--scrub-hbm")) scrub_hbm = true;
    else if (!strcmp(a, "--memtest")) { NEXT(); memtest_what = v; }
    else if (!strcmp(a, "--mailbox")) { NEXT(); mailbox = strtoull(v, NULL, 0); have_mailbox = true; }
    else if (!strcmp(a, "--rtc-ns")) { NEXT(); rtc_ns = strtoull(v, NULL, 0); have_rtc = true; }
    else if (!strcmp(a, "--threads")) { NEXT(); nthreads = atoi(v); }
    else if (!strcmp(a, "--no-mmap")) use_mmap = false;
    else if (!strcmp(a, "-q")) verbose = 0;
    else usage(argv[0]);
#undef NEXT
  }
  if (console) {
    use_stdin = true;
    no_markers = true;
    if (!timeout_set) timeout = 0;
  }
  if (linux_mode) {
    if (!fw || !image || !dtb || nloads + 4 > MAX_LOADS) usage(argv[0]);
    loads[nloads++] = (struct load){0x80000000ull, fw, false};
    loads[nloads++] = (struct load){0x80200000ull, image, false};
    loads[nloads++] = (struct load){dtb_addr, dtb, true};
    if (initrd) loads[nloads++] = (struct load){initrd_addr, initrd, false};
  }
  if (nloads == 0 && !memtest_what && !info_only) usage(argv[0]);
  if (nexit == 0) {
    static const char *dflt[] = {"LINUX_BOOT_OK", "SIGIL TEST PASS", "SOC CRYPTO PASS", "SOC HASH PASS",
                                 "FPGA SMOKE PASS", "HELLO FROM S-MODE", "F2 PLATFORM PASS",
                                 "F2 MEMTEST PASS"};
    for (size_t k = 0; k < sizeof dflt / sizeof *dflt; k++) exits[nexit++] = dflt[k];
  }
  if (nfail == 0) {
    fails[nfail++] = "FAIL";
    fails[nfail++] = "Kernel panic";
  }
  if (no_markers) nexit = nfail = 0;
  check_paths(loads, nloads, saves, nsaves, log_path);

  // ---- FPGA / AFI / clocks ------------------------------------------
  if (fpga_mgmt_init() != 0) die(3, "fpga_mgmt_init failed (run as root on an F2 instance?)");
  if (afi) {
    struct fpga_mgmt_image_info img;
    memset(&img, 0, sizeof img);
    info("loading %s into slot %d", afi, slot);
    if (fpga_mgmt_load_local_image_sync(slot, (char *)afi, 120, 1000, &img) != 0)
      die(3, "AFI load failed");
  }
  struct fpga_mgmt_image_info loaded;
  memset(&loaded, 0, sizeof loaded);
  if (fpga_mgmt_describe_local_image(slot, &loaded, 0) != 0) die(3, "describe slot %d failed", slot);
  if (loaded.status != FPGA_STATUS_LOADED)
    die(3, "slot %d: no AFI loaded (status %d)", slot, loaded.status);
  info("slot %d: AFI %s, shell 0x%08x", slot, loaded.ids.afi_id, loaded.sh_version);
  // Release the CL resets with the build's clock recipes first (the OCL
  // registers sit behind them), then optionally reprogram group B.
  if (aws_clkgen_deassert_resets(slot) != 0) die(3, "aws_clkgen_deassert_resets failed");
  if (recipe_b >= 0) {
    // Groups A/C: HDK defaults A1, C0. HBM: the build's recipe from OCL
    // CAPS[7:4] (recipe + 1) when the CL reports it, else H2 (v3 CL).
    uint32_t hbm_recipe = 2;
    if (fpga_pci_attach(slot, FPGA_APP_PF, APP_PF_BAR0, 0, &ocl) == 0) {
      uint32_t v = 0, caps = 0;
      if (fpga_pci_peek(ocl, R_ID, &v) == 0 && v == SIGIL_ID &&
          fpga_pci_peek(ocl, R_VERSION, &caps) == 0 && (caps >> 16) >= 4 &&
          fpga_pci_peek(ocl, R_CAPS, &caps) == 0 && ((caps >> 4) & 0xF) != 0)
        hbm_recipe = ((caps >> 4) & 0xF) - 1;
      fpga_pci_detach(ocl);
      ocl = PCI_BAR_HANDLE_INIT;
    }
    info("AWS_CLK_GEN: group B recipe B%d (A1 C0 H%u for the other groups)", recipe_b, hbm_recipe);
    if (aws_clkgen_set_recipe(slot, 1, (uint32_t)recipe_b, 0, hbm_recipe, 0) != 0)
      die(3, "aws_clkgen_set_recipe failed");
  }
  if (fpga_pci_attach(slot, FPGA_APP_PF, APP_PF_BAR0, 0, &ocl) != 0) die(3, "attach OCL BAR0 failed");
  if (fpga_pci_attach(slot, FPGA_APP_PF, APP_PF_BAR4, BURST_CAPABLE, &pcis) != 0)
    die(3, "attach PCIS BAR4 failed");

  const uint32_t id = rd(R_ID);
  if (id != SIGIL_ID) die(3, "OCL ID 0x%08x is not the Sigil CL (0x%08x)", id, SIGIL_ID);
  const uint32_t version = rd(R_VERSION);
  const uint32_t khz = rd(R_CLK_KHZ);
  const bool v4 = (version >> 16) >= 4;
  ram_size = v4 ? (uint64_t)rd(R_RAM_SIZE_MB) << 20 : 0x08000000ull;
  const uint32_t caps = v4 ? rd(R_CAPS) : 0;
  const bool has_hbm = caps & 1u;
  info("Sigil CL version 0x%08x, RAM window %" PRIu64 " MiB at 0x80000000%s", version,
       ram_size >> 20, has_hbm ? " (DDR4 64 GiB + HBM 16 GiB)" : "");
  if (has_hbm && (caps >> 4) & 0xF) info("HBM AXI clock: AWS_CLK_GEN recipe H%u", ((caps >> 4) & 0xF) - 1);
  // The core clock is also the mtime rate, so the Linux DTB's
  // timebase-frequency must equal it (checked when --dtb is loaded).
  core_khz = recipe_b >= 0 ? RECIPE_B_KHZ[recipe_b] : khz <= 1000000 ? khz : 0;
  const char *dtb_name = dtb_for_khz(core_khz);
  if (recipe_b >= 0)
    info("core clock %.3f MHz (--recipe-b B%d; the AFI's build recipe is %.3f MHz)",
         core_khz / 1000.0, recipe_b, khz / 1000.0);
  else
    info("core clock %.3f MHz (the AFI's build recipe, OCL CLK_KHZ)", core_khz / 1000.0);
  if (core_khz && (linux_mode || info_only))
    info("Linux timebase-frequency must be %u Hz%s%s", core_khz * 1000u,
         dtb_name ? ": boot with " : "", dtb_name ? dtb_name : "");
  if (info_only) {
    printf("slot=%d\nafi=%s\nshell=0x%08x\ncl_version=0x%08x\ncore_clk_khz=%u\nbuild_clk_khz=%u\n"
           "ram_mb=%" PRIu64 "\nhbm=%d\n", slot, loaded.ids.afi_id, loaded.sh_version, version,
           core_khz, khz, ram_size >> 20, has_hbm ? 1 : 0);
    if (has_hbm && (caps >> 4) & 0xF) printf("hbm_recipe=H%u\n", ((caps >> 4) & 0xF) - 1);
    if (dtb_name) printf("dtb=%s\n", dtb_name);
    fflush(stdout);
    fpga_pci_detach(ocl);
    fpga_pci_detach(pcis);
    return 0;
  }
  if (v4 && recipe_b >= 0) {
    // The RTC adds RTC_INC ns per core cycle (Q8.24); its reset value is
    // for the build recipe.
    const uint32_t inc = (uint32_t)((1000000ull << 24) / core_khz);
    wr(R_RTC_INC, inc);
    info("RTC increment 0x%08x (%.3f ns per core cycle)", inc, inc / 16777216.0);
  }
#ifndef SV_TEST
  if (use_mmap) {
    void *p = NULL;
    if (fpga_pci_get_address(pcis, 0, 64, &p) == 0 && p) pcis_map = p;
    else info("BAR4 mmap unavailable; using the burst API");
  }
#else
  (void)use_mmap;
#endif

  // ---- hold, ready, scrub, memtest ----------------------------------
  const uint32_t ctrl_run = cache_en ? CTRL_CACHE_EN : 0;
  wr(R_CTRL, ctrl_run | CTRL_RESET_REQ);
  for (int k = 0; !(rd(R_STATUS) & ST_IN_RESET); k++)
    if (k > 100000) die(1, "SoC never entered reset");
  unsigned stale = 0;
  while (rd(R_TX_DATA) & 0x80000000u) stale++;
  if (stale) info("discarded %u UART bytes from a previous run", stale);
  bool hbm_ok = has_hbm;
  {
    const double t0 = now_s();
    uint32_t st;
    while (!((st = rd(R_STATUS)) & ST_DDR_READY) || (has_hbm && !(st & ST_HBM_READY))) {
      if (now_s() - t0 > 10) {
        if (!(st & ST_DDR_READY)) die(3, "DDR4 not ready (STATUS 0x%08x)", st);
        info("WARNING: HBM not ready after 10 s (STATUS 0x%08x); DDR4 only", st);
        hbm_ok = false;
        break;
      }
      sigil_usleep(1000);
    }
    info("DDR4 ready%s (STATUS 0x%08x)", hbm_ok ? ", HBM ready" : "", st);
  }
  if (v4) wr(R_CTRL, ctrl_run | CTRL_RESET_REQ | CTRL_ERR_CLR);  // clear the error capture
  int rc_mem = 0;
  if (v4) {
    uint32_t hf = rd(R_HOST_FLAGS);
    const uint64_t ddr_axi = ram_size < DDR_SIZE ? ram_size : DDR_SIZE;
    if (memtest_what) {
      if (strcmp(memtest_what, "hbm")) {
        rc_mem |= memtest("ddr", 0, ddr_axi);
        hf |= HF_DDR_SCRUBBED;  // written by the test
      }
      if (hbm_ok && strcmp(memtest_what, "ddr")) {
        rc_mem |= memtest("hbm", HBM_AXI, HBM_SIZE);
        hf |= HF_HBM_SCRUBBED;
      }
      wr(R_HOST_FLAGS, hf);
    }
    if (scrub_mode == 1 || (scrub_mode == 0 && !(hf & HF_DDR_SCRUBBED))) {
      scrub("DDR4", 0, ddr_axi);
      hf |= HF_DDR_SCRUBBED;
      wr(R_HOST_FLAGS, hf);
    }
    if (hbm_ok && scrub_hbm && (scrub_mode == 1 || !(hf & HF_HBM_SCRUBBED))) {
      scrub("HBM", HBM_AXI, HBM_SIZE);
      hf |= HF_HBM_SCRUBBED;
      wr(R_HOST_FLAGS, hf);
    }
  }
  if (nloads == 0) {
    if (keep_running) info("no images: SoC left held");
    fpga_pci_detach(ocl);
    fpga_pci_detach(pcis);
    return rc_mem ? 1 : 0;
  }

  FILE *logf = log_path ? fopen(log_path, "wb") : NULL;
  if (use_stdin) fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);
  int rc = 2;
  const char *why = "timeout";
  int reboots = 0;
  uint64_t c0 = 0;
  double t0 = 0;

run_again:
  // ---- load, release ---------------------------------------------------
  // After a finisher reboot only the boot images are reloaded (Linux
  // reused that memory); anything in the pmem disk window keeps what the
  // guest wrote (OpenSBI writes the D$ back before the finisher).
  for (int k = 0; k < nloads; k++) {
    if (reboots && loads[k].addr >= PMEM_BASE && loads[k].addr < PMEM_END) {
      info("reboot: %s at 0x%" PRIx64 " (pmem window) kept, not reloaded", loads[k].path,
           loads[k].addr);
      continue;
    }
    load_image(&loads[k], verify_all);
  }
  if (have_mailbox) {
    uint8_t line[64] = {0};
    memcpy(line, &mailbox, 8);
    bar_copy(0x80080000ull - RAM_BASE, line, 64, false);
  }
  if (tohost) {
    if (tohost < RAM_BASE || tohost - RAM_BASE >= ram_size) die(3, "--tohost outside RAM");
    if (fpga_pci_poke64(pcis, tohost - RAM_BASE, 0) != 0) die(3, "tohost clear failed");
  }
  if (v4) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    const uint64_t ns = have_rtc ? rtc_ns : (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
    wr(R_RTC_LO, (uint32_t)ns);
    wr(R_RTC_HI, (uint32_t)(ns >> 32));  // commits
  }
  wr(R_BOOT_PC_LO, (uint32_t)boot_pc);
  wr(R_BOOT_PC_HI, (uint32_t)(boot_pc >> 32));
  if (console) {
    make_raw();
    info("console: Ctrl-] detaches%s", tty_raw ? "" : " (stdin is not a terminal)");
  }
  if (reboots == 0) {
    c0 = cycles();
    t0 = now_s();
  }
  wr(R_CTRL, ctrl_run);  // release (UART back-pressure on: no tx_drop)
  info("SoC released: boot PC 0x%" PRIx64 ", caches %s, timeout %g s%s", boot_pc,
       cache_en ? "on" : "off", timeout, reboots ? " (after reboot)" : "");

  // ---- console loop -----------------------------------------------------
  char tail[4096];
  size_t tlen = 0;
  rc = 2;
  why = "timeout";
  uint8_t rxbuf[256];
  size_t rxn = 0, rxi = 0;
  unsigned spin = 0;
  bool detached = false;
  double last_status = 0, fin_seen = 0;
  for (;;) {
    if (timeout > 0 && now_s() - t0 >= timeout) break;
    // Drain the UART (up to three bytes per read) while it has data.
    unsigned got = 0;
    if (v4) {
      for (int burst = 0; burst < 256; burst++) {
        const uint32_t d = rd(R_TX_DATA3);
        const unsigned n = (d >> 24) & 3u;
        if (!n) break;
        for (unsigned b = 0; b < n; b++) {
          const char ch = (char)(d >> (8 * b));
          fputc(ch, stdout);
          if (logf) fputc(ch, logf);
          if (tlen == sizeof tail - 1) {
            memmove(tail, tail + sizeof tail / 2, sizeof tail / 2 - 1);
            tlen = sizeof tail / 2 - 1;
          }
          tail[tlen++] = ch;
          tail[tlen] = 0;
          for (int m = 0; m < nexit && rc == 2; m++) {
            size_t L = strlen(exits[m]);
            if (tlen >= L && !memcmp(tail + tlen - L, exits[m], L)) { rc = 0; why = exits[m]; }
          }
          for (int m = 0; m < nfail && rc == 2; m++) {
            size_t L = strlen(fails[m]);
            if (tlen >= L && !memcmp(tail + tlen - L, fails[m], L)) { rc = 1; why = fails[m]; }
          }
        }
        got += n;
        if (n < 3) break;
      }
    } else {
      const uint32_t cnt = rd(R_TX_STATUS) & 0xFFFFu;
      for (uint32_t k = 0; k < cnt; k++) {
        const uint32_t d = rd(R_TX_DATA);
        if (!(d & 0x80000000u)) break;
        const char ch = (char)(d & 0xFF);
        fputc(ch, stdout);
        if (logf) fputc(ch, logf);
        if (tlen == sizeof tail - 1) {
          memmove(tail, tail + sizeof tail / 2, sizeof tail / 2 - 1);
          tlen = sizeof tail / 2 - 1;
        }
        tail[tlen++] = ch;
        tail[tlen] = 0;
        for (int m = 0; m < nexit && rc == 2; m++) {
          size_t L = strlen(exits[m]);
          if (tlen >= L && !memcmp(tail + tlen - L, exits[m], L)) { rc = 0; why = exits[m]; }
        }
        for (int m = 0; m < nfail && rc == 2; m++) {
          size_t L = strlen(fails[m]);
          if (tlen >= L && !memcmp(tail + tlen - L, fails[m], L)) { rc = 1; why = fails[m]; }
        }
        got++;
      }
    }
    if (got) fflush(stdout);
    if (rc != 2) break;
    // Keyboard / stdin -> UART RX.
    if (use_stdin) {
      if (rxi == rxn) {
        ssize_t r = read(0, rxbuf, sizeof rxbuf);
        rxn = r > 0 ? (size_t)r : 0;
        rxi = 0;
        if (console)
          for (size_t k = 0; k < rxn; k++)
            if (rxbuf[k] == 0x1d) {  // Ctrl-]
              rxn = k;
              detached = true;
            }
      }
      while (rxi < rxn && !(rd(R_RX_STATUS) & 0x80000000u)) wr(R_RX_DATA, rxbuf[rxi++]);
      if (detached && rxi == rxn) {
        rc = 4;
        why = "console detached (Ctrl-])";
        break;
      }
    }
    if (tohost) {
      uint64_t v = 0;
      fpga_pci_peek64(pcis, tohost - RAM_BASE, &v);
      if (v) {
        rc = v == 1 ? 0 : 1;
        why = v == 1 ? "tohost = 1" : "tohost fail";
        if (v != 1) fprintf(stderr, "[sigil_host] tohost = 0x%" PRIx64 " (test %" PRIu64 ")\n", v, v >> 1);
        break;
      }
    }
    // Status: errors, overflow, finisher (every 1 ms, or when idle).
    const double tn = now_s();
    if (!got || tn - last_status > 0.001) {
      last_status = tn;
      const uint32_t st = rd(R_STATUS);
      if (st & ST_MEM_ERR) {
        static bool reported;
        if (!reported && v4) {
          print_err_capture();
          reported = true;
        }
        if (!ignore_mem_err) {
          rc = 1;
          why = "memory error (STATUS.mem_err)";
          break;
        }
      }
      if (st & ST_TX_OVF) {
        rc = 1;
        why = "UART TX overflow";
        break;
      }
      if ((st & ST_FIN) && fin_seen == 0) fin_seen = tn;
      // Finisher: end once the UART has been quiet for 2 ms (Linux may
      // still have up to 16 bytes in the 16550 FIFO when it powers off).
      if (fin_seen > 0 && !(st & ST_TX_VALID) && !got && tn - fin_seen > 0.002) {
        const uint32_t fv = rd(R_FIN_VALUE);
        const uint32_t code = fv >> 16;
        if ((fv & 0xFFFF) == 0x7777) {
          reboots++;
          if (reboot_rerun && reboots <= 16) {
            restore_tty();
            fprintf(stderr, "\n[sigil_host] finisher: reboot (#%d) -- reloading and releasing again\n",
                    reboots);
            wr(R_CTRL, ctrl_run | CTRL_RESET_REQ);
            for (int k = 0; !(rd(R_STATUS) & ST_IN_RESET); k++)
              if (k > 100000) die(1, "SoC never entered reset");
            fin_seen = 0;
            goto run_again;
          }
          rc = 5;
          why = "finisher: reboot requested";
        } else if ((fv & 0xFFFF) == 0x5555) {
          rc = 0;
          why = "finisher: power off";
        } else {
          rc = 1;
          why = "finisher: fail";
          fprintf(stderr, "\n[sigil_host] finisher fail code %u (0x%08x)\n", code, fv);
        }
        break;
      }
      if (!got) {
        if (use_stdin) {
          struct pollfd pfd = {.fd = 0, .events = POLLIN};
          poll(&pfd, 1, ++spin < 64 ? 0 : 1);
        } else {
          sigil_usleep(++spin < 64 ? 20 : 200);
        }
      } else {
        spin = 0;
      }
    }
  }
  restore_tty();
  const uint64_t c1 = cycles();
  const double t1 = now_s();
  if (logf) fclose(logf);

  const double mhz = (double)(c1 - c0) / (t1 - t0) / 1e6;
  fprintf(stderr, "\n[sigil_host] result: %s (%s) after %.3f s, %" PRIu64 " core cycles%s\n",
          rc == 0 ? "PASS" : rc == 1 ? "FAIL" : rc == 2 ? "TIMEOUT" : rc == 4 ? "DETACHED" : "REBOOT",
          why, t1 - t0, c1 - c0, reboots ? "" : "");
  if (reboots) fprintf(stderr, "[sigil_host] reboots: %d\n", reboots);
  fprintf(stderr, "[sigil_host] measured core clock: %.3f MHz (cycle counter / wall time; "
          "expected %.3f MHz)\n", mhz, core_khz / 1000.0);
  fprintf(stderr, "[sigil_host] traps: %u, last cause 0x%08x%08x pc 0x%08x%08x, STATUS 0x%08x\n",
          rd(R_TRAP_COUNT), rd(R_TRAP_CAUSE_HI), rd(R_TRAP_CAUSE_LO), rd(R_TRAP_PC_HI),
          rd(R_TRAP_PC_LO), rd(R_STATUS));
  if (v4) print_err_capture();
  if (rc == 4 || keep_running) {
    // Leave the SoC running; drop UART bytes nobody drains.
    wr(R_CTRL, ctrl_run | (v4 ? CTRL_TX_DROP : 0));
    info("SoC left running (UART TX in drop mode until the next sigil_host run)");
  } else {
    wr(R_CTRL, ctrl_run | CTRL_RESET_REQ);
    for (int k = 0; !(rd(R_STATUS) & ST_IN_RESET); k++)
      if (k > 100000) break;
  }
  for (int k = 0; k < nsaves; k++) {
    if (rc == 4 || keep_running) info("note: --save while the SoC runs (its L1 D$ may hold newer data)");
    save_range(&saves[k]);
  }
  fpga_pci_detach(ocl);
  fpga_pci_detach(pcis);
  if (rc == 0 && rc_mem) rc = 1;
  return rc;
}
