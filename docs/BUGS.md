# BUGS.md — Bug Ledger

**The single place a bug's status lives.** New and resolved, with a rough report time and (for recent
ones) the taskblock in play. Its job: **a resolved bug must have a closure marker here**, so an old
report — still readable in `taskblock_done/`, still describing acceptance criteria — is never
re-derived as open. If you fixed something, mark it RESOLVED here, even if the fix landed as a plain
commit outside the taskblock cadence. That out-of-cadence gap is exactly what let stale reports
recur.

**This file holds only what is still open.** Once an entry reaches `Resolved`, it moves verbatim to
`docs/BUGS-ARCHIVE.md` and is never edited again — so everything here is something that still wants
attention, and "what's open" needs no index, just this file. Move an entry on closure, not in a later
sweep; the archive is history, not a queue.

**Entry format.** The heading carries only the three things you scan for — **ID, status, owner** —
so a single `grep '^### BR'` is the whole open-bug index and nothing derived needs maintaining. The
description sits on the line below it, with source and CC session under that. (The example below is
gutter-marked with `|` so the index grep can't mistake it for a real entry — the marker is not part of
the format.)

```
| ### BR32.01 — Active — owner: `SUPERVISOR`
| **Stray wall-cutout hole at a cell with no unit**
| - **Source:** `SUPERVISOR`  ·  **CC session:** `<uuid>`
```

**`owner` = who is allowed to close it.** Distinct from `source` (who *found* it), which stays
recorded but no longer governs anything. Owner defaults to the source — a `CC`-found bug is
`CC`-owned and CC may resolve it directly; a `SUPERVISOR`-found bug is `SUPERVISOR`-owned and CC may
only ever write `Pending Confirmation`. **The supervisor may promote any entry to `SUPERVISOR`
ownership at any time**, including CC-found ones, so that anything worth watching cannot be silently
closed. Owner is the gate; read it, not the source.

**Status legend:**
- `Active` — open.
- `Suspected` — a possible lead, not yet a confirmed or fully described bug. The reporter refines it
  into a real status at their review pass.
- `Pending` — the fix is complete and CC believes it works, but the owner hasn't seen it
  work yet. The only status CC may write toward closure on a `SUPERVISOR`-owned entry. (Pending *what*: the owner seeing it work.)
- `Resolved` — confirmed fixed by the owner.
- `Obsolete` — the entry can no longer be confirmed or reproduced because the code it describes was
  replaced or removed, not because anyone verified a fix. Closing an entry this way is an honest
  "this question no longer exists" — never use `Resolved` for it, since that would assert a
  verification that never happened. Point at whatever superseded it.

Closed entries (`Resolved`, `Obsolete`) move verbatim to `docs/BUGS-ARCHIVE.md`.

**Convention:** one flat list, sorted by BR number ascending (`BR26.xx` before `BR27.xx` before
`BR30.xx`, lowest sequence first within a taskblock) — no category sections. **Status is inline in the
entry heading** (`Active` / `Pending Confirmation` / `Resolved`), right after the ID, so status and ID
are both visible while scanning. Entries reported before the `BR<taskblock>.<seq>` convention existed
have no ID to sort by — they follow at the end, in their own legacy block, oldest work first. Recent
entries get a timecode + taskblock; older migrated ones get a rough date. `RESOLVED` entries name the
fixing commit(s)/taskblock so the closure is verifiable.

**Every bug carries an ID:** `BR<taskblock>.<seq>` — e.g. `BR27.01` (Bug Report, reported during
taskblock 27, first of that block). **The ID is assigned at report time and never changes** — a bug
reported in tb27 stays `BR27.xx` even if fixed in tb30, so the handle is stable across its whole life
between supervisor, CC, and the reviewer. Put the ID in the entry heading.

**Every bug carries a `source`:**
- **`CC`** — found by CC during its own work (usually a pure-code bug). CC owns the whole loop
  (sees it, fixes it, tests it), so **CC may mark a `CC`-sourced bug `RESOLVED` directly.**
