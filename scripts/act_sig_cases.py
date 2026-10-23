#!/usr/bin/env python3
"""Case-level comparison of an ACT4 signature dump against Sail.

Usage: act_sig_cases.py TEST.S SAIL.sig CORE.dump TEST_NAME [--csv]

TEST.S is the ACT source the ELF was built from; SAIL.sig is the
reference signature (one 64-bit hex word per line) that
build_act4_core.sh produced by running the same .sig.elf on Sail;
CORE.dump is core_tb's CORE_TB_SIGDUMP output ("SIG <hex>" lines)
for that .sig.elf on the in-house core.

Signature layout (riscv-arch-test tests/env/rvtest_setup.h,
signature mode): word 0 canary, words 1..SIGUPD_COUNT one per
RVTEST_SIGUPD in source order (unused tail stays 0xdeadbeef), then
the final-offset canaries/slots, the trap region and the end canary.
Each RVTEST_SIGUPD names the test case label it belongs to, so every
word maps to a case. With --csv, prints one row per case:
test,case,coverpoint,slots,sail,core,result (values '|'-joined).
Always prints a summary line to stderr; exit status 1 on any
mismatch or length difference.
"""
import re
import sys


def parse_source(path):
    """[(label, coverpoint)] per RVTEST_SIGUPD, in source order."""
    out = []
    cp = ""
    prev_sep = False
    for line in open(path):
        s = line.strip()
        if s.startswith("/////"):
            prev_sep = True
            continue
        m = re.match(r"^// (\w+)$", s)
        if prev_sep and m:
            cp = m.group(1)
        prev_sep = False
        m = re.match(r"^RVTEST_SIGUPD\(([^)]*)\)", s)
        if m:
            args = [a.strip() for a in m.group(1).split(",")]
            out.append((args[4], cp))
    return out


def main():
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    src, sail_path, core_path, name = sys.argv[1:5]
    want_csv = "--csv" in sys.argv[5:]
    sigupd = parse_source(src)
    sail = [int(x, 16) for x in open(sail_path).read().split()]
    core = [int(m.group(1), 16) for m in
            (re.match(r"^SIG ([0-9a-fA-F]+)$", ln.strip()) for ln in open(core_path))
            if m]
    count_m = re.search(r"#define SIGUPD_COUNT (\d+)", open(src).read())
    sigupd_count = int(count_m.group(1)) if count_m else len(sigupd)
    words = max(len(sail), len(core))
    mism = [i for i in range(words)
            if i >= len(sail) or i >= len(core) or sail[i] != core[i]]
    # Group words into cases: 0 canary, 1..len(sigupd) cases, the rest
    # (unused SIGUPD slots, final-offset slots, trap region, canaries)
    # as one "framework" group.
    groups = [("canary", "framework", [0])]
    for i, (label, cp) in enumerate(sigupd, start=1):
        if groups[-1][0] == label:
            groups[-1][2].append(i)
        else:
            groups.append((label, cp, [i]))
    groups.append(("unused_slots_offsets_trap_region_end_canary", "framework",
                   list(range(len(sigupd) + 1, words))))
    bad_cases = 0
    if want_csv:
        print("test,case,coverpoint,slots,sail,core,result")
    for label, cp, slots in groups:
        sv = [f"{sail[i]:016x}" if i < len(sail) else "missing" for i in slots]
        cv = [f"{core[i]:016x}" if i < len(core) else "missing" for i in slots]
        ok = sv == cv
        bad_cases += not ok
        if want_csv:
            slot_txt = f"{slots[0]}" if len(slots) == 1 else f"{slots[0]}-{slots[-1]}"
            if label.startswith("unused"):
                sv = cv = [f"{len(slots)} words"] if ok else ["see dump"]
            print(f"{name},{label},{cp},{slot_txt},{'|'.join(sv)},{'|'.join(cv)},"
                  f"{'MATCH' if ok else 'MISMATCH'}")
    ncases = len(groups) - 2
    print(f"{name}: {len(sigupd)} SIGUPD slots (SIGUPD_COUNT {sigupd_count}) in "
          f"{ncases} cases; signature words sail={len(sail)} core={len(core)}; "
          f"word mismatches {len(mism)}; case mismatches {bad_cases}",
          file=sys.stderr)
    return 0 if not mism and len(sail) == len(core) and sail else 1


if __name__ == "__main__":
    sys.exit(main())
