# Taskblock 34 Report — Aim View: Truth & Legibility

All five passes done, in order (A→B→C→D→E). Passes B–D were explicitly visual per the taskblock's own
text; you checked the bound ring, pellet circle, and z-fighting live and confirmed all three read
correctly. Full suite: 2005/2006 green throughout — the one failure is the pre-existing, already-
documented `test_full_mission` seed-brittleness (unrelated, not chased).

## Pass A — one scatter resolution, and a cache that survives it

Root bug: `Dartboard.resolve_scatter`'s `radius_multiplier` got assembled by hand at each call site.
`AttackAction`/`BurstAction` always passed `RangeModel.dartboard_radius_scale(weapon, range_cells)`;
`AimController.resolve` (the drawn board) never did, defaulting to 1.0 — so the board shown was always
the weapon's best-case accuracy while the fired shot widened with distance. New `ShotScatter.for_shot`
is the one place that chain gets assembled now; every consumer (the view, every ranged/melee action)
calls it. Migrated `StabAction` too (identical manual-assembly pattern, not explicitly named in the
taskblock) and deliberately left `Overwatch._fire` alone (already flagged elsewhere as its own pending
resolver refactor — `docs/SUPERSEDED.md`).

Fixed the cache landmine this creates: `AimView._rings_match` compared absolute radius, so once radii
vary continuously with range, every retarget/reposition would miss the cache and rebuild the ring
image pixel-by-pixel every frame. `_rings_match` now compares ring-to-outer-ring ratios instead —
`DartboardTexture.build` already normalizes by `outer_radius`, so a pure uniform rescale produces a
byte-identical image.

## Pass B — draw the two spreads the board was hiding

Recoil bound ring: `AimController.recoil_bound_radius` resolves the widest burst pull's own radius
(`RecoilResolver.widen` at `burst_size - 1`) and bakes it into the same cached texture as a crisp
outline — its ratio to the outer ring is weapon-constant, so the Pass A cache invariant survives.
Gated on the armed action actually being `&"burst"` (a weapon that CAN burst but is armed to a plain
shot draws no bound).

Pellet-spread circle: `AimController.pellet_circle_radius` surfaces `SpreadPattern.pattern_radius`
(made public) for actual pellet weapons. Drawn as a genuinely separate, un-cached overlay
(`DartboardTexture.build_solid_dot`) since its size doesn't scale with range — baking it into the
range-scaled ring texture would have reintroduced the per-frame rebuild Pass A just closed.

You confirmed live: the bound reads as visually distinct, not a doubled edge; the pellet circle
doesn't z-fight with the window's flat quad; both correctly disappear for a plain single-shot weapon.
One thing flagged and accepted, not fixed: pellet spread should probably widen with range too
eventually, but doesn't yet (by original tb13 design — "mechanical_accuracy... scales the pattern,
never the dartboard") — noted as fine for now, no action taken.

## Pass C — part tooltip on the aim plane

New `TacticsController.update_aim_hover(screen_pos)`, split out from `aim_reticle_at_screen` rather
than folded into it — maps the cursor to an aim-plane point (the same conversion the reticle uses) and
finds the containing Region via new `ShotPlane.region_at` (a thin public alias for the internal
`resolve_projectile`, which stays locked to `shot_plane.gd` per the existing invariant test). Writes
only `aim_hovered_part`, never `reticle_offset` or anything `resolves` reads — "hovering reads, it
never re-aims" is a provable, directly-tested guarantee (its own function, no other side effect) rather
than just a comment. `aim_reticle_at_screen` calls it at the end so the same cursor position keeps both
in sync during normal play.

`AimView` renders the hovered part's tooltip via a `Label3D`, coplanar with the aim window, through new
`TooltipView.to_plain_text` — a third host for the same `TooltipData` shape `to_bbcode` already
renders, since `Label3D` has no BBCode support. Required threading `material_table` into
`AimView.setup()`, so `squad_control_overlay.gd`'s own `material_table` local moved earlier to cover
both call sites.

One fixture surprise, worth knowing about: a target's default aim point (zero reticle offset) doesn't
always land on its torso — a gripped weapon's own hand can stick out further forward and be the true
frontmost region. Fixed the tests to assert against whatever `ShotPlane.region_at` actually resolves
there, rather than hardcoding an assumed part id.

## Pass D — sniper framing for distant targets

New `CameraOrbitState.sniper_framing(target)`: this rig's own topology (the camera always faces its
own `pan_offset` pivot) means setting `pan_offset = target.center` centers the target on screen at ANY
yaw/pitch — no dual-sphere BACK solve needed like `attack_framing`'s own binary search, just a
closed-form single-sphere zoom (the distance at which the target's own angular footprint fits the
usable half-FOV). Keeps the current yaw/pitch rather than solving a new viewing angle. Needed a small
`SNIPER_ZOOM_SLACK` backoff — the closed-form solve lands exactly on the FOV boundary with zero slack,
grazing it under floating-point rounding at larger radii, the same reason `ATTACK_MARGIN` itself
exists.

New `CameraRig.ease_to_framing(shooter, target, distance_cells)` picks between the two framings by
`CameraOrbitState.SNIPER_FRAME_DISTANCE` (5 cells, a named tunable) and eases through the same shared
`_ease_to` tween `ease_to_attack_framing` itself uses. `ease_to_attack_framing` stays unchanged as the
plain, always-over-the-shoulder primitive — every one of its 8 existing tests, including the reference
`test_ease_to_attack_framing_centers_the_target_on_screen`, was left untouched; `TacticsController
._enter_aim_mode` is the one caller upgraded to the new distance-aware entry point.

