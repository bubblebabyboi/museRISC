#!/usr/bin/env python3
"""ci_replay.py <workflow.yml> <repo-dir> <sandbox-home> <job>: run a GitHub
Actions job's `run:` steps locally, in order, the way the runner would on a
cache miss. `uses:` steps are emulated (checkout = the given clone, cache =
miss, upload-artifact = list the paths). ${{ }} expressions are replaced
from a fixed table (workflow_dispatch with the input defaults). Each step
runs with bash -eo pipefail in the repo dir; GITHUB_PATH/GITHUB_OUTPUT/
GITHUB_STEP_SUMMARY are files in the sandbox. Skips steps named in SKIP."""
import os, re, subprocess, sys, time, glob
import yaml
wf_path, repo, home, job = sys.argv[1:5]
SKIP = {"Install host tools"}          # packages already present; checked separately
wf = yaml.safe_load(open(wf_path))
inputs = {k: str(v.get("default", "")) for k, v in wf["on"]["workflow_dispatch"]["inputs"].items()}
env = {"HOME": home, "PATH": os.path.join(home, "fakebin") + ":/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
       "LANG": "C.UTF-8", "GITHUB_RUN_NUMBER": "1", "GITHUB_EVENT_NAME": "workflow_dispatch",
       "GITHUB_WORKSPACE": repo, "RUNNER_OS": "Linux", "CI": "true"}
for f in ("GITHUB_PATH", "GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY", "GITHUB_ENV"):
    env[f] = os.path.join(home, f.lower())
    open(env[f], "w").close()
env.update({k: str(v) for k, v in wf.get("env", {}).items()})
def expr(s):
    def rep(m):
        e = m.group(1).strip()
        if e == "github.event_name": return "workflow_dispatch"
        if e.startswith("inputs."): return inputs[e[7:]]
        if e.startswith("env."): return env.get(e[4:], "")
        if e.startswith("steps.") and e.endswith("cache-hit"): return ""
        if e == "github.run_number": return "1"
        if e == "github.sha": return subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        if e.startswith("hashFiles"): return "x"
        raise SystemExit("unknown expression " + e)
    return re.sub(r"\$\{\{(.*?)\}\}", rep, s)
steps = wf["jobs"][job]["steps"]
t_all = time.time()
for st in steps:
    name = st.get("name", st.get("uses", "?"))
    cond = st.get("if", "")
    if "uses" in st:
        u = st["uses"]
        if u.startswith("actions/upload-artifact"):
            paths = [p.strip() for p in st["with"]["path"].splitlines() if p.strip()]
            print("== %s: would upload:" % name)
            for p in paths:
                hits = glob.glob(os.path.join(repo, p.rstrip("/")))
                print("   %s -> %s" % (p, ", ".join(os.path.relpath(h, repo) for h in hits) or "(none)"))
        else:
            print("== %s: emulated (%s)" % (name, "cache miss" if "cache" in u else "clone at %s" % repo))
        continue
    if name in SKIP:
        print("== %s: skipped (see host tool check)" % name)
        continue
    if cond and "cache-hit != 'true'" not in cond and cond != "always()":
        raise SystemExit("unhandled if: " + cond)
    senv = dict(env)
    senv.update({k: expr(str(v)) for k, v in st.get("env", {}).items()})
    # GITHUB_PATH entries are prepended for later steps, as on the runner.
    extra = [l.strip() for l in open(env["GITHUB_PATH"]) if l.strip()]
    senv["PATH"] = ":".join(reversed(extra)) + (":" if extra else "") + env["PATH"]
    script = expr(st["run"])
    t0 = time.time()
    print("== %s" % name, flush=True)
    rc = subprocess.run(["bash", "-eo", "pipefail", "-c", script], cwd=repo, env=senv).returncode
    print("== %s: rc=%d, %.0f s" % (name, rc, time.time() - t0), flush=True)
    if rc != 0 and cond != "always()":
        print("== job failed at %s" % name)
        break
print("== job wall time %.0f s" % (time.time() - t_all))
print("== step summary:")
print(open(env["GITHUB_STEP_SUMMARY"]).read())
