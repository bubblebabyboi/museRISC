#!/usr/bin/env python3
"""riscv-dv random-instruction regression: Sigil core vs Spike (issue #8).

For every (test, seed): generate a program with the riscv-dv Python
generator (pygen, target 'sigil'), assemble it, run it on Spike with
--log-commits and on the Verilated core (core_tb with the retire
trace), then compare the two commit traces (rdv_trace.py). One CSV row
per (test, seed):

  PASS         traces match up to the HTIF tohost store, both exit 0
  MISMATCH     the DUT finished, but its trace diverges from Spike
  DUT_TIMEOUT  core_tb hit its cycle limit (or the wall-clock limit)
  DUT_FAIL     core_tb reported a failing tohost value or crashed
  GEN_FAIL     pygen or the assembler failed
  SPIKE_FAIL   Spike failed or did not reach tohost=1

The first-divergence column is filled for MISMATCH and, when the
traces differ, for DUT_FAIL / DUT_TIMEOUT too.

Run through scripts/riscv_dv_regress.sh (sets up the environment) or
`make -C sim riscv-dv`; see docs/VERIFICATION.md.
"""

import argparse
import concurrent.futures
import csv
import os
import shlex
import shutil
import subprocess
import sys
import time
import zlib

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import rdv_trace  # noqa: E402

BUILD = os.path.join(ROOT, "build", "riscv-dv")
GEN_DIR = os.path.join(BUILD, "gen")              # patched pygen copy
VENV_PY = os.path.join(BUILD, "venv", "bin", "python3")
USER_EXT = os.path.join(HERE, "user_extension")
LINK_LD = os.path.join(ROOT, "third_party", "riscv-dv", "scripts", "link.ld")
TESTLIST = os.path.join(HERE, "testlist.yaml")

# Assembler ISA: what pygen emits plus Zcb, so the assembler's
# automatic compression also produces Zcb encodings.
MARCH = "rv64gc_zba_zbb_zbc_zbs_zbkb_zcb"
MABI = "lp64"
# Reference model configured as Sigil (docs/VERIFICATION.md "Spike"):
# misa reads 0x8000_0000_0034_11AF on both. Misaligned accesses trap
# (no Zicclsm), 16 PMP entries with G=0 (4-byte grain), no triggers,
# WFI completes like a NOP.
SPIKE_ISA = ("rv64imafdcbvh_zicsr_zifencei_zicntr_zbc_zbkb_zbkc_zbkx"
             "_zkne_zknd_zknh_zicond_zcb_zvl512b_svnapot")
SPIKE_ARGS = ["--isa=" + SPIKE_ISA, "--priv=msu", "--triggers=0",
              "--pmpregions=16", "--pmpgranularity=4", "--wfi-as-nop"]
# Seeded random bus latency/backpressure, as in `make riscv-tests`.
CORE_TB_BUS = ["--mem-lat", "1:6", "--mem-gap", "2", "--mem-ready", "70"]

STATUSES = ["PASS", "MISMATCH", "DUT_TIMEOUT", "DUT_FAIL", "GEN_FAIL", "SPIKE_FAIL"]
FIELDS = ["test", "seed", "gen_seed", "status", "first_divergence", "ref_records",
          "dut_records", "dut_cycles", "gen_s", "spike_s", "dut_s", "dir",
          "asm", "elf", "spike_log", "dut_trace", "ref_csv", "dut_csv", "report"]


def load_testlist(path):
    with open(path) as fh:
        entries = yaml.safe_load(fh)
    supported, excluded = [], []
    for e in entries:
        (excluded if "excluded" in e else supported).append(e)
    return supported, excluded


def parse_seeds(spec):
    seeds = []
    for part in str(spec).split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            lo, hi = part.split("-", 1)
            seeds.extend(range(int(lo), int(hi) + 1))
        else:
            seeds.append(int(part))
    return seeds