## Pass E — BR26.02 (low framerate while aiming)

The taskblock's own sequencing point: profile after B–D land, since A removes work and B–D add it.
Two things done, one thing NOT done:

- **Headless cache regression** (what I could actually automate): swept `ShotScatter.for_shot` across
  every cell from adjacent to max range, standing in for a live aim session's own repositioning, and
  confirmed `DartboardTexture.build` runs at most once across the whole sweep.
- **A second, unplanned fix** — re-reading `docs/BUGS.md`'s own BR26.02 entry surfaced an existing,
  already-root-caused note from 2026-07-21 that had never actually been applied: `AimView._process()`
  unconditionally called `refresh()` every single frame while aiming, even though `refresh()` was
  already fully wired to `tactics.aim_changed`. Re-audited all 11 `aim_changed.emit()` call sites to
  confirm every mutation path was genuinely covered, then deleted the override outright. This wasn't
  something the taskblock asked for by name, but it's exactly the class of fix Pass E's own text
  anticipates ("the remaining suspects are the per-frame `ShotPlane.build`/reticle path") and was
  already diagnosed, not guessed — flagging it here as a decision made without being asked, in case
  that scope call should have gone differently.
- **Not done: actually profiling.** This environment has no GPU/profiler. Both fixes are well-reasoned
  and address the two most concretely diagnosed costs, but per the pass's own "measure, don't guess"
  instruction, only a live frame-rate observation confirms the aiming screen is actually fast now —
  and profiling might still name the new Pass B/C overlays as a further cost if these two fixes aren't
  the whole story.

## Living docs

- `docs/CHANGELOG.md` — new "Aim view: truth & legibility" paragraph under **Tooling, data & view**.
- `docs/BUGS.md` — **BR26.02** marked `RESOLVED-PENDING-CONFIRMATION [CC
  16507d21-1035-4b1c-a0fe-72a911df7403]` (SUPERVISOR-sourced — never plain `RESOLVED`; needs your own
  live frame-rate check). Also logged two NEW findings from live playtesting mid-block, both left open
  (not fixed, per your own instructions each time):
  - **BR27.02** (pre-existing "backward-firing" ticket) updated with two new dated notes: a live log
    excerpt where a 12-round chaingun burst's every pull hit a wall in the geometrically opposite
    quadrant from the aimed target, and a follow-up read-only investigation tracing this to a
    plausible negative-`region.depth` sort-order bug in `ShotPlane.build`/`_find_next` — a real
    hypothesis, arithmetically consistent with the logged numbers, but not proven against a
    constructed fixture.
  - **BR34.01** (new) — every penetration/deflection hop in a single trigger pull replays the FULL
    bright hit-flash and inter-shot pacing gap, when only the first hit should. Root cause identified
    (`ResolutionPlayer.play()` reuses the log's own per-hop granularity as its own per-shot playback
    granularity) but not fixed — needs a design call on how to mark "hop 2+" in the data.

## SUPERVISOR bugs moved to PENDING-CONFIRMATION this block

- **BR26.02** — low framerate while aiming. Two fixes landed (cache-invalidation, redundant per-frame
  refresh); needs your own live frame-rate check before promotion to `RESOLVED`.

## Decisions made without asking (flagged for review)

1. **Migrated `StabAction` to `ShotScatter.for_shot` alongside the two explicitly-named consumers.**
   Not asked for by name, but it had the identical manual-assembly pattern the whole pass exists to
   kill — leaving it unmigrated would've kept the exact divergence risk alive at a third site.
2. **Split `update_aim_hover` into its own function rather than folding the lookup into
   `aim_reticle_at_screen`.** The taskblock's own test list ("hovering does not change
   `AimResult.resolves` or the reticle") reads as wanting this provable in isolation, not just true by
   inspection of a bigger function — recomputes the screen→plane ray a second time rather than
   threading an already-computed value between the two, trading a little redundant math for a much
   cleaner independence guarantee.
3. **`Label3D`/`TooltipView.to_plain_text` for the in-world tooltip**, rather than trying to reuse the
   existing 2D `TooltipView`/BBCode rendering somehow. `Label3D` has no BBCode support, so a plain-text
   sibling function was the least-duplicative option that still shares the exact `TooltipData` content.
4. **`sniper_framing` keeps the shooter out of its own solve entirely** (signature takes only
   `target`, unlike `attack_framing`'s `(shooter, target)`) and preserves whatever yaw/pitch the rig
   already has, rather than computing a "look from behind the shooter" viewing angle. The taskblock
   only asked that the target center on screen, which this rig's topology gives for free at any
   angle — computing a shooter-relative viewing direction anyway would have been unrequested scope on
   top of a simpler, sufficient solution.
5. **Removed `AimView._process()` outright** (Pass E) rather than gating it with a cheap comparison.
   Already-diagnosed dead weight once `refresh()` was confirmed fully signal-driven — gating it would
   have kept a redundant check running every frame for no reason, when deleting it is both simpler and
   strictly faster.
6. **Didn't attempt a fix for either of the two bugs found via live playtesting** (BR27.02's new
   angle, BR34.01) — both were explicit "investigate/log only, don't fix" instructions in the moment,
   carried through faithfully rather than getting swept into this taskblock's own passes even though
   they live in the same neighborhood (resolution/playback geometry).
