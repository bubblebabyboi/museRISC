// Sigil F2 host runtime (issue #54, FPGA F3). Runs on an AWS EC2 F2
// instance against the aws-fpga SDK (fpga_mgmt / fpga_pci /
// fpga_clkgen), with the Sigil AFI (fpga/cl_sigil) loaded or loadable.
//
//   sigil_host [options] --linux --fw fw_jump.bin --image Image --dtb sigil.dtb
//   sigil_host [options] --bin firmware.bin          (baremetal at 0x8000_0000)
//   sigil_host [options] --load 0xADDR=FILE ...      (any layout)
//
// Flow: (load AFI) -> AWS_CLK_GEN clock recipe / reset release ->
// hold the SoC in reset (OCL CTRL) -> wait for DDR -> copy the images
// into DDR through PCIS (AppPF BAR4; SoC 0x8000_0000 + x = DDR x) ->
// set the boot PC -> release -> stream the virtual UART to stdout
// (and stdin to the UART RX when --stdin) until an exit marker, a
// failure marker, the riscv-tests tohost word (--tohost) or the
// timeout -> report the measured core clock = delta(cycle counter) /
// delta(wall time).
//
// Register map: docs/FPGA_F2.md "F3" (rtl/fpga/sigil_ocl_regs.sv).
// Exit status: 0 pass, 1 fail marker / tohost fail / hardware error,
// 2 timeout, 3 setup error.
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <fpga_clkgen.h>
#include <fpga_mgmt.h>
#include <fpga_pci.h>

// OCL registers (byte offsets in AppPF BAR0).
enum {
  R_ID = 0x000, R_VERSION = 0x004, R_CTRL = 0x008, R_STATUS = 0x00C,
  R_BOOT_PC_LO = 0x010, R_BOOT_PC_HI = 0x014, R_CYCLE_LO = 0x018,
  R_CYCLE_HI = 0x01C, R_TRAP_COUNT = 0x020, R_CLK_KHZ = 0x024,
  R_TRAP_CAUSE_LO = 0x028, R_TRAP_CAUSE_HI = 0x02C, R_TRAP_PC_LO = 0x030,
  R_TRAP_PC_HI = 0x034, R_SCRATCH = 0x03C, R_TX_DATA = 0x040,
  R_TX_STATUS = 0x044, R_RX_DATA = 0x048, R_RX_STATUS = 0x04C,
};
enum {
  CTRL_RESET_REQ = 1u << 0, CTRL_CACHE_EN = 1u << 1,
  ST_IN_RESET = 1u << 0, ST_MEM_ERR = 1u << 1, ST_TX_OVF = 1u << 2,
  ST_RX_FULL = 1u << 3, ST_TRAP_SEEN = 1u << 4, ST_TX_VALID = 1u << 5,
  ST_DDR_READY = 1u << 6,
};
#define SIGIL_ID 0x5349474Cu  // "SIGL"
#define RAM_BASE 0x80000000ull
#define RAM_SIZE 0x08000000ull  // 128 MiB, sw/linux/sigil.dts
#define MAX_LOADS 8
#define MAX_MARKERS 16

#ifdef SV_TEST
// HDK XSIM co-simulation build (fpga/host/cosim/): the SDK calls are
// served by the Shell BFM through DPI, time is simulation time.
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
static int verbose = 1;

static void info(const char *fmt, ...) {
  if (!verbose) return;
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "[sigil_host] ");
  vfprintf(stderr, fmt, ap);
  fputc('\n', stderr);
  va_end(ap);
}
static void die(int code, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "[sigil_host] ERROR: ");
  vfprintf(stderr, fmt, ap);
  fputc('\n', stderr);
  va_end(ap);
  sigil_exit(code);
}

