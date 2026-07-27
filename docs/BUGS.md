# BUGS.md — Bug Ledger

**The single place a bug's status lives.** New and resolved, with a rough report time and (for recent
ones) the taskblock in play. Its job: **a resolved bug must have a closure marker here**, so it is
never re-derived as open once the report or spec that first described it has aged out of
`reports/`'s own rolling window or been purged — this ledger (and `docs/BUGS-ARCHIVE.md` for closed
entries) is the durable record now, not whatever taskblock first found it. If you fixed something,
mark it RESOLVED here, even if the fix landed as a plain commit outside the taskblock cadence. That
out-of-cadence gap is exactly what let stale reports recur.

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
- **2026-07-23 (supervisor revision to the instrumentation spec — supersedes the offsets below).**
  The dumps landed in tb35 A1; the offsets want changing now that they exist:
  - **Turn FPS at 0 ms** — an additional dump *at* turn start, capturing the boundary cost itself
    rather than avoiding it (this is the number BR27.09 is actually about).
  - **Replace the 200 ms dumps with 2000 ms** — 200 ms proved too close to the transient to read as
    settled state; two seconds in is the honest steady-state sample.
  Keep both samples rather than replacing one with the other: 0 ms and 2000 ms together give the
  boundary spike *and* the settled rate, which is exactly the pair needed to tell BR26.02 and BR27.09
  apart.
- **2026-07-26 — the instrumentation revision above is BUILT (tb42 Pass A)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. It had sat unbuilt since 2026-07-23: `FpsDumpSink` was
  last touched in tb35 and still fired a single 200ms sample. Now two per turn —
  `context: turn_boundary` at **0ms** and `context: turn_settled` at **2000ms** — plus the aim-entry
  dump in `TacticsController._enter_aim_mode()` moved to the same 2000ms and reading the shared
  `FpsDumpSink.SETTLED_DELAY_SECONDS` rather than repeating the number.
  - **The boundary sample is emitted synchronously, with no `await` at all.** `create_timer(0.0)` or
    `process_frame` would push it a frame past the boundary — exactly the transient it exists to
    catch — and quietly turn it into a second copy of the settled sample under a different label.
    There is a test asserting it lands before anything yields.
  - `data.offset_ms` rides alongside `context` so a log reader never has to parse the prose, and a
    test pins that the settled sample has NOT arrived at the old 200ms mark.
  - **No measurement is claimed here.** This pass built the instrument only; every number in
    taskblock-42 is taken with it afterwards. **Status unchanged, and the aiming path is still
    unmeasured** — that is Pass B's job, and this entry stays `SUPERVISOR`-owned regardless.
- **2026-07-26 (tb42 Pass B — the aiming path finally has a number)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. This entry has absorbed three fixes that were reasoned
  rather than measured. The first measurement: the per-orientation-preview
  `HitVolumeView.refresh()` at `squad_control_overlay.gd:782`, which fires on **every** reticle-driven
  facing change while aiming, cost **795µs per unit per change** and now costs **267µs** (3.0×, real
  class, 30-part humanoid, 200 repeats).
  - **This does not close anything.** It is one cost on the aiming path, now smaller; nobody has
    measured what the rest of that path costs, and the supervisor has already said aiming is
    tolerable. `SUPERVISOR`-owned — **do not close from CC's side.**
  - The `fps_dump` numbers this wants comparing against are taken at taskblock-42's own hard pause,
    on a real build, not here.
- **Also requested: a live FPS counter, rendered ON TOP OF the combat log rather than logged into
  it** — a continuous readout for the supervisor's own eyes, distinct from the dumps (which exist for
  CC to grep). Tracked with the log-window UX work in `docs/PLAN.md`.
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
- **2026-07-23 (tb35 Pass A1 — the two supervisor-specified dumps built)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Both dumps this entry's own "make framerate a logged
  number" instruction called for now exist, emitting `&"fps_dump"` events into the ordinary combat
  log: **Aim FPS** — `TacticsController._dump_aim_fps()`, fired once per `_enter_aim_mode()` call
  (never per reticle nudge), 200ms later. **Turn FPS** — new `FpsDumpSink`
  (`src/view/fps_dump_sink.gd`), watching for `&"turn_start"` on `combat_state.combat_log`, wired in
  `BattleScene.load_battle()` alongside `file_sink` so it re-points on every bout regardless of
  overlay. Headless coverage (`test_tactics_controller.gd::
  test_entering_aim_mode_dumps_fps_200ms_later`, `test_battle_scene.gd::
  test_turn_start_triggers_an_fps_dump_200ms_later`) only proves the plumbing fires on schedule with
  the right context tag — `Engine.get_frames_per_second()` itself is meaningless outside a real
  running client, so the actual before/after numbers still need a live session and `out/combat.log`.
  This closes this entry's own instrumentation ask; the underlying "is aiming actually fast now"
  question stays open pending that live read.
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
### BR27.03 — Active — owner: `SUPERVISOR`
**Other shots appear to resolve before an earlier shot's own deflect finishes**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20, correcting a taskblock-27 misdiagnosis: Pass A2 had assumed a shot and
  its own deflect were wrongly paused apart and inserted a fix for that — but they're SUPPOSED to
  resolve simultaneously, that was never broken. The real, still-open defect is different: a
  DIFFERENT, later shot can appear to resolve/animate before an EARLIER shot's own deflect segment
  has finished.
