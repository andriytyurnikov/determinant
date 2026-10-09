#!/usr/bin/env python3
"""Mutation testing for Determinant: inject one small bug at a time into a copy of the
source tree, run the test suites, and record whether any test noticed.

  python3 -I tools/mutation/mutate.py --tree DIR --check [ID ...]
  python3 -I tools/mutation/mutate.py --tree DIR --results FILE [ID ...] [options]
  python3 -I tools/mutation/mutate.py --report FILE

For each mutant of the catalogue (mutants.py next to this file) the driver
  1. applies its edits (each anchor must occur exactly once in the file),
  2. runs `zig build test` (unit + CLI tests), then `zig build test-all` (adds the
     compliance tests and the corpus digest checks), each in its own process group,
     killed on timeout,
  3. restores the original bytes (an in-memory copy; no git involved),
  4. removes the cache entries the mutant created and restores the cache manifests it
     rewrote, so the next build starts from the pristine tree's cache,
and appends one JSON line per mutant to the results file. See README.md.

Standard library only. Run it with `python3 -I`.
"""

import argparse
import base64
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True  # never leave a __pycache__ next to the catalogue

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CATALOGUE = os.path.join(HERE, "mutants.py")

# Top-level "run test" steps of each build step, in build.zig order. They are all named
# "run test", so they are told apart by position; failing test names are checked
# against their module prefixes (see suite_of_test) to catch a reordered build.zig.
RUN_TESTS = {"test": ("unit", "cli"), "test-all": ("unit", "cli", "compliance")}
# The corpus digest check runs twice under test-digests: decode cache on, then off.
DIGEST_RUNS = ("digests", "digests_nocache", "digests_runtime")
SUITES = ("unit", "cli", "compliance", "digests", "digests_nocache", "digests_runtime")

CACHE_SUBDIRS = ("o", "h", "z", "tmp")
IN_PROGRESS = ".mutation-in-progress.json"  # in the tree: original bytes of a mutated file
BASELINE_MARK = "mutation-baseline.json"  # in the tree's .zig-cache: who built this cache

COMPILE_ERROR_RE = re.compile(r"^(\S+?\.zig):(\d+):(\d+): error: (.*)$", re.M)
FAILED_TEST_RE = re.compile(
    r"^error: '(.+)' (failed|terminated|exited|stopped|timed out|leaked|logged)", re.M)
DIGEST_CMD_RE = re.compile(r"^failed command: (.*corpus-digests.*)$", re.M)
DIGEST_DIFF_RE = re.compile(r"^\+ (\S+\.bin) ", re.M)
NATIVE_DIFF_RE = re.compile(r"^(\S+\.bin): result differs from the native run", re.M)
FAIL_WORD_RE = re.compile(r"\b(fail|failure|crash|timeout|timed out|errors?|leaks?)\b")
PASS_WORD_RE = re.compile(r"\b(pass|success|cached)\b")


class EditError(Exception):
    pass


# ---------------------------------------------------------------- catalogue


