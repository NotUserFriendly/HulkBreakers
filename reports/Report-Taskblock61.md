# Taskblock 61 Report — the hunt

**All six passes landed.** A and B (shot geometry, membership), C (wall cutout), D (input
affordance), E (the cheap remainder), and F is this report. Full gate green.

**Thirteen entries moved.** Eight closed on the supervisor's own instruction earlier in the block —
`BR30.02`, `BR30.04`, `BR32.04`, `BR32.05`, `BR32.07`, `BR32.08` as `Resolved`, `BR33.01` and
`BR34.03` as `Obsolete`. **Nine sit at `Pending`** awaiting the supervisor's eyes: `BR51.01`,
`BR52.07`, `BR52.10` and `BR35.02` from the earlier passes, and `BR51.19`, `BR51.21`, `BR34.04`,
`BR51.16` and `BR57.02` from pass E. **Six new entries were filed** (`BR61.01`–`BR61.06`). The
ledger stood at 43 open when pass C began and stands at **39** — 27 `Active`, 9 `Pending`, 3
`Suspected`.

**One entry is named as not started rather than quietly carried: `BR27.15`.** It is unblocked and
specified; see Open Questions.

**The block's lesson held for five passes and then inverted, which is the more interesting result.**
Passes A through D repeated the same failure four times: CC measured a component headlessly,
inferred the whole system's behaviour, and reported a conclusion the supervisor's next in-game
action disproved. Pass C did it with a cost probe that measured a one-box fixture where a real shell
is 48 boxes, and the supervisor's session came back at **13 fps**.

**Pass E did not repeat that failure, and the reason is method rather than luck: every one of its
six entries was measured before it was touched.** `BR51.19` was counted (12 units on 8 cells) before
the wrap was found. `BR51.16` was counted (15 rows to 2) before a line changed, which is what its
own entry demanded. `BR34.04` and `BR57.02` were both measured by disabling the fix and reading the
real nodes back — 2.139 units past the target, and a cull-mask overlap of exactly zero.
**Instrumentation before repair was already the block's stated finding; pass E is the first pass
that applied it to every entry rather than to the one that had defeated three previous attempts.**

**It repeated a different failure instead, and the fast gate hid it.** `BR51.16` shipped two changes:
the reported fix, and a second one CC decided to make while measuring — clearing the panel on a new
bout, which nobody had asked for. It also introduced a readability regression, opening the log with
board-build noise instead of the `bout_start` header. **Both were caught by the pre-push full gate
and neither could have been caught by the fast one**, because the test that holds those expectations
builds bouts and the fast gate skips every such file. The pass had been green on the fast gate three
times while carrying them. One change was reverted, one was corrected.

**Three of pass E's six entries turned out to have something wrong in their own recorded diagnosis**,
which is worth more than the fixes: `BR51.21`'s corrected fix shape pointed at the wrong module and
made a false claim about empty event lists, `BR51.16`'s three named suspects were all wrong, and
`BR57.02`'s suspects table had checked the wrong one of two similarly-named masks. In each case the
entry was close enough to be useful and wrong in a way only running it would show.

## Decisions made without asking

**`BR52.10`'s fix uses no new input and no new weight.** `shoot.tres` already carries
`line_of_fire` as a consideration and `UtilityScorer`'s product model preserves a zero at every
`n`, so answering `false` vetoes shooting from that cell outright — which is exactly the
`held: ally_in_line` refusal the retired branch planner performed. Inventing a "friendly fire risk"
weight would have been a balance number nobody chose, expressing something the existing veto
already says.

**`BR52.10` reads through `WorldView.units_visible_to`, not `_state.units`.** That is the seam the
class exists to hold, and it costs nothing: *"allies are always known: they are on the radio"*, so
a squadmate is in the list at every intelligence tier including `MINDLESS`.

