class_name ResolutionPlayer
extends Node

## docs/10 Phase 12.4: plays back a resolved turn's captured log purely as
## a cosmetic replay — by the time play() runs, resolve_turn()/BoutRunner.
## step() has already mutated the real state synchronously. This Node
## never drives the sim; it only shows what already happened, over
## wall-clock time.
##
## taskblock-15 Pass B: extended with real TIMED animation — slide,
## facing, and a bright-shot-to-dull-tracer ring buffer — replacing the
## old instant-tracer-only playback. B0's own invariant: animation is
## PLAYBACK, it never decides anything. `state`/`unit_views` have already
## reached their final values by the time any of this runs; every
## animation here is a temporary, self-cancelling COSMETIC offset on top
## of that already-correct final state (HitVolumeView.refresh() rebuilds
## every child mesh at the true final cell/orientation; this class only
## ever nudges the view's own root Node3D transform away from identity and
## eases it back — never touches UnitGeometry/resolution-critical geometry
## at all). Decoupled from TacticsController entirely (SpectatorOverlay has
## none) — reads `battle.combat_state`/`battle.unit_views` directly.
##
## Two real visual bugs, fixed here:
## 1. `refresh_unit_views()` already bakes every mesh at the FINAL state,
##    synchronously, before `play()`'s own RESOLVE_LEAD_IN wait even
##    starts — a unit would flash at its destination for that whole real-
##    time wait, then jump BACK the instant its own event actually began
##    animating. `play()` now calls `_prime()` first, synchronously, in
##    the same frame `refresh_unit_views()` already ran in and before the
##    engine ever presents it — the "as if still at the old state" offset
##    is applied before any frame is ever drawn, so there is no flash and
##    no jump.
## 2. A plain `view.rotation.y` rotates around the VIEW's own local origin
##    — which is world origin (0,0,0), since every child bakes an
##    ABSOLUTE world position, and `view.position` is otherwise identity.
##    Turning a unit that isn't standing on cell (0,0) that way visibly
##    swings its whole body through a wide arc around the map origin
##    instead of turning in place. Every rotation here now goes through
##    `_apply_display_transform()`, which pivots on the unit's own body
##    center instead.

const TACTICS_BANNER := "TACTICS"
const RESOLUTION_BANNER := "RESOLUTION"

## "Tracers may be raycast fakes — a line from muzzle to impact is enough"
## (docs/10). taskblock-23 Pass D: no longer the universal height — every
## real hop now logs its own real `origin_height`/`hit_height`/`end_height`
## (Pass A/C). Kept only as the `.get()` default for a log entry that
## somehow doesn't carry one — roughly chest-height on the reference
## humanoid, same flagged placeholder it always was for that one case.
const TRACER_MUZZLE_HEIGHT := 1.25
const TRACER_THICKNESS := 0.03
## The live raycast flash a shot draws with, bright and momentary.
const TRACER_COLOR := Color(1.0, 0.85, 0.3)
## The color a live shot fades TO and persists at in the ring buffer —
## deliberately a different hue from the live flash (not `.darkened()`
## anymore), so "still resolving" and "already-fired history" read as two
## distinct things at a glance: a dark red, faint enough that a dense ring
## of retired tracers never reads as solid as the live shot drawn over them.
const TRACER_DULL_COLOR := Color(0.5, 0.0, 0.0, 0.3)
## taskblock-26 Pass A1: a DEFLECT's own bounced continuation, drawn as a
## second segment from the impact point — "insane amounts of deflects is
## the intended combat texture," so a bounce needs to read as visually
## distinct from a clean penetrating/stopping hit at a glance, not just a
## second identical-looking tracer. A flagged first pass at the exact
## hue (a cool blue against the warm yellow/red of an ordinary shot), not
## a final art decision — only "visually distinguishable" is specified.
const TRACER_DEFLECT_COLOR := Color(0.3, 0.75, 1.0)
const TRACER_DEFLECT_DULL_COLOR := Color(0.0, 0.15, 0.4, 0.3)
## Render priority split (docs/10: transparent geometry sorts by camera
## distance by default, which can't be trusted to keep the CURRENT shot
## drawn over older, possibly-overlapping retired tracers along a similar
## line of fire) — the one live/fading tracer always outranks every
## already-retired one, then drops to the shared base tier the instant it
## joins the ring buffer.
const TRACER_LIVE_RENDER_PRIORITY := 1
const TRACER_RETIRED_RENDER_PRIORITY := 0
const INTER_SHOT_BREAK_MS := 100.0
## taskblock-27 Pass A2: "shot -> (pause) -> its deflect -> (delay) -> next
## pair," not a shot and its deflect firing simultaneously. A beat inside
## one impact's own primary->deflect pair, distinct from
## `INTER_SHOT_BREAK_MS` (the gap BETWEEN separate impact/miss events) —
## same flagged-placeholder posture, only "a visible gap" is specified.
const DEFLECT_BEAT_MS := 100.0

