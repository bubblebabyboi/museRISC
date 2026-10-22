#!/usr/bin/env python3
"""Performance harness runner (issue #56, docs/PERFORMANCE.md).

Called by `make -C sim perf` (sim/perf.mk), which builds the testbenches
first and passes one --run MEM:CONFIG=TB per testbench. For every
benchmark found under sw/bench/<name>/ (a Makefile on sw/sdk/sdk.mk plus
bench.json) and every build variant it declares, this script

  1. builds the image once (make -C sw/bench/<name> OUT=... plus the
     variant's make variables and BENCH_ITERATIONS; --variants selects
     variants by name),
  2. runs it on each testbench (JOBS at a time, REPEAT times each) with
     +sigil_perf=<file>, so the simulation-only counters in sigil_cpu
     write a SIGIL_PERF record at the program's sigil_perf_end(),
  3. validates the run: testbench exit status 0 on the exit string
     "SIGIL TEST PASS <name>", every bench.json "expect" line (the
     bench's and the variant's) in the UART output, one SIGIL_PERF
     record per measured region (the bench's regions, or the variant's
     "regions" subset) with
     cycles == mcycle delta, instret == minstret delta and the per-cycle
     accounting summing to cycles, and the program's own
     "SIGIL PERF region=<id> cycles=<n> instret=<n>" line (the hardware
     counter view); with REPEAT > 1, identical numbers in every repeat,
  4. writes results.json (everything, with tool versions and the
     commit), then results.csv and report.md via perf_report.py.

A run that does not validate is reported and makes the script exit 1;
its numbers are kept in results.json under "failed" but never in the
tables.
"""

import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import time

CONFIGS = ("default", "sky130", "oreg", "fpga")
MEMS = ("soc", "axi")
PERF_RE = re.compile(r"^SIGIL_PERF v1 (.*)$")
HW_RE = re.compile(r"SIGIL PERF region=(\d+) cycles=(\d+) instret=(\d+)")


def sh(cmd, cwd=None):
    """Runs cmd, returns stripped stdout ('' on failure)."""
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              check=False).stdout.strip()
    except OSError:
        return ""


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_benches(root, wanted):
    bench_dir = os.path.join(root, "sw", "bench")
    found = {}
    for name in sorted(os.listdir(bench_dir)):
        d = os.path.join(bench_dir, name)
        meta = os.path.join(d, "bench.json")
        if not (os.path.isfile(meta) and os.path.isfile(os.path.join(d, "Makefile"))):
            continue
        with open(meta) as f:
            b = json.load(f)
        if b.get("name") != name:
            sys.exit(f"perf: {meta}: \"name\" must be the directory name {name!r}")
        if not isinstance(b.get("iterations"), int) or b["iterations"] < 1:
            sys.exit(f"perf: {meta}: \"iterations\" must be a positive integer")
        b.setdefault("max_cycles", 200000000)
        b.setdefault("expect", [])
        b.setdefault("metrics", [])
        b.setdefault("regions", {"0": "main"})
        b.setdefault("variants", {"default": {}})
        b.setdefault("bytes_per_iteration", 0)
        check_bench(meta, b)
        b["dir"] = d
        found[name] = b
    if wanted:
        missing = [w for w in wanted if w not in found]
        if missing:
            sys.exit(f"perf: no benchmark {' '.join(missing)} under {bench_dir} "
                     f"(have: {' '.join(found) or 'none'})")
        found = {w: found[w] for w in wanted}
    if not found:
        sys.exit(f"perf: no benchmarks under {bench_dir}")
    return found


REGION_NUM_KEYS = ("bytes_per_iteration", "work_per_iteration")


def region_info(b, rid):
    """bench.json "regions" entry rid as a dict: label, plus the optional
    per-region bytes_per_iteration (default: the bench's),
    work_per_iteration + work_unit and baseline (a region id)."""
    v = b["regions"][str(rid)]
    info = {"label": v} if isinstance(v, str) else dict(v)
    info.setdefault("bytes_per_iteration", b.get("bytes_per_iteration", 0))
    info.setdefault("work_per_iteration", 0)
    info.setdefault("work_unit", "")
    info.setdefault("baseline", None)
    return info


def variant_regions(b, vcfg):
    """Region ids (strings) measured by one variant: the variant's
    "regions" list, or every region of the bench."""
    sel = vcfg.get("regions")
    return [str(r) for r in sel] if sel is not None else list(b["regions"])


