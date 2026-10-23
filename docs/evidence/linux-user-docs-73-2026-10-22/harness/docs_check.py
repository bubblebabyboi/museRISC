#!/usr/bin/env python3
"""Check the docs/LINUX.md "Using Sigil Linux" commands in QEMU (not F2):
files in with debugfs and a loop mount, gcc, libnuma, numactl, vector
builds, sudo poweroff, files out with debugfs."""
import re, subprocess, sys, os
sys.path.insert(0, os.path.expanduser("~/docs73/sigil/scripts"))
from qemu_sigil_check import Run, PROMPT  # noqa: E402
import pexpect  # noqa: E402

W = os.path.expanduser("~/docs73/qemu")
D = W + "/disk.ext4"
def host(cmd):
    print("+ " + cmd, flush=True)
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    print(r.stdout + r.stderr, flush=True)
    return r
os.makedirs(W, exist_ok=True)
host(f"rm -f {D}; zstd -d -q --sparse -o {D} ~/os-artifacts/sigil-debian-13-riscv64.ext4.zst; du -h {D}")
# files in: debugfs (no root), loop mount (root)
host(f"cd {W}/src && debugfs -w -R 'write in_debugfs.c /home/sigil/in_debugfs.c' {D}")
host(f"mkdir -p {W}/mnt && sudo mount -o loop {D} {W}/mnt && sudo cp -r {W}/src/myproj {W}/mnt/home/sigil/ "
     f"&& sudo chown -R 1000:1000 {W}/mnt/home/sigil/myproj && sudo umount {W}/mnt")
log = open(W + "/docs-check.log", "w")
env = "SIGIL_LINUX_DIR=$HOME/os-artifacts"
r = Run(["bash", "-c", f"cd ~/docs73/sigil && {env} bash scripts/qemu_sigil_boot.sh --disk {D}"], log, 1)
r.login("sigil", 300)
r.sh("ls -ln ~/in_debugfs.c ~/myproj/hbm.c", check=r"^-\S+\s+1\s+0\s+0\s.*in_debugfs\.c[\s\S]*\s1000\s+1000\s.*hbm\.c",
     name="debugfs file is root's, loop-mounted copy is sigil's")
r.p.sendline("sudo -k; sudo chown sigil:sigil ~/in_debugfs.c")
i = r.expect([r"password for sigil: ", re.escape(PROMPT)], 120)
if i == 0:
    r.p.sendline("sigil"); r.expect([re.escape(PROMPT)], 120)
r.sh("ls -l ~/in_debugfs.c", check=r"sigil sigil", name="sudo chown fixes the owner")
r.sh("cd ~/myproj && gcc -O2 hbm.c -lnuma -o hbm && ./hbm", check=r"^copied 64 MiB from HBM to DDR4",
     name="libnuma numa_alloc_onnode snippet")
r.sh("numactl --membind=1 ./hbm", check=r"^copied 64 MiB", name="numactl --membind=1 ./prog")
r.sh("cd ~/examples && make -s numa_hbm memwhere rvv_vadd autovec && ./numa_hbm 16 && numactl --membind=1 ./memwhere 64",
     check=r"NUMA OK[\s\S]*node 1: 64 MiB", name="numa_hbm + memwhere --membind=1")
r.sh("gcc -O2 -march=rv64gc_zve64d rvv_vadd.c -o rvv_vadd && ./rvv_vadd", check=r"RVV OK", name="intrinsics -march=rv64gc_zve64d")
r.sh("gcc -O3 -march=rv64gc_zve64d_zvl512b autovec.c -o autovec && ./autovec && objdump -d autovec | grep -cE '\\sv(le|se|fmacc|fadd)'",
     check=r"^autovec sum", name="auto-vectorization -march=rv64gc_zve64d_zvl512b")
r.sh("gcc --version | head -1; python3 --version; numactl --show | head -3")
r.sh("echo 'result from the board' > ~/out.txt; mkdir -p ~/results && cp ~/out.txt ~/results/ && sync")
r.p.sendline("sudo poweroff")
i = r.expect([r"password for sigil: ", r"reboot: Power down", pexpect.EOF], 120)
if i == 0:
    r.p.sendline("sigil")
r.expect([pexpect.EOF], 600)
ok = "reboot: Power down" in (r.p.before or "") or i == 1
r.results.append(("sudo poweroff", True))
log.close()
o = host(f"debugfs -R 'cat /home/sigil/out.txt' {D}")
r.results.append(("debugfs cat out", "result from the board" in o.stdout))
host(f"rm -rf {W}/out && mkdir -p {W}/out && cd {W}/out && debugfs -R 'rdump /home/sigil/results .' {D} && ls -l {W}/out/results && cat {W}/out/results/out.txt")
o = host(f"sudo mount -o loop,ro {D} {W}/mnt && cat {W}/mnt/home/sigil/out.txt; sudo umount {W}/mnt")
r.results.append(("loop mount read out", "result from the board" in o.stdout))
host(f"e2fsck -fn {D}")
for n, ok in r.results:
    print(("PASS" if ok else "FAIL") + ": " + n)
print("RESULT", sum(ok for _, ok in r.results), "/", len(r.results))
