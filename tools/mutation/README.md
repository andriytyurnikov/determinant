# Mutation testing

Mutation testing checks the tests, not the VM. Each *mutant* is one small, plausible
bug, such as a `>=` turned into `>`, a sign extension dropped or a reserved-encoding
check removed. The driver injects one mutant at a time into a copy of the source tree,
runs the test suites, and records whether any test failed (the mutant is *killed*)
or all passed (it *survived*). A surviving mutant is either a gap in the tests or a
change with no observable effect (an *equivalent* mutant).

| File | Contents |
|---|---|
| `mutate.py` | the driver: validates, runs and reports. Python 3 standard library only. |
| `mutants.py` | the catalogue: every mutant as anchor-based edits, plus `EQUIVALENT`, the survivors judged equivalent, each with its reason. |

Run it before every release, and after changes to the tests or to code the catalogue
covers. A mutant that survived before and is killed now is progress. A mutant that was
killed before and survives now means coverage was lost.

## Running it

The driver edits files, so it runs on an **export** of the repository, never on the
checkout itself (it refuses a directory that contains `.git`).

```sh
# 1. Export the commit under test into a new directory: no .git, no .zig-cache.
RUN=/path/to/scratch/mutation-run            # any empty scratch directory
mkdir -p "$RUN/tree"
git archive HEAD | tar -x -C "$RUN/tree"

# 2. Check that every mutant's edits apply to that tree.
python3 -I tools/mutation/mutate.py --tree "$RUN/tree" --check

# 3. Run the catalogue. This takes about an hour (10-25 s per mutant). The first
#    step is a baseline `zig build test-all` of the pristine tree, which must pass.
python3 -I tools/mutation/mutate.py --tree "$RUN/tree" --results "$RUN/results.jsonl" \
    --commit "$(git rev-parse --short HEAD)"

# 4. Summarize.
python3 -I tools/mutation/mutate.py --report "$RUN/results.jsonl"
```

Other options:

- `mutate.py ... ID ...` runs (or `--check`s) only the given mutants, for example
  `P01 I06`.
- `--resume` skips mutants that already have a result in `--results`. Use it to
  continue an interrupted run in the same tree.
- `--fresh-cache` builds every mutant with a new, empty `--cache-dir`. It is slow (a
  cold build per mutant), and is meant for re-checking surprising results.
- `--timeout-test`, `--timeout-all`, `--timeout-all-killed` and `--test-timeout` set the
  time limits. See `--help` for the defaults.

Ctrl-C (or SIGTERM) restores the mutated file before exiting. If the driver is killed
outright, the original bytes are kept in `<tree>/.mutation-in-progress.json`, and the
next run restores them before doing anything else. `--check` refuses such a tree.

## What one mutant run does

1. Applies the mutant's edits. Each edit is `(orig, repl)`. `orig` must occur exactly
   once in the file as it stands when that edit is applied. Otherwise `--check` fails
   and the run does not start.
2. Runs `zig build test` (unit and CLI tests). This shows whether the fast suite alone
   kills the mutant.
3. Runs `zig build test-all` (adds the riscv-tests compliance suite and the corpus
   digest check, which runs with the decode cache on and off, and with runtime
   memory). Both builds get
   `--summary all --color off --error-style verbose --multiline-errors indent
   --test-timeout 60s`, so the output the driver parses does not depend on the
   terminal or on `ZIG_BUILD_*` variables. Each runs in its own process group, which
   is killed on timeout.
4. Restores the original bytes from an in-memory copy (no git), then removes the cache
   entries the mutant created and restores the cache manifests it rewrote.
5. Appends one JSON line to the results file.

## Reading the results

`--report` prints the counts and the score for all mutants, for the new mutants and
for the ported ones. It also lists how many killed mutants each suite caught, the
mutants caught only by compliance or digests, and every survivor, marked
`[EQUIVALENT: reason]` or `[gap]`.

