#!/usr/bin/env python3
"""tb66 Pass F — one verdict from N shard logs.

Reads every shard log named on the command line and prints a single aggregated report:
pass/fail, summed counters with duplication subtracted, and every failure with its file
and message.

Why Python rather than GDScript: this runs *after* the shards, outside any engine
process, and starting a Godot instance to add integers would add a second of floor to
every gate for nothing. It reads only what the shards printed.

## The three properties that matter, and they are properties of this file

**Ordering is stable.** Shards finish in whatever order the scheduler gives them, so
everything here is keyed and sorted by shard index rather than by arrival. A gate whose
output reorders between runs is a gate nobody can diff, which makes a real regression
invisible in the noise of a reordered report.

**A shard that produced no summary is a failure, not a missing section.** That is the
same guard `run_tests.sh` already carries for the unsharded path, and it is the easy bug
to ship here: a crashed shard writes a log with no cost line, and a merger that only sums
what it finds reports green. Silent partial success is the worst outcome available.

**Duplication is subtracted, not ignored.** `maps` and `floods` are gated counters and
every shard has its own `MapCorpus._cache`; see `ShardMerge` for why the fills are keyed
rather than counted.

## tb67 Pass A: `--totals-json=<path>` hands the controlled totals to the budget

This file computes the totals a drift guard needs and **does not judge them**. The judging
lives in `SuiteBudget.violations()`, in GDScript, and `tools/check_budget.gd` runs it over
what is written here. Re-implementing the budget rule in Python was the other shape and it
was rejected: `HEADROOM`, `BASELINE`, `GATED` and the `sampled_turns` subtraction are one
rule with a long argued history, and a second copy of it drifts silently in the direction
that matters — a stale Python baseline passing a run GDScript would have failed.

The artifact is written in `violations()`'s own input shape, `{"totals": ..., "files": []}`,
so nothing has to translate between them. **`files` is empty on purpose and it is not an
oversight**: per-file `usec` is untrustworthy under eight competing processes, so a sharded
run has no honest per-file half to offer. `check_budget.gd` says so where it prints.
"""

import json
import re
import sys

COUNTERS = [
    "bouts", "turns", "plans", "candidates", "shot_planes",
    "floods", "ui_builds", "escaped", "maps", "spawns", "sampled_turns",
    # tb67 Pass A: the draw's own floods and maps, so `SuiteBudget` can subtract them from a
    # sharded gate's totals exactly as it does for an unsharded profile. They sum across shards
    # like any other counter — only one shard draws, so only one shard contributes.
    "sampled_floods", "sampled_maps",
]
COST_RE = re.compile(
    r"(\d+) script\(s\), (\d+) test\(s\), (\d+) failure\(s\), ([\d.]+) s"
)
FILLS_RE = re.compile(r"--- corpus fills --- (\{.*\})")
# GUT prints a failing assertion's location on the line above its message.
FAIL_RE = re.compile(r"\[Failed\]:?\s*(.*)")
# The corpus draw is the gate's most useful single number and it lives in one shard's log.
# Surfacing it here is the difference between a merged report and a lossy one.
DRAW_RE = re.compile(r"(seeds to first completion: .*)")


def read_shard(index, path):
    """One shard's contribution, or a record saying it never finished."""
    try:
        text = open(path, errors="replace").read()
    except OSError as exc:
        return {"index": index, "path": path, "ok": False,
                "why": "log unreadable: %s" % exc}

    cost = COST_RE.search(text)
    if not cost:
        # No summary line means the runner never reached the end — a Debugger Break, a
        # segfault, or a kill. Never treat this as zero work.
        return {"index": index, "path": path, "ok": False,
                "why": "no '--- suite cost ---' summary; the shard did not finish"}

    counters = {}
    marker = text.split("--- suite cost ---")
    if len(marker) > 1:
        body = marker[1].splitlines()
        line = body[2] if len(body) > 2 else ""
        for key in COUNTERS:
            found = re.search(r"\b%s (\d+)" % key, line)
            counters[key] = int(found.group(1)) if found else 0

    draw = DRAW_RE.search(text)
    fills = FILLS_RE.search(text)
    failures = [m.group(1).strip() for m in FAIL_RE.finditer(text)]

    return {
        "index": index, "path": path, "ok": True,
        "scripts": int(cost.group(1)), "tests": int(cost.group(2)),
        "failures": int(cost.group(3)), "seconds": float(cost.group(4)),
        "counters": counters,
        "fills": json.loads(fills.group(1)) if fills else {},
        "messages": failures,
        "draw": draw.group(1) if draw else "",
    }


