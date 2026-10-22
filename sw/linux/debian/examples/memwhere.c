/* Where does my memory live? Allocates MiB with plain malloc, touches
 * every page, then asks the kernel (move_pages query) which NUMA node
 * each page is on. Run it as is (node 0, DDR4) or under numactl:
 *   ./memwhere 1024
 *   numactl --membind=1 ./memwhere 1024        # all in HBM
 *   numactl --interleave=0,1 ./memwhere 1024   # half and half
 * (link with -lnuma) */
#include <numaif.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  size_t mib = argc > 1 ? strtoul(argv[1], 0, 0) : 256, size = mib << 20;
  size_t npages = size / 4096, count[8] = {0}, other = 0;
  char *buf = malloc(size);
  void **pages = malloc(npages * sizeof *pages);
  int *status = malloc(npages * sizeof *status);
  if (!buf || !pages || !status) { printf("allocation failed\n"); return 1; }
  memset(buf, 1, size);
  for (size_t i = 0; i < npages; i++) pages[i] = buf + i * 4096;
  if (move_pages(0, npages, pages, NULL, status, 0) != 0) { perror("move_pages"); return 1; }
  for (size_t i = 0; i < npages; i++) {
    if (status[i] >= 0 && status[i] < 8) count[status[i]]++; else other++;
  }
  printf("%zu MiB malloc'd and touched:", mib);
  for (int n = 0; n < 8; n++)
    if (count[n]) printf(" node %d: %zu MiB", n, count[n] * 4096 >> 20);
  if (other) printf(" unknown: %zu pages", other);
  printf("\n");
  return 0;
}
