#!/usr/bin/env python3
"""
flag_matlab_renames.py
Read commit_history.json (from extract_commits.py) and flag every commit in
which a MATLAB file (.m) changed its name.

Flagged:
  * renames git detected (status "R") where either the old or the new name
    is a .m file - including a file that became a .m file (e.g. an .asv
    autosave renamed to .m), case-only renames and moves between folders;
  * possible renames: a .m file deleted and another .m file added in the
    same commit with similar names, which git did not pair because the
    content changed too much.  Shown separately, lower confidence.

It also prints the name history (lineage) of each file, oldest name first,
and whether the last name still exists at HEAD.  Nothing is saved.

Usage:
    python flag_matlab_renames.py [--history audit_output/commit_history.json]
"""
import argparse
import difflib
import json
import os
import posixpath
import sys

SIMILAR_NAME = 0.6      # difflib ratio for a delete + add pair to count as a possible rename


def is_m(path):
    return path.lower().endswith(".m")


def kind_of(old, new):
    if old.lower() == new.lower() and old != new:
        return "case only"
    if is_m(old) != is_m(new):
        return "became .m" if is_m(new) else "no longer .m"
    if posixpath.basename(old) == posixpath.basename(new):
        return "moved"
    return "renamed"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--history", default=os.path.join("audit_output", "commit_history.json"),
                    help="path to commit_history.json")
    ap.add_argument("--no-possible", action="store_true",
                    help="do not report delete+add pairs as possible renames")
    args = ap.parse_args()

    if not os.path.isfile(args.history):
        sys.exit("flag_matlab_renames: %s not found - run extract_commits.py first" % args.history)
    with open(args.history, encoding="utf-8") as fh:
        data = json.load(fh)

    head_files = set(data.get("head_files", []))
    commits = list(reversed(data["commits"]))          # oldest first
    sure, possible = [], []

    for c in commits:
        for ch in c["files"]:
            if ch["status"] == "R" and (is_m(ch["old_path"]) or is_m(ch["path"])):
                sure.append((c, ch["old_path"], ch["path"], ch.get("similarity"),
                             kind_of(ch["old_path"], ch["path"])))
        if args.no_possible:
            continue
        dels = [x["path"] for x in c["files"] if x["status"] == "D" and is_m(x["path"])]
        adds = [x["path"] for x in c["files"] if x["status"] == "A" and is_m(x["path"])]
        used = set()
        for d in dels:
            best, score = None, 0.0
            for a in adds:
                if a in used:
                    continue
                r = difflib.SequenceMatcher(None, posixpath.basename(d).lower(),
                                            posixpath.basename(a).lower()).ratio()
                if r > score:
                    best, score = a, r
            if best is not None and score >= SIMILAR_NAME:
                used.add(best)
                possible.append((c, d, best, score))

    print("=" * 96)
    print("MATLAB FILE NAME CHANGES  -  %s" % (data.get("remote") or data.get("repository")))
    print("%d commits scanned%s" % (len(commits), "  (SHALLOW CLONE: history incomplete)"
                                    if data.get("shallow") else ""))
    print("=" * 96)

    if not sure:
        print("No renames of .m files detected by git.")
    else:
        print("%-8s %-10s %-12s %5s  %s" % ("commit", "date", "kind", "sim%", "old name  ->  new name"))
        print("-" * 96)
        for c, old, new, sim, kind in sure:
            print("%-8s %-10s %-12s %5s  %s  ->  %s" % (c["short"], c["author_date"][:10], kind,
                                                        "" if sim is None else sim, old, new))
            print("%-8s %-10s %s" % ("", "", ('"%s"' % c["subject"])[:76]))
    print()

    if not args.no_possible:
        print("POSSIBLE RENAMES (a .m deleted and a similar .m added in one commit, not paired by git)")
        print("-" * 96)
        if not possible:
            print("none")
        for c, old, new, score in possible:
            print("%-8s %-10s name match %3.0f %%   %s  ->  %s" % (c["short"], c["author_date"][:10],
                                                              100 * score, old, new))
        print()

    # lineage: follow rename chains, oldest name first
    nxt = {}
    for _, old, new, _, _ in sure:
        nxt[old] = new
    starts = [o for o in nxt if o not in set(nxt.values())]
    if starts:
        print("NAME HISTORY (oldest -> newest)")
        print("-" * 96)
        for s in sorted(starts, key=str.lower):
            chain, seen = [s], {s}
            while chain[-1] in nxt and nxt[chain[-1]] not in seen:
                chain.append(nxt[chain[-1]])
                seen.add(chain[-1])
            state = "in repo" if chain[-1] in head_files else "NOT at HEAD (deleted or renamed again)"
            print("  " + "  ->  ".join(chain) + "   [%s]" % state)
    print("=" * 96)
    print("flagged: %d rename(s)%s" % (len(sure), "" if args.no_possible
                                       else ", %d possible rename(s)" % len(possible)))


if __name__ == "__main__":
    main()