def duplication(all_fills):
    """Everything past the first fill of each key — see ShardMerge.duplication."""
    seen, dup = set(), {"maps": 0, "floods": 0}
    for fills in all_fills:
        for key, cost in fills.items():
            if key in seen:
                dup["maps"] += int(cost.get("maps", 0))
                dup["floods"] += int(cost.get("floods", 0))
            else:
                seen.add(key)
    return dup, len(seen)


def write_totals(path, controlled):
    """The controlled totals in `SuiteBudget.violations()`'s input shape.

    **A temp file for the caller, never a committed artifact.** `suite_profile.json` is the
    baseline everything is compared against and a run that saw part of the suite must not
    write it; this is a handoff between two steps of one gate, and `run_tests.sh` deletes it
    with the shard logs.
    """
    with open(path, "w") as handle:
        json.dump({"totals": controlled, "files": []}, handle, indent=2, sort_keys=True)


def main(argv):
    paths, totals_path = [], ""
    for arg in argv:
        if arg.startswith("--totals-json="):
            totals_path = arg.split("=", 1)[1]
        else:
            paths.append(arg)

    shards = [read_shard(i, p) for i, p in enumerate(paths)]
    shards.sort(key=lambda s: s["index"])  # stable output, never arrival order

    broken = [s for s in shards if not s["ok"]]
    good = [s for s in shards if s["ok"]]

    totals = {k: sum(s["counters"].get(k, 0) for s in good) for k in COUNTERS}
    dup, distinct = duplication([s["fills"] for s in good])
    controlled = dict(totals)
    for key in ("maps", "floods"):
        controlled[key] = totals[key] - dup[key]

    # **Written whatever the verdict below turns out to be, and the caller decides.** The
    # numbers are what this run cost either way; whether it is worth judging the work of a
    # suite that did not finish is `run_tests.sh`'s call, and it declines.
    if totals_path:
        write_totals(totals_path, controlled)

    print("--- sharded gate ---")
    for s in shards:
        if s["ok"]:
            print("  shard %d: %3d script(s), %4d test(s), %d failure(s), %6.1f s"
                  % (s["index"], s["scripts"], s["tests"], s["failures"], s["seconds"]))
        else:
            print("  shard %d: DID NOT FINISH — %s" % (s["index"], s["why"]))

    failures = sum(s["failures"] for s in good)
    print("\n%d shard(s), %d script(s), %d test(s), %d failure(s)"
          % (len(shards), sum(s["scripts"] for s in good),
             sum(s["tests"] for s in good), failures))
    print("  " + "  ".join("%s %d" % (k, controlled[k]) for k in COUNTERS))
    if dup["maps"] or dup["floods"]:
        print("  duplicated corpus fills subtracted: maps %d, floods %d "
              "(%d distinct keys) — this is the shard map's affinity score"
              % (dup["maps"], dup["floods"], distinct))

    drawn = [s for s in good if s["draw"]]
    for s in drawn:
        print("  corpus draw (shard %d): %s" % (s["index"], s["draw"]))
    if len(drawn) > 1:
        print("  MORE THAN ONE SHARD DREW. Co-location is broken — every reader of "
              "BoutCorpus must be in one shard, or the gate plays several samples and "
              "the report above describes none of them.")

    if failures:
        print("\n--- failures ---")
        for s in good:
            for message in s["messages"]:
                print("  shard %d: %s" % (s["index"], message))

    if len(drawn) > 1:
        return 1
    if broken:
        print("\n%d shard(s) did not finish. A gate that sums only the shards that "
              "survived is a gate that reports green on a crash." % len(broken))
        return 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
