/* hbm.c: one buffer in HBM, one in DDR4.  gcc -O2 hbm.c -lnuma -o hbm */
#include <numa.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  size_t size = 64 << 20;                      /* 64 MiB each */
  if (numa_available() < 0) return 1;
  char *hbm = numa_alloc_onnode(size, 1);      /* node 1 = HBM */
  char *ddr = numa_alloc_onnode(size, 0);      /* node 0 = DDR4 */
  if (!hbm || !ddr) return 1;
  memset(hbm, 1, size);                        /* pages are placed at first touch */
  memcpy(ddr, hbm, size);
  long long free_hbm;
  numa_node_size64(1, &free_hbm);
  printf("copied %zu MiB from HBM to DDR4, %lld MiB of HBM free\n", size >> 20, free_hbm >> 20);
  numa_free(hbm, size);
  numa_free(ddr, size);
  return 0;
}