static uint32_t rd(uint64_t off) {
  uint32_t v = 0;
  if (fpga_pci_peek(ocl, off, &v) != 0) die(3, "OCL read 0x%03" PRIx64 " failed", off);
  return v;
}
static void wr(uint64_t off, uint32_t v) {
  if (fpga_pci_poke(ocl, off, v) != 0) die(3, "OCL write 0x%03" PRIx64 " failed", off);
}
static uint64_t cycles(void) {
  uint32_t lo = rd(R_CYCLE_LO);  // snapshots the upper half
  uint32_t hi = rd(R_CYCLE_HI);
  return ((uint64_t)hi << 32) | lo;
}
struct load { uint64_t addr; const char *path; };

static uint8_t *read_file(const char *path, size_t *len) {
  FILE *f = fopen(path, "rb");
  if (!f) die(3, "cannot open %s: %s", path, strerror(errno));
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  size_t cap = ((size_t)n + 63) & ~(size_t)63;  // whole 64-byte lines
  uint8_t *buf = calloc(1, cap ? cap : 64);
  if (!buf || fread(buf, 1, (size_t)n, f) != (size_t)n) die(3, "cannot read %s", path);
  fclose(f);
  *len = (size_t)n;
  return buf;
}

// Copy one image into DDR through PCIS and spot-check it.
static void load_image(const struct load *l, bool verify_all) {
  size_t n;
  uint8_t *buf = read_file(l->path, &n);
  if (l->addr < RAM_BASE || l->addr + n > RAM_BASE + RAM_SIZE || (l->addr & 63))
    die(3, "%s: 0x%" PRIx64 "+%zu outside the 128 MiB RAM window or not 64-byte aligned",
        l->path, l->addr, n);
  const uint64_t ddr = l->addr - RAM_BASE;  // bridge DDR_BASE = 0
  const size_t words = ((n + 63) & ~(size_t)63) / 4;
  const double t0 = now_s();
  const size_t chunk = 1u << 16;  // dwords per burst call
  for (size_t w = 0; w < words; w += chunk) {
    size_t c = words - w < chunk ? words - w : chunk;
    if (fpga_pci_write_burst(pcis, ddr + 4 * w, (uint32_t *)buf + w, c) != 0)
      die(3, "PCIS write at DDR 0x%" PRIx64 " failed", ddr + 4 * w);
  }
  const double t1 = now_s();
  // Read back (all of it with --verify, else the first and last 4 KiB).
  size_t bad = 0;
  for (size_t w = 0; w < words; w += 2) {
    if (!verify_all && w >= 1024 && w + 1024 < words) { w = words - 1024; w &= ~(size_t)1; }
    uint64_t v;
    if (fpga_pci_peek64(pcis, ddr + 4 * w, &v) != 0) die(3, "PCIS read failed");
    uint64_t e;
    memcpy(&e, buf + 4 * w, 8);
    if (v != e && bad++ < 4)
      fprintf(stderr, "[sigil_host] verify %s +0x%zx: 0x%016" PRIx64 " != 0x%016" PRIx64 "\n",
              l->path, 4 * w, v, e);
  }
  if (bad) die(1, "%s: %zu mismatching words after load", l->path, bad);
  info("loaded %s: %zu bytes at 0x%" PRIx64 " (DDR 0x%" PRIx64 ") in %.3f s, %s verified",
       l->path, n, l->addr, ddr, t1 - t0, verify_all ? "fully" : "head/tail");
  free(buf);
}