def load_catalogue(path):
    spec = importlib.util.spec_from_file_location("mutants", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for name in ("MUTANTS", "NEW", "EQUIVALENT"):
        if not hasattr(mod, name):
            sys.exit(f"{path}: missing {name}")
    return mod


def catalogue_problems(mod):
    problems, seen = [], set()
    for m in mod.MUTANTS:
        mid = m.get("id", "?")
        for key in ("id", "file", "desc", "edits"):
            if key not in m:
                problems.append(f"{mid}: missing '{key}'")
        if mid in seen:
            problems.append(f"{mid}: duplicate id")
        seen.add(mid)
        if not m.get("edits"):
            problems.append(f"{mid}: no edits")
        for n, edit in enumerate(m.get("edits", []), 1):
            if len(edit) != 2 or not edit[0] or edit[0] == edit[1]:
                problems.append(f"{mid}: edit {n} must be (orig, repl) with a non-empty orig != repl")
    for mid in mod.EQUIVALENT:
        if mid not in seen:
            problems.append(f"EQUIVALENT lists unknown id {mid}")
    return problems


def apply_edits(text, edits):
    """Apply (orig, repl) edits in order; each orig must occur exactly once."""
    for n, (orig, repl) in enumerate(edits, 1):
        count = text.count(orig)
        if count != 1:
            raise EditError(f"edit {n}: anchor occurs {count} times, must be exactly once: {orig!r}")
        text = text.replace(orig, repl, 1)
    return text


def validate(tree, mutants):
    """Every mutant's edits apply to the tree's files. Returns a list of problems."""
    problems = []
    for m in mutants:
        path = os.path.join(tree, m["file"])
        try:
            with open(path, "rb") as f:
                text = f.read().decode("utf-8")
        except OSError as e:
            problems.append(f"{m['id']}: {m['file']}: {e.strerror}")
            continue
        try:
            if apply_edits(text, m["edits"]) == text:
                problems.append(f"{m['id']}: edits leave {m['file']} unchanged")
        except EditError as e:
            problems.append(f"{m['id']}: {m['file']}: {e}")
    return problems


# ---------------------------------------------------------------- tree and cache safety


def check_tree(tree, allow_git):
    if not os.path.isfile(os.path.join(tree, "build.zig")):
        sys.exit(f"{tree}: no build.zig; --tree must be an exported source tree")
    if os.path.exists(os.path.join(tree, ".git")) and not allow_git:
        sys.exit(f"{tree} is a git checkout. Mutate an export instead "
                 "(git archive <commit> | tar -x -C DIR), or pass --allow-git-tree.")


def recover_in_progress(tree):
    """Restore a file a killed run left mutated."""
    marker = os.path.join(tree, IN_PROGRESS)
    if not os.path.exists(marker):
        return
    with open(marker) as f:
        state = json.load(f)
    with open(os.path.join(tree, state["file"]), "wb") as f:
        f.write(base64.b64decode(state["original"]))
    os.remove(marker)
    print(f"restored {state['file']} (left mutated by {state['id']} in an interrupted run)", flush=True)


def cache_identity(cache):
    st = os.stat(cache)
    return {"cache": os.path.realpath(cache), "dev": st.st_dev, "ino": st.st_ino}


def check_cache(tree, trust):
    """Refuse a .zig-cache that this script did not build in this very directory.

    Zig trusts the file metadata recorded in its cache manifests. A cache copied from
    another tree, or shared with one through --cache-dir, can report stale cached
    results for mutated sources."""
    cache = os.path.join(tree, ".zig-cache")
    if not os.path.isdir(cache) or trust:
        return
    mark = os.path.join(cache, BASELINE_MARK)
    try:
        with open(mark) as f:
            if json.load(f) == cache_identity(cache):
                return
    except (OSError, ValueError):
        pass
    sys.exit(f"{cache} was not created by this script's baseline run in this directory "
             "(copied, shared or older). Delete it and start again, or pass --trust-cache "
             "if you know it was built from this tree alone.")


def snapshot_cache(cache):
    entries = {}
    for d in CACHE_SUBDIRS:
        p = os.path.join(cache, d)
        entries[d] = set(os.listdir(p)) if os.path.isdir(p) else set()
    manifests = {}
    for name in entries["h"]:
        p = os.path.join(cache, "h", name)
        if os.path.isfile(p):
            with open(p, "rb") as f:
                manifests[name] = f.read()
    return entries, manifests


def restore_cache(cache, snapshot):
    """Remove entries created since the snapshot and restore rewritten manifests.

    Restoring the manifests matters: a compile manifest is named after the build
    options, not the sources, so a mutant's build rewrites it in place. Left alone, it
    would describe the mutant, whose output directory is deleted here, and building the
    same mutant again would hit a manifest without its artifacts."""
    entries, manifests = snapshot
    for d in CACHE_SUBDIRS:
        p = os.path.join(cache, d)
        if not os.path.isdir(p):
            continue
        for e in set(os.listdir(p)) - entries[d]:
            full = os.path.join(p, e)
            if os.path.isdir(full) and not os.path.islink(full):
                shutil.rmtree(full, ignore_errors=True)
            else:
                try:
                    os.remove(full)
                except FileNotFoundError:
                    pass
    for name, data in manifests.items():
        p = os.path.join(cache, "h", name)
        try:
            with open(p, "rb") as f:
                if f.read() == data:
                    continue
        except FileNotFoundError:
            pass
        with open(p, "wb") as f:
            f.write(data)


# ---------------------------------------------------------------- running zig build


def run_cmd(cmd, cwd, timeout):
    """Run cmd in its own process group; kill the whole group on timeout or interrupt."""
    t0 = time.monotonic()
    proc = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            start_new_session=True)
    timed_out = False
    try:
        out, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        kill_group(proc)
        out, _ = proc.communicate()
    except BaseException:
        kill_group(proc)
        proc.communicate()
        raise
    return proc.returncode, out.decode("utf-8", "replace"), timed_out, round(time.monotonic() - t0, 1)


