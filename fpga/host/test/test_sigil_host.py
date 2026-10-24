#!/usr/bin/env python3
"""Host-side test of sigil_host without an FPGA (#75).

  python3 fpga/host/test/test_sigil_host.py BUILD/sigil_host_mock

BUILD/sigil_host_mock is sigil_host.c built against the SDK/CL mock
(test/sigil_host_mock.c; `make -C fpga/host test` builds and runs it).
Runs the F2 Linux flow of the 100 MHz Debian trial (--linux --fw --image
--dtb --load 0xC80000000=disk --save ... --console --on-reboot exit) on
a fresh "AFI" (DDR4 not scrubbed yet, so sigil_host scrubs before the
loads) with:
  1. relative paths from the image directory (trial run 1) -> the images
     reach SoC memory, the guest's disk write comes back with --save
  2. relative paths, the saved disk reloaded, DDR4 already scrubbed
     (trial run 2) -> the guest finds its stamp
  3. ../ paths from a subdirectory, a 62.5 MHz DTB on the 100 MHz AFI
     -> loaded, timebase-frequency rewritten to the core clock
  4. absolute paths from another directory (the trial's workaround)
  5. relative paths from the wrong directory -- what the trial driver
     did after sourcing aws-fpga's sdk_setup.sh from outside the
     aws-fpga checkout, which left its shell in that checkout -> exit 3
     before the FPGA is touched, the error names the directory
  6. a --save into a missing directory -> exit 3 before the FPGA
"""
import os
import struct
import subprocess
import sys
import tempfile
import time

BIN = os.path.abspath(sys.argv[1])
LINUX = sys.platform.startswith("linux")   # the real mmap build (else SV_TEST)
DISK_PA, DTB_PA, STAMP_OFF = 0xC80000000, 0x83000000, 0x1000


def pattern(n, seed):
    """Deterministic pseudo-random bytes."""
    out = bytearray(n)
    x = seed & 0xFFFFFFFF or 1
    for i in range(0, n, 4):
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        out[i:i + 4] = struct.pack("<I", x)[: n - i]
    return bytes(out)


def fdt(timebase):
    """Minimal flattened device tree: /cpus/timebase-frequency,
    /cpus/cpu@0/timebase-frequency, /chosen/rng-seed. Returns the blob
    and the offsets of the two timebase values and of the seed."""
    strings = b"timebase-frequency\0rng-seed\0"
    st = bytearray()
    offs = {}

    def node(name):
        st.extend(struct.pack(">I", 1) + name + b"\0")
        while len(st) % 4:
            st.append(0)

    def prop(nameoff, value, key):
        st.extend(struct.pack(">III", 3, len(value), nameoff))
        offs[key] = len(st)
        st.extend(value)
        while len(st) % 4:
            st.append(0)

    node(b"")
    node(b"cpus")
    prop(0, struct.pack(">I", timebase), "tb_cpus")
    node(b"cpu@0")
    prop(0, struct.pack(">I", timebase), "tb_cpu0")
    st.extend(struct.pack(">I", 2))
    st.extend(struct.pack(">I", 2))
    node(b"chosen")
    prop(19, bytes(32), "seed")
    st.extend(struct.pack(">I", 2))
    st.extend(struct.pack(">I", 2))
    st.extend(struct.pack(">I", 9))
    off_struct = 40 + 16
    off_strings = off_struct + len(st)
    total = off_strings + len(strings)
    hdr = struct.pack(">10I", 0xD00DFEED, total, off_struct, off_strings, 40, 17, 16, 0,
                      len(strings), len(st))
    blob = hdr + bytes(16) + bytes(st) + strings
    return blob, {k: off_struct + v for k, v in offs.items()}


def run(name, cwd, args, env_extra, timeout=120):
    log = os.path.join(T, f"mock-{name}.log")
    env = dict(os.environ, MOCK_LOG=log, MOCK_CLK_KHZ="100000", **env_extra)
    t0 = time.monotonic()
    p = subprocess.run([BIN] + args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                       capture_output=True, text=True, errors="replace", timeout=timeout)
    events = open(log).read().splitlines() if os.path.exists(log) else []
    return p.returncode, p.stdout, p.stderr, events, time.monotonic() - t0


results = []


def check(case, cond, what, detail=""):
    results.append((case, what, bool(cond)))
    print(f"  {'ok  ' if cond else 'FAIL'} {what}" + ("" if cond else f"\n       {detail}"))


def show(rc, out, err):
    print("    --- sigil_host stderr ---\n" + "".join("    " + l + "\n" for l in err.splitlines()[-25:]))
    print("    --- UART ---\n" + "".join("    " + l + "\n" for l in out.splitlines()[-10:]))


