// Unit test of sigil_host's DTB helpers: the timebase check / fix and the
// /chosen/rng-seed fill, run on real DTBs.
//   test_fdt KHZ FIX IN.dtb OUT.dtb   (FIX 1 = default, 0 = --keep-timebase)
#define main sigil_host_main_unused
#include "sigil_host.c"
#undef main
int main(int argc, char **argv) {
  if (argc != 5) return 2;
  core_khz = (uint32_t)atoi(argv[1]);
  keep_timebase = !atoi(argv[2]);
  FILE *f = fopen(argv[3], "rb");
  if (!f) return 2;
  static uint8_t buf[1 << 20];
  size_t n = fread(buf, 1, sizeof buf, f);
  fclose(f);
  fdt_check_timebase(argv[3], buf, n);
  struct fdt_timebase t = {0};
  fdt_walk(buf, n, fdt_timebase_prop, &t);
  printf("after: timebase %u (%u copies)\n", t.found, t.n_found);
  size_t k = fdt_fill_rng_seed(buf, n);
  printf("rng-seed bytes filled: %zu\n", k);
  f = fopen(argv[4], "wb");
  if (!f || fwrite(buf, 1, n, f) != n) return 2;
  fclose(f);
  return 0;
}
