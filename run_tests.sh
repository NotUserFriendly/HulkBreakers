#!/usr/bin/env bash
set -euo pipefail

# Set GODOT=/path/to/godot if 'godot' isn't on PATH.
GODOT="${GODOT:-godot}"

# taskblock-47 Pass C / taskblock-48 Pass A1, **rewritten at taskblock-67 Pass C**:
# four rungs, because they answer different questions and cost an order of magnitude
# apart.
#
#   ./run_tests.sh test_foo.gd   one file (or a directory) — the edit loop
#   ./run_tests.sh fast          everything that does not build a bout — SHARDED
#   ./run_tests.sh               everything — SHARDED. Green before a pass commits.
#   ./run_tests.sh profile       everything, one process. The bookkeeping run.
#
# **A targeted run is never what a pass is green on.** It cannot see that a change
# broke a different file, which is the entire reason the full suite exists.
#
# ## taskblock-67 Pass C: `fast` and the bare gate are sharded, and the names did not move
#
# **The rungs were inverted and nobody would have noticed from reading them.** The rung
# run before every pass commit cost MORE than the rung that ran the whole suite, and
# covered less: serial `fast` measured **684 s** against a sharded full gate's 177-733 s.
# Both now shard, and the names stay what they are because they are what `CLAUDE.md`
# documents and what gets typed — renaming them would leave every existing instruction
# pointing at the wrong thing.
#
# **Measured at Pass B, six runs, before any of this was wired** (wall / spread):
#
#   serial fast                       684.7, 684.1 s   0.1%
#   sharded, full map, skip in place  140.4, 139.4 s   0.7%
#   sharded, fast-specific map        113.3, 113.8 s   0.4%   <- this rung
#
# **A fast gate builds no bouts, so it has no corpus draw, so it is a number rather
# than a distribution.** That is why it is the per-pass rung and the sharded full gate
# is not: the full gate's cost is a draw (177-733 s across four runs on one tree).
#
# ## `profile` is not "the slow way" — it is the only run that can write the artifacts
#
# `test/suite_profile.json` is per-file wall-clock, and eight processes competing for
# cores inflate and scramble exactly that (taskblock-66 E6). A profile regenerated
# under sharding would degrade the packer's own input a little more every time, and
# each run would look locally reasonable. So the single-process rung is named for the
# job only it can do rather than for being slower.
#
# **Run it before a bug-hunt block, before a doc review, and never less often than
# every five taskblocks.** Five is not a round number: `reports/` keeps a rolling five,
# so drift found at a review can still be attributed to the reports covering it. It is
# also the only thing that detects wall-clock growth in work no counter sees —
# `test_generated_board_sight_sweep.gd` burns 31.8 s while moving `{floods: 2, maps: 1}`
# (tb67 A), and after Pass A the work budget rides on merged shard totals, so
# `SuiteBudget` no longer depends on this rung at all.
#
# ## `shard` is retired (taskblock-67 Pass C)
#
# It named the sharded full gate when that was an opt-in fourth rung. The bare gate IS
# that now, so the name was a synonym for the default. It is refused **by name** below
# rather than falling through to "no test file called 'shard'", because a rung that
# stops existing has to say so — the taskblock-66 census counted eight stale claims in
# this repo's own instructions and a silently-wrong error message is how a ninth starts.
#
# The full gate is a strict superset of the fast one; nothing exists only in the fast
# tier. Which files the fast gate skips is `SuiteTier.BOUT_FILES`, and it is NOT a
# directory rule: eleven of the twelve bout-building files live under test/unit/,
# including the single most expensive file in the suite, so "skip integration/" would
# have declared the fast gate bout-free while it played almost all of them.
#
# The tier list is checked against the profile's own bout counter on every run
# (test_suite_tier.gd), so adding a bout to a unit test fails a test rather than
# quietly making the fast gate slow.
#
# ## The fixed floor, measured rather than assumed (taskblock-48 A1)
#
#   gdlint src test   6.14 s
#   import            2.32 s
#   parse guard       0.82 s
#   GUT startup      ~1.20 s
#   ---------------------------
#   floor            10.5 s
#
# On a sub-second file that floor is the entire cost, so **a targeted run narrows what
# it can honestly narrow**: gdlint runs over the target only (0.21 s), and the
# checkpoint parse guard is skipped because it guards checkpoint scenarios and has
# nothing to do with the file under test. The import step STAYS — it is what registers
# a `class_name`, and skipping it makes a newly added script invisible in a way that
# looks like a broken test. That takes a targeted run's floor to about 3.7 s.
GATE="${1:-full}"
TARGET=""
GATE_START=$SECONDS

