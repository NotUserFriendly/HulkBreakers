# Taskblock 35 Report — The wall-model audit, and the AI that stopped acting

All four passes done, in order (A→B→C→D). Full suite green throughout every commit: 2022/2022 at the
end. Five separate commits landed and pushed, one per pass (Pass A landed in three: A2/B1 together
since the depth floor genuinely unblocked A2, then A1, then A3).

## Pass A — Make the AI observable, then make it act

**A2 (BR34.06, the blocker) and B1 (the depth floor) landed together**, exactly as the taskblock's own
text anticipated ("B may partially fix A"). Root cause: `ShotPlane.build`'s own depth-sort has no
floor at zero, by design (the aim window legitimately reads negative-depth regions) — but three
independent "walk the depth-sorted plane, return the first match" implementations
(`ShotPlane.resolve_projectile`, `DamageResolver._find_next`, `LineOfFire._first_hit_excluding` — the
third not named in the taskblock's own Pass B text, found on the same pass) all inherited that
unfloored sort with no floor of their own. A wall many tiles behind the shooter could win outright,
which was BR27.02's own logged 12/12-DEFLECT-on-a-wall-behind-the-shooter case, and post-tb31's dense
walls, the same defect made `has_clear_line_of_fire` read "no clear line" almost everywhere — BR34.06.

Fixed by flooring the RESOLVING path only, opt-in on `resolve_projectile` (a `floor_at_zero` param,
default false — a raw `BodyProjector`-only plane, exercised directly by a wide swath of this
codebase's own test suite, legitimately has negative-depth near-side faces that are NOT "behind the
shooter"; this floor snapped a real test — `test_body_assembler.gd`'s own lateral-armor-socket
fixture — before it was made opt-in), unconditional on `resolve_ray`/`_find_next`/
`_first_hit_excluding` (always fed a real shooter-anchored plane). A second, distinct gap surfaced once
LOF was genuinely correct: `LineOfFire.approach_path`'s own weapon-range cap left a unit starting
genuinely far from any LOF cell with nothing to fall back to, holding forever. New
`LineOfFire.closing_path` — real A* toward the enemy, no LOF requirement — fixed it; a naive greedy
distance-scorer was tried first and reverted, since it reproduces BR32.10's own concave-wall freeze.

Verified live, not just headlessly: a 60-turn, 6-unit `BoutSetup` bout that previously held every turn
(confirmed before AND immediately after the depth-floor fix alone) shows real movement, bursts,
impacts, kills across the whole run once `closing_path` landed.

**A1** — the AI decision log (`AiDecisionLog.emit`, kept in its own file to stay under `unit_ai.gd`'s
own line cap) writes one `&"ai_decision"` event per unit-turn: branch taken, fired/held, hold reason.
The two supervisor-specified FPS dumps (Aim FPS, Turn FPS) landed in a later commit — genuinely
view-layer work, not logic, so it waited until the logic passes were settled. Both emit `&"fps_dump"`
into the ordinary combat log; headless tests only prove the plumbing fires on schedule, since
`Engine.get_frames_per_second()` means nothing without a real running client.

**A3 (BR27.09)** — confirmed the "tb33 added a real `ShotPlane` build per candidate cell" suspicion
directly: `_any_reachable_has_lof` and `_engagement_score` each independently resolved
`LineOfFire.first_hit` for the same cell. New `LineOfFire.cached_first_hit` (opt-in memo, same
default-false pattern) cut average reposition/hold-turn cost from 2023ms to 974ms on the same 60-turn
bout — roughly halved, not eliminated. The remaining cost is real, unavoidable per-cell geometry work
this memoisation can't remove without a bigger algorithmic change; logged as such, not oversold.

## Pass B2 — BR34.05, root-caused and reproduced, not fixed

Misses vanishing in an enclosed room, reproduced directly via `DamageResolver.resolve_shot`: at
ordinary lateral scatter offsets, zero shots vanished (before or after the depth-floor fix — a
genuinely different defect from BR34.06/BR27.02). At wide offsets — the range a late pull of a long
burst at extended range can reach once `RecoilResolver.widen` and `RangeModel`'s own range-accuracy
widening compound — misses start appearing reliably (56/200 at a lateral offset of ~8).
`ShotPlane.build` projects each wall cell as its own independent rect; adjacent cells' projections
aren't guaranteed to tile edge-to-edge from an arbitrary shooter angle, so a wide enough offset threads
a real gap. Also confirmed: there is no modeled floor Region anywhere — the supervisor's own "or the
floor" half of the design rule has nothing to resolve against yet. Not fixed — this touches the shared
geometry every shot in the game resolves against, and the fix is a real design call among three
candidate directions (documented in `docs/BUGS.md`/`docs/PLAN.md`), not a bug to quietly patch.

## Pass C — the assumption audit

Delegated the multi-file sweep to parallel research agents, verified every finding before acting on
it. Most named sites check out **correct as-is** — the `is Unit` distinction in each one does exactly
what it should regardless of wall density:
- `attack_action.gd`/`burst_action.gd`/`stab_action.gd`'s muzzle self-obstruction redirect (a static
  obstruction, cover or wall, should redirect aim; an ally should not — the player's own risk to take).
- `shot_resolution.gd`'s `target_unit_id` falling to -1 for a non-Unit body (every consumer already
  treats -1 as "no unit hit," unaffected by what kind of non-unit thing it was).
- `UnitAI._ally_in_firing_line`'s own `is Unit` gate (asks specifically "is an ally blocking" — a wall
  correctly reads false; wall-blocking is `has_clear_line_of_fire`'s own separate, already-correct
  concern).
