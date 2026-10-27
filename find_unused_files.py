#!/usr/bin/env python3
"""
find_unused_files.py
Flag the files in the repository that nothing uses.  Prints only - saves
nothing.

Uses the same static scan as find_run_order.py (comments ignored, sprintf
names treated as wildcards, variables resolved).

Categories
  1. UNREFERENCED FILES   data, figures, documents, autosaves: no script
                          reads or writes a file with this name.
  2. ORPHAN .mat OUTPUTS  written by a script, never loaded by any script.
  3. ISOLATED SCRIPTS     share no file with any other script and are not
                          run by one - the strongest "not used" signal.
  4. UNCALLED FUNCTIONS   .m function files no script calls.
  5. DEAD-END SCRIPTS     read pipeline data, but no other script uses what
                          they produce.  Often legitimate figure or check
                          scripts; listed so you can decide.

Never flagged: README, LICENSE, .gitignore and similar repository files.

Usage:
    python find_unused_files.py --repo PATH_TO_REPO [--out OUTPUT_DIR]
    (--out is only used to keep the audit's own output folder out of the scan)
"""
import argparse
import os
import sys

from find_run_order import Ref, analyse_repo

META = ("readme", "license", "licence", "copying", "changelog", "citation", "contributing")
META_EXACT = {".gitignore", ".gitattributes", ".gitmodules", "requirements.txt", "environment.yml",
              "setup.py", "pyproject.toml", ".editorconfig"}


def is_meta(path):
    parts = path.replace("\\", "/").split("/")
    if any(p.startswith(".") for p in parts[:-1]):        # .vscode/, .github/, .idea/ ...
        return True
    name = parts[-1].lower()
    return name in META_EXACT or name.startswith(META)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".", help="path to the repository (default: .)")
    ap.add_argument("--out", default="audit_output", help="audit output folder to exclude from the scan")
    args = ap.parse_args()
    if not os.path.isdir(args.repo):
        sys.exit("find_unused_files: %s is not a folder" % args.repo)

    a = analyse_repo(args.repo, exclude_dirs=[args.out])
    scripts = a["scripts"]

    all_reads = [Ref(x) for s in scripts.values() for x in s["reads"]]
    all_writes = [Ref(x) for s in scripts.values() for x in s["writes"]]

    def matched(name, refs):
        return any(r.matches_name(name) for r in refs)

    unreferenced, orphan = [], []
    for f in a["files"]:
        if f in scripts or is_meta(f):
            continue
        name = os.path.basename(f)
        r, w = matched(name, all_reads), matched(name, all_writes)
        if not r and not w:
            unreferenced.append(f)
        elif w and not r and name.lower().endswith(".mat"):
            for s, i in sorted(scripts.items()):
                hit = next((x for x in i["writes"] if Ref(x).matches_name(name)), None)
                if hit:
                    orphan.append((f, s, hit))
                    break

    groups = {}
    for f, s, pat in orphan:
        groups.setdefault((s, pat), []).append(f)
    orphan_rows = []
    for (s, pat), fs in sorted(groups.items(), key=lambda kv: kv[1][0].lower()):
        if len(fs) <= 3:
            orphan_rows += ["%-40s written by %s" % (f, s) for f in fs]
        else:
            loaded = [g for g in a["files"] if Ref(pat).matches_name(os.path.basename(g))
                      and matched(os.path.basename(g), all_reads)]
            orphan_rows.append("%-40s %d files, written by %s" % (pat, len(fs), s))
            orphan_rows.append("%-40s (loaded: %s)" % ("", ", ".join(loaded) if loaded else "none"))
            orphan_rows += ["%-40s   %s" % ("", f) for f in fs]

    producers = set(a["edges"])
    consumers = {c for cs in a["edges"].values() for c in cs}
    isolated = a["isolated"]
    uncalled_fn = sorted([f for f, i in scripts.items() if i["is_function"] and not a["called_by"].get(f)],
                         key=str.lower)
    dead_end = sorted([f for f in a["top"] if f in consumers and f not in producers
                       and f not in isolated], key=str.lower)

    def section(title, rows):
        print(title)
        print("-" * 90)
        if not rows:
            print("  none")
        for row in rows:
            print("  " + row)
        print()

    print("=" * 90)
    print("UNUSED FILES  -  %s" % os.path.abspath(args.repo))
    print("=" * 90)
    section("1. UNREFERENCED FILES (no script reads or writes this name)",
            ["%-55s %8.1f kB" % (f, os.path.getsize(os.path.join(a["repo"], f)) / 1024)
             for f in unreferenced])
    section("2. ORPHAN .mat OUTPUTS (written, never loaded by any script)", orphan_rows)
    section("3. ISOLATED SCRIPTS (no shared files with any script, not run by one)", isolated)
    section("4. UNCALLED FUNCTION FILES", uncalled_fn)

    rows = []
    for f in dead_end:
        outs = sorted({r.text for r in a["eff_w"][f]}, key=str.lower)
        rows.append("%-28s -> %s" % (f, ", ".join(outs) if outs else "figures / printout only"))
    section("5. DEAD-END SCRIPTS (use pipeline data; nothing uses their results - check)", rows)

    if a["case_warn"]:
        section("WARNING: letter-case mismatches between calls and file names",
                ["%s calls '%s', file is %s" % x for x in sorted(set(a["case_warn"]))])

    print("summary: %d unreferenced, %d orphan .mat, %d isolated, %d uncalled functions, %d dead-end"
          % (len(unreferenced), len(orphan), len(isolated), len(uncalled_fn), len(dead_end)))
    print("Static scan: a file opened through a name assembled at run time may be reported")
    print("as unused.  Check before deleting.")


if __name__ == "__main__":
    main()
