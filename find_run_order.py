#!/usr/bin/env python3
"""
find_run_order.py
Work out the order in which the scripts of a MATLAB repository must be run,
and save it to a text file.

How it works
  1. Every .m and .py file is scanned with comments removed (file names in
     comments are not real dependencies).
  2. File names written by a script are taken from save / writetable /
     exportgraphics / saveas / print / ... calls, including names built with
     sprintf ('system_curve_%s_%de.mat' becomes a wildcard pattern) and names
     held in variables (SYSFILE = '...'; load(SYSFILE)).  Every other data
     file name in the code is treated as a file the script reads.
  3. A script that runs another one (run('systemCurve.m'), or calling it by
     name) absorbs the callee's inputs and outputs; the callee is listed
     under its caller and not as a separate step.
  4. Script B depends on script A if B reads a file A writes.  Hand-offs that
     do not go through a file (coefficients pasted by hand) are added from
     MANUAL_EDGES below.
  5. A topological sort gives stages: everything in one stage can run in any
     order once the earlier stages are done.

Usage:
    python find_run_order.py --repo PATH_TO_REPO [--out OUTPUT_DIR]
Output:
    OUTPUT_DIR/run_order.txt

find_unused_files.py imports analyse_repo() from this file.
"""
import argparse
import ast
import io
import os
import re
import subprocess
import sys
import tokenize
from collections import defaultdict

# Hand-offs that are not file based (from model-pipeline.md).  Applied only
# when both files exist.  (producer, consumer, reason)
MANUAL_EDGES = [
    ("pump_number.m", "fitpumpcurve.m", "train count k_trains set from the staging tables"),
    ("fitpumpcurve.m", "erdOperating.m", "pump-curve coefficients pH, pEta copied by hand"),
    ("fitpumpcurve.m", "pump_oprating.m", "pump-curve coefficients pH, pEta copied by hand"),
]

# Files belonging to this audit tool - never analysed.
TOOL_FILES = {"extract_commits.py", "flag_matlab_renames.py", "find_run_order.py",
              "find_unused_files.py", "run_all.py", "commit_history.json", "run_order.txt"}

DATA_EXT = ("mat", "csv", "nc", "xlsx", "xls", "txt", "json", "png", "jpg", "jpeg", "pdf",
            "fig", "tif", "tiff", "svg", "dat", "h5", "xml", "zip")
FILE_RE = re.compile(r"^[^\s\\/:*?\"<>|]+\.(?:%s)$" % "|".join(DATA_EXT), re.I)
SPEC_RE = re.compile(r"%%|%[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[diouxXeEfgGcs]")
WRITE_FUNCS = ("save", "writetable", "writematrix", "writecell", "writestruct", "exportgraphics",
               "saveas", "print", "imwrite", "csvwrite", "dlmwrite", "savefig", "writelines")
WRITE_CALL_RE = re.compile(r"\b(%s)\s*\(" % "|".join(WRITE_FUNCS))
READ_FUNCS = ("load", "matfile", "ncread", "ncinfo", "ncdisp", "readtable", "readmatrix", "readcell",
              "readlines", "readstruct", "csvread", "dlmread", "importdata", "fileread", "imread",
              "xlsread", "fopen", "exist", "isfile", "dir", "open", "detectImportOptions")
READ_CALL_RE = re.compile(r"\b(%s)\s*\(" % "|".join(READ_FUNCS))
RUN_CALL_RE = re.compile(r"\brun\s*\(")
CMD_RE = re.compile(r"^\s*(save|load)\s+([^\s(;,=']+)")
RUN_CMD_RE = re.compile(r"^\s*run\s+([A-Za-z]\w*(?:\.m)?)\s*$")
ASSIGN_RE = re.compile(r"^\s*([A-Za-z]\w*)\s*(?:[({][^=]*[)}])?\s*=(?!=)(.*)$")
RHS_HOLDS_NAME = re.compile(r"^\s*(?:__S\d+__|[\[{]|(?:sprintf|fullfile|strcat|string|char|cellstr|"
                            r"arrayfun|cellfun|compose|strjoin|strrep|replace|append)\s*\()")
PH_RE = re.compile(r"__S(\d+)__")
IDENT_RE = re.compile(r"\b([A-Za-z]\w*)\b")


