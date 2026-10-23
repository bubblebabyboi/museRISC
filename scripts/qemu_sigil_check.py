#!/usr/bin/env python3
"""Automated acceptance run for Sigil Debian (issue #70), QEMU or F2.

Boots scripts/qemu_sigil_boot.sh (or any console command, e.g. sigil_host
on an F2 with --cmd), waits for SIGIL_LINUX_BOOT_OK and the login
prompt, logs in over the serial console and runs the checks from
docs/LINUX.md: gcc hello, malloc, numactl --hardware (two nodes),
--membind=1 placement in node 1, an RVV (Zve64d) user program, sudo,
a file written to the pmem disk surviving a reboot, then poweroff.
Writes the console transcript and a summary with timings.

  python3 scripts/qemu_sigil_check.py [--log FILE] [--fresh] [--icount]
  python3 scripts/qemu_sigil_check.py --cmd 'sudo sigil_host ... --console' \
      --scale 40 --no-reboot --label F2        # F2: reboot reloads the disk
  python3 scripts/qemu_sigil_check.py --cmd '...' --persist-check STAMP

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
    def __init__(self, cmd, log, timeout_scale, release=None):
        self.release = release
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
        if self.release:            # host loads the images first (F2)
            self.expect([self.release], 1800)
            self.mark("SoC released (host: " + self.release + ")")
            self.release = None
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
    ap.add_argument("--cmd", help="console command to run instead of QEMU "
                    "(shell string, e.g. sigil_host --console ...)")
    ap.add_argument("--scale", type=float, help="timeout multiplier")
    ap.add_argument("--label", default="QEMU", help="platform name in the summary")
    ap.add_argument("--release", help="regex the console command prints when the "
                    "SoC starts (e.g. 'SoC released' for sigil_host); times are "
                    "then also measured from it")
    ap.add_argument("--no-reboot", action="store_true",
                    help="skip the reboot round (poweroff after the checks)")
    ap.add_argument("--stamp", default=str(int(time.time())),
                    help="content tag of the file written to the disk")
    ap.add_argument("--persist-check", metavar="STAMP",
                    help="only log in as root, check ~sigil/persist.txt, power off")
    a = ap.parse_args()

    if a.cmd:
        cmd = ["bash", "-c", a.cmd]
    else:
        cmd = ["bash", "scripts/qemu_sigil_boot.sh"]
        if a.fresh:
            cmd.append("--fresh")
        if a.icount:
            cmd.append("--icount")
    scale = a.scale or (20 if a.icount else 1)
    with open(a.log, "w") as log:
        r = Run(cmd, log, scale, a.release)
        if a.persist_check:
            r.login("root", 900)
            r.sh("cat /home/sigil/persist.txt", check=f"^sigil-persist-{a.persist_check}$",
                 name="file survived power-off, save and reload")
            r.sh("systemd-analyze; journalctl --list-boots --no-pager | tail -3", 600)
            poweroff(r)
        elif a.icount:
            r.login("sigil", 900)
            # guest time = 16 ns per instruction (62.5 MHz at IPC 1)
            r.sh("cat /proc/uptime", 600)
            r.sh("systemd-analyze; systemd-analyze blame --no-pager | head -25", 1200,
                 r"Startup finished", "systemd-analyze (icount)")
            r.sh("time (gcc -O2 -o /tmp/h examples/hello.c && /tmp/h)", 1200,
                 r"Hello from sigil", "gcc hello (icount)")
            r.sh("time python3 -c 'print(42)'", 1200, r"^42$", "python3 start (icount)")
            r.p.sendline("sudo poweroff")
            r.expect([r"\[sudo\] password for sigil: "], 120)
            r.p.sendline(PASSWORD)
            r.expect([pexpect.EOF], 1200)
            r.mark("powered off")
        else:
            r.login("sigil", 900)
            checks(r, a.stamp, not a.no_reboot)
        log.flush()

    print(f"\nSummary ({a.label}{', not FPGA timings' if a.label == 'QEMU' else ''}):")
    for what, t in r.marks:
        print(f"  {t:8.1f} s  {what}")
    bad = [n for n, ok in r.results if not ok]
    print(f"{len(r.results) - len(bad)}/{len(r.results)} checks passed")
    if bad:
        print("FAILED: " + ", ".join(bad))
        return 1
    print(f"{a.label.upper()} SIGIL DEBIAN CHECK PASS")
    return 0


def poweroff(r):
    r.p.sendline("poweroff")
    r.mark("poweroff requested")
    i = r.expect([pexpect.EOF, pexpect.TIMEOUT], 600)
    ok = i == 0 and "reboot: Power down" in r.p.before
    r.results.append(("poweroff ends the run (test finisher 0x5555)", ok))
    r.mark(("PASS" if ok else "FAIL") + ": poweroff")


def guest_clock(r, tag):
    """Guest wall clock (date) vs host wall clock, for the timebase check."""
    h0 = time.time()
    out, _ = r.sh("date -u +%s.%N", 300)
    h1 = time.time()
    try:
        g = float(out.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None
    host = (h0 + h1) / 2
    r.mark(f"clock {tag}: guest {g:.3f} host {host:.3f} offset {g - host:+.3f} s")
    return g, host


def checks(r, stamp, do_reboot):
    clk0 = guest_clock(r, "after login")
    r.sh("uname -a; . /etc/os-release; echo \"$PRETTY_NAME\"; cat /etc/sigil-release",
         check=r"6\.12\.\d+-sigil .*riscv64[\s\S]*Debian GNU/Linux 13",
         name="kernel 6.12 + Debian 13")
    r.sh("cat /proc/cpuinfo; nproc; cat /proc/device-tree/model; echo",
         check=r"zve64d", name="cpu isa has zve64d")
    r.sh("systemctl is-system-running --wait; systemctl --failed --no-legend",
         check=r"^running", name="systemd running, no failed units")
    r.sh("findmnt -n /; df -h /; ls -l /dev/pmem0; cat /sys/block/pmem0/size",
         check=r"/dev/pmem0\s+ext4\s+rw", name="root on /dev/pmem0 (ext4, rw)")
    r.sh("free -h; free -m; cat /sys/devices/system/node/online", check=r"^0-1$",
         name="nodes 0-1 online")
    r.sh("numactl --hardware", check=r"available: 2 nodes \(0-1\)[\s\S]*node 1 size: 16\d\d\d MB",
         name="numactl --hardware: 2 nodes, node 1 = 16 GiB")
    r.sh("cd ~/examples && rm -f a.out && time (gcc hello.c && ./a.out)",
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
    r.sh("time python3 -c 'import platform, sys; print(platform.machine(), sys.version.split()[0])'",
         check=r"riscv64 3\.", name="python3")
    r.sh("git --version; gdb --version | head -1; strace -V | head -1; vim --version | head -1; "
         "file /bin/bash; man -w printf", check=r"ELF 64-bit LSB pie executable, UCB RISC-V",
         name="GNU tools present")
    r.sh("systemd-analyze; systemd-analyze blame --no-pager | head -15", check=r"Startup finished",
         name="systemd-analyze")
    r.sh("ndctl list -N 2>/dev/null; ls /dev/rtc0 && cat /sys/class/rtc/rtc0/name; date -u")
    # Timebase: `sleep 10` must take 10 s of host wall time (plus exec
    # overhead), and the guest clock must not drift against the host's.
    h = time.time()
    r.sh("sleep 10", 300)
    dt = time.time() - h
    ok = 9.9 <= dt <= 13.0
    r.results.append((f"sleep 10 took {dt:.2f} s host wall time", ok))
    r.mark(f"{'PASS' if ok else 'FAIL'}: sleep 10 = {dt:.2f} s of host wall time")
    clk1 = guest_clock(r, "end")
    if clk0 and clk1:
        gd, hd = clk1[0] - clk0[0], clk1[1] - clk0[1]
        drift = (gd - hd) / hd
        ok = abs(drift) < 0.005
        r.results.append((f"guest clock drift {drift * 100:+.3f} % over {hd:.0f} s", ok))
        r.mark(f"{'PASS' if ok else 'FAIL'}: guest clock {gd:.1f} s vs host {hd:.1f} s "
               f"(drift {drift * 100:+.3f} %)")
    r.sh(f"echo sigil-persist-{stamp} > ~/persist.txt && sync && cat ~/persist.txt",
         check=f"^sigil-persist-{stamp}$", name="write file on pmem disk")
    if not do_reboot:
        r.p.sendline("sudo poweroff")
        r.mark("poweroff requested")
        i = r.expect([r"\[sudo\] password for sigil: ", pexpect.EOF, pexpect.TIMEOUT], 1200)
        if i == 0:
            r.p.sendline(PASSWORD)
            i = 1 + r.expect([pexpect.EOF, pexpect.TIMEOUT], 1200)
        i -= 1
        ok = i == 0 and "reboot: Power down" in r.p.before
        r.results.append(("poweroff ends the run (test finisher 0x5555)", ok))
        r.mark(("PASS" if ok else "FAIL") + ": poweroff")
        return

    # Reboot through the test finisher (0x7777); QEMU resets in place.
    r.p.sendline("sudo reboot")
    r.mark("reboot requested")
    if r.expect([r"\[sudo\] password for sigil: ", r"reboot: Restarting system"], 300) == 0:
        r.p.sendline(PASSWORD)
    r.login("root", 900)
    r.sh("cat /home/sigil/persist.txt", check=f"^sigil-persist-{stamp}$", name="file survived reboot")
    r.sh("journalctl --list-boots --no-pager | tail -3")
    poweroff(r)


if __name__ == "__main__":
    sys.exit(main())