static void usage(const char *p) {
  fprintf(stderr,
"usage: %s [options] (--linux --fw F --image F --dtb F | --bin F | --load 0xADDR=F ...)\n"
"  -S N               FPGA slot (default 0)\n"
"  --afi agfi-...     load this AFI first (else it must already be loaded)\n"
"  --recipe-b N       program AWS_CLK_GEN group B recipe N (0..5; 1 = 62.5 MHz,\n"
"                     5 = 100 MHz) instead of keeping the AFI's build recipe\n"
"  --linux            OpenSBI fw_jump (--fw) at 0x80000000, Linux --image at\n"
"                     0x80200000, --dtb at 0x83000000 [--initrd F at 0x84000000]\n"
"  --bin F            baremetal image at 0x80000000 (boot ROM jumps there)\n"
"  --load 0xADDR=F    image at SoC address ADDR (repeatable)\n"
"  --boot-pc 0xADDR   reset PC (default 0x1000, the boot ROM)\n"
"  --no-cache         L1 caches off\n"
"  --exit TEXT        pass marker (repeatable; default: LINUX_BOOT_OK (matches\n"
"                     SIGIL_LINUX_BOOT_OK and older payloads), SOC CRYPTO PASS,\n"
"                     SOC HASH PASS, FPGA SMOKE PASS, HELLO FROM S-MODE)\n"
"  --fail TEXT        failure marker (repeatable; default: FAIL, Kernel panic)\n"
"  --tohost 0xADDR    riscv-tests HTIF: poll this RAM word (use --no-cache)\n"
"  --timeout S        seconds (default 60)\n"
"  --stdin            forward stdin to the UART RX\n"
"  --log F            also write the UART stream to F\n"
"  --verify           read every loaded word back (default: head/tail)\n"
"  --keep-running     leave the SoC running on exit (default: hold in reset)\n"
"  --ignore-mem-err   do not stop on STATUS.mem_err (workaround: the first\n"
"                     AFI sets it early in every run without affecting\n"
"                     results; root cause tracked in issue #62)\n"
"  -q                 quiet (UART output only)\n", p);
  sigil_exit(3);
}

