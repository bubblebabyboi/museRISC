/* CoreMark porting layer for the Sigil SDK (bare metal, M-mode, RV64).
 *
 * Only core_portme.{h,c} are Sigil code; the benchmark sources are the
 * unmodified EEMBC files fetched into third_party/coremark by
 * fetch_coremark.sh (README.md). The configuration below follows the
 * EEMBC barebones port; the differences are the 64-bit types an LP64
 * target needs (ee_ptr_int, CORE_TICKS) and the timer (mcycle through
 * the SDK's sigil_perf region, see core_portme.c). */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>

/* Floating point is used only to print seconds and iterations/s,
 * outside the timed region. */
#ifndef HAS_FLOAT
#define HAS_FLOAT 1
#endif
#ifndef HAS_TIME_H
#define HAS_TIME_H 0
#endif
#ifndef USE_CLOCK
#define USE_CLOCK 0
#endif
#ifndef HAS_STDIO
#define HAS_STDIO 0
#endif
#ifndef HAS_PRINTF
#define HAS_PRINTF 0
#endif

#ifndef COMPILER_VERSION
#ifdef __GNUC__
#define COMPILER_VERSION "GCC" __VERSION__
#else
#define COMPILER_VERSION "unknown compiler"
#endif
#endif
/* FLAGS_STR is the code-generation part of the compile command, set by
 * the Makefile from sdk.mk's CFLAGS. */
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS FLAGS_STR
#endif
#ifndef MEM_LOCATION
#define MEM_LOCATION "STACK"
#endif

typedef signed short ee_s16;
typedef unsigned short ee_u16;
typedef signed int ee_s32;
typedef double ee_f32;
typedef unsigned char ee_u8;
typedef unsigned int ee_u32;
typedef uintptr_t ee_ptr_int; /* holds a pointer: 64 bits on RV64 */
typedef size_t ee_size_t;
#ifndef NULL
#define NULL ((void *)0)
#endif

/* Align an offset to a 32-bit boundary (matrix init). */
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

/* Timer ticks are core clock cycles (mcycle), 64 bits wide. */
#define CORETIMETYPE uint64_t
typedef uint64_t CORE_TICKS;

#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif
#ifndef MEM_METHOD
#define MEM_METHOD MEM_STACK
#endif
#ifndef MULTITHREAD
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK 0
#define USE_SOCKET 0
#endif
/* crt0 calls main() without arguments. */
#ifndef MAIN_HAS_NOARGC
#define MAIN_HAS_NOARGC 1
#endif
#ifndef MAIN_HAS_NORETURN
#define MAIN_HAS_NORETURN 0
#endif

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
  ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

int ee_printf(const char *fmt, ...);

#endif /* CORE_PORTME_H */