## taskblock-15 Pass B4: "editable fields at the top of the spectator
## overlay... temporary debug knobs." Public, mutable — SpectatorOverlay's
## own UI writes into these directly; not baked constants.
var slide_ms: float = 100.0
var bullet_ms: float = 250.0
var tracer_count: int = 100
## Pacing speed (1x/2x/4x, taskblock-14 Pass C) — every duration below
## divides by this, so a faster watch speed animates faster too, not just
## steps more often.
var speed: float = 1.0

var banner: Label
var battle: BattleScene

var _tracers: Node3D
## Ring buffer of persisted dull tracers, capped at `tracer_count` — the
## oldest is evicted the instant an (N+1)th arrives. `tracer_count <= 0`
## skips this stage entirely (B3: "the fade completes to nothing, no
## history kept — demo mode").
var _tracer_ring: Array[MeshInstance3D] = []
## unit_id -> the cell/orientation this player last actually SHOWED that
## unit at — a `move`/`faced` LogEvent only ever carries its own target,
## never where it started FROM, so this is the one piece of state this
## class carries across playback calls (persists turn to turn, same
## object, same overlay's whole lifetime). A unit's very first-ever
## animated move/turn has nothing to animate from and simply snaps — a
## harmless, one-time edge case, not worth inventing a fake "always at
## cell zero initially" origin for.
var _display_cell: Dictionary = {}
var _display_orientation: Dictionary = {}
var _on_finished: Callable


func _init() -> void:
	_tracers = Node3D.new()
	add_child(_tracers)


## `p_banner` is optional (null skips every banner text flip) — a
## TACTICS/RESOLUTION phase banner is meaningful for SquadControlOverlay's
## own human-played turn, not for an all-AI spectated bout, which has no
## "tactics phase" of its own to announce. `p_on_finished` is called once
## the whole playback (lead-in, every event, tail) completes —
## SquadControlOverlay passes `tactics.unlock_input`; SpectatorOverlay
## passes nothing (its own step loop just awaits `play()` returning).
func setup(
	p_battle: BattleScene, p_on_finished: Callable = Callable(), p_banner: Label = null
) -> void:
	battle = p_battle
	_on_finished = p_on_finished
	banner = p_banner
	if banner != null:
		banner.text = TACTICS_BANNER


