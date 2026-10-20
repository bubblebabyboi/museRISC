/* KVM smoke /init for the Sigil hypervisor gate (#22).
 *
 * Creates one VM with one vCPU and a single 4 KiB RAM slot at
 * GPA 0x1000, loads a four-instruction guest, and runs it in
 * VS-mode. The guest stores the value 42 to MMIO GPA 0x2000;
 * the host passes only if KVM_RUN exits with KVM_EXIT_MMIO
 * carrying that address, length, direction, and data, then
 * prints SIGIL_KVM_OK (the soc_tb exit string). Any failure
 * prints SIGIL_KVM_FAIL with the step and errno instead.
 * This proves the KVM ioctl path plus one guest entry/exit on
 * the in-house core; it is not a guest-OS boot. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/kvm.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <unistd.h>

#include <asm/kvm.h>

static void fail(const char *step) {
  printf("SIGIL_KVM_FAIL step=%s errno=%d (%s)\n", step, errno,
         strerror(errno));
  fflush(stdout);
  for (;;) pause();
}

static void set_one_reg(int vcpu, uint64_t id, uint64_t value,
                        const char *step) {
  struct kvm_one_reg reg = {.id = id, .addr = (uint64_t)&value};
  if (ioctl(vcpu, KVM_SET_ONE_REG, &reg) < 0) fail(step);
}

int main(void) {
  /* Guest: addi a0,x0,42; lui a1,2 (0x2000); sw a0,0(a1); 1: j 1b */
  static const uint32_t guest_code[] = {
      0x02a00513u, 0x000025b7u, 0x00a5a023u, 0x0000006fu,
  };
  const uint64_t gpa_ram = 0x1000;
  const uint64_t gpa_mmio = 0x2000;
  const size_t ram_size = 0x1000;
  int kvm, vm, vcpu, run_size;
  void *ram;
  struct kvm_userspace_memory_region region;
  struct kvm_run *run;
  uint64_t mode = KVM_RISCV_MODE_S;

  mount("proc", "/proc", "proc", 0, "");
  mount("devtmpfs", "/dev", "devtmpfs", 0, "");
  printf("sigil kvm smoke: starting\n");
  fflush(stdout);

  kvm = open("/dev/kvm", O_RDWR | O_CLOEXEC);
  if (kvm < 0) fail("open_/dev/kvm");
  printf("kvm step: opened /dev/kvm\n");
  fflush(stdout);
  if (ioctl(kvm, KVM_GET_API_VERSION, 0) != KVM_API_VERSION)
    fail("KVM_GET_API_VERSION");
  vm = ioctl(kvm, KVM_CREATE_VM, 0UL);
  if (vm < 0) fail("KVM_CREATE_VM");
  printf("kvm step: created vm\n");
  fflush(stdout);

  ram = mmap(NULL, ram_size, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (ram == MAP_FAILED) fail("mmap_ram");
  memcpy(ram, guest_code, sizeof(guest_code));
  memset(&region, 0, sizeof(region));
  region.slot = 0;
  region.guest_phys_addr = gpa_ram;
  region.memory_size = ram_size;
  region.userspace_addr = (uint64_t)ram;
  if (ioctl(vm, KVM_SET_USER_MEMORY_REGION, &region) < 0)
    fail("KVM_SET_USER_MEMORY_REGION");
  printf("kvm step: set memory region\n");
  fflush(stdout);

  vcpu = ioctl(vm, KVM_CREATE_VCPU, 0UL);
  if (vcpu < 0) fail("KVM_CREATE_VCPU");
  printf("kvm step: created vcpu\n");
  fflush(stdout);
  run_size = ioctl(kvm, KVM_GET_VCPU_MMAP_SIZE, 0);
  if (run_size <= 0) fail("KVM_GET_VCPU_MMAP_SIZE");
  run = mmap(NULL, (size_t)run_size, PROT_READ | PROT_WRITE, MAP_SHARED,
             vcpu, 0);
  if (run == MAP_FAILED) fail("mmap_kvm_run");

  set_one_reg(vcpu,
              KVM_REG_RISCV | KVM_REG_SIZE_U64 | KVM_REG_RISCV_CORE |
                  KVM_REG_RISCV_CORE_REG(mode),
              mode, "SET_ONE_REG_mode");
  set_one_reg(vcpu,
              KVM_REG_RISCV | KVM_REG_SIZE_U64 | KVM_REG_RISCV_CORE |
                  KVM_REG_RISCV_CORE_REG(regs.pc),
              gpa_ram, "SET_ONE_REG_pc");
  printf("kvm step: set regs, entering KVM_RUN\n");
  fflush(stdout);

  for (int i = 0; i < 16; ++i) {
    if (ioctl(vcpu, KVM_RUN, 0) < 0) fail("KVM_RUN");
    printf("kvm exit %d reason=%u\n", i, run->exit_reason);
    fflush(stdout);
    if (run->exit_reason == KVM_EXIT_MMIO) {
      uint32_t data = 0;
      memcpy(&data, run->mmio.data,
             run->mmio.len < sizeof(data) ? run->mmio.len : sizeof(data));
      printf("kvm mmio addr=0x%llx len=%u write=%u data=%u\n",
             (unsigned long long)run->mmio.phys_addr, run->mmio.len,
             run->mmio.is_write, data);
      if (run->mmio.phys_addr == gpa_mmio && run->mmio.len == 4 &&
          run->mmio.is_write && data == 42) {
        printf("SIGIL_KVM_OK\n");
        fflush(stdout);
        for (;;) pause();
      }
      errno = EIO;
      fail("unexpected_mmio");
    }
  }
  errno = ETIMEDOUT;
  fail("too_many_exits");
}