- **Status:** not yet investigated. taskblock-27 Pass A2's own `DEFLECT_BEAT_MS` fix (a deliberate
  pause between a primary hit and its own deflect) does not address this bug and is itself now a
  wrong implementation of the intended simultaneous behavior — not reverted, only reclassified.
  Likely candidate: `ResolutionPlayer`'s own inter-event sequencing between separate impact events,
  not the intra-event primary/deflect pairing `DEFLECT_BEAT_MS` targeted.
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
- **Three concrete costs, measured headlessly (tb21 Pass E) — recorded here so they stop living in a
  planning doc.** Real logic and view classes timed directly, not through GUT. None of the three is
  fixed:
  1. **The combat-log UI sink reassigns `label.text` in full on every event** — ~175–180µs per call at
     a 200-line scrollback, and a real 3v3 bout averages 9.9 events per turn (peak 29), so a heavy turn
     pays ~5ms just relaying text nobody scrolled to. `HierarchicalUiSink` inherited the identical
     pattern, so it is still live. *Fix:* incremental `RichTextLabel.append_text` for the new line, plus
     a line-cap strategy other than trim-every-line. **This one gets worse the moment the planned log
     verbosity work lands** — that item's cost scales linearly with event count.
  2. **`HitVolumeView.refresh()` rebuilds every mesh and material from scratch** for the acting unit on
     every turn (~550–600µs on a 27-part unit), even on turns where nothing about its geometry changed.
     *Fix:* skip the rebuild when the turn's only events were `turn_start`/`turn_end`/`faced`.
  3. **Turn-start power recompute re-walks the same unchanged part graph 5–6 times** per `_start_turn`
     (uncached `all_parts()`/`operable_parts()`) — smaller (~175µs) but pure waste. *Fix:* compute
     `operable_parts()` once and thread it through.
  Initiative re-sort was measured and **ruled out** (~40µs per turn across a 12-unit roster) — not a
  contributor, don't re-investigate it.
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
- **2026-07-26 (tb42 Pass B — cost #2 cut, not eliminated)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. `HitVolumeView.refresh()` freed every child and
  re-instanced all of them even when only a transform had changed — which is the most common case
  there is, a unit that moved. Added `refresh_transforms()`: same nodes, new transforms.
  **Measured on a real 30-part reference humanoid (34 child nodes per view), 200 repeats:**

  | path | before | after | |
  |---|---|---|---|
  | move refresh (post-AI-batch) | 858µs | **351µs** | 2.4× |
  | orientation preview (aim path) | 795µs | **267µs** | 3.0× |

  The "before" figure corroborates this entry's own original ~550–600µs on a 27-part unit.
  - **Partial, and the remainder is named.** The teardown is gone; what is left is
    `UnitGeometry.placements()` recomposing the socket tree, which the cheap path cannot skip — it
    needs the new transforms. Removing that needs cached geometry, a larger change than this pass.
  - **The cheap path REFUSES rather than guesses.** It compares a signature of everything the node
    SET depends on (part order, per-part box counts, render path per part, downed-ness, hit-volume
    toggle) and returns false on any difference, so the caller falls back to a full rebuild. The risk
    here was never speed, it was a view that silently stops updating in a case nobody enumerated.
  - A test pins that a cheap refresh lands the scene in a state **identical** to a full rebuild, node
    for node. Writing it surfaced a real ordering defect: rebuilding the ground markers appended them
    to the end of the child list, so the two paths held the same nodes in different tree order.
    Nothing rendered differently, but "identical" stopped being literally true — fixed with
    `move_child`.
- **2026-07-26 (tb42 Pass C — cost #3 confirmed, collapsed, and it is SMALL)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Instrumented `PartGraph.walk` before changing
  anything: **exactly five full socket-tree walks per turn start** — `recharge_batteries`,
  `has_power_system`, `max_ap_for` (three internally), `discharge_batteries`, `mp_per_ap`, each
  walking independently. **This entry's own "5–6 times" was right.** Collapsed to one walk threaded
  through all of them: **117.7µs → 39.6µs per unit per turn start (3.0×)**.
  - **Say the unwelcome half plainly: this is noise next to the real problem.** ~78µs saved per unit
    per turn, against a hitch this entry now describes as *several seconds*. It is a genuine
    inefficiency genuinely removed, and it will not be felt. Cost #2 (tb42 Pass B) is ~10× larger,
    and cost #4 (the synchronous AI batch) is four orders of magnitude larger.
  - **Explicit threading, not a per-turn cache.** A cache needs invalidating on every structural
    change to the part tree, and a stale power reading is a silent wrong number rather than a crash.
    Threading has no state to go stale — the "cache invalidates on any structural change" acceptance
    is met by there being nothing to invalidate. Every existing call site is untouched: the new
    parameters default to empty and walk on demand exactly as before.
- **2026-07-26 (tb42 Pass D — cost #4: the batch yields now, and THE HITCH IS NOT FIXED)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. `advance_ai_turns` was a bare `while` loop with no
  `await` anywhere in it; it now yields a frame between units, so input is processed and the board
  draws while the batch runs, and each unit's own move becomes visible as it happens instead of the
  whole opposing team appearing to teleport at the end.
  - **The measurement that matters, and it is bad: a single `BoutRunner.step()` costs ~1672ms.**
    24 steps of a real 3v3 bout took **40.1 seconds** of pure planning. **Yielding BETWEEN steps
    therefore buys one responsive frame every ~1.7 seconds — it does not fix this entry.** The
    several-second hitch is one `UnitAI.plan_turn` call, not an accumulation of small ones, and no
    amount of yielding around it addresses that.
  - **This relocates the bug.** Costs #1–#3 are now measured and cut (5–10ms, ~500µs, ~78µs
    respectively) and together they are **under 1%** of a single step. The remaining ~1.7s/step lives
    inside `UnitAI.plan_turn` — per-candidate-cell pathfinding, LOS and cover scoring, which tb35
    Pass A3 already halved once (2023ms → 974ms per turn) by removing duplicate `ShotPlane` work and
    named the remainder as real per-cell geometry. It has since grown again. **That is the whole
    bug now, and it wants an algorithmic pass of its own, not another sweep.**
  - **Determinism verified, and it was the acceptance rather than the speed.** A seeded bout driven
    through the yielding overlay path and through a tight `BoutRunner` loop with no yielding lands
    in an identical state (`test_ai_batch_yield.gd`). `step()` draws only from `state.rng` and
    nothing on the frame path touches it.
  - **Coalescing fork, decided before implementing:** refresh only the units THAT step touched,
    after that step. taskblock-19 Pass I2's measured waste was refreshing the whole board repeatedly;
    this is proportional to what changed (usually one unit), and Pass B made each ~2.4× cheaper. The
    accumulated set still gets one final pass so the active-turn highlight lands on the real end
    state.
  - **Status unchanged — `Active`.** Three of its four named costs are closed as costs; the entry's
    actual symptom is not.
- **2026-07-27 (tb44 Pass B — the line-of-fire query inverted; ~700ms -> ~525ms per AI step)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. The planner cast from N candidate cells to one target,
  paying a real `ShotPlane.build` per candidate. It now builds **one `VisibilityField` per target per
  turn** (`src/logic/visibility_field.gd`) and each candidate's question becomes a bit test.
  `PackedInt64Array`, flat `i = x + y*W + z*W*H`.
  - **Measured, editor_debug, same bench/seeds/steps throughout:** **~686-712ms -> ~523-528ms per AI
    step (~24%)**. Exported release: **~412ms**, still ~1.29x under debug.
  - **The field is a conservative PREFILTER; `ShotPlane` stays final.** One obligation — never report
    "no line" where one exists. It therefore deliberately over-includes in three places, each costing
    a cast it could in principle have saved: cover never occludes (cover blocks shots, not sight),
    units never occlude, and any cell at a different elevation from the target is always allowed
    (occlusion data here is 2D, so it says nothing reliable about a shot passing over a wall).
  - **The occluder test is opacity AND a blocker the plane would actually resolve against**
    (`BodyProjector.projects`, extracted so there is one answer rather than two). Opacity alone would
    be genuinely WRONG: `Grid.opacity` is never cleared when a wall is destroyed, so a dead wall would
    occlude in the field while shots pass straight through it — under-inclusion, the one failure mode
    that matters. There is a direct test for exactly that.
  - **The negative case now costs nothing.** `field.allows_none(reachable)` settles "nobody can shoot
    from anywhere reachable" with **exactly zero** `ShotPlane` builds, asserted as a number rather
    than a bound. That was 19 of 60 turns in taskblock-43's census.
  - **Where the cost moved, which is Pass B4's answer and matters for Pass D.** Per repositioning turn:
    `any_lof_scan` **271.9ms -> 77.8ms**, new `field_build` **4.2ms** — but `engagement_search`
    **98.3ms -> 251.2ms**. It did not get slower; it was previously being subsidised. The old scan
    built a `ShotPlane` for nearly every reachable cell and left them in the per-turn memo, so the
    scorer ran warm. Now the scan short-circuits and the scorer pays for its own casts on the cells the
    field allows. **The remaining cost is per-candidate casts inside `_engagement_score`**, not the
    prefilter.
  - Acceptance was identical output and it holds: full suite green including `test_full_mission.gd`
    and the byte-identical seeded-bout tests. **Status unchanged, `Active`** — CC appends numbers, the
    supervisor closes.
- **2026-07-27 (tb44 Pass A COMPLETE — the release number exists, and debug overhead is NOT the story)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. The supervisor installed export templates, CC wrote
  `export_presets.cfg` (+ a committed `.example`) and `tools/bench_release.sh`, and the measurement
  this pass asks for is done. Same bench, same seeds, same steps, both builds:

  | build | ms per AI step |
  |---|---|
  | `editor_debug` (every historical figure in this entry) | ~686-712 |
  | `exported_debug` | ~665 |
  | **`exported_release`** | **~530-554** |

  - **Release is ~1.29x faster — it is not the explanation.** A hoped-for answer here was "most of the
    hitch is the harness"; it is not. Roughly 78% of the debug cost survives into a real player build,
    so **the AI planning cost is genuine** and the rebuild's urgency stands essentially unchanged.
    `candidates_skipped` was identical (2306) across all three builds, which is the cross-check that
    the same deterministic work ran in each.
  - **Getting there required fixing BR44.01** (`docs/BUGS-ARCHIVE.md`): the first-ever export of this
    project loaded **no data at all**, and presented as a bare SIGFPE with no message. Every number
    above is from a build with that fix in.
  - **Two structural things worth knowing.** An export template **ignores `-s res://...`** — it is
    tools-only — so the bench needed a main-scene entry point (`run/main_scene.bench`, activated by
    the preset's `bench` custom feature) alongside the existing `-s` one, sharing one implementation
    via `AiPlanningBench`. And `BuildIdentity` did its job: `bench_release.sh` refuses to report a
    number unless the binary itself declares `build=exported_release`, so a silent fallback to a debug
    binary cannot be mistaken for the real figure.
- **2026-07-27 (tb44 Pass A — every number in this entry came from a tools binary, and now says so)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. **The release-vs-debug measurement this pass asks for
  could NOT be taken here and no proxy was substituted.** `~/.local/share/godot/export_templates/` is
  empty and the project has no `export_presets.cfg` (it is gitignored), so `--export-release` refuses.
  The pass's own instruction on this is "say so and stop"; the exact procedure for the supervisor to
  run it locally is in `reports/Report-Taskblock44.md`.
  - **What the missing number means for this entry:** every figure above — the ~1672ms, the ~1498ms,
    tb35's 2023ms→974ms, tb43's whole bench series — was taken on an **editor/tools binary**, which
    carries GDScript's per-line debug overhead by a factor nobody has measured. **They may all be
    proportionally right and absolutely wrong.** That does not invalidate any of the A/B comparisons
    (both sides shared the build) but it does mean the absolute severity of this bug is unknown.
  - **Built instead: the provenance itself.** `src/debug/build_identity.gd` classifies the running
    build (`editor_debug` / `exported_debug` / `exported_release`) and is stamped into both
    instruments — `tools/bench_ai_planning.gd` prints it as its first line with an explicit warning
    when the build is not representative, and every `FpsDumpSink` event now carries it in `data`, so a
    framerate read out of `out/combat.log` says which build produced it. Status unchanged, `Active`.
- **2026-07-26 (tb43 Passes C+D — batches land, and they measure the block's own premise WRONG)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. `Unit.batch_id` (0 = independent), a `set_batch`
  injector verb, a round-scoped `BatchPlan` on `CombatState`, a board badge, and the planner split:
  the first member of a batch to take a turn claims the lead and pays for the full positional search,
  every later member that round reads its destination and scans a handful of cells around it instead.
  Leadership is derived, never stored — no `leader_id`, no promotion logic, nothing to desync.
  - **Pass D's stated acceptance is NOT met, and this is the block's most useful finding.** It asks
    for a follower to be "dramatically cheaper" than a leader, and says that if it isn't, "the local
    scan is too wide." Measured on `tools/bench_ai_planning.gd --batched`: **leader ~330ms, follower
    ~317ms — about 4%.** The scan is not too wide (radius 1, at most 9 cells); **the diagnosis in the
    taskblock is wrong**, and the profile says where the time actually is.
  - **`_any_reachable_has_lof` is the hog, not `_pick_engagement_position`.** Per repositioning turn
    (`--profile`, means over 60 turns): **`_any_reachable_has_lof` 271.9ms, `_pick_engagement_position`
    98.3ms** (warm cache, which is the real in-planner order), `_nearest_living_enemy` 15.0ms,
    `Pathfinder.reachable` 2.5ms. So the positional search is **~25% of a planning turn**, and
    removing it outright for followers cannot save more than that. Everything before it is paid by
    leader and follower alike.
  - **This retargets BR27.09.** Passes A, B and D all attacked the candidate search — a quarter of
    the cost — because that is where three taskblocks in a row assumed the time went. The **LOF
    prefilter scan over the whole reachable set is the actual remaining bug**, and the cheapest exact
    attack on it is ordering: it early-returns on the first cell with a clear line, and currently
    walks `reachable` in BFS-from-the-unit order rather than trying cells nearest the target first.
    Deliberately NOT built here — this block is triage with a stated scope, and an unrequested fifth
    pass on the newly-found real cause is how a scope fence stops meaning anything.
  - Branch census over the same 60 turns, which is what makes the above legible: `repositioned` 23,
    `no_lof_no_route` 15, `followed_leader` 10, `closing_fallback` 4, `fired_in_place` 5,
    `stepped_out` 2. **19 of 60 turns end with no reachable cell having a line at all**, and each of
    those scanned every reachable cell to find that out.
  - Whole-bout effect of batching one squad of three: **~671ms -> ~646ms per AI step**, two runs each.
    Real, small, and honest about being small.
  - **Status unchanged — `Active`.** `SUPERVISOR`-owned; nothing here closes it, and the per-step
    figure has not moved by anything like the order of magnitude that would.
- **2026-07-26 (tb43 Pass B — the candidate rectangle, and a repeatable bench to judge it by)**
  [CC `a56eac1a-eddb-4d30-946a-4c8e594ef198`]. `_pick_engagement_position` now scores only the
  reachable cells inside a rectangle with two corners on the acting unit and its target
  (`src/logic/ai/engagement_rect.gd`), padded 2 cells laterally and, on the far side beyond the unit,
  by the weapon's own standoff distance — the asymmetric half, without which a unit that wants to
  back off finds no candidates behind it.
  - **The numbers here are NOT comparable to this entry's earlier ones and the reason matters.**
    Every figure above came from a bench nobody kept; `tools/bench_ai_planning.gd` is now in the
    tree, fixed at 5 seeds x 12 steps of a 3v3, and every number below is from it. **On that bench:
    ~745ms -> ~674ms per AI step (~9%)**, taken twice per build. Treat the earlier ~1672/~1498ms as a
    different instrument's readings, not as a series this continues.
  - **Honest size, and the block predicted it: the rect keeps 64.9% of candidates**, mean 95.7 -> 62.1
    per decision. It does not carry this bug and was never going to.
  - **The behavioural cost, measured rather than assumed: the chosen cell differs in 7 of 60
    decisions (11.7%).** Full-suite green including `test_full_mission.gd`'s `MIN_COMPLETION_RATE`.
    Much of that 11.7% is cells that *tie* — on open ground a whole arc sits at exactly the standoff
    distance and scores identically, so dropping one changes the cell without changing the decision.
  - **The LOF scan deliberately still sees the WHOLE reachable set.** Culling before it would let a
    discarded cell flip which BRANCH runs (engagement vs. the approach fallback), a far larger
    behaviour change than picking a different cell inside the branch this pass is scoped to.
- **2026-07-26 (tb43 Pass A — exact early-out in the candidate scorer)**
  [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. `_engagement_score` walked two paths per candidate
  cell (`is_covered_from`, `_ally_in_firing_line`) regardless of how bad the cell's cheap terms
  already were. **Bound enumeration, in full, because the soundness rests on it:** every term is a
  non-negative penalty subtracted from the total — distance, obstruction, ally-blocked, min-range,
  suppression, opportunity, no-LOF — and **exactly one term can raise the score**, `cover_bonus`,
  bounded by `COVER_SCORE_BONUS` (zero when `weight_cover` is false). Dropping every not-yet-computed
  penalty therefore gives a true upper bound, and a cell that cannot beat the best complete score so
  far is skipped whole. `<=` is correct because selection is strict `score > best_score`: a cell that
  can at best tie never wins.
  - **Measured: ~1672ms → ~1498ms per AI step (~10%)**, 203 candidates skipped across 12 steps.
    Real, exact, and **nowhere near enough on its own** — the taskblock's own expectation.
  - **Acceptance was identical output, not the number.** A seeded bout produces a byte-identical
    action sequence, and a separate test asserts the skip actually fires — an early-out that never
    runs passes an identical-output test trivially.
  - Any future term that can INCREASE a cell's score must join the ceiling, or this silently starts
    choosing a different cell. Stated in the code at the branch itself.
- **2026-07-26 (tb41 Pass A — cost #1 fixed, but by coalescing, NOT by the `append_text` this entry
  prescribes)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. **Supervisor approved the override; this
  is an append, not a status change.** Cost #1's stated fix — "incremental `RichTextLabel.append_text`
  for the new line" — fits `UISink`, which genuinely is append-only. It **cannot** fit
  `HierarchicalUiSink`, which this entry itself flags as having inherited the same pattern and still
  being live: a new event there routinely rewrites an **existing** group's summary rather than
  appending a row, and expand/collapse re-renders everything. There is no correct incremental append
  against a folding model. What landed instead: `emit()` updates the model and marks dirty, and the
  label draw happens at most once per frame, driven from `ControlOverlay._process` (new
  `UiLogSink` base, shared by both sinks). Two properties `append_text` would not have given: it is
  correct for the folding sink, and **render cost stops scaling with event count at all** rather than
  merely getting cheaper per event — which is what makes tb41 Pass D's deliberate verbosity
  affordable instead of a regression. Incremental `append_text` in `UISink` alone is still available
  on top, and is deliberately **not** taken here: it should only be judged against the coalesced
  baseline, not the old per-event one.
  - **Measured, real classes against a real `RichTextLabel` in a real tree** (same posture tb21 Pass E
    used for the original figures), at this entry's own scenario — 200-line scrollback, 3v3, 9.9
    events/turn averaged, peak 29. Before = render after every emit (exactly what these sinks did),
    after = one render for the frame, 200 repeats each:

    | | peak turn (29 events) | average turn (10 events) |
    |---|---|---|
    | `UISink` before | 4845µs | 1677µs |
    | `UISink` after | **225µs** | **193µs** |
    | `HierarchicalUiSink` before | 10058µs | 3263µs |
    | `HierarchicalUiSink` after | **870µs** | **495µs** |

    The `UISink` "before" figure works out to ~167µs per event, which corroborates this entry's own
    original ~175–180µs measurement closely enough to trust the rest. **`HierarchicalUiSink` was
    never actually measured before and is roughly twice as expensive as the sink that was** — a peak
    turn cost ~10ms in the sink that is the one actually wired into both live overlays, not the ~5ms
    this entry estimated from the flat sink. Headless and a real x11 display agreed within ~2% on
    every figure, so the headless number is trustworthy for this particular cost and no GPU frame is
    needed to re-measure it later.
  - **The hitch is still there, and that is the expected result.** This entry is now a
    several-second hitch whose known mechanism is `advance_ai_turns` stepping the whole AI batch
    synchronously with no yield; the sink was ~5–10ms of it. Cost #1 is closed as a cost. Costs #2
    (`HitVolumeView.refresh()` rebuilding every mesh per turn) and #3 (turn-start power recompute
    re-walking the part graph 5–6 times) are untouched, as is the AI batch itself and the
    player-turn-end-with-no-AI-batch question. **Not resolved, not pending — still `Active`.**

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
- **2026-07-23 (tb35 Pass D — the candidate mechanism confirmed exactly, still not fixed)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Read `ResolutionPlayer._play_slide`/`_set_slide_anchor`
  (`resolution_player.gd:312-350`) directly: a move's own tween mutates `view.position`/`view.basis`
  (the `HitVolumeView` node's real, currently-animating transform) every tween step, over the slide's
  own duration. `BoardView.update_wall_cutout()` never reads that node at all — it recomputes each
  unit's own screen position fresh from `UnitGeometry.bounding_sphere(unit).center`, which is built
  from `unit.cell`, the model's own already-resolved, instantaneous cell. So the candidate mechanism
  above is exactly right: the cutout jumps to the destination the instant `resolve_to_marker()`
  mutates state, while the SAME unit's own visible body is still several tween-frames from actually
  arriving there.
  - **Fix direction (not implemented — real architectural surface, not a one-line change):**
    `BoardView` has no visibility into `HitVolumeView`'s own current transform at all today (only
    `BattleScene` holds `unit_views`); `update_wall_cutout()` needs to read the unit's own CURRENTLY
    RENDERED position (docs/00's own "read the real node back, don't re-derive it" rule, applied here)
    rather than recomputing from the logical model whenever an animation is in flight. The cleanest
    shape found by reading the code: a `Dictionary[int, Vector3]` of "current display position per
    unit," written by `_set_slide_anchor` every tween tick (it already computes the exact anchor
    needed) and consulted by `update_wall_cutout()` before falling back to the logical
    `bounding_sphere` position for a unit that isn't mid-animation. Not implemented this pass —
    correctly scoping the override's own lifecycle (when it's cleared, so a stale display position
    can't itself become a new staleness bug) wants its own careful pass, not a rushed one at the tail
    of an already-long taskblock.
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
- **2026-07-25 (tb40 Pass C — elevation diagnosis, reasoned from shader source, not run; no fix, per
  the pass's own scope)** [CC d0685fa0-63d7-4f3e-b29b-f52886a5e0bc]. Read `wall_cutout.gdshader`'s
  `fragment()` and `BoardView.update_wall_cutout`/`WallLegibility.pixel_radius_for_tiles` end to end
  against two named cases (unit on level 3, wall at level 0 in front and below, genuinely occluding —
  should cut; unit on level 0, wall at level 3 behind them, occluding nothing — should not cut).
  **Same root cause as the rest of this entry — no real ray/line-of-sight test — but elevation opens a
  genuinely new way for the SAME coarse heuristic to misfire, not just a bigger blast radius on the
  existing same-side over-cut:**
  - **The depth gate (`frag_depth >= unit_depths[i]` → skip) is itself already elevation-correct.**
    Both sides of the compare are real 3D Euclidean distances (`length(view_pos.xyz)` reconstructed
    from the hardware depth buffer on the shader side; `camera_position.distance_to(bounding_sphere(
    unit).center)` on the GDScript side, and `bounding_sphere` already reads `unit.height` — real
    elevation, not a flattened ground-plane read). Nothing here assumes a flat map.
  - **Case 1 (should cut) is not newly broken by elevation.** A fragment that is genuinely ON the
    camera-to-unit ray projects, by definition, to very nearly the SAME screen position as the unit
    itself — screen-space proximity is not a flat-map assumption, it's true of any real 3D projection
    regardless of height. Reasoned through; no failure mode found here.
  - **Case 2 (should not cut) exposes a case the depth gate cannot catch once height varies.** On a
    flat map, "positioned behind the unit relative to the camera" and "farther from the camera in
    Euclidean distance" are the same condition, because everything sits near one shared height — so
    the depth gate has always doubled as a correct "is this wall really between camera and unit" proxy
    *for that reason*, not because it's a real occlusion test. Once a wall can be elevated far above a
    low unit, that equivalence breaks: a wall that is horizontally BEHIND the unit (farther along the
    ground-plane line from camera through unit) can still be Euclidean-NEARER to an elevated camera
    than the low unit is, purely because it sits closer to the camera's own altitude — geometry no
    flat map can produce. `frag_depth >= unit_depths[i]` then evaluates false (wall reads as nearer),
    the screen-space radius check is the only remaining gate, and `WallLegibility`'s own doc comment
    already concedes that gate was sized for "the tactical camera sits well above and back... a wall
    within N world units of that [camera-to-ground-unit] ray almost never fires" — a premise about
    where walls and units sit relative to the camera that elevation is specifically what breaks.
  - **Conclusion: do not open a new BUGS.md entry** — the fix (a real ray/line-of-sight test, or
    gating on the angle between camera→wall and camera→unit, both already named above as candidate
    fixes) is the same fix this entry already wants; elevation just adds one more concrete geometry
    that motivates it, worth having on record for whoever picks the candidate fixes.
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
- **2026-07-23 (tb35 Pass C — re-derived the failure point, found no code-level break)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Traced the full aim-entry chain for a burst-armed click
  on a wall cell end to end: `TacticsController.click_cell` → `PartPicker.hit` (`HitKind.PART`) →
  `_enter_aim_mode` → `aim_state()` → `AimController.resolve()` → `ShotScatter.for_shot()`. Every step
  is generic over action id — `ActionCatalog`'s own `&"burst"` entry gets the same `TargetingMode.
  BOARD` as `&"shoot"`, `_click_part()` dispatches on `armed_action != null` alone, and
  `ShotScatter.for_shot()` never even receives the `AimTarget`, only `target_cell`/`weapon` — it
  cannot distinguish a wall target from a unit target and has no code path assuming a live `Unit`.
  The one place action id is read in this whole chain (`AimController.recoil_bound_radius`) only
  gates a cosmetic ring overlay, guarded against a null/empty case, and cannot block aim entry.
  **New headless regression, confirmed passing:**
  `test_tactics_controller.gd::test_arming_burst_and_clicking_a_wall_enters_aim_mode` — arms burst,
  clicks a real wall-blocker cell, asserts `aiming_at != null` and `aim_state()` non-empty. Passes
  cleanly. **Not fixed, because nothing reproducibly breaks at this level** — if the live symptom
  persists, it likely lives outside the `TacticsController`/`AimController`/`ShotScatter` chain (a
  render-layer/raycast issue in the real click path, or `PartPicker`'s own collision setup against
  live `BoardView` scene nodes — the same class of headless-vs-live gap BR27.08 hit) rather than in
  the targeting logic itself. Recommend a live re-check before further investigation here; stays
  Active, not Pending, since no fix was made.
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
- **2026-07-23 (tb35 Pass B2 — root-caused and reproduced, not fixed)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. `resolve_shot` does build a real continuation — the
  question was never "does it try," it genuinely finds nothing to hit in some cases. Reproduced
  directly: fired hundreds of simulated shots (`DamageResolver.resolve_shot`) from a unit standing in
  a fully-walled room (real `grid.blockers` Parts on every perimeter cell, both a hand-built room and
  real `BoutSetup`-generated maps) with a wide range of aim points. At an ordinary/tight lateral
  offset (|x| under ~1 unit — the range any single weapon's own authored scatter ring realistically
  produces), **zero** shots vanished, before or after this taskblock's own depth-floor fix — so this
  is a genuinely different defect from BR34.06/BR27.02, not the same one re-surfacing. Once the
  lateral offset is pushed wide (|x| beyond ~4-5 units), misses start appearing reliably (56/200 at
  |x| up to 8) — **`ShotPlane.build` projects each wall cell as its own independent rect; adjacent
  cells' projected rects are not guaranteed to tile edge-to-edge from an arbitrary shooter angle, so a
  sufficiently wide lateral offset can thread a real gap between them and pass clean through, even
  though the room is genuinely enclosed.**
  - **Why a real weapon can reach that range:** a burst's own scatter widens per pull
    (`RecoilResolver.widen`, `factor = 1.0 + resolved_step * recoil_step`) — a late pull in a long
    burst (the chaingun bursts logged elsewhere in this file routinely run 20-30 pulls) can multiply
    the base outer ring (chaingun: `0.6`) several times over, and `RangeModel.dartboard_radius_scale`
    widens it further at long range (up to `1.0 / ACCURACY_FLOOR ≈ 2.86x`). The two compound: a late
    pull of a long burst fired at range is exactly the shape of shot most likely to reach the lateral
    offsets that expose this gap — and exactly the shape of shot ("the most recent chaingun bursts")
    this ledger already has several live reports about.
  - **The supervisor's own "or the floor" half of the design rule has no geometry to hit at all** —
    `ShotPlane.build` only ever projects `state.units` and `state.grid.blockers`; there is no modeled
    floor/ground-plane Region anywhere in this system. That half of the fix is a real feature gap, not
    a bug in existing code.
  - **Not fixed this pass — needs a design call, not an invented number.** This touches `ShotPlane`/
    `BodyProjector`, the shared geometry every single shot in the game resolves against; three
    directions, not picked between: (a) make adjacent same-material blocker cells project as one
    contiguous rect run instead of independent per-cell boxes, closing the seam at the source: (b) cap
    dartboard scatter radius (post-recoil, post-range-widen) at some bound that guarantees plane
    coverage — a real balance number, not this session's to invent; (c) add a genuine floor Region so
    at least the "hits the floor" half of the design rule has something to resolve against. Flagging
    for supervisor/design input rather than guessing.
### BR35.01 — Active — owner: `CC`
**`PartPicker.hit` scans every `grid.blockers`/`field_items` entry on every hover, not just ones near the ray**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23 (tb35 Pass C, `Grid.blockers` audit sweep). `PartPicker.hit()`
  (`part_picker.gd:40,48`) iterates every entry in `grid.blockers` and `grid.field_items`
  unconditionally, running a full per-box ray test (`_nearest_t`) against each one regardless of the
  ray's own direction or distance from it. Before tb31 C, `blockers` held a handful of scattered cover
  props — cheap to fully scan. Now it holds every wall cell on the map (confirmed: real generated
  bouts run 200+ blocker entries), and this runs on **every mouse-move**, not just clicks
  (`TacticsController.update_hover()` calls `_cell_at()` → `PartPicker.hit()` on hover, per its own
  doc comment) — a real, newly-introduced per-frame cost, not hypothetical.
- **Not fixed this pass.** The safe fix (march only cells the ray plausibly crosses — a bounded
  grid-DDA walk along the ray's own 2D projection, the same shape `LoS.has_los` already bounds its own
  opacity walk to) touches core picking geometry with a real risk of silently skipping a genuine hit
  if the bound is gotten wrong, and this codebase has already been burned once by a plausible-looking
  formula nobody could verify without a live client (docs/00's own attack-camera yaw story). Flagging
  rather than guessing at a fix under time pressure.
- **2026-07-26 — NOT addressed (tb42 Pass E)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Named in
  the pass as a companion item and deliberately left: `PartPicker.hit` still scans every
  `grid.blockers`/`field_items` entry per call. Stated rather than quietly dropped — it is `CC`-owned
  and small, and belongs to whoever picks this up next.
### BR35.02 — Active — owner: `CC`
**Spectator's tile-inspect click can silently resolve to a cell hidden behind a wall**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23 (tb35 Pass C, view-layer `Grid.blockers` audit sweep). `SpectatorOverlay`'s
  tile-inspect path (`_unhandled_input`) resolves a click via `BoardPicker.cell_at_ray` — pure
  `y == 0` ground-plane math with no geometry/occlusion awareness at all. Before tb31 C, cover was
  short and sparse, so a ground-plane hit reliably matched the tile the camera could actually see. Now
  walls are 2.4m tall and dense; a click that LOOKS like it's on a wall's face, or on an open tile
  actually hidden behind a wall from the camera's own angle, still resolves via blind plane math to
  whichever cell the ray crosses at `y=0` — which can be a cell on the far side of the wall, never
  visible at all. The only existing filter excludes the resolved cell if IT ITSELF is a wall tile; it
  does nothing for a resolved open tile that's occluded by an intervening one.
- **Not fixed this pass.** Needs a real line-of-sight/geometry check between the camera and the
  resolved cell (or a real physics/geometry raycast against the wall meshes `BoardView` already
  builds) before trusting `BoardPicker`'s own result — a genuine new check, not a one-line guard, and
  risky to improvise without live verification.
### BR35.03 — Pending — owner: `CC`
**Every debug-panel verb rebuilds the entire board view, not just ones that touch blockers/field items**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23 (tb35 Pass C, view-layer `Grid.blockers` audit sweep). `SpectatorOverlay.
  _on_debug_panel_applied()` calls `battle.sync_board_view()` (a full teardown/rebuild of every
  static mesh — walls, field items, indicators) after **every** debug verb, including ones with no
  possible effect on board geometry (`set_ap`, `set_mp`, `force_current_unit`, ...). Before tb31 C
  this rebuilt a handful of props each time; now it rebuilds hundreds of wall meshes on every single
  debug action regardless of relevance. Debug-build-only (`OS.is_debug_build()`), so the blast radius
  is limited, but it's a real, newly-heavier cost every time.
- **Not fixed this pass.** The fix is straightforward in shape (gate the rebuild to verbs that can
  actually touch `grid.blockers`/`field_items` — `move_object`/`spawn_object`/`remove_object`) but
  getting the verb-id list exactly right (not missing one that can add/move/remove a blocker or field
  item) wants a careful pass of its own rather than a rushed guess at the end of an already-long one.
- **2026-07-26 — `Pending` (tb42 Pass E)** [CC `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`]. Both overlays'
  `_on_debug_panel_applied` called `sync_board_view()` — a full `BoardView.build()` of terrain, grid
  lines, every blocker and every field item — after **every** verb, including the ~20 that only ever
  touch one unit's AP, facing, pose or parts. `DebugVerbs.affects_board()` is now the one authority
  both overlays read; the same question answered separately in two files is how they drift.
  `move_object`/`remove_object` stay in the list unconditionally: either can target a cell or a unit,
  decided at call time, and a missed board rebuild is invisible-until-noticed while an extra one is
  merely slow.
  - A test checks the list against `DebugVerbs.all()`, and immediately earned it: my first draft
    listed `place_cover`/`clear_cover`, which are **not** panel verbs (the panel exposes
    `spawn_object`/`remove_object`, which front both). They matched nothing and would have quietly
    misled the next reader.
  - **To confirm:** open `Inject...`, apply a unit-only verb (Set AP, Set Facing), and check the board
    does not visibly rebuild; then apply Set Cell Level or Spawn Object and check it does.
### BR35.04 — Active — owner: `SUPERVISOR`
**A DEFLECT's drawn "bounce" tracer is a decorative fixed-range projection, not the real continuation**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **2026-07-23 (supervisor observation — independently seen, and a decision made).** Observed live as
  *"some drawn deflect raycasts are blue"* — the same defect from the visual side that this entry
  found in the log. The blue segments are exactly these decorative fixed-range projections; the real
  continuation, when one exists, is a separate `stop_dead` ray drawn independently.
- **Supervisor's call: remove the decorative projection entirely.** Do not try to make it agree with
  the real resolution — draw only geometry that corresponds to something that actually resolved.
  A tracer nobody can distinguish from a real hit, drawn to an arbitrary distance, is worse than no
  tracer: it invented the "wall impacts" the supervisor spent a whole review session investigating.
  **Owner promoted to `SUPERVISOR`** — the fix is visual, so closure needs a live look.
- **See also BR35.07**, the same class of defect on the `STOP_DEAD` tracer (drawn past its own hit
  point). Filed separately per the supervisor's own rule that one entry tracks one observed symptom.
- **Found:** 2026-07-23, reading a real chaingun burst out of `out/combat.log` at the supervisor's own
  request. Every `DEFLECT` outcome logs a `deflect_end_x/y/height` (`shot_resolution.gd:225-232`),
  drawn by `ResolutionPlayer._play_impact` as a second, visually distinct segment
  (`resolution_player.gd:457-478`) — but that endpoint is `hit_point + reflected_dir * void_range`,
  where `void_range` is just the weapon's own authored max range (or the map's longest side,
  unauthored) — **a fixed-distance projection with zero awareness of whether anything is actually
  there.** The code's own doc comment says this is deliberate: drawn "regardless of whether a real
  ricochet hop happens to follow it." Meanwhile `DamageResolver` separately does a REAL recursive
  search along that same reflected direction, and when it finds something, that's its own
  independent, correctly-resolved `impact` event (a `STOP_DEAD`/`PENETRATE`/etc. a few lines later in
  the log) — with its own separately-drawn tracer.
- **The two are drawn as if they agree; they usually don't.** On a real burst read from the log: a
  deflect at (24.91, 4.01) had a REAL follow-up wall hit only ~3.7 units further on, at (25.65, 0.43)
  — but the cosmetic bounce line was drawn a full 12 units out (the chaingun's own max range) in the
  same direction, sailing straight through/past the real wall with no awareness it was there. Two
  visually distinct tracers, same origin, same direction, different endpoints, both drawn as if
  each were the truth. For pulls where the real recursive search found NOTHING (most of them, in
  that same burst), the "wall impact" the supervisor visually saw was **purely the decorative
  projection** — no wall actually took damage there, nothing mechanical happened at that point at
  all; whether it visually reads as a hit is coincidence.
- **Why this matters more than a visual nit (supervisor's own framing):** visible raycasts need to
  match under-the-hood behavior as closely as possible, specifically *because* CC's own debugging
  process depends on reading the log and reasoning about what the drawn scene must have looked like —
  a drawn tracer that routinely disagrees with the mechanically-resolved outcome breaks that
  correspondence, the same class of problem the whole `docs/00` "read the real node back" rule exists
  to prevent, just on the logging/replay side instead of the geometry side.
- **Not fixed yet.** Candidate fix: when the real recursive search succeeds, draw the bounce segment
  to THAT hit's own real coordinates (already logged as its own event) instead of the fixed
  `void_range` projection — the cosmetic projection should only ever be the fallback for the case
  where the recursive search genuinely finds nothing, mirroring `log_miss_result`'s own "void" ray
  exactly, not a separate always-drawn distance regardless of a real hit existing.
### BR35.05 — Active — owner: `CC`
**`approach_path`/`closing_path` have no ally-awareness — squadmates converge into each other's own line of fire**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23, reading a real bout's own `out/combat.log` at the supervisor's own request
  ("units that are close all holding action"). On turn 0, units 1/2/3 (all sharing a similar start
  position and the same target) independently compute nearly identical `closing_fallback` paths —
  unit 1 and unit 3's own move sequences share the corridor `(6,14)→(7,13)→(7,11)→(11,7)` cell for
  cell — and end up bunched close together: unit 1 at (13,7), unit 3 at (13,8), **directly adjacent**.
  Unit 0's and unit 2's own `ai_decision` lines log `held: ally_in_line` — a squadmate is standing
  in their own intended shot.
- **Root cause:** `LineOfFire.approach_path` (tb33) and `LineOfFire.closing_path` (tb35 Pass A, this
  session) both compute "the nearest cell that gets a shot" (or "the nearest cell that closes
  distance") purely from grid/LOF geometry — **neither has any notion of where other allies already
  are or are heading.** `closing_path` inherited this blind spot from `approach_path` rather than
  fixing it. When several squadmates share a similar starting position and target, they independently
  converge on the same corridor/destination and end up close enough to block each other's own shots,
  which then makes every one of them hold.
- **Not fixed yet.** A real fix (giving the fallback pathing awareness of cells allies already occupy
  or are heading toward, so a squad spreads out instead of stacking) is a genuine design question —
  how much to weight "don't stack with an ally" against "get to a real shot as fast as possible" —
  not a one-line patch, and not guessed at here.
### BR35.06 — Active — owner: `CC`
**A unit with a real available shot elsewhere can still get stuck holding a covered, blind position**
- **Source:** `CC`  ·  **CC session:** `16507d21-1035-4b1c-a0fe-72a911df7403`
- **Found:** 2026-07-23, same log read as BR35.05. Unit 7 logs `repositioned (held: no_clear_lof)` on
  three consecutive turns (1, 2, 3) — `repositioned` means `_any_reachable_has_lof` found SOME
  reachable cell with a real shot this turn, yet the unit still resolves to a blocked position and
  holds anyway, turn after turn, making no progress. Unit 6 shows a compound case of the same family
  (`no_lof_no_route (held: ally_in_line)`, repeated across all three turns too).
- **Suspected mechanism, not confirmed:** `_engagement_score`'s own `COVER_SCORE_BONUS` can outscore
  the distance/LOF terms for a cell that's covered but blind, and `cell == self_unit.cell` is exempt
  from `NO_LOF_PENALTY` ("staying put is free") — so a unit already sitting somewhere covered has no
  scoring pressure to ever step into the open for the shot a `repositioned` branch says exists
  elsewhere. Consistent with, but not yet proven against, the actual per-candidate scores.
- **Not fixed yet.** Needs the actual `_engagement_score` breakdown for unit 7's own candidate set on
  one of these turns before concluding this is really the cover-bonus/self-exemption interaction and
  not something else — flagged rather than guessed at further.

### BR35.07 — Active — owner: `SUPERVISOR`
**`STOP_DEAD` tracers are drawn past their own hit point, reading as a penetration that never happened**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb35 review, live). A drawn `STOP_DEAD` ray continues visibly *beyond* the
  point where it actually stopped, so a round that was halted dead reads on screen as though it
  punched through and carried on.
- **Same class as BR35.04, different outcome type:** tracer geometry drawn from something other than
  what the resolver actually produced. Where BR35.04 is a deliberately decorative fixed-range
  projection on `DEFLECT`, this is a `STOP_DEAD` segment overshooting its own resolved endpoint —
  worth confirming whether it shares the same drawing path (`ResolutionPlayer._play_impact`) and the
  same "draw to a distance, not to the hit" habit, or is a separate length/endpoint error.
- **The reason this matters beyond looks:** it makes the two outcomes visually indistinguishable.
  `STOP_DEAD` and `PENETRATE` are mechanically different results, and if a stopped round is drawn
  like a penetrating one, the player cannot read what their weapon actually did — the same class of
  harm as the dartboard understating spread (tb34): the display teaching a rule the sim doesn't
  follow.
- Filed separately from BR35.04 per the supervisor's own convention — one entry per observed symptom,
  cross-linked, rather than bundling by shared root.

### BR35.08 — Active — owner: `SUPERVISOR`
**Detonations are invisible — nothing is drawn when an explosion resolves**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (tb35 review, live). A detonation resolves mechanically but draws nothing
  at all, so neither the fact of the explosion nor its extent is visible.
- **Supervisor-specified presentation (a spec, not a suggestion):** draw a **translucent red sphere**
  originating at the detonation point that **grows outward**, its **final radius matching the actual
  explosion radius** — so the visual is a readout of the real mechanical extent, not decoration —
  then **fades out**.
  - **Grow : fade time ratio is 1 : 3.**
  - **Total time is exposed as a tunable in the same place bullet timing lives**, defaulting to
    **1000 ms**.
- **Read the radius from the resolved detonation, never a parallel constant.** The whole value here is
  that the sphere teaches the player the real blast extent; a separately-authored visual radius that
  drifts from the mechanical one would be BR35.04's mistake again in a new place — a drawn thing that
  looks authoritative and isn't.

### BR40.01 — Active — owner: `CC`
**Attack-camera framing can end up looking THROUGH the shooter's own standing platform when the
shooter is elevated on a small platform and the target is below**
- **Source:** `CC`  ·  **CC session:** `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`
- **Reported:** 2026-07-25 (tb40 Pass D, discovered building checkpoint 8's own loadable scenario —
  not something Pass B's headless height-delta matrix could have caught: that matrix checks only
  whether both bounding SPHERES fit inside the FOV cone, with no scene geometry in the harness at all
  to occlude against. `checkpoint_8.gd`'s scenario B is a real render, with a real platform.)
- **Repro:** `./checkpoint.sh 8` → `b_target_below.png` (shooter on a 3x3 platform at level 3, cell
  (5,3); target on the ground at level 0, cell (1,3); a real wall at (3,3)). The rendered frame shows
  almost nothing but a huge, near, blank green expanse — no wall, no target, no drop-off — filling
  the whole visible area.
- **Root cause, confirmed numerically** (reproduced the exact solve standalone):
  `CameraOrbitState.attack_framing(shooter, target)` for this pair solves `camera_pos = (8.49, 3.6,
  2.1)` — **x=8.49, well past the platform's own far edge (the platform only spans x in [4,6])**,
  because `_solve_back` pushes the camera backward along the shooter->target line far enough to fit
  both bodies' angular footprint, with no awareness that "backward" here walks the camera clean off
  the platform the shooter is standing on. The platform's own solid mass — quite close to the camera
  now, and directly on the line toward the target — fills the frame. `_both_fit`'s own fit check
  still reports true throughout, correctly, because it only tests each SPHERE's angular footprint
  against the FOV — it has no concept of intervening solid terrain at all, on a flat map or this one.
  This is a real gap in the solver, not a mock/scenario artifact: any elevated stand small enough for
  `back` to walk the camera past its own edge would reproduce this in real play, not just this
  fixture.
- **Not fixed.** Out of taskblock-40 Pass D's own scope (build a loadable scenario + checklist, not a
  camera fix) and out of Pass B's own scope too (Pass B's fence was "fix the vertical anchor if the
  numbers show a problem" — this isn't an anchor-height problem, it's a missing occlusion/terrain
  awareness the anchor fix wouldn't touch). Candidate fix directions, not chosen: cap `back` at the
  shooter's own platform extent (clamp the search's `hi` to stay within the shooter's floored area,
  where knowable), or a real occlusion check against `Grid.blockers`/placed `Surface`s alongside the
  angular fit — the same class of fix BR32.05 already wants for the wall cutout, possibly shareable.

### BR40.03 — Active — owner: `SUPERVISOR`
**Scattered cover generates at level 0 inside raised rooms — each cover object sits at the bottom of
its own one-tile pit punched through the raised floor**
- **Source:** `SUPERVISOR`  ·  **CC session:** `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`
- **Reported:** 2026-07-26, post-taskblock-40, from looking at real generated maps. "Cover items are
  generating at 0 level, not up on top of lifted terrain."
- **Root cause, confirmed by re-running `MapGen.generate()`'s own steps in order with a level
  snapshot between each** (same private statics, same order, nothing simulated):
  `MapGen._repair_stranded_elevation` (`map_gen.gd:248`) floods with a real `Pathfinder` and flattens
  every unreached `OPEN` cell back to level 0. `Pathfinder._base_cost` (`pathfinder.gd:85`) returns
  `-1.0` for **any cell carrying a live blocker** — so every cell `_scatter_cover` (`map_gen.gd:426`,
  which runs first, at `map_gen.gd:80`) just dropped a crate/pillar/forklift on is *by construction*
  outside the reachable set, and gets `set_level(cell, 0)`. `_emit` then places that cell's
  `ship_floor` `Surface` at height 0, and `BoardView._spawn_blocker`/`_build_terrain` faithfully draw
  both the floor and the cover object down there — a `LEVEL_HEIGHT` (1.0) deep hole in an otherwise
  flat raised floor, with the cover item at the bottom of it. The view layer is innocent; the map is
  genuinely authored that way.
- **The pass is conflating two different questions.** Its documented job (its own doc comment) is
  "a raised room whose only ramp approach got sealed by cover shouldn't stay raised and stranded" —
  that requires flooding *with* blockers, which is correct and deliberate. But "a cell a mover cannot
  stand on" and "a cell that is stranded" are not the same question, and the blocker's **own** cell
  always answers the first one `false` for reasons that have nothing to do with connectivity.
- **Scale (40 seeds, 32×24 — `BoutSetup`'s own map size):** 30/40 maps author at least one raised
  room. **870 raised cells are flattened by this pass; 716 of them (82%) are cells that carry a
  scattered cover blocker.** Counting the visible symptom instead — a level-0 floored cell with 3+
  orthogonally raised neighbours — **483 of 2882 cover cells sit in such a pit, and *zero* cells with
  neither a blocker nor a spawn marker do.** Nothing else sinks. `_ensure_spawns_connected`'s own
  forced-corridor fallback (the other thing in `generate()` that can flatten terrain) fired on 0/40
  seeds and is not a contributor.
- **Same root cause as `BR40.04`** (spawn/extraction cells recessed) — one fix very likely closes
  both, but they are filed separately because the symptoms and the gameplay consequences differ and
  each wants confirming on its own.
- **Not fixed** — no fix attempted; reported for a call on direction first (CLAUDE.md: ask, don't
  invent). Candidate directions, none chosen: (a) exclude blocker-carrying cells from the *flatten*
  decision and give each one whatever level its own reachable neighbours ended up at, in a second
  pass — this keeps the sealed-room case working (the room behind the blocker is still unreachable
  and still flattens) while stopping the blocker's own tile from punching a hole, and it correctly
  lowers a cover object along with its room when the room really does get flattened; (b) flatten by
  *region* rather than per cell, so a single unstandable tile inside an otherwise reachable area is
  never treated as a stranded island. Naïvely re-flooding without blockers is **not** a fix — it
  would report a cover-sealed raised room as reachable and defeat the pass's whole purpose.
  `docs/PLAN.md`'s queued "Review pass over map generation" item is the natural home.

### BR40.04 — Active — owner: `SUPERVISOR`
**Extraction/spawn tiles recessed to level 0 inside raised rooms — and a unit that spawns on one can
be permanently immobilised**
- **Source:** `SUPERVISOR`  ·  **CC session:** `d0685fa0-63d7-4f3e-b29b-f52886a5e0bc`
- **Reported:** 2026-07-26, post-taskblock-40. "Extract tiles that spawn without a unit atop them are
  recessed down to 0 level."
- **Root cause: the same `_repair_stranded_elevation` flatten as `BR40.03`, plus an ordering
  detail.** `_scatter_cover` (`map_gen.gd:80`) can drop a blocker on a cell that becomes a spawn zone
  a moment later; `_repair_stranded_elevation` (`map_gen.gd:88`) then flattens that cell to level 0
  because the blocker makes it unreachable; and only *afterwards* does `_place_spawn_zones` →
  `_mark_zone` (`map_gen.gd:90`, `map_gen.gd:531`) erase the blocker — deliberately, so spawns are
  guaranteed clear. The blocker goes away; **the level-0 flattening it caused does not.** What is left
  is a clean, empty, correctly-marked spawn/extraction cell sitting a full `LEVEL_HEIGHT` below the
  rest of its own raised room. `BoardView._build_extraction_tiles` draws the team-coloured marker at
  that cell's real floor height, so the marker is exactly where the map says it is — recessed.
- **The "without a unit atop them" qualifier is a visibility artifact, and the occupied case is the
  worse one.** `CombatState`'s constructor (`combat_state.gd:125`) sets `unit.height` from the same
  `UnitGeometry.true_height_for_cell`, so a unit spawned on a sunk tile sinks *with* it and its body
  hides the marker — the tile only *reads* as recessed when nothing is standing on it. Both cases are
  the same defect.
- **Gameplay consequence — a unit can spawn unable to move at all.** The pit is exactly one level
  deep, climbing is capability-gated on `Shell.can_climb()` (`shell.gd:105`, an open `CLIMBER` part
  tag), and **no part anywhere in the repo carries `CLIMBER` today** — so no unit that currently
  exists can climb out of anything. Asking a real non-climbing `Pathfinder` what a unit standing on
  each sunk spawn cell can reach: **seeds 17, 18 and 38 return exactly 1 cell — the one it is standing
  on.** Seed 32 returns 2 (the two sunk cells, both spawn tiles). It is a sealed hole, and the unit
  spends the whole battle in it. Hop-down *into* the pit is legal, so the tile still works as an
  extraction target; it is the spawning unit that is stuck.
- **Scale (same 40-seed, 32×24 sweep):** 8 of 80 spawn zones (10%) come out with non-uniform floor
  heights — always one or two of the four cells at 0.0 with the rest at 1.0. Which of the four sinks
  is uncorrelated with whether a unit spawns there (`BoutSetup._spawn_squad` takes cells in reading
  order): 4 of the 8 sank a cell a 2-unit roster would occupy, 4 sank one it would not.
- **Same root cause as `BR40.03`.** A fix there very likely closes this too. If it does not, the
  narrower fix available here is ordering — running `_place_spawn_zones` (which already erases spawn
  blockers) *before* `_repair_stranded_elevation` would make spawn cells blocker-free at flood time —
  but that only addresses spawn cells, leaves `BR40.03` untouched, and reorders a sequence whose
  current order is itself load-bearing and documented, so it is not obviously the right lever.
- **Not fixed** — no fix attempted; reported for a call on direction alongside `BR40.03`.
