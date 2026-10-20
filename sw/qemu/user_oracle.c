/* Static user-mode oracle payload (issue #30).
 *
 * A tiny deterministic RISC-V Linux binary used to sanity-check
 * the QEMU user-mode oracle path before running the same kind of
 * payload on RTL. It deliberately avoids /proc, mounts, and
 * floating-point libm calls: the kernel /init in sw/linux/init.c
 * assumes PID 1 and pauses forever, so it is not a user-mode test.
 */
#include <stdint.h>
#include <stdio.h>

int main(void) {
  uint32_t x = 0x9e3779b9u;
  uint64_t sum = 0;
  double acc = 0.0;

  for (uint32_t i = 0; i < 10000; ++i) {
    x = x * 1664525u + 1013904223u;
    sum += (x >> 16) ^ i;
    acc += (double)(i & 7) * 0.5;
  }

  printf("SIGIL_QEMU_USER_OK x=%08x sum=%llu acc=%.1f\n", x,
         (unsigned long long)sum, acc);
  return 0;
}