## Sequential, gated playback (taskblock-15 Pass B1): each event plays out
## its own real duration (a slide, a facing turn, a shot's bright-to-dull
## fade) before the next one starts — never a pre-computed, independently-
## staggered cue list (docs/10 Phase 12.4's original LogPlayback-driven
## model, superseded here; LogPlayback itself is untouched and still
## correct on its own terms). Consecutive impacts get `INTER_SHOT_BREAK_MS`
## between them so a burst reads as distinct shots, not a smear.
func play(events: Array[LogEvent]) -> void:
	if banner != null:
		banner.text = RESOLUTION_BANNER
	_prime(events)

	await get_tree().create_timer(LogPlayback.RESOLVE_LEAD_IN / speed).timeout

	# taskblock-21 Pass F: a miss draws a real, timed tracer too now — the
	# same "space consecutive shots out" pacing impacts already got must
	# cover any run of impact/miss in either order, not just back-to-back
	# impacts, or a miss right after a hit (or another miss) would play
	# with no break at all.
	var previous_was_shot := false
	for event: LogEvent in events:
		var is_shot: bool = event.kind == &"impact" or event.kind == &"miss"
		if previous_was_shot and is_shot:
			await get_tree().create_timer((INTER_SHOT_BREAK_MS / 1000.0) / speed).timeout
		await _play_event(event)
		previous_was_shot = is_shot

	await get_tree().create_timer(LogPlayback.RESOLVE_TAIL / speed).timeout
	if banner != null:
		banner.text = TACTICS_BANNER
	if _on_finished.is_valid():
		_on_finished.call()


func _play_event(event: LogEvent) -> void:
	match event.kind:
		&"move":
			await _play_slide(event)
		&"faced":
			await _play_facing(event)
		&"impact":
			await _play_impact(event)
		&"miss":
			await _play_miss(event)
		_:
			pass


## Synchronously (no `await` — runs to completion in the same frame
## `battle.refresh_unit_views()` already did, before the engine ever
## presents that frame) ensures every unit with a move or facing change
## this turn has a REAL, WRITTEN `_display_cell`/`_display_orientation`
## entry before anything else touches either dict, then shows it — so the
## already-final `refresh()` never actually becomes visible first.
##
## Both dicts, not just whichever dimension the unit's OWN first event
## this turn happens to touch: a unit whose turn is
## `[faced(X), move(...), faced(Y final)]` — turn to face X, walk, turn to
## face Y — used to have its FIRST `faced(X)` event read `_display_
## orientation.get(id, X)` (X itself, the fallback, since nothing had
## ever written the dict yet) and silently, instantly snap with no visible
## transition at all (its own "from" trivially equalled its own target);
## the SLIDE that followed then read that same now-STALE dict value and
## rendered the whole walk at orientation X — a real, reported bug: a
## sudden, simultaneous position-and-rotation pop the instant the slide
## started, mid-turn, well past the point any earlier fix (priming a
## first-ever MOVE's own start cell alone) could catch. Seeding both
## dicts up front, once, fixes every ordering — not just move-first.
func _prime(events: Array[LogEvent]) -> void:
	var first_move: Dictionary = {}  # unit_id -> LogEvent
	var relevant: Dictionary = {}  # unit_id -> true
	for event: LogEvent in events:
		if event.kind == &"move":
			relevant[event.unit_id] = true
			if not first_move.has(event.unit_id):
				first_move[event.unit_id] = event
		elif event.kind == &"faced":
			relevant[event.unit_id] = true
	for unit_id: int in relevant:
		_ensure_primed(unit_id, first_move.get(unit_id))


## Writes a real starting `_display_cell`/`_display_orientation` entry for
## `unit_id` if either is still missing (a genuinely first-ever animated
## unit has neither — nothing to animate from, a harmless one-time snap),
## then applies it. `move_event`, if this unit has one this turn, supplies
## the real starting cell (`path[0]`) — what changed is that this is now
## written ONCE, up front, rather than left for whichever event happens to
## run first to (mis)infer on its own.
##
## taskblock-21 Pass G: orientation gets the SAME `move_event`-derived
## treatment now, for the same reason `_display_cell` already does — a
## real, reported bug: a unit whose first move this turn needed no
## preceding `faced` event at all (it already happened to be facing that
## way — a fresh spawn orientation lined up with its first move, say) used
## to prime here from `unit.orientation`, which by THIS call's own time
## (after resolution has already fully finished) is the turn's FINAL
## orientation — wrong if this same turn re-faces again later (an attack,
## a step-out's own return leg). `_play_slide` then read that same
## too-late value for its whole traversal: the unit visibly slid toward
## its real destination while facing wherever it turned to LATER instead.
## `orientation_toward(path[0], path[1])` is exactly what the move itself
## required to already be true — the same fact `apply_stepwise` itself
## used to decide no re-face was needed — so it's a strictly more correct
## fallback than the final state ever was. A turn with no move event at
## all (pure in-place turning) still has nothing analogous to derive from
## and keeps falling back to `unit.orientation`, unchanged.
func _ensure_primed(unit_id: int, move_event: Variant) -> void:
	var unit: Unit = battle.combat_state.find_unit(unit_id)
	if unit == null:
		return
	var move_path: Array = (
		(move_event as LogEvent).data.get("path", []) if move_event != null else []
	)
	if not _display_cell.has(unit_id):
		var start_cell: Vector2i = unit.cell
		if not move_path.is_empty():
			start_cell = move_path[0]
		_display_cell[unit_id] = start_cell
	if not _display_orientation.has(unit_id):
		var start_orientation: float = unit.orientation
		if move_path.size() >= 2:
			start_orientation = FaceAction.orientation_toward(move_path[0], move_path[1])
		_display_orientation[unit_id] = start_orientation
	_redraw(unit_id)


