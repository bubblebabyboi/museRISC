// ptwstress: user-space reproducer for the Sigil fetch-walk preemption
// bug (issue #73 oops hunt; core tests ptw_preempt_*_directed.S).
//
// The data region D lives under its own Sv39 root entry (VA
// 0x20_0000_0000, root index 128), the program text under root[0]. Each
// pass first thrashes the TLB and the D$ (reads a 512 KiB region under
// a third root entry), then runs ptw_chain (ptwstress_gadgets.S): a
// chain of 4 KiB code pages that each end with a load from a new D page,
// so a fetch walk (next code page) and a data walk (new D page) collide
// at every page crossing. On a correct core every load returns its
// expected value (word at VA x holds x ^ KEY) and the pass takes no page
// faults (D is MAP_POPULATE'd). On the affected RTL a data walk can
// consume the fetch walk's root[0] PTE: it then follows the text's own
// tables, either returning text bytes for a D address (reported as BAD)
// or raising a page fault on a present page, which Linux silently
// retries (counted as spurious minor faults).
//
// Runs as /init of an initramfs or as a normal program:
//   ptwstress [passes]      (default 400; progress every 20 passes)
// Prints "PTWSTRESS DONE bad=<n> spurious=<n> passes=<n>" and, as PID 1,
// "SIGIL_LINUX_BOOT_OK ptwstress", then idles.
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

long ptw_chain(unsigned long d, unsigned long stride, unsigned long key);

#define DBASE 0x2000000000UL  // root index 128
#define DSIZE (2UL << 20)
#define TBASE 0x3000000000UL  // root index 192
#define TSIZE (512UL << 10)
#define KEY 0x5a5aa5a5c3c33c3cUL
#define NPAGES 48             // gadget pages (ptwstress_gadgets.S)

static long minflt(void) {
  struct rusage ru;
  getrusage(RUSAGE_SELF, &ru);
  return ru.ru_minflt;
}

static void *map_fixed(unsigned long va, unsigned long size) {
  void *p = mmap((void *)va, size, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE | MAP_POPULATE,
                 -1, 0);
  if (p != (void *)va) {
    printf("PTWSTRESS mmap 0x%lx failed\n", va);
    fflush(stdout);
    exit(2);
  }
  return p;
}

int main(int argc, char **argv) {
  long passes = argc > 1 ? atol(argv[1]) : 400;
  setvbuf(stdout, NULL, _IOLBF, 0);
  map_fixed(DBASE, DSIZE);
  map_fixed(TBASE, TSIZE);
  for (unsigned long a = DBASE; a < DBASE + DSIZE; a += 8) *(volatile uint64_t *)a = a ^ KEY;
  for (unsigned long a = TBASE; a < TBASE + TSIZE; a += 8) *(volatile uint64_t *)a = a;
  printf("PTWSTRESS start: %ld passes, %d gadget pages, ptw_chain at %p\n", passes, NPAGES,
         (void *)ptw_chain);
  long bad = 0, spurious = 0;
  volatile uint64_t sink = 0;
  for (long it = 0; it < passes; ++it) {
    for (unsigned long a = TBASE; a < TBASE + TSIZE; a += 64) sink += *(volatile uint64_t *)a;
    // D pages 16 .. 16 + NPAGES (+ up to 7 words): the text's own L0
    // indexes, so a walk through the wrong root lands on mapped text.
    const unsigned long stride = 4096 + 8 * (unsigned long)(it % 8);
    const unsigned long d = DBASE + 0x10000 + 8 * (unsigned long)((it / 8) % 64);
    const long f0 = minflt();
    const long r = ptw_chain(d - stride, stride, KEY);
    const long f1 = minflt();
    spurious += f1 - f0;
    if (r != 0) {
      ++bad;
      if (bad <= 20) {
        printf("PTWSTRESS BAD pass %ld va 0x%lx read 0x%016lx expected 0x%016lx\n", it,
               (unsigned long)r, (unsigned long)*(volatile uint64_t *)r,
               (unsigned long)r ^ KEY);
      }
    }
    if ((it + 1) % 20 == 0) {
      printf("PTWSTRESS pass %ld bad=%ld spurious=%ld\n", it + 1, bad, spurious);
    }
  }
  printf("PTWSTRESS DONE bad=%ld spurious=%ld passes=%ld\n", bad, spurious, passes);
  if (getpid() == 1) {
    printf("SIGIL_LINUX_BOOT_OK ptwstress\n");
    for (;;) pause();
  }
  return bad != 0;
}
