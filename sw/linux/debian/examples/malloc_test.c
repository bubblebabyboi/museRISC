/* glibc malloc/free/realloc smoke test: many small blocks (brk heap),
 * a few large ones (mmap), then one big block touched page by page.
 *   ./malloc_test [big MiB, default 256] */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t rnd = 88172645463325252ull;
static uint64_t xorshift(void) {
  rnd ^= rnd << 13; rnd ^= rnd >> 7; rnd ^= rnd << 17;
  return rnd;
}

int main(int argc, char **argv) {
  enum { N = 20000 };
  static unsigned char *blk[N];
  static size_t len[N];
  size_t total = 0, big_mib = argc > 1 ? strtoul(argv[1], 0, 0) : 256;

  for (int i = 0; i < N; i++) {
    len[i] = (i % 1000 == 0) ? (1u << 20) + xorshift() % (1u << 20)  /* mmap */
                             : 1 + xorshift() % 2048;                /* heap */
    blk[i] = malloc(len[i]);
    if (!blk[i]) { printf("MALLOC FAIL: block %d\n", i); return 1; }
    memset(blk[i], i & 0xff, len[i]);
    total += len[i];
  }
  for (int i = 0; i < N; i += 2) {             /* grow half of them */
    size_t n = len[i] * 2;
    unsigned char *p = realloc(blk[i], n);
    if (!p) { printf("MALLOC FAIL: realloc %d\n", i); return 1; }
    memset(p + len[i], i & 0xff, n - len[i]);
    blk[i] = p; total += n - len[i]; len[i] = n;
  }
  for (int i = 0; i < N; i++) {
    for (size_t j = 0; j < len[i]; j += 97)
      if (blk[i][j] != (i & 0xff)) { printf("MALLOC FAIL: data %d\n", i); return 1; }
    free(blk[i]);
  }
  printf("%d blocks, %.1f MiB allocated, written, verified, freed\n", N,
         total / 1048576.0);

  size_t big = big_mib << 20;
  unsigned char *p = malloc(big);
  if (!p) { printf("MALLOC FAIL: %zu MiB\n", big_mib); return 1; }
  for (size_t j = 0; j < big; j += 4096) p[j] = (unsigned char)(j >> 12);
  for (size_t j = 0; j < big; j += 4096)
    if (p[j] != (unsigned char)(j >> 12)) { printf("MALLOC FAIL: big\n"); return 1; }
  free(p);
  printf("big block %zu MiB touched and verified\nMALLOC OK\n", big_mib);
  return 0;
}
