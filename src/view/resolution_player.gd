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

const TACTICS_BANNER := "TACTICS"
const RESOLUTION_BANNER := "RESOLUTION"

## "Tracers may be raycast fakes — a line from muzzle to impact is enough"
## (docs/10). Muzzle height is a flagged placeholder (the log doesn't carry
## a real muzzle position) — roughly chest-height on the reference humanoid.
const TRACER_MUZZLE_HEIGHT := 1.25
const TRACER_THICKNESS := 0.03
const TRACER_COLOR := Color(1.0, 0.85, 0.3)
## taskblock-15 Pass B3: "bright draw -> fade -> dull tracer" — the color a
## live shot fades TO, not away to nothing. `.darkened()`, not a
## hand-picked second color, so it stays visibly the same hue.
const INTER_SHOT_BREAK_MS := 100.0

## taskblock-15 Pass B4: "editable fields at the top of the spectator
## overlay... temporary debug knobs." Public, mutable — SpectatorOverlay's
## own UI writes into these directly; not baked constants.
var slide_ms: float = 100.0
var bullet_ms: float = 250.0
var tracer_count: int = 3
## Pacing speed (1x/2x/4x, taskblock-14 Pass C) — every duration below
## divides by this, so a faster watch speed animates faster too, not just
## steps more often.
var speed: float = 1.0

var banner: Label
var battle: BattleScene

var _tracer_dull_color: Color = TRACER_COLOR.darkened(0.7)
var _tracers: Node3D
## Ring buffer of persisted dull tracers, capped at `tracer_count` — the
## oldest is evicted the instant an (N+1)th arrives. `tracer_count <= 0`
## skips this stage entirely (B3: "the fade completes to nothing, no
## history kept — demo mode").
var _tracer_ring: Array[MeshInstance3D] = []
## unit_id -> the orientation this player last actually SHOWED that unit
## facing — a `faced` LogEvent only ever carries its own target, never
## where it turned FROM, so this is the one piece of state this class
## carries across playback calls (persists turn to turn, same object,
## same overlay's whole lifetime). A unit's very first-ever facing change
## has nothing to animate from and simply snaps — a harmless, one-time
## edge case, not worth inventing a fake "always faced 0 initially" origin
## for.
var _displayed_orientation: Dictionary = {}
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

	await get_tree().create_timer(LogPlayback.RESOLVE_LEAD_IN / speed).timeout

	var previous_was_impact := false
	for event: LogEvent in events:
		if previous_was_impact and event.kind == &"impact":
			await get_tree().create_timer((INTER_SHOT_BREAK_MS / 1000.0) / speed).timeout
		await _play_event(event)
		previous_was_impact = event.kind == &"impact"

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
		_:
			pass


## B2: "slide — a MoveAction's start->end, PER CELL — slide_ms per cell."
## Children are already rebuilt at the path's own FINAL cell
## (HitVolumeView.refresh() already ran, synchronously, before this).
## `view.position` is otherwise always identity (every child bakes its own
## absolute world position — see HitVolumeView's own header) — free to use
## here as a temporary, self-cancelling offset: set to "as if still at the
## previous cell," tweened cell by cell back to zero.
func _play_slide(event: LogEvent) -> void:
	var view: HitVolumeView = _view_for(event.unit_id)
	if view == null:
		return
	var path: Array = event.data.get("path", [])
	if path.size() < 2:
		return
	var final_cell: Vector2i = path[path.size() - 1]
	var per_cell: float = slide_segment_duration()
	view.position = _cell_offset(path[0], final_cell)
	for i in range(1, path.size()):
		var target_offset: Vector3 = _cell_offset(path[i], final_cell)
		if per_cell <= 0.0:
			view.position = target_offset
			continue
		var tween := create_tween()
		tween.tween_property(view, "position", target_offset, per_cell)
		await tween.finished
	view.position = Vector3.ZERO