- **`SUPERVISOR`** — reported by the supervisor (the human overseeing the project). CC often
  *can't see* what was reported (a visual glitch, a "feels wrong" behavior), so it may have fixed
  the wrong thing. **CC may NEVER write plain `RESOLVED` on a `SUPERVISOR`-sourced bug.** The most
  it may write is **`RESOLVED-PENDING-CONFIRMATION`** (fix committed, CC believes it's done,
  awaiting the supervisor's verification). Only the supervisor promotes `PENDING-CONFIRMATION` →
  `RESOLVED`, and only after seeing the fix work.

**Session stamps.** CC has no sequential session counter — what it *does* have is a **session
UUID** embedded in its scratchpad directory path (e.g. `.../83fb8082-732a-4a4f-a726-04186087ef69/
scratchpad`). CC stamps its closure marks with the **full UUID**, not a shortened prefix — a prefix
is one collision away from misattributing a stamp to the wrong session on a long-lived machine, and
the full string costs nothing to write (e.g.
`RESOLVED-PENDING-CONFIRMATION [CC 83fb8082-732a-4a4f-a726-04186087ef69]`). If CC is refreshed it
gets a *new* UUID, so a later session reading an earlier session's `PENDING-CONFIRMATION` sees a
**different** stamp than its own — that's the signal it's *another instance's* unverified claim. It
must NOT promote it to `RESOLVED` on the strength of a prior CC's word, only on the supervisor's. A
pending mark whose UUID isn't your current one is a claim to re-check, not a closure to trust.

**End-of-taskblock digest.** At the end of each taskblock, CC lists every `SUPERVISOR`-sourced bug
it moved to `RESOLVED-PENDING-CONFIRMATION` this block — a "here's what I think I fixed, please
confirm" roll-up — so pending items surface at a natural review point without interrupting mid-work.

---
### BR26.02 — Active — owner: `SUPERVISOR`
**Low framerate while aiming**
- **Source:** `SUPERVISOR`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **2026-07-23 (supervisor re-check — REOPENED; worse, not better).** Framerate while aiming is still
  bad and is *likely worse than originally*. tb34's two fixes (the ratio-normalized texture cache, and
  deleting `AimView._process`'s redundant per-frame `refresh()`) were both reasoned rather than
  measured — no profiler exists in CC's environment — so neither is confirmed to have helped, and the
  tb34 Pass B/C additions (bound ring, pellet overlay, in-world `Label3D` tooltip) are unexamined new
  cost in the same path.
- **Supervisor-specified instrumentation — make framerate a LOGGED number, not a felt one.** The
  reason this bug has survived three passes is that CC cannot see a framerate; make it something CC
  *can* see. Two combat-log dumps:
  1. **Aim FPS** — dump framerate **200 ms after entering aim** (past the entry transient, into the
     steady-state sweep).
  2. **Turn FPS** — dump framerate **200 ms after a new turn begins**, deliberately offset so it
     measures the settled frame rate and not BR27.09's turn-boundary hitch.
  With both in the log, every future change to the aiming path carries its own before/after evidence,
  and this stops being a bug only the supervisor can adjudicate. Build the instrumentation before
  attempting another fix.
- **Reported:** taskblock-26 (bout review), filed in the taskblock's own scope fence as explicitly
  deferred: "B-tier; investigate separately — likely the inspect field updating every frame; not a
  correctness bug, don't rush a fix into this block."
- **Status:** not investigated. Flagged for the post-tb26 testing/tooling review (pairs with a "what
  does CC do repeatedly" audit) rather than fixed under taskblock-26's own scope.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** root cause is NOT the
  inspect field (the original guess) — it's `aim_view.gd:104-106`, a `_process()` override that
  unconditionally calls `refresh()` every single frame while aiming, even though `refresh()` is
  already correctly wired to the `aim_changed` signal (fired only on real state changes — reticle
  move, layer scroll, target change — from ~9 call sites in `tactics_controller.gd`). Each redundant
  frame call clones the preview `CombatState` and rebuilds the full-board `ShotPlane` twice (once in
  `aim_state()`, again inside `AimController.resolve()`), plus reallocates dartboard resolver/mesh
  objects. **Candidate fix (not yet applied):** delete or gate the `_process` override behind the
  same change-detection the signal path already provides.
- **2026-07-23 (tb34 Pass A + Pass E):** two real fixes landed, addressing the pass's own two named
  suspects in order. Pass A fixed the OTHER latent cost this same screen was about to acquire:
  `DartboardTexture.build`'s 128x128 per-pixel rebuild used to always cache-hit because rings were
  weapon-constant; the instant the board became range-aware (`ShotScatter.for_shot`), every
  retarget/reposition would have missed the cache and rebuilt it — `AimView._rings_match` now keys on
  ring-RATIO rather than absolute radius, so a pure range change still reuses the cached texture.
  Pass E then applied this ticket's own already-diagnosed fix directly: confirmed the redundant
  `_process()` override (quoted above) was still present and unchanged, confirmed every mutation path
  `refresh()` cares about already emits `aim_changed` (11 call sites, comprehensive per re-audit), and
  deleted the override outright — `refresh()` is now purely signal-driven, no per-frame poll at all.
  Full suite green throughout (headless — the cache-regression test this ticket's own ledger already
  asked for is in `test_aim_view_dartboard_cache.gd::test_a_realistic_range_sweep_builds_the_texture_
  at_most_once`).
- **Not live-verified.** Both fixes are well-reasoned and address the two most concretely diagnosed
  costs, but per this ticket's own "measure, don't guess" instruction, only an actual live frame-rate
  observation confirms the aiming screen is no longer slow — and per the taskblock's own admission,
  profiling might still name the new Pass B/C overlays as a further cost if the two fixes above aren't
  the whole story. Needs the supervisor's own hands-on confirmation before promotion to `RESOLVED`.
### BR27.01 — Active — owner: `SUPERVISOR`
**Player Step Out: four bugs, one system**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27: Step Out works for the AI but the player's own path was broken four
  ways — (1) doesn't open the dartboard, always resolves a center-mass shot; (2) charges MP for the
  automated legs; (3) the ghost snaps back to the base cell instead of holding the step-out
  waypoint; (4) the intended sequence (pick step-out → ghost holds the cell → dartboard opens there
  → fire resolves the whole move/fire/return) wasn't followed.
- **Root cause:** `TacticsController._confirm_step_out()` called `StepOutPlanner.build_triple()`
  wholesale the instant the player confirmed a candidate cell — queuing the WHOLE move+attack+move
  triple (an automated center-mass shot) in one click, never entering ordinary aim mode at all. The
  ghost "snapping back" was a direct symptom of this: the entire triple (ending back at origin)
  was queued and previewed in the same instant the step-out cell was chosen, so there was never a
  sustained moment where the ghost held the stepped-out position for the player to see. `MoveAction`
  had no discount mechanism at all — `StepOutPlanner`'s own doc comment stated "real MP/AP cost for
  both legs, no discount" as a deliberate original design choice.
- **Fix:** split the flow. Confirming a step-out cell now queues ONLY the free outbound leg
  (`MoveAction.free`, new — no MP/AP either direction, docs/SUPERSEDED.md), then hands off into
  ORDINARY aim mode from the stepped-out position (`_framing_shooter()`/`aim_state()` already read
  the previewed unit, so the camera and dartboard follow the queued move for free). Firing
  (confirm_shot() again, now in aim mode) appends the free return leg once a real shot actually
  queues. Canceling aim mid-step-out (before firing) undoes the queued outbound leg. The ghost
  "snapping back" is now correct, not a bug — it only happens once the return leg is genuinely
  queued (after firing), the truthful final resting position; during the aim phase it holds the
  stepped-out cell via the same queued-move preview machinery every other action already uses.
  `free` applies to the AI's own `StepOutPlanner` usage too, not just the player's — the same shared
  maneuver, same cost either way.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — taskblock-27 Pass B,
  proven via `test_tactics_controller_step_out.gd`'s updated/new tests (cell-confirm queues only the
  free out-leg and opens aim; firing completes the free triple; canceling aim undoes the out-leg)
  and `test_step_out_planner.gd::test_the_triple_costs_no_mp_for_either_leg`.
- **2026-07-20:** supervisor could not verify — blocked by a new, separate bug (now logged as
  **BR27.06 — Step Out no longer occurs at all**, a regression from this very restructure). Until
  BR27.06 is fixed, BR27.01 can't be confirmed. **Verification deferred**; still pending, and now
  gated behind BR27.06.
- **2026-07-21:** BR27.06 now has a fix pending its own confirmation (commit `d42f744`). Worth
  re-attempting BR27.01's own verification alongside BR27.06's — same play session either way.
- **2026-07-21 (broken down by the supervisor, same session as BR27.06's confirmation):** parts (2)
  and (3) confirmed **RESOLVED** — no more MP charged for the automated legs, ghost no longer snaps
  back. Part (4) ("the intended sequence wasn't followed") was the supervisor's own original
  rephrasing of (1)-(3) together, not a distinct fourth symptom — folded in, not tracked separately.
  Part (1) has **mutated, not resolved** — reopened with a precise new repro: "clicking shoot, then
  clicking an enemy, doesn't bring up the dartboard if the unit had to step out; clicking again brings
  up the dartboard." Likely the two-step step-out flow itself (first click enters step-out-cell-choice
  mode, a second click/`confirm_shot()` is what actually opens ordinary aim mode per the Pass B fix
  above) reading as "doesn't work" without a clear in-between visual cue — not yet investigated
  code-side. **BR27.01 stays open for this one remaining piece.**
- **2026-07-22 (tb32 review — still reproduces):** unchanged — step-out after shooting still does not
  open the dartboard immediately on the step-out; a second click is required. tb32 didn't touch this.
  The one open piece (part 1) persists exactly as the 2026-07-21 repro describes.
### BR27.02 — Active — owner: `SUPERVISOR`
**Chaingun bursts fire half-backward (visual only, hits are correct)**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20, observed watching a live bout play out — "the most recent two chaingun
  bursts look odd, both look like half the burst is going backward."
- **First fix (taskblock-27 Pass A1):** every attack action's shot-plane `direction` was cell-anchored
  while `origin` was muzzle-anchored — two different anchors for the same ray, which could resolve a
  target at negative depth and animate as the round travelling backward. Both now share the muzzle
  anchor. **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082-732a-4a4f-a726-04186087ef69] at the time,
  proven via a constructed overshoot-geometry test.
- **2026-07-20: supervisor reports still visually backward** — but with a key new detail: "those
  backwards shots do seem to be hitting the things they're drawn as hitting." The actual hit
  resolution (which part takes the damage) is correct; only the drawn tracer/animation direction
  still reads as backward. This means the Pass A1 fix (a `ShotPlane`/`AttackAction` geometry fix)
  either isn't the code path driving the visible tracer, or there's a second, separate anchor
  mismatch specifically in the rendering path (`resolution_player.gd`'s own tracer-drawing code, not
  yet audited against this same origin/direction-anchor class of bug). **Reopened — not
  investigated further this pass**, per instruction to just log and wait.
- **2026-07-20 (taskblock-28 Pass C):** not investigated or fixed this pass either — but
  `out/combat.log` now prints every impact/miss event's own real origin/hit geometry (was already in
  `data` since tb22/23; `LogEvent._to_string()` just never rendered it, and `Overwatch._fire`'s own
  separate impact path had no geometry at all until this pass routed it through the shared logger).
  A future session chasing this bug can read the geometry straight from the log text instead of
  re-deriving it or relying on live playback. Still open; still unconfirmed.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** primary tracer
  read/write anchors now match (post first-fix) — no mismatch there. Suspect is the DEFLECT
  bounce-continuation segment: `resolution_player.gd:464-478` draws from the hit point to
  `deflect_end_*`, computed in `shot_resolution.gd:225-232` as `hit_point + reflected_dir *
  void_range`. `reflected_dir`'s sign/normal convention (`damage_resolver.gd:118-131`) has not been
  audited against this bug class — a flipped convention there would draw a visibly backward secondary
  ray for DEFLECT-outcome shots while leaving the real hit correct, matching "half the burst backward,
  hits correct" exactly. **Bonus find (separate, same bug class):** `overwatch.gd:264-265` still
  computes `origin` as a raw cell-center — never migrated to the muzzle-anchor fix `AttackAction`
  received in Pass A1. A second live instance of the exact same anchor-mismatch class, in a different
  code path. Neither finding implemented or tested yet.
- **2026-07-23 (live playtest, `out/combat.log`, units 0/1/2 supervisor-controlled) — a new angle,
  not yet reconciled with the 2026-07-21 suspects above.** Unit 0's 12-round chaingun burst at
  `(6, 19)`, fired from roughly `(4, 17)`: **all 12 of 12 pulls resolve `DEFLECT on wall`**, every one
  clustering around hit point `~(0.3-0.8, 13.7-14.8)` —
  e.g. `DEFLECT on wall [origin (3.95, 17.26)@1.53 -> hit (0.67, 13.80)@1.71]`. That hit point sits in
  the OPPOSITE quadrant from the aimed target: origin-to-target is `+x, +y`; origin-to-hit is
  `-x, -y`. Every pull agrees on roughly the same wrong-direction spot (scatter alone wouldn't do
  that), and — unlike the two-hop chain logged minutes later for unit 2 (`DEFLECT` immediately
  followed by its own `STOP_DEAD` continuation, sharing an origin/hit boundary) — each of these 12
  pulls logs exactly ONE impact event, no continuation segment. That means the anomaly sits in the
  FIRST forward ray-cast (muzzle to first wall) itself, not in the `reflected_dir` bounce-continuation
  segment the 2026-07-21 note suspected (which only governs what happens AFTER the first hit) — a
  candidate for a still-live anchor mismatch in the primary ray itself, distinct from that suspect,
  not yet root-caused. Logged only — not investigated or fixed this pass.