**Pass B's fix was implemented, failed, and was reverted rather than salvaged.** Making
`UnitGeometry` defer to `BodyProjector.projects` resurrected every destroyed wall as a sight
blocker, because `Part.failure_mode` defaults to `MANGLE` and `wall.tres` authors none. **The
taskblock told me not to patch that locally and I did anyway after flagging the risk in the same
message.** That was the wrong call; the reverted attempt is recorded because the failure is the
finding.

**`BR51.01`'s camera-lean fix was implemented and reverted.** Removing the lean was over-reading
*"why is a flourish affecting aim?"* as *"delete the flourish"*. The supervisor's correction —
*"disconnecting the flourish and the actual result is what we're trying for"* — arrived after the
in-game shot showed no improvement.

**`ShotPlane` misses return `null` with no fallback**, on the supervisor's *"misses loud"*. My first
version returned `Vector2.ZERO` — correct units, still a fabricated aim point, and a
*plausible-looking* one, which is worse than an absurd one because nobody notices it. The
constraint that a null must **not** become a refusal to fire is the supervisor's and is written
into the function's own header so a later reader does not "improve" it into one.

**`depth_of`'s `0.0` miss was made loud without being asked.** It is the same class as the cell
address — zero depth reads as *at the muzzle* — but the instruction was given about `centre`, and
extending it was my call.

**Pass A's `BR52.07` was marked `Pending` on the grounds that its mechanism was unreachable.**
That was wrong: `_aim_point_world` still builds the ray's target from a plane-space lateral offset,
so the artifact survived the resolver migration in the one place I did not check. Corrected in the
entry.


### Passes C and D

**The `BR32.05` gate is the supervisor's shape, not CC's, and the difference was load-bearing.** CC
proposed a per-wall pre-pass (compute which wall cells genuinely occlude, feed them to the shader).
The supervisor inverted it to a per-unit gate — if no wall is between camera and unit, do not feed
that unit at all — which needed **no shader change whatsoever**. CC's version would have been a
larger change to a subsystem already "fixed" three times.

**Cover counted as occluding, deliberately, and that was wrong.** CC wrote down the reasoning at the
time — *"the safe direction is keeping a cutout"* — and the supervisor overruled it: a cutout kept
alive over geometry that can never be cut is a hole with no visible cause. The fix introduced the
`&"cutout"` tag that should always have existed, replacing a hardcoded `part.id == &"wall"`.

**`BR32.04` was fixed with a different mechanism than its own entry recorded.** tb35 proposed a
dictionary of display positions written per tween tick and named the override lifecycle as why it
went unattempted for three blocks. There is no lifecycle: `ResolutionPlayer` already writes the real
`HitVolumeView` transform every tick and leaves it at identity when idle. CC used the node instead
of a cache, which is what `docs/00` asks for and what the entry was reaching toward.

**`BR32.07`'s legality gate was removed rather than tuned.** The supervisor's call. Worth recording
that the gate *contradicted the resolver it guarded*: `docs/02` marches a real ray that meets what
is in the way and spends damage penetrating it, so a cell-to-cell sight line vetoing the shot
forbade the exact outcome the chain exists to produce.

**Two CC changes were reverted in the same block they landed.** Pass B's membership fix (recorded in
the first draft), and Pass D4's queue-label generalisation — the latter after the supervisor asked
CC to check what actually called it. Nothing in `src/` calls `queue_entries()`; the only surviving
reader of `short_describe()` is the combat log, so the "fix" stripped detail from log lines for a UI
row that no longer exists.

**`BR35.02` was instrumented instead of given a repro route.** CC could not show the fallback path
is reachable — the primary pick tests units, blockers, field items *and* floors, and the only things
the fallback can open are a blocker or a floor tile. Rather than stage a route that might not fire,
the path now logs whenever it runs.

### Pass E