## Recomputes and applies `unit_id`'s own view transform from whatever its
## `_display_cell`/`_display_orientation` currently say (defaulting to the
## unit's own TRUE, already-final state the first time it's ever seen —
## nothing to animate from yet) against its TRUE final state. A safe no-op
## if the unit or its view no longer exists (a kill/subtree-drop can
## remove either mid-resolution).
func _redraw(unit_id: int) -> void:
	var view: HitVolumeView = _view_for(unit_id)
	var unit: Unit = battle.combat_state.find_unit(unit_id)
	if view == null or unit == null:
		return
	var display_cell: Vector2i = _display_cell.get(unit_id, unit.cell)
	var display_orientation: float = _display_orientation.get(unit_id, unit.orientation)
	_apply_display_transform(
		view, unit.cell, unit.orientation, _world_anchor(display_cell), display_orientation
	)


## The one place a compensating view transform is actually computed.
## `final_cell`/`final_orientation` are the TRUE state already baked into
## every child by `refresh()`; `display_anchor`/`display_orientation` are
## what should appear on screen right now instead. Rotation pivots on the
## unit's own FINAL body center — never the view's own local origin
## (world origin) — or a facing change swings the whole assembly through
## a wide, wrong arc around cell (0,0) instead of turning in place (the
## reported "fly off" bug).
func _apply_display_transform(
	view: HitVolumeView,
	final_cell: Vector2i,
	final_orientation: float,
	display_anchor: Vector3,
	display_orientation: float
) -> void:
	var delta_angle: float = display_orientation - final_orientation
	var pivot: Vector3 = _world_anchor(final_cell)
	var basis := Basis(Vector3.UP, delta_angle)
	view.basis = basis
	view.position = display_anchor - basis * pivot


func _world_anchor(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y) * UnitGeometry.CELL_SIZE


## B2: "slide — a MoveAction's start->end, PER CELL — slide_ms per cell."
## `_display_cell` (already primed to the path's own start cell, or the
## unit's own true cell if this is its first-ever animated move) walks
## forward one cell at a time; `tween_method` re-applies the full
## compensating transform every frame of each segment, so a facing offset
## still pending from an earlier event in this same turn keeps rendering
## correctly throughout — this never independently tweens a bare
## position/rotation Node property, only ever the combined, pivot-correct
## transform above.
## taskblock-19 Pass I1: the view/unit lookup used to happen INSIDE
## `_set_slide_anchor`, re-run on every single `tween_method` callback —
## a full `_view_for()` linear scan over `battle.unit_views` (and a
## matching `find_unit()` scan) every frame of every slide, for the
## entire animation's duration. Neither can actually change mid-slide
## (ResolutionPlayer only ever replays a turn's events AFTER
## resolve_turn() already finished mutating the real state — see this
## class's own header), so resolving both ONCE here and threading them
## through the tween's bound args removes real, unnecessary per-frame
## work instead of just moving it around.
func _play_slide(event: LogEvent) -> void:
	var unit: Unit = battle.combat_state.find_unit(event.unit_id)
	var view: HitVolumeView = _view_for(event.unit_id)
	if unit == null or view == null:
		return
	var path: Array = event.data.get("path", [])
	if path.size() < 2:
		return
	var per_cell: float = slide_segment_duration()
	for i in range(1, path.size()):
		var from_anchor: Vector3 = _world_anchor(path[i - 1])
		var to_anchor: Vector3 = _world_anchor(path[i])
		if per_cell <= 0.0:
			_set_slide_anchor(to_anchor, view, unit)
			continue
		var tween := create_tween()
		tween.tween_method(_set_slide_anchor.bind(view, unit), from_anchor, to_anchor, per_cell)
		await tween.finished
	_display_cell[event.unit_id] = path[path.size() - 1]
	_redraw(event.unit_id)


