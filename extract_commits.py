#!/usr/bin/env python3
"""
extract_commits.py
Extract the full commit history of a git repository and save it as JSON.

For every commit on every branch, tag and remote branch it records the hash,
parents, author, committer, dates, refs, message and the list of changed
files.  File changes come from `git diff-tree` with rename detection, so a
renamed file is stored as one entry (status "R", old_path -> path, similarity
in %) rather than a delete plus an add.  The list of files at HEAD is saved
too, so later tools can tell whether a file still exists.

Usage:
    python extract_commits.py --repo PATH_TO_REPO [--out OUTPUT_DIR]
Output:
    OUTPUT_DIR/commit_history.json
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys

FIELD = "\x1f"
RECORD = "\x1e"
LOG_FORMAT = FIELD.join(["%H", "%P", "%an", "%ae", "%aI", "%cn", "%ce", "%cI", "%D", "%s", "%b"]) + RECORD


def git(repo, *args):
    """Run a git command in `repo` and return stdout as text."""
    res = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", *args],
                         capture_output=True)
    if res.returncode != 0:
        raise RuntimeError("git %s failed:\n%s" % (" ".join(args),
                           res.stderr.decode("utf-8", "replace").strip()))
    return res.stdout.decode("utf-8", "replace")


def parse_name_status(raw):
    """Parse NUL-separated `--name-status -z` output into change dicts."""
    tok = [t for t in raw.split("\0")]
    if tok and tok[-1] == "":
        tok.pop()
    out, i = [], 0
    while i < len(tok):
        status = tok[i]
        code = status[0]
        score = int(status[1:]) if len(status) > 1 and status[1:].isdigit() else None
        if code in ("R", "C"):
            out.append({"status": code, "similarity": score,
                        "old_path": tok[i + 1], "path": tok[i + 2]})
            i += 3
        else:
            out.append({"status": code, "path": tok[i + 1]})
            i += 2
    return out


def commit_files(repo, sha, parents):
    """Files changed by one commit, compared with its first parent."""
    if parents:
        raw = git(repo, "diff-tree", "-r", "-M", "--no-commit-id", "--name-status", "-z",
                  parents[0], sha)
    else:
        raw = git(repo, "diff-tree", "-r", "-M", "--root", "--no-commit-id", "--name-status",
                  "-z", sha)
    return parse_name_status(raw)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".", help="path to the git repository (default: .)")
    ap.add_argument("--out", default="audit_output", help="output directory (default: audit_output)")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    try:
        if git(repo, "rev-parse", "--is-inside-work-tree").strip() != "true":
            raise RuntimeError("not a work tree")
    except Exception as exc:
        sys.exit("extract_commits: %s is not a git repository (%s)" % (repo, exc))

    shallow = git(repo, "rev-parse", "--is-shallow-repository").strip() == "true"
    if shallow:
        print("WARNING: this is a shallow clone - history is incomplete. "
              "Run `git fetch --unshallow` for the full history.")

    try:
        remote = git(repo, "remote", "get-url", "origin").strip()
    except RuntimeError:
        remote = None
    head = git(repo, "rev-parse", "HEAD").strip()
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD").strip()
    head_files = [f for f in git(repo, "ls-tree", "-r", "--name-only", "-z", "HEAD").split("\0") if f]

    raw = git(repo, "log", "--branches", "--tags", "--remotes", "HEAD",
              "--date-order", "--format=" + LOG_FORMAT)
    commits = []
    records = [r.strip("\n") for r in raw.split(RECORD) if r.strip("\n")]
    for n, rec in enumerate(records, 1):
        f = rec.split(FIELD)
        sha, parents = f[0], f[1].split()
        commits.append({
            "hash": sha,
            "short": sha[:7],
            "parents": parents,
            "is_merge": len(parents) > 1,
            "author": {"name": f[2], "email": f[3]},
            "author_date": f[4],
            "committer": {"name": f[5], "email": f[6]},
            "committer_date": f[7],
            "refs": [r.strip() for r in f[8].split(",") if r.strip()],
            "subject": f[9],
            "body": f[10].strip(),
            "files": commit_files(repo, sha, parents),
        })
        if n % 100 == 0:
            print("  %d / %d commits" % (n, len(records)))

    data = {
        "repository": repo,
        "remote": remote,
        "extracted_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "head": head,
        "branch": branch,
        "shallow": shallow,
        "commit_count": len(commits),
        "head_files": head_files,
        "commits": commits,          # newest first
    }

    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, "commit_history.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)

    n_changes = sum(len(c["files"]) for c in commits)
    n_ren = sum(1 for c in commits for x in c["files"] if x["status"] == "R")
    print("extract_commits: %d commits, %d file changes (%d renames) -> %s"
          % (len(commits), n_changes, n_ren, path))


if __name__ == "__main__":
    main()
