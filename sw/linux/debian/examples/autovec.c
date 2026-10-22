/* Plain C loops that GCC turns into vector code for Sigil:
 *   gcc -O3 -march=rv64gc_zve64d_zvl512b autovec.c -o autovec
 * (zvl512b tells GCC the vector length; check with
 *  objdump -d autovec | grep -E '\sv(le|se|fmacc|fadd)') */
#include <stdio.h>

#define N 4096
double a[N], b[N];

int main(void) {
  for (int i = 0; i < N; i++) { a[i] = i; b[i] = 2 * i; }
  for (int i = 0; i < N; i++) a[i] += 3 * b[i];   /* vectorized */
  double s = 0;
  for (int i = 0; i < N; i++) s += a[i];
  printf("autovec sum %.0f (expect %.0f)\n", s, 7.0 * (N - 1) * N / 2);
  return s == 7.0 * (N - 1) * N / 2 ? 0 : 1;
}
