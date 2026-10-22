#!/usr/bin/env bash
# Build the Sigil AWS F2 CL design checkpoint (issue #54) with the
# aws-fpga HDK (v2.3.5, Small Shell) on an F2 Developer AMI.
#
#   fpga/scripts/build_cl_sigil.sh [--recipe-b B1] [--tag YYYY_MM_DD-HHMMSS]
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
# (+ <TAG>.sigil_source.txt: the Sigil and aws-fpga commits built;
# a `git archive` export can carry the commit in a .git-rev file)
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
set +euo pipefail
cd "$AWS_FPGA_REPO_DIR"
# shellcheck disable=SC1091
source hdk_setup.sh > "$CL_DIR/build/hdk_setup.log" 2>&1
set -euo pipefail
[ -n "${HDK_SHELL_DIR:-}" ] || {
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
# The HDK writes the tag into the AFI manifest "date" field, so keep the
# HDK's own timestamp format.
[ -n "$TAG" ] || TAG=$(date +%Y_%m_%d-%H%M%S)
[[ "$TAG" =~ ^[0-9]{4}_[0-9]{2}_[0-9]{2}-[0-9]{6}$ ]] ||
  { echo "--tag must look like YYYY_MM_DD-HHMMSS (manifest date field)" >&2; exit 2; }
args+=(--tag "$TAG")
REV=$(cat "$REPO/.git-rev" 2>/dev/null || git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)
mkdir -p "$CL_DIR/build/checkpoints"
echo "sigil $REV recipe_b=$RECIPE_B aws-fpga $(git -C "$AWS_FPGA_REPO_DIR" rev-parse HEAD 2>/dev/null)" \
  > "$CL_DIR/build/checkpoints/$TAG.sigil_source.txt"
echo "build_cl_sigil: tag $TAG, sigil $REV, recipe_b=$RECIPE_B"
python3 ./aws_build_dcp_from_cl.py "${args[@]}"