**`BR60.01` was measured and deliberately not fixed, and that is the biggest unilateral call in the
pass.** The entry is `CC`-owned, so closing it was mine to do. The detection half landed
(`MapNavigability.unreachable_cells`, plus a sweep at the 40x30 board the game actually plays, which
reproduces twelve regions over eight of fifty seeds). **The repair did not**, because the three
available repairs — ladder in, flatten, stair in — differ in what generated maps *look like*, not in
correctness. Flattening erases a 232-cell shelf on seed 2; the ladder is the cheapest and reuses
`guarantee_navigability`'s existing mechanism, but taskblock-61's own one-line summary of this entry
reads *"a large raised region reachable only by ladder"*, so it may be the thing being complained
about. All three are costed in `PLAN.md`. **The alternative was to pick the ladder and close the
entry**, which would have been a design decision about map character taken unasked.

**`BR60.01`'s anchor theory was reported as a correlate rather than promoted to a cause.** The
entry predicted the defect correlates with `rooms[0]` being raised. It does — seven of eight
defective boards, against a base rate of 19 in 50 — but twelve raised-anchor boards are clean and
one defective board has a flat anchor. **It would have been easy to call that confirmed and
re-anchor the repair**; the table is recorded in the test instead.

**`BR51.21`'s playback was put on `DebugPanelModule`, not on `PlaybackModule` where the entry
pointed.** The entry names `PlaybackModule._on_verb_applied` as the dead handler, which reads as an
instruction. **It is wrong**: `playback` is not in `PLAYER_MODULES`, so a fix there animates
injections while spectating and silently not while playing — the same one-path shape the entry
exists about. A test asserts the mode difference so the "obvious" placement cannot be restored by a
later reader.

**`InjectionEvents` was introduced rather than filtering inline.** The entry's claim that an
event-emitting verb self-selects is false — `_guard` puts `command`/`command_outcome`/`inject` on
every verb, so a raw capture is never empty and `play([])` is not the no-op it looks like. The
alternative was to filter to the kinds `ResolutionPlayer` animates, which would have duplicated that
class's knowledge in a second place; stripping the injector's own bookkeeping keeps the knowledge
where it is authored.

**`SNIPER_UP_OFFSET` reuses `ATTACK_UP_OFFSET`'s value under a new name.** The supervisor's spec
says the sniper camera sits *above* the shooter-target line without saying how far. Rather than
invent a number, the fix borrows the lift the over-the-shoulder framing already uses and names it
separately so the two can be tuned apart. **It is the only chosen number in that fix**, and it is
flagged as the one line to move.

**`CombatLog.MAX_HISTORY` is 2000, and history retention is new behaviour in a logic class.** The
alternative to retaining anything was to keep the panel alive across overlay swaps, which is not
possible — modules are freed on teardown. Making replay opt-in (`LogSink.wants_replay`, default
false) is what keeps `FileSink` from double-writing and a one-turn `MemorySink` from swallowing a
bout.

**`BR51.16`'s second half was implemented, shipped through three fast gates, and then reverted.**
While measuring the reported emptying, CC noticed the opposite defect — a new bout loading under a
live overlay carries the previous bout's rows forward — and fixed that too by clearing the fold on
attach. **It was an overreach on two counts:** nobody reported it, and
`test_battle_scene.gd::test_a_second_bout_logs_its_own_seed_not_the_first_bouts` pins the
accumulation *on purpose*, because several bouts run under one scene and the panel accumulates them
the way `FileSink` appends them to one file. **The full gate caught it and the fast gate could not**,
because that file builds bouts. Reverted, and the behaviour is now pinned from the overlay side too
so the next reader does not repeat it.

**`BR57.02` was fixed by widening the light's `layers`, not the camera's `cull_mask`.** Widening the
mask is the shorter change and would have undone tb22 G2 by letting every other unit and blocker
draw through the preview. A test pins layer 1 as still excluded.

**Three files hit the 1000-line lint cap in pass E alone** (`bout_injector.gd` at 998,
`test_inspect_panel.gd` at 927, after `board_view.gd` earlier in the block). **Each was paid by
extracting a separable concern rather than by shortening comments** — the trade this block already
made once and recorded as the worst available. That produced `src/debug/injection_events.gd` and
`test/unit/view/test_inspect_viewer_lighting.gd`.


