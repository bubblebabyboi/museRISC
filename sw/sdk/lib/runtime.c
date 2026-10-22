/* Sigil SDK runtime: UART console, printf-lite, pass/fail/exit, trap
 * dispatch, delays, bump allocator and the small libc subset the
 * compiler may call. See include/sigil.h for the API. */
#include <stdarg.h>

#include "sigil.h"

#ifndef SIGIL_PROG
#define SIGIL_PROG "program"
#endif

/* Keep the libc subset scalar: GCC would otherwise vectorize these
 * loops (or turn them back into calls to themselves). */
#define SIGIL_SCALAR __attribute__((optimize("no-tree-vectorize", "no-tree-loop-distribute-patterns")))

/* ---------------- console ---------------- */
void sigil_putc(char c) {
  if (c == '\n') sigil_putc('\r');
  while ((SIGIL_REG8(SIGIL_UART_BASE + SIGIL_UART_LSR) & SIGIL_UART_LSR_THRE) == 0) {
  }
  SIGIL_REG8(SIGIL_UART_BASE + SIGIL_UART_THR) = (uint8_t)c;
}

void sigil_puts(const char *s) {
  while (*s) sigil_putc(*s++);
}

int sigil_getc(void) {
  if ((SIGIL_REG8(SIGIL_UART_BASE + SIGIL_UART_LSR) & SIGIL_UART_LSR_DR) == 0) return -1;
  return SIGIL_REG8(SIGIL_UART_BASE + SIGIL_UART_RBR);
}

/* Emits one formatted number; returns characters written. */
static int put_num(uint64_t v, int base, int upper, int neg, int width,
                   int zero, int left) {
  char buf[24];
  const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
  int n = 0, out = 0;
  do {
    buf[n++] = digits[v % (uint64_t)base];
    v /= (uint64_t)base;
  } while (v != 0);
  int len = n + (neg ? 1 : 0);
  if (neg && zero) {
    sigil_putc('-');
    out++;
  }
  if (!left) {
    for (; len < width; len++, out++) sigil_putc(zero ? '0' : ' ');
  }
  if (neg && !zero) {
    sigil_putc('-');
    out++;
  }
  while (n > 0) {
    sigil_putc(buf[--n]);
    out++;
  }
  if (left) {
    for (; len < width; len++, out++) sigil_putc(' ');
  }
  return out;
}

int sigil_printf(const char *fmt, ...) {
  va_list ap;
  int out = 0;
  va_start(ap, fmt);
  for (; *fmt; fmt++) {
    if (*fmt != '%') {
      sigil_putc(*fmt);
      out++;
      continue;
    }
    fmt++;
    int zero = 0, left = 0, width = 0, lng = 0;
    for (;; fmt++) {
      if (*fmt == '0') {
        zero = 1;
      } else if (*fmt == '-') {
        left = 1;
      } else {
        break;
      }
    }
    if (left) zero = 0;
    while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
    while (*fmt == 'l' || *fmt == 'z') {
      lng++;
      fmt++;
    }
    switch (*fmt) {
      case 'c':
        sigil_putc((char)va_arg(ap, int));
        out++;
        break;
      case 's': {
        const char *s = va_arg(ap, const char *);
        int len = 0;
        if (s == NULL) s = "(null)";
        while (s[len]) len++;
        if (!left) {
          for (; len < width; width--, out++) sigil_putc(' ');
        }
        for (const char *p = s; *p; p++, out++) sigil_putc(*p);
        if (left) {
          for (; len < width; width--, out++) sigil_putc(' ');
        }
        break;
      }
      case 'd':
      case 'i': {
        int64_t v = lng ? va_arg(ap, int64_t) : va_arg(ap, int);
        uint64_t mag = v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v;
        out += put_num(mag, 10, 0, v < 0, width, zero, left);
        break;
      }
      case 'u':
      case 'x':
      case 'X': {
        uint64_t v = lng ? va_arg(ap, uint64_t) : va_arg(ap, unsigned);
        out += put_num(v, *fmt == 'u' ? 10 : 16, *fmt == 'X', 0, width, zero, left);
        break;
      }
      case 'p':
        sigil_puts("0x");
        out += 2 + put_num((uint64_t)(uintptr_t)va_arg(ap, void *), 16, 0, 0,
                           16, 1, 0);
        break;
      case '%':
        sigil_putc('%');
        out++;
        break;
      case '\0':
        fmt--; /* lone '%' at the end */
        break;
      default: /* unsupported: print it verbatim */
        sigil_putc('%');
        sigil_putc(*fmt);
        out += 2;
        break;
    }
  }
  va_end(ap);
  return out;
}

void sigil_print_fixed(double x, int decimals) {
  if (x < 0) {
    sigil_putc('-');
    x = -x;
  }
  double scale = 1.0;
  for (int i = 0; i < decimals; i++) scale *= 10.0;
  uint64_t scaled = (uint64_t)(x * scale + 0.5); /* round half up */
  uint64_t ip = scaled, fp = 0, s = 1;
  for (int i = 0; i < decimals; i++) s *= 10;
  ip = scaled / s;
  fp = scaled % s;
  sigil_printf("%lu", (unsigned long)ip);
  if (decimals > 0) {
    sigil_putc('.');
    put_num(fp, 10, 0, 0, decimals, 1, 0);
  }
}

void sigil_print_hex(const void *buf, size_t n) {
  const uint8_t *p = (const uint8_t *)buf;
  for (size_t i = 0; i < n; i++) sigil_printf("%02x", p[i]);
}

/* ---------------- pass / fail / exit ---------------- */
static const char *test_name = SIGIL_PROG;

