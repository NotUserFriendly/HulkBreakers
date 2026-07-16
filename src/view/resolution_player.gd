class_name ResolutionPlayer
extends Node

## docs/10 Phase 12.4: plays back a resolved turn's captured log purely as
## a cosmetic replay — by the time play() runs, resolve_turn() has already
## mutated the real state synchronously (TacticsController.end_turn()).
## This Node never drives the sim; it only holds the RESOLUTION banner,
## fires a muzzle->impact tracer per "impact" cue at LogPlayback's own
## staggered offsets, and keeps input locked for its total_duration()
## before handing control back to TACTICS.

const TACTICS_BANNER := "TACTICS"
const RESOLUTION_BANNER := "RESOLUTION"

## "Tracers may be raycast fakes — a line from muzzle to impact is enough"
## (docs/10). Muzzle height is a flagged placeholder (the log doesn't carry
## a real muzzle position) — roughly chest-height on the reference humanoid.
const TRACER_MUZZLE_HEIGHT := 1.25
const TRACER_THICKNESS := 0.03
const TRACER_LIFETIME := 0.15
const TRACER_COLOR := Color(1.0, 0.85, 0.3)

var banner: Label
var tactics: TacticsController

var _tracers: Node3D


func _init() -> void:
	_tracers = Node3D.new()
	add_child(_tracers)


func setup(p_banner: Label, p_tactics: TacticsController) -> void:
	banner = p_banner
	tactics = p_tactics
	banner.text = TACTICS_BANNER


## docs/10's barebones sequence: banner + lock (already true by the time
## this is called — TacticsController.end_turn() sets it) -> wait
## RESOLVE_LEAD_IN -> play cues, projectiles staggered by
## PROJECTILE_STAGGER -> wait RESOLVE_TAIL -> banner TACTICS + unlock.
func play(events: Array[LogEvent]) -> void:
	banner.text = RESOLUTION_BANNER
	var cues: Array[PlaybackCue] = LogPlayback.build(events)

	await get_tree().create_timer(LogPlayback.RESOLVE_LEAD_IN).timeout

	var elapsed := 0.0
	for cue: PlaybackCue in cues:
		var wait: float = cue.time - elapsed
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		elapsed = cue.time
		_play_cue(cue.event)

	await get_tree().create_timer(LogPlayback.RESOLVE_TAIL).timeout
	banner.text = TACTICS_BANNER
	tactics.unlock_input()


func _play_cue(event: LogEvent) -> void:
	if event.kind != &"impact":
		return
	var state: CombatState = tactics.selection.state
	var attacker: Unit = state.find_unit(event.unit_id)
	if attacker == null:
		return
	var target_id: int = int(event.data.get("target_unit_id", -1))
	var target: Unit = state.find_unit(target_id) if target_id >= 0 else null
	if target == null:
		return

	var impact_point: Vector3 = _impact_point(target, event.data.get("part", &""))
	_spawn_tracer(_muzzle_point(attacker), impact_point)


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


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var direction: Vector3 = to - from
	if direction.length() < 0.001:
		return
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(TRACER_THICKNESS, TRACER_THICKNESS, direction.length())
	box.material = WorldPalette.overlay_material(TRACER_COLOR)
	instance.mesh = box
	instance.transform = Transform3D(
		Basis.looking_at(-direction.normalized(), Vector3.UP), (from + to) * 0.5
	)
	_tracers.add_child(instance)
	_fade_out(instance)


func _fade_out(instance: MeshInstance3D) -> void:
	await get_tree().create_timer(TRACER_LIFETIME).timeout
	if is_instance_valid(instance):
		_tracers.remove_child(instance)
		instance.queue_free()