## Tests that failed, then were corrected

**Six failing before correction**, and the two most useful were tests that had been passing while
asserting nothing real.

1. **`test_one_aim_path.gd::test_the_off_axis_angle_grows_as_range_shrinks` — passing on
   floating-point noise.** It asserted `readings[0] > readings[1]` to confirm `BR54.01`'s range
   effect. With the torso as the aim point both readings are **3.7e-9 cells** — numerically zero —
   and `atan2(3.7e-9, 1.93)` is fractionally larger than `atan2(3.7e-9, 7.93)`, so a strict `>` was
   satisfied by nothing at all. Now asserts an absolute bound. **Found only because its sibling
   went red and it was read while fixing that.**

2. **`test_taskblock21_gun_data.gd` — two fixtures asserting against an impossible board.** Both
   built their target as `Shell.new(Part.new())`: a body with **no `volume`**, which projects no
   regions. They passed only because the old `center_of` invented a point for a miss. The loud miss
   caught them within minutes of existing. Fixed by giving the target real geometry, not by
   silencing the error.

3. **Three tests pinning `BR51.01` itself** — `center_of` falling back to the target's cell, and
   `depth_of`/`depth_of_part` falling back to `0.0`. Reversed with the old assertions quoted. The
   `depth_of` (Unit) twin was missed on the first pass and caught by a targeted run.

4. **`test_los.gd::test_destroying_a_wall_with_a_real_shot_clears_los_through_it`** — went red on
   Pass B's attempted membership fix, with a bout-determinism golden failing downstream. That
   failure is what disproved the fix, and the fix was reverted rather than the test adjusted.


### Passes C and D — five more, and three were CC's own tests asserting the wrong thing

1. **`test_cutout_gate_cost_probe.gd` — measuring a fixture that measured nothing.** It reported
   41 usec per unit against a body of **one `Box`**; a real assembled shell is **48**, and
   `placements_aabb` costs eight corner transforms per box. It passed throughout and cleared a
   change that took the supervisor's session to 13 fps. Replaced with a real assembled shell, and a
   second end-to-end probe added that measures the whole per-frame call with nothing stubbed.

2. **`test_board_view.gd`'s ghost-path count — the arithmetic encoded a double-draw.** It asserted
   8 overlay children; queued legs are contiguous, so one cell was receiving two markers, which is
   what hid the hollow waypoint box under a filled square. Corrected to 7 with the reasoning spelled
   out — the test had been quietly documenting the bug.

3. **CC's own aim test compared across the preview-clone boundary.** It asserted the reading against
   the pre-clone unit and failed: `aim_state()` builds its plane from `queue.preview(state)`, so
   `region.body` is the clone. That is `BR51.01`'s identity trap, walked into again — and the
   production path was correct; only the test was wrong.

4. **CC's own waypoint test compared float32 against float64.** It filtered meshes on a `0.02`
   thickness and read zero every time, because `BoxMesh.size` stores float32. It would have passed
   trivially for the wrong reason had the count been zero-tolerant.

5. **`test_attack_action.gd::test_is_legal_false_without_line_of_sight`** — reversed rather than
   deleted, with its old expectation named, when obstructed shots became legal.

### Pass E — five, and the last two were only reachable from the full gate

1. **`test_log_fold.gd::test_folding_never_changes_what_other_sinks_on_the_same_log_receive` —
   comparing absolute totals when it meant "the same events".** It summed the fold's event count and
   asserted equality with a `MemorySink`'s. That held only while both sinks necessarily started
   empty, which `BR51.16`'s replay ended: `HierarchicalUiSink` now arrives holding everything
   `CombatState.new` logged while building the board, and the `MemorySink` does not replay.
   **Corrected to measure the delta across the action**, which states the test's actual claim more
   exactly than the totals ever did. Went red on the fix and was not adjusted away.

