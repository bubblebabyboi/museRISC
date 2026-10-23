#!/usr/bin/env bash
# Set up the riscv-dv random-instruction generator for the Sigil
# regression (issue #8; docs/VERIFICATION.md):
#   third_party/riscv-dv   pinned clone of chipsalliance/riscv-dv (git-ignored,
#                          never modified)
#   build/riscv-dv/venv    Python venv with sim/riscv-dv/requirements.txt
#   build/riscv-dv/gen     copy of riscv-dv's pygen with
#                          sim/riscv-dv/patches/pygen-sigil.patch applied and
#                          the 'sigil' target (sim/riscv-dv/target/sigil) added
# Idempotent; scripts/riscv_dv_regress.sh re-runs it when the patch, the
# core setting or the pin change. PYTHON= picks the interpreter for the
# venv (default python3; validated with 3.12).
set -euo pipefail
cd "$(dirname "$0")/.."

RDV_URL=https://github.com/chipsalliance/riscv-dv.git
RDV_SHA=0d71c2b666dec48dde0b804a2138426da56aa252   # master, 2026-09-21
RDV=third_party/riscv-dv
B=build/riscv-dv
PATCH=sim/riscv-dv/patches/pygen-sigil.patch
SETTING=sim/riscv-dv/target/sigil/riscv_core_setting.py

if [ ! -e "$RDV/.git" ]; then
  mkdir -p third_party
  git clone -q "$RDV_URL" "$RDV"
fi
if [ "$(git -C "$RDV" rev-parse HEAD)" != "$RDV_SHA" ]; then
  if [ -L "$RDV" ]; then
    # Worktrees share the main checkout's clone (scripts/worktree_setup.sh);
    # never move it from here.
    echo "error: $RDV (shared, $(readlink "$RDV")) is not at $RDV_SHA;" \
         "run this script in the main checkout" >&2
    exit 1
  fi
  git -C "$RDV" fetch -q origin
  git -C "$RDV" -c advice.detachedHead=false checkout -q "$RDV_SHA"
fi

mkdir -p "$B"
if [ ! -x "$B/venv/bin/python3" ]; then
  "${PYTHON:-python3}" -m venv "$B/venv"
fi
"$B/venv/bin/pip" install -q --disable-pip-version-check -r sim/riscv-dv/requirements.txt

rm -rf "$B/gen"
mkdir -p "$B/gen"
cp -R "$RDV/pygen" "$B/gen/pygen"
# Some upstream files have CRLF line endings; the patch is against LF.
find "$B/gen/pygen" -name '*.py' -exec perl -pi -e 's/\r$//' {} +
patch -s -p1 -d "$B/gen" < "$PATCH"
mkdir -p "$B/gen/pygen/pygen_src/target/sigil"
cp "$SETTING" "$B/gen/pygen/pygen_src/target/sigil/riscv_core_setting.py"
cat "$PATCH" "$SETTING" <(echo "$RDV_SHA") | sha256sum | cut -d' ' -f1 > "$B/gen/.stamp"
echo "riscv-dv $RDV_SHA: patched pygen in $B/gen, venv $B/venv ($("$B/venv/bin/python3" --version))"