def check_bench(meta, b):
    """Checks the optional keys that perf_report.py relies on; exits with
    a message naming the bench.json on the first error."""
    def bad(msg):
        sys.exit(f"perf: {meta}: {msg}")
    if not isinstance(b["regions"], dict) or not b["regions"]:
        bad("\"regions\" must be a non-empty object {\"<id>\": label or {...}}")
    for rid, v in b["regions"].items():
        if not rid.isdigit() or int(rid) > 255:
            bad(f"region id {rid!r} must be 0..255")
        if isinstance(v, str):
            continue
        if not isinstance(v, dict) or not isinstance(v.get("label"), str):
            bad(f"region {rid}: a label string or an object with a \"label\"")
        for k in REGION_NUM_KEYS:
            if k in v and not (isinstance(v[k], (int, float)) and v[k] > 0):
                bad(f"region {rid}: \"{k}\" must be a positive number")
        if "work_per_iteration" in v and not v.get("work_unit"):
            bad(f"region {rid}: \"work_per_iteration\" needs a \"work_unit\"")
        if v.get("baseline") is not None and str(v["baseline"]) not in b["regions"]:
            bad(f"region {rid}: baseline {v['baseline']!r} is not a declared region")
    win = b.get("window_region")
    if win is not None and str(win) not in b["regions"]:
        bad(f"\"window_region\" {win!r} is not a declared region")
    if "bytes_per_cycle" in b["metrics"]:
        zero = [rid for rid in b["regions"] if not region_info(b, rid)["bytes_per_iteration"]]
        if zero:
            bad(f"metric bytes_per_cycle needs bytes_per_iteration (bench or region) for regions {zero}")
    if not isinstance(b["variants"], dict) or not b["variants"]:
        bad("\"variants\" must be a non-empty object")
    for vname, vcfg in b["variants"].items():
        sel = vcfg.get("regions")
        if sel is not None:
            if not isinstance(sel, list) or not sel:
                bad(f"variant {vname}: \"regions\" must be a non-empty list of region ids")
            unknown = [r for r in sel if str(r) not in b["regions"]]
            if unknown:
                bad(f"variant {vname}: regions {unknown} are not declared in \"regions\"")
        if not isinstance(vcfg.get("expect", []), list):
            bad(f"variant {vname}: \"expect\" must be a list")


def build(bench, variant, vcfg, iterations, out_root, prefix):
    out = os.path.join(out_root, "bin", f"{bench['name']}-{variant}")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    make_vars = dict(vcfg.get("make", {}))
    make_vars["OUT"] = out
    make_vars["BENCH_ITERATIONS"] = str(iterations)
    if prefix:
        make_vars["RISCV_PREFIX"] = prefix
    cmd = ["make", "-C", bench["dir"]] + [f"{k}={v}" for k, v in make_vars.items()]
    p = subprocess.run(cmd, capture_output=True, text=True, check=False)
    log = os.path.join(out, "build.log")
    with open(log, "w") as f:
        f.write("$ " + shlex.join(cmd) + "\n" + p.stdout + p.stderr)
    binary = os.path.join(out, bench["name"] + ".bin")
    if p.returncode != 0 or not os.path.isfile(binary):
        sys.exit(f"perf: build of {bench['name']} ({variant}) failed, see {log}")
    ccs = [l for l in p.stdout.splitlines() if re.match(r"^\S*gcc ", l)]
    return {"bin": binary, "elf": os.path.join(out, bench["name"] + ".elf"),
            "bin_sha256": sha256(binary), "build_log": log, "make": cmd[3:],
            "cc_command": ccs[0] if ccs else "", "cc_commands": ccs}


def parse_kv(text):
    rec = {}
    for tok in text.split():
        k, _, v = tok.partition("=")
        rec[k] = int(v) if re.fullmatch(r"-?\d+", v) else v
    return rec