func _set_slide_anchor(anchor: Vector3, view: HitVolumeView, unit: Unit) -> void:
	if not is_instance_valid(view):
		return
	var display_orientation: float = _display_orientation.get(unit.id, unit.orientation)
	_apply_display_transform(view, unit.cell, unit.orientation, anchor, display_orientation)


## B2: "slide_ms per cell, scaled by pacing speed" — one cell-slide
## segment's own real duration. Pure and directly testable (TESTS: "a
## slide's ... total duration derive[s] from slide_ms × cells ÷ pacing" —
## the "× cells" half is `path.size() - 1` calls to this, in `_play_slide`
## above).
func slide_segment_duration() -> float:
	return (slide_ms / 1000.0) / speed


## B2: "facing — a FaceAction's start->end orientation — derived from
## slide_ms." Simplest faithful reading of "derived from," same status as
## every other unspecified formula shape in this codebase (CLAUDE.md: use
## the simplest faithful version, flag it, ask before tuning) — one
## cell-slide's own duration, not a second independent knob.
## `_display_cell` (already primed) stays wherever it currently is for the
## whole turn — position and facing never animate concurrently (B2 lists
## them as sequential steps), so this only ever moves `display_orientation`.
## taskblock-19 Pass I1: "the direction-change slowdown... probably the
## VIEW re-resolving something per direction-change" — exactly this:
## `_set_facing_angle` used to re-run a full `_view_for()`/`find_unit()`
## linear scan on every single frame of every facing tween. Resolved
## once here instead (see `_play_slide`'s own matching fix and doc
## comment — neither can change mid-turn-replay).
func _play_facing(event: LogEvent) -> void:
	var unit: Unit = battle.combat_state.find_unit(event.unit_id)
	if unit == null:
		return
	var target_orientation: float = float(event.data.get("direction", 0.0))
	var from_orientation: float = _display_orientation.get(event.unit_id, target_orientation)
	if is_equal_approx(from_orientation, target_orientation):
		_display_orientation[event.unit_id] = target_orientation
		return
	var duration: float = facing_duration()
	if duration <= 0.0:
		_display_orientation[event.unit_id] = target_orientation
		_redraw(event.unit_id)
		return
	var view: HitVolumeView = _view_for(event.unit_id)
	if view == null:
		return
	var tween := create_tween()
	tween.tween_method(
		_set_facing_angle.bind(view, unit), from_orientation, target_orientation, duration
	)
	await tween.finished
	_display_orientation[event.unit_id] = target_orientation
	_redraw(event.unit_id)


func _set_facing_angle(angle: float, view: HitVolumeView, unit: Unit) -> void:
	if not is_instance_valid(view):
		return
	var display_cell: Vector2i = _display_cell.get(unit.id, unit.cell)
	_apply_display_transform(view, unit.cell, unit.orientation, _world_anchor(display_cell), angle)


## TESTS: "facing duration is a function of slide_ms" — "turn built off
## slide speed" (B2), the same one cell-slide duration, not a second knob.
func facing_duration() -> float:
	return (slide_ms / 1000.0) / speed


