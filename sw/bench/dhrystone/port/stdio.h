/* Sigil port of Dhrystone 2.1 (README.md). dhry.h includes <stdio.h>
 * "for strcpy, strcmp" (and dhry_1.c prints with printf); the SDK has
 * no stdio, so this header (found first via -Iport) maps printf onto
 * the SDK console and declares the port glue in sigil_port.c. */
#ifndef SIGIL_DHRY_STDIO_H
#define SIGIL_DHRY_STDIO_H

#include "sigil.h" /* sigil_printf, strcmp, sigil_perf_begin/end */

#define printf sigil_printf

char *strcpy(char *dst, const char *src);

/* Region delta from sigil_perf_end() (mcycle/minstret). */
extern sigil_perf_t sigil_dhry_perf;
/* Checks every final value dhry_1.c prints against its "should be"
 * value, prints the result line and passes or fails the test. */
__attribute__((noreturn)) void sigil_dhry_finish(int int_1_loc, int int_2_loc,
                                                 int int_3_loc, int enum_loc,
                                                 const char *str_1_loc,
                                                 const char *str_2_loc,
                                                 int number_of_runs);
#endif
