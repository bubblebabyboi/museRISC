/* Embedded-initramfs /init for the Sigil Linux boot gate
 * (issue #21): proves the kernel reached userspace on the
 * in-house core. Prints a banner plus uname(2) and the first
 * bytes of /proc/version, then idles; soc_tb ends the run when
 * it sees SIGIL_LINUX_BOOT_OK on the UART. */
#include <fcntl.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/utsname.h>
#include <unistd.h>

int main(void) {
  struct utsname u;
  char buf[256];
  int fd;
  ssize_t n;

  mount("proc", "/proc", "proc", 0, "");
  printf("sigil init: userspace alive\n");
  if (uname(&u) == 0) {
    printf("uname: %s %s %s %s\n", u.sysname, u.release, u.version,
           u.machine);
  }
  fd = open("/proc/version", O_RDONLY);
  if (fd >= 0) {
    n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
      buf[n] = '\0';
      printf("/proc/version: %s", buf);
    }
    close(fd);
  }
  printf("SIGIL_LINUX_BOOT_OK\n");
  fflush(stdout);
  for (;;) pause();
}
