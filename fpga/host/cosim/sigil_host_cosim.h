// XSIM co-simulation hooks for sigil_host.c (issue #54): compiled into
// the HDK testbench by fpga/cl_sigil/verif (test_sigil_host_cosim),
// with SV_TEST defined by the HDK XSIM flow.
#ifndef SIGIL_HOST_COSIM_H_
#define SIGIL_HOST_COSIM_H_
#include <stdint.h>
double sigil_cosim_now_s(void);          // simulation time in seconds
void sigil_cosim_usleep(unsigned us);    // advance simulation time
void sigil_cosim_exit(int code);         // unwinds to the cosim driver
#define now_s sigil_cosim_now_s
#define sigil_usleep sigil_cosim_usleep
#define sigil_exit sigil_cosim_exit
#endif