- **2026-07-23 (follow-up, read-only code investigation — no fix attempted): a concrete hypothesis
  for the first-segment anomaly above, arithmetically consistent with the logged numbers.**
  `damage_resolver.gd::resolve_shot` computes each hop's own logged point as
  `origin + dir * region.depth + perp * point.x` (`dir`/`perp` from the outer call's own `direction`,
  never re-derived per hop). Solving that equation backward for the unit-0 example above
  (`origin (3.95, 17.26)`, `dir` normalized toward `(6, 19)` ≈ `(0.76, 0.65)`, `hit (0.67, 13.80)`)
  requires `region.depth ≈ -4.3 to -5.3` — genuinely **negative**, i.e. the resolved region sits
  BEHIND the shooter along this shot's own fire line, not in front of it.
  **Why a negative-depth region could win at all:** `ShotPlane.build` (`shot_plane.gd:45`) sorts the
  whole plane with a bare `a.depth < b.depth` — no floor at zero anywhere — and `_find_next`
  (`damage_resolver.gd:837`) just walks that sorted array and returns the FIRST region whose rect
  overlaps the aim point. Negative-depth regions are a known, INTENTIONAL part of the plane (`docs/09`
  taskblock06 Pass H's own `AimController.window_depth` doc comment: "a body positioned behind the
  shooter along the fire line still gets a Region... so its own frontmost depth can be small or even
  negative") — but that fact was only ever handled defensively on the AIM-WINDOW side
  (`window_depth`'s own `MIN_WINDOW_DEPTH` clamp) and the SHOOTER's-own-body self-exclusion
  (`_first_hit_excluding`/`self_obstruction`, by identity). Neither guard stops a DIFFERENT body's
  region — a wall, say — from sorting first purely because its projected depth happens to be more
  negative than every real, forward obstacle, then winning `_find_next`'s linear scan if the aim
  point's lateral/height coordinates happen to fall inside that region's rect (which a wide/tall wall
  segment's own rect can do regardless of which side of the shooter it's actually on). If real, this
  would be a genuine RESOLUTION bug (which region gets picked), not merely a rendering-direction one —
  which would refine, not just extend, the 2026-07-20 report's own claim that "hit resolution... is
  correct; only the drawn tracer direction is backward" (that may hold for whatever case prompted that
  original report, but doesn't appear to hold for this DEFLECT case). **Not verified against a
  constructed fixture — this is a read-through-the-code hypothesis from one live example's own
  arithmetic, not a proven root cause.** No fix attempted.
- **2026-07-23 (tb35 Pass B — this hypothesis confirmed and fixed, advancing but not closing)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. The 2026-07-23 read-only hypothesis above was exactly
  right: `_find_next` (and `ShotPlane.resolve_projectile`, and a third independent implementation,
  `LineOfFire._first_hit_excluding`, discovered on the same pass) all walked the unfloored,
  negative-depth-inclusive plane with no floor of their own. Fixed by flooring the RESOLVING path at
  `depth >= 0` (opt-in on `resolve_projectile`, unconditional on the other two, which are always fed
  a real shooter-anchored plane) while leaving `ShotPlane.build`'s own sort and the aim window's
  `window_depth` reading untouched, per this same bug's own 2026-07-23 note above. Headless
  regression: `test_line_of_fire.gd::test_first_hit_never_resolves_to_a_wall_behind_the_shooter`
  reconstructs this exact shape (real target ahead, wall several cells behind the shooter, present in
  the plane on purpose) and asserts the resolved hit is the target, not the wall. **Stays Active, one
  entry** (this taskblock's own scope fence, per the supervisor's ruling): this fixes the resolution
  mechanism the hypothesis named, but the original report was about the drawn TRACER direction
  specifically, and that rendering path (`resolution_player.gd`) has not been re-checked live against
  this fix — needs a live bout to confirm the visual symptom is actually gone, not just the
  resolution math underneath it.
### BR27.03 — Active — owner: `SUPERVISOR`
**Other shots appear to resolve before an earlier shot's own deflect finishes**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20, correcting a taskblock-27 misdiagnosis (see the correction note in
  `taskblock_done/Report-Taskblock27.md`): a shot and its own deflect are SUPPOSED to resolve
  simultaneously (not paused apart, as taskblock-27 Pass A2 assumed) — the real defect is that a
  DIFFERENT, later shot can appear to resolve/animate before an earlier shot's own deflect segment
  has finished.
- **Status:** not yet investigated. taskblock-27 Pass A2's own `DEFLECT_BEAT_MS` fix inserted a
  deliberate pause between a primary hit and its own deflect — per this correction, that pause is
  itself a wrong implementation of the actual intent (simultaneous primary+deflect) and does not
  address this bug at all. Likely candidate: `ResolutionPlayer`'s own inter-event sequencing between
  separate impact events, not the intra-event primary/deflect pairing `DEFLECT_BEAT_MS` targeted.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** confirmed not an
  intra-event bug — each `ResolutionPlayer.play()` call is fully await-serialized internally,
  primary+deflect included. The gap is a missing reentrancy guard: `play()` has no busy-flag, and
  `SpectatorOverlay.step_once()` (`spectator_overlay.gd:249-251`) calls `pause()` (only flips a bool,
  doesn't cancel anything in flight) then immediately awaits `_advance()` — so a Step/Play issued
  right after Pause can start a SECOND concurrent `play()` while an earlier turn's own deflect tracer
  is still animating. **Candidate fix (not yet applied):** add a busy/in-flight guard to
  `ResolutionPlayer.play()`, or have `pause()` actually await the in-flight `_advance()` before
  returning.
### BR27.04 — Active — owner: `SUPERVISOR`
**Lighting differs between spectator and player view**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27 D1b: spectator and player view are said to light the board
  differently.
- **Investigated, no code fix applied:** `BattleScene._ready()` already builds
  `WorldPalette.world_environment()` and `WorldPalette.directional_light()` exactly once, as
  children of the shared `BattleScene` itself — strictly before either overlay
  (`SquadControlOverlay`/`SpectatorOverlay`) is installed via `set_overlay()`. Neither overlay
  constructs its own lighting anywhere; both render the same lights on the same world. The code
  does not support the premise of a divergence as currently written.
- **Status:** not resolved — needs the supervisor's own visual re-check (a real screenshot
  comparison) rather than a code claim, since no divergent lighting path was found to remove.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** re-confirms the prior
  pass's conclusion — no new code path found. Genuinely needs the supervisor's own visual/screenshot
  re-check, not further code digging.
### BR27.07 — Pending — owner: `SUPERVISOR`
**Active-turn highlight lands on the wrong unit; change to facing-marker-only**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor check — looks right, BLOCKED on full confirmation).** The change reads as
  correct on inspection, but it cannot be properly verified while **BR34.06** (every AI unit passing
  every turn) is live — there aren't enough real turn transitions to watch. Re-check after BR34.06.
- **Reported:** 2026-07-20 (tb27 review). Two parts: (a) **design change** — instead of recoloring the
  active unit's facing wedge + team marker (tb27 D2), the supervisor wants *only the current unit to
  show a facing marker at all* (the marker's presence indicates whose turn it is, not a color). (b)
  **bug** — the current-unit highlight sometimes lands on the *next* or *prior* unit, not the active
  one.
- **Status:** open. Note the design change supersedes part of D2 (which shipped as a feature in
  CHANGELOG) — the "recolor" approach is being replaced by "only the active unit has a facing marker."
  The wrong-unit bug may be independent (an off-by-one in whichever index drives the highlight) and
  should be checked even after the design change, in case the change is built on the buggy selector.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here) — concrete ordering bug,
  confirmed:** `SquadControlOverlay._on_turn_ended()` (`squad_control_overlay.gd:573-582`) calls
  `refresh_unit_views()` — which flips the highlight to the new current unit — at line 574, BEFORE
  `await resolution_player.play(events)` at line 577 animates the unit whose turn just ended. The
  marker visually jumps to the next unit while the previous unit is still animating its own queued
  action. **Compounding bug:** `SingleUnitOverlay._on_turn_ended()` (`single_unit_overlay.gd:40-42`)
  calls `super._on_turn_ended(events)` WITHOUT `await` — since the parent implementation contains an
  internal `await`, this lets `_auto_select_if_current()` run immediately, racing ahead of the
  parent's own animation/AI-batch completion. **Candidate fix (not yet applied):** reorder so
  `refresh_unit_views()`'s highlight flip runs after the animation await completes; add the missing
  `await` in `SingleUnitOverlay`.
- **2026-07-22 (tb32 Pass D) — both parts done:** (a) design change — `HitVolumeView.set_active_turn()`
  no longer recolors anything (`ACTIVE_TURN_COLOR` retired); it toggles the facing wedge's own
  `.visible` instead, so only the current unit ever shows a facing marker at all, exactly as
  requested. (b) ordering bug — `BattleScene.refresh_unit_views()` gained an `apply_highlight: bool =
  true` parameter; `SquadControlOverlay._on_turn_ended()` now passes `false` and calls the (newly
  public) `battle.apply_active_turn_highlight()` itself AFTER `await resolution_player.play(events)`
  completes, so the marker no longer jumps to the next unit mid-animation. `SingleUnitOverlay._on_
  turn_ended()` now `await`s its `super` call, closing the compounding race. Every other existing
  caller (`advance_ai_turns`, `SpectatorOverlay`) keeps the old default (`apply_highlight` true, no
  deferral) unchanged.
