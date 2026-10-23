#!/bin/bash
# ci.sh: replay .github/workflows/riscv-dv.yml (job riscv-dv) from a fresh
# clone of origin/8-riscv-dv, in a sandbox HOME with nproc = 4.
set -u
C=~/rdvcrit2/ci; rm -rf $C; mkdir -p $C/home/fakebin
printf '#!/bin/sh\necho 4\n' > $C/home/fakebin/nproc; chmod +x $C/home/fakebin/nproc
git clone -q --branch 8-riscv-dv https://github.com/bubblebabyboi/sigil.git $C/sigil
{ echo "# start $(date -u) commit $(git -C $C/sigil rev-parse HEAD)"; } > $C/replay.meta
python3 ~/rdvcrit/ci_replay.py $C/sigil/.github/workflows/riscv-dv.yml $C/sigil $C/home riscv-dv > $C/replay.log 2>&1
echo "# rc $? end $(date -u)" >> $C/replay.meta
