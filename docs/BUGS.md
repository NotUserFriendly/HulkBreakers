# BUGS.md — Bug Ledger

**The single place a bug's status lives.** New and resolved, with a rough report time and (for recent
ones) the taskblock in play. Its job: **a resolved bug must have a closure marker here**, so an old
report — still readable in `taskblock_done/`, still describing acceptance criteria — is never
re-derived as open. If you fixed something, mark it RESOLVED here, even if the fix landed as a plain
commit outside the taskblock cadence. That out-of-cadence gap is exactly what let stale reports
recur.

**Convention:** newest at the top of each section. Recent entries get a timecode + taskblock; older
migrated ones get a rough date. `RESOLVED` entries name the fixing commit(s)/taskblock so the closure
is verifiable.

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
scratchpad`). CC stamps its closure marks with that UUID — the short prefix is enough to read at a
glance (e.g. `RESOLVED-PENDING-CONFIRMATION [CC 83fb8082]`). If CC is refreshed it gets a *new* UUID,
so a later session reading an earlier session's `PENDING-CONFIRMATION` sees a **different** stamp than
its own — that's the signal it's *another instance's* unverified claim. It must NOT promote it to
`RESOLVED` on the strength of a prior CC's word, only on the supervisor's. A pending mark whose UUID
isn't your current one is a claim to re-check, not a closure to trust.

**End-of-taskblock digest.** At the end of each taskblock, CC lists every `SUPERVISOR`-sourced bug
it moved to `RESOLVED-PENDING-CONFIRMATION` this block — a "here's what I think I fixed, please
confirm" roll-up — so pending items surface at a natural review point without interrupting mid-work.

---

## ✅ Resolved

### Resource Editor — four layout bugs (stale-report source)  ·  source: `SUPERVISOR`
- **Reported:** recurring through 2026-07-20 (arrived repeatedly as a `## User Request` to launch
  `run_resource_editor.sh` and screenshot the bugs). Era: taskblock 11 was the active block when
  first reported.
- **Symptoms:** (1) nothing resized/expanded on window resize; (2) no visible column-resize grab
  handles in the Tree header; (3) header bar changed height/width while interacting; (4) 3D preview
  z-fought the ground disc (needed zoom-in + upward offset).
- **RESOLVED** 2026-07-18, ~101 commits before the last stale re-report, in three commits:
  - `713f411` — layout never resized, columns wouldn't drag, preview mis-framed
  - `1bff29b` — garbage edits, silent save loss, header jitter
  - `944d019` — preview: drop the dummy-matrix carrier, add `show_assembly`
- **Verified** both in code and by direct supervisor observation of the corrected tool — so this
  `SUPERVISOR`-sourced bug is legitimately `RESOLVED` (the gate was satisfied: the supervisor
  confirmed it).
- **Why it kept recurring:** the fixes landed as plain bugfix commits *outside* the "Taskblock N Pass
  X" cadence, so the usual "update CHANGELOG on landing" never fired. With no closure marker anywhere
  and the tb11 spec still on disk in `taskblock_done/` (gitignored-but-not-deleted, per repo
  convention), the taskblock-generating instance treated the living docs as authority, found nothing,
  and re-derived "go verify the Resource Editor" as open. **This ledger is the fix for that class.**

