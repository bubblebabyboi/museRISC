/* Sigil bare-metal SDK: the one header a program includes.
 *
 * Programs run in M-mode, alone on the hart, linked at 0x8000_0000
 * (sw/sdk/link.ld). The startup code (sw/sdk/lib/crt0.S) sets up the
 * stack and gp, clears .bss, turns on the FPU and vector unit
 * (mstatus.FS/VS), installs a trap vector, calls main() and passes its
 * return value to sigil_exit(). Guide: docs/PROGRAMMING.md.
 *
 * Contents:
 *   memory map (docs/SPEC.md section 4) and MMIO helpers
 *   UART console: sigil_putc / sigil_puts / sigil_printf (printf-lite)
 *   pass/fail convention: SIGIL TEST PASS <name> / SIGIL TEST FAIL <name>
 *   CSR, performance counter, CLINT timer and interrupt helpers
 *   crypto/hash accelerator driver (register map: sw/sigil_crypto.h)
 *
 * Reference code, NOT constant-time: do not handle private keys with
 * it (docs/SPEC.md section 3, security note). */
#ifndef SIGIL_H
#define SIGIL_H

#include <stddef.h>
#include <stdint.h>

#include "sigil_crypto.h" /* sw/sigil_crypto.h: accelerator register map */

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Memory map (sigil_soc_top, sw/linux/sigil.dts)                      */
/* ------------------------------------------------------------------ */
#define SIGIL_BOOTROM_BASE 0x00001000UL /* 4 KiB; jumps to 0x8000_0000 */
#define SIGIL_CLINT_BASE   0x02000000UL
#define SIGIL_PLIC_BASE    0x0C000000UL
#define SIGIL_UART_BASE    0x10000000UL /* 16550, byte registers */
/* SIGIL_CRYPTO_BASE 0x2000_0000 comes from sigil_crypto.h. */
#define SIGIL_RAM_BASE     0x80000000UL
#define SIGIL_RAM_SIZE     0x08000000UL /* 128 MiB (sim and F2) */

/* CLINT registers (one mtime tick per core clock cycle). */
#define SIGIL_CLINT_MSIP     (SIGIL_CLINT_BASE + 0x0000)
#define SIGIL_CLINT_MTIMECMP (SIGIL_CLINT_BASE + 0x4000)
#define SIGIL_CLINT_MTIME    (SIGIL_CLINT_BASE + 0xBFF8)

/* 16550 UART registers (byte offsets). */
#define SIGIL_UART_THR 0 /* write: transmit byte   */
#define SIGIL_UART_RBR 0 /* read: received byte    */
#define SIGIL_UART_IER 1
#define SIGIL_UART_LSR 5
#define SIGIL_UART_LSR_DR   0x01 /* receive data ready */
#define SIGIL_UART_LSR_THRE 0x20 /* transmitter can take a byte */

/* MMIO accessors. Devices are uncached (only RAM is cacheable). */
#define SIGIL_REG8(a)  (*(volatile uint8_t *)(uintptr_t)(a))
#define SIGIL_REG32(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define SIGIL_REG64(a) (*(volatile uint64_t *)(uintptr_t)(a))

/* ------------------------------------------------------------------ */
/* Console (UART)                                                      */
/* ------------------------------------------------------------------ */
void sigil_putc(char c); /* '\n' is sent as "\r\n" */
void sigil_puts(const char *s); /* no newline appended */
/* Returns the next received byte, or -1 if none is waiting. */
int sigil_getc(void);
/* printf-lite: %c %s %d %i %u %x %X %p %%, length modifiers l / ll / z,
 * flags '0' and '-', field width (e.g. %08x, %-10s, %16llx). No
 * floating point: print doubles with sigil_print_fixed(). Returns the
 * number of characters written. */
int sigil_printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
/* Prints x with `decimals` digits after the point (|x| < 2^63). */
void sigil_print_fixed(double x, int decimals);
/* Prints n bytes as lowercase hex (no separators). */
void sigil_print_hex(const void *buf, size_t n);

/* ------------------------------------------------------------------ */
/* Pass/fail convention                                                */
/* ------------------------------------------------------------------ */
/* The test name defaults to the program name (PROG in the Makefile).
 * sigil_pass() prints "SIGIL TEST PASS <name>" and halts;
 * sigil_fail() prints "SIGIL TEST FAIL <name>: <why>" and halts.
 * Returning from main() calls sigil_exit(ret): 0 = pass, else fail.
 * soc_rtl_tb / fpga_top_tb (--exit-string / --fail-string) and the F2
 * host runtime (sigil_host --exit / --fail) end the run on these. */