## taskblock-22 Pass D: "every shot is visible... draw a tracer for every
## hop of a shot's path, not just muzzle -> first impact." `from` is THIS
## hop's own real muzzle (`origin_x/y` — the true shooter for a shot's
## first hop, the PREVIOUS hop's own deflection point for a ricochet) —
## never re-derived from the shooter's own current position, since a
## ricochet's real muzzle (a bounce point in open air) has no other way to
## reach at all.
##
## taskblock-23 Pass D: `origin_height`/`hit_height` (Pass A/C: every
## region and hop now has a real one) replace the old universal
## `TRACER_MUZZLE_HEIGHT`, and `to` now ALWAYS uses the hop's own logged
## `hit_x/hit_height/hit_y` — never a target unit's own composed box
## center (the old `_impact_point`, deleted): that center was ONE FIXED
## point per part, shared by every pellet that ever landed on it, which is
## the actual mechanism behind "a spread burst stitches one line across
## the body" the taskblock names — the pellet's own real per-shot
## resolved position (already logged, just unused for a Unit target)
## replaces it outright, `target == null` or not.
func _play_impact(event: LogEvent) -> void:
	var state: CombatState = battle.combat_state
	var attacker: Unit = state.find_unit(event.unit_id)
	if attacker == null:
		return
	var origin_x: float = float(event.data.get("origin_x", 0.0))
	var origin_y: float = float(event.data.get("origin_y", 0.0))
	var origin_height: float = float(event.data.get("origin_height", TRACER_MUZZLE_HEIGHT))
	var from := Vector3(origin_x, origin_height, origin_y) * UnitGeometry.CELL_SIZE

	var hit_x: float = float(event.data.get("hit_x", 0.0))
	var hit_y: float = float(event.data.get("hit_y", 0.0))
	var hit_height: float = float(event.data.get("hit_height", TRACER_MUZZLE_HEIGHT))
	var to := Vector3(hit_x, hit_height, hit_y) * UnitGeometry.CELL_SIZE

	await _spawn_tracer(from, to)

	# taskblock-26 Pass A1: "the bounced secondary ray is computed, logged,
	# never drawn." A DEFLECT outcome carries its own reflected endpoint
	# (ShotResolution.log_impact_result's void-ray convention, same shape
	# `log_miss_result` already uses) — drawn as a second, visually distinct
	# segment regardless of whether a real ricochet hop happens to follow
	# it (a ricochet that finds nothing to hit produces no further event
	# at all, so this is the only place that bounce is ever drawable).
	if (
		int(event.data.get("outcome", -1)) == Enums.Outcome.DEFLECT
		and event.data.has("deflect_end_x")
	):
		# taskblock-27 Pass A2: a beat between the primary impact and its own
		# deflect — "hit, then bounce," not both at once — distinct from
		# `INTER_SHOT_BREAK_MS`'s own gap between separate impact/miss pairs.
		await get_tree().create_timer((DEFLECT_BEAT_MS / 1000.0) / speed).timeout
		var deflect_end_x: float = float(event.data.get("deflect_end_x", hit_x))
		var deflect_end_y: float = float(event.data.get("deflect_end_y", hit_y))
		var deflect_end_height: float = float(event.data.get("deflect_end_height", hit_height))
		var deflect_to: Vector3 = (
			Vector3(deflect_end_x, deflect_end_height, deflect_end_y) * UnitGeometry.CELL_SIZE
		)
		await _spawn_tracer(to, deflect_to, TRACER_DEFLECT_COLOR, TRACER_DEFLECT_DULL_COLOR)