### Waist-line of impacts — the shot-plane Z-discard  ·  source: `SUPERVISOR`
- **Reported:** through mid-2026-07 review passes ("a line of impacts across the waist"; "only seeing
  ~20% of shots"; "no ricochets").
- **Symptom:** projection collapsed `Vector3 → Vector2(x, z)`, dropping the height axis — so vertical
  scatter collapsed to a horizontal band and tracers/ricochets pinned to one height.
- **RESOLVED** in **taskblock 23** (true-3D shot resolution): projection retains height, the dartboard
  scatters in 3D, `resolve_ray` accepts vertical shots, tracers draw the real 3D path. Tagged in
  `docs/CHANGELOG.md`.

### `los.gd` `range`-shadow (v1)  ·  source: `CC`
- **Symptom:** a param named `range` shadowed the builtin, failing at load/call time.
- **RESOLVED** in the v1 foundation work (noted historically in `docs/SUPERSEDED.md`). `gdlint` now
  catches this class faster than the engine does (see `docs/TOOLING.md` gotchas).

---

## ⏳ Resolved — pending supervisor confirmation
*(CC-fixed `SUPERVISOR` bugs awaiting verification. CC writes here, never straight to Resolved;
the supervisor promotes confirmed ones up to Resolved.)*

### Bout maker AI dropdown missing new playstyles  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: tb24/tb25 added playstyles (overwatch-capable set, PSYCHOTIC, TURTLE)
  but the bout setup menu's own AI dropdown was a hardcoded, independently-maintained list.
- **Fix:** `UnitAI.PLAYSTYLES` is now the one maintained list every `_plan_turn_before_shutdown_check`
  match arm corresponds to; `GenerateBoutOverlay.PLAYSTYLES` is a direct reference to it, not a copy.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass C1.

### Bout menu jumpy add/duplicate, not truly centered  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: adding/duplicating a roster entry reflows jarringly; the menu reads as
  intended-centered but isn't.
- **Root cause:** `set_anchors_and_offsets_preset(PRESET_CENTER)` baked a one-time pixel offset from
  the layout's own size at construction — before a single child existed — so centering was computed
  for an empty control, not the real populated menu. Real entry rows had no `custom_minimum_size.y`
  of their own while the trailing padding spacers were pinned to `ROW_MIN_HEIGHT`, so the roster
  crossing `MIN_VISIBLE_ROWS` changed the total layout height by an inconsistent amount.
- **Fix:** anchors pinned to 0.5 with `GROW_DIRECTION_BOTH` (no baked offset) keeps the layout's own
  center pinned to the parent's midpoint regardless of size changes; every row (entry, add, spacer)
  now reserves the same `ROW_MIN_HEIGHT`.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass C2.

### Inspect header shows only the variant, not unit id/squad  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: the inspect panel showed the bot's variant but not which unit/squad
  this actually was in the current bout — two units built from the same variant read identically.
- **Fix:** the panel's own title bar (`_title_bar`, previously a static "INSPECT" string) now reads
  "INSPECT — Unit N (Squad M) — <variant>" once a unit is open, resetting to plain "INSPECT" on close.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass C3.

### Opposing team teleports before the player's own attack lands  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the last blue unit took its turn and the opposing team
  appeared to jump to new positions before that unit's attack animation resolved."
- **Root cause:** `SquadControlOverlay._on_turn_ended` called `advance_ai_turns(battle)` — which
  fast-forwards every AI turn with NO animation at all, a single instant `refresh_unit_views` at its
  own end — BEFORE the human's own turn had even started its own animated `resolution_player.play()`,
  and that `play()` call wasn't even awaited.
- **Fix:** reordered so the human's own turn is fully awaited through its complete animated playback
  before `advance_ai_turns` runs at all.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass B1.

### Skirmisher squares off through walls, never takes space  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: `_plan_ranged` seeks the preferred standoff distance but never checks
  line of sight — a skirmisher faces off at range through a wall and never advances to gain a real
  line.
- **Fix:** `_engagement_score` gained a dominant (but non-exclusionary) `NO_LOS_PENALTY`, exempting
  only the unit's own origin cell (a covered origin is what `StepOutPlanner`'s own move/fire/return
  fallback already exists to handle — penalizing it here would starve that mechanism of the
  "didn't reposition" signal it's gated on). Reuses the existing `LoS.has_los` primitive, no parallel
  visibility test.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass B2.

### Deflect tracers never drawn  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the resolver produces DEFLECT outcomes (a review bout
  logged 25), but resolution_player.gd references DEFLECT zero times — the bounced secondary ray is
  computed, logged, never drawn."
- **Root cause:** `ImpactResult.reflected_dir`/`reflected_vertical` were always computed by
  `resolve_impact` for a DEFLECT, but `ShotResolution._log_impact` never stamped them onto the log
  event's own data — and a ricochet that then finds nothing to hit produces no further event at all,
  so the view had nothing to draw even when it wanted to.
- **Fix:** every DEFLECT-outcome impact event now carries its own `deflect_end_x/y/height` (the same
  void-ray convention `_log_miss` already used for a total miss), unconditionally — so it's drawable
  whether or not a real ricochet continuation follows. `resolution_player.gd` draws it as a second,
  visually distinct (cool blue vs. warm yellow/red) tracer segment.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass A1.

### Muzzle origin inside the shooter's own armor  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the muzzle originates at the shoulder socket's center
  ('the literal shoulder, not *from* the shoulder'), so the ray starts inside the shooter's own
  geometry and can hit its own armor."
- **Root cause:** `UnitGeometry.muzzle_point` returned the weapon's own box CENTER, not its forward
  emission point — for any weapon shorter than its own full authored length, that center sits back
  inside the gun's own body, close to the shooter's torso.
- **Fix:** `muzzle_point` now returns the box's forward tip (`center + (0, 0, size.z / 2)`, per
  `box.gd`'s own documented "+Z forward" convention), composed through the same placement transform.
  Every reader (Overwatch, AimView, `shouldered_muzzle_point`) gets the corrected point for free.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass A2.

### Extract-tile marker / facing-indicator z-fight  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review), "same class as tb23's floor/indicator z-fighting."
- **Root cause:** the unit facing wedge (`HitVolumeView._build_facing_wedge`) centered its own
  0.10-tall box on `TEAM_MARKER_Y + TEAM_MARKER_HEIGHT` (0.03) — its bottom face reached down to
  -0.02, below the ground plane (Y=0) and into the same height band as a ground-tier board marker
  (e.g. `board_view.gd`'s `EXTRACTION_TILE_HEIGHT`, 0.010).
- **Fix:** raised the wedge's own base height (`FACING_WEDGE_Y := 0.09`) so its bottom face clears
  both the team marker disc's own top surface and every ground-tier board marker with real headroom.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — taskblock-26 Pass A3.

---

## 🔧 Active / Open
*(none currently tracked — add here with `source`, timecode + taskblock as they're reported)*

---

## Notes on scope
- **Design reversals** (a decision that changed shape) go in `docs/SUPERSEDED.md`, not here — that's
  "the design used to be X, now it's Y," not "something was broken."
- **Known-limitations that are deferred by choice** (a stubbed system awaiting its phase) live in
  `docs/PLAN.md`, not here — they aren't bugs, they're unbuilt work.
- This file is only for **things that were broken**: reported defects and their closure.
