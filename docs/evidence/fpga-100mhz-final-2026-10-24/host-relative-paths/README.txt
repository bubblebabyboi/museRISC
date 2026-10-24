sigil_host and relative --load paths (#75, 100 MHz trial attempt 0)
===================================================================
Symptom (docs/evidence/linux-100mhz-trial-2026-10-23/attempt0-relative-paths/):
the detached trial driver ran sigil_host (53-100mhz-afi @ 866efb6) with
relative paths; it printed the AFI, clock and DDR4-ready lines, scrubbed
DDR4 and stopped with "ERROR: cannot open sigil-debian-13-riscv64.ext4:
No such file or directory", although the file was in the directory the
driver had cd'ed to. With absolute paths the same binary booted Debian.

Root cause: the driver's shell was no longer in that directory.
sigil_host is not involved.
- The driver (trial100.sh; its xtrace is attempt0-relative-paths/
  trial.log.txt) did, in one shell: cd /mnt/nvme/os73; sha256sum / zstd on relative
  names (worked); source ~/aws-fpga/sdk_setup.sh > /dev/null 2>&1;
  fpga-load-local-image; sigil_host with relative paths (failed, runs 1
  and 2); sudo sha256sum on relative names (failed).
- aws-fpga v2.3.5 shared/bin/set_common_env_vars.sh:19 finds the
  checkout with "git rev-parse --show-toplevel" in the CALLER's
  directory. From /mnt/nvme/os73 (not a git checkout) AWS_FPGA_REPO_DIR
  is empty and SDK_DIR=/sdk; sdk_setup.sh:44 "cd $script_dir", :45
  "bash $SDK_DIR/sdk_install.sh" fails (/sdk/sdk_install.sh: No such
  file), :47 "return 1" -- before :64 "cd $current_dir". The sourcing
  shell is left in ~/aws-fpga, so every later relative path named a
  file there. (Its output went to /dev/null, so the trial log only
  shows "+ source /home/ubuntu/aws-fpga/sdk_setup.sh".)
- sdk_cwd_repro.sh / sdk_cwd_repro.log: that shell sequence replayed
  on sigil-fpga-build (Ubuntu 24.04.1, kernel 6.8.0-1021-aws as on the
  F2 instance) against a scratch clone of aws-fpga v2.3.5 (sudo
  stubbed, nothing installed): source rc=1, pwd after = the aws-fpga
  clone; in a subshell the caller's directory is kept.
- Timing agrees: the driver went from its start (06:11:18) to STAMP
  (06:11:45) through an 8 GiB zstd -d + sha256sum and the AFI load, so
  sdk_setup.sh returned at once; the successful sourcing in the host
  build step (cd ~/aws-fpga first) rebuilt the SDK and its Cython
  bindings and took over a minute.
- The 2026-10-22 62.5 MHz runs that worked with relative paths were
  started as ssh '... cd /mnt/nvme/os73 && ... sigil_host ...' in a
  fresh shell that had not sourced sdk_setup.sh; so was the absolute-
  path rerun (f2-100-driver.sh). The sigil_host.c changes since main
  (timebase check/rewrite, --info, fdt_walk, clock report) do not touch
  file handling: open() is called only in map_file and save_range,
  both unchanged, and nothing calls chdir.
- The old sigil_host.c (1892e0e) under the host test (below) loads,
  boots and saves with relative, ../ and absolute paths
  (host-test-linux-old.log, cases 1-4) and, started from the wrong
  directory, prints the trial's lines one for one: AFI, clock, DDR4
  ready, "scrubbed DDR4", "ERROR: cannot open
  sigil-debian-13-riscv64.ext4: No such file or directory".

Changes (53-100mhz-afi, 2026-10-24):
- sigil_host opens every image and checks every --save / --log
  directory for write access before the FPGA is touched (a bad path
  now fails in milliseconds, not after the AFI setup and the 10-17 s
  DDR4 scrub); path errors name the working directory a relative path
  was resolved against; a run with relative paths logs "relative paths
  resolve against DIR".
- docs/FPGA_F2.md: source sdk_setup.sh from inside the aws-fpga
  checkout; in scripts use a subshell, (cd ~/aws-fpga && source
  sdk_setup.sh).
- Host-side test, no FPGA and no SDK: fpga/host/test/ (mock of the SDK
  and the Sigil CL: OCL registers, 80 GiB sparse PCIS memory, memory
  engine, UART, test finisher) + test_sigil_host.py, 6 cases on the F2
  Linux invocation of the trial: relative paths on a fresh AFI (scrub,
  then loads; images checked in SoC memory at release; the guest's disk
  write saved with a relative --save), the saved disk reloaded, ../
  paths with a 62.5 MHz DTB (timebase rewritten), absolute paths,
  relative paths from the wrong directory (exit 3 before any SDK call,
  message names the directory), --save into a missing directory.
  "make -C fpga/host test"; part of the top-level "make test" (CI
  regression job). On Linux it is the real host build (mmap'd BAR4,
  copy threads, mmap'd images); elsewhere the co-simulation seam.

Results:
  host-test-linux-new.log  this commit, Linux host build      23/23 PASS
  host-test-mac.log        this commit, macOS (SV_TEST seam)   22/22 PASS
                           (the rng-seed check is Linux-only)
  host-test-linux-old.log  1892e0e sigil_host.c, Linux         18/23: the
                           five failures are the new checks only (cwd in
                           the message, nothing touched before the
                           error, --save directory checked early)