2. **`test_camera_orbit_state.gd::test_sniper_framing_keeps_the_current_yaw_and_pitch` — a
   deliberate reversal, with the old expectation quoted in place.** It asserted that the solve keeps
   the rig's current angle, on reasoning that is *still correct* — with no second body to frame, any
   angle centres the target. It was right about the mechanism and wrong about what the supervisor
   wanted, which is the entry's whole content. Renamed to
   `test_sniper_framing_solves_a_new_angle_rather_than_keeping_the_current_one`.

3. **`test_debug_control_panel.gd` — CC's own new test passed for the wrong reason and was
   rewritten.** The first draft asserted "a verb that emits events hands them over" against a bare
   `Part.new()` unit, and it passed while carrying only `command`, `inject`, `command_outcome` — the
   injector's own bookkeeping, and nothing the verb caused. **The sibling test asserting the empty
   case is what exposed it**, by failing: it proved no verb ever yields an empty list, which meant
   the first test's non-empty list proved nothing. Rebuilt around a real detonating goo barrel,
   which is the entry's own reproduction, and it now carries exactly one `detonation`.

4. **`test_battle_scene.gd::test_new_battle_logs_the_seed_at_bout_start_to_both_sinks` — a real
   readability regression, caught only by the full gate.** `BR51.16`'s replay handed a
   freshly-mounted panel events emitted *before any panel existed*: `CombatState.new` logs its own
   construction and `load_battle` attaches the sink afterwards, deliberately. So the panel opened
   with `2× unit_assembled` instead of the `bout_start` header. **The test was right and the change
   was wrong** — fixed with `CombatLog._replay_floor`, one integer set by the first replay-wanting
   sink, rather than by relaxing the assertion.

5. **`test_battle_scene.gd::test_a_second_bout_logs_its_own_seed_not_the_first_bouts` — the test
   that caught the overreach.** It counted `bout_start` headers in the panel and got 1 where it
   wanted 2, then crashed indexing past the end. CC's fold reset had made a new bout clear the
   panel; this test pins the accumulation deliberately, with its reasoning recorded. **Reverted
   rather than adjusted**, and CC's own test asserting the opposite was replaced by one asserting
   what was kept.

**Three fixes were additionally confirmed red by disabling them** rather than trusting that a new
test tests something — `BR34.04`'s three rig tests, `BR51.16`'s overlay test, and `BR57.02`'s
cull-mask test. That is where the 2.139-units-past-the-target and `6 & 1 == 0` numbers come from.

**Pass E was green on the fast gate three separate times while carrying both of those.** The fast
gate skips every bout-building file, and `test_battle_scene.gd` is one — so the pass's most
invasive change (retained history in a core logic class) was unverified against the path that
actually loads bouts until the pre-push gate. **That is the fast gate working as designed and worth
stating plainly rather than filed as a near-miss.**


## `SUPERVISOR`-owned entries moved to `Pending`

**Passes A and B (still awaiting a look):**

- **`BR52.10`** — AI no longer fires through its own squadmate. **To see it:** watch a bout with
  three units a side; units lined up behind one another should hold or reposition rather than firing
  through the one in front. Impacts landing on a squadmate fell from **6.71% to 2.25%**; the residual
  is expected, since the check is cell-granular and an ally can move into a line after the decision.
- **`BR52.07`** — the diagnosed mechanism is unreachable and **CC did not fix this**. **To see it:**
  fire a long burst at a target 6+ cells away and read the impact lines; a hit perpendicular to the
  muzzle-to-target axis at that range is the defect returning.
- **`BR51.01`** — root cause found and both halves fixed. **To see it:** fire at a pillar or wall
  from several facings; `weapon_used` logs `aim` and `offset`, and a healthy shot has an `offset`
  under a cell in both components. **A `ShotPlane: no region for ...` line means it regressed.**

**Pass D (new):**

