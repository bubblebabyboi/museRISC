#!/bin/busybox sh
# Fork/exec stress as an initramfs /init (#73 F2 bring-up): six parallel
# shell loops exec'ing busybox applets (ls, cat, md5sum, sh -c) from
# the initramfs page cache — the many-process fork/exec/exit load under
# which Debian's systemd boot oopses on the F2, without pmem, ext4 or
# systemd. Built by scripts/build_stress_kernels.sh; prints
# "EXECSTRESS DONE" (and SIGIL_LINUX_BOOT_OK) when every loop finished.
/bin/busybox mkdir -p /proc /sys /tmp /dev
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t tmpfs tmp /tmp
N=${EXECSTRESS_ITERS:-200}
echo "execstress: start $(cut -d" " -f1 /proc/uptime)"
for p in 1 2 3 4 5 6; do
  ( i=0
    while [ $i -lt $N ]; do
      ls -l /bin > /tmp/ls$p; cat /proc/meminfo > /dev/null; md5sum /bin/busybox > /tmp/m$p
      sh -c "echo x > /tmp/e$p"; i=$((i+1))
      [ $((i % 25)) = 0 ] && echo "execstress: worker $p at $i $(cut -d" " -f1 /proc/uptime)"
    done
    echo "execstress: worker $p done $(cut -d" " -f1 /proc/uptime)" ) &
done
wait
echo "EXECSTRESS DONE $(cut -d" " -f1 /proc/uptime)"
echo "SIGIL_LINUX_BOOT_OK execstress"
while :; do sleep 3600; done