# --------------------------------------------------------------------------
# patterns
# --------------------------------------------------------------------------
class Ref:
    """A file name, literal or sprintf pattern, as written in the code."""

    def __init__(self, text):
        self.text = text
        self.is_pattern = bool(SPEC_RE.search(text.replace("%%", "")))
        parts, last = [], 0
        for m in SPEC_RE.finditer(text):
            parts.append(re.escape(text[last:m.start()]))
            parts.append("%" if m.group() == "%%" else ".+?")
            last = m.end()
        parts.append(re.escape(text[last:]))
        self.rx = re.compile("".join(parts), re.I)
        self.example = SPEC_RE.sub(lambda m: "%" if m.group() == "%%" else "X", text)

    def matches_name(self, name):
        return bool(self.rx.fullmatch(name))

    def overlaps(self, other):
        if not self.is_pattern and not other.is_pattern:
            return self.text.lower() == other.text.lower()
        return bool(self.rx.fullmatch(other.example) or other.rx.fullmatch(self.example))

    def __repr__(self):
        return self.text


def looks_like_file(s):
    return bool(FILE_RE.match(s.strip()))


# --------------------------------------------------------------------------
# MATLAB scanning
# --------------------------------------------------------------------------
def _mask_line(line, strings):
    """Remove the comment, replace string literals by __S<n>__.  Returns
    (code, continues_on_next_line)."""
    res, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c == "%":
            break
        if line.startswith("...", i):
            return "".join(res), True
        if c == '"' or (c == "'" and not (i > 0 and (line[i - 1].isalnum() or line[i - 1] in "_)]}.'"))):
            q, j, buf = c, i + 1, []
            while j < n:
                if line[j] == q:
                    if j + 1 < n and line[j + 1] == q:
                        buf.append(q)
                        j += 2
                        continue
                    break
                buf.append(line[j])
                j += 1
            strings.append("".join(buf))
            res.append("__S%d__" % (len(strings) - 1))
            i = j + 1
            continue
        res.append(c)
        i += 1
    return "".join(res), False


def _depth(code):
    d = 0
    for ch in code:
        if ch in "([{":
            d += 1
        elif ch in ")]}":
            d -= 1
    return d


def mask_matlab(text):
    """Code statements without comments and the string table.  Lines are
    joined on '...' and while a [ ] or { } is open (a newline inside
    brackets is a row separator, not the end of the statement)."""
    strings, lines, buf, block = [], [], "", 0
    for raw in text.splitlines():
        s = raw.strip()
        if s == "%{":
            block += 1
            continue
        if block:
            if s == "%}":
                block -= 1
            continue
        code, cont = _mask_line(raw, strings)
        buf += code
        if cont:
            buf += " "
            continue
        if _depth(buf) > 0:
            buf += "; "
            continue
        lines.append(buf)
        buf = ""
    if buf:
        lines.append(buf)
    return lines, strings


def split_statements(line):
    """Split a code line on ; and , at bracket depth 0 (newline already split)."""
    out, depth, cur = [], 0, []
    for ch in line:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        if ch in ";," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return [s for s in out if s.strip()]


def call_spans(stmt, rx):
    """(start, end) of the argument text of every call matched by rx."""
    spans = []
    for m in rx.finditer(stmt):
        depth, j = 1, m.end()
        while j < len(stmt) and depth:
            depth += {"(": 1, ")": -1}.get(stmt[j], 0)
            j += 1
        spans.append((m.end(), j))
    return spans