- `Pathfinder.move_cost`/`tile_inspection.gd` (single-key dict lookups, density-proof by construction).
- `los.gd`/`inspect_panel.gd`/`world_palette.gd` (no `grid.blockers` reads at all).

**Two real defects found and fixed:**
- A destroyed wall never cleared `grid.opacity` — `Pathfinder` already treated a destroyed blocker as
  passable, but `LoS.has_los` kept reading the same cell as permanently opaque forever. New
  `Grid.cell_of_blocker()` (reverse lookup, only ever run on the rare destruction event) backs a clear
  in `DamageResolver._resolve_destruction_consequences`.
- `BoardView`'s wall-indicator marker checked a terrain condition confirmed, via a real generated
  bout, to never match a live wall cell anymore (`MapGen._finalize_walls_and_void` gives every real
  wall `OPEN` terrain, not `WALL`). Not a live-game bug, but the loop's own comment was stale and the
  condition could still double-draw on a hand-authored grid — guarded and corrected.

**BR32.07 re-derived, not fixed** — traced the full aim-entry chain end to end for a burst-armed click
on a wall; every step is generic over action id, and a new passing regression
(`test_arming_burst_and_clicking_a_wall_enters_aim_mode`) proves it works headlessly. No code-level
break found; recommends a live re-check, the same class of headless-vs-live gap BR27.08 hit.

**Three new findings logged as BR35.01-03 (owner CC), not fixed** — each has a clear fix shape but real
correctness/scope risk if rushed under time pressure: `PartPicker.hit()`'s O(n) blockers/field_items
scan on every hover; `SpectatorOverlay`'s occlusion-blind tile-inspect click (ground-plane math with
no wall-intervening check); an overly-broad debug-panel rebuild trigger (every verb, not just the ones
that touch blockers/field_items).

**BR33.01 left untouched** — no supervisor policy call has been made yet on the aim-scroll-cycles-walls
question. Per the taskblock's own instruction, not guessed at.

## Pass D — the cutout bugs

**BR32.01/03 fixed as one defect**, per the taskblock's own framing. Root cause: `wall_cutout_units`
was set in exactly one place in the whole codebase — `SquadControlOverlay._on_battle_loaded()`.
`SpectatorOverlay` (the default overlay every fresh bout starts in) never touched it, and
`BattleScene.load_battle()` itself never re-pointed it either — so starting/reloading a bout in
Spectator mode left the feed pointing at whatever it held before, either null or the previous bout's
own orphaned units. This is also precisely why clicking "Assume Control" always fixed it live: that's
the only path that ever installs a real `SquadControlOverlay`, the only code that ever set the feed.
Fixed by moving the assignment into `BattleScene.load_battle()` itself, once, for every overlay.

**BR32.04 root-caused, not fixed** — confirmed `ResolutionPlayer._play_slide` animates a unit's own
view node position directly every tween tick, while `update_wall_cutout()` recomputes from the
already-resolved logical `unit.cell`, never reading the view's own current transform. Fix direction is
clear (a per-unit "current display position" map, written by the tween) but scoping its own lifecycle
correctly wants a dedicated pass.

**BR32.05 untouched** — real shader work; the taskblock's own text says shader bugs are invisible to
CC without a live client, and the ledger already has candidate fixes recorded from BR32.02's analysis.

## Tests that failed, then were corrected

Two, both surfaced by the depth-floor fix specifically — no other regression across the whole
taskblock:

1. `test_body_assembler.gd::test_a_lateral_armor_socket_puts_a_plate_on_the_outer_face_and_a_lateral_
   shot_hits_it` — broke (1 failing) the moment the depth floor was first applied unconditionally to
   `resolve_projectile`. Root cause: `BodyProjector`'s own local-body depth convention (centered on
   the body, not a shooter) makes a near-side face's negative depth completely normal and correct —
   different from `ShotPlane.build`'s world/shooter-anchored convention the floor was actually meant
   for. Corrected by making the floor an explicit opt-in parameter instead of blanket behavior.
2. `test_unit_ai_engagement_lof.gd::test_scorer_ranks_a_clear_lof_cell_above_a_los_but_wall_blocked_
   cell` — broke (1 failing) after the floor was made correctly opt-in and threaded through
   `UnitAI`'s own LOF calls. Root cause: the fixture co-located a wall with the exact query cell being
   scored — a configuration no real unit ever occupies (walls are unwalkable) — which happened to
   exercise the identical near-zero-depth self-obstruction pattern a real shooter's own body is
   already excluded for. Corrected by moving the wall to a genuinely downrange cell, matching the
   test's own stated intent (a wall between the candidate and the enemy, not on top of it).

## Supervisor-owned entries moved to Pending this taskblock

Please confirm live when convenient — none of these can be closed without you seeing them work:

- **BR34.06** (AI passes every turn in bouts) — the depth floor + `closing_path` fallback; verified
  live on a 60-turn synthetic bout, needs a real bout to confirm.
- **BR32.01** (stray wall-cutout hole) and **BR32.03** (cutout carries over across bouts) — one fix,
  the `wall_cutout_units` feed-refresh boundary; verified headlessly (Spectator-mode bout reload no
  longer leaves a stale feed), needs a live look (start a bout, stay in Spectator, confirm no stray
  cutout).

Everything else touched this taskblock either stayed Active (found correct-as-is, root-caused but not
fixed, or explicitly left for a design call) or is a brand-new CC-owned finding (BR35.01-03) not yet
attempted.
