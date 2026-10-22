#!/bin/bash
# Setup of a Sigil F2 playground on an f2.6xlarge (FPGA Developer AMI):
# aws-fpga runtime SDK, a bare-metal RISC-V GCC, ~/sigil with sigil_host, the
# Sigil AFI, and ~/bin/sigil-run (bare-metal programs, docs/PROGRAMMING.md) and
# ~/bin/sigil-linux (Debian, docs/LINUX.md section 4). Rerun it to update
# ~/sigil, sigil_host and the helpers.
set -euo pipefail
AGFI=agfi-0a1fd54ef68bdc754
cd ~
[ -d aws-fpga ] || git clone -q -b v2.3.5 --depth 1 https://github.com/aws/aws-fpga.git aws-fpga
# shellcheck disable=SC1091  # aws-fpga's setup script
(cd aws-fpga && source sdk_setup.sh > ~/sdk_setup.log 2>&1)
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc-riscv64-unknown-elf make zstd tmux > /dev/null
if [ -d sigil ]; then git -C sigil pull -q --ff-only; else git clone -q https://github.com/bubblebabyboi/sigil.git sigil; fi
make -s -C sigil/fpga/host SDK_DIR="$HOME/aws-fpga/sdk"

mkdir -p ~/bin
for s in sigil-run sigil-linux; do
  cp ~/sigil/fpga/scripts/$s ~/bin/$s
  chmod +x ~/bin/$s
done
# shellcheck disable=SC2016  # $HOME expands in .bashrc
grep -q 'HOME/bin' ~/.bashrc || echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc

mkdir -p ~/hello
[ -e ~/hello/hello.c ] || cat > ~/hello/hello.c <<'EOS'
#include "sigil.h"

int main(void) {
  sigil_printf("Hello, world! from the Sigil RISC-V SoC on an AWS F2 FPGA\n");
  sigil_printf("misa = 0x%lx, cycle = %lu\n", sigil_csr_read(misa), sigil_rdcycle());
  return 0;   /* prints "SIGIL TEST PASS hello" and halts */
}
EOS
# Load the AFI unless the FPGA already has it (a load resets the FPGA).
if ! sudo fpga-describe-local-image -S 0 -H 2> /dev/null | grep -q "$AGFI.*loaded"; then
  sudo fpga-load-local-image -S 0 -I "$AGFI" -H > /dev/null
fi
echo SETUP_DONE
