#!/usr/bin/env python3
"""
run_all.py
Run the whole repository audit in the right order:

  1. extract_commits.py      full commit history  -> OUT/commit_history.json
  2. flag_matlab_renames.py  .m name changes, read from that file (printed)
  3. find_run_order.py       script run order     -> OUT/run_order.txt
  4. find_unused_files.py    unused files (printed only)

Step 2 needs step 1's file, so the audit stops if step 1 fails.  Steps 3 and
4 do not need git history and run even if the folder is not a git repository.

Usage:
    python run_all.py --repo PATH_TO_REPO [--out OUTPUT_DIR]

Keep the five .py files together in one folder (inside or outside the repo).
"""
import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def step(n, title, script, args):
    print("\n" + "#" * 90)
    print("# STEP %d - %s" % (n, title))
    print("#" * 90, flush=True)
    path = os.path.join(HERE, script)
    if not os.path.isfile(path):
        print("missing %s - keep all audit scripts in one folder" % script)
        return False
    t0 = time.time()
    rc = subprocess.call([sys.executable, path] + args, cwd=HERE)
    print("# step %d %s in %.1f s" % (n, "finished" if rc == 0 else "FAILED (exit %d)" % rc,
                                      time.time() - t0), flush=True)
    return rc == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".", help="path to the repository (default: .)")
    ap.add_argument("--out", default="audit_output", help="output directory (default: audit_output)")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    out = os.path.abspath(args.out)
    if not os.path.isdir(repo):
        sys.exit("run_all: %s is not a folder" % repo)
    os.makedirs(out, exist_ok=True)
    history = os.path.join(out, "commit_history.json")
    common = ["--repo", repo, "--out", out]

    ok = {}
    ok[1] = step(1, "extract commit history", "extract_commits.py", common)
    if ok[1]:
        ok[2] = step(2, "flag MATLAB file renames", "flag_matlab_renames.py", ["--history", history])
    else:
        print("skipping step 2: it needs commit_history.json from step 1")
        ok[2] = False
    ok[3] = step(3, "find run order", "find_run_order.py", common)
    ok[4] = step(4, "find unused files", "find_unused_files.py", common)

    print("\n" + "=" * 90)
    names = {1: "commit history", 2: "MATLAB renames", 3: "run order", 4: "unused files"}
    for k in sorted(ok):
        print("  %-16s %s" % (names[k], "ok" if ok[k] else "FAILED / skipped"))
    print("  outputs in      %s" % out)
    print("=" * 90)
    sys.exit(0 if all(ok.values()) else 1)


if __name__ == "__main__":
    main()
