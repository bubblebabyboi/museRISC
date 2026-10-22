// XSIM co-simulation shim for the Sigil host runtime (issue #54).
// Implements the aws-fpga SDK calls sigil_host.c uses (fpga_mgmt,
// fpga_pci, fpga_clkgen) on top of DPI tasks exported by
// fpga/cl_sigil/verif/tests/test_sigil_host_cosim.sv, which drive the
// HDK Shell BFM: OCL (AppPF BAR0), PCIS (AppPF BAR4) and the SDA
// AWS_CLK_GEN registers. The same sigil_host.c main() then runs
// unchanged against the simulated CL. Arguments come from
// ../../../tests/sigil_host_cosim.args (one per line, relative to the
// XSIM run directory).
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <fpga_clkgen.h>
#include <fpga_mgmt.h>
#include <fpga_pci.h>

#include "svdpi.h"
#include "sigil_host_cosim.h"

// Exported from test_sigil_host_cosim.sv.
extern int sv_sigil_ocl_rd(unsigned int addr, unsigned int *data);
extern int sv_sigil_ocl_wr(unsigned int addr, unsigned int data);
extern int sv_sigil_pcis_rd64(unsigned long long addr, unsigned long long *data);
extern int sv_sigil_pcis_wr_line(unsigned long long addr, const svBitVecVal *data,
                                 const svBitVecVal *strb);
extern int sv_sigil_sleep_ns(int ns);
extern int sv_sigil_clkgen(int recipe_b);
extern long long sv_sigil_time_ps(void);

int sigil_host_main(int argc, char **argv);

static jmp_buf exit_jmp;
static int exit_code;

double sigil_cosim_now_s(void) { return (double)sv_sigil_time_ps() * 1e-12; }
void sigil_cosim_usleep(unsigned us) { sv_sigil_sleep_ns((int)(us * 1000u)); }
void sigil_cosim_exit(int code) {
  exit_code = code;
  longjmp(exit_jmp, 1);
}

// Called from the SV test: run sigil_host's main() with the argument file.
int sigil_host_cosim_main(void) {
  static char buf[4096];
  char *argv[64];
  int argc = 0;
  argv[argc++] = "sigil_host";
  FILE *f = fopen("../../../tests/sigil_host_cosim.args", "r");
  if (!f) {
    fprintf(stderr, "cosim: cannot open sigil_host_cosim.args\n");
    return 3;
  }
  size_t n = fread(buf, 1, sizeof buf - 1, f);
  fclose(f);
  buf[n] = 0;
  for (char *line = strtok(buf, "\n"); line && argc < 63; line = strtok(NULL, "\n"))
    if (line[0] && line[0] != '#') argv[argc++] = line;
  argv[argc] = NULL;
  if (setjmp(exit_jmp) == 0) exit_code = sigil_host_main(argc, argv);
  fflush(stdout);
  fflush(stderr);
  return exit_code;
}

// ---- fpga_mgmt / fpga_clkgen ------------------------------------------------
int fpga_mgmt_init(void) { return 0; }
int fpga_mgmt_load_local_image_sync(int slot_id, char *afi_id, uint32_t timeout,
                                    uint32_t delay_msec, struct fpga_mgmt_image_info *info) {
  (void)slot_id; (void)afi_id; (void)timeout; (void)delay_msec; (void)info;
  return 0;  // the testbench "loads" the CL at power-up
}
int fpga_mgmt_describe_local_image(int slot_id, struct fpga_mgmt_image_info *info,
                                   uint32_t flags) {
  (void)flags;
  memset(info, 0, sizeof *info);
  info->status = FPGA_STATUS_LOADED;
  info->slot_id = slot_id;
  snprintf(info->ids.afi_id, sizeof info->ids.afi_id, "xsim-cl_sigil");
  info->sh_version = 0x10212415;
  return 0;
}
int aws_clkgen_set_recipe(int slot_id, uint32_t a, uint32_t b, uint32_t c, uint32_t hbm,
                          uint32_t reset) {
  (void)slot_id; (void)a; (void)c; (void)hbm; (void)reset;
  return sv_sigil_clkgen((int)b) == 0 ? 0 : -1;
}
int aws_clkgen_deassert_resets(int slot_id) {
  (void)slot_id;
  return sv_sigil_clkgen(-1) == 0 ? 0 : -1;
}

// ---- fpga_pci: handle = BAR number (0 = OCL, 4 = PCIS) ----------------------
int fpga_pci_attach(int slot_id, int pf_id, int bar_id, uint32_t flags,
                    pci_bar_handle_t *handle) {
  (void)slot_id; (void)pf_id; (void)flags;
  *handle = bar_id;
  return 0;
}
int fpga_pci_detach(pci_bar_handle_t handle) { (void)handle; return 0; }

static int pcis_write(uint64_t off, const uint8_t *src, size_t len) {
  while (len) {
    const uint64_t line = off & ~63ull;
    const size_t o = (size_t)(off - line);
    const size_t n = len < 64 - o ? len : 64 - o;
    svBitVecVal data[16] = {0}, strb[2] = {0};
    uint8_t bytes[64] = {0};
    memcpy(bytes + o, src, n);
    memcpy(data, bytes, 64);
    for (size_t k = o; k < o + n; k++) strb[k / 32] |= 1u << (k % 32);
    sv_sigil_pcis_wr_line(line, data, strb);
    off += n; src += n; len -= n;
  }
  return 0;
}

int fpga_pci_peek(pci_bar_handle_t handle, uint64_t offset, uint32_t *value) {
  if (handle == 0) {
    unsigned int v = 0;
    sv_sigil_ocl_rd((unsigned)offset, &v);
    *value = v;
    return 0;
  }
  unsigned long long v = 0;
  sv_sigil_pcis_rd64(offset & ~7ull, &v);
  *value = (uint32_t)(v >> (8 * (offset & 4)));
  return 0;
}
int fpga_pci_poke(pci_bar_handle_t handle, uint64_t offset, uint32_t value) {
  if (handle == 0) return sv_sigil_ocl_wr((unsigned)offset, value), 0;
  return pcis_write(offset, (const uint8_t *)&value, 4);
}
int fpga_pci_peek64(pci_bar_handle_t handle, uint64_t offset, uint64_t *value) {
  if (handle == 0) return -1;
  unsigned long long v = 0;
  sv_sigil_pcis_rd64(offset, &v);
  *value = v;
  return 0;
}
int fpga_pci_poke64(pci_bar_handle_t handle, uint64_t offset, uint64_t value) {
  if (handle == 0) return -1;
  return pcis_write(offset, (const uint8_t *)&value, 8);
}
int fpga_pci_write_burst(pci_bar_handle_t handle, uint64_t offset, uint32_t *datap,
                         uint64_t dword_len) {
  if (handle == 0) return -1;
  return pcis_write(offset, (const uint8_t *)datap, (size_t)dword_len * 4);
}
