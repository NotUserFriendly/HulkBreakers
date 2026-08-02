# Taskblock 52 Report — The ray chain

Passes A–F landed in order, with a supervised stop at the block's own **HARD PAUSE** between D and E.
The flag flip landed in Pass F: `CombatState.shot_resolver` defaults to `&"ray"` and the ray chain
resolves every shot. A supervisor bug-hunt pass followed the flip. Suite green throughout.

## Decisions made without asking

- **`Part.is_destructible` was made real.** Declared in `part.gd`, set `false` on `ship_floor` and
  `ramp`, and **no logic read it**. Harmless only while floors could not be shot; the moment Pass D
  gave surfaces geometry, a 1-hp indestructible deck plate would have been destroyed by the first
  round. The alternative — a large hit-point total on floors — is a balance number invented to hide a
  modelling gap.
- **Floor geometry was authored as data, not synthesised in code.** A synthetic box built inside
  `RayCaster` would have meant a designer could not add a walkable surface without a code edit. **The
  0.2 thickness is flagged, not designed:** no shipped material authors a `dt_curve`, so `dt_at`
  ignores thickness entirely today.
- **Six `DamageResolver` helpers were made public rather than copied.** The chain decides *where* a
  round goes; what happens when it arrives stays the one resolver. The alternative was a second copy
  of the crit and destruction logic — the parallel system this project keeps deleting.
- **Joints were put into the march** (`assembly_placements(include_joints)`, default false). Not asked
  for. Without it every joint hit would have shown up in the differential as a disagreement for no
  reason other than one model not knowing joints exist.
- **`Closest root` was kept even though it is measured-dead**, and recorded as such in a test whose
  doc comment says to update rather than delete it if that changes. Deleting a stage the taskblock
  specified is a design call.
- **`PartPicker` was fixed as well as the caster** (`BR52.01`) — outside a resolver block's strict
  scope, but leaving the aim UI hit-testing at a different height from the thing resolution marches
  through would have been two answers to one question.
- **The aim preview was moved onto the active resolver** (Pass E), so `docs/08`'s pillar stops holding
  only by two implementations agreeing.
- **The bout seed was put on `CombatState` rather than into its constructor** (`BR52.11`).
  `CombatState.new` has 733 call sites and almost none are bouts anyone replays. The alternative —
  a required constructor argument — is stricter and would have touched every one of them.
- **`session_start` was renamed `bout_start` rather than left accurate-sounding.** A log file holds
  several bouts now, so a per-file header can only describe the first. Keeping the old name was the
  cheaper option and would have reproduced the same misattribution under a familiar word.
- **The bout header is pushed straight into a late overlay's sink, not re-emitted.** Re-emitting
  through `CombatLog` also reaches the file sink and writes two `bout_start` lines for one bout —
  inventing a duplicate event to close a display gap, which is the shape `BR35.04` was filed for.
- **`BR35.05` was closed `Obsolete`, not `Resolved`.** Its subject (`LineOfFire.approach_path` /
  `closing_path`) was deleted in tb46 Pass C; nobody verified the behaviour was fixed. Its live
  symptom was re-filed against the code that exists.
- **The audit snapshot's deliberate staleness could not be preserved, and this was decided rather than
  discovered late.** `suite_audit.csv` and `suite_profile.json` must agree — the sum assertion checks
  per-test counters against the profile's global totals — so a fresh profile and a stale CSV cannot
  both hold. Dropping the excluded files back out was tried and fails that assertion. The alternative
  was reverting the tests that forced the regeneration.

## Tests that failed, then were corrected

Four failed during A–E; two were defects in the code and two in the tests. Pass F updated a further 16
blocking fixtures, and the pattern is worth stating once: **each was restated in terms of the rule it
protected rather than bumped to match new output.** Impact counts had been standing in for pull counts,
for "one attack fired", and for "the round reached its target"; none survive a round that continues
past what it hit.

1. **A penetrating round struck the same plate six times.** Found by *reading a printed log*, not by an
   assertion — the chain resumed past the struck box's **entry** face, leaving the round inside it.
   `ray_box_hit` reports the exit face now, with an assertion for it and one for `hollow` parts, whose
   enter-and-exit pair is the one case that legitimately strikes one box twice and had no coverage.
2. **The differential reported 152 of 216 shots as `different_part` while its own printed detail showed
   both models striking `wall/STOP_DEAD`.** The comparator compared `Part` by object identity across
   two independently built boards. **The most dangerous failure of the block** — it would have read as
   a catastrophic parity failure and been believed.
3. **An attribution check scored the ray chain at 51%** by rounding hit coordinates to cells; a hit
   lands exactly *on* a box face and 0.5 rounds into the neighbouring cell. The test was measuring its
   own rounding. Replaced with a real point-to-box distance; the honest figure is 100%.
4. **An existing test caught a real bug in the chain the moment the ray became the default.**
   `test_penetration_traverses_body.gd` failed on the lodged-bullet mechanic (tb20 C4) because the
   chain cleared its hollow-cavity flag **before** checking whether the round cleared the far face,
   silently deleting the mechanic on the new path. The fixture held the right assumption and the new
   path was wrong — exactly what a flag inversion is for.
5. **The first version of the late-overlay seed test passed while the bug was fully present.** It
   asserted on the panel that was up *during* `load_battle()`, which is the panel that receives the
   header and is then torn down. Rewritten to assert through the real handoff — load, *then* swap —
   and verified by re-breaking the fix.

## Open questions

- **Friendly fire is a design call, not a patch** (`BR52.10`). An AI unit put eight point-blank rounds
  into the squadmate in front of it. The check *used to exist* — the retired branch planner logged
  `held: ally_in_line` — and `UtilityPlanner` carries no consideration for it. **Should friendly-fire
  risk veto a shot (a precondition) or penalise it (a scored input), and does a player unit get the
  same treatment or does `docs/06`'s asymmetry apply?** Both are one line in shape and very different
  in behaviour. The evidence points at a scored input, because a hard veto reintroduces the
  hold-forever failure `BR35.05` described.
- **A destroyed cover object should probably not simply vanish** (`BR52.09`). `DROPPED_TAG` and
  `mangles_into`/`wreckage_pool` already exist and `_spawn_blocker` already reads `DROPPED_TAG`, so
  "replace with wreckage" is as reachable as "remove". Evidence points at wreckage — the parts are
  authored — but it changes what cover means mid-fight, so it is yours.
- **Overwatch wants an instrument before it wants tuning** (`BR52.12`). Twelve declarations, zero
  fires, and every rejection path is silent, so "never armed", "arc missed" and "never evaluated" are
  indistinguishable. `arc_cells` and `would_trigger_at` already compute the per-cell answer the pie
  slice would draw; it simply is not emitted.
- **Two flagged numbers that are not design decisions yet.** `RayTiebreak.PROBE_RADIUS` (0.05) exists
  only to give the arbiter probe a corner that can lead — **it must not become a projectile width**,
  which the taskblock is explicit is a later lever. The floor's 0.2 box thickness has no DT effect
  today because no material authors a `dt_curve`; it wants a real answer the moment one does.
- **The audit's exclusion is gone and cannot be restored without loosening its own test.** If the
  staleness was worth keeping, the way to keep it is to stop
  `test_per_test_counters_sum_to_the_file_level_profile` gating on the profile's global totals.