def scan_matlab(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    lines, strings = mask_matlab(text)
    first = next((ln.strip() for ln in lines if ln.strip()), "")
    info = {"lang": "m", "is_function": first.startswith("function"),
            "reads": [], "writes": [], "strings": strings, "idents": set(),
            "assigned": set(), "local_functions": set()}

    var_lits = defaultdict(list)          # var -> placeholder ids assigned to it
    var_write, var_read, var_readcall = set(), set(), set()
    direct_w, direct_r = [], []
    info["calls_literal"] = []

    for line in lines:
        fm = re.match(r"^\s*function\s+(?:\[?[\w,\s]*\]?\s*=\s*)?([A-Za-z]\w*)", line)
        if fm:
            info["local_functions"].add(fm.group(1))
        for stmt in split_statements(line):
            cm = CMD_RE.match(stmt)
            if cm and "__S" not in cm.group(2) and looks_like_file(cm.group(2)):
                (direct_w if cm.group(1) == "save" else direct_r).append(cm.group(2))
                continue
            rm = RUN_CMD_RE.match(stmt)
            if rm:
                info["calls_literal"].append(rm.group(1))
                continue
            for a, b in call_spans(stmt, RUN_CALL_RE):
                info["calls_literal"].extend(strings[int(k)] for k in PH_RE.findall(stmt[a:b]))
            for a, b in call_spans(stmt, READ_CALL_RE):
                var_readcall.update(IDENT_RE.findall(PH_RE.sub(" ", stmt[a:b])))
            spans = call_spans(stmt, WRITE_CALL_RE)
            in_w = lambda pos: any(a <= pos < b for a, b in spans)
            for a, b in spans:
                seg = stmt[a:b]
                direct_w.extend(int(k) for k in PH_RE.findall(seg))
                var_write.update(IDENT_RE.findall(PH_RE.sub(" ", seg)))
            outside = "".join(ch if not in_w(i) else " " for i, ch in enumerate(stmt))
            am = ASSIGN_RE.match(outside)
            if am:
                lhs, rhs = am.group(1), am.group(2)
                info["assigned"].add(lhs)
                ids = [int(k) for k in PH_RE.findall(rhs)]
                if RHS_HOLDS_NAME.match(rhs):
                    var_lits[lhs].extend(ids)
                else:
                    direct_r.extend(ids)
                var_read.update(i for i in IDENT_RE.findall(PH_RE.sub(" ", rhs)) if i != lhs)
                info["idents"].update(IDENT_RE.findall(PH_RE.sub(" ", rhs)))
            else:
                direct_r.extend(int(k) for k in PH_RE.findall(outside))
                ids_out = IDENT_RE.findall(PH_RE.sub(" ", outside))
                var_read.update(ids_out)
                info["idents"].update(ids_out)
            info["idents"].update(IDENT_RE.findall(PH_RE.sub(" ", stmt)))

    def add(target, item):
        s = strings[item] if isinstance(item, int) else item
        if looks_like_file(s):
            target.append(s)

    for k in direct_w:
        add(info["writes"], k)
    for k in direct_r:
        add(info["reads"], k)
    for var, ids in var_lits.items():
        used_w = var in var_write
        for k in ids:
            if used_w:
                add(info["writes"], k)
            if var in var_readcall or not used_w:
                add(info["reads"], k)
    return info


# --------------------------------------------------------------------------
# Python scanning (light: every data-file string is a reference)
# --------------------------------------------------------------------------
PY_WRITE_HINT = re.compile(r"\.(to_csv|to_excel|to_netcdf|to_json|savefig|save|savez|savemat|"
                           r"dump|imwrite)\s*\(|open\s*\([^)]*['\"][wa]b?['\"]")


def scan_python(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    info = {"lang": "py", "is_function": False, "reads": [], "writes": [], "strings": [],
            "idents": set(), "assigned": set(), "local_functions": set(), "calls_literal": []}
    lines = src.splitlines()
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (tokenize.TokenError, SyntaxError):
        return info
    for t in toks:
        if t.type == tokenize.NAME:
            info["idents"].add(t.string)
        elif t.type == tokenize.STRING:
            try:
                val = ast.literal_eval(t.string)
            except Exception:
                continue
            if isinstance(val, bytes):
                val = val.decode("utf-8", "replace")
            if not isinstance(val, str):
                continue
            info["strings"].append(val)
            if looks_like_file(val):
                line = lines[t.start[0] - 1] if t.start[0] - 1 < len(lines) else ""
                (info["writes"] if PY_WRITE_HINT.search(line) else info["reads"]).append(val)
    return info


# --------------------------------------------------------------------------
# repository analysis
# --------------------------------------------------------------------------
def list_files(repo, exclude_dirs=()):
    """Tracked + untracked (not ignored) files, relative paths."""
    try:
        res = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", "ls-files", "-co",
                              "--exclude-standard", "-z"], capture_output=True, check=True)
        files = [f for f in res.stdout.decode("utf-8", "replace").split("\0") if f]
    except (subprocess.CalledProcessError, FileNotFoundError):
        files = []
        for root, dirs, names in os.walk(repo):
            dirs[:] = [d for d in dirs if d != ".git"]
            for nm in names:
                files.append(os.path.relpath(os.path.join(root, nm), repo).replace(os.sep, "/"))
    ex = [os.path.abspath(d) for d in exclude_dirs]
    keep = []
    for f in files:
        full = os.path.abspath(os.path.join(repo, f))
        if any(full == d or full.startswith(d + os.sep) for d in ex):
            continue
        if os.path.basename(f) in TOOL_FILES or not os.path.isfile(full):
            continue
        if "__pycache__" in f.split("/") or f.endswith((".pyc", ".pyo")):
            continue
        keep.append(f)
    return sorted(keep, key=str.lower)