# ## taskblock-67 Pass D: **the fallback is loud, recorded, and never a test failure**
#
# The risk sharding carries is not that it breaks. It is that it **degrades quietly** and a
# future CC concludes that twenty-two minutes is normal — the same shape as the profile going
# eight blocks stale, where every individual run looked fine.
#
# **A failing test is a red gate. It is never a reason to re-run anything single-process.** Only
# infrastructure may fall back, and the list is closed: the map missing or unparseable, `python3`
# absent, or a shard process that never started. A shard that started and *died* is a gate
# failure and stays one — laundering a real crash into a slow green run is the one outcome worse
# than the crash.
#
# **Loud means it survives being skimmed**, because CC reads the tail of a log and reports from
# it. So a fallback appears in all three of: a banner where it happens, the final verdict line,
# and a durable record.
FALLBACK_LOG="${HB_FALLBACK_LOG:-audit/gate_fallbacks.log}"
FALLBACK_REASON=""
REPACK_NOTE=""

# **HB_DRY_RUN is a test-only seam and cannot be mistaken for a pass.** Testing the fallback for
# real would mean running the whole suite single-process — 1687 s — for each case, so the two
# decision tests stop the script at the point the decision is made. It exits **3** and prints
# `DRY RUN`, so a stray export produces something that is obviously not a green gate.
DRY_RUN="${HB_DRY_RUN:-}"

## Announces a fallback where it happens. The condition and the fix, not just the fact.
note_fallback() {
  FALLBACK_REASON="$1"
  echo "" >&2
  echo "######################################################################" >&2
  echo "# SHARDED GATE UNAVAILABLE — FALLING BACK TO ONE PROCESS" >&2
  echo "# condition: $1" >&2
  echo "# fix:       $2" >&2
  echo "# This is a finding to REPORT, not a slow run to sit through." >&2
  echo "######################################################################" >&2
}

## The durable half. **One fallback is noise; the same one four times is a defect nobody filed** —
## which is only visible if they are written down somewhere a doc review will read.
record_incident() {
  local kind="$1" detail="$2"
  mkdir -p "$(dirname "$FALLBACK_LOG")"
  printf '%s\t%s\t%s\t%s\t%ss\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$kind" "$GATE" "$detail" "$((SECONDS - GATE_START))" \
    >> "$FALLBACK_LOG"
}

## The line that gets quoted into a report, and therefore the line a fallback has to reach.
verdict() {
  local status="$1" mode="$2" label="PASS"
  [[ "$status" -ne 0 ]] && label="FAIL"
  echo ""
  echo "=== GATE $label — $GATE, $mode, $((SECONDS - GATE_START)) s$REPACK_NOTE"
  if [[ -n "$FALLBACK_REASON" ]]; then
    echo "=== FELL BACK TO ONE PROCESS: $FALLBACK_REASON"
    echo "=== A fallback is a finding to report. Recorded in $FALLBACK_LOG"
  fi
}

