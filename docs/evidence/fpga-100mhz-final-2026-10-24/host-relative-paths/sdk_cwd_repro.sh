#!/bin/bash
# #75: the 2026-10-23 100 MHz trial driver did "cd $W" and later
# "source ~/aws-fpga/sdk_setup.sh > /dev/null 2>&1" in the same shell,
# then ran sigil_host with paths relative to $W. This replays that shell
# sequence against a scratch clone of aws-fpga v2.3.5 (sudo is a logging
# stub: nothing is installed) and prints the working directory after it.
set -u
R=$HOME/integ24/sdkrepro
rm -rf $R && mkdir -p $R/bin $R/data
git clone -q --branch v2.3.5 $HOME/src/project_data/aws-fpga $R/aws-fpga 2>&1 | tail -1
printf '#!/bin/bash\necho "[stub sudo] $*" >> %s/sudo.log\n' $R > $R/bin/sudo; chmod +x $R/bin/sudo
export PATH=$R/bin:$PATH
echo "host: $(lsb_release -ds 2>/dev/null), kernel $(uname -r), bash $BASH_VERSION"
echo "aws-fpga: $(git -C $R/aws-fpga describe --tags) ($(git -C $R/aws-fpga rev-parse --short HEAD))"
echo "data dir: $R/data (not inside a git checkout)"
echo
echo "== 1. as the trial driver: cd data; source sdk_setup.sh (same shell)"
cd $R/data
source $R/aws-fpga/sdk_setup.sh > $R/sdk_setup.log 2>&1
echo "source rc=$?; pwd after: $(pwd)"
sed 's/^/   sdk_setup.sh| /' $R/sdk_setup.log
echo
echo "== 2. in a subshell: cd data; (source sdk_setup.sh)"
cd $R/data
( source $R/aws-fpga/sdk_setup.sh > /dev/null 2>&1 ); echo "subshell rc=$?; pwd after: $(pwd)"
echo
echo "== the lines responsible (aws-fpga v2.3.5)"
grep -n "repo_root=\|export SDK_DIR" $R/aws-fpga/shared/bin/set_common_env_vars.sh | sed 's/^/   shared\/bin\/set_common_env_vars.sh:/'
grep -n "^cd \|sdk_install.sh; then\|^    return 1\|^cd \$current_dir" $R/aws-fpga/sdk_setup.sh | sed 's/^/   sdk_setup.sh:/'
rm -rf $R