- **2026-07-22 (supervisor tweak):** "facing marker" means the WHOLE disk/facing-pip assembly (the
  ground marker AND the wedge together), not the wedge alone — the first pass only toggled the
  wedge's own visibility, leaving every unit's ground disk always showing regardless of whose turn
  it is. `set_active_turn()` now toggles both `_team_marker.visible` and `_facing_wedge.visible`
  together.
### BR27.09 — Active — owner: `SUPERVISOR`
**Major hitch on new-turn or end-turn**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20 (tb27 review). A significant frame hitch fires on either the new-turn or
  end-turn transition — supervisor can't yet tell which of the two triggers it.
- **Status:** open. First step is isolating which transition (instrument both, or bisect). Possibly
  related to per-turn work done synchronously (a full `refresh_unit_views` / re-resolve on the turn
  boundary).
- **2026-07-21 — pinned down, likely the same underlying mechanism as the now-retired BR26.01
  ("opposing team teleports"):** supervisor reports the transition precisely now — "at the end of
  player unit turns, there's a heavy lag spike, then all the opposing units move and act in one go."
  BR26.01's own fix only reordered so the human's own turn finishes animating BEFORE the AI batch
  starts; it never gave the AI batch itself any animation. A read-only investigation pass
  (`docs/Bugs-add.md`, rolled in here) confirms the mechanism: `advance_ai_turns`
  (`control_overlay.gd:68-83`) calls `BoutRunner.step()` once per consecutive AI unit with **no yield
  between iterations**, and each `step()` runs full per-candidate pathfinding/LOS/cover scoring via
  `UnitAI.plan_turn` — the entire AI batch executes synchronously in one frame, which is both the
  hitch (all that planning work landing in one frame) and the "one go" (no animation between AI units,
  just a single `refresh_unit_views` once the whole batch is done).
