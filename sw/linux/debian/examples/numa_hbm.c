/* DDR4 vs HBM on Sigil: node 0 is DDR4 (the CPU's node, default for
 * malloc), node 1 is the 16 GiB HBM (no CPUs). Allocates a buffer on
 * each node with libnuma, checks where the pages really landed
 * (move_pages query), and times a write pass and a dependent-load
 * (pointer-chasing) pass on each.
 *   ./numa_hbm [MiB per node, default 64]      (link with -lnuma) */
#include <numa.h>
#include <numaif.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

static int check_node(void *buf, size_t size, int want) {
  size_t npages = size / 4096, bad = 0;
  void **pages = malloc(npages * sizeof *pages);
  int *status = malloc(npages * sizeof *status);
  for (size_t i = 0; i < npages; i++) pages[i] = (char *)buf + i * 4096;
  if (numa_move_pages(0, npages, pages, NULL, status, 0) != 0) {
    perror("move_pages");
    return -1;
  }
  for (size_t i = 0; i < npages; i++) bad += status[i] != want;
  free(pages); free(status);
  return (int)bad;
}

static void bench(int node, size_t size) {
  uint64_t *buf = numa_alloc_onnode(size, node);
  if (!buf) { printf("node %d: allocation failed\n", node); exit(1); }
  double t0 = now();
  memset(buf, 0, size);                       /* first touch: placement */
  double t1 = now();
  int bad = check_node(buf, size, node);
  /* random cyclic permutation over 64-byte lines -> dependent loads */
  size_t lines = size / 64, steps = lines < 1000000 ? lines : 1000000;
  size_t *perm = malloc(lines * sizeof *perm);
  for (size_t i = 0; i < lines; i++) perm[i] = i;
  srand(1);
  for (size_t i = lines - 1; i > 0; i--) {
    size_t j = (size_t)rand() % (i + 1), t = perm[i];
    perm[i] = perm[j]; perm[j] = t;
  }
  for (size_t i = 0; i < lines; i++)
    buf[perm[i] * 8] = perm[(i + 1) % lines] * 8;
  free(perm);
  double t2 = now();
  uint64_t p = 0;
  for (size_t i = 0; i < steps; i++) p = buf[p];
  double t3 = now();
  printf("node %d: %zu MiB, pages on node %d: %s, write %.0f MB/s, "
         "dependent load %.0f ns (%llu)\n", node, size >> 20, node,
         bad == 0 ? "all" : "NOT ALL", size / (t1 - t0) / 1e6,
         (t3 - t2) / steps * 1e9, (unsigned long long)(p & 1));
  numa_free(buf, size);
  if (bad) exit(1);
}

int main(int argc, char **argv) {
  size_t mib = argc > 1 ? strtoul(argv[1], 0, 0) : 64;
  if (numa_available() < 0) { printf("NUMA not available\n"); return 1; }
  int maxn = numa_max_node();
  for (int n = 0; n <= maxn; n++) {
    long long free_b, size = numa_node_size64(n, &free_b);
    printf("node %d: %.1f GiB total, %.1f GiB free%s\n", n, size / 1073741824.0,
           free_b / 1073741824.0, n == 0 ? " (DDR4, CPU node)" : " (HBM)");
  }
  for (int n = 0; n <= maxn; n++) bench(n, mib << 20);
  printf("NUMA OK (%d nodes)\n", maxn + 1);
  return 0;
}