def gen_opts(entry, instr_cnt):
    """riscv-dv '+opt=val' gen_opts -> pygen '--opt=val' arguments."""
    out = []
    for tok in shlex.split(entry.get("gen_opts", "")):
        if not tok.startswith("+"):
            raise ValueError("%s: bad gen_opt %r" % (entry["test"], tok))
        tok = "--" + tok[1:]
        if instr_cnt and tok.startswith("--instr_cnt="):
            tok = "--instr_cnt=%d" % instr_cnt
        out.append(tok)
    return out


def tail(path, n=3):
    try:
        with open(path, errors="replace") as fh:
            lines = [l.strip() for l in fh if l.strip()]
        return " | ".join(lines[-n:])
    except OSError:
        return ""


def run_cmd(cmd, log, cwd=None, timeout=None):
    """Run cmd with stdout+stderr to log. Returns (rc, seconds); rc is
    None on timeout."""
    t0 = time.time()
    with open(log, "w") as fh:
        fh.write("$ %s\n" % " ".join(shlex.quote(c) for c in cmd))
        fh.flush()
        try:
            rc = subprocess.run(cmd, cwd=cwd, stdout=fh, stderr=subprocess.STDOUT,
                                timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            rc = None
    return rc, round(time.time() - t0, 1)


def spike_wrote_tohost(log, tohost):
    """Spike stops shortly after the HTIF tohost store: look for it in
    the tail of the commit log."""
    pat = " mem 0x%016x 0x" % tohost
    try:
        with open(log, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            fh.seek(max(0, fh.tell() - (1 << 20)))
            data = fh.read().decode(errors="replace")
    except OSError:
        return False
    return pat in data


def gen_seed(test, seed):
    """pygen seed for (test, seed). pygen draws everything, including the
    boot mode, from one random stream seeded with this value, so using
    the bare seed would give every test the same boot mode per seed."""
    return (zlib.crc32(test.encode()) + seed) & 0x7FFFFFFF


def run_one(entry, seed, a):
    test = entry["test"]
    d = os.path.join(a.out, test, str(seed))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    p = {k: os.path.join(d, v) for k, v in {
        "asm": "%s_0.S" % test, "elf": "%s.elf" % test, "spike_log": "spike.log",
        "dut_trace": "dut.trace", "ref_csv": "ref.csv", "dut_csv": "dut.csv",
        "report": "compare.txt"}.items()}
    row = {"test": test, "seed": seed, "gen_seed": gen_seed(test, seed), "dir": d,
           "first_divergence": "",
           "ref_records": "", "dut_records": "", "dut_cycles": "",
           "gen_s": "", "spike_s": "", "dut_s": ""}
    row.update(p)

    def done(status, why=""):
        row["status"] = status
        if why:
            row["first_divergence"] = why
        return row

    # 1. Generate (pygen) and assemble. A directed entry ('asm:', like
    #    riscv-dv's --asm_test) skips generation; its seed only varies
    #    the DUT bus timing.
    if "asm" in entry:
        shutil.copyfile(os.path.join(HERE, entry["asm"]), p["asm"])
        row["gen_s"] = 0
    else:
        cmd = [a.venv_py, "pygen/pygen_src/test/riscv_instr_base_test.py",
               "--target=sigil", "--gen_test=%s" % entry.get("gen_test", "riscv_instr_base_test"),
               "--num_of_tests=1", "--start_idx=0", "--seed=%d" % row["gen_seed"],
               "--asm_file_name=%s" % os.path.join(d, test),
               "--log_file_name=%s" % os.path.join(d, "gen.log")] + gen_opts(entry, a.instr_cnt)
        rc, row["gen_s"] = run_cmd(cmd, os.path.join(d, "gen.out"), cwd=a.gen_dir,
                                   timeout=a.gen_timeout)
        if rc != 0 or not os.path.exists(p["asm"]):
            return done("GEN_FAIL", "pygen %s: %s" % (
                "timeout" if rc is None else "rc=%d" % rc, tail(os.path.join(d, "gen.out"), 2)))
    cmd = [a.gcc, "-march=" + entry.get("march", MARCH), "-mabi=" + MABI, "-static", "-mcmodel=medany",
           "-fvisibility=hidden", "-nostdlib", "-nostartfiles", p["asm"],
           "-I", USER_EXT, "-T", LINK_LD, "-o", p["elf"]]
    rc, _ = run_cmd(cmd, os.path.join(d, "gcc.out"), timeout=300)
    if rc != 0:
        return done("GEN_FAIL", "gcc rc=%s: %s" % (rc, tail(os.path.join(d, "gcc.out"), 2)))

    # 2. Reference.
    cmd = [a.spike] + SPIKE_ARGS + ["-l", "--log-commits", "--log=" + p["spike_log"],
                                    "--instructions=%d" % a.max_instr, p["elf"]]
    rc, row["spike_s"] = run_cmd(cmd, os.path.join(d, "spike.out"), timeout=a.sim_timeout)
    if rc != 0:
        return done("SPIKE_FAIL", "spike %s: %s" % (
            "timeout" if rc is None else "rc=%d" % rc, tail(os.path.join(d, "spike.out"), 2)))
    # A program that never reaches tohost on the reference (generator
    # problem) is a SPIKE_FAIL; do not spend the DUT cycle budget on it.
    tohost = rdv_trace.elf_symbols(p["elf"]).get("tohost")
    if tohost is None or not spike_wrote_tohost(p["spike_log"], tohost):
        return done("SPIKE_FAIL", "reference did not write tohost within %d instructions"
                    % a.max_instr)

    # 3. DUT.
    cmd = [a.core_tb, p["elf"], str(a.max_cycles), "--drain", "64",
           "+sigil_trace=" + p["dut_trace"]] + CORE_TB_BUS + ["--mem-seed", str(seed)]
    dut_rc, row["dut_s"] = run_cmd(cmd, os.path.join(d, "dut.out"), timeout=a.sim_timeout)
    dut_msg = tail(os.path.join(d, "dut.out"), 1)
    for tok in dut_msg.replace("(", " ").split():
        if tok.isdigit():
            row["dut_cycles"] = tok
    if not os.path.exists(p["dut_trace"]):
        open(p["dut_trace"], "w").close()

    # 4. Compare.
    try:
        res = rdv_trace.run(p["elf"], p["spike_log"], p["dut_trace"],
                            p["ref_csv"], p["dut_csv"], p["report"])
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as e:
        return done("DUT_FAIL", "trace compare error: %s" % e)
    row["ref_records"] = res["ref_records"]
    row["dut_records"] = res["dut_records"]
    if not res["ref_tohost"] or res["ref_exit"] != 1:
        return done("SPIKE_FAIL", "reference did not end with tohost=1 (%s)" % res["ref_exit"])
    why = res["divergence"]
    if dut_rc is None:
        return done("DUT_TIMEOUT", why or "wall-clock limit (%ds)" % a.sim_timeout)
    if dut_rc == 2:
        return done("DUT_TIMEOUT", why or dut_msg)
    if dut_rc != 0:
        return done("DUT_FAIL", why or dut_msg)
    if not res["ok"]:
        return done("MISMATCH", why)
    if not a.keep:
        for k in ("spike_log", "dut_trace"):
            os.remove(p[k])
            row[k] = ""
    return done("PASS")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--tests", default="all",
                    help="comma-separated test names, or 'all' (default)")
    ap.add_argument("--seeds", default="1,2,3", help="e.g. 1,2,3 or 1-10 (default 1,2,3)")
    ap.add_argument("--jobs", type=int, default=min(16, os.cpu_count() or 1))
    ap.add_argument("--out", default=os.path.join(BUILD, "run"))
    ap.add_argument("--csv", help="results CSV (default <out>/results.csv)")
    ap.add_argument("--instr-cnt", type=int, default=0,
                    help="override every test's +instr_cnt (quick runs)")
    ap.add_argument("--max-cycles", type=int, default=5_000_000,
                    help="core_tb cycle limit (DUT_TIMEOUT beyond)")
    ap.add_argument("--max-instr", type=int, default=2_000_000,
                    help="Spike instruction limit (SPIKE_FAIL beyond)")
    ap.add_argument("--gen-timeout", type=int, default=1800)
    ap.add_argument("--sim-timeout", type=int, default=900)
    ap.add_argument("--keep", action="store_true",
                    help="keep Spike logs and DUT traces of passing runs")
    ap.add_argument("--list", action="store_true", help="list tests and exit")
    ap.add_argument("--core-tb", default=os.path.join(ROOT, "build", "sim", "core_tb"))
    ap.add_argument("--spike", default=os.environ.get("SPIKE") or shutil.which("spike")
                    or os.path.expanduser("~/opt/spike/bin/spike"))
    ap.add_argument("--gcc", default="riscv64-unknown-elf-gcc")
    ap.add_argument("--gen-dir", default=GEN_DIR)
    ap.add_argument("--venv-py", default=VENV_PY)
    a = ap.parse_args()
    a.out = os.path.abspath(a.out)

    supported, excluded = load_testlist(TESTLIST)
    if a.list:
        for e in supported:
            print("%-40s %s" % (e["test"], e["asm"] if "asm" in e else " ".join(gen_opts(e, 0))))
        for e in excluded:
            print("%-40s EXCLUDED: %s" % (e["test"], " ".join(e["excluded"].split())))
        return 0
    names = [e["test"] for e in supported]
    if a.tests != "all":
        want = [t.strip() for t in a.tests.split(",") if t.strip()]
        bad = [t for t in want if t not in names]
        if bad:
            print("unknown or excluded test(s): %s (see --list)" % ", ".join(bad),
                  file=sys.stderr)
            return 2
        supported = [e for e in supported if e["test"] in want]
    seeds = parse_seeds(a.seeds)
    for path, what in ((a.core_tb, "core_tb (make -C sim ../build/sim/core_tb)"),
                       (a.spike, "spike (set SPIKE=)"),
                       (os.path.join(a.gen_dir, "pygen"), "pygen copy (scripts/riscv_dv_setup.sh)"),
                       (a.venv_py, "venv (scripts/riscv_dv_setup.sh)"), (LINK_LD, "riscv-dv clone")):
        if not path or not os.path.exists(path):
            print("missing %s: %s" % (what, path), file=sys.stderr)
            return 2
    os.makedirs(a.out, exist_ok=True)
    out_csv = a.csv or os.path.join(a.out, "results.csv")
    jobs = [(e, s) for e in supported for s in seeds]
    print("riscv-dv regression: %d tests x %d seeds = %d runs, %d parallel, out %s"
          % (len(supported), len(seeds), len(jobs), a.jobs, a.out), flush=True)
    rows = []
    t0 = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = {ex.submit(run_one, e, s, a): (e["test"], s) for e, s in jobs}
        for f in concurrent.futures.as_completed(futs):
            test, seed = futs[f]
            try:
                row = f.result()
            except Exception as e:  # keep the regression going
                row = {"test": test, "seed": seed, "status": "GEN_FAIL",
                       "first_divergence": "driver error: %r" % e}
            rows.append(row)
            print("%-11s %s seed %s %s" % (row["status"], test, seed,
                                          row.get("first_divergence", "")[:200]), flush=True)
    order = {e["test"]: i for i, e in enumerate(supported)}
    rows.sort(key=lambda r: (order.get(r["test"], 0), int(r["seed"])))
    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
    counts = {s: sum(1 for r in rows if r["status"] == s) for s in STATUSES}
    print("summary: %s (%d runs, %.0f s) -> %s" % (
        ", ".join("%s %d" % (s, n) for s, n in counts.items() if n), len(rows),
        time.time() - t0, out_csv))
    return 0 if counts["PASS"] == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