- **Candidate fix (not yet applied):** yield between AI units in the loop (e.g.
  `await get_tree().process_frame`) to spread the planning cost across frames instead of one
  synchronous batch — would likely also restore *some* per-unit animation pacing, though the AI batch
  is deliberately unanimated by design (only the human's own turn animates), so a fix here is about
  the hitch specifically, not necessarily adding animation.
- **2026-07-23 (tb34 review — worse and broader than logged):** the hitch is **several seconds long**,
  not a frame spike. And the scope is wider than the AI-batch case above: **every player turn now ends
  in a long hitch**, not only turns followed by the opposing team's batch move. That second part
  matters — the `advance_ai_turns` synchronous-batch mechanism explains a hitch *before the AI acts*,
  but it does not explain a hitch at the end of a player turn with no AI batch pending. Either there's
  a second cost on the player turn-end path (a full `refresh_unit_views` / re-resolve on the boundary,
  the original 2026-07-20 suspicion), or the AI planning is now more expensive per unit than it was —
  tb33 added a real `ShotPlane` build per candidate cell to the engagement scorer and an approach
  flood on the no-LOF path, both inside `UnitAI.plan_turn`, which is exactly the code this entry says
  runs synchronously for the whole batch. **Instrument the player turn-end path separately from the AI
  batch before fixing** — the candidate fix above (yield between AI units) addresses only one of the
  two, and would leave a several-second player-turn hitch untouched.
- **2026-07-23 (tb35 Pass A3 — one real cost measured and cut, not the whole bug)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Confirmed the "tb33 added a real `ShotPlane` build per
  candidate cell" suspicion directly: `_any_reachable_has_lof` and `_engagement_score` each
  independently resolved `LineOfFire.first_hit` for the same (unit, enemy, cell) — up to ~2 real
  `ShotPlane.build`s per reachable cell, ~96 reachable cells on a normal map, every single
  reposition-or-hold turn. Added `LineOfFire.cached_first_hit` (opt-in, `null` default — every other
  caller unaffected) and threaded one per-turn memo `Dictionary` through `_plan_ranged` →
  `_any_reachable_has_lof`/`_pick_engagement_position`/`_engagement_score`/`_ally_in_firing_line` so
  each cell resolves once, not twice. Measured on the same 60-turn `BoutSetup` bout used to verify
  BR34.06: average per-turn cost for a reposition/hold turn dropped from **2023ms to 974ms** — roughly
  halved, matching "cut the duplicate resolution" exactly. **Not a full fix:** ~974ms/turn is still
  real, unavoidable per-cell `ShotPlane.build` cost this memoisation can't remove without a bigger
  algorithmic change (out of scope for "memoise per cell" as specified) — BR27.09 stays open. The
  original player-turn-end-hitch-with-no-AI-batch question above is also still unaddressed; this pass
  only measured and cut the AI-planning half.
### BR30.02 — Active — owner: `SUPERVISOR`
**Debug move_object mutates state but the model never visually moves**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, live bout review), tested BEFORE BR30.01 (spawn) in the
  same session — so NOT explained by testing move against an already-invisible just-spawned unit (an
  earlier CC theory here, now known wrong; see BR30.01's own history). Both "Move On Next Click" and
  manual cell-entry Apply are reported affected. `unit.cell` genuinely changes (confirmed via inspect);
  the rendered model does not.
- **Status:** could not reproduce through any headless path tried so far — logged as a real negative
  result, not a fix. Built a REAL `BattleScene` + `SpectatorOverlay`/`SquadControlOverlay`, drove the
  debug panel's actual `_on_apply_pressed()`/`applied` signal for real, and read `HitVolumeView`
  transforms (both the root and a child marker) back per CLAUDE.md's own view-math rule, across three
  scenarios: a fresh bout, a bout after driving several real AI turns through the normal animated
  `ResolutionPlayer` path first (in case a stale cosmetic offset from a real animation was leaking into
  a later debug move), and through both overlays. In all three, `battle.refresh_unit_views()` (already
  wired to the panel's own `applied` signal) correctly rebuilt the moved unit's mesh at the new cell —
  no bug found in `move_object`, `HitVolumeView.refresh()`, `UnitGeometry`, or the `applied` signal
  wiring itself.
- **Needs a more specific repro before further guessing is worth the cost** (per tb30's own "don't loop
  within a block" instruction): does the status label read "Move Object: applied"? Is the camera
  actually framing the destination cell (a correct-but-off-screen move would look identical to "nothing
  happened" without a wrong transform)? Does re-selecting/re-inspecting the same unit afterward show it
  at the new cell in the 3D view specifically (not just the inspect panel's own text)? Exact steps
  (verb used, source/destination cells, which overlay) would let this become a matching headless
  fixture instead of a fourth guess.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here) — concrete asymmetry,
  confirmed:** in `debug_control_panel.gd`, the "Move On Next Click" path's own
  `_begin_move_on_next_click` (:349-363) explicitly snapshots the active object BEFORE arming the
  destination-cell picker, specifically to dodge a signal race (a comment at :344-348 explains why).
  But `_on_apply_pressed`'s OBJECT-param resolution (`_resolve_param`, :414-415) has NO equivalent
  snapshot — it reads whatever `_active` is live at Apply time. Since `_start_picking`'s one-shot
  listener (:371-379) shares the same `board_clicked` signal as the panel's always-on tracker
  (`_arm_active_tracking`, :185-192), clicking "Pick" on the destination CELL field can silently
  overwrite `_active` and swap out the intended unit object before Apply resolves it — explaining
  "data mutates, model doesn't move" without any bug in `move_object`/`HitVolumeView`/the `applied`
  signal itself. This would specifically explain the manual cell-entry Apply path IF the supervisor's
  own workflow used that field's "Pick" button rather than typing coordinates by hand. **Candidate fix
  (not yet applied):** give `_on_apply_pressed`'s OBJECT resolution the same snapshot-before-arming
  treatment `_begin_move_on_next_click` already uses.
### BR30.04 — Active — owner: `SUPERVISOR`
**Waypoint colors shuffle when arming an attack and targeting a cover item**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21, found while confirming BR27.05: "selecting an attack, then trying to shoot
  a cover item causes your waypoint colors to shuffle."
- **Status:** open, not yet investigated. Likely candidate given the symptom: `BoardView.
  show_ghost_paths()` cycles `LEG_COLORS` by queue index (`LEG_COLORS[i % LEG_COLORS.size()]`) — if
  arming an attack against a cover item (rather than a unit) somehow re-queues/re-indexes the existing
  move legs, or a targeting-mode preview call feeds it a different leg count/order than what's actually
  queued, the per-leg color assignment would visibly shift without the underlying queued path changing.
  Not yet confirmed — needs a real repro (which action, what leg count was already queued, which cover
  item) before touching the code.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here) — confirms the ledger's
  own hypothesis above:** `LEG_COLORS` has only 4 entries (`board_view.gd:36-41`), cycled via `i % 4`
  (:376). Targeting a COVERED target routes through the step-out triple
  (`tactics_controller.gd:603-621`, `872-926`), which appends 1-2 extra "free" `MoveAction` legs
  indistinguishable from real ones in `show_ghost_paths`'s own input list — pushing the total leg
  count past 4 and wrapping colors. Targeting an uncovered unit adds zero extra legs, so it never
  wraps, which is why the bug only shows on cover-item targeting. **Candidate fix (not yet applied):**
  either grow the color palette past 4, or exclude free step-out legs from the color-cycling index so
  only "real" queued legs consume a color slot.
### BR30.05 — Active — owner: `SUPERVISOR`
**Debug panel: clicks and scroll bleed through to the world board/camera**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21, live debug-panel use. Two related symptoms: (1) clicking within the debug
  menu itself can also select a world cell (the click reaches the board underneath, not just the
  panel widget); (2) once the verb list's own `ItemList` is scrolled to the bottom, further scroll
  input bleeds through and zooms the world camera instead of stopping at the list's own end.
- **Status:** not yet investigated. Likely candidates: (1) some region within `DebugControlPanel`'s
  own layout still has a plain `Control.MOUSE_FILTER_IGNORE` container gap that isn't actually
  covered by an interactive child, letting a click over that gap fall through to the 3D
  viewport/`_unhandled_input` underneath (the same class of bug `docs/09` taskblock07 Pass B4 already
  fixed once elsewhere); (2) `ItemList`'s own scroll wheel input isn't marked handled once it can't
  scroll further, so the same wheel event continues on to `CameraRig`'s own zoom handler. Both are
  UI-event-consumption gaps in the SAME panel, not two unrelated bugs.
### BR30.10 — Pending — owner: `SUPERVISOR`
**Shots resolve straight through walls**
- **Source:** `SUPERVISOR`
- **2026-07-23 (supervisor check — NOT confirmable yet).** Rounds are definitely striking walls now,
  so the core of the fix is doing something — but there are enough remaining inconsistencies that the
  fix can't be signed off. Three specific findings came out of this check and are filed separately:
  **BR32.07** (burst can't engage a wall at all — symptom has since shifted, see that entry),
  **BR34.05** (misses vanish instead of striking anything), and the depth-floor defect that tb35 Pass B
  addresses. Leave `Pending Confirmation` until those are settled — several of them are probably the
  "inconsistencies" observed here rather than separate phenomena.
- **Reported:** 2026-07-21, live play testing BR27.01: an attack against an enemy on the opposite side
  of a wall tile connects as if the wall isn't there. Confirmed by the supervisor as their very first
  test case, deliberately, not an accidental cross-cover shot.
- **Root cause, confirmed by code:** `LoS.has_los()` (`src/logic/los.gd`) and `ShotPlane.build()`
  (`src/logic/shot_plane.gd:19-46`) read entirely disjoint data. `LoS` reads only `grid.opacity` (set
  to `1.0` for wall cells by `MapGen.generate()`, `map_gen.gd:52-56`) — correctly treats walls as
  opaque for TACTICAL gating (aim-mode/step-out decisions). `ShotPlane.build()` only ever projects
  `state.units` and `state.grid.blockers` (`shot_plane.gd:24,33`) into the depth-sorted hit plane —
  never `grid.opacity`. `MapGen` never writes a `blockers` entry for WALL cells — only
  `_scatter_cover()` (`map_gen.gd:201-208`) populates `blockers`, and only for scattered cover props on
  `OPEN` cells. So a real wall has an opacity flag but no Part, no mesh, nothing in `grid.blockers` —
  it is entirely invisible to the actual damage-resolution path, which only ever sees shooter, target,
  and scattered-cover Parts. `docs/02` (`docs/02-projection-and-targeting.md:82-84`) already documents
  the intended fix: terrain should be "a Part flagged indestructible" living in the same plane as
  everything else — never implemented for walls, only for scattered cover.
- **View-layer confirmation:** walls have no 3D volume either — `BoardView._build_wall_indicators()`
  (`src/view/board_view.gd:239-245`) only draws a flat floor decal (`WALL_INDICATOR_HEIGHT = 0.015`)
  plus a thin decorative cross; no `CollisionShape`/`StaticBody` exists for walls anywhere in
  `src/view/`. This matches the supervisor's own observation that walls are "visually nothing" beyond
  the debug 'x' marker.
- **Fix:** `MapGen._stamp_wall_geometry()` (new, runs last in `generate()`, after
  `_ensure_spawns_connected` so it sees the grid's final layout) gives every WALL cell that borders at
  least one non-WALL cell a real, indestructible `Part` in `grid.blockers` — `data/parts/wall.tres`
  (new: a full-cell box, `is_destructible = false`, matching docs/02's own "terrain is a Part flagged
  indestructible"). A WALL cell buried in solid, unreachable rock (no non-WALL neighbor) deliberately
  gets no blocker — it can never be the nearest hit along any real ray, so skipping it is a pure perf
  win (`ShotPlane.build`'s own per-shot scan is unculled), not a behavior change.
  `LoS.has_los()` is unchanged (opacity-only) — it already correctly treated walls as opaque; only the
  hit-resolution side was blind to them.
- **Side effect, expected and not chased further this pass:** as a direct consequence of walls now
  really blocking, this landed a follow-on discovery — a live seed-search on `test/integration/
  test_full_mission.gd` (whose own hardcoded `SEED` now fails, same "a real mechanics fix reshuffles
  the deterministic timeline" pattern that test's own header already documents five times over) showed
  **81% of all impacts in one full mission (368/457) landing on a wall instead of the intended
  target** — the AI appears to fire without ever verifying a genuinely clear line of fire, trusting
  `ShotPlane` alone to arbitrate (harmless before this fix, since nothing ever blocked a shot). Likely
  why missions now grind through more turns under the fix. Not filed as its own bug yet — flagged here
  as the reason `test_full_mission.gd`'s current failure may need more than a seed re-pick, and as a
  candidate follow-up investigation into AI engagement/target selection (`UnitAI._pick_engagement_
  position`/`_engagement_score`).
- **Verified:** `test_shot_plane.gd::test_a_wall_part_between_shooter_and_target_blocks_the_shot` (a
  wall Part between shooter and target intercepts the shot; the target is still there once the wall is
  excluded) and `test_map_gen.gd::test_exposed_wall_cells_carry_a_blocking_part_interior_walls_do_not`
  (every exposed wall cell across 50 seeds carries the blocker; every fully-interior one doesn't).
  1868/1869 green — the one remaining failure is `test_full_mission.gd` itself, above, a known,
  expected consequence, not chased this pass (supervisor's own call: "consider the full test failed
  for the moment, we have a couple other things to check").
- **RESOLVED-PENDING-CONFIRMATION** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit pending.
### BR32.01 — Active — owner: `SUPERVISOR`
**Stray wall-cutout hole at a cell with no unit**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor re-check — REOPENED, and merged in understanding with BR32.03).** Still
  reproduces. The description here is almost certainly the *same phenomenon* BR32.03 describes from
  the other side: a "stray cutout at a cell with no unit" is what a cutout that **carried over from a
  previous bout** looks like once the unit that justified it is gone. Treat BR32.01 and BR32.03 as one
  defect with two observed faces — fix the feed-refresh boundary (bout load, unit spawn, unit removal)
  once and both should fall. Do not fix them as separate bugs.
- **Reported:** 2026-07-22 (live bout, tb32 review). "A stray culling around cell 2,18, with no unit
  to produce that effect... that is the ONLY culling step I see, it's not showing on the units."
- **Root cause, confirmed by reading the code (no live repro available to me — this session has no
  Xvfb/GPU, so I can't run the actual bout myself):** `BoardView.wall_cutout_units` is a live
  reference to `CombatState.units`, fed unfiltered into the wall-cutout shader
  (`BoardView.update_wall_cutout`) every frame. Two ways a unit can leave the board while STAYING in
  that array at its own stale `.cell` forever: (a) **extraction** (`MissionState.extract_unit()` sets
  `alive = false`/`extracted = true` but never clears `.cell`, and nothing in the view layer ever
  read `.extracted` before this fix — the unit's own `HitVolumeView` doesn't even get hidden,
  a separate, more visible latent issue flagged below); (b) the **debug panel's "remove object" verb**
  on a unit (`BoutInjector.remove_object` → `CombatState.kill_unit` — same `alive = false`, cell
  untouched — plus `BattleScene.remove_unit_view()`, which DOES destroy the `HitVolumeView`,
  tracked in `_removed_unit_ids`). Either way, the cutout shader keeps cutting a hole at that unit's
  last position indefinitely, with nothing visibly there to explain it — exactly the reported
  symptom. ("Not showing on the units" is very likely just describing that no *currently on-board*
  unit happens to be behind a wall from the camera's current angle right now — not itself a bug,
  though unconfirmed without seeing the bout.)
- **Fix:** `update_wall_cutout()` now skips any unit with `.extracted == true`. A new
  `BoardView.exclude_unit_from_occlusion(unit_id)` (cleared on every `build()`, so a fresh battle
  never inherits a stale exclusion) is called from `BattleScene.remove_unit_view()` — the same
  `_removed_unit_ids` moment — and checked alongside `.extracted` in the cutout feed. Pass B's own
  `BattleScene._occluding_friendlies()` (same `wall_cutout_units` list, same class of bug for the
  friendly-fade effect) got the matching `.extracted` filter too, since an extracted friendly's own
  `HitVolumeView` stays live (extraction never calls `remove_unit_view`) and would otherwise visibly
  fade as if still standing there.
- **Separate, more visible latent issue flagged, not yet fixed:** nothing in the view layer reads
  `Unit.extracted` at all outside this fix — an extracted unit's own `HitVolumeView` never gets
  hidden or specially posed, so its body may just keep standing there, fully rendered, indefinitely.
  Worth a supervisor look independent of this ticket.
- **Not yet confirmed which of the two mechanisms (a)/(b) actually produced the (2,18) hole** — both
  are now fixed regardless, but knowing which would confirm the diagnosis. Did a unit get extracted
  or debug-removed near that cell?
- **2026-07-22 (supervisor):** if extraction/debug-removal was the cause, it happened on a PRIOR
  bout, not this one — the stray hole was already present on loading into the current bout. See
  **BR32.03** below — a distinct, not-yet-investigated angle (does something carry over across a
  "New Battle" that shouldn't?), since this fix's own `_excluded_from_occlusion` is cleared on every
  `BoardView.build()` and `wall_cutout_units` is reassigned fresh from the new `CombatState.units` on
  load, so neither of the mechanisms fixed here should be ABLE to survive a bout transition as
  currently understood — worth a real look, just not yet.
### BR32.03 — Active — owner: `SUPERVISOR`
**Wall cutout carries over across a bout transition; new units get none**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22. The supervisor noticed BR32.01's own "stray culling, no unit there"
  symptom immediately on loading into the current bout — if extraction/debug-removal was the actual
  cause (BR32.01's own fix), it would have happened on a PRIOR bout, meaning something about that
  stale state survived a "New Battle" transition into this fresh one.
- **Explicitly not investigated yet, by instruction** — do not look into this until the supervisor's
  own review pass. Filed only so it isn't lost.
- **Why this looks surprising against BR32.01's own fix (not a contradiction, just unexplained):**
  `BoardView.wall_cutout_units` is reassigned fresh from the NEW `CombatState.units` on every
  `_on_battle_loaded()`, and `_excluded_from_occlusion` is cleared on every `BoardView.build()` — on
  paper, neither of BR32.01's two mechanisms should be able to survive a bout transition at all. If
  this reproduces again, that gap between "should be impossible" and "was observed" is the actual
  bug.
- **2026-07-22 (supervisor review — confirmed, promoted Suspected→Active):** reproduces. The cutout
  from the *prior* match persists into a new bout — old culling never cleared, and the new bout's own
  units get no cutout at all (the only hole visible is the stale one). So it's not just a leftover: what
  survives the transition also prevents the fresh feed from taking effect.
- **Key diagnostic — clicking "Assume Control" snaps the culls to their proper location.** So the feed
  isn't permanently broken, it's *stale until an event forces a re-read*: whatever Assume-Control does
  (re-selects/re-projects the live units) is exactly the refresh the bout-load path is missing. Same
  feed-timing family as **BR32.04** (cutout jumps to the resolved cell ahead of the move animation) —
  both are "`update_wall_cutout()` reads/refreshes at the wrong moment." The bout-load path (and unit
  spawn) needs to trigger the same re-feed Assume-Control already does.
### BR32.04 — Active — owner: `SUPERVISOR`
**Clicking Resolve snaps the wall-cutout hole to the destination before the move animation catches up**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (BR27.08 rebuild review). "On clicking resolve, cull position moves to the
  right cell immediately, while animation plays separately, splitting them."
- **Explicitly not investigated yet, by instruction — "likely a process change so just flag it for
  now."** Filed only so it isn't lost.
- **Candidate mechanism, not confirmed:** `resolve_to_marker()` resolves the queued prefix against real
  `CombatState` synchronously — `unit.cell` (and whatever `BoardView.update_wall_cutout()` projects
  from `wall_cutout_units`, a live reference into `combat_state.units`) updates the very next frame.
  The visual slide itself (`ResolutionPlayer`, driven off the `queue_partially_resolved`/`turn_ended`
  event stream) plays out separately, over multiple frames, from wherever the model's own
  `HitVolumeView` transform currently sits. If the wall-cutout shader's own per-frame feed
  (`BattleScene._process()`/`BoardView.update_wall_cutout()`) reads the unit's real, already-resolved
  `.cell` rather than the model's own currently-animated transform, the cutout hole would jump to the
  destination instantly while the model is still visibly sliding toward it — a real position, but the
  WRONG one to be reading from mid-animation. Consistent with the supervisor's own "likely a process
  change" guess: whichever `_process()` feeds the cutout's unit positions would need to read the
  animated/rendered position (or hold the old one) until the slide finishes, not the authoritative
  logical cell the instant it changes.
- **Not yet reproduced or fixed.** Needs a live look, not guessed at further here.
### BR32.05 — Active — owner: `SUPERVISOR`
**Wall cutout cuts walls that aren't between camera and unit (coarse heuristic)**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). The cutout shape mostly works, but the *shape* is wrong at
  the edges: looking at a unit with a wall **behind** them, a chunk is cut out of the top of that wall
  even though it's ordered behind the unit; and the cut exposes the interior (wall-to-wall) textures
  of each wall.
- **This is BR32.02's explicitly-deferred facet, now the supervisor's review item.** BR32.02 fixed the
  depth *source* so the cutout appears at all; this is the separate, deferred precision problem its
  report flagged: the shader's occlusion test is a coarse single-scalar heuristic — "fragment nearer
  the camera than the unit's reference depth AND within its screen-space radius" — with **no real 3D
  ray / line-of-sight check** against the camera-to-unit line. A wall merely *near* a unit (adjacent,
  or behind but close) satisfies both conditions by geometric coincidence, so walls that aren't
  actually occluding get cut. Same root as the same-side over-cutting BR32.02 deferred (multiple
  adjacent walls cut at once in a corridor).
- **Candidate fixes (from BR32.02's own analysis, not yet chosen):** a real per-fragment ray/line-
  segment test against the camera-to-unit line, or gate on the *angle* between camera→wall and
  camera→unit rather than screen-space pixel distance + a bare depth compare.
- **Interior-texture exposure** is a sub-symptom (the cut reveals unlit/placeholder wall interiors);
  it may largely resolve once the shape is corrected, and is otherwise shader-pass polish, not worth
  chasing separately before then.
### BR32.07 — Active — owner: `SUPERVISOR`
**Burst at/through a wall aims, then silently fails (no AP, no queued action)**
- **Source:** `SUPERVISOR`
- **2026-07-23 (supervisor re-check — the symptom has SHIFTED).** It is now reported as **"cannot
  seem to aim at a wall with burst"** — i.e. the aim step itself no longer engages, where the original
  report was "lets you aim the dartboard, then silently fails out." That is a different failure point,
  not a rewording: something between tb32 and now moved the failure *earlier*, from confirm/queue to
  aim. Prime suspect is tb34's targeting rework — `ShotScatter.for_shot` and the `TargetingMode`
  dispatch both sit in the burst aim path, and tb32 Pass C's `HitKind.PART` targeting is what makes a
  wall aimable at all. Re-derive the failure point before fixing; the original diagnosis (the PART
  branch of `BurstAction.is_legal()`/`apply()`) may now be aimed at the wrong seam.
- **Reported:** 2026-07-22 (tb32 review). A shot **directed at a wall or through a wall** (both cases)
  lets you aim the dartboard, then silently fails out — no AP spent, no action queued. Appears
  **burst-specific**.
- **Where to look:** tb32 Pass C made non-unit Parts targetable (`HitKind.PART`,
  `Grid.shootable_part_at`) and Pass D routed burst through `TargetingMode`. `BurstAction` legality
  now accepts a PART target, but the confirm/queue path silently no-ops for burst against a wall — the
  aim succeeds (dartboard opens) but nothing commits. Likely `BurstAction.is_legal()`/`apply()`'s PART
  branch (vs `AttackAction`'s) or the burst confirm path dropping the action. Contrast with single
  shoot to isolate. Related in spirit to BR30.11 (burst step-out silently dropping the shot) — check
  whether it's the same silent-drop seam, and whether the intent/outcome logging idea in PLAN would
  have surfaced it.
### BR32.08 — Suspected — owner: `SUPERVISOR`
**Dead or knocked-out shells may have strange cutout behavior**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). Not observed directly — flagged as a likely edge case: a
  dead or knocked-out shell may feed or interact with the wall-cutout oddly (still in
  `CombatState.units`? still fed to the cutout? faded as a friendly? left with a stale cell like
  BR32.01?).
- **Suspected, not confirmed** — logged so it isn't lost; confirm/describe at a review pass. Shares
  the unit-feed edge-case family with BR32.01 (extracted/removed) and BR32.03 (carryover).
### BR32.09 — Active — owner: `SUPERVISOR`
**Spectator: current-unit indicator jumps to the next unit before the active turn resolves**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review, direct note). In spectator, the current-unit indicator
  advances to the next unit before the active unit has finished resolving its entire turn.
- **Likely the spectator-side sibling of BR27.07's ordering bug.** tb32 Pass D fixed the *player*-view
  early-flip by deferring `apply_active_turn_highlight()` until after the resolution animation
  (`SquadControlOverlay._on_turn_ended()`), but the spectator path wasn't touched — its indicator
  still flips ahead of resolution. Apply the same defer-until-animation-finishes fix on the spectator
  overlay's turn-end handler.
### BR32.10 — Pending — owner: `SUPERVISOR`
**AI gets stuck on opposite sides of U-shaped / concave maps**
- **Source:** `SUPERVISOR`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **2026-07-23 (supervisor check — BLOCKED, not verifiable).** Cannot be checked: **BR34.06** (AI
  passes its turn in bout matches) means the AI does nothing observable in a bout, so there is no way
  to see whether approach-pathing works. Note this is the same symptom CC's own tb33 follow-up hit
  ("every unit holds every turn, the whole mission long") — which was written off as a boxed-in seed
  and now looks systemic. Re-check only after BR34.06 is fixed.
- **2026-07-23 (tb35 Pass A/B — BR34.06 marked Pending, unblocking this one too)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. `LineOfFire.closing_path` (added this pass for
  BR34.06's own second gap) is real A* to a cell next to the enemy specifically BECAUSE the greedy
  distance-scorer alternative reproduces this bug's own concave/U-shaped freeze — headless coverage
  (`test_line_of_fire.gd::test_closing_path_routes_around_a_concave_wall_instead_of_freezing`) proves
  it routes around a sealed column via a real gap rather than stalling. Live re-check in a supervised
  bout still needed before promotion — this entry stays Pending.
- **Reported:** 2026-07-22 (tb32 review; long-standing — logged now, wasn't in the ledger). On
  U-shaped / concave map geometry, opposing units end up stuck on opposite sides, unable to path
  around to engage.
- **Root is the known AI pathing gap, not a new defect.** `docs/PLAN.md` (Support & combat gaps): the
  AI does single-turn reachability, not a genuine multi-turn shortest-path-to-nearest-LOS search — so
  a concave wall between two units, where no single turn's reachable set reaches the other side, leaves
  the AI with nothing to move toward. Same family as the AI line-of-fire gap. The real fix is the
  multi-turn approach-pathing design in PLAN; this entry tracks the observable symptom against it.
- **Fix (tb33 Pass B):** when no cell reachable this turn has a real shot (`_any_reachable_has_lof`
  false), `_plan_ranged` no longer hands off to the greedy least-bad-reachable-cell scorer at all —
  `LineOfFire.approach_path` Dijkstra-floods (`Pathfinder.nearest_matching`, lazy — the real
  `ShotPlane`-based LOF check only runs on cells as they're popped) to the nearest cell that WOULD
  have a clear shot, capped at weapon range + margin, and queues a move truncated to this turn's own
  MP budget (`Pathfinder.truncate_to_budget`). The same fallback re-fires next turn, walking the rest
  of the path, until a reachable cell genuinely has LOF and the normal engagement scorer takes back
  over. This is what a concave map needs that the tb27 C1 `obstruction_count` fix (above) couldn't
  give it: a real multi-turn path to a target cell, including the step that moves farther from the
  enemy before it curves back in — the move a per-turn distance/obstruction scorer can't make no
  matter how it's weighted.
- **Verified (headless):** `test_unit_ai_lof_fallback.gd` — a concave-pocket fixture where the AI's
  queued move includes a genuine Chebyshev-distance increase before it decreases
  (`test_ai_takes_a_step_that_increases_chebyshev_distance_before_it_decreases`); the fallback reaches
  a real shot and fires within a bounded number of simulated turns
  (`test_the_approach_fallback_eventually_reaches_a_lof_cell_and_fires`); a fully walled-off enemy
  falls through to hold/end-turn instead of freezing or erroring; an open-field engagement never
  enters the fallback at all; same seed/fixture produces the same path (determinism).
- **Not live-verified** — headless-only per the taskblock's own design (no rendering needed: grid +
  `ShotPlane`). Needs the supervisor's own hands-on confirmation on a real U-shaped/concave bout
  before promotion to `RESOLVED`.

---
### BR33.01 — Suspected — owner: `SUPERVISOR`
**Aim-view scroll cycles walls; layer labels read as part names**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb33 review). Scrolling while aiming "cycles parts on a unit (or at least
  it looks that way)." The original intent: scrolling cycles between the current enemy and what stands
  *behind* it — preferably other enemies, with cover acceptable now that cover is real.
- **The mechanism is correct; the input to it isn't.** `AimController.layers_for` groups the shot
  plane by `region.body` and sorts nearest-first — one layer per distinct body, which *is* the
  intended "current enemy, then what's behind it." `ShotPlane.build` sets `region.body = unit` for a
  unit's parts and `= part` for an unowned cover Part, so grouping is genuinely body-level, not
  part-level.
- **What changed:** tb31 C turned walls into cover-`Part`s that live in the shot plane, so **every
  wall is its own body and therefore its own aim layer**. Scrolling a walled scene now cycles wall
  after wall. Compounding it, `AimView._body_name` renders a non-Unit body as its raw part id
  (`wall`, `scrap_pile`, `pillar`) — debug strings that read like part names, which is most likely
  what makes it look like part-cycling. A three-blocks-earlier change to terrain quietly degraded
  aiming; nobody connected the two.
- **Suspected, and deliberately not fixed yet.** The supervisor will observe scroll behaviour on
  tb34's finished aim view before deciding — the fix is a policy call, not a mechanism one.
  **Options when decided:** skip walls by default (cover still reachable), rank enemies ahead of cover
  regardless of depth, or collapse contiguous walls into a single layer; plus player-facing names
  instead of `unit_3` / raw part ids.
### BR34.01 — Active — owner: `SUPERVISOR`
**Every penetration/deflection hop replays the full bright hit-flash, not just the first**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (live playtest). A single queued shot that penetrates or deflects through
  several objects visually reads as multiple separate shots firing — "the bright raycast flashing
  should only play for the first hit," not for every subsequent hop of the same trigger pull.
- **Root cause, read-only investigation (quick look, not a fix):** `DamageResolver.resolve_shot`
  correctly returns one `Array[ImpactResult]` per trigger pull, one entry per hop (wall, then cover,
  then the target, say) — that's the right granularity for damage/consequence bookkeeping.
  `ResolutionPlayer.play()` (`resolution_player.gd:148`) reuses that SAME granularity directly for
  PLAYBACK: its own loop treats every `&"impact"`/`&"miss"` `LogEvent` as an independent "shot"
  (`is_shot := event.kind == &"impact" or event.kind == &"miss"`), inserting `INTER_SHOT_BREAK_MS`
  between them, and `_play_impact()` (`resolution_player.gd:440`) unconditionally calls
  `_spawn_tracer()` — the full bright-live-to-dull-fade flash — for every one of them. Nothing in
  `LogEvent.data`/`ImpactResult` distinguishes "the first hop of this trigger pull" from "hop 2+,
  the same round continuing forward" — the log's own per-hop granularity (correct for its own job) is
  being read as the playback's own per-shot granularity (wrong for this job), conflating two different
  concerns. A 3-hop PENETRATE chain from one queued attack currently plays THREE full bright flashes
  with pacing gaps between them, reading as three separate trigger pulls.
- **Distinct from BR27.02** (the backward-tracer-direction ticket) — this is about flash/pacing
  REPETITION per hop, not the direction of any single segment. Both live in the same playback/
  resolution-geometry neighborhood but are separate defects.
- **Not investigated further, no fix attempted** — logged per instruction. A real fix needs a design
  call on what SHOULD distinguish "first hit of a pull" from "continuation," which doesn't exist in
  the data today (candidate: thread a hop index/continuation flag through `ImpactResult`/`LogEvent`,
  then have `ResolutionPlayer` skip the live flash — or use a dimmer one — and skip the inter-shot gap
  for hop index > 0). That's a design/implementation question for whoever picks this up, not answered
  here.

---
### BR34.02 — Active — owner: `SUPERVISOR`
**Combat log is fully transparent but still eats clicks**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb34 review). Most of the combat log is fully transparent, yet the
  transparent area cannot be clicked through — so an invisible panel blocks board interaction. The
  supervisor's framing: **one of the two should change** — either the log gets a visible background
  (so it's honest about occupying that space), or the transparent region stops intercepting clicks.
- **Same class as BR31.01 and tb31 Pass A's `TopLeftControls` fix** — a container whose `mouse_filter`
  defaults to `STOP` swallowing input across its whole rect, including areas that render nothing.
  That's now the third instance of this exact failure; worth checking every full-rect UI container's
  filter in one sweep rather than one bug at a time.
- **Pairs with the log-window UX work in `docs/PLAN.md`** (title bar, minimize, resize, scroll
  hand-off). If that lands in the same pass, the "visible background vs click-through" decision is
  made naturally — a titled, resizable panel wants a real background, and the click question answers
  itself.
### BR34.03 — Active — owner: `SUPERVISOR`
**`AttackAction` in the move queue isn't label-pruned like `MoveAction`**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb34 review). The queue row for an attack still renders the verbose default
  form; it should read as compactly as the move rows now do — `AttackAction(unit=2)`.
- **Known pattern, already solved once:** BR27.08's follow-up work shortened the `MoveAction` queue
  label (commit "keep the queued suffix on partial resolve, short Move label"). Apply the same
  treatment to `AttackAction` — and while in there, check the remaining action types (burst, overwatch,
  repair, the melee actions) rather than fixing one and leaving the next to be reported separately.
### BR34.04 — Active — owner: `SUPERVISOR`
**Sniper camera frames the target from an odd angle**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (post-tb34 check). tb34 Pass D's sniper framing engages past 5 cells and
  does centre the target, but the viewing angle it centres *from* reads wrong.
- **Supervisor-specified intent:** the camera should sit **directly above the line drawn between
  shooter and target**, looking along it — so the shot's own geometry is what you're reading, rather
  than an arbitrary heading that happens to contain the target.
- **Why it landed this way (not a defect in the code, a gap in the spec):** tb34 Pass D deliberately
  *kept the rig's existing yaw/pitch* and only solved zoom, because this rig always faces its own
  `pan_offset` pivot — so setting `pan_offset = target.center` centres the target at any angle, and
  the taskblock only asked that it centre. CC flagged exactly this as decision 4 ("keeps the shooter
  out of its own solve entirely… computing a shooter-relative viewing direction anyway would have been
  unrequested scope"). The decision was correct against the spec as written; the spec was
  under-specified. **The fix is the shooter-relative solve that was explicitly not done:** derive yaw
  from the shooter→target vector and position above it.
- Camera math — verify by reading the built node's `global_transform`/`unproject_position` back, per
  `docs/10` rule 2, including a diagonal case (the yaw bug that rule exists for survived a full suite
  of row/column-aligned cases).
### BR34.05 — Active — owner: `SUPERVISOR`
**Misses vanish instead of striking anything**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (post-tb34 check, during the BR30.10 verification). A missed shot appears
  to travel into nothing — it strikes no obstacle at all on its way out, passing through an arena that
  is enclosed on every side.
- **Supervisor's stated rule for how this SHOULD work — a design statement, not just a repro:** a shot
  should **nearly always hit something**. The floor, or one of the many walls surrounding the arena.
  The only legitimate ways for a round to hit nothing are **through an already-broken wall** or **out
  through the ceiling**. Anything else vanishing is wrong.
- **Why this matters more than a visual nit:** it means "miss" is currently modelled as *terminate the
  round*, rather than *continue until something stops it*. That has real consequences now that walls
  are destructible and decompression is a planned hook — a missed burst that should be chewing a wall
  behind the target is instead doing nothing, and the arena never accumulates the damage a firefight
  should leave. It also interacts with **BR34.01** (per-hop playback): a miss that continues has hops,
  and hops are what that entry is about.
- Likely the same neighbourhood as tb35 Pass B's depth floor and the `&"miss"` handling in
  `ResolutionPlayer`/`shot_resolution.gd` — check whether a miss even builds a continuation ray, or
  simply stops.
### BR34.06 — Pending — owner: `SUPERVISOR`
**AI passes its turn, in bout matches only — BLOCKER**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (post-tb34 check). Every AI unit passes its turn in bout matches. The
  qualifier matters: **bouts specifically**, which is the mode used for essentially all live
  verification.
- **This blocks confirmation of at least BR32.10 and BR27.07**, and makes bouts near-useless as a
  testing surface — which is why it should be treated as the highest-priority open entry rather than
  one bug among several.
- **Strong prior hypothesis — this is probably not new, and probably not a bout-setup bug.** CC's own
  tb33 follow-up investigation reported exactly this symptom while re-measuring the BR30.10 wall-hit
  ratio: *"zero impacts in 400 turns… every unit holds every turn, the whole mission long."* At the
  time it was attributed to one enemy spawning in a geometric nook with no clean line anywhere, and
  written off as a bad seed. The same symptom appearing across bout matches generally says it is
  **systemic, not seed-specific** — and the obvious candidate is tb33's own LOF work: either
  `has_clear_line_of_fire` returns false far more often than it should (walls are dense and
  full-height post-tb31, so a strict first-hit-must-be-the-target test may almost never pass), or the
  Pass B approach fallback isn't engaging when it should, leaving the unit with nothing to do and
  holding.
- **Where to start:** log the AI's own decision per unit per turn (which branch it took, and why LOF
  said no) — the intent/outcome logging idea in `docs/PLAN.md` is exactly the tool this needs. Do not
  fix by loosening the LOF gate until the log says that's the cause; tb33's correctness fix should not
  be undone to paper over a fallback that isn't firing.
- **2026-07-23 (tb35 Pass A/B, root cause found and fixed) — RESOLVED-PENDING-CONFIRMATION**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Confirmed the LOF-too-strict half of the prior
  hypothesis, not the fallback-not-engaging half: `ShotPlane.build`'s own depth-sort
  (`shot_plane.gd:45`) has no floor at zero, by design — a region behind the ray's own origin is
  legitimately present (the aim window reads it). But `LineOfFire._first_hit_excluding`,
  `ShotPlane.resolve_projectile`, and `DamageResolver._find_next` are three independent
  "walk the depth-sorted plane, return the first match" implementations that all inherited that
  same unfloored sort with no floor of their own — so a wall many tiles BEHIND the shooter (still
  in the plane on purpose) sorted first and won almost every resolution, including
  `has_clear_line_of_fire`'s own. That's why LOF read false almost everywhere post-tb31's dense
  walls: not because real geometry blocked every shot, but because the resolver was picking the
  wrong region. Live-diagnosed on a real `BoutSetup`-built bout (not a synthetic fixture): a unit
  reading zero clear cells even with an UNCAPPED search before the fix found one real cell
  (`(27, 16)`) after it.
  - **Fix, scoped as tight as possible:** `resolve_projectile` gained an opt-in `floor_at_zero`
    parameter (default false — every existing raw/body-local-plane caller, including this file's
    own test suite, is unaffected). `self_obstruction` and `region_at` opt in; `resolve_ray`'s own
    inline loop and `DamageResolver._find_next` (both always fed a real shooter-anchored
    `ShotPlane.build` plane, never a raw body-local one) floor unconditionally.
    `LineOfFire._first_hit_excluding` likewise floors unconditionally — a THIRD parallel
    implementation of the same rect-walk, not named in this taskblock's own audit list, found and
    fixed on the same pass.
  - **Second, distinct gap found and fixed once the LOF predicate was genuinely correct:**
    `LineOfFire.approach_path` (tb33 Pass B, BR32.10's own fix) is deliberately capped at
    `weapon.max_range + APPROACH_MARGIN` — a unit starting genuinely far from the nearest real LOF
    cell (more common than expected: mission-start positions are often tens of cells apart) found
    nothing within that cap and held forever even after the depth-floor fix, since nothing was
    LEFT to fall back to. Added `LineOfFire.closing_path`: real A* toward a cell adjacent to the
    enemy, no LOF requirement — deliberately NOT a greedy per-turn distance scorer (tried first,
    reverted: it reproduces BR32.10's own concave/U-shaped-wall freeze, since a one-step
    hill-climb can permanently stall the instant no reachable cell reduces raw distance further,
    where real A* just routes around).
  - **Verified live:** a 60-turn, 6-unit `BoutSetup` bout that previously showed 100% `held` turns
    (confirmed both before AND immediately after the depth-floor fix alone) now shows real
    movement, `burst_fired`/`impact`/`part_destroyed`/`part_mangled`/kills across the whole run
    once `closing_path` was added. Headless coverage:
    `test_shot_plane.gd::test_self_obstruction_never_resolves_to_a_wall_behind_the_shooter`,
    `test_shot_plane.gd::test_resolve_projectile_floor_at_zero_is_opt_in`,
    `test_line_of_fire.gd::test_first_hit_never_resolves_to_a_wall_behind_the_shooter` (a
    reconstructed BR27.02-shaped fixture), `test_line_of_fire.gd::test_closing_path_*` (progress
    toward a far enemy; routes around a concave wall instead of freezing).
  - **A1's decision log now exists** (`AiDecisionLog.emit`, `src/logic/ai/ai_decision_log.gd`): one
    `&"ai_decision"` event per unit-turn, branch taken + fired/held + hold reason, greppable off
    `combat.log` or a `MemorySink` in tests. **Not yet done:** the two framerate dumps (aim entry,
    turn start) A1 also called for are view-layer work, not logic, and remain open; so does BR27.09
    (A3). Marked Pending, not Resolved: this needs a live bout watched by the supervisor before
    promotion, same as BR32.10/BR27.07 below.