# ## The sharded path — taskblock-66 Pass F, generalised to two rungs at taskblock-67 Pass C
#
# Which file goes where is a committed artifact generated by `tools/pack_shards.gd` — see
# `ShardMap` for why it is an artifact rather than computed here. Two maps, from one packer run
# so they cannot be packed from different profiles:
#
#   test/shard_map.json        the full gate. **Shard 0 carries the corpus readers and is
#                              launched first**: its cost is the draw, which is the makespan in
#                              every draw the model admits, so it must never wait on a scheduler.
#   test/shard_map_fast.json   the fast gate. Bout files are absent rather than zero-costed, so
#                              no shard loads and parses a file whose every test will skip — and
#                              since every corpus reader IS a bout file, there is no draw to
#                              reserve a shard for and all eight bins do work.
#
# **The merge is what makes a red shard visible.** Eight output streams are exactly what makes
# people abandon sharding, so `tools/merge_shards.py` prints one verdict in a stable order, and a
# shard that produced no summary line fails the gate rather than contributing nothing. That is the
# same guard the single-process path carries below.
#
# **`gdlint src test` and the checkpoint parse guard both run here, and are named so nobody
# removes them believing the shards cover them** (Pass C2). They do not: gdlint never enters an
# engine at all, and the parse guard loads checkpoint SCENARIOS, which are not test files and are
# therefore in neither map.
run_sharded() {
  local map="${HB_SHARD_MAP:-$1}" fast="$2"
  # **`HB_REPACK_CMD` is a test-only seam, and it exists for safety rather than convenience.**
  # The stale-map branch rewrites two committed artifacts, so a test that drives this path with a
  # deliberately-incomplete map would repack the real ones as a side effect. Overriding the
  # command with a no-op is what lets the branch be exercised without the gate editing the repo.
  local repack="${HB_REPACK_CMD:-godot --headless --path . -s res://tools/pack_shards.gd}"

  # --- before launch: the three infrastructure conditions ---------------------------
  if ! command -v python3 > /dev/null 2>&1; then
    note_fallback "python3 is not on PATH, so the shard merge cannot run" "install python3"
    return 1
  fi
  if [[ ! -f "$map" ]]; then
    note_fallback "$map does not exist" "$repack"
    return 1
  fi
  if ! python3 -c "import json,sys;json.load(open('$map'))['shards']" > /dev/null 2>&1; then
    note_fallback "$map is not a parseable shard map" "$repack"
    return 1
  fi

  # **A stale map repacks rather than failing with an instruction.** The whole premise of
  # taskblock-67 is automation over discretion at the moment of running, and the repack is one
  # deterministic command whose input is already committed. **The regenerated maps are part of
  # the commit and the diff must not be reverted** — and it is a big diff: LPT packing is
  # sensitive to its input costs, so a repack moved 274 of 367 files at Pass B.
  #
  # This is not a fallback. The gate still shards; it just fixes its own input first.
  local unassigned
  unassigned=$(python3 - "$map" "${fast:+fast}" <<'PY'
import json, os, re, sys
assigned = {p for fs in json.load(open(sys.argv[1]))["shards"].values() for p in fs}
expected = set()
for root, _, files in os.walk("test"):
    for f in files:
        if f.startswith("test_") and f.endswith(".gd"):
            expected.add("res://" + os.path.join(root, f).replace(os.sep, "/"))
if len(sys.argv) > 2 and sys.argv[2] == "fast":
    # Bout files are absent from the fast map by design, not by staleness.
    src = open("test/support/suite_tier.gd").read()
    block = re.search(r"BOUT_FILES[^=]*=\s*\[(.*?)\]", src, re.S).group(1)
    expected -= set(re.findall(r'"(res://[^"]+)"', block))
print(len(expected - assigned))
PY
)
  if [[ "$unassigned" -gt 0 ]]; then
    echo ""
    echo "== $map is stale: $unassigned test file(s) are in no shard =="
    echo "== a file in no shard is never run, and the gate would go green having skipped it =="
    echo "== repacking now; the map diff belongs in your commit =="
    if [[ -n "$DRY_RUN" ]]; then
      echo "DRY RUN — would repack and continue sharded"
      exit 3
    fi
    if ! $repack; then
      note_fallback "$map is stale and the repack failed" "run $repack by hand"
      return 1
    fi
    REPACK_NOTE=" [REPACKED $unassigned unassigned file(s) — commit the map diff]"
    record_incident "repack" "$unassigned unassigned file(s) in $map"
  fi

  if [[ -n "$DRY_RUN" ]]; then
    echo "DRY RUN — would run the sharded gate over $map"
    exit 3
  fi

  local count
  count=$(python3 -c "import json;print(json.load(open('$map'))['shard_count'])")
  echo "== sharded ${fast:+fast }gate: $count shards from $map =="

  gdlint src test
  "$GODOT" --headless --path . --import --quit || true
  "$GODOT" --headless -d --display-driver headless --audio-driver Dummy \
    --path . -s res://tools/checkpoints/parse_guard.gd

  SHARD_DIR="$(mktemp -d)"
  trap 'rm -rf "$SHARD_DIR"' EXIT
  export HB_NO_WRITE_PROFILE=1
  [[ -n "$fast" ]] && export HB_FAST_GATE=1

  local logs=() pids=() codes=() i log args
  for i in $(seq 0 $((count - 1))); do
    args=$(python3 -c "
import json
for p in json.load(open('$map'))['shards']['$i']:
    print('--test=' + p)
")
    log="$SHARD_DIR/shard$i.log"
    logs+=("$log")
    # Shard 0 first, and every shard detached — the wait below is the barrier.
    GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
      --display-driver headless --audio-driver Dummy \
      --path . -s res://tools/run_suite.gd -- $args > "$log" 2>&1 &
    pids+=($!)
  done
  # **Waited per pid rather than bare `wait`, so each shard's exit code survives.** The
  # never-started test below cannot be made without them.
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then codes[$i]=0; else codes[$i]=$?; fi
  done

  # ## The dangerous condition, and why it is drawn this tightly
  #
  # *"A shard produced no summary line"* is both a launch failure and a crash, and only the first
  # may fall back — otherwise **a real crash gets laundered into a slow green run.** So the test
  # is for a process that demonstrably never got going: the shell could not execute the binary
  # (126/127) **and** the log carries no engine banner. Anything else — a segfault, a Debugger
  # Break, a kill, an unexplained death — falls through to the merge and fails the gate.
  #
  # **`BR67.01` is exactly the case this must not swallow.** A shard died after ~499 s with no
  # summary and no explanation; it had plainly started, so it stays a failure.
  local never_started="" unfinished=()
  for i in "${!logs[@]}"; do
    if grep -q -- "--- suite cost ---" "${logs[$i]}"; then
      continue
    fi
    unfinished+=("$i")
    if [[ "${codes[$i]}" -eq 126 || "${codes[$i]}" -eq 127 ]] \
      && ! grep -q "Godot Engine" "${logs[$i]}"; then
      never_started="shard $i"
    fi
  done

  # ## `BR67.01`: **a shard that dies takes its own evidence with it, unless this runs**
  #
  # The shard logs live in a `mktemp -d` under a cleanup trap, so the one artifact that could
  # name the cause is deleted at the moment the gate reports the failure. Observed once: shard 0
  # died after ~499 s, the other seven were green at 0 failures, and nothing could be said about
  # why — it was green in isolation and green on the next gate.
  #
  # **Only the shards that produced no summary are kept.** An ordinary test failure is already
  # reported by the merge with its file and message; a shard with no summary is the case where
  # the merge can say nothing except that it happened.
  if [[ ${#unfinished[@]} -gt 0 ]]; then
    local keep="out/logs/gate/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$keep"
    for i in "${unfinished[@]}"; do
      cp "${logs[$i]}" "$keep/shard$i.log" 2> /dev/null || true
    done
    echo "" >&2
    echo "== shard(s) ${unfinished[*]} produced no summary — logs kept in $keep ==" >&2
    echo "== they would otherwise be deleted with the temp directory (BR67.01) ==" >&2
    record_incident "shard-no-summary" "shard(s) ${unfinished[*]}; logs in $keep"
  fi
  if [[ -n "$never_started" ]]; then
    note_fallback \
      "$never_started never started — exit ${codes[0]}, no engine banner in its log" \
      "check that GODOT=${GODOT} is executable"
    return 1
  fi

  # ## tb67 Pass A: **the sharded gate enforces the work budget.**
  #
  # Until this landed, `SuiteBudget` was inert on the path people actually run.
  # `merge_shards.py` computed the controlled totals and gated on nothing but shard health;
  # `test_suite_budget.gd` reads the *committed* profile, so under sharding it re-asserted a
  # snapshot the last single-process gate wrote and passed regardless of what this run cost.
  #
  # **Totals, never per-file.** Counts are comparable across process counts once duplication is
  # subtracted; per-file wall-clock is not, and never becomes so — see `check_budget.gd`.
  #
  # **The budget check is skipped when the merge already failed, and that is deliberate.** A red
  # gate has a cause; a second verdict about how much work an incomplete suite did adds noise to
  # an investigation that already has somewhere to start. Same reasoning as
  # `run_suite.gd::_on_end_run` declining to write artifacts from a red run.
  #
  # **It is also skipped on the fast gate, and that is not laziness.** The fast gate does not run
  # 21 bout-building files, so its totals are a fraction of the suite's and every gated counter
  # reads low against a whole-suite baseline. A check that cannot fail is worse than no check: it
  # prints a reassuring line nobody should trust.
  local totals="$SHARD_DIR/totals.json"
  set +e
  python3 tools/merge_shards.py "--totals-json=$totals" "${logs[@]}"
  local merge_status=$?
  set -e
  if [[ "$merge_status" -ne 0 ]]; then
    verdict "$merge_status" "sharded"
    exit "$merge_status"
  fi
  if [[ -n "$fast" ]]; then
    echo ""
    echo "--- work budget --- not checked: a fast gate measures part of the suite"
    verdict 0 "sharded"
    exit 0
  fi

  set +e
  "$GODOT" --headless --path . -s res://tools/check_budget.gd -- "--totals=$totals"
  local budget_status=$?
  set -e
  verdict "$budget_status" "sharded"
  exit "$budget_status"
}

# **`shard` named the sharded full gate when that was opt-in. The bare gate is that now.**
# Refused by name rather than left to the filename resolver, which would say "no test file or
# directory named 'shard'" — true, unhelpful, and the start of a stale instruction.
if [[ "$GATE" == "shard" ]]; then
  echo "'shard' was retired at taskblock-67 Pass C — the bare gate is sharded now." >&2
  echo "  ./run_tests.sh            the sharded full gate (what 'shard' used to mean)" >&2
  echo "  ./run_tests.sh fast       the sharded fast gate" >&2
  echo "  ./run_tests.sh profile    one process, and the only run that writes the profile" >&2
  exit 2
fi

# `run_sharded` exits when it handled the gate. Reaching the line after it means it declined —
# an infrastructure condition — so the run continues single-process with the banner already
# printed and the reason carried into the verdict below.
if [[ "$GATE" == "fast" ]]; then
  run_sharded "test/shard_map_fast.json" "fast" || true
  record_incident "fallback" "$FALLBACK_REASON"
  if [[ -n "$DRY_RUN" ]]; then
    verdict 3 "one process (DRY RUN — nothing was run)"
    exit 3
  fi
  export HB_FAST_GATE=1
  echo "== fast gate, one process: skipping bout-building files =="
fi
if [[ "$GATE" == "full" ]]; then
  run_sharded "test/shard_map.json" "" || true
  record_incident "fallback" "$FALLBACK_REASON"
  if [[ -n "$DRY_RUN" ]]; then
    verdict 3 "one process (DRY RUN — nothing was run)"
    exit 3
  fi
  echo "== full gate, one process =="
fi

# Only `profile` and a targeted file reach here — `fast` and `full` exited inside
# `run_sharded` above.
case "$GATE" in
  profile)
    echo "== profile run: the whole suite in one process, writing the artifacts =="
    ;;
  fast | full)
    # Only reachable after a fallback — the scope stays the whole suite.
    ;;
  *)
    # A bare filename resolves by search — nobody should have to type
    # res://test/unit/logic/ai/... . Two files sharing a name is a repo mistake to
    # fix, not a case to disambiguate cleverly, so it prints both and stops.
    if [[ -e "$GATE" ]]; then
      TARGET="$GATE"
    else
      # HB_TEST_ROOT is a test-only seam. `test_run_suite.gd` has to prove that two
      # same-named files are reported rather than silently disambiguated, and doing
      # that against the real tree meant writing a duplicate .gd into test/ — which
      # races Godot's importer and orphans a .uid, the exact failure that broke the
      # full gate once already. Pointed at a throwaway directory, the resolver can be
      # exercised without touching the project at all.
      SEARCH_ROOT="${HB_TEST_ROOT:-test}"
      MATCHES=$(find "$SEARCH_ROOT" -name "$GATE" -o -type d -name "$GATE" | sort)
      COUNT=$(printf '%s' "$MATCHES" | grep -c . || true)
      if [[ "$COUNT" -eq 0 ]]; then
        echo "no test file or directory named '$GATE' under ${HB_TEST_ROOT:-test}/" >&2
        echo "usage: $0 [fast|full|profile|<file.gd>|<directory>]" >&2
        exit 2
      elif [[ "$COUNT" -gt 1 ]]; then
        echo "'$GATE' is ambiguous — rename one of these:" >&2
        printf '%s\n' "$MATCHES" >&2
        exit 2
      fi
      TARGET="$MATCHES"
    fi
    echo "== targeted run: $TARGET =="
    ;;
esac

# 1. Lint gate — fast failure, no engine needed. `pip install gdtoolkit` to get
#    gdlint/gdformat. Project style overrides live in ./gdlintrc (max-returns
#    raised from the default 6 — this codebase's is_legal() validation gates
#    are deliberate early-return chains, not something to collapse for a
#    linter default; max-public-methods raised from 20 — a GUT test file's own
#    `test_*` functions are deliberately many small, focused cases, not
#    something to split apart just to satisfy a linter default).
#
#    taskblock-63 Pass A: **max-file-lines is 2500, and that number is the
#    project's rather than gdlint's.** The 1000 it replaced was the tool's own
#    default — inherited, never argued for — and a line count cannot tell code
#    from comments, so it penalised exactly the files that carry their rules in
#    doc comments, which is this project's standing convention. BR62.02 records
#    it biting three source files in one taskblock with the cost coming out of
#    documentation twice. Everything else gdlint does is unchanged.
#    `test/unit/test_lint_config.gd` asserts the 2500 directly, so this cannot
#    drift without someone saying why in a test — the mechanism taskblock-45
#    Pass E introduced, kept, with a number that was decided rather than
#    inherited. (That pass's own reason for the 1000 — the cap coming back down
#    being the objective proof `src/logic/ai/unit_ai.gd` was truly replaced after
#    eight bumps taken on its behalf — was delivered and cannot be delivered
#    twice; `test_retired_planner_sweep.gd` is what keeps the planner gone now.)
if [[ -n "$TARGET" ]]; then
  gdlint "$TARGET"
else
  gdlint src test
fi

# 2. Warm-up import so class_name scripts register (required on cold checkouts).
#    This step can exit non-zero on benign import warnings, so don't let it abort.
"$GODOT" --headless --path . --import --quit || true

# 3. Checkpoint parse guard (taskblock-41 Pass E). Visual checkpoints need a
#    real GPU frame, so they can never RUN here — but they can be PARSED, and
#    that is exactly what BR40.02 needed: a UnitView -> HitVolumeView rename
#    orphaned two scenario scripts for ~15 taskblocks because nothing re-ran
#    them. Deliberately NOT under `-d`: a parse error inside load() raises a
#    Debugger Break there and would hang the build instead of failing it. Runs
#    ahead of GUT so a broken scenario fails fast, before the debugger-enabled
#    step below could hit the same script.
#    Skipped for a targeted run: it guards checkpoint SCENARIOS, which have nothing
#    to do with whichever test file is under the cursor, and it is 0.8 s of a ~3.7 s
#    floor. The full and fast gates still pay it, which is where it earns its place.
if [[ -z "$TARGET" ]]; then
  "$GODOT" --headless --path . -s res://tools/checkpoints/parse_guard.gd
fi

# 4. Run the suite through `tools/run_suite.gd` (taskblock-48 Pass A2).
#
#    **Not `gut_cmdln.gd` any more, and the difference is the exit code.** Work
#    counts exist only in-process and only a runner that hosts `GutRunner` itself can
#    collect them, so there used to be two entry points into one suite — and only one
#    of them failed the build. They are collapsed; this one both counts and fails.
#
#    Artifacts (`SUITE-PROFILE.md`, `suite_profile.json`) are committed, so they are
#    rewritten only when asked for with `--write`. Counts print on every run either
#    way.
#
#    GODOT_DISABLE_LEAK_CHECKS avoids false failures from leak logs printed on exit.
if [[ -n "$TARGET" ]]; then
  SCOPE="--test=res://$TARGET"
  [[ -d "$TARGET" ]] && SCOPE="--dir=res://$TARGET"
else
  SCOPE="--dir=res://test"
fi

# **Only the full gate may write the artifacts, whatever WRITE_PROFILE says.**
#
# `SUITE-PROFILE.md` and `suite_profile.json` describe the WHOLE suite, so a run that
# saw part of it cannot honestly produce them. This is not hypothetical: exporting
# WRITE_PROFILE=1 leaks it into every subprocess, and `test_run_suite.gd` shells out
# to a targeted run — which promptly overwrote the committed profile with a single
# file's data, mid-run, while `test_suite_budget.gd` and `test_suite_tier.gd` were
# still reading it. The outer run rewrote it correctly at the end, so the damage was
# invisible in the final tree and showed up only as two unrelated tests failing.
#
# ## taskblock-65 close-out: **the full gate writes them by default.**
#
# The profile went eight blocks stale between taskblock-56 and taskblock-64, and every
# suite-cost conversation in between was partly guesswork. When it was finally
# regenerated it turned the fast gate red on three counts, none of them false — four
# files building bouts without being registered, and five work budgets that had been
# passing against numbers nobody had re-measured. **That is the recurring defect, and
# the instance is not the interesting part**: the artifacts were only ever written
# behind an opt-in flag, so keeping them current depended on somebody remembering, in
# exactly the situation where forgetting is invisible.
#
# So the full gate — the run you already have to make green before pushing — now
# produces them. `WRITE_PROFILE=1` is kept for the fast/targeted case only to print the
# refusal below, since a run that saw part of the suite cannot honestly describe it.
#
# ## taskblock-67 Pass C: **that run is now `profile`, and the writing moved with it**
#
# The bare gate shards, and a sharded run cannot honestly write per-file wall-clock — so
# the artifacts follow the single-process rung rather than the word "full". Nothing about
# the argument above changes; the run that carries it has a name now.
#
# **A red run still writes nothing** (`run_suite.gd::_on_end_run`). Its counts describe a
# suite that did not complete as intended, and committing those as the baseline
# everything is compared against is worse than having no fresh numbers.
#
# **Set HB_NO_WRITE_PROFILE=1 to opt out** — for a profile run you are doing to see
# whether something is red, where an artifact diff is noise you would only discard.
WRITE_FLAG=""
if [[ -z "$TARGET" && "$GATE" == "profile" ]]; then
  if [[ -z "${HB_NO_WRITE_PROFILE:-}" ]]; then
    WRITE_FLAG="--write"
  else
    echo "== HB_NO_WRITE_PROFILE set: leaving the committed artifacts alone =="
  fi
elif [[ -n "${WRITE_PROFILE:-}" ]]; then
  echo "== WRITE_PROFILE ignored: only ./run_tests.sh profile writes a whole-suite profile =="
fi

# **Nothing this run spawns may write the artifacts.** The suite contains tests that launch
# suites (`test_suite_run.gd`, `test_run_suite.gd`, `test_replay_wiring.gd` — 25 spawns
# between them by the tb65 counter). Every one of them passes a target today, so every one
# is a targeted run and already refuses — but "already refuses" is a property of their
# current arguments, not of the design, and one `start(&"full")` with no target would have a
# nested run rewriting the profile MID-RUN while `test_suite_budget.gd` and
# `test_suite_tier.gd` were reading it. That precise failure has happened once already, when
# exporting WRITE_PROFILE=1 leaked into a child.
#
# Exported AFTER this run's own WRITE_FLAG is decided, so it binds children and not us.
export HB_NO_WRITE_PROFILE=1

# 5. **The completion guard, and it is not belt-and-braces.**
#
#    The suite runs under `-d`, which GUT needs to notice unexpected engine errors. A
#    runtime script error therefore raises a Debugger Break, and a Debugger Break ENDS
#    THE RUN — `run_suite.gd` never reaches `_on_end_run`, never computes an exit code,
#    and the process exits 0. **A green gate that saw three quarters of the suite is
#    worse than a red one**, and this is not hypothetical: taskblock-57 Pass C3 moved
#    some fields, two test files still reached for them, and the full gate reported
#    success from a log with no totals in it at all.
#
#    A runner that has vanished cannot report its own absence, so the caller checks for
#    the summary line the runner prints last. Missing marker, failed build.
#
#    **The other shape is a hang, and it is deliberately not handled here.** `-d` opens
#    an interactive debugger on stdin; with a long queue of scripts behind it the break
#    is stepped past and the run truncates (the case above), but a break in the LAST
#    script sits at a `debug>` prompt waiting for input that never comes. A hang is
#    loud — it never returns — where a truncated green run is silent, so the silent one
#    is what needs a guard. Adding a timeout here would put a wall-clock number on a
#    suite whose runtime is the thing being measured.
SUITE_LOG="$(mktemp)"
trap 'rm -f "$SUITE_LOG"' EXIT
set +e
GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless -d \
  --display-driver headless --audio-driver Dummy \
  --path . \
  -s res://tools/run_suite.gd \
  -- "$SCOPE" $WRITE_FLAG 2>&1 | tee "$SUITE_LOG"
SUITE_STATUS=${PIPESTATUS[0]}
set -e

if ! grep -q -- "--- suite cost ---" "$SUITE_LOG"; then
  echo "" >&2
  echo "the suite did not finish — no '--- suite cost ---' summary was printed." >&2
  echo "a Debugger Break (a runtime script error under -d) ends the run before" >&2
  echo "run_suite.gd can compute an exit code, so the process would otherwise" >&2
  echo "report success having skipped everything after the error." >&2
  verdict 1 "one process"
  exit 1
fi

verdict "$SUITE_STATUS" "one process"
exit "$SUITE_STATUS"