void sigil_set_test_name(const char *name) { test_name = name; }
const char *sigil_test_name(void) { return test_name; }

void sigil_halt(void) {
  sigil_irq_global_disable();
  for (;;) sigil_wfi();
}

void sigil_pass(void) {
  sigil_printf("SIGIL TEST PASS %s\n", test_name);
  sigil_halt();
}

void sigil_fail(const char *why) {
  sigil_printf("SIGIL TEST FAIL %s: %s\n", test_name, why ? why : "");
  sigil_halt();
}

void sigil_exit(int code) {
  if (code == 0) sigil_pass();
  sigil_printf("SIGIL TEST FAIL %s: exit code %d\n", test_name, code);
  sigil_halt();
}

void sigil_check_failed(const char *expr, const char *file, int line) {
  sigil_printf("check failed at %s:%d: %s\n", file, line, expr);
  sigil_fail("SIGIL_CHECK");
}

/* ---------------- traps ---------------- */
static sigil_irq_handler_t irq_handler;
static sigil_exc_handler_t exc_handler;

void sigil_set_irq_handler(sigil_irq_handler_t fn) { irq_handler = fn; }
void sigil_set_exc_handler(sigil_exc_handler_t fn) { exc_handler = fn; }

static const char *exc_name(uint64_t cause) {
  static const char *const names[] = {
      "instruction address misaligned", "instruction access fault",
      "illegal instruction", "breakpoint", "load address misaligned",
      "load access fault", "store/AMO address misaligned",
      "store/AMO access fault", "ecall from U-mode", "ecall from S-mode",
      "reserved", "ecall from M-mode", "instruction page fault",
      "load page fault", "reserved", "store/AMO page fault"};
  return cause < 16 ? names[cause] : "unknown";
}

/* Called by sigil_trap_entry (crt0.S) with the saved register frame;
 * returns the PC to resume at. */
uint64_t sigil_trap_dispatch(uint64_t *frame) {
  (void)frame;
  uint64_t mcause = sigil_csr_read(mcause);
  uint64_t mepc = sigil_csr_read(mepc);
  if (mcause & SIGIL_MCAUSE_IRQ) {
    uint64_t irq = mcause & ~SIGIL_MCAUSE_IRQ;
    if (irq_handler != NULL) {
      irq_handler(irq);
      return mepc;
    }
    sigil_printf("SIGIL TRAP unexpected interrupt %lu (no handler)\n",
                 (unsigned long)irq);
    sigil_fail("unexpected interrupt");
  }
  uint64_t mtval = sigil_csr_read(mtval);
  if (exc_handler != NULL) {
    uint64_t resume = exc_handler(mcause, mepc, mtval);
    if (resume != 0) return resume;
  }
  sigil_printf("SIGIL TRAP mcause=0x%lx (%s) mepc=0x%lx mtval=0x%lx\n",
               (unsigned long)mcause, exc_name(mcause), (unsigned long)mepc,
               (unsigned long)mtval);
  sigil_fail("unhandled exception");
}

/* ---------------- misc ---------------- */
void sigil_delay_cycles(uint64_t n) {
  uint64_t t0 = sigil_rdcycle();
  while (sigil_rdcycle() - t0 < n) {
  }
}

extern char _end[], _ram_end[];
static uintptr_t heap_next;

void *sigil_alloc(size_t n, size_t align) {
  if (heap_next == 0) heap_next = (uintptr_t)_end;
  if (align == 0) align = 16;
  uintptr_t p = (heap_next + align - 1) & ~(uintptr_t)(align - 1);
  if (p + n > (uintptr_t)_ram_end || p + n < p) return NULL;
  heap_next = p + n;
  return (void *)p;
}

/* ---------------- libc subset ---------------- */
SIGIL_SCALAR void *memset(void *dst, int c, size_t n) {
  uint8_t *d = (uint8_t *)dst;
  if ((((uintptr_t)d) & 7) == 0) {
    uint64_t w = (uint8_t)c;
    w |= w << 8;
    w |= w << 16;
    w |= w << 32;
    for (; n >= 8; n -= 8, d += 8) *(uint64_t *)d = w;
  }
  while (n--) *d++ = (uint8_t)c;
  return dst;
}

SIGIL_SCALAR void *memcpy(void *dst, const void *src, size_t n) {
  uint8_t *d = (uint8_t *)dst;
  const uint8_t *s = (const uint8_t *)src;
  if (((((uintptr_t)d) | ((uintptr_t)s)) & 7) == 0) {
    for (; n >= 8; n -= 8, d += 8, s += 8) *(uint64_t *)d = *(const uint64_t *)s;
  }
  while (n--) *d++ = *s++;
  return dst;
}

SIGIL_SCALAR void *memmove(void *dst, const void *src, size_t n) {
  uint8_t *d = (uint8_t *)dst;
  const uint8_t *s = (const uint8_t *)src;
  if (d <= s || d >= s + n) return memcpy(dst, src, n);
  while (n--) d[n] = s[n];
  return dst;
}

SIGIL_SCALAR int memcmp(const void *a, const void *b, size_t n) {
  const uint8_t *x = (const uint8_t *)a, *y = (const uint8_t *)b;
  for (size_t i = 0; i < n; i++) {
    if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return 0;
}

SIGIL_SCALAR size_t strlen(const char *s) {
  size_t n = 0;
  while (s[n]) n++;
  return n;
}

SIGIL_SCALAR int strcmp(const char *a, const char *b) {
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return (int)(uint8_t)*a - (int)(uint8_t)*b;
}