- **`BR35.02`** — tile-inspect can no longer open a cell hidden behind geometry. **The supervisor
  has already tried and could not reproduce the original defect**, which is expected: CC cannot show
  the fallback path is reachable. **Standing instruction from the owner: one more failed
  reproduction closes it `Obsolete`**, not `Resolved` — nobody has ever seen the symptom. The
  `inspect_fallback` log line is the evidence; a session with no such line is that second failure.

**Pass E (new) — five, and every one has a route:**

- **`BR51.19`** — squads larger than four no longer spawn stacked. **To see it:** start a bout with
  **six or more units a side** and look at turn 0. Every unit on its own cell, the ones past the
  fourth arranged outward from the spawn zone. The old symptom was units beginning stacked and then
  moving apart to plausible positions; it should be gone entirely, not rarer. **Measured 12 units on
  8 cells before, 12 on 12 after.**
- **`BR51.21`** — a debug injection animates. **To see it:** set a goo barrel's HP to 0 with Set
  Part HP and press Apply. **The explosion sphere `BR35.08` built should play** where the board
  previously just snapped; a forced move should slide rather than teleport. **Check the other half
  too**: a verb with no visible effect (a readout toggle, `force_current_unit`) must still feel
  instant, with no banner flash and no pause. **This also unblocks `BR35.08`'s own confirmation**,
  which could not be judged on the debug path until an injection animated.
- **`BR34.04`** — the sniper camera sits on the shot line. **To see it:** aim at something more than
  5 cells away. The camera should settle **behind and slightly above your own shooter, looking down
  the shot**. Measured: it was previously **2.139 units past the target**, framing it from the far
  side. If it still reads wrong, `CameraOrbitState.SNIPER_UP_OFFSET` is the one number to move.
- **`BR51.16`** — the in-game log survives an overlay swap. **To see it:** play until the log has
  content, then press **Assume Control** — it should keep everything instead of blanking. Then press
  **New Battle** — it should start clean rather than carrying the last bout's lines. **Both
  directions are the check**; only the first was reported, and the second was a real defect found
  while measuring it.
- **`BR57.02`** — the inspect viewer's units are lit. **To see it:** open Inspect on a **live unit
  on the board** (not cover, not a loose part — those never had it). Faces should show real
  directional shading from the board's light angle instead of one flat tone. **Also glance at the
  board itself**: it must look unchanged, since the light gained render layers and not energy.
  **CC cannot see pixels** — the measured claim is only that the light is now in that camera's
  render set at all, where the overlap was previously exactly zero.

**Closed during the block on the supervisor's own instruction:** `BR30.02`, **`BR30.04`**,
`BR32.04`, `BR32.05`, `BR32.07`, `BR32.08` (`Resolved`), and `BR33.01`, `BR34.03` (`Obsolete` — the
feature or the UI it described is gone, so there was no fix anyone could confirm). **Eight, not the
seven this line listed before pass F** — `BR30.04` was closed in the same commit as `BR32.07` and
was left off; all eight are verifiable in `docs/BUGS-ARCHIVE.md`.

## Open questions

**1. `BR27.15` is the one entry named as not started, and it is still unblocked.** The
supervisor's spec is recorded: step-out is an automatic action, so the dartboard opens on the
**first** click; the default is the **closer shot** (a re-order of `sort_by_safety`, not just a UI
change); the wheel re-picks among the candidates — usually two — while already aiming. `BR33.01`'s
real payoff was freeing the wheel for it: the binding tested `aiming_at` first, so step-out cycling
was unreachable the moment aim opened, and neither entry named that coupling. **Not started because
it is a core flow change with four tests pinning the current two-step behaviour**, and it is the
only Pass D item outstanding while Pass E's six were all deliverable.

**2. `BR61.01` — CC's test runs write the supervisor's live combat log.** Unchanged and still
`Active`. It cost a wrong conclusion in pass A (a "working pistol" the supervisor never fired) and
every log read in passes C and D had to begin by checking the file's timestamp against CC's own last
gate run. **This is now load-bearing**: three separate defects this block were settled by reading
that log.

