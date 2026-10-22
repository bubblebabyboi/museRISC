/* The classic, built on the board with Debian's gcc. */
#include <stdio.h>
#include <sys/utsname.h>

int main(void) {
  struct utsname u;
  uname(&u);
  printf("Hello from %s on %s (%s %s)\n", u.nodename, u.machine, u.sysname,
         u.release);
  return 0;
}