## B2: "slide_ms per cell, scaled by pacing speed" — one cell-slide
## segment's own real duration. Pure and directly testable (TESTS: "a
## slide's ... total duration derive[s] from slide_ms × cells ÷ pacing" —
## the "× cells" half is `path.size() - 1` calls to this, in `_play_slide`
## above).
func slide_segment_duration() -> float:
	return (slide_ms / 1000.0) / speed


func _cell_offset(cell: Vector2i, relative_to: Vector2i) -> Vector3:
	return Vector3(cell.x - relative_to.x, 0.0, cell.y - relative_to.y) * UnitGeometry.CELL_SIZE


## B2: "facing — a FaceAction's start->end orientation — derived from
## slide_ms." Simplest faithful reading of "derived from," same status as
## every other unspecified formula shape in this codebase (CLAUDE.md: use
## the simplest faithful version, flag it, ask before tuning) — one
## cell-slide's own duration, not a second independent knob. Same
## compensating-offset technique as _play_slide, on `view.rotation.y`
## instead of `view.position`.
func _play_facing(event: LogEvent) -> void:
	var view: HitVolumeView = _view_for(event.unit_id)
	if view == null:
		return
	var target_orientation: float = float(event.data.get("direction", 0.0))
	var from_orientation: float = _displayed_orientation.get(event.unit_id, target_orientation)
	_displayed_orientation[event.unit_id] = target_orientation
	if is_equal_approx(from_orientation, target_orientation):
		return
	var duration: float = facing_duration()
	if duration <= 0.0:
		return
	view.rotation.y = from_orientation - target_orientation
	var tween := create_tween()
	tween.tween_property(view, "rotation:y", 0.0, duration)
	await tween.finished
	view.rotation.y = 0.0


## TESTS: "facing duration is a function of slide_ms" — "turn built off
## slide speed" (B2), the same one cell-slide duration, not a second knob.
func facing_duration() -> float:
	return (slide_ms / 1000.0) / speed


func _play_impact(event: LogEvent) -> void:
	var state: CombatState = battle.combat_state
	var attacker: Unit = state.find_unit(event.unit_id)
	if attacker == null:
		return
	var target_id: int = int(event.data.get("target_unit_id", -1))
	var target: Unit = state.find_unit(target_id) if target_id >= 0 else null
	if target == null:
		return

	var impact_point: Vector3 = _impact_point(target, event.data.get("part", &""))
	await _spawn_tracer(_muzzle_point(attacker), impact_point)


func _muzzle_point(unit: Unit) -> Vector3:
	return Vector3(unit.cell.x, TRACER_MUZZLE_HEIGHT, unit.cell.y) * UnitGeometry.CELL_SIZE


## The hit part's own composed world position if it's still findable (a
## subtree dropped later in the same resolution can remove it from the
## tree) — the unit's own cell as a cosmetic fallback otherwise.
func _impact_point(unit: Unit, part_id: StringName) -> Vector3:
	var part: Part = unit.shell.find_part(part_id)
	if part != null:
		for placement: BoxPlacement in UnitGeometry.placements(unit):
			if placement.part == part:
				return placement.transform * placement.box.center
	return _muzzle_point(unit)


## B3: "bright draw -> fade -> dull tracer (two lifetimes, one word)" —
## drawn at full TRACER_COLOR, tweened to `_tracer_dull_color` over
## `bullet_ms`, then handed to the ring buffer (or freed outright if
## `tracer_count <= 0` — B3's own "demo mode").
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	if (to - from).length() < 0.001:
		return
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = TracerGeometry.segment_size(from, to, TRACER_THICKNESS)
	var material: StandardMaterial3D = WorldPalette.overlay_material(TRACER_COLOR)
	box.material = material
	instance.mesh = box
	instance.transform = TracerGeometry.segment_transform(from, to)
	_tracers.add_child(instance)

	var duration: float = bullet_fade_duration()
	if duration > 0.0:
		var tween := create_tween()
		tween.tween_property(material, "albedo_color", _tracer_dull_color, duration)
		await tween.finished
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
