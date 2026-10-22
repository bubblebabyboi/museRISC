#!/usr/bin/env bash
# Boot Sigil Debian under QEMU (issue #70 bring-up): the same OpenSBI
# fw_jump, kernel Image and disk image as the F2 board, on
# qemu-system-riscv64 -M virt shaped like docs/LINUX_PLATFORM.md:
#   - one rv64 hart with Sigil's extensions (B, Zicond, Zbk*/Zkn*,
#     Zve64d with VLEN 512, H) and without the ones Sigil lacks
#     (full V, Sstc, Svpbmt, Zicbo*, Zfa, Zfh, Zihpm, ...), Sv39;
#   - DDR4 node 0 = 48 GiB at 0x8000_0000, the pmem disk = 16 GiB at
#     0xC_8000_0000 backed by the disk image file (shared: guest writes
#     land in the file, like saving the F2 window back), HBM node 1 =
#     16 GiB at 0x10_8000_0000; UART, PLIC, CLINT, test finisher and
#     goldfish RTC at the contract addresses (they are QEMU virt's);
#   - the device tree is build/linux/sigil-qemu.dtb (QEMU's own is not
#     used).
# QEMU deviations (docs/LINUX.md): 10 MHz timebase; the three memory
# ranges are QEMU NUMA "sockets", so QEMU creates two extra harts that
# are not in the DT and that OpenSBI parks; optional virtio NIC.
#
#   bash scripts/qemu_sigil_boot.sh [--disk FILE] [--fresh] [--net]
#        [--initramfs] [--icount] [-- extra qemu args]
#   --disk FILE  pmem disk file (default build/debian/sigil-disk.img, a
#                16 GiB sparse copy of the built image made on first use)
#   --fresh      recreate the default disk from the built image
#   --net        virtio NIC with QEMU user networking (then, in the
#                guest: sudo sigil-qemu-net && sudo apt update)
#   --initramfs  boot Image-initramfs (SIGIL_LINUX_BOOT_OK smoke) instead
#   --icount     deterministic instruction-counting mode (slower): guest
#                time = 16 ns per instruction, i.e. a 62.5 MHz hart at
#                IPC 1 (a lower bound for the F2 boot time)
# Console: QEMU's stdio (Ctrl-A X quits, Ctrl-A C is the QEMU monitor).
set -euo pipefail
cd "$(dirname "$0")/.."

L=${SIGIL_LINUX_DIR:-build/linux}
IMG=${SIGIL_ROOTFS_IMG:-build/debian/sigil-debian-13-riscv64.ext4}
DISK=build/debian/sigil-disk.img
FRESH=0 NET=() KERNEL=$L/Image ICOUNT=()
while [ $# -gt 0 ]; do
  case $1 in
    --disk) DISK=$2; shift 2 ;;
    --fresh) FRESH=1; shift ;;
    --net) NET=(-netdev user,id=net0 -device virtio-net-device,netdev=net0); shift ;;
    --initramfs) KERNEL=$L/Image-initramfs; shift ;;
    --icount) ICOUNT=(-icount shift=4,align=off,sleep=off); shift ;;
    --) shift; break ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

for f in "$L/fw_jump.bin" "$KERNEL" "$L/sigil-qemu.dtb"; do
  [ -f "$f" ] || { echo "error: $f missing (scripts/build_opensbi.sh, build_linux_kernel.sh)" >&2; exit 1; }
done

PMEM=16G
if [ "$FRESH" = 1 ] || [ ! -f "$DISK" ]; then
  [ -f "$IMG" ] || { echo "error: $IMG missing (sudo scripts/build_debian_rootfs.sh, or unpack the .zst)" >&2; exit 1; }
  echo "qemu_sigil_boot: creating $DISK from $IMG" >&2
  cp --sparse=always "$IMG" "$DISK"
fi
# The pmem window is 16 GiB; the image (8 GiB of ext4) sits at its start.
[ "$(stat -c %s "$DISK")" -le $((16 << 30)) ] || { echo "error: $DISK > 16 GiB" >&2; exit 1; }
truncate -s "$PMEM" "$DISK"

CPU=rv64,v=false,zve32f=true,zve64f=true,zve64d=true,vlen=512,elen=64,h=true
CPU+=,zba=true,zbb=true,zbc=true,zbs=true,zbkb=true,zbkc=true,zbkx=true
CPU+=,zkne=true,zknd=true,zknh=true,zicond=true,zcb=true
CPU+=,sstc=false,svpbmt=false,svinval=false,svnapot=false,zicbom=false,zicboz=false
CPU+=,zawrs=false,zfa=false,zfh=false,zfhmin=false,zihintpause=false,zihintntl=false
CPU+=,zihpm=false,sscofpmf=false,sv39=on,sv48=off,sv57=off

exec qemu-system-riscv64 -M virt -cpu "$CPU" \
  -smp 3,sockets=3,cores=1,threads=1 -m 80G \
  -object memory-backend-ram,id=ddr4,size=48G,reserve=off \
  -object memory-backend-file,id=pmem,size=$PMEM,mem-path="$DISK",share=on \
  -object memory-backend-ram,id=hbm,size=16G,reserve=off \
  -numa node,nodeid=0,cpus=0,memdev=ddr4 \
  -numa node,nodeid=1,cpus=1,memdev=pmem \
  -numa node,nodeid=2,cpus=2,memdev=hbm \
  -bios "$L/fw_jump.bin" -kernel "$KERNEL" -dtb "$L/sigil-qemu.dtb" \
  -nographic -serial mon:stdio "${NET[@]}" "${ICOUNT[@]}" "$@"