with tempfile.TemporaryDirectory(prefix="sigil-host-test-") as T:
    T = os.path.realpath(T)
    data = os.path.join(T, "os73")             # the trial's image directory
    awsfpga = os.path.join(T, "aws-fpga")      # where sdk_setup.sh leaves the shell
    sub = os.path.join(data, "sub")
    for d in (data, awsfpga, sub):
        os.makedirs(d)
    imgs = {
        "fw_jump.bin": pattern(277840, 1),                    # not a multiple of 64
        "Image": pattern(15470592 // 8 + 12, 2),              # 1.9 MB, padded
        "sigil-debian-13-riscv64.ext4": pattern(17 << 20, 3), # >= 16 MiB: copy threads, mmap
    }
    for n, b in imgs.items():
        open(os.path.join(data, n), "wb").write(b)
    dtb100, dtb_offs = fdt(100000000)
    dtb62, _ = fdt(62500000)
    open(os.path.join(data, "sigil-f2-100.dtb"), "wb").write(dtb100)
    open(os.path.join(data, "sigil-f2.dtb"), "wb").write(dtb62)
    disk = imgs["sigil-debian-13-riscv64.ext4"]
    stamp = f"sigil-persist-{int(time.time())}"

    def linux_args(prefix, dtb, disk_in, disk_out, dtb_out):
        return ["--linux", "--fw", prefix + "fw_jump.bin", "--image", prefix + "Image",
                "--dtb", prefix + dtb, "--console", "--on-reboot", "exit",
                "--load", f"0x{DISK_PA:X}={prefix}{disk_in}",
                "--save", f"0x{DISK_PA:X}={prefix}{disk_out}:17M",
                "--save", f"0x{DTB_PA:X}={prefix}{dtb_out}:{len(dtb100)}"]

    def expect(prefix_dir, disk_in):
        return {"MOCK_EXPECT": ";".join([f"0x80000000={prefix_dir}/fw_jump.bin",
                                         f"0x80200000={prefix_dir}/Image",
                                         f"0x{DISK_PA:X}={prefix_dir}/{disk_in}"])}

    def dtb_timebases(path):
        b = open(path, "rb").read() if os.path.exists(path) else bytes(len(dtb100))
        return [struct.unpack(">I", b[dtb_offs[k]:dtb_offs[k] + 4])[0] for k in ("tb_cpus", "tb_cpu0")], \
            b[dtb_offs["seed"]:dtb_offs["seed"] + 32]

    print(f"sigil_host host test: {BIN} ({'Linux host build' if LINUX else 'SV_TEST seam'})")

    # 1 --------------------------------------------------------------------
    case = "1 relative paths, fresh AFI (trial run 1)"
    print(case)
    rc, out, err, ev, dt = run("1", data, linux_args("", "sigil-f2-100.dtb", "sigil-debian-13-riscv64.ext4",
                                                     "sigil-disk-saved.ext4", "dtb-in-memory.bin"),
                               dict(expect(data, "sigil-debian-13-riscv64.ext4"),
                                    MOCK_HOST_FLAGS="0", MOCK_STAMP=f"0x{DISK_PA + STAMP_OFF:X}={stamp}"))
    check(case, rc == 0, f"exit 0 (got {rc}, {dt:.1f} s)", err.splitlines()[-3:] if err else "")
    i_scrub = err.find("scrubbed DDR4 (64 GiB)")
    i_disk = err.find("loaded sigil-debian-13-riscv64.ext4:")
    check(case, 0 <= i_scrub < i_disk, "DDR4 scrubbed, then the relative --load loaded")
    check(case, f"relative paths resolve against {data}" in err, "working directory reported")
    check(case, sum(e.startswith("engine fill-zero") for e in ev) == 16, "scrub = 16 x 4 GiB engine fills")
    check(case, "MOCK SOC: images ok" in out, "fw, Image and disk intact in SoC memory at release")
    saved = os.path.join(data, "sigil-disk-saved.ext4")
    want = disk[:STAMP_OFF] + stamp.encode() + disk[STAMP_OFF + len(stamp):]
    check(case, os.path.exists(saved) and open(saved, "rb").read() == want,
          "relative --save wrote the disk with the guest's stamp")
    tb, seed = dtb_timebases(os.path.join(data, "dtb-in-memory.bin"))
    check(case, tb == [100000000, 100000000] and "= the core clock" in err, "DTB timebase 100 MHz kept")
    if LINUX:
        check(case, seed != bytes(32), "/chosen/rng-seed filled")
    if any(not ok for c, _, ok in results if c == case):
        show(rc, out, err)

    # 2 --------------------------------------------------------------------
    case = "2 relative paths, saved disk, DDR4 already scrubbed (trial run 2)"
    print(case)
    rc, out, err, ev, dt = run("2", data, linux_args("", "sigil-f2-100.dtb", "sigil-disk-saved.ext4",
                                                     "sigil-disk-saved2.ext4", "dtb-in-memory2.bin"),
                               dict(expect(data, "sigil-disk-saved.ext4"), MOCK_HOST_FLAGS="1",
                                    MOCK_STAMP=f"0x{DISK_PA + STAMP_OFF:X}={stamp}-2"))
    check(case, rc == 0, f"exit 0 (got {rc}, {dt:.1f} s)")
    check(case, "scrubbed" not in err and not any(e.startswith("engine") for e in ev), "no second scrub")
    check(case, f"MOCK SOC: stamp was '{stamp}" in out, "guest finds the stamp of run 1")
    saved2 = os.path.join(data, "sigil-disk-saved2.ext4")
    check(case, os.path.exists(saved2) and open(saved2, "rb").read()[STAMP_OFF:STAMP_OFF + len(stamp) + 2]
          == (stamp + "-2").encode(), "second save has the new stamp")
    if any(not ok for c, _, ok in results if c == case):
        show(rc, out, err)

    # 3 --------------------------------------------------------------------
    case = "3 ../ paths from a subdirectory, 62.5 MHz DTB on the 100 MHz AFI"
    print(case)
    rc, out, err, ev, dt = run("3", sub, linux_args("../", "sigil-f2.dtb", "sigil-debian-13-riscv64.ext4",
                                                    "sigil-disk-saved3.ext4", "dtb-in-memory3.bin"),
                               dict(expect(data, "sigil-debian-13-riscv64.ext4"), MOCK_HOST_FLAGS="0"))
    check(case, rc == 0, f"exit 0 (got {rc}, {dt:.1f} s)")
    check(case, "MOCK SOC: images ok" in out, "images intact")
    tb, _ = dtb_timebases(os.path.join(data, "dtb-in-memory3.bin"))
    check(case, tb == [100000000, 100000000], f"timebase-frequency rewritten to 100 MHz in memory (got {tb})")
    check(case, open(os.path.join(data, "sigil-f2.dtb"), "rb").read() == dtb62, "the DTB file is unchanged")
    if any(not ok for c, _, ok in results if c == case):
        show(rc, out, err)

    # 4 --------------------------------------------------------------------
    case = "4 absolute paths from another directory (the trial's workaround)"
    print(case)
    rc, out, err, ev, dt = run("4", awsfpga, linux_args(data + "/", "sigil-f2-100.dtb",
                                                        "sigil-debian-13-riscv64.ext4",
                                                        "sigil-disk-saved4.ext4", "dtb-in-memory4.bin"),
                               dict(expect(data, "sigil-debian-13-riscv64.ext4"), MOCK_HOST_FLAGS="0"))
    check(case, rc == 0, f"exit 0 (got {rc}, {dt:.1f} s)")
    check(case, "MOCK SOC: images ok" in out and "relative paths" not in err, "images intact, no relative paths")
    if any(not ok for c, _, ok in results if c == case):
        show(rc, out, err)

    # 5 --------------------------------------------------------------------
    case = "5 relative paths from the wrong directory (trial attempt 0)"
    print(case)
    rc, out, err, ev, dt = run("5", awsfpga, linux_args("", "sigil-f2-100.dtb", "sigil-debian-13-riscv64.ext4",
                                                        "sigil-disk-saved5.ext4", "dtb-in-memory5.bin"),
                               {"MOCK_HOST_FLAGS": "0"})
    msg = (f"cannot open sigil-debian-13-riscv64.ext4: No such file or directory "
           f"(relative to the working directory {awsfpga})")
    check(case, rc == 3, f"exit 3 (got {rc})")
    check(case, msg in err, "error names the file and the working directory", err.strip()[-300:])
    check(case, not ev, "nothing touched: no SDK call, no scrub", ev[:3])
    if any(not ok for c, _, ok in results if c == case):
        show(rc, out, err)

    # 6 --------------------------------------------------------------------
    case = "6 --save into a missing directory"
    print(case)
    args = linux_args("", "sigil-f2-100.dtb", "sigil-debian-13-riscv64.ext4", "nodir/saved.ext4", "dtb6.bin")
    rc, out, err, ev, dt = run("6", data, args, {"MOCK_HOST_FLAGS": "0"})
    check(case, rc == 3 and "cannot create nodir/saved.ext4: No such file or directory "
          f"(relative to the working directory {data})" in err, f"exit 3 naming the path (got {rc})",
          err.strip()[-300:])
    check(case, not ev, "nothing touched", ev[:3])

bad = [f"{c}: {w}" for c, w, ok in results if not ok]
print(f"\n{len(results) - len(bad)}/{len(results)} checks passed")
if bad:
    print("FAILED:\n  " + "\n  ".join(bad))
    sys.exit(1)
print("SIGIL HOST TESTS PASS")