def kill_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def build_cmd(args, step, cache_dir):
    cmd = [args.zig, "build", step, "--summary", "all", "--color", "off",
           "--error-style", "verbose", "--multiline-errors", "indent"]
    if args.test_timeout:
        cmd += ["--test-timeout", args.test_timeout]
    if cache_dir:
        cmd += ["--cache-dir", cache_dir]
    return cmd


def suite_of_test(name):
    """Suite of a failing test, from its fully qualified name: the root module's
    directory decides the prefix (src/compliance/... vs src/main/... vs the library)."""
    if name.startswith("compliance."):
        return "compliance"
    if name.startswith("main."):
        return "cli"
    return "unit"


def step_state(text):
    if FAIL_WORD_RE.search(text):
        return "FAIL"
    if PASS_WORD_RE.search(text):
        return "pass"
    return "skipped" if "skipped" in text else "?"


def parse_tree(out):
    """Children of the requested step in the Build Summary tree (in build.zig order)
    and the corpus-digests runs below test-digests."""
    i = out.rfind("Build Summary:")
    if i < 0:
        return None, None
    children, digest_runs = [], []
    for line in out[i:].splitlines()[2:]:
        if line.startswith("+- "):
            children.append(line[3:].strip())
        elif line.startswith(("|", " ")):
            m = re.match(r"^[| ]  \+- (run exe corpus-digests.*)$", line)
            if m:
                digest_runs.append(m.group(1))
        else:
            break
    return children, digest_runs


def first_unique(items, n):
    seen, res = set(), []
    for x in items:
        if x not in seen:
            seen.add(x)
            res.append(x)
    return res[:n]


def analyse(step, rc, out, timed_out, secs):
    res = {"status": None, "rc": rc, "secs": secs, "suites": {}, "failed_tests": [],
           "failed_test_count": 0, "compile_errors": [], "warnings": []}
    res["compile_errors"] = first_unique(
        (f"{f}:{ln}: {msg}" for f, ln, _, msg in COMPILE_ERROR_RE.findall(out)), 3)

    failed = FAILED_TEST_RE.findall(out)
    names = first_unique((name for name, _ in failed), len(failed))
    res["failed_test_count"] = len(names)
    res["failed_tests"] = names[:25]
    kinds = {}
    for _, kind in failed:
        kinds[kind] = kinds.get(kind, 0) + 1
    if kinds:
        res["failure_kinds"] = kinds

    children, digest_runs = parse_tree(out)
    suites = res["suites"]
    if children is not None:
        run_tests = [c for c in children if c.startswith("run test")]
        expected = RUN_TESTS[step]
        if len(run_tests) != len(expected):
            res["warnings"].append(f"{len(run_tests)} 'run test' steps, expected {len(expected)}")
        for name, text in zip(expected, run_tests):
            suites[name] = step_state(text)
        if step == "test-all":
            for name, text in zip(DIGEST_RUNS, digest_runs):
                suites[name] = step_state(text)
            # Cross-check with the failed commands: the other runs have their flag.
            for cmd in DIGEST_CMD_RE.findall(out):
                name = ("digests_nocache" if "--no-decode-cache" in cmd else
                        "digests_runtime" if "--runtime-memory" in cmd else "digests")
                if suites.get(name) != "FAIL":
                    res["warnings"].append(f"failed command for {name}, but its step is {suites.get(name)}")
                    suites[name] = "FAIL"
            programs = DIGEST_DIFF_RE.findall(out) + NATIVE_DIFF_RE.findall(out)
            if programs:
                uniq = first_unique(programs, len(programs))
                res["digest_programs_count"] = len(uniq)
                res["digest_programs"] = uniq[:10]
    for name in names:
        suite = suite_of_test(name)
        if suites.get(suite) != "FAIL":
            res["warnings"].append(f"failing test {name!r} but suite {suite} is {suites.get(suite)}")

    if timed_out:
        res["status"] = "TIMEOUT"
    elif res["compile_errors"]:
        res["status"] = "COMPILE_ERROR"
    elif rc == 0:
        res["status"] = "SURVIVED"
    elif "FAIL" in suites.values() or names:
        res["status"] = "KILLED"
    else:
        res["status"] = "ERROR"  # zig build failed without a failing test or step
    if res["status"] in ("ERROR", "TIMEOUT") or res["warnings"]:
        res["tail"] = out[-3000:]
    if not res["warnings"]:
        del res["warnings"]
    return res


