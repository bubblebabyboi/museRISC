#!/bin/bash
# Setup on a fresh f2.6xlarge (FPGA Developer AMI): the steps of
# fpga/scripts/f2_playground_setup.sh minus the RISC-V compiler and the
# sigil clone (images and fpga/host come pre-built/copied in ~/f2perf).
set -euo pipefail
AGFI=agfi-035116450e0a0d093
cd ~
t0=$(date -u +%s)
[ -d aws-fpga ] || git clone -q -b v2.3.5 --depth 1 https://github.com/aws/aws-fpga.git aws-fpga
(cd aws-fpga && source sdk_setup.sh > ~/sdk_setup.log 2>&1)
make -s -C ~/f2perf/host SDK_DIR=$HOME/aws-fpga/sdk
sudo fpga-load-local-image -S 0 -I "$AGFI" -H
sudo fpga-describe-local-image -S 0 -H
echo "SETUP_DONE in $(( $(date -u +%s) - t0 )) s"
