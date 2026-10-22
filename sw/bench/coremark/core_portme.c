/* CoreMark porting layer for the Sigil SDK (README.md).
 *
 * - Timer: start_time()/stop_time() open and close the harness region
 *   (sigil_perf_begin/sigil_perf_end), so the timed region of
 *   core_main.c (exactly iterate()) is the measured region, and
 *   CoreMark's ticks are the mcycle delta of that region.
 * - Seconds: ticks / SIGIL_COREMARK_CLOCK_HZ (the F2 B1 clock, 62.5 MHz,
 *   by default). Only CoreMark's printout uses it.
 * - Self-check: portable_fini() runs after core_main.c's report and
 *   re-checks the results it has (seed CRC, list/matrix/state CRCs,
 *   CoreMark's error count, and crcfinal against a host reference when
 *   the iteration count is in the table below), then passes or fails
 *   the test.
 * - ee_printf: forwards each conversion to the SDK's sigil_printf; %f
 *   goes to sigil_print_fixed (6 decimals, as printf). */
#include <stdarg.h>

#include "coremark.h"
#include "sigil.h"

#ifndef SIGIL_COREMARK_CLOCK_HZ
#define SIGIL_COREMARK_CLOCK_HZ 62500000u
#endif
#define EE_TICKS_PER_SEC ((double)SIGIL_COREMARK_CLOCK_HZ)

/* EEMBC run rule 5 (check_data_types() repeats these at run time). */
_Static_assert(sizeof(ee_u8) == 1 && sizeof(ee_s16) == 2 && sizeof(ee_u16) == 2,
               "8/16-bit types");
_Static_assert(sizeof(ee_s32) == 4 && sizeof(ee_u32) == 4, "32-bit types");
_Static_assert(sizeof(ee_ptr_int) == sizeof(void *), "ee_ptr_int holds a pointer");

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

/* ---------------------------------------------------------------- */
/* Timing                                                            */
/* ---------------------------------------------------------------- */
static sigil_perf_t cm_perf;

void start_time(void) { sigil_perf_begin(); }

void stop_time(void) { cm_perf = sigil_perf_end(); }

CORE_TICKS get_time(void) { return (CORE_TICKS)cm_perf.cycles; }

secs_ret time_in_secs(CORE_TICKS ticks) {
  return (secs_ret)ticks / (secs_ret)EE_TICKS_PER_SEC;
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[]) {
  (void)argc;
  (void)argv;
  p->portable_id = 1;
}

/* ---------------------------------------------------------------- */
/* Self-check                                                        */
/* ---------------------------------------------------------------- */
/* Known CRCs of core_main.c for TOTAL_DATA_SIZE 2000 (666 bytes per
 * algorithm): known_id 3 (performance seeds 0,0,0x66) and 4
 * (validation seeds 0x3415,0x3415,0x66). */
#if PERFORMANCE_RUN
#define CM_RUN "performance"
#define CM_SEEDCRC 0xe9f5
#define CM_CRCLIST 0xe714
#define CM_CRCMATRIX 0x1fd7
#define CM_CRCSTATE 0x8e3a
#elif VALIDATION_RUN
#define CM_RUN "validation"
#define CM_SEEDCRC 0x18f2
#define CM_CRCLIST 0xe3c1
#define CM_CRCMATRIX 0x0747
#define CM_CRCSTATE 0x8d84
#else
#error "build with PERFORMANCE_RUN=1 or VALIDATION_RUN=1 (TOTAL_DATA_SIZE 2000)"
#endif
#if TOTAL_DATA_SIZE != 2000
#error "the known CRCs are for TOTAL_DATA_SIZE 2000"
#endif

/* crcfinal (the CRC over every iteration's list results) depends on
 * the iteration count. Reference values from the unmodified sources
 * built natively for x86-64 with EEMBC's linux port (README.md). */
static const struct {
  ee_u32 iterations;
  ee_u16 perf, valid;
} cm_crcfinal_ref[] = {
    {1, 0xe714, 0xe3c1},
    {10, 0xfcaf, 0x0000},
};

static int cm_failures;

static void cm_check(const char *what, unsigned got, unsigned want) {
  if (got != want) {
    sigil_printf("COREMARK MISMATCH %s: 0x%04x, expected 0x%04x\n", what, got, want);
    cm_failures++;
  }
}