def run_one(job):
    """Runs one (bench, variant, mem, config, rep); returns a result dict."""
    b, variant, vcfg, img, mem, cfg, tb, tb_args, rep, iters, max_cycles, out_root = job
    tag = f"{b['name']}-{variant}.{mem}-{cfg}.r{rep}"
    rdir = os.path.join(out_root, "runs")
    log = os.path.join(rdir, tag + ".log")
    perf_file = os.path.join(rdir, tag + ".perf")
    if os.path.exists(perf_file):
        os.remove(perf_file)
    exit_s = f"SIGIL TEST PASS {b['name']}"
    cmd = ([tb, str(max_cycles)] + shlex.split(tb_args) +
           ["--load", f"0x80000000={img['bin']}", "--exit-string", exit_s,
            "--fail-string", "SIGIL TEST FAIL", f"+sigil_perf={perf_file}"])
    t0 = time.time()
    with open(log, "w") as f:
        f.write("$ " + shlex.join(cmd) + "\n")
        f.flush()
        p = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, check=False)
    wall = time.time() - t0
    with open(log, errors="replace") as f:
        text = f.read()
    errors = []
    if p.returncode != 0:
        errors.append(f"testbench exit status {p.returncode}")
    if exit_s not in text:
        errors.append(f"no '{exit_s}'")
    for e in b["expect"] + vcfg.get("expect", []):
        e = e.replace("{iterations}", str(iters))
        if e not in text:
            errors.append(f"expected line missing: '{e}'")
    hw = {int(m.group(1)): (int(m.group(2)), int(m.group(3)))
          for m in HW_RE.finditer(text)}
    records = []
    if os.path.exists(perf_file):
        with open(perf_file) as f:
            for line in f:
                m = PERF_RE.match(line.strip())
                if m:
                    records.append(parse_kv(m.group(1)))
    regions = variant_regions(b, vcfg)
    extra = sorted({r.get("region") for r in records} - {int(k) for k in regions})
    if extra:
        errors.append(f"SIGIL_PERF records for undeclared regions {extra} (bench.json \"regions\")")
    win = b.get("window_region")
    results = []
    for rid in sorted(regions, key=int):
        info = region_info(b, rid)
        rid = int(rid)
        recs = [r for r in records if r.get("region") == rid]
        rerr = list(errors)
        if len(recs) != 1:
            rerr.append(f"region {rid}: {len(recs)} SIGIL_PERF records (want 1)")
        rec = recs[0] if recs else {}
        if rec:
            if rec["cycles"] != rec["mcycle_delta"]:
                rerr.append("cycles != mcycle delta")
            if rec["instret"] != rec["minstret_delta"]:
                rerr.append("instret != minstret delta")
            if rec["stk_sum"] != rec["cycles"]:
                rerr.append("accounting slots do not sum to cycles")
        if rid not in hw:
            rerr.append(f"region {rid}: no 'SIGIL PERF region={rid}' line")
        hwc, hwi = hw.get(rid, (None, None))
        if rec and hwc is not None and not (0 <= rec["cycles"] - hwc < 1000):
            rerr.append(f"hardware-counter cycles {hwc} far from the window {rec['cycles']}")
        results.append({
            "bench": b["name"], "variant": variant, "region": rid, "label": info["label"],
            "mem": mem, "config": cfg, "rep": rep, "iterations": iters,
            "tb": tb, "tb_args": tb_args, "log": log, "perf_file": perf_file,
            "bin_sha256": img["bin_sha256"], "wall_s": round(wall, 2),
            "hw_cycles": hwc, "hw_instret": hwi, "counters": rec,
            "metrics": b["metrics"], "bytes_per_iteration": info["bytes_per_iteration"],
            "work_per_iteration": info["work_per_iteration"], "work_unit": info["work_unit"],
            "baseline_region": None if info["baseline"] is None else int(info["baseline"]),
            "window_region": None if win is None else int(win),
            "max_cycles": max_cycles, "ok": not rerr, "errors": rerr})
    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--benches", default="")
    ap.add_argument("--run", action="append", default=[],
                    help="MEM:CONFIG=TESTBENCH (repeatable)")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--iterations", type=int)
    ap.add_argument("--variants", default="",
                    help="build variants to run, by name (default: every variant)")
    ap.add_argument("--max-cycles", type=int,
                    help="simulation cycle limit for every bench (default: bench.json max_cycles)")
    ap.add_argument("--clock-mhz", default="",
                    help="clocks (MHz) for the report's projected-throughput table")
    ap.add_argument("--riscv-prefix", default="")
    ap.add_argument("--soc-args", default="")
    ap.add_argument("--axi-args", default="")
    a = ap.parse_args()

    root = os.path.abspath(a.root)
    benches = load_benches(root, a.benches.split())
    if a.variants.split():
        want = a.variants.split()
        have = {v for b in benches.values() for v in b["variants"]}
        missing = [v for v in want if v not in have]
        if missing:
            sys.exit(f"perf: no variant {' '.join(missing)} in the selected benches "
                     f"(have: {' '.join(sorted(have))})")
        for name in list(benches):
            b = benches[name]
            b["variants"] = {k: v for k, v in b["variants"].items() if k in want}
            if not b["variants"]:
                print(f"perf: {name}: none of the variants {' '.join(want)}; skipped", flush=True)
                del benches[name]
    for b in benches.values():
        for vname, vcfg in b["variants"].items():
            if vcfg.get("regions") is not None and any(str(r) not in b["regions"] for r in vcfg["regions"]):
                sys.exit(f"perf: {b['name']} variant {vname}: \"regions\" names an undeclared region")
    if a.max_cycles is not None and a.max_cycles < 1:
        sys.exit("perf: --max-cycles must be positive")
    try:
        clocks = [float(c) for c in a.clock_mhz.split()]
    except ValueError:
        sys.exit(f"perf: bad --clock-mhz {a.clock_mhz!r} (MHz values, e.g. \"62.5 100\")")
    runs = []
    for spec in a.run:
        m = re.fullmatch(r"(\w+):(\w+)=(.+)", spec)
        if not m or m.group(1) not in MEMS or m.group(2) not in CONFIGS:
            sys.exit(f"perf: bad --run {spec!r}: MEM in {MEMS}, CONFIG in {CONFIGS}")
        if not os.access(m.group(3), os.X_OK):
            sys.exit(f"perf: testbench {m.group(3)} missing")
        runs.append((m.group(1), m.group(2), m.group(3)))
    if not runs:
        sys.exit("perf: nothing to run (no --run)")
    os.makedirs(os.path.join(a.out, "runs"), exist_ok=True)
    mem_args = {"soc": a.soc_args, "axi": a.axi_args}

    images, jobs = {}, []
    for b in benches.values():
        iters = a.iterations or b["iterations"]
        max_cycles = a.max_cycles or b["max_cycles"]
        for variant, vcfg in b["variants"].items():
            print(f"perf: build {b['name']} [{variant}] ({iters} iterations)", flush=True)
            img = build(b, variant, vcfg, iters, a.out, a.riscv_prefix)
            images[f"{b['name']}-{variant}"] = dict(img, variant_description=vcfg.get("description", ""))
            for mem, cfg, tb in runs:
                for rep in range(a.repeat):
                    jobs.append((b, variant, vcfg, img, mem, cfg, tb, mem_args[mem], rep,
                                 iters, max_cycles, a.out))

    print(f"perf: {len(jobs)} runs, {a.jobs} at a time", flush=True)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as ex:
        for res in ex.map(run_one, jobs):
            for r in res:
                c = r["counters"]
                status = "PASS" if r["ok"] else "FAIL: " + "; ".join(r["errors"])
                print(f"perf: {r['bench']}[{r['variant']}] region {r['region']} "
                      f"{r['mem']}/{r['config']} rep {r['rep']}: "
                      f"cycles={c.get('cycles')} instret={c.get('instret')} "
                      f"({r['wall_s']} s) {status}", flush=True)
                results.append(r)

    # Determinism: every repeat of a (bench, variant, region, mem, config)
    # must give identical counters and hardware-counter numbers.
    det = {}
    for r in results:
        key = (r["bench"], r["variant"], r["region"], r["mem"], r["config"])
        sig = (json.dumps(r["counters"], sort_keys=True), r["hw_cycles"], r["hw_instret"])
        det.setdefault(key, set()).add(sig)
    nondet = [k for k, s in det.items() if len(s) > 1]
    for r in results:
        key = (r["bench"], r["variant"], r["region"], r["mem"], r["config"])
        if key in nondet:
            r["ok"] = False
            r["errors"].append("counts differ between repeats")

    meta = {
        "date_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_head": sh(["git", "rev-parse", "HEAD"], cwd=root),
        "git_branch": sh(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root),
        "git_dirty": bool(sh(["git", "status", "--porcelain", "--untracked-files=no"], cwd=root)),
        "git_base_main": sh(["git", "merge-base", "HEAD", "origin/main"], cwd=root),
        "rtl_tree": sh(["git", "rev-parse", "HEAD:rtl"], cwd=root),
        "verilator": sh(["verilator", "--version"]),
        "compiler": sh([(a.riscv_prefix or "riscv64-unknown-elf-") + "gcc", "--version"]).split("\n")[0],
        "host": f"{platform.node()} {platform.system()} {platform.release()} {platform.machine()}",
        "python": platform.python_version(),
        "repeat": a.repeat,
        "jobs": a.jobs,
        "iterations_override": a.iterations,
        "max_cycles_override": a.max_cycles,
        "variants_selected": a.variants.split() or None,
        "clock_mhz": clocks,
        "mem_args": mem_args,
        "runs": [{"mem": m, "config": c, "tb": t} for m, c, t in runs],
        "images": images,
        "benches": {n: {k: v for k, v in b.items() if k != "dir"} for n, b in benches.items()},
        "deterministic": None if a.repeat < 2 else not nondet,
    }
    ok = [r for r in results if r["ok"]]
    bad = [r for r in results if not r["ok"]]
    out_json = os.path.join(a.out, "results.json")
    with open(out_json, "w") as f:
        json.dump({"meta": meta, "runs": ok, "failed": bad}, f, indent=1)
    rep = subprocess.run([sys.executable, os.path.join(root, "scripts", "perf_report.py"),
                          out_json, "--csv", os.path.join(a.out, "results.csv"),
                          "--md", os.path.join(a.out, "report.md")]
                         + (["--clock-mhz", a.clock_mhz] if clocks else []), check=False)
    if a.repeat > 1:
        print(f"perf: determinism over {a.repeat} repeats: "
              f"{'PASS (identical counts)' if not nondet else 'FAIL ' + str(nondet)}")
    print(f"perf: {len(ok)} runs valid, {len(bad)} failed; {out_json}, "
          f"{os.path.join(a.out, 'report.md')}")
    if bad or rep.returncode != 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