void sigil_set_test_name(const char *name);
const char *sigil_test_name(void);
__attribute__((noreturn)) void sigil_pass(void);
__attribute__((noreturn)) void sigil_fail(const char *why);
__attribute__((noreturn)) void sigil_exit(int code);
/* Halt the hart: interrupts off, wfi forever. */
__attribute__((noreturn)) void sigil_halt(void);

/* Fails the test with file:line and the expression text if !cond. */
#define SIGIL_CHECK(cond)                                         \
  do {                                                            \
    if (!(cond)) sigil_check_failed(#cond, __FILE__, __LINE__);   \
  } while (0)
__attribute__((noreturn)) void sigil_check_failed(const char *expr,
                                                  const char *file, int line);

/* ------------------------------------------------------------------ */
/* CSRs, counters                                                      */
/* ------------------------------------------------------------------ */
#define SIGIL_STR_(x) #x
#define SIGIL_STR(x) SIGIL_STR_(x)
#define sigil_csr_read(csr)                                   \
  ({                                                          \
    uint64_t v_;                                              \
    __asm__ volatile("csrr %0, " SIGIL_STR(csr) : "=r"(v_)); \
    v_;                                                       \
  })
#define sigil_csr_write(csr, val) \
  __asm__ volatile("csrw " SIGIL_STR(csr) ", %0" ::"rK"((uint64_t)(val)) : "memory")
#define sigil_csr_set(csr, bits) \
  __asm__ volatile("csrs " SIGIL_STR(csr) ", %0" ::"rK"((uint64_t)(bits)) : "memory")
#define sigil_csr_clear(csr, bits) \
  __asm__ volatile("csrc " SIGIL_STR(csr) ", %0" ::"rK"((uint64_t)(bits)) : "memory")

/* The counter reads and the perf-region markers below are always
 * inlined, also under -fno-inline (Dhrystone's ground rules), so a
 * measured region has no call overhead at its edges. */
#define SIGIL_ALWAYS_INLINE static inline __attribute__((always_inline))

/* Core clock cycles / retired instructions since reset (64-bit). */
SIGIL_ALWAYS_INLINE uint64_t sigil_rdcycle(void) {
  uint64_t v;
  __asm__ volatile("rdcycle %0" : "=r"(v));
  return v;
}
SIGIL_ALWAYS_INLINE uint64_t sigil_rdinstret(void) {
  uint64_t v;
  __asm__ volatile("rdinstret %0" : "=r"(v));
  return v;
}
/* time CSR = CLINT mtime (one tick per core clock). */
static inline uint64_t sigil_rdtime(void) {
  uint64_t v;
  __asm__ volatile("rdtime %0" : "=r"(v));
  return v;
}

/* Cycle + instret snapshot for measuring a code region. */
typedef struct {
  uint64_t cycles, instret;
} sigil_perf_t;
SIGIL_ALWAYS_INLINE sigil_perf_t sigil_perf_now(void) {
  sigil_perf_t p;
  p.cycles = sigil_rdcycle();
  p.instret = sigil_rdinstret();
  return p;
}
SIGIL_ALWAYS_INLINE sigil_perf_t sigil_perf_since(sigil_perf_t start) {
  sigil_perf_t p = sigil_perf_now();
  p.cycles -= start.cycles;
  p.instret -= start.instret;
  return p;
}

/* Measured region for the performance harness (make -C sim perf,
 * docs/PERFORMANCE.md):
 *   sigil_perf_begin();  work();  sigil_perf_t t = sigil_perf_end();
 * sigil_perf_begin() writes the begin marker, then snapshots
 * mcycle/minstret; sigil_perf_end() snapshots them, writes the end
 * marker, prints "SIGIL PERF region=<id> cycles=<n> instret=<n>" and
 * returns the delta. A marker is one write to mhpmevent31, which this
 * core ignores (no architectural effect, no pipeline flush). In
 * simulation the event counters in sigil_cpu count every cycle between
 * the two markers and write a SIGIL_PERF record; on hardware only the
 * mcycle/minstret numbers exist. One region is open at a time; the
 * _id forms tag it (0..255) when a program measures several. */
#define SIGIL_PERF_MARK_CSR mhpmevent31
#define SIGIL_PERF_MAGIC 0x50450000UL /* marker[63:16] = "PE" */
extern sigil_perf_t sigil_perf_start_;
SIGIL_ALWAYS_INLINE void sigil_perf_mark_(uint64_t v) {
  __asm__ volatile("csrw " SIGIL_STR(SIGIL_PERF_MARK_CSR) ", %0" ::"r"(v)
                   : "memory");
}
SIGIL_ALWAYS_INLINE void sigil_perf_begin_id(unsigned id) {
  sigil_perf_mark_(SIGIL_PERF_MAGIC | ((uint64_t)(id & 0xffu) << 8) | 1u);
  sigil_perf_start_ = sigil_perf_now();
}
sigil_perf_t sigil_perf_report_(unsigned id, sigil_perf_t t);
SIGIL_ALWAYS_INLINE sigil_perf_t sigil_perf_end_id(unsigned id) {
  sigil_perf_t t = sigil_perf_since(sigil_perf_start_);
  sigil_perf_mark_(SIGIL_PERF_MAGIC | ((uint64_t)(id & 0xffu) << 8) | 2u);
  return sigil_perf_report_(id, t);
}
SIGIL_ALWAYS_INLINE void sigil_perf_begin(void) { sigil_perf_begin_id(0); }
SIGIL_ALWAYS_INLINE sigil_perf_t sigil_perf_end(void) { return sigil_perf_end_id(0); }

static inline void sigil_fence(void) { __asm__ volatile("fence" ::: "memory"); }
/* Required after writing instructions to memory (D$ write-back +
 * I$ invalidate), before executing them. */
static inline void sigil_fence_i(void) { __asm__ volatile("fence.i" ::: "memory"); }
static inline void sigil_wfi(void) { __asm__ volatile("wfi"); }

/* Busy-wait (in core clock cycles). */
void sigil_delay_cycles(uint64_t n);

/* ------------------------------------------------------------------ */
/* CLINT timer and interrupts                                          */
/* ------------------------------------------------------------------ */
#define SIGIL_MSTATUS_MIE (1UL << 3)
#define SIGIL_MIE_MSIE (1UL << 3)
#define SIGIL_MIE_MTIE (1UL << 7)
#define SIGIL_MIE_MEIE (1UL << 11)
#define SIGIL_MCAUSE_IRQ (1UL << 63)
#define SIGIL_IRQ_M_SOFT 3
#define SIGIL_IRQ_M_TIMER 7
#define SIGIL_IRQ_M_EXT 11

static inline uint64_t sigil_mtime(void) { return SIGIL_REG64(SIGIL_CLINT_MTIME); }
static inline void sigil_set_mtimecmp(uint64_t t) { SIGIL_REG64(SIGIL_CLINT_MTIMECMP) = t; }
static inline uint64_t sigil_get_mtimecmp(void) { return SIGIL_REG64(SIGIL_CLINT_MTIMECMP); }
/* mtimecmp = mtime + ticks. */
static inline void sigil_timer_after(uint64_t ticks) { sigil_set_mtimecmp(sigil_mtime() + ticks); }
/* mtimecmp = all ones: the timer interrupt is never pending. */
static inline void sigil_timer_off(void) { sigil_set_mtimecmp(~0ULL); }

static inline void sigil_irq_global_enable(void) { sigil_csr_set(mstatus, SIGIL_MSTATUS_MIE); }
static inline void sigil_irq_global_disable(void) { sigil_csr_clear(mstatus, SIGIL_MSTATUS_MIE); }
static inline void sigil_irq_enable(uint64_t mie_bits) { sigil_csr_set(mie, mie_bits); }
static inline void sigil_irq_disable(uint64_t mie_bits) { sigil_csr_clear(mie, mie_bits); }

/* Interrupt handler: called from the trap vector with the interrupt
 * number (mcause without bit 63). It must clear the source (e.g. move
 * mtimecmp) before returning, or the interrupt is taken again. The
 * trap vector saves the integer and caller-saved FP registers; handlers
 * must not use vector instructions (vector state is not saved). */
typedef void (*sigil_irq_handler_t)(uint64_t irq);
void sigil_set_irq_handler(sigil_irq_handler_t fn);

/* Synchronous exceptions (illegal instruction, misaligned or faulting
 * access, ecall, ...) print "SIGIL TRAP mcause=.. mepc=.. mtval=.."
 * and fail the test. A program can take them instead: the handler
 * gets mcause/mepc/mtval and returns the PC to resume at, or 0 to
 * fall back to the default (fail). */
typedef uint64_t (*sigil_exc_handler_t)(uint64_t mcause, uint64_t mepc,
                                         uint64_t mtval);
void sigil_set_exc_handler(sigil_exc_handler_t fn);
/* PC of the instruction after the one at `pc` (2 or 4 bytes: the
 * program is built with C, so an instruction may be compressed). Use it
 * to return past a faulting instruction from an exception handler. */
static inline uint64_t sigil_next_pc(uint64_t pc) {
  return pc + (((*(volatile uint16_t *)(uintptr_t)pc) & 3) == 3 ? 4 : 2);
}

/* ------------------------------------------------------------------ */
/* Bump allocator over the RAM after the stack (no free).               */
/* ------------------------------------------------------------------ */
void *sigil_alloc(size_t n, size_t align); /* NULL when out of RAM */

/* libc subset provided by the SDK (the compiler may call these). */
void *memset(void *dst, int c, size_t n);
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
int memcmp(const void *a, const void *b, size_t n);
size_t strlen(const char *s);
int strcmp(const char *a, const char *b);

/* ------------------------------------------------------------------ */
/* Crypto accelerator (0x2000_0000, docs/SPEC.md section 3)            */
/* ------------------------------------------------------------------ */

/* SHA-256 engine: one 512-bit block per start, from the IV, no
 * chaining. sigil_sha256() pads in software, so it hashes messages of
 * up to 55 bytes (one block). Returns 0, or -1 if len > 55 (hash longer
 * messages in software, or use SHA-512 / SHA3 on the streaming engine).
 * The digest is in standard byte order. */
#define SIGIL_SHA256_MAX_LEN 55
int sigil_sha256(const void *msg, size_t len, uint8_t digest[32]);
/* Raw block interface: 16 big-endian message words in, the 8 digest
 * words H0..H7 out (no padding added). */
void sigil_sha256_block(const uint32_t block[16], uint32_t h[8]);

/* Streaming hash engine: arbitrary-length messages, padding in
 * hardware. mode: SIGIL_HASH_SHA512 (64-byte digest), SIGIL_HASH_SHA3_256,
 * SIGIL_HASH_KECCAK256 (32 bytes), SIGIL_HASH_SHAKE256 (any length).
 * One message at a time (the engine is a single instance):
 *   sigil_hash_init(mode); sigil_hash_update(p, n)...; sigil_hash_final(out, len)
 * or the one-shot sigil_hash(). Returns 0, or -1 if the engine flagged
 * a protocol error (HSTATUS.err) or outlen is too long for the mode. */
void sigil_hash_init(int mode);
void sigil_hash_update(const void *data, size_t len);
int sigil_hash_final(uint8_t *out, size_t outlen);
int sigil_hash(int mode, const void *msg, size_t len, uint8_t *out,
               size_t outlen);

/* 256-bit field unit: add/sub/mul mod p with p selected by MODSEL. */
typedef struct {
  uint64_t v[4]; /* little-endian 64-bit limbs */
} sigil_fe_t;
#define SIGIL_MOD_SECP256K1 0 /* p = 2^256 - 2^32 - 977 */
#define SIGIL_MOD_CURVE25519 1 /* p = 2^255 - 19 */
#define SIGIL_MOD_CUSTOM 2 /* sigil_fe_set_modulus() */
void sigil_fe_modsel(uint32_t sel);
void sigil_fe_set_modulus(const sigil_fe_t *m); /* also selects CUSTOM */
void sigil_fe_add(const sigil_fe_t *a, const sigil_fe_t *b, sigil_fe_t *r);
void sigil_fe_sub(const sigil_fe_t *a, const sigil_fe_t *b, sigil_fe_t *r);
void sigil_fe_mul(const sigil_fe_t *a, const sigil_fe_t *b, sigil_fe_t *r);
void sigil_fe_pow(const sigil_fe_t *a, const sigil_fe_t *e, sigil_fe_t *r);
static inline void sigil_fe_set_u64(sigil_fe_t *r, uint64_t x) {
  r->v[0] = x;
  r->v[1] = r->v[2] = r->v[3] = 0;
}
static inline int sigil_fe_eq(const sigil_fe_t *a, const sigil_fe_t *b) {
  return ((a->v[0] ^ b->v[0]) | (a->v[1] ^ b->v[1]) | (a->v[2] ^ b->v[2]) |
          (a->v[3] ^ b->v[3])) == 0;
}

/* Ed25519 signature verify (RFC 8032 section 5.1.7, cofactorless as in
 * sw/ec_ops.py): Curve25519 field ops on the accelerator, k =
 * SHA-512(R || A || M) on the streaming hash engine. Leaves MODSEL set
 * to Curve25519. Returns SIGIL_ED25519_OK (0) or the reason for
 * rejection. Variable-time: fine for public inputs only. */
#define SIGIL_ED25519_OK 0
#define SIGIL_ED25519_BAD_KEY 1 /* A does not decode to a curve point */
#define SIGIL_ED25519_BAD_S 2 /* S >= L (non-canonical) */
#define SIGIL_ED25519_MISMATCH 3 /* [S]B - [k]A != R */
int sigil_ed25519_verify(const uint8_t pub[32], const void *msg, size_t len,
                         const uint8_t sig[64]);

#ifdef __cplusplus
}
#endif
#endif /* SIGIL_H */
