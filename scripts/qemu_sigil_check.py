#!/usr/bin/env python3
"""Automated QEMU acceptance run for Sigil Debian (issue #70).

Boots scripts/qemu_sigil_boot.sh, waits for SIGIL_LINUX_BOOT_OK and the
login prompt, logs in over the serial console and runs the checks from
docs/LINUX.md: gcc hello, malloc, numactl --hardware (two nodes),
--membind=1 placement in node 1, an RVV (Zve64d) user program, sudo,
a file written to the pmem disk surviving a reboot, then poweroff.
Writes the console transcript and a summary with timings.

  python3 scripts/qemu_sigil_check.py [--log FILE] [--fresh] [--icount]

Needs python3-pexpect. QEMU timings are not FPGA timings.
"""
import argparse
import re
import sys
import time

import pexpect

PROMPT = "SIGILPS> "
# terminal control sequences (colours, bracketed paste, titles, keypad)
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[=>78]")
PASSWORD = "sigil"


class Run:
    def __init__(self, cmd, log, timeout_scale):
        self.t0 = time.monotonic()
        self.scale = timeout_scale
        self.p = pexpect.spawn(cmd[0], cmd[1:], encoding="utf-8",
                               codec_errors="replace", timeout=60,
                               dimensions=(50, 160))
        self.p.logfile_read = log
        self.marks = []
        self.results = []

    def t(self):
        return time.monotonic() - self.t0

    def mark(self, what):
        self.marks.append((what, self.t()))
        print(f"[{self.t():8.1f} s] {what}", file=sys.stderr, flush=True)

    def expect(self, pats, timeout):
        return self.p.expect(pats, timeout=timeout * self.scale)

    def login(self, user, boot_timeout):
        self.expect([r"SIGIL_LINUX_BOOT_OK[^\r\n]*"], boot_timeout)
        self.mark("boot marker: " + self.p.after.strip())
        self.expect([r"sigil login: "], 600)
        self.mark("login prompt")
        self.p.sendline(user)
        self.expect([r"Password: "], 120)
        self.p.sendline(PASSWORD)
        # sigil-resize asks the terminal for its size (CPR); answer it.
        while True:
            i = self.expect([r"\x1b\[6n", r"sigil@sigil\S*~\S*\$ ", r"root@sigil\S*~\S*# "], 600)
            if i == 0:
                self.p.send("\x1b[50;160R")
                continue
            break
        self.mark(f"logged in as {user}")
        self.p.sendline(f"export PS1='{PROMPT}'; stty cols 160 rows 50")
        self.expect([re.escape(PROMPT)], 60)
        self.expect([re.escape(PROMPT)], 60)

    def sh(self, cmd, timeout=300, check=None, name=None):
        self.p.sendline(cmd)
        self.expect([re.escape(PROMPT)], timeout)
        out = ANSI.sub("", self.p.before).replace("\r", "")
        ok = True
        if check is not None:
            ok = bool(re.search(check, out, re.M))
            self.results.append((name or cmd, ok))
            self.mark(f"{'PASS' if ok else 'FAIL'}: {name or cmd}")
        return out, ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default="build/debian/qemu-check.log")
    ap.add_argument("--fresh", action="store_true",
                    help="recreate the QEMU disk from the built image")
    ap.add_argument("--icount", action="store_true",
                    help="instruction-counting QEMU (62.5 MHz at IPC 1)")
    a = ap.parse_args()

    cmd = ["bash", "scripts/qemu_sigil_boot.sh"]
    if a.fresh:
        cmd.append("--fresh")
    if a.icount:
        cmd.append("--icount")
    scale = 20 if a.icount else 1
    with open(a.log, "w") as log:
        r = Run(cmd, log, scale)
        r.login("sigil", 900)

        if a.icount:
            r.sh("systemd-analyze; cat /proc/uptime", 600,
                 r"Startup finished", "systemd-analyze (icount)")
            r.p.sendline("sudo poweroff")
            r.expect([r"\[sudo\] password for sigil: "], 120)
            r.p.sendline(PASSWORD)
            r.expect([pexpect.EOF], 1200)
            r.mark("powered off")
        else:
            checks(r)
        log.flush()

    print("\nSummary (QEMU, not FPGA timings):")
    for what, t in r.marks:
        print(f"  {t:8.1f} s  {what}")
    bad = [n for n, ok in r.results if not ok]
    print(f"{len(r.results) - len(bad)}/{len(r.results)} checks passed")
    if bad:
        print("FAILED: " + ", ".join(bad))
        return 1
    print("QEMU SIGIL DEBIAN CHECK PASS")
    return 0


