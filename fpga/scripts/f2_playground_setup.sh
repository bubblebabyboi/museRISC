#!/bin/bash
# One-time setup of a Sigil F2 playground on an f2.6xlarge (FPGA Developer AMI).
set -euo pipefail
AGFI=agfi-0a1fd54ef68bdc754
cd ~
[ -d aws-fpga ] || git clone -q -b v2.3.5 --depth 1 https://github.com/aws/aws-fpga.git aws-fpga
(cd aws-fpga && source sdk_setup.sh > ~/sdk_setup.log 2>&1)
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc-riscv64-unknown-elf make > /dev/null
[ -d sigil ] || git clone -q https://github.com/bubblebabyboi/sigil.git sigil
make -s -C sigil/fpga/host SDK_DIR=$HOME/aws-fpga/sdk

mkdir -p ~/bin
cp ~/sigil/fpga/scripts/sigil-run ~/bin/sigil-run
chmod +x ~/bin/sigil-run
grep -q 'HOME/bin' ~/.bashrc || echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc

mkdir -p ~/hello
cat > ~/hello/hello.c <<'EOS'
#include "sigil.h"

int main(void) {
  sigil_printf("Hello, world! from the Sigil RISC-V SoC on an AWS F2 FPGA\n");
  sigil_printf("misa = 0x%lx, cycle = %lu\n", sigil_csr_read(misa), sigil_rdcycle());
  return 0;   /* prints "SIGIL TEST PASS hello" and halts */
}
EOS
sudo fpga-load-local-image -S 0 -I "$AGFI" -H > /dev/null
echo SETUP_DONE