## taskblock-21 Pass F: "every fired shot draws its ray, hit or miss" —
## same `_spawn_tracer` bright-fade-dull path `_play_impact` above uses,
## just terminating at the miss's own logged void endpoint
## (`ShotResolution.log_miss_result`) instead of a struck part's world position.
## taskblock-23 Pass D: `origin_height`/`end_height` (real muzzle height,
## and the flat aim height a miss travels at — a miss can't ricochet, so
## there's no tilt to account for) replace `TRACER_MUZZLE_HEIGHT`.
func _play_miss(event: LogEvent) -> void:
	var state: CombatState = battle.combat_state
	var attacker: Unit = state.find_unit(event.unit_id)
	if attacker == null:
		return
	var origin_x: float = float(event.data.get("origin_x", attacker.cell.x))
	var origin_y: float = float(event.data.get("origin_y", attacker.cell.y))
	var origin_height: float = float(event.data.get("origin_height", TRACER_MUZZLE_HEIGHT))
	var from := Vector3(origin_x, origin_height, origin_y) * UnitGeometry.CELL_SIZE
	var end_x: float = float(event.data.get("end_x", 0.0))
	var end_y: float = float(event.data.get("end_y", 0.0))
	var end_height: float = float(event.data.get("end_height", TRACER_MUZZLE_HEIGHT))
	var end_point := Vector3(end_x, end_height, end_y) * UnitGeometry.CELL_SIZE
	await _spawn_tracer(from, end_point)


## B3: "bright draw -> fade -> dull tracer (two lifetimes, one word)" —
## drawn at full TRACER_COLOR (the live raycast), tweened to
## `TRACER_DULL_COLOR` (red, half-opacity) over `bullet_ms`, then handed to
## the ring buffer (or freed outright if `tracer_count <= 0` — B3's own
## "demo mode"). `translucent_material`, not `overlay_material`: the fade
## target's own alpha (0.5) has to actually blend, not just tint. Render
## priority starts at the LIVE tier so this shot draws over every already-
## retired tracer on the board, then drops to the shared retired tier the
## moment the fade finishes and it joins the ring.
## taskblock-26 Pass A1: `live_color`/`dull_color` default to the ordinary
## shot pair — a DEFLECT's own bounced continuation passes the distinct
## `TRACER_DEFLECT_COLOR`/`TRACER_DEFLECT_DULL_COLOR` pair instead, same
## draw/fade/retire mechanics either way.
func _spawn_tracer(
	from: Vector3,
	to: Vector3,
	live_color: Color = TRACER_COLOR,
	dull_color: Color = TRACER_DULL_COLOR
) -> void:
	if (to - from).length() < 0.001:
		return
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = TracerGeometry.segment_size(from, to, TRACER_THICKNESS)
	var material: StandardMaterial3D = WorldPalette.translucent_material(live_color)
	material.render_priority = TRACER_LIVE_RENDER_PRIORITY
	box.material = material
	instance.mesh = box
	instance.transform = TracerGeometry.segment_transform(from, to)
	_tracers.add_child(instance)

	var duration: float = bullet_fade_duration()
	if duration > 0.0:
		var tween := create_tween()
		tween.tween_property(material, "albedo_color", dull_color, duration)
		await tween.finished
	material.render_priority = TRACER_RETIRED_RENDER_PRIORITY
	_retire_tracer(instance)


## TESTS: "a shot draws bright then fades over bullet_ms" — B3's own
## "bullet_ms — covers draw+fade" default (250ms), scaled by pacing speed
## like every other duration here.
func bullet_fade_duration() -> float:
	return (bullet_ms / 1000.0) / speed


## `tracer_count <= 0`: no history kept, the tracer is simply freed once
## its own fade finishes. Otherwise: pushed onto the ring, evicting (and
## freeing) the oldest the instant the ring exceeds `tracer_count` — never
## more than N dull ghosts on screen at once.
func _retire_tracer(instance: MeshInstance3D) -> void:
	if tracer_count <= 0:
		_free_tracer(instance)
		return
	_tracer_ring.append(instance)
	while _tracer_ring.size() > tracer_count:
		_free_tracer(_tracer_ring.pop_front())


func _free_tracer(instance: MeshInstance3D) -> void:
	if is_instance_valid(instance):
		_tracers.remove_child(instance)
		instance.queue_free()


func _view_for(unit_id: int) -> HitVolumeView:
	for view: HitVolumeView in battle.unit_views:
		if view.unit != null and view.unit.id == unit_id:
			return view
	return null
