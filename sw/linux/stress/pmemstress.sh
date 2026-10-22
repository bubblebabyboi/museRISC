#!/bin/busybox sh
# pmem + ext4 + page-cache + dynamic-exec stress as an initramfs /init
# (#73 F2 bring-up). Mounts the Debian disk (/dev/pmem0, read-only),
# then three loops checksum files from it while three loops exec
# dynamically linked Debian binaries from it (chroot: ld.so + libc from
# the pmem page cache) — the part of the Debian boot that execstress
# (initramfs only) does not do. Prints "PMEMSTRESS DONE" at the end.
/bin/busybox mkdir -p /proc /sys /tmp /dev /mnt
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t tmpfs tmp /tmp
mount -t devtmpfs dev /dev
i=0; while [ ! -b /dev/pmem0 ] && [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done
mount -t ext4 -o ro /dev/pmem0 /mnt || { echo "PMEMSTRESS FAIL mount"; while :; do sleep 3600; done; }
mount -t proc proc /mnt/proc 2>/dev/null; mount -t devtmpfs dev /mnt/dev 2>/dev/null
N=${PMEMSTRESS_ITERS:-40}
echo "pmemstress: start $(cut -d" " -f1 /proc/uptime)"
find /mnt/usr/lib/riscv64-linux-gnu -maxdepth 1 -type f -name "*.so*" | head -150 > /tmp/files
md5sum $(cat /tmp/files) > /tmp/ref
for p in 1 2 3; do
  ( i=0
    while [ $i -lt $N ]; do
      md5sum $(cat /tmp/files) > /tmp/sum$p
      cmp -s /tmp/sum$p /tmp/ref || echo "PMEMSTRESS FAIL checksum mismatch (reader $p, pass $i)"
      echo 3 > /proc/sys/vm/drop_caches
      i=$((i+1))
      [ $((i % 5)) = 0 ] && echo "pmemstress: reader $p at $i $(cut -d" " -f1 /proc/uptime)"
    done
    echo "pmemstress: reader $p done $(cut -d" " -f1 /proc/uptime)" ) &
done
for p in 4 5 6; do
  ( i=0
    while [ $i -lt $N ]; do
      chroot /mnt /usr/bin/ls -l /usr/bin > /tmp/ls$p || echo "PMEMSTRESS FAIL exec ls ($p, $i)"
      chroot /mnt /usr/bin/sort /etc/passwd > /dev/null || echo "PMEMSTRESS FAIL exec sort ($p, $i)"
      chroot /mnt /usr/bin/true || echo "PMEMSTRESS FAIL exec true ($p, $i)"
      i=$((i+1))
      [ $((i % 5)) = 0 ] && echo "pmemstress: exec $p at $i $(cut -d" " -f1 /proc/uptime)"
    done
    echo "pmemstress: exec $p done $(cut -d" " -f1 /proc/uptime)" ) &
done
wait
echo "PMEMSTRESS DONE $(cut -d" " -f1 /proc/uptime)"
echo "SIGIL_LINUX_BOOT_OK pmemstress"
while :; do sleep 3600; done
