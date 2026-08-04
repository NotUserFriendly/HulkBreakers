# Taskblock 57 Report — the layout's foundations, and a handoff mid-block

**Passes A, B and C1 landed, in order, each committed on a green full gate. The block is
incomplete — C2 through H are unstarted — and this is a handoff report written for the next
session rather than a closing one.** Nothing visible has moved yet: no mode uses the new chrome, so
every surface still sits where taskblock-56 left it. What exists is the machinery the rest of the
block spends.

**Rewrite this opening when the block closes.** It describes three of eight passes.

## Pass timings

Recorded as each pass's full gate exited 0 and it committed — not when its code was written. Kept
in the gitignored `tb57-pass-times.md` as the block runs; copied here because that file is local
and this one is not.

| pass | completed | gate | commit |
|---|---|---|---|
| A — coordinate spaces, UI scale | 2026-08-04 14:18 CDT | 2910/2910 | `335045f` |
| B — action bar publishes slots | 2026-08-04 14:28 CDT | 2917/2917 | `d153579` |
| C1 — placement arithmetic | 2026-08-04 14:52 CDT | 2931/2931 | `dbc52d2` |

**About 34 minutes of wall clock for three passes**, against a full gate that costs ~7 minutes and
was run four times (C1 needed a second run after its own guard fired). So **the gate is roughly
four fifths of the elapsed time** — worth knowing before planning the remaining five passes, and
the reason the targeted rung exists.

## Decisions made without asking

**Pass C was split into C1 and C2.** The taskblock's Pass C is ten placements plus four behaviours,
which is larger than any other pass in the block. C1 is where every surface sits; C2 moves the
modules into those slots and adds the behaviours. The taskblock already splits its own passes
(A1/A2, G1/G2), so this follows its grain rather than inventing a structure — and it meant three
green commits instead of one long uncommitted stretch.

**`safe_rect` keeps its 16:9 guarantee and the crush became a separate factor.** A1's prose
("narrower ratios crush rather than clip") and A1's own stated test ("`safe_rect` is 16:9 inside any
screen ratio and never exceeds it") cannot both be true of one rect. The alternative was to let
`safe_rect` fill on narrow screens and drop the 16:9 guarantee, which would have failed the test the
taskblock itself wrote. Reversible: one function changes if the rect should fill.

**The debug-menu budge shifts by the measured overlap rather than a constant.** The obvious reading
of *"budges left if Inspect crowds it"* is a fixed distance, and that is what I wrote first.
Measured against the table's own fractions it is wrong at both ends — see the open questions below.
The alternative was to keep a constant and pick a bigger number, which would have been a guess
sized against nothing. This stays a one-off: one function, one surface, one reason.

**The action bar and its four satellites are not collapsible.** A2's rule is that everything pinned
to a side is collapsible or off by default. I read that as being about surfaces that *crowd* — the
bar is centred at the bottom at half width, and a control surface you can switch off is a game you
cannot play. The alternative reading (every edge-pinned slot, no exceptions) is one line in
`ModuleSlots.SLOT_EDGES` if the supervisor prefers it.

**No module declares `preferred_slot()` yet.** Declaring one in Pass B would have moved the
side-pinned set and forced a collapsibility call per module, incidentally and one at a time. Those
calls want the whole placement table in view, so they belong in C2.

**`taskblock57.md` was committed.** `taskblock54.md` and `taskblock56.md` are tracked; this one was
not. Matching the precedent keeps the spec in the tree while the block runs.

## Tests that failed, then were corrected

**Two, both of them guards I had written earlier in the same block firing exactly as intended.**
Neither was a defect in shipped behaviour.

1. **GUT called Pass A's side-pinned sweep *risky — did not assert*.** The right verdict: no module
   declares a slot until C2, so iterating `ModuleCatalog` ranged over an empty set and reported
   green. That is the "passes while proving nothing" shape `docs/TEST-AUDIT.md` keeps finding, and
   it was caught by the runner rather than by me. It now also asserts the side-pinned set equals a
   pinned `EXPECTED_SIDE_PINNED` — empty today, with teeth immediately, and **C2 must update it
   deliberately.**
2. **Pass A's escaping guard failed when C1 added the escaping slots.** It was written as *"nothing
   escapes yet — the three arrive in Pass C"*, so C1 adding them is the ratchet working rather than
   a regression. Rewritten to pin the escaping set at exactly `inspect_panel`, `inspect_viewer` and
   `perf_monitor`, so a fourth has to be argued for in the commit that adds it.

**Also worth recording, because it changed the design rather than a test.** Writing the budge test I
asserted that Inspect crowds the debug menu, and it does not — that failure is what produced the
measurement in the open questions below. **The test was wrong and the code was right**, which is the
opposite of the usual direction and the reason the constant went away.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** No pass so far touched an entry in `docs/BUGS.md`. `BR56.01` remains `Active` and
untouched, per the standing do-not-fix instruction — NEXT 3 deletes the subsystem it lives in.

## Open questions

**Should budging exist at all?** With the table's fractions, the debug menu and Inspect **abut
exactly at 1x** — arithmetic, not luck: the menu ends at `1/2 + 1/8 = 5/8` of the safe width and
Inspect begins at `1 - (2/3)(9/16) = 5/8`.

| UI scale | debug menu | Inspect starts | overlap |
|---|---|---|---|
| 1.0 | 720 – 1200 | 1200 | **0** |
| 1.5 | 600 – 1320 | 840 | 480 |
| 2.0 | 480 – 1440 | 480 | 960 |

So budging only fires once UI scale moves, and scale is not settable until the options menu exists
— it is currently correct, tested, and unreachable in normal play. **The evidence points at
deleting it** and revisiting when the tuning pass changes those fractions, since a one-off that
cannot fire is a one-off nobody will remember the reason for. It is left in because it is
specified, and removing a specified feature is the supervisor's call.

**The Inspect Viewer split is a refactor, not a placement.** Pass C's table treats it as a position,
but the 3D view lives inside `inspect_panel.gd` as `_build_bot_viewer`, and **that file is at 992
lines against the 1000-line limit.** Extracting it would relieve that pressure and is probably worth
doing on its own terms — but it is not the re-slotting the table implies, and C2 should not absorb
it silently. **A supervisor call: fold it into C2, or give it its own pass?**

**`EXPECTED_SIDE_PINNED` is a deliberate tripwire.** It is empty and **will** fail the moment C2
declares a module's slot. That is its job; the next session should update it with the
collapsibility calls made deliberately rather than treating the failure as noise.

**The rolling-five report rotation is deferred.** CLAUDE.md's rule deletes
`Report-Taskblock52.md` in the same commit that writes this file. **It has not been deleted**,
because the rule's trigger is a finished taskblock and this one is open — deleting history early is
the harder thing to undo. The rotation should happen in the commit that closes taskblock 57.
