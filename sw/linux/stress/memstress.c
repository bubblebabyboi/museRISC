/* Linux user-space memory stress for the Sigil F2 bring-up (#73):
 * an alternate initramfs /init (scripts/build_stress_kernels.sh).
 * Checks that what user code writes to RAM reads back, under the things
 * Linux does that bare-metal tests do not: page faults, timer
 * interrupts and context switches between processes, FENCE.I (on Sigil
 * it writes back every dirty D$ line), fork/COW, LR/SC and AMOs.
 * Prints MEMSTRESS PASS or MEMSTRESS FAIL lines with the first bad
 * addresses. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define LINE 64

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

static inline uint64_t pat(uint64_t seed, uint64_t i) {
  uint64_t x = seed ^ (i * 0x9E3779B97F4A7C15ull);
  x ^= x >> 29; x *= 0xBF58476D1CE4E5B9ull; x ^= x >> 32;
  return x;
}

static inline void fence_i(void) { __asm__ __volatile__("fence.i" ::: "memory"); }

/* Fill words with a pattern (stride through lines so the D$ keeps
 * evicting dirty lines), optional FENCE.I every `fi` lines, verify. */
static long pass(uint64_t *buf, size_t words, uint64_t seed, unsigned fi,
                 const char *tag) {
  size_t lines = words / (LINE / 8);
  long bad = 0;
  for (size_t l = 0; l < lines; l++) {
    size_t li = (l * 2654435761u) % lines;          /* scattered lines */
    for (int w = 0; w < LINE / 8; w++) {
      size_t i = li * (LINE / 8) + w;
      buf[i] = pat(seed, i);
    }
    if (fi && (l % fi) == 0) fence_i();
  }
  for (size_t i = 0; i < words; i++) {
    uint64_t want = pat(seed, i);
    if (buf[i] != want) {
      if (bad < 8)
        printf("MEMSTRESS FAIL %s: va %p word %zu got %016llx want %016llx\n",
               tag, (void *)&buf[i], i, (unsigned long long)buf[i],
               (unsigned long long)want);
      bad++;
    }
  }
  return bad;
}

static long atomics(uint64_t *buf, size_t words, unsigned rounds) {
  long bad = 0;
  for (unsigned r = 0; r < rounds; r++)
    for (size_t i = 0; i < words; i += 8) {
      __atomic_fetch_add(&buf[i], 3, __ATOMIC_SEQ_CST);          /* AMOADD */
      uint64_t e = __atomic_load_n(&buf[i + 1], __ATOMIC_RELAXED);
      while (!__atomic_compare_exchange_n(&buf[i + 1], &e, e + 5, 0,
                                          __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
        ;                                                         /* LR/SC */
    }
  for (size_t i = 0; i < words; i += 8)
    if (buf[i] != 3ull * rounds || buf[i + 1] != 5ull * rounds) {
      if (bad < 8)
        printf("MEMSTRESS FAIL atomics: word %zu got %llu/%llu want %llu/%llu\n", i,
               (unsigned long long)buf[i], (unsigned long long)buf[i + 1],
               3ull * rounds, 5ull * rounds);
      bad++;
    }
  return bad;
}

static long worker(int id, size_t mib, int iters) {
  size_t bytes = mib << 20, words = bytes / 8;
  long bad = 0;
  for (int it = 0; it < iters; it++) {
    uint64_t *buf = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (buf == MAP_FAILED) { printf("MEMSTRESS FAIL mmap\n"); return 1; }
    char tag[32];
    snprintf(tag, sizeof tag, "p%d.i%d", id, it);
    bad += pass(buf, words, 0x1234 + id * 977 + it, it & 1 ? 64 : 0, tag);
    /* fork: the child sees the parent's data (COW), writes its own */
    pid_t c = fork();
    if (c == 0) {
      long b = 0;
      for (size_t i = 0; i < words; i += 4096 / 8)
        if (buf[i] != pat(0x1234 + id * 977 + it, i)) b++;
      b += pass(buf, words / 4, 0xC0FFEE + id, 16, "child");
      _exit(b ? 1 : 0);
    }
    int st = 0;
    waitpid(c, &st, 0);
    if (!WIFEXITED(st) || WEXITSTATUS(st)) { printf("MEMSTRESS FAIL fork/COW %s\n", tag); bad++; }
    for (size_t i = 0; i < words; i += 4096 / 8)       /* parent unchanged */
      if (buf[i] != pat(0x1234 + id * 977 + it, i)) { bad++; break; }
    memset(buf, 0, 1 << 20);
    bad += atomics(buf, (1 << 20) / 8, 50);
    munmap(buf, bytes);
  }
  return bad;
}

int main(void) {
  mount("proc", "/proc", "proc", 0, "");
  setvbuf(stdout, NULL, _IOLBF, 0);
  printf("memstress: start\n");
  double t0 = now();
  long bad = worker(0, 64, 4);                 /* one process */
  printf("memstress: single process done, %ld bad (%.1f s)\n", bad, now() - t0);
  const int np = 6;                            /* several processes */
  pid_t pids[np];
  for (int p = 0; p < np; p++) {
    pids[p] = fork();
    if (pids[p] == 0) _exit(worker(p + 1, 32, 6) ? 1 : 0);
  }
  for (int p = 0; p < np; p++) {
    int st = 0;
    waitpid(pids[p], &st, 0);
    if (!WIFEXITED(st) || WEXITSTATUS(st)) { printf("MEMSTRESS FAIL process %d\n", p + 1); bad++; }
  }
  printf("memstress: %d processes done (%.1f s)\n", np, now() - t0);
  printf(bad ? "MEMSTRESS FAIL (%ld)\n" : "MEMSTRESS PASS (%ld)\n", bad);
  printf("SIGIL_LINUX_BOOT_OK memstress\n");
  for (;;) pause();
}