**3. `BR60.02`'s mangle refit is specified, deferred, and has grown a second symptom.** `BR61.06`
records a destroyed forklift emitting `part_destroyed` **and** `part_mangled` at one instant —
almost certainly `Part.failure_mode` defaulting to `MANGLE` with no cover or terrain part authoring
one, the same default Pass B caught resurrecting destroyed walls. Harmless today only by coincidence
of which gate reads `hp > 0` and which reads `is_mangled`.

**4. The framerate ledger has a new, larger entry than the one CC caused.** `BR61.04`: the cutout
feed rebuilds every body's box tree **every frame** purely because the camera moved — **3 114 usec
for a 16-unit roster, 45% of a 144 fps frame**, and pre-existing. CC's own regression on top of it
was 2 260 usec and is fixed. The fix for the remainder wants `BR32.04`'s rendered-position work,
which now exists.

**5. `board_view.gd` has hit the 1000-line lint cap three times in this block**, and one of those
rounds was paid by shortening comments — losing recorded reasoning to satisfy a line count. Two
extractions came out of it (`cutout_log.gd`, `overlay_markers.gd`), both scoped by what would fit
rather than by what belonged together. Queued in `PLAN.md` with the honest shape: the cutout feed is
the separable concern, and it should not be done inside another bug fix. **Pass E added two more
files to that list — read this with question 8, which carries the current count.**

**6. `BR60.01`'s repair is a design call and it is the one thing pass E deliberately left open.**
Three options, all costed in `PLAN.md`. **Ladder in** — reuses `guarantee_navigability`'s existing
`_open_a_route_out`, cheapest, and would open a 232-cell shelf by ladder, which taskblock-61's own
summary of the entry (*"reachable only by ladder"*) may be complaining about. **Flatten** — what
`_repair_stranded_elevation` already does to ground it cannot reach; erases a fifth of seed 2's
elevation. **Stair in** — reads best and is what the generator already does for raised rooms, but
needs a straight run of lower cells a shelf against the board edge may not have. **The evidence
points at stair-then-flatten-as-fallback**, but that is a guess about how generated boards should
look and not a correctness argument, so it is not taken. The sweep is pinned either way, so whatever
lands can be judged against a number.

**7. `BR57.02` is the one pass E `Pending` whose result CC genuinely cannot verify.** The mechanism
is measured — the isolate camera's `cull_mask` is 6, the board light's `layers` was 1, and the
overlap was exactly zero — and the necessary condition is now met. **Whether the shading looks right
is not something a headless test can answer.** If it is still flat after this, the next thing to
check is whether the `SubViewport` receives the board's `World3D` lighting at all, which is the
other half of the entry's own "where to look next" and is not disproved by this fix.

**8. Four files have now hit the 1000-line lint cap in one block** — `board_view.gd` three times,
`bout_injector.gd`, `test_inspect_panel.gd`, and `test_debug_control_panel.gd` is close. Each round
was paid by extracting, which is the right trade, **but the extractions are being scoped by what
will fit rather than by what belongs together** — the report said this after pass D and pass E did
it twice more. `PLAN.md` carries the `board_view.gd` split with an honest shape. **Worth asking
whether the cap is doing useful work on test files specifically**, where length tracks coverage
rather than complexity.

**9. The fast gate cannot see any bout-building file, and pass E is the first hard evidence of what
that costs.** Sixteen files are on `SuiteTier.BOUT_FILES`, including `test_battle_scene.gd` — which
is where the expectations about what the combat-log panel opens with and how it behaves across
bouts actually live. **`BR51.16` added retained history to `CombatLog`, a core logic class every
bout path touches, and was green on the fast gate three times while carrying a reverted overreach
and a readability regression.** The tier is working exactly as designed and the full gate caught
both, so nothing is broken; the question is whether a change to `src/logic/` shared infrastructure
should be allowed to commit on the fast gate at all, or whether that class of edit should pay the
full one per pass. **The evidence points at "yes, pay it"**, but the full gate is 1000 s against
555 s and that is the supervisor's trade to make, not CC's.