def analyse_repo(repo, exclude_dirs=()):
    repo = os.path.abspath(repo)
    files = list_files(repo, exclude_dirs)
    scripts = {}
    for f in files:
        ext = f.lower().rsplit(".", 1)[-1] if "." in f else ""
        full = os.path.join(repo, f)
        if ext == "m":
            scripts[f] = scan_matlab(full)
        elif ext == "py":
            scripts[f] = scan_python(full)

    base_of = {f: os.path.splitext(os.path.basename(f))[0] for f in scripts if f.lower().endswith(".m")}
    by_lower = defaultdict(list)
    for f, b in base_of.items():
        by_lower[b.lower()].append(f)

    # --- who calls whom -----------------------------------------------------
    calls, case_warn = defaultdict(set), []
    for f, info in scripts.items():
        cands = set()
        if info["lang"] == "m":
            for name in info["idents"] - info["assigned"] - info["local_functions"]:
                cands.add(name)
        for lit in info["calls_literal"]:
            cands.add(os.path.splitext(os.path.basename(lit))[0])
        for name in cands:
            for target in by_lower.get(name.lower(), []):
                if target == f:
                    continue
                calls[f].add(target)
                if base_of[target] != name:
                    case_warn.append((f, name, target))

    def closure(f, seen=None):
        seen = seen or set()
        for c in calls.get(f, ()):
            if c not in seen:
                seen.add(c)
                closure(c, seen)
        return seen

    called_by = defaultdict(set)
    for f, cs in calls.items():
        for c in cs:
            called_by[c].add(f)

    # --- effective I/O of top-level scripts ------------------------------------
    top = [f for f in scripts if not called_by.get(f) and not scripts[f]["is_function"]]
    eff_r, eff_w = {}, {}
    for f in top:
        group = {f} | closure(f)
        eff_r[f] = [Ref(x) for g in sorted(group) for x in scripts[g]["reads"]]
        eff_w[f] = [Ref(x) for g in sorted(group) for x in scripts[g]["writes"]]

    # --- edges -----------------------------------------------------------------
    edges = defaultdict(dict)                  # producer -> consumer -> [file names]
    external = defaultdict(set)                # repo file / name -> readers
    missing = defaultdict(set)
    present = {os.path.basename(f).lower(): f for f in files}
    for c in top:
        for r in eff_r[c]:
            prods = [p for p in top if p != c and any(w.overlaps(r) for w in eff_w[p])]
            for p in prods:
                edges[p].setdefault(c, []).append(r.text)
            if not prods and not any(w.overlaps(r) for w in eff_w[c]):
                hits = [f for f in files if r.matches_name(os.path.basename(f))]
                if hits:
                    for h in hits:
                        external[h].add(c)
                else:
                    missing[r.text].add(c)
    manual = []
    for a, b, why in MANUAL_EDGES:
        pa = next((t for t in top if os.path.basename(t).lower() == a.lower()), None)
        pb = next((t for t in top if os.path.basename(t).lower() == b.lower()), None)
        if pa and pb:
            edges[pa].setdefault(pb, []).append("(manual) " + why)
            manual.append((pa, pb, why))

    # --- topological stages ------------------------------------------------------
    indeg = {f: 0 for f in top}
    for p, cs in edges.items():
        for c in cs:
            indeg[c] += 1
    linked = {f for f in top if indeg[f] or edges.get(f) or any(f in v for v in external.values())}
    stages, done, remaining = [], set(), set(linked)
    while remaining:
        ready = sorted([f for f in remaining
                        if all(p in done or p not in linked for p in top
                               if f in edges.get(p, {}))], key=str.lower)
        if not ready:
            break
        stages.append(ready)
        done.update(ready)
        remaining -= set(ready)
    cycles = sorted(remaining, key=str.lower)
    isolated = sorted([f for f in top if f not in linked], key=str.lower)

    return {
        "repo": repo, "files": files, "scripts": scripts, "calls": calls, "called_by": called_by,
        "top": top, "eff_r": eff_r, "eff_w": eff_w, "edges": edges, "external": external,
        "missing": missing, "manual": manual, "stages": stages, "cycles": cycles,
        "isolated": isolated, "case_warn": case_warn, "present": present,
    }


# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------
def render(a):
    L = []
    w = L.append
    w("RUN ORDER  -  %s" % a["repo"])
    w("=" * 90)
    w("Stages run top to bottom.  Scripts inside one stage do not depend on each other")
    w("and can run in any order.  'reads' names the stage that produced each input.")
    w("")
    ext_by_reader = defaultdict(list)
    for fname, readers in a["external"].items():
        for r in readers:
            ext_by_reader[r].append(fname)
    if a["external"]:
        w("RAW INPUTS (read, produced by no script - keep these in the repo)")
        for fname in sorted(a["external"], key=str.lower):
            w("  %-55s used by %s" % (fname, ", ".join(sorted(a["external"][fname]))))
        w("")
    stage_of = {f: i + 1 for i, st in enumerate(a["stages"]) for f in st}
    consumers = {p for p in a["edges"]}
    for i, st in enumerate(a["stages"], 1):
        w("STAGE %d" % i)
        w("-" * 90)
        for f in st:
            tail = "" if f in consumers else "   [end of chain - nothing reads its outputs]"
            w("  %s%s" % (f, tail))
            for callee in sorted(a["calls"].get(f, ())):
                w("      runs   %s  (do not run it on its own)" % callee)
            ins = defaultdict(set)
            for p, cs in a["edges"].items():
                for x in cs.get(f, []):
                    ins[p].add(x)
            for p in sorted(ins, key=lambda q: (stage_of.get(q, 0), q.lower())):
                w("      reads  %s   <- %s (stage %s)" % (", ".join(sorted(ins[p])), p, stage_of.get(p, "?")))
            for x in sorted(ext_by_reader.get(f, []), key=str.lower):
                w("      reads  %s   <- raw input" % x)
            outs = sorted({r.text for r in a["eff_w"][f]}, key=str.lower)
            if outs:
                w("      writes %s" % ", ".join(outs))
        w("")
    if a["cycles"]:
        w("CIRCULAR DEPENDENCIES (could not be ordered)")
        for f in a["cycles"]:
            w("  %s" % f)
        w("")
    if a["isolated"]:
        w("NOT LINKED TO ANY OTHER SCRIPT (no shared files, not called) - run any time, or unused")
        for f in a["isolated"]:
            w("  %s" % f)
        w("")
    helpers = sorted([f for f in a["scripts"] if a["called_by"].get(f)], key=str.lower)
    if helpers:
        w("RUN BY OTHER SCRIPTS (not separate steps)")
        for f in helpers:
            w("  %-35s run by %s" % (f, ", ".join(sorted(a["called_by"][f]))))
        w("")
    if a["manual"]:
        w("MANUAL HAND-OFFS ADDED (not visible in the files)")
        for p, c, why in a["manual"]:
            w("  %s -> %s : %s" % (p, c, why))
        w("")
    if a["missing"]:
        w("REFERENCED BUT MISSING (no script writes it and it is not in the repo)")
        for fname in sorted(a["missing"], key=str.lower):
            w("  %-55s needed by %s" % (fname, ", ".join(sorted(a["missing"][fname]))))
        w("")
    if a["case_warn"]:
        w("LETTER-CASE MISMATCHES (fail on Linux / case-sensitive systems)")
        for f, name, target in sorted(set(a["case_warn"])):
            w("  %s calls '%s' but the file is %s" % (f, name, target))
        w("")
    w("Limits: file names built at run time from variables that are not string literals,")
    w("and hand-offs not listed in MANUAL_EDGES, cannot be seen by a static scan.")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".", help="path to the repository (default: .)")
    ap.add_argument("--out", default="audit_output", help="output directory (default: audit_output)")
    args = ap.parse_args()
    if not os.path.isdir(args.repo):
        sys.exit("find_run_order: %s is not a folder" % args.repo)

    a = analyse_repo(args.repo, exclude_dirs=[args.out])
    report = render(a)
    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, "run_order.txt")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(report)
    print(report)
    print("find_run_order: %d stages, %d scripts ordered -> %s"
          % (len(a["stages"]), sum(map(len, a["stages"])), path))


if __name__ == "__main__":
    main()
