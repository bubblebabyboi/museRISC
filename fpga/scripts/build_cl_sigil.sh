#!/usr/bin/env bash
# Build the Sigil AWS F2 CL design checkpoint (issue #54) with the
# aws-fpga HDK (v2.3.5, Small Shell) on an F2 Developer AMI.
#
#   fpga/scripts/build_cl_sigil.sh [--recipe-b B1] [--tag TAG]
#                                  [--flow BuildAll|SynthCL|ImplCL]
#
# Needs AWS_FPGA_REPO_DIR (an aws-fpga checkout at tag v2.3.5) or
# ~/src/project_data/aws-fpga, and Vivado on PATH (the Developer AMI's
# login shell). Always builds unencrypted (--no-encrypt) so the AFI
# can be published and rebuilt from this repository.
#
# Core clock = AWS_CLK_GEN clk_extra_b1, frequency by group-B recipe:
#   B1 (default) 62.5 MHz  -- interim label until #53 closes 100 MHz
#   B4 75 MHz, B5 100 MHz  (B0 125, B2 225, B3 62.5)
# Groups A/C/HBM are unused by the SoC and left at the HDK defaults.
#
# Output: fpga/cl_sigil/build/checkpoints/<TAG>.Developer_CL.tar
# (DCP + manifest for create-fpga-image, issue #55) and reports in
# fpga/cl_sigil/build/reports/.
set -euo pipefail
RECIPE_B=B1
TAG=""
FLOW=BuildAll
while [ $# -gt 0 ]; do
  case "$1" in
    --recipe-b) RECIPE_B="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --flow) FLOW="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-$HOME/src/project_data/aws-fpga}"
export CL_DIR="$REPO/fpga/cl_sigil"
# hdk_setup.sh is not -u/-e clean.
set +eu
cd "$AWS_FPGA_REPO_DIR"
# shellcheck disable=SC1091
source hdk_setup.sh > "$CL_DIR/build/hdk_setup.log" 2>&1
rc=$?
set -eu
[ $rc -eq 0 ] && [ -n "${HDK_SHELL_DIR:-}" ] || {
  echo "hdk_setup.sh failed; see $CL_DIR/build/hdk_setup.log" >&2; exit 1; }
grep -q "RELEASE_VERSION=2.3.5" "$AWS_FPGA_REPO_DIR/release_version.txt" ||
  echo "WARNING: aws-fpga is not v2.3.5 ($(cat "$AWS_FPGA_REPO_DIR/release_version.txt"))" >&2
S="$CL_DIR/build/scripts"
for f in aws_build_dcp_from_cl.py build_all.tcl build_level_1_cl.tcl; do
  ln -sf "$HDK_SHELL_DIR/build/scripts/$f" "$S/$f"
done
cd "$S"
args=(-c cl_sigil --mode small_shell --flow "$FLOW" --aws_clk_gen --no-encrypt
      --clock_recipe_a A1 --clock_recipe_b "$RECIPE_B"
      --clock_recipe_c C0 --clock_recipe_hbm H2)
[ -n "$TAG" ] && args+=(--tag "$TAG")
echo "build_cl_sigil: $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo no-git) recipe_b=$RECIPE_B"
python3 ./aws_build_dcp_from_cl.py "${args[@]}"