def overall_status(test, test_all):
    if "COMPILE_ERROR" in (test["status"], test_all["status"]):
        return "COMPILE_ERROR"
    if test_all["status"] == "TIMEOUT" and test["status"] == "KILLED":
        return "KILLED"  # test-all runs the same unit and CLI tests
    if test_all["status"] == "SURVIVED" and test["status"] != "SURVIVED":
        return "ERROR"  # inconsistent: test failed but test-all passed
    return test_all["status"]


def failed_suites(rec):
    return [s for s in SUITES if rec["test_all"]["suites"].get(s) == "FAIL"]


# ---------------------------------------------------------------- the run


def run_baseline(args, tree):
    print("baseline: zig build test-all on the pristine tree ...", flush=True)
    rc, out, to, secs = run_cmd(build_cmd(args, "test-all", None), tree, args.timeout_all)
    res = analyse("test-all", rc, out, to, secs)
    counts = re.findall(r"^\+- run test (.*)$", out, re.M)
    print(f"baseline: {res['status']} in {secs}s; run test steps: {counts}", flush=True)
    if res["status"] != "SURVIVED":
        print(out[-4000:])
        sys.exit("baseline failed: the pristine tree must pass zig build test-all")
    rc, out, to, test_secs = run_cmd(build_cmd(args, "test", None), tree, args.timeout_test)
    if analyse("test", rc, out, to, test_secs)["status"] != "SURVIVED":
        print(out[-4000:])
        sys.exit("baseline failed: the pristine tree must pass zig build test")
    cache = os.path.join(tree, ".zig-cache")
    with open(os.path.join(cache, BASELINE_MARK), "w") as f:
        json.dump(cache_identity(cache), f)
    return {"kind": "baseline", "time": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "commit": args.commit, "secs": secs, "run_tests": counts}


def run_mutant(args, tree, m, snapshot):
    path = os.path.join(tree, m["file"])
    with open(path, "rb") as f:
        original = f.read()
    mutated = apply_edits(original.decode("utf-8"), m["edits"]).encode("utf-8")
    rec = {"kind": "mutant", "id": m["id"], "file": m["file"], "desc": m["desc"],
           "edits": [list(e) for e in m["edits"]], "commit": args.commit}
    marker = os.path.join(tree, IN_PROGRESS)
    cache_dir = None
    try:
        with open(marker, "w") as f:
            json.dump({"id": m["id"], "file": m["file"],
                       "original": base64.b64encode(original).decode("ascii")}, f)
        with open(path, "wb") as f:
            f.write(mutated)
        if args.fresh_cache:
            cache_dir = tempfile.mkdtemp(prefix=f"zig-cache-{m['id']}-",
                                         dir=os.path.dirname(os.path.abspath(args.results)))
            rec["fresh_cache_dir"] = cache_dir
        rc, out, to, secs = run_cmd(build_cmd(args, "test", cache_dir), tree, args.timeout_test)
        rec["test"] = analyse("test", rc, out, to, secs)
        timeout = args.timeout_all_killed if rec["test"]["status"] == "KILLED" else args.timeout_all
        rc, out, to, secs = run_cmd(build_cmd(args, "test-all", cache_dir), tree, timeout)
        rec["test_all"] = analyse("test-all", rc, out, to, secs)
    finally:
        with open(path, "wb") as f:
            f.write(original)
        if os.path.exists(marker):  # removed only once the original bytes are back
            os.remove(marker)
        if cache_dir:
            shutil.rmtree(cache_dir, ignore_errors=True)
        elif snapshot is not None:
            restore_cache(os.path.join(tree, ".zig-cache"), snapshot)
    rec["status"] = overall_status(rec["test"], rec["test_all"])
    rec["killed_by_test"] = rec["test"]["status"] == "KILLED"
    return rec


def done_ids(results):
    ids = set()
    if os.path.exists(results):
        with open(results) as f:
            for line in f:
                if line.strip():
                    r = json.loads(line)
                    if r.get("kind") == "mutant" and r.get("status") != "ERROR":
                        ids.add(r["id"])
    return ids


def select(mod, ids):
    by_id = {m["id"]: m for m in mod.MUTANTS}
    unknown = [i for i in ids if i not in by_id]
    if unknown:
        sys.exit(f"unknown mutant ids: {' '.join(unknown)}")
    return [by_id[i] for i in ids] if ids else list(mod.MUTANTS)