def checks(r):
    r.sh("uname -a; . /etc/os-release; echo \"$PRETTY_NAME\"; cat /etc/sigil-release",
         check=r"6\.12\.\d+-sigil .*riscv64[\s\S]*Debian GNU/Linux 13",
         name="kernel 6.12 + Debian 13")
    r.sh("grep -m1 '^isa' /proc/cpuinfo; nproc; cat /proc/device-tree/model; echo",
         check=r"zve64d", name="cpu isa has zve64d")
    r.sh("systemctl is-system-running --wait; systemctl --failed --no-legend",
         check=r"^running", name="systemd running, no failed units")
    r.sh("findmnt -n /; df -h /; ls -l /dev/pmem0; cat /sys/block/pmem0/size",
         check=r"/dev/pmem0\s+ext4\s+rw", name="root on /dev/pmem0 (ext4, rw)")
    r.sh("free -m; cat /sys/devices/system/node/online", check=r"^0-1$",
         name="nodes 0-1 online")
    r.sh("numactl --hardware", check=r"available: 2 nodes \(0-1\)[\s\S]*node 1 size: 16\d\d\d MB",
         name="numactl --hardware: 2 nodes, node 1 = 16 GiB")
    r.sh("cd ~/examples && rm -f a.out && gcc hello.c && ./a.out",
         check=r"^Hello from sigil on riscv64", name="gcc hello.c && ./a.out")
    r.sh("gcc --version | head -1; ld --version | head -1; ldd --version | head -1",
         check=r"gcc .*14\.", name="gcc 14 / binutils / glibc versions")
    r.sh("make", 600, check=r"rvv_vadd", name="make examples")
    r.sh("./malloc_test 512", 600, check=r"^MALLOC OK", name="malloc test")
    r.sh("./numa_hbm 256", 600, check=r"^NUMA OK \(2 nodes\)", name="numa_hbm (libnuma onnode 0 and 1)")
    r.sh("./memwhere 1024", 600, check=r"node 0: 1024 MiB$", name="default malloc lands in node 0")
    r.sh("numactl --membind=1 ./memwhere 1024", 600, check=r"node 1: 1024 MiB$",
         name="numactl --membind=1 lands in node 1")
    r.sh("numactl --interleave=0,1 ./memwhere 1024", 600,
         check=r"node 0: 512 MiB node 1: 512 MiB$", name="numactl --interleave=0,1 splits")
    r.sh("grep -E 'MemTotal|MemUsed' /sys/devices/system/node/node1/meminfo")
    r.sh("./rvv_vadd", check=r"VLEN = 512 bits[\s\S]*^RVV OK", name="RVV Zve64d user program")
    r.sh("./autovec && echo \"vector insns: $(objdump -d autovec | grep -cE '\\sv(le64|se64|fmacc|fmadd|fadd)\\.')\"",
         check=r"^autovec sum 58705920 [\s\S]*vector insns: [1-9]", name="gcc auto-vectorized Zve64d program")
    r.p.sendline("sudo -k; sudo id")
    r.expect([r"\[sudo\] password for sigil: "], 120)
    r.p.sendline(PASSWORD)
    r.expect([re.escape(PROMPT)], 120)
    ok = "uid=0(root)" in r.p.before
    r.results.append(("sudo", ok))
    r.mark(("PASS" if ok else "FAIL") + ": sudo")
    r.sh("python3 -c 'import platform, sys; print(platform.machine(), sys.version.split()[0])'",
         check=r"riscv64 3\.", name="python3")
    r.sh("git --version; gdb --version | head -1; strace -V | head -1; vim --version | head -1; "
         "file /bin/bash; man -w printf", check=r"ELF 64-bit LSB pie executable, UCB RISC-V",
         name="GNU tools present")
    r.sh("systemd-analyze; systemd-analyze blame --no-pager | head -15", check=r"Startup finished",
         name="systemd-analyze")
    r.sh("ndctl list -N 2>/dev/null; ls /dev/rtc0 && cat /sys/class/rtc/rtc0/name; date -u")
    stamp = str(int(time.time()))
    r.sh(f"echo sigil-persist-{stamp} > ~/persist.txt && sync && cat ~/persist.txt",
         check=f"^sigil-persist-{stamp}$", name="write file on pmem disk")

    # Reboot through the test finisher (0x7777); QEMU resets in place.
    r.p.sendline("sudo reboot")
    r.mark("reboot requested")
    if r.expect([r"\[sudo\] password for sigil: ", r"reboot: Restarting system"], 300) == 0:
        r.p.sendline(PASSWORD)
    r.login("root", 900)
    r.sh("cat /home/sigil/persist.txt", check=f"^sigil-persist-{stamp}$", name="file survived reboot")
    r.sh("journalctl --list-boots --no-pager | tail -3")
    r.p.sendline("poweroff")
    r.mark("poweroff requested")
    i = r.expect([pexpect.EOF, pexpect.TIMEOUT], 600)
    ok = i == 0 and "reboot: Power down" in r.p.before
    r.results.append(("poweroff ends QEMU (test finisher 0x5555)", ok))
    r.mark(("PASS" if ok else "FAIL") + ": poweroff")


if __name__ == "__main__":
    sys.exit(main())
