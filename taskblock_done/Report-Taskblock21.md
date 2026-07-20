# Taskblock 21 Report — The Inspect Panel, Bout Control, Flee/Extraction, and Cleanup

(Delete after review — not a permanent doc.)

## Headline numbers

| | before | after |
|---|---|---|
| test funcs | 1383 | 1424 |
| commits | — | 8 (`5862556`..`bccc756`) |

Full suite green (`./run_tests.sh`) at every commit, re-run twice each time to
catch order-dependent flakes.

## What got built, pass by pass

**Pass A — the inspect/status panel.** `InspectPanel` (new, `src/view/inspect_panel.gd`):
a bot viewer (rotates on its own, click-drag interrupts and resumes — shares the Resource
Editor's own preview primitive), a status/wound column (one entry per unique wound id, colored
by disabling, hover fills the info panel), a logic matrix area, a strongly-sorted inventory
`Tree` (Weapons → Containers → Body parts, via new `InspectRow`/`InspectRows`, three separate
stable filter passes rather than a `sort_custom` — Godot's own sort isn't stable), an info
panel + item viewer (dead zones hold the last info, never clear on hover-off), and a
right-click debug menu (Reset Health / Set Health to 0 / Set Ammo Type, plus the "add if
cheap" extras — Inflict Wound, Detonate Part, Strip Cladding, Refill AP/Power). Supersedes the
transient hover-tooltip for object/part/unit inspection; the tooltip itself survives untouched
for quick hovers (action bar, pips) — `TooltipView.to_bbcode` was made `static` so
`InspectPanel` could reuse it directly instead of duplicating BBCode rendering.

**Pass B — spectator click-to-pause-inspect.** `SpectatorOverlay` no longer builds its own
`TacticsController`/`TooltipController`/`TooltipView` at all — a raycast through
`UnitPicker.hit()` (already pure, no controller needed) plus the Pass A panel replaces that
whole stack. Clicking a bot pauses (reusing tb15's existing pacing pause, never a second one)
and opens the panel; closing it resumes only if playback was actually running before.

**Pass C — "assume control" in bouts.** One new `BattleScene.toggle_blue_control()`: flips
`CombatState.controller_for(0)` and swaps the overlay via the existing `set_overlay()`
mechanism (`SquadControlOverlay` ↔ `SpectatorOverlay`) — the same overlay-swap tb15 already
built, exposed as a toggle from three places (a checkbox on `GenerateBoutOverlay`, an "Assume
Control" button on `SpectatorOverlay`, a "Watch" button on `SquadControlOverlay`). Red always
stays AI; nothing about how a bout resolves changes, only which overlay is driving squad 0's
queue.

**Pass D — no-weapon AI flees to extraction.** New `MissionState.team_extraction_cells`
(`Dictionary`, squad_id -> cells) alongside the existing flat `extraction_cells`, purely
additive — `ExtractAction.is_legal()` reads the team-coded set first, falling back to the flat
field only for the mission's own player squad. `BoutSetup.build_bout` populates both squads'
tiles at their own spawn cells. `UnitAI.plan_turn` gets a new top-priority branch, above the
ranged/cover planners: `_has_functional_weapon` (reusing `WeaponRows`' real operability check,
not the looser "a part with damage > 0 exists" `_find_weapon_id` uses elsewhere) gates
`_plan_flee`, which paths to the nearest tile and escapes via the existing `ExtractAction` —
the taskblock's own explicit "no new outcome" instruction, so a single disarmed unit reaching
its tile ends the whole bout immediately. A squad with no team-coded tile and no claim on the
flat field just ends its turn, same degenerate fallback `_plan_non_combat_turn` already used.

**Pass E — the inter-turn FPS hitch (investigation only, no fix).** Headless probes measured
three real suspects instead of guessing: `UISink.emit`'s full-text `RichTextLabel` relayout on
every single combat-log event (~175-180us each, and a real 3v3 bout averaged 9.9 events/turn,
peaking at 29 — up to ~5ms on a heavy turn); `HitVolumeView.refresh()`'s mesh teardown/rebuild,
unconditional on the acting unit every turn even when nothing about its geometry changed
(~550-600us per affected unit, 2-4/turn observed); and turn-start power recompute re-walking
the same unchanged part graph roughly 5-6 times per `_start_turn` call via uncached
`Shell.all_parts()`/`operable_parts()` (~175us/turn). Initiative re-sort was measured and ruled
out (~40us across a 12-unit roster). Full writeup with recommendations lives inline in
`taskblock21.md`'s own Pass E section, carried into this report's file below. No fix applied,
per the taskblock's own instruction — none of the three felt trivially obvious enough to flag
as the stated exception.

**Pass F — missed shots draw tracers too.** A genuine miss used to emit zero log events (the
dartboard point landed nowhere any region in the whole shot plane covers). Since every
wall/cover object is already its own `Region` in the plane, an empty result can only mean the
void — no separate "hit a wall" case exists for a miss. `ShotResolution.resolve_and_log_point`
now logs a `&"miss"` event carrying the ray's own void endpoint (mirroring `resolve_shot`'s own
muzzle-to-impact math, terminated at the firing weapon's authored `max_range` or the map's own
longest side when unauthored). `ResolutionPlayer` routes it through the same `_spawn_tracer`
bright-fade-dull path `&"impact"` already uses, and the inter-shot pacing break now covers any
run of impact/miss in either order, not just back-to-back impacts.

**Pass G — the intermittent sideways-slide fix.** Root-caused to a view-only priming bug, not
a logic-layer facing gap: `ResolutionPlayer._ensure_primed()` primed a unit's starting display
orientation from `unit.orientation` whenever nothing had written it yet — but by `_prime()`'s
own call time, resolution has already fully finished, so that's the turn's FINAL orientation.
Invisible whenever a `faced` event preceded the move (the common case — `_play_facing`
overwrites the value first), but on a unit's first-ever animated move that needed no re-face at
all (already facing that way, e.g. off its own spawn orientation) whose same turn re-faces
again later (an attack, a step-out's own return leg), the slide played facing wherever the unit
turned to LATER instead of the direction it was actually walking. Fixed by deriving
`FaceAction.orientation_toward(path[0], path[1])` from the move event itself when one exists —
mirroring `_display_cell`'s own existing `path[0]`-derived fix one line up, for orientation
instead of position. Reproduced with a direct regression test before the fix, confirmed it
failed, then confirmed the fix passes without disturbing the existing, deliberately-different
"no move event at all" priming behavior (still `unit.orientation`, unchanged, its own already-
covered case).

**Pass H — data-only fixes.** Each reference gun (`sniper_rifle`, `chaingun`, `pump_shotgun`,
`auto_shotgun`, `rifle`) re-authored from two scatter rings to three (outer/middle-heaviest/
inner, radius ratio 0.25/0.65/1.0, weight ratio 1/5/1). AP costs authored per the taskblock's
own numbers: sniper 3/shot, chaingun 4/burst, shotgun 2/shot; `auto_shotgun` (2/shot, 3/burst)
was a "per feel" pick, flagged, since it wasn't named explicitly. Locking tests for both,
verified spent via real `AttackAction`/`BurstAction.apply()` calls, not just field reads.

## Design decisions made without a further ask

- **Pass A**: the panel built as an additive modal, never replacing `InventoryPanel`'s own
  file — `SquadControlOverlay` gained an "Inspect" button alongside its existing inventory
  footer rather than the inventory panel being torn out.
- **Pass D**: `team_extraction_cells` kept as a brand new field rather than retyping/migrating
  the existing `extraction_cells` (used across 10+ files) — simple, reversible, matches "go
  with the option that's easier to revert."
- **Pass D**: fleeing reuses `ExtractAction` verbatim, ending the whole bout the instant any one
  disarmed unit reaches its own tile — the taskblock's own explicit instruction, surfaced here
  since it's a real, visible consequence (one weak unit can end a fight teammates are still
  winning).
- **Pass D**: the flat `extraction_cells` fallback was scoped to the player's own squad only,
  after it broke `test_full_mission.gd`'s pinned seed — an enemy squad with no team-coded tile
  now goes idle instead of walking toward the player's own landing zone once disarmed.
- **Pass F**: `max_range` threaded through as a plain optional float parameter rather than a new
  shared struct/context object — the smallest change that gets the weapon's own authored range
  to the one place that needed it.
- **Pass H**: `auto_shotgun`'s AP costs were an own judgment call (not named in the taskblock),
  flagged in the commit as tunable.

## Real bugs found and fixed along the way

- **Pass A**: `Camera3D.look_at()` called before the node was inside the `SceneTree` — reused
  the exact `add_child`-before-`setup()` ordering `resource_editor.gd`'s own comments already
  warn about, caught via 68 cascading unrelated test failures the first time it was violated.
- **Pass A**: `InspectPanel` defaulted to `MOUSE_FILTER_STOP`, failing the whole-scene
  board-click audit test — fixed to `MOUSE_FILTER_IGNORE`, matching `TooltipView`'s own
  established convention.
- **Pass A**: a `PopupMenu` id collision — every dynamically-added "Set Ammo: X" item reused
  the same numeric id, losing which one was actually chosen. Fixed with unique ids per index
  and a parallel lookup array.
- **Pass D**: after adding the flee branch, `test_full_mission.gd`'s pinned seed stopped
  reaching extraction — a disarmed defender that used to still attempt (and fail) actions now
  correctly went idle, and the landing squad ground it down at point-blank range long enough to
  wipe itself out on ricochet splash. A real, deliberate AI behavior change, not a regression —
  re-picked to seed 12355 via the same brute-force nearby-seed search this file's own header
  already documents doing twice before, for the same underlying reason (a correct engine change
  reshuffling one pinned seed's own emergent outcome).
- **Pass G**: the sideways-slide root cause itself — see the Pass G writeup above. Reproduced
  with a direct regression test first, confirmed it failed against the unfixed code, then
  confirmed the fix.

## Files touched (new)

- `src/logic/inspect_row.gd`, `src/logic/inspect_rows.gd`, `src/view/inspect_panel.gd`
- `test/unit/logic/test_inspect_rows.gd`, `test/unit/view/test_inspect_panel.gd`
- `test/unit/logic/actions/test_shot_resolution.gd`
- `test/unit/data/test_taskblock21_gun_data.gd`
- Extensive additions to `test_unit_ai.gd`, `test_bout_setup.gd`, `test_extract_action.gd`,
  `test_battle_scene.gd`, `test_spectator_overlay.gd`, `test_resolution_player.gd`,
  `test_full_mission.gd` (re-seeded, see above)

Full suite: 1424/1424 passing, re-run twice per commit, clean headless boot checked after
every pass.

## Pass E — FPS hitch investigation (full writeup)

**Method:** standalone headless probe scripts (`SceneTree`-based, not GUT — timed with
`Time.get_ticks_usec()`), calling the real logic/view classes directly. Two measurements:
(1) microbenchmarking each suspect in isolation over repeated calls on a realistic 27-part
deep-struck unit, and (2) a real 3v3 bout (`BoutSetup.build_bout`, AGGRESSIVE AI both sides)
driven 60 turns through the actual `CombatState.resolve_until` path, counting real events/turn
and real affected-unit-ids/turn (what `refresh_unit_views` actually has to redraw) as it
happened. Numbers are from this machine/build, order-of-magnitude evidence, not a promise of
exact ms in the real game loop (which also pays render/physics costs the probes don't).

1. **`UISink.emit`'s full-text relayout — the biggest, most variable suspect, and worse than
   the "turn-announce" framing suggests.** `label.text = "\n".join(lines)` is a *full*
   reassignment of the whole up-to-200-line scrollback, on **every single event**, not just
   the turn-start line — measured at ~175-180us/call once the log is full (200 lines), vs.
   ~50us on an empty label. A real combat turn is not one event: the 3v3 bout averaged
   **9.9 events/turn**, peaking at **29** (a burst-fire turn). At steady state that's
   ~1.7ms on an average turn and **~5ms+ on a heavy one** — a real, visible stall, and it
   scales directly with how much a turn actually does (more scatter pellets/ricochets = more
   relayouts), which fits "persistent, noticeable, between turns" well. The turn-start line is
   just the first of many events paying the same tax that turn, which is probably why it reads
   as "coinciding with the turn-announcement" — it's simply first.
   *Recommendation:* switch to an incremental append (`RichTextLabel.append_text` for the new
   line only) instead of reassigning `.text` from the whole buffer; the 200-line cap needs a
   different trim strategy (e.g. trim every N lines instead of every line, or drop the cap and
   let `scroll_following` + a max buffer size handle it). Real design tradeoff, not fixed here.

2. **`HitVolumeView.refresh()` — full mesh teardown/rebuild, unconditional on the acting unit
   every single turn.** Measured ~550-600us per call on the 27-part unit (`remove_child` +
   `queue_free` on every child, then rebuild every box/mesh + material from
   `UnitGeometry.placements`). The 3v3 bout showed 2-4 affected unit ids per turn (mostly 2:
   the acting unit is *always* included via its own `turn_start` event, even on a turn where
   nothing about its geometry changed at all — no move, no hit taken). So this is ~0.6-2.3ms
   of guaranteed-every-turn work, most of it wasted on turns where the unit's own mesh didn't
   actually change.
   *Recommendation:* skip the rebuild for a unit whose only event this turn was `turn_start`/
   `turn_end`/`faced` (no `move`, `impact`, `part_destroyed`, `part_mangled`, `subtree_dropped`)
   — its geometry provably didn't change, so there's nothing to redraw.

3. **Turn-start power recompute — smaller in isolation, but mechanically wasteful.** Measured
   ~175us/call (`_start_turn`'s own `PowerResolver` sequence), unconditional every turn
   regardless of whether the shell even has a power system. Root cause: `has_power_system` +
   `recharge_batteries` + `max_ap_for` (which itself calls `reactor_power` a second time) +
   `discharge_batteries` each independently call `shell.all_parts()`/`operable_parts()`, and
   neither is cached — `Shell.all_parts()` re-walks the whole part graph
   (`PartGraph.walk`, recursive, allocates a fresh `Array[Part]` per level) from scratch on
   every call. One `_start_turn` call re-walks the *same, unchanged* 27-part graph roughly
   5-6 times. Real, but the smallest of the three — "heavier than it looks" mostly because of
   redundant work, not because any one walk is slow.
   *Recommendation:* compute `operable_parts()` once per `_start_turn` call and thread it
   through, instead of each `PowerResolver` function re-deriving it.

4. **Initiative re-sort (`_fastest_by_initiative`/`ResolutionSpeed.initiative`) — measured and
   ruled out.** ~3-4us/unit even across a 12-unit roster (~40us total per `advance_turn()`
   call). `ResolutionSpeed.initiative()` does route through `StatResolver` per docs/08, but at
   this roster scale it's noise next to suspects 1-3. Not a contributor to the hitch.

**Net read:** the log sink (1) is the largest and most turn-shape-dependent cost, the mesh
rebuild (2) is the second largest and the most obviously *wasteful* (fires on turns that
provably changed nothing), and the power recompute (3) is real but small. None was fixed in
this pass per the taskblock's own instruction — none of the three felt "trivially obvious"
enough to flag as an exception: each recommendation above has a real design tradeoff (the log
sink's line-cap strategy, what "provably unchanged" should mean for the view, and whether
`operable_parts()` should be cached on `Shell` itself or just threaded through one call).