def cmd_check(args, mod):
    tree = os.path.abspath(args.tree)
    if os.path.exists(os.path.join(tree, IN_PROGRESS)):
        sys.exit(f"{tree} has a mutated file left by an interrupted run; run without --check to restore it")
    mutants = select(mod, args.ids)
    problems = catalogue_problems(mod) + validate(tree, mutants)
    for p in problems:
        print(p)
    if problems:
        sys.exit(f"{len(problems)} problem(s)")
    new = {m["id"] for m in mod.NEW}
    n_new = sum(1 for m in mutants if m["id"] in new)
    files = len({m["file"] for m in mutants})
    print(f"{len(mutants)} mutants ({len(mutants) - n_new} ported, {n_new} new) in {files} files "
          f"validated against {tree}")


def cmd_run(args, mod):
    tree = os.path.abspath(args.tree)
    check_tree(tree, args.allow_git_tree)
    recover_in_progress(tree)
    mutants = select(mod, args.ids)
    problems = catalogue_problems(mod) + validate(tree, mutants)
    if problems:
        for p in problems:
            print(p)
        sys.exit("the catalogue does not apply to this tree; fix it first (--check)")
    if args.resume:
        done = done_ids(args.results)
        mutants = [m for m in mutants if m["id"] not in done]
        print(f"resume: {len(done)} done, {len(mutants)} to run", flush=True)

    snapshot = None
    if not args.fresh_cache:
        check_cache(tree, args.trust_cache)
        cache = os.path.join(tree, ".zig-cache")
        if not args.no_baseline and not os.path.isdir(cache):
            base = run_baseline(args, tree)
            with open(args.results, "a") as f:
                f.write(json.dumps(base) + "\n")
        elif not args.no_baseline:
            print("baseline: skipped, this tree's cache was built by an earlier baseline run", flush=True)
        # Without a cache yet (--no-baseline), everything a mutant builds is pruned.
        snapshot = snapshot_cache(cache)

    t_start = time.monotonic()
    for k, m in enumerate(mutants, 1):
        rec = run_mutant(args, tree, m, snapshot)
        with open(args.results, "a") as f:
            f.write(json.dumps(rec) + "\n")
        suites = ",".join(failed_suites(rec)) or "-"
        secs = rec["test"]["secs"] + rec["test_all"]["secs"]
        print(f"[{k:3}/{len(mutants)}] {m['id']:5} {rec['status']:13} test={rec['test']['status']:13} "
              f"{suites:44} {secs:6.1f}s  {m['desc']}", flush=True)
    print(f"{len(mutants)} mutants in {time.monotonic() - t_start:.0f}s; results in {args.results}")


# ---------------------------------------------------------------- report


