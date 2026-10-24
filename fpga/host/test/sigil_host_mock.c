// Host-side test build of sigil_host (#75): sigil_host.c compiled
// against a mock of the aws-fpga SDK and of the Sigil CL behind it (OCL
// registers, PCIS memory, memory engine, UART, test finisher), so the
// host flow -- argument and path handling, AFI/clock setup, hold, DDR4
// scrub, image loads, release, console loop, finisher, --save -- runs
// without an FPGA or the SDK. On Linux it is the real host build (BAR4
// mmap'd, multi-threaded copies, mmap'd image files); elsewhere the
// co-simulation seam (SV_TEST: SDK burst calls, no mmap). Driven by
// test_sigil_host.py (make -C fpga/host test).
//
// Environment:
//   MOCK_LOG=F           append one line per SDK / CL event to F
//   MOCK_CLK_KHZ=N       OCL CLK_KHZ, the AFI's core clock (default 100000)
//   MOCK_HOST_FLAGS=N    OCL HOST_FLAGS as the AFI load left it (default 0:
//                        DDR4 not scrubbed yet, so sigil_host scrubs)
//   MOCK_EXPECT=PA=F;... at release, compare SoC memory at PA with file F
//                        (and the zero padding up to a 64-byte line)
//   MOCK_STAMP=PA=TEXT   at release, report the bytes at PA, then write
//                        TEXT there (a guest writing to its pmem disk)
// At release the "SoC" reports its checks on the UART and powers off
// through the test finisher (0x5555), or fails with code 1 (0x10003333)
// on a mismatch.
#include "../sigil_host.c"  // defines _GNU_SOURCE first

#ifndef MAP_NORESERVE
#define MAP_NORESERVE 0
#endif
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif

#define MOCK_RAM_MB 81920u  // DDR4 64 GiB + HBM 16 GiB, as the F2 CL
#define MOCK_MEM_SIZE ((uint64_t)MOCK_RAM_MB << 20)
// 64-bit OCL register pairs kept by the mock (mock_regs64_lo/hi index).
enum { M_BOOT = 0, M_RTC = 1, M_BASE = 0, M_SIZE = 1, M_SEED = 2 };  // MEM_*: index 4 + M_*

static uint8_t *mock_mem;  // PCIS BAR4 offset = AXI address = PA - RAM_BASE
static bool mock_in_reset, mock_fin, mock_bar_ok[2];
static uint32_t mock_ctrl, mock_host_flags, mock_khz = 100000, mock_fin_value, mock_mem_status;
static uint32_t mock_scratch, mock_cycle_hi, mock_regs64_lo[8], mock_regs64_hi[8];
static char mock_uart[16384];
static size_t mock_uart_head, mock_uart_tail;
static double mock_t0;

