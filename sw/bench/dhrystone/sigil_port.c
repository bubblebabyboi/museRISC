/* Sigil port glue for Dhrystone 2.1 (README.md): the C library pieces
 * the benchmark calls (malloc, strcpy, time) and the self-check +
 * report that replace the original's wall-clock printout. Not part of
 * the measured region except strcpy, which Dhrystone calls by design
 * (the SDK provides strcmp). */
#include "dhry.h"

extern Rec_Pointer Ptr_Glob, Next_Ptr_Glob;
extern int Int_Glob;
extern Boolean Bool_Glob;
extern char Ch_1_Glob, Ch_2_Glob;
extern int Arr_1_Glob[50];
extern int Arr_2_Glob[50][50];

sigil_perf_t sigil_dhry_perf;

void *malloc(size_t n) { return sigil_alloc(n, 16); }

/* dhry.h needs TIME or TIMES; there is no wall clock here (the cycle
 * counts come from the sigil_perf region), so time() reads 0. */
long time(long *t) {
  if (t) *t = 0;
  return 0;
}

/* Plain byte loop, like the SDK's strcmp (kept scalar and out of
 * GCC's loop-to-libcall distribution). */
__attribute__((optimize("no-tree-vectorize", "no-tree-loop-distribute-patterns")))
char *strcpy(char *dst, const char *src) {
  char *d = dst;
  while ((*d++ = *src++) != '\0') {
  }
  return dst;
}

static int failures;

static void check_int(const char *what, long got, long want) {
  if (got != want) {
    sigil_printf("DHRYSTONE MISMATCH %s: %ld, expected %ld\n", what, got, want);
    failures++;
  }
}

static void check_str(const char *what, const char *got, const char *want) {
  if (strcmp(got, want) != 0) {
    sigil_printf("DHRYSTONE MISMATCH %s: \"%s\", expected \"%s\"\n", what, got,
                 want);
    failures++;
  }
}

void sigil_dhry_finish(int int_1_loc, int int_2_loc, int int_3_loc,
                       int enum_loc, const char *str_1_loc,
                       const char *str_2_loc, int number_of_runs) {
  /* The "should be" values printed by dhry_1.c. */
  check_int("Int_Glob", Int_Glob, 5);
  check_int("Bool_Glob", Bool_Glob, 1);
  check_int("Ch_1_Glob", Ch_1_Glob, 'A');
  check_int("Ch_2_Glob", Ch_2_Glob, 'B');
  check_int("Arr_1_Glob[8]", Arr_1_Glob[8], 7);
  check_int("Arr_2_Glob[8][7]", Arr_2_Glob[8][7], number_of_runs + 10);
  check_int("Ptr_Glob->Discr", Ptr_Glob->Discr, 0);
  check_int("Ptr_Glob->Enum_Comp", Ptr_Glob->variant.var_1.Enum_Comp, 2);
  check_int("Ptr_Glob->Int_Comp", Ptr_Glob->variant.var_1.Int_Comp, 17);
  check_str("Ptr_Glob->Str_Comp", Ptr_Glob->variant.var_1.Str_Comp,
            "DHRYSTONE PROGRAM, SOME STRING");
  check_int("Next_Ptr_Glob->Ptr_Comp == Ptr_Glob->Ptr_Comp",
            Next_Ptr_Glob->Ptr_Comp == Ptr_Glob->Ptr_Comp, 1);
  check_int("Next_Ptr_Glob->Discr", Next_Ptr_Glob->Discr, 0);
  check_int("Next_Ptr_Glob->Enum_Comp", Next_Ptr_Glob->variant.var_1.Enum_Comp, 1);
  check_int("Next_Ptr_Glob->Int_Comp", Next_Ptr_Glob->variant.var_1.Int_Comp, 18);
  check_str("Next_Ptr_Glob->Str_Comp", Next_Ptr_Glob->variant.var_1.Str_Comp,
            "DHRYSTONE PROGRAM, SOME STRING");
  check_int("Int_1_Loc", int_1_loc, 5);
  check_int("Int_2_Loc", int_2_loc, 13);
  check_int("Int_3_Loc", int_3_loc, 7);
  check_int("Enum_Loc", enum_loc, 1);
  check_str("Str_1_Loc", str_1_loc, "DHRYSTONE PROGRAM, 1'ST STRING");
  check_str("Str_2_Loc", str_2_loc, "DHRYSTONE PROGRAM, 2'ND STRING");
  if (failures != 0) sigil_fail("Dhrystone final values differ");

  /* Hardware-counter view of the region (the harness reports the
   * simulation counters; on F2 this line is all there is).
   * DMIPS/MHz = runs / cycles * 1e6 / 1757 (VAX 11/780 = 1 DMIPS). */
  uint64_t c = sigil_dhry_perf.cycles, n = (uint64_t)number_of_runs;
  uint64_t milli = c ? n * 1000000000ull / (c * 1757ull) : 0;
  sigil_printf("DHRYSTONE runs=%d cycles=%llu instret=%llu cycles/run=%llu "
               "DMIPS/MHz=%llu.%03llu\n",
               number_of_runs, (unsigned long long)c,
               (unsigned long long)sigil_dhry_perf.instret,
               (unsigned long long)(n ? c / n : 0),
               (unsigned long long)(milli / 1000), (unsigned long long)(milli % 1000));
  sigil_printf("DHRYSTONE CHECK OK runs=%d\n", number_of_runs);
  sigil_pass();
}