def cmd_report(args, mod):
    recs = {}
    baselines = []
    with open(args.report) as f:
        for line in f:
            if not line.strip():
                continue
            r = json.loads(line)
            if r.get("kind") == "mutant":
                recs[r["id"]] = r  # the last result per mutant wins
            elif r.get("kind") == "baseline":
                baselines.append(r)
    catalogue = {m["id"]: m for m in mod.MUTANTS}
    new_ids = {m["id"] for m in mod.NEW}
    order = [m["id"] for m in mod.MUTANTS if m["id"] in recs] + sorted(set(recs) - set(catalogue))

    for b in baselines[-1:]:
        print(f"baseline: commit {b.get('commit')}, {b.get('time')}, run test steps {b.get('run_tests')}")
    missing = [i for i in catalogue if i not in recs]
    if missing:
        print(f"not run: {len(missing)} mutants ({' '.join(missing[:20])}{' ...' if len(missing) > 20 else ''})")
    stale = [i for i in order if i in catalogue and recs[i]["edits"] != [list(e) for e in catalogue[i]["edits"]]]
    if stale:
        print(f"results whose edits differ from the current catalogue: {' '.join(stale)}")

    def summarize(ids, label):
        if not ids:
            print(f"\n{label}: none run")
            return {}
        by = {}
        for i in ids:
            by.setdefault(recs[i]["status"], []).append(i)
        equivalent = [i for i in by.get("SURVIVED", []) if i in mod.EQUIVALENT]
        killed = len(by.get("KILLED", []))
        timeouts = len(by.get("TIMEOUT", []))
        denom = len(ids) - len(equivalent) - len(by.get("COMPILE_ERROR", []))
        counts = ", ".join(f"{s} {len(v)}" for s, v in sorted(by.items()))
        print(f"\n{label}: {len(ids)} mutants: {counts}; equivalent {len(equivalent)}")
        if denom:
            line = f"  score = KILLED / (total - EQUIVALENT - COMPILE_ERROR) = {killed}/{denom} = {100 * killed / denom:.1f}%"
            if timeouts:
                line += f"; counting TIMEOUT as killed: {100 * (killed + timeouts) / denom:.1f}%"
            print(line)
        return by

    by = summarize(order, "all")
    summarize([i for i in order if i in new_ids], "new")
    summarize([i for i in order if i not in new_ids], "ported")

    killed = by.get("KILLED", [])
    per_suite = {s: sum(1 for i in killed if s in failed_suites(recs[i])) for s in SUITES}
    print(f"\nkilled mutants caught by each suite: {per_suite}")
    late = [i for i in killed if recs[i]["test"]["status"] == "SURVIVED"]
    print(f"killed only by compliance/digests (zig build test passes): {len(late)}")
    for i in late:
        print(f"  {i:5} {','.join(failed_suites(recs[i])):30} {recs[i]['desc']}")

    for status in ("SURVIVED", "TIMEOUT", "COMPILE_ERROR", "ERROR"):
        ids = by.get(status, [])
        if not ids:
            continue
        print(f"\n{status}: {len(ids)}")
        for i in ids:
            note = ""
            if status == "SURVIVED":
                note = f"  [EQUIVALENT: {mod.EQUIVALENT[i]}]" if i in mod.EQUIVALENT else "  [gap]"
            elif status == "COMPILE_ERROR":
                errs = recs[i]["test_all"]["compile_errors"] or recs[i]["test"]["compile_errors"]
                note = f"  ({errs[0] if errs else '?'})"
            print(f"  {i:5} {recs[i]['desc']}{note}")
    contradictions = [i for i in mod.EQUIVALENT if i in recs and recs[i]["status"] != "SURVIVED"]
    if contradictions:
        print(f"\nlisted as EQUIVALENT but not SURVIVED: {' '.join(contradictions)}")


# ---------------------------------------------------------------- main


def main():
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="See tools/mutation/README.md.")
    ap.add_argument("ids", nargs="*", metavar="ID", help="mutants to run or check (default: all)")
    ap.add_argument("--tree", help="exported source tree to mutate (never a git checkout)")
    ap.add_argument("--results", help="JSON-lines file the results are appended to")
    ap.add_argument("--check", action="store_true", help="only validate that every mutant's edits apply")
    ap.add_argument("--report", metavar="RESULTS", help="summarize a results file")
    ap.add_argument("--catalogue", default=DEFAULT_CATALOGUE, help="mutant catalogue (default: mutants.py here)")
    ap.add_argument("--resume", action="store_true", help="skip mutants that already have a result")
    ap.add_argument("--fresh-cache", action="store_true",
                    help="build every mutant with a new, empty --cache-dir (slow; to re-check results)")
    ap.add_argument("--no-baseline", action="store_true", help="skip the baseline run of the pristine tree")
    ap.add_argument("--trust-cache", action="store_true",
                    help="use a .zig-cache this script's baseline did not create (see README)")
    ap.add_argument("--allow-git-tree", action="store_true", help="allow --tree to be a git checkout")
    ap.add_argument("--commit", help="label stored with each result, e.g. the exported commit")
    ap.add_argument("--zig", default="zig", help="zig executable (default: zig on PATH)")
    ap.add_argument("--timeout-test", type=int, default=300, help="seconds for zig build test (default 300)")
    ap.add_argument("--timeout-all", type=int, default=900,
                    help="seconds for zig build test-all when zig build test passed (default 900)")
    ap.add_argument("--timeout-all-killed", type=int, default=240,
                    help="seconds for zig build test-all when zig build test failed (default 240)")
    ap.add_argument("--test-timeout", default="60s",
                    help="per unit test limit given to zig build, '' to disable (default 60s)")
    args = ap.parse_args()

    mod = load_catalogue(args.catalogue)
    if args.report:
        return cmd_report(args, mod)
    if not args.tree:
        ap.error("--tree is required")
    if args.check:
        return cmd_check(args, mod)
    if not args.results:
        ap.error("--results is required to run mutants")
    signal.signal(signal.SIGTERM, interrupt)
    try:
        cmd_run(args, mod)
    except KeyboardInterrupt:
        sys.exit("interrupted; the mutated file was restored")


def interrupt(signum, frame):
    raise KeyboardInterrupt  # unwinds through run_mutant's finally, which restores the file


if __name__ == "__main__":
    main()