static double mock_now(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void mock_log(const char *fmt, ...) {
  const char *path = getenv("MOCK_LOG");
  if (!path) return;
  FILE *f = fopen(path, "a");
  if (!f) return;
  va_list ap;
  va_start(ap, fmt);
  vfprintf(f, fmt, ap);
  va_end(ap);
  fputc('\n', f);
  fclose(f);
}

static void mock_uart_puts(const char *fmt, ...) {
  char line[512];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(line, sizeof line, fmt, ap);
  va_end(ap);
  for (const char *c = line; *c && mock_uart_tail < sizeof mock_uart; c++) mock_uart[mock_uart_tail++] = *c;
}

static void mock_init(void) {
  if (mock_mem) return;
  mock_t0 = mock_now();
  void *p = mmap(NULL, MOCK_MEM_SIZE, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
  if (p == MAP_FAILED) {
    perror("[mock] cannot reserve the SoC memory");
    exit(99);
  }
  mock_mem = p;
  const char *k = getenv("MOCK_CLK_KHZ");
  if (k) mock_khz = (uint32_t)strtoul(k, NULL, 0);
  const char *hf = getenv("MOCK_HOST_FLAGS");
  if (hf) mock_host_flags = (uint32_t)strtoul(hf, NULL, 0);
}

// Fresh zero pages over [off, off+len) (page-aligned), whatever the size.
static void mock_zero(uint64_t off, uint64_t len) {
  if (mmap(mock_mem + off, len, PROT_READ | PROT_WRITE,
           MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED, -1, 0) == MAP_FAILED) {
    perror("[mock] zero");
    exit(99);
  }
}

// ---- the SoC: checks the loaded images, writes the stamp, powers off ----
static bool mock_check_image(uint64_t pa, const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) {
    mock_uart_puts("MOCK SOC: cannot open expected image %s\r\n", path);
    return false;
  }
  const uint64_t off = pa - RAM_BASE;
  uint64_t n = 0, bad = 0, first_bad = 0;
  int c;
  while ((c = fgetc(f)) != EOF) {
    if (off + n >= MOCK_MEM_SIZE || mock_mem[off + n] != (uint8_t)c) {
      if (!bad++) first_bad = n;
    }
    n++;
  }
  fclose(f);
  for (uint64_t k = n; k % 64 && off + k < MOCK_MEM_SIZE; k++)  // zero padding to the line
    if (mock_mem[off + k] && !bad++) first_bad = k;
  if (bad)
    mock_uart_puts("MOCK SOC: 0x%" PRIx64 " MISMATCH vs %s: %" PRIu64 " bytes differ, first at +0x%" PRIx64
                   "\r\n", pa, path, bad, first_bad);
  else
    mock_uart_puts("MOCK SOC: 0x%" PRIx64 " ok (%" PRIu64 " bytes)\r\n", pa, n);
  mock_log("check 0x%" PRIx64 " %s", pa, bad ? "mismatch" : "ok");
  return bad == 0;
}

static void mock_release(void) {
  mock_log("release boot_pc 0x%08x%08x", mock_regs64_hi[M_BOOT], mock_regs64_lo[M_BOOT]);
  bool ok = true;
  const char *e = getenv("MOCK_EXPECT");
  if (e) {
    char *list = strdup(e), *save = NULL;
    for (char *t = strtok_r(list, ";", &save); t; t = strtok_r(NULL, ";", &save)) {
      char *eq = strchr(t, '=');
      if (!eq) continue;
      *eq = 0;
      ok &= mock_check_image(strtoull(t, NULL, 0), eq + 1);
    }
    free(list);
  }
  const char *st = getenv("MOCK_STAMP");
  if (st && strchr(st, '=')) {
    const uint64_t off = strtoull(st, NULL, 0) - RAM_BASE;
    const char *text = strchr(st, '=') + 1;
    const size_t n = strlen(text);
    char was[256];
    size_t k = 0;
    for (; k < n && k < sizeof was - 1; k++) {
      const uint8_t b = mock_mem[off + k];
      was[k] = b >= 0x20 && b < 0x7f ? (char)b : '.';
    }
    was[k] = 0;
    mock_uart_puts("MOCK SOC: stamp was '%s'\r\n", was);
    memcpy(mock_mem + off, text, n);
    mock_uart_puts("MOCK SOC: stamp now '%s'\r\n", text);
  }
  mock_uart_puts("MOCK SOC: %s, power off\r\n", ok ? "images ok" : "image check failed");
  mock_fin = true;
  mock_fin_value = ok ? 0x5555u : (1u << 16) | 0x3333u;
}

// ---- memory engine -------------------------------------------------------
static void mock_engine(uint32_t v) {
  if (!(v & 1u)) return;
  const uint64_t base = (uint64_t)mock_regs64_hi[4 + M_BASE] << 32 | mock_regs64_lo[4 + M_BASE];
  const uint64_t size = (uint64_t)mock_regs64_hi[4 + M_SIZE] << 32 | mock_regs64_lo[4 + M_SIZE];
  const uint64_t seed = (uint64_t)mock_regs64_hi[4 + M_SEED] << 32 | mock_regs64_lo[4 + M_SEED];
  const unsigned mode = (v >> 4) & 3u;
  if (!mock_in_reset) {  // the CL runs the engine only while the SoC is held
    mock_log("engine refused (SoC not held)");
    mock_mem_status = 0;
    return;
  }
  if (base + size > MOCK_MEM_SIZE || (base | size) & 4095) {
    mock_log("engine bad range 0x%" PRIx64 "+0x%" PRIx64, base, size);
    mock_mem_status = 2u | 4u;
    return;
  }
  if (mode == 0 && seed == 0) {
    mock_zero(base, size);
    mock_mem_status = 2u;
    mock_log("engine fill-zero 0x%" PRIx64 "+0x%" PRIx64, base, size);
  } else {  // address patterns / checks (--memtest) are not modelled
    mock_mem_status = 2u | 4u;
    mock_log("engine mode %u not modelled", mode);
  }
}

// ---- OCL registers -------------------------------------------------------
// 64-bit register pairs held by the mock: slot * 2 + (1 for the HI word),
// or -1 (the pairs are not all 8-byte aligned: MEM_BASE_LO is 0x0A4).
static int mock_slot(uint64_t off) {
  switch (off) {
    case R_BOOT_PC_LO: return 0;
    case R_BOOT_PC_HI: return 1;
    case R_RTC_LO: return 2 * M_RTC;
    case R_RTC_HI: return 2 * M_RTC + 1;
    case R_MEM_BASE_LO: return 2 * (4 + M_BASE);
    case R_MEM_BASE_HI: return 2 * (4 + M_BASE) + 1;
    case R_MEM_SIZE_LO: return 2 * (4 + M_SIZE);
    case R_MEM_SIZE_HI: return 2 * (4 + M_SIZE) + 1;
    case R_MEM_SEED_LO: return 2 * (4 + M_SEED);
    case R_MEM_SEED_HI: return 2 * (4 + M_SEED) + 1;
    default: return -1;
  }
}

static uint32_t mock_rd(uint64_t off) {
  const int s = mock_slot(off);
  if (s >= 0) return (s & 1) ? mock_regs64_hi[s / 2] : mock_regs64_lo[s / 2];
  switch (off) {
    case R_ID: return SIGIL_ID;
    case R_VERSION: return 0x00040001u;
    case R_CTRL: return mock_ctrl;
    case R_STATUS:
      return (mock_in_reset ? ST_IN_RESET : 0) | ST_DDR_READY | ST_HBM_READY | (mock_fin ? ST_FIN : 0) |
             (mock_uart_head < mock_uart_tail ? ST_TX_VALID : 0);
    case R_CYCLE_LO: {
      const uint64_t c = (uint64_t)((mock_now() - mock_t0) * mock_khz * 1000.0);
      mock_cycle_hi = (uint32_t)(c >> 32);
      return (uint32_t)c;
    }
    case R_CYCLE_HI: return mock_cycle_hi;
    case R_CLK_KHZ: return mock_khz;
    case R_HOST_FLAGS: return mock_host_flags;
    case R_SCRATCH: return mock_scratch;
    case R_TX_DATA3: {
      uint32_t d = 0, n = 0;
      while (n < 3 && mock_uart_head < mock_uart_tail) {
        d |= (uint32_t)(uint8_t)mock_uart[mock_uart_head++] << (8 * n);
        n++;
      }
      return d | n << 24;
    }
    case R_RAM_SIZE_MB: return MOCK_RAM_MB;
    case R_CAPS: return 1u | (1u << 4);  // HBM, AXI clock recipe H0
    case R_FIN_STATUS: return mock_fin ? 1u : 0u;
    case R_FIN_VALUE: return mock_fin_value;
    case R_RTC_INC: return 0;
    case R_MEM_CTRL: return mock_mem_status;
    default: return 0;  // TX_DATA/STATUS (no stale bytes), RX, traps, error capture
  }
}

static void mock_wr(uint64_t off, uint32_t v) {
  const int s = mock_slot(off);
  if (s >= 0) {
    if (s & 1) mock_regs64_hi[s / 2] = v;
    else mock_regs64_lo[s / 2] = v;
    return;
  }
  switch (off) {
    case R_CTRL:
      mock_ctrl = v;
      if (v & CTRL_RESET_REQ) {
        if (!mock_in_reset) mock_log("hold");
        mock_in_reset = true;
      } else if (mock_in_reset) {
        mock_in_reset = false;
        mock_release();
      }
      break;
    case R_HOST_FLAGS: mock_host_flags = v; break;
    case R_SCRATCH: mock_scratch = v; break;
    case R_MEM_CTRL: mock_engine(v); break;
    default: break;  // RTC_INC, RX_DATA
  }
}

// ---- the SDK -------------------------------------------------------------
int fpga_mgmt_init(void) {
  mock_init();
  mock_log("fpga_mgmt_init");
  return 0;
}
static void mock_image_info(int slot_id, struct fpga_mgmt_image_info *info) {
  memset(info, 0, sizeof *info);
  info->status = FPGA_STATUS_LOADED;
  info->slot_id = slot_id;
  snprintf(info->ids.afi_id, sizeof info->ids.afi_id, "agfi-0mock00000000000");
  info->sh_version = 0x10212415u;
}
int fpga_mgmt_describe_local_image(int slot_id, struct fpga_mgmt_image_info *info, uint32_t flags) {
  (void)flags;
  mock_image_info(slot_id, info);
  return 0;
}
int fpga_mgmt_load_local_image_sync(int slot_id, char *afi_id, uint32_t timeout, uint32_t delay_msec,
                                    struct fpga_mgmt_image_info *info) {
  (void)timeout;
  (void)delay_msec;
  mock_log("load AFI %s", afi_id);
  mock_host_flags = 0;
  mock_image_info(slot_id, info);
  return 0;
}
int aws_clkgen_set_recipe(int slot_id, uint32_t a, uint32_t b, uint32_t c, uint32_t hbm, uint32_t reset) {
  (void)slot_id;
  (void)reset;
  mock_log("clkgen recipe A%u B%u C%u H%u", a, b, c, hbm);
  return 0;
}
int aws_clkgen_deassert_resets(int slot_id) {
  (void)slot_id;
  mock_log("clkgen deassert resets");
  return 0;
}
int fpga_pci_attach(int slot_id, int pf_id, int bar_id, uint32_t flags, pci_bar_handle_t *handle) {
  (void)slot_id;
  (void)pf_id;
  (void)flags;
  mock_init();
  if (bar_id != APP_PF_BAR0 && bar_id != APP_PF_BAR4) return -1;
  mock_bar_ok[bar_id == APP_PF_BAR4] = true;
  *handle = bar_id;
  return 0;
}
int fpga_pci_detach(pci_bar_handle_t handle) {
  if (handle == APP_PF_BAR0 || handle == APP_PF_BAR4) mock_bar_ok[handle == APP_PF_BAR4] = false;
  return 0;
}
int fpga_pci_peek(pci_bar_handle_t handle, uint64_t offset, uint32_t *value) {
  if (handle != APP_PF_BAR0 || !mock_bar_ok[0] || (offset & 3)) return -1;
  *value = mock_rd(offset);
  return 0;
}
int fpga_pci_poke(pci_bar_handle_t handle, uint64_t offset, uint32_t value) {
  if (handle != APP_PF_BAR0 || !mock_bar_ok[0] || (offset & 3)) return -1;
  mock_wr(offset, value);
  return 0;
}
static bool mock_pcis(pci_bar_handle_t handle, uint64_t offset, uint64_t len) {
  return handle == APP_PF_BAR4 && mock_bar_ok[1] && offset <= MOCK_MEM_SIZE && len <= MOCK_MEM_SIZE - offset;
}
int fpga_pci_peek64(pci_bar_handle_t handle, uint64_t offset, uint64_t *value) {
  if (!mock_pcis(handle, offset, 8)) return -1;
  memcpy(value, mock_mem + offset, 8);
  return 0;
}
int fpga_pci_poke64(pci_bar_handle_t handle, uint64_t offset, uint64_t value) {
  if (!mock_pcis(handle, offset, 8)) return -1;
  memcpy(mock_mem + offset, &value, 8);
  return 0;
}
int fpga_pci_write_burst(pci_bar_handle_t handle, uint64_t offset, uint32_t *datap, uint64_t dword_len) {
  if (!mock_pcis(handle, offset, dword_len * 4)) return -1;
  memcpy(mock_mem + offset, datap, dword_len * 4);
  return 0;
}
int fpga_pci_get_address(pci_bar_handle_t handle, uint64_t offset, uint64_t dword_len, void **ptr) {
  if (!mock_pcis(handle, offset, dword_len * 4)) return -1;
  *ptr = mock_mem + offset;
  return 0;
}

#ifdef SV_TEST
// The co-simulation seam (cosim/sigil_host_cosim.h) on the wall clock.
double sigil_cosim_now_s(void) { return mock_now(); }
void sigil_cosim_usleep(unsigned us) { usleep(us); }
void sigil_cosim_exit(int code) { exit(code); }
#undef main
int main(int argc, char **argv) { return sigil_host_main(argc, argv); }
#endif
