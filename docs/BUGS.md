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

### Deflect tracers never drawn  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the resolver produces DEFLECT outcomes (a review bout
  logged 25), but resolution_player.gd references DEFLECT zero times — the bounced secondary ray is
  computed, logged, never drawn."
- **Fix:** `taskblock-26 Pass A1` (commit `7c07445`) — every DEFLECT-outcome impact event now
  carries its own `deflect_end_x/y/height`, drawn as a second, visually distinct tracer segment.
- **RESOLVED** — confirmed by the supervisor.

### Bout maker AI dropdown missing new playstyles  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: tb24/tb25 added playstyles (overwatch-capable set, PSYCHOTIC, TURTLE)
  but the bout setup menu's own AI dropdown was a hardcoded, independently-maintained list.
- **Fix:** `taskblock-26 Pass C1` (commit `67c7ca8`) — `GenerateBoutOverlay.PLAYSTYLES` is now a
  direct reference to `UnitAI.PLAYSTYLES`, not a hardcoded copy.
- **RESOLVED** — confirmed by the supervisor.

### Bout menu jumpy add/duplicate, not truly centered  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: adding/duplicating a roster entry reflows jarringly; the menu reads as
  intended-centered but isn't.
- **Fix:** `taskblock-26 Pass C2` (commit `67c7ca8`) — anchors pinned to 0.5 with
  `GROW_DIRECTION_BOTH` (no baked offset); every row reserves the same `ROW_MIN_HEIGHT`.
- **RESOLVED** — confirmed by the supervisor.

### Inspect header shows only the variant, not unit id/squad  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26: the inspect panel showed the bot's variant but not which unit/squad
  this actually was in the current bout — two units built from the same variant read identically.
- **Fix:** `taskblock-26 Pass C3` (commit `67c7ca8`) — the title bar now reads "INSPECT — Unit N
  (Squad M) — <variant>" once a unit is open.
- **RESOLVED** — confirmed by the supervisor.

### Stab's slide-deflect could land back on the shooter's own body  ·  source: `CC`
- **Found:** while re-diagnosing A2 below (see that entry) — `DamageResolver._resolve_slide` (stab's
  own DEFLECT_MODE_SLIDE response) re-searches the WHOLE plane from index 0 with a lateral nudge, but
  hardcoded an EMPTY exclude list on that re-search, unlike every other plane lookup in `resolve_shot`.
  A stab that deflects and slides at point-blank range could therefore land back on the shooter's own
  body (which sits at the ray's own near-zero depth), the one lookup `resolve_shot`'s own first-hop
  exclusion never covered.
- **Fix:** `_resolve_slide` now takes `exclude_parts` and passes it through to its own `_find_next`
  call, the same shooter-parts list `resolve_shot` itself was given.
- **RESOLVED** — proven both ways (fails without the fix, passes with it) by
  `test_damage_resolver_deflect_modes.gd::test_slide_deflect_never_lands_back_on_the_shooters_own_excluded_body`.

---

## ⏳ Resolved — pending supervisor confirmation
*(CC-fixed `SUPERVISOR` bugs awaiting verification. CC writes here, never straight to Resolved;
the supervisor promotes confirmed ones up to Resolved.)*

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
- **2026-07-20:** supervisor could not verify — blocked by a separate, new issue encountered during
  the attempt. Still pending; the new issue itself needs to be filed once its own shape is known.

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

### Muzzle origin inside the shooter's own armor  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the muzzle originates at the shoulder socket's center
  ('the literal shoulder, not *from* the shoulder'), so the ray starts inside the shooter's own
  geometry and can hit its own armor."
- **First attempt (taskblock-26 Pass A2, commit `7c07445`):** `UnitGeometry.muzzle_point` returned
  the weapon's own box CENTER, not its forward emission point — changed to return the box's forward
  tip. **2026-07-20: supervisor reported still present.**
- **Re-diagnosis:** that fix touched a function no real firing action actually consumed for its
  horizontal origin. Every real attack (`AttackAction`/`BurstAction`/`GrindAction`/`SlashAction`/
  `StabAction`) built the shot plane — and therefore the logged/drawn `impact.origin` — from the
  shooter's own bare CELL center (`Vector2(actual.cell.x, actual.cell.y)`), never from
  `shouldered_muzzle_point`'s own (already-correct) result. Real self-hits were already impossible
  either way (every shooter part is excluded by identity on the plane's first lookup), so this was
  purely the visible/logged origin sitting dead center in the shooter's own torso.
- **Second fix:** all five action files now anchor the shot plane on
  `Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE` (the same continuous muzzle position
  `ShotPlane.resolve_ray` already anchors the reticle/overwatch path on), computed from
  `shouldered_muzzle_point` before the plane is built, not after.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — second attempt, proven via
  `test_attack_action.gd::test_impact_origin_comes_from_the_real_muzzle_not_the_bare_cell_center`.

### Extract-tile marker / facing-indicator z-fight  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review), "same class as tb23's floor/indicator z-fighting."
- **First attempt (taskblock-26 Pass A3, commit `7c07445`):** raised the unit facing wedge's own base
  height (`FACING_WEDGE_Y := 0.09`) so its bottom face clears the team marker disc and the extraction
  tile marker. **2026-07-20: supervisor reported still present.**
- **Re-diagnosis:** the fix checked clearance against only the two markers named in the original
  report — it never checked `board_view.gd`'s own `OVERWATCH_ARC_HEIGHT` (top face 0.05, the amber
  overwatch-arc tile — a very ordinary thing to have visible under a standing unit), which the 0.09
  center's own bottom face (0.04) genuinely interpenetrated.
- **Second fix:** `FACING_WEDGE_Y` raised again, to 0.12 — clears the TALLEST known ground-tier
  marker (`OVERWATCH_ARC_HEIGHT`) with real headroom, not just the two originally named.
- **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082] — second attempt, proven via
  `test_hit_volume_view.gd::test_the_facing_wedge_clears_every_ground_tier_marker_including_the_overwatch_arc`.

---

## 🔧 Active / Open

### Low framerate while aiming  ·  source: `SUPERVISOR`
- **Reported:** taskblock-26 (bout review), filed in the taskblock's own scope fence as explicitly
  deferred: "B-tier; investigate separately — likely the inspect field updating every frame; not a
  correctness bug, don't rush a fix into this block."
- **Status:** not investigated. Flagged for the post-tb26 testing/tooling review (pairs with a "what
  does CC do repeatedly" audit) rather than fixed under taskblock-26's own scope.

---

## Notes on scope
- **Design reversals** (a decision that changed shape) go in `docs/SUPERSEDED.md`, not here — that's
  "the design used to be X, now it's Y," not "something was broken."
- **Known-limitations that are deferred by choice** (a stubbed system awaiting its phase) live in
  `docs/PLAN.md`, not here — they aren't bugs, they're unbuilt work.
- This file is only for **things that were broken**: reported defects and their closure.
