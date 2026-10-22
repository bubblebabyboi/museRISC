#!/usr/bin/env bash
# riscv-dv random-instruction regression: Sigil core vs Spike (issue #8).
#
#   scripts/riscv_dv_regress.sh [--tests a,b|all] [--seeds 1,2,3|1-10]
#                               [--jobs N] [--list] [--help ...]
#
# One CSV row per (test, seed) in build/riscv-dv/run/results.csv:
# PASS / MISMATCH / DUT_TIMEOUT / DUT_FAIL / GEN_FAIL / SPIKE_FAIL, the
# first divergence and the artifact paths. Needs the core harness
# (make -C sim ../build/sim/core_tb, or use `make -C sim riscv-dv`) and
# Spike (SPIKE=/path/to/spike, or spike on PATH, or ~/opt/spike/bin).
# Sets up the generator (scripts/riscv_dv_setup.sh) when needed.
# Usage, pins and the test list: docs/VERIFICATION.md.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f deps/env.sh ]; then
  set +u
  # shellcheck disable=SC1091
  source deps/env.sh
  set -u
fi
B=build/riscv-dv
want=$(cat sim/riscv-dv/patches/pygen-sigil.patch \
           sim/riscv-dv/target/sigil/riscv_core_setting.py \
           <(sed -n 's/^RDV_SHA=\([0-9a-f]*\).*/\1/p' scripts/riscv_dv_setup.sh) |
       sha256sum | cut -d' ' -f1)
if [ ! -x "$B/venv/bin/python3" ] || [ "$(cat "$B/gen/.stamp" 2>/dev/null)" != "$want" ]; then
  ./scripts/riscv_dv_setup.sh
fi
exec "$B/venv/bin/python3" sim/riscv-dv/rdv_regress.py "$@"
