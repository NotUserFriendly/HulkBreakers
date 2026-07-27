# Taskblock 45 Report — AI v2, part two: the utility planner

**IN PROGRESS — nothing landed yet.** `taskblock45.md` is in the tree and is the authority on scope;
this file records what actually happens.

**The rolling-five window is NOT rolled yet.** `Report-Taskblock40.md` stays until this block
finishes; rolling it for an empty stub would trade a complete record for an incomplete one.

## Carried in from taskblock 44

- **The suite is slower and it is `test_plan_pacer.gd`'s fault, and the fix is already scheduled by
  the supervisor for later — do not fix it inside this block.** The numbers, so the scheduled work has
  them: the suite went 2223 tests / 282.1s (taskblock-43 baseline) → 2301 tests / **338.9s** now, and
  `test_plan_pacer.gd` alone accounts for **33.9s** of that — one file, 14 tests, ~12% of total
  runtime for 0.6% of the tests. The cause is three of its cases setting `chunk = 1`, so a single plan
  suspends once per candidate cell (~90 real frames) when the assertion only needs "more than one".
  Shrinking the board in its `_field()` and raising `chunk` keeps every claim intact.
- **The `SurrogateLadder.demote` warning volume is not a taskblock-44 regression** and was
  investigated rather than assumed: the warning has fired since taskblock-03 Pass A2, and
  `run_tests.sh` has not changed since taskblock-43. taskblock-44 only added tests that run real
  seeded bouts, so more combat resolves and the existing warning fires more often. It became audible,
  not newly wrong. Now filed as **`BR45.01`, `CC`-owned** at the supervisor's direction — the
  placeholder it flags (an ambiguous DAG demotion resolved by declaration order) is the thing wanting
  resolution, **not the warning**.

## Decisions made without asking

*(nothing yet)*

## Tests that failed, then were corrected

*(nothing yet)*

## `SUPERVISOR`-owned entries moved to `Pending`

*(nothing yet)*

## Open questions

*(nothing yet)*
