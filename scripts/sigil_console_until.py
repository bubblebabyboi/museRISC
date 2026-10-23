#!/usr/bin/env python3
"""Run a console command (e.g. sudo sigil_host ... --console) in a pty, log
everything to LOG, stop when PATTERN (regex) appears or after TIMEOUT_S;
then detach sigil_host with Ctrl-]. Used for the F2 stress-kernel runs (#73):
  sigil_console_until.py LOG TIMEOUT_S PATTERN -- CMD...
Needs python3-pexpect."""
import sys, time, pexpect
log, tmo, pat = sys.argv[1], float(sys.argv[2]), sys.argv[3]
cmd = sys.argv[sys.argv.index("--") + 1:]
t0 = time.time()
with open(log, "w") as f:
    p = pexpect.spawn(cmd[0], cmd[1:], encoding="utf-8", codec_errors="replace",
                      timeout=tmo, dimensions=(50, 160))
    p.logfile_read = f
    i = p.expect([pat, pexpect.EOF, pexpect.TIMEOUT])
    f.write(f"\n[run_console] {['pattern', 'eof', 'timeout'][i]} after {time.time() - t0:.1f} s\n")
    if i == 0:
        try:
            p.expect([pexpect.EOF], timeout=20)
        except pexpect.TIMEOUT:
            pass
    if p.isalive():
        p.send("\x1d")            # Ctrl-] detaches sigil_host
        time.sleep(3)
        p.terminate(force=True)