int main(int argc, char **argv) {
  int slot = 0, recipe_b = -1;
  const char *afi = NULL, *fw = NULL, *image = NULL, *dtb = NULL, *initrd = NULL;
  const char *log_path = NULL;
  bool linux_mode = false, cache_en = true, use_stdin = false, verify_all = false;
  bool keep_running = false;
  bool ignore_mem_err = false;
  uint64_t boot_pc = 0x1000, tohost = 0;
  double timeout = 60;
  struct load loads[MAX_LOADS];
  int nloads = 0;
  const char *exits[MAX_MARKERS], *fails[MAX_MARKERS];
  int nexit = 0, nfail = 0;

  for (int i = 1; i < argc; i++) {
    const char *a = argv[i];
    const char *v = i + 1 < argc ? argv[i + 1] : NULL;
#define NEXT() do { if (!v) usage(argv[0]); i++; } while (0)
    if (!strcmp(a, "-S")) { NEXT(); slot = atoi(v); }
    else if (!strcmp(a, "--afi")) { NEXT(); afi = v; }
    else if (!strcmp(a, "--recipe-b")) { NEXT(); recipe_b = atoi(v); }
    else if (!strcmp(a, "--linux")) linux_mode = true;
    else if (!strcmp(a, "--fw")) { NEXT(); fw = v; }
    else if (!strcmp(a, "--image")) { NEXT(); image = v; }
    else if (!strcmp(a, "--dtb")) { NEXT(); dtb = v; }
    else if (!strcmp(a, "--initrd")) { NEXT(); initrd = v; }
    else if (!strcmp(a, "--bin")) {
      NEXT();
      if (nloads == MAX_LOADS) usage(argv[0]);
      loads[nloads++] = (struct load){RAM_BASE, v};
    } else if (!strcmp(a, "--load")) {
      NEXT();
      const char *eq = strchr(v, '=');
      if (!eq || nloads == MAX_LOADS) usage(argv[0]);
      loads[nloads++] = (struct load){strtoull(v, NULL, 0), eq + 1};
    }
    else if (!strcmp(a, "--boot-pc")) { NEXT(); boot_pc = strtoull(v, NULL, 0); }
    else if (!strcmp(a, "--no-cache")) cache_en = false;
    else if (!strcmp(a, "--exit")) { NEXT(); if (nexit < MAX_MARKERS) exits[nexit++] = v; }
    else if (!strcmp(a, "--fail")) { NEXT(); if (nfail < MAX_MARKERS) fails[nfail++] = v; }
    else if (!strcmp(a, "--tohost")) { NEXT(); tohost = strtoull(v, NULL, 0); }
    else if (!strcmp(a, "--timeout")) { NEXT(); timeout = atof(v); }
    else if (!strcmp(a, "--stdin")) use_stdin = true;
    else if (!strcmp(a, "--log")) { NEXT(); log_path = v; }
    else if (!strcmp(a, "--verify")) verify_all = true;
    else if (!strcmp(a, "--keep-running")) keep_running = true;
    else if (!strcmp(a, "--ignore-mem-err")) ignore_mem_err = true;
    else if (!strcmp(a, "-q")) verbose = 0;
    else usage(argv[0]);
#undef NEXT
  }
  if (linux_mode) {
    if (!fw || !image || !dtb || nloads + 4 > MAX_LOADS) usage(argv[0]);
    loads[nloads++] = (struct load){0x80000000ull, fw};
    loads[nloads++] = (struct load){0x80200000ull, image};
    loads[nloads++] = (struct load){0x83000000ull, dtb};
    if (initrd) loads[nloads++] = (struct load){0x84000000ull, initrd};
  }
  if (nloads == 0) usage(argv[0]);
  if (nexit == 0) {
    static const char *dflt[] = {"LINUX_BOOT_OK", "SOC CRYPTO PASS", "SOC HASH PASS",
                                 "FPGA SMOKE PASS", "HELLO FROM S-MODE"};
    for (size_t k = 0; k < sizeof dflt / sizeof *dflt; k++) exits[nexit++] = dflt[k];
  }
  if (nfail == 0) {
    fails[nfail++] = "FAIL";
    fails[nfail++] = "Kernel panic";
  }

  // ---- FPGA / AFI / clocks ------------------------------------------
  if (fpga_mgmt_init() != 0) die(3, "fpga_mgmt_init failed (run as root on an F2 instance?)");
  if (afi) {
    struct fpga_mgmt_image_info img;
    memset(&img, 0, sizeof img);
    info("loading %s into slot %d", afi, slot);
    if (fpga_mgmt_load_local_image_sync(slot, (char *)afi, 120, 1000, &img) != 0)
      die(3, "AFI load failed");
  }
  {
    struct fpga_mgmt_image_info img;
    memset(&img, 0, sizeof img);
    if (fpga_mgmt_describe_local_image(slot, &img, 0) != 0) die(3, "describe slot %d failed", slot);
    if (img.status != FPGA_STATUS_LOADED) die(3, "slot %d: no AFI loaded (status %d)", slot, img.status);
    info("slot %d: AFI %s, shell 0x%08x", slot, img.ids.afi_id, img.sh_version);
  }
  if (recipe_b >= 0) {
    // Groups A/C/HBM are unused by the SoC: HDK defaults A1, C0, H2.
    info("AWS_CLK_GEN: group B recipe B%d (A1 C0 H2 for the unused groups)", recipe_b);
    if (aws_clkgen_set_recipe(slot, 1, (uint32_t)recipe_b, 0, 2, 0) != 0)
      die(3, "aws_clkgen_set_recipe failed");
  } else if (aws_clkgen_deassert_resets(slot) != 0) {
    die(3, "aws_clkgen_deassert_resets failed");
  }
  if (fpga_pci_attach(slot, FPGA_APP_PF, APP_PF_BAR0, 0, &ocl) != 0) die(3, "attach OCL BAR0 failed");
  if (fpga_pci_attach(slot, FPGA_APP_PF, APP_PF_BAR4, BURST_CAPABLE, &pcis) != 0)
    die(3, "attach PCIS BAR4 failed");

  const uint32_t id = rd(R_ID);
  if (id != SIGIL_ID) die(3, "OCL ID 0x%08x is not the Sigil CL (0x%08x)", id, SIGIL_ID);
  const uint32_t khz = rd(R_CLK_KHZ);
  info("Sigil CL version 0x%08x, build clock recipe %.3f MHz", rd(R_VERSION), khz / 1000.0);

  // ---- hold, load, release -------------------------------------------
  const uint32_t ctrl_run = cache_en ? CTRL_CACHE_EN : 0;
  wr(R_CTRL, ctrl_run | CTRL_RESET_REQ);
  for (int k = 0; !(rd(R_STATUS) & ST_IN_RESET); k++)
    if (k > 100000) die(1, "SoC never entered reset");
  unsigned stale = 0;
  while (rd(R_TX_DATA) & 0x80000000u) stale++;
  if (stale) info("discarded %u UART bytes from a previous run", stale);
  for (int k = 0; !(rd(R_STATUS) & ST_DDR_READY); k++) {
    if (k > 1000) die(3, "DDR not ready (STATUS 0x%08x)", rd(R_STATUS));
    sigil_usleep(1000);
  }
  for (int k = 0; k < nloads; k++) load_image(&loads[k], verify_all);
  if (tohost) {
    if (tohost < RAM_BASE || tohost >= RAM_BASE + RAM_SIZE) die(3, "--tohost outside RAM");
    if (fpga_pci_poke64(pcis, tohost - RAM_BASE, 0) != 0) die(3, "tohost clear failed");
  }
  wr(R_BOOT_PC_LO, (uint32_t)boot_pc);
  wr(R_BOOT_PC_HI, (uint32_t)(boot_pc >> 32));

  FILE *logf = log_path ? fopen(log_path, "wb") : NULL;
  if (use_stdin) fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);

  const uint64_t c0 = cycles();
  const double t0 = now_s();
  wr(R_CTRL, ctrl_run);  // release
  info("SoC released: boot PC 0x%" PRIx64 ", caches %s, timeout %g s", boot_pc,
       cache_en ? "on" : "off", timeout);

  // ---- console loop -----------------------------------------------------
  char tail[4096];
  size_t tlen = 0;
  int rc = 2;
  const char *why = "timeout";
  uint8_t rxbuf[256];
  size_t rxn = 0, rxi = 0;
  unsigned idle = 0;
  while (now_s() - t0 < timeout) {
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
    }
    if (cnt) fflush(stdout);
    if (rc != 2) break;
    if (use_stdin) {
      if (rxi == rxn) {
        ssize_t r = read(0, rxbuf, sizeof rxbuf);
        rxn = r > 0 ? (size_t)r : 0;
        rxi = 0;
      }
      while (rxi < rxn && !(rd(R_RX_STATUS) & 0x80000000u)) wr(R_RX_DATA, rxbuf[rxi++]);
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
    if (++idle % 64 == 0) {
      const uint32_t st = rd(R_STATUS);
      if (st & (ignore_mem_err ? ST_TX_OVF : (ST_MEM_ERR | ST_TX_OVF))) {
        rc = 1;
        why = st & ST_MEM_ERR ? "AXI error (STATUS.mem_err)" : "UART TX overflow";
        break;
      }
    }
    if (!cnt) sigil_usleep(200);
  }
  const uint64_t c1 = cycles();
  const double t1 = now_s();
  if (logf) fclose(logf);

  const double mhz = (double)(c1 - c0) / (t1 - t0) / 1e6;
  fprintf(stderr, "\n[sigil_host] result: %s (%s) after %.3f s, %" PRIu64 " core cycles\n",
          rc == 0 ? "PASS" : rc == 1 ? "FAIL" : "TIMEOUT", why, t1 - t0, c1 - c0);
  fprintf(stderr, "[sigil_host] measured core clock: %.3f MHz (cycle counter / wall time; "
          "build recipe %.3f MHz)\n", mhz, khz / 1000.0);
  fprintf(stderr, "[sigil_host] traps: %u, last cause 0x%08x%08x pc 0x%08x%08x, STATUS 0x%08x\n",
          rd(R_TRAP_COUNT), rd(R_TRAP_CAUSE_HI), rd(R_TRAP_CAUSE_LO), rd(R_TRAP_PC_HI),
          rd(R_TRAP_PC_LO), rd(R_STATUS));
  if (!keep_running) wr(R_CTRL, ctrl_run | CTRL_RESET_REQ);
  fpga_pci_detach(ocl);
  fpga_pci_detach(pcis);
  return rc;
}