Each line of the results file is one JSON object. `"kind": "baseline"` is the pristine
run. `"kind": "mutant"` has:

| Field | Meaning |
|---|---|
| `id`, `file`, `desc`, `edits`, `commit` | the mutant, and the `--commit` label |
| `status` | `KILLED`, `SURVIVED`, `TIMEOUT`, `COMPILE_ERROR` or `ERROR` (see below) |
| `killed_by_test` | `zig build test` alone (unit and CLI) killed it |
| `test`, `test_all` | per build: `status`, `rc`, `secs`, `suites`, `failed_tests` (first 25), `failed_test_count`, `compile_errors` (first 3); for test-all also `digest_programs` (programs whose digest or result differed) |

`suites` gives `pass` or `FAIL` for `unit`, `cli`, `compliance`, `digests` (decode cache
on), `digests_nocache` and `digests_runtime` (a `RuntimeCpuType`). The three `run test` steps are identified by their position
in the Build Summary tree, in `build.zig` order. As a cross-check, each failing test's
name prefix gives its suite: `compliance.` for compliance, `main.` for CLI, anything
else for unit. A disagreement is recorded under `warnings`, so a reordered `build.zig`
is noticed.

| Status | Meaning |
|---|---|
| `KILLED` | a test or digest check failed (or crashed, or hit the per-test timeout) |
| `SURVIVED` | everything passed |
| `TIMEOUT` | `zig build test-all` did not finish in time, and `zig build test` had not failed. If `zig build test` had failed, the status is `KILLED`. |
| `COMPILE_ERROR` | the mutant does not compile (a stillborn mutant, not a test result) |
| `ERROR` | the build failed without a failing step, or the two builds disagree: inspect `tail` |

**Score** = KILLED / (total − EQUIVALENT − COMPILE_ERROR). EQUIVALENT counts the
survivors listed in `mutants.EQUIVALENT`. `--report` also gives the score with TIMEOUT
counted as killed, when there are timeouts.

A survivor is **equivalent** only if no test could tell it apart from the original.
Examples are a mask that a later `@truncate` makes redundant, or a check that a
previous check already guarantees. Record the reason in `EQUIVALENT`. Every other
survivor is a gap: write a test that fails with the mutant and passes without it.

To check such a test, add it to a fresh export and run the driver on that export with
the survivor's ID. The baseline shows that the test passes on the unmutated code, and
the mutant should now be `KILLED`, with the new test in `failed_tests`.

## The Zig cache hazard

Zig decides whether a source file changed from the metadata in its cache manifests
(inode, mtime, size), and rehashes the contents only when that metadata differs. A
`.zig-cache` that was copied from another tree, or shared with one through
`--cache-dir`, can therefore report stale *cached* passes for mutated sources. Every
mutant then appears to survive. So:

- start every run from a tree with **no** `.zig-cache`, and never copy one in;
- never point two trees at the same `--cache-dir`;
- run one driver per tree, never several at once.

The driver enforces the first rule. After its baseline run, it records the identity of
the cache it built (path, device, inode). It refuses any other `.zig-cache` unless
given `--trust-cache`. Within a run, mutating and restoring a file always gives it a
new mtime, so Zig rehashes it. The driver also undoes each mutant's cache changes
(step 4 above). Without that, a repeat of the same mutant would find its manifest but
not the build output it names. If a result looks wrong, re-run that mutant with
`--fresh-cache`.

## Writing mutants

- Make it a bug someone could plausibly write, not a syntax error. Compile errors are
  excluded from the score.
- Anchor on text that is unique in the file, and include the surrounding line when the
  expression repeats. Anchors may span lines: write `\n` plus the exact indentation.
- Keep the ID when re-anchoring a mutant after a code change, and give new mutants new
  IDs. When the code a mutant targets disappears, drop the mutant and record its ID
  in the header comment of `mutants.py`.
- Run `--check` after every edit to the catalogue, and after every source change it
  covers.