void portable_fini(core_portable *p) {
  p->portable_id = 0;
  /* core_main.c passes &results[0].port. */
  const core_results *r =
      (const core_results *)(const void *)((const char *)p - offsetof(core_results, port));

  ee_u16 seedcrc = 0;
  seedcrc = crc16(r->seed1, seedcrc);
  seedcrc = crc16(r->seed2, seedcrc);
  seedcrc = crc16(r->seed3, seedcrc);
  seedcrc = crc16((ee_s16)r->size, seedcrc);
  cm_check("seedcrc", seedcrc, CM_SEEDCRC);
  cm_check("size per algorithm", r->size, TOTAL_DATA_SIZE / 3);
  cm_check("algorithms", r->execs, ALL_ALGORITHMS_MASK);
  cm_check("iterations", r->iterations, (unsigned)ITERATIONS);
  cm_check("crclist", r->crclist, CM_CRCLIST);
  cm_check("crcmatrix", r->crcmatrix, CM_CRCMATRIX);
  cm_check("crcstate", r->crcstate, CM_CRCSTATE);
  cm_check("CoreMark error count", (unsigned)(ee_u16)r->err, 0);

  int have_ref = 0;
  for (size_t i = 0; i < sizeof cm_crcfinal_ref / sizeof cm_crcfinal_ref[0]; i++) {
    if (cm_crcfinal_ref[i].iterations == r->iterations) {
#if PERFORMANCE_RUN
      cm_check("crcfinal", r->crc, cm_crcfinal_ref[i].perf);
#else
      cm_check("crcfinal", r->crc, cm_crcfinal_ref[i].valid);
#endif
      have_ref = 1;
    }
  }
  if (cm_failures != 0) sigil_fail("CoreMark results differ from the known values");

  /* Hardware-counter view of the timed region (the harness reports the
   * simulation counters; on F2 this is all there is).
   * CoreMark/MHz = iterations / cycles * 1e6. */
  uint64_t c = cm_perf.cycles, n = r->iterations;
  uint64_t milli = c ? n * 1000000000ull / c : 0;
  sigil_printf("COREMARK %s run: iterations=%llu cycles=%llu instret=%llu "
               "cycles/iteration=%llu CoreMark/MHz=%llu.%03llu\n",
               CM_RUN, (unsigned long long)n, (unsigned long long)c,
               (unsigned long long)cm_perf.instret,
               (unsigned long long)(n ? c / n : 0),
               (unsigned long long)(milli / 1000), (unsigned long long)(milli % 1000));
  uint64_t ms = c * 1000ull / SIGIL_COREMARK_CLOCK_HZ;
  if (c < 10ull * SIGIL_COREMARK_CLOCK_HZ)
    sigil_printf("COREMARK NOTE timed region %llu.%03llu s at %u Hz < 10 s: "
                 "core_main's 10 s ERROR and 'Errors detected' lines refer to "
                 "that run rule only (not reportable as a CoreMark score)\n",
                 (unsigned long long)(ms / 1000), (unsigned long long)(ms % 1000),
                 (unsigned)SIGIL_COREMARK_CLOCK_HZ);
  sigil_printf("COREMARK CRC seedcrc=0x%04x crclist=0x%04x crcmatrix=0x%04x "
               "crcstate=0x%04x crcfinal=0x%04x (%s)\n",
               seedcrc, r->crclist, r->crcmatrix, r->crcstate, r->crc,
               have_ref ? "crcfinal matches the host reference"
                        : "no crcfinal reference for this iteration count");
  sigil_printf("COREMARK CHECK OK iterations=%llu\n", (unsigned long long)n);
  sigil_pass();
}

/* ---------------------------------------------------------------- */
/* ee_printf                                                         */
/* ---------------------------------------------------------------- */
/* core_main.c uses %s %d %u %lu %04x %f. Each conversion is passed to
 * sigil_printf on its own with the argument of the right type. */
int ee_printf(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int n = 0;
  while (*fmt) {
    if (*fmt != '%') {
      sigil_putc(*fmt++);
      n++;
      continue;
    }
    const char *start = fmt++;
    while (*fmt == '-' || *fmt == '0') fmt++;
    while (*fmt >= '0' && *fmt <= '9') fmt++;
    int longs = 0;
    while (*fmt == 'l') {
      longs++;
      fmt++;
    }
    char spec[16];
    size_t len = (size_t)(fmt - start) + 1;
    if (*fmt == '\0' || len >= sizeof spec) break;
    for (size_t i = 0; i < len; i++) spec[i] = start[i];
    spec[len] = '\0';
    switch (*fmt++) {
      case 'd':
      case 'i':
        n += longs ? sigil_printf(spec, va_arg(ap, long)) : sigil_printf(spec, va_arg(ap, int));
        break;
      case 'u':
      case 'x':
      case 'X':
        n += longs ? sigil_printf(spec, va_arg(ap, unsigned long))
                   : sigil_printf(spec, va_arg(ap, unsigned));
        break;
      case 'c':
        n += sigil_printf(spec, va_arg(ap, int));
        break;
      case 's':
        n += sigil_printf(spec, va_arg(ap, const char *));
        break;
      case 'f':
        sigil_print_fixed(va_arg(ap, double), 6);
        break;
      case '%':
        sigil_putc('%');
        n++;
        break;
      default:
        sigil_puts(spec);
        break;
    }
  }
  va_end(ap);
  return n;
}
