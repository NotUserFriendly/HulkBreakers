class_name BoutInjector
extends RefCounted

## taskblock-29: the debug scalpel — a single, explicit entry point for
## mutating a LIVE `CombatState` from outside the turn loop, so CC (or the
## supervisor) can force a specific scenario into a running bout and watch
## it instead of waiting for one to occur naturally. `src/debug/`, not
## `src/logic/` (CLAUDE.md: "Debug = ASCII renderers, your eyes" — this is
## the same tier, a tool that inspects/mutates for a human's benefit, not
## game logic itself), view-agnostic but never reachable from a real
## player-controlled bout (Pass C/D: `SpectatorOverlay` is the only view
## that ever constructs one).
##
## **The core constraint: injection is a deliberate determinism break.**
## Every verb goes through ONE gate (`_guard`): reject outright if
## `state.is_resolving` (a mutation mid-`resolve_until` is forbidden, the
## same two-phase-turn discipline docs/09 already states, applied here);
## otherwise mark `state.was_injected` and log a distinct `&"inject"`
## event BEFORE doing anything else, naming exactly what's about to
## happen — so a bug found under injection is traceable to the injection
## that set it up.
##
## taskblock-41 Pass C: a rejected call still mutates nothing and still draws
## no RNG, but it is **no longer silent** (this reverses the original "no log
## entry" half — see `docs/SUPERSEDED.md`). Every verb emits a `command` event
## before anything can refuse it and a `command_outcome` after, carrying a
## machine-readable `reason` — a debug scalpel that quietly does nothing is
## indistinguishable from one that ran and had no effect, which is precisely
## the class of bug this project keeps producing.
##
## **No parallel systems.** Every verb below is a thin call into the real
## mutation path it fronts (`DeepStrike`/`BodyAssembler`, `KitEquipper`,
## `PartGraph`, `WoundEffects`, `CombatState.try_apply`) — injection
## INVOKES the real logic, it never reimplements it.

var state: CombatState


func _init(p_state: CombatState) -> void:
	state = p_state


## True iff a verb may mutate right now — never mid-resolution.
func can_inject() -> bool:
	return not state.is_resolving


## taskblock-41 Pass C: every verb's own first line. Logs "what was sent"
## (always, before anything can refuse it) and then answers the one gate every
## verb shares. False means the caller returns false immediately — the refusal
## is already logged by the time this returns.
##
## This is the `_guard` the file header has always described; it existed only
## as a convention repeated in 25 places until this pass gave it a body.
func _guard(kind: StringName, data: Dictionary = {}) -> bool:
	CommandLog.issued(state, kind, data)
	if state.is_resolving:
		# Kept alongside the log line, deliberately: `push_error` is what makes
		# this visible in the Godot console and in GUT's own error tracker, and
		# since tb41 Pass B it ALSO lands on the combat-log stream as a
		# `diagnostic`. The `command_outcome` below is the structured half —
		# greppable, with a machine-readable reason — not a duplicate of it.
		push_error("BoutInjector: %s rejected — injection mid-resolution is forbidden" % kind)
		_refuse(kind, &"mid_resolution", data)
		return false
	return true


## Every refusal below routes through here. Returns false so a caller reads
## `return _refuse(...)` and cannot refuse silently.
func _refuse(kind: StringName, reason: StringName, data: Dictionary = {}) -> bool:
	return CommandLog.refused(state, kind, reason, data)


## Every successful verb's own tail call: marks the bout non-deterministic
## for good and logs the `&"inject"` event. `unit_id` -1 — the same
## "no specific unit caused this" convention cover/terrain impacts already
## use (`ShotResolution`) — since an injection isn't attributed to any
## unit's own turn.
func _log_injection(kind: StringName, data: Dictionary, text: String) -> void:
	state.was_injected = true
	var full_data: Dictionary = data.duplicate()
	full_data["verb"] = kind
	state.combat_log.emit(
		LogEvent.new(state.round_number, Enums.Phase.RESOLUTION, -1, &"inject", full_data, text)
	)
	# taskblock-41 Pass C: the accepted half of the command/outcome pair. The
	# `inject` event above is unchanged and keeps carrying this verb's own rich
	# detail; this is the uniform outcome every command path emits, so "was it
	# accepted" is one grep across the injector AND the action path rather than
	# a different shape per verb.
	CommandLog.accepted(state, kind, data)


## Forces whose turn it is — `CombatState.force_current_unit`, which
## (deliberately, see its own doc comment) never resets AP/MP/facing the
## way a real `_begin_turn` would; a scenario that wants a fresh turn too
## should follow this with a real `set_ap`/`set_mp` call, not get one
## silently bundled in.
func force_current_unit(unit: Unit) -> bool:
	if not _guard(&"force_current_unit", {"unit": unit.id}):
		return false
	state.force_current_unit(unit.id)
	_log_injection(&"force_current_unit", {"unit": unit.id}, "unit %d forced current" % unit.id)
	return true


## taskblock-29 Pass B ---------------------------------------------------
## Each verb below is a thin call into a real, already-existing mutation
## path (see the file header's own "no parallel systems" note) — nothing
## here reimplements spawn/attach/damage/status logic.


## Spawns a unit from `preset` onto `cell`, squad-assignable — the SAME
## `DeepStrike.assemble_from_preset` + `CombatState.add_unit` (+, if the
## preset carries one, `KitEquipper`) path `BoutSetup._spawn_squad` itself
## uses. `matrix_id`, left `&""`, draws a fresh one from the BOUT's own
## `rng` (never a bare `randi()` — docs/00) so a re-run of the same
## injections in the same order stays reproducible-given-the-injections
## (Pass C). Returns null (no mutation, no log) on a preset that can't
## actually assemble — the same "never crash, never silently invent"
## posture `DeepStrike.assemble_from_preset` itself already has.
func spawn_unit(
	preset: BotPreset, cell: Vector2i, squad_id: int, matrix_id: StringName = &""
) -> Unit:
	if not _guard(&"spawn_unit", {"cell": cell, "squad": squad_id}):
		return null
	var matrix := Matrix.new()
	matrix.id = matrix_id if matrix_id != &"" else StringName("injected_%d" % state.rng.randi())
	var unit: Unit = DeepStrike.assemble_from_preset(preset, matrix, cell, squad_id)
	if unit == null:
		_refuse(&"spawn_unit", &"preset_could_not_assemble", {"preset": preset.preset_name})
		return null
	state.add_unit(unit)
	if preset.kit != null:
		KitEquipper.stock(unit, preset.kit, DeepStrike.reference_humanoid_pool())
		KitEquipper.equip(unit, preset.kit)
	_log_injection(
		&"spawn_unit",
		{"preset": preset.preset_name, "cell": cell, "squad_id": squad_id, "unit": unit.id},
		"spawned %s (unit %d) at %s, squad %d" % [preset.preset_name, unit.id, cell, squad_id]
	)
	return unit


## taskblock-30 follow-up (supervisor): "Kill is a new feature, that forces
## matrix ejection." Renamed from this session's own earlier `remove_unit`
## fix — the supervisor's own later request splits removal into two
## distinct debug verbs: this one (a REAL, narratively true death, visible
## as a downed corpse) and `remove_object` below (a debug-only "make it
## vanish entirely," no corpse). `CombatState.kill_unit` is the ONE place
## a unit's alive flag ever flips (vacates its cell, stays in `state.units`
## as a dead entry, same posture a real kill leaves behind) — never an
## actual array deletion, which would break any code still holding a
## reference to it. Refuses (no mutation) on an already-dead unit.
##
## `HitVolumeView.is_downed()`/the view's own DOWN pose read `Unit.
## resolve_matrix() == null` — never `alive` directly — because that's
## also exactly what a REAL kill leaves behind (`DamageResolver.
## eject_matrix_if_needed`/`eject_surrogate_if_needed`: null the hosting
## part's `hosted_matrix`, drop it as a loose field item, THEN
## `kill_unit`). `kill_unit` alone is only ever half of that — flipping
## `alive` with the matrix still docked leaves `resolve_matrix()` still
## finding it, so the view never changes. Ejecting the matrix here too —
## the same field-item drop, not a parallel mechanism — makes a debug
## kill read exactly like a real one, not a half-measure invisible to the
## one thing that actually checks it.
func kill(unit: Unit) -> bool:
	if not _guard(&"kill", {"unit": unit.id}):
		return false
	if not unit.alive:
		return _refuse(&"kill", &"already_dead", {"unit": unit.id})
	for part: Part in unit.shell.all_parts():
		if part.hosts_matrix() and part.hosted_matrix != null:
			var ejected: Matrix = part.hosted_matrix
			part.hosted_matrix = null
			if not state.grid.field_items.has(unit.cell):
				state.grid.field_items[unit.cell] = []
			state.grid.field_items[unit.cell].append(ejected)
			break
	state.kill_unit(unit)
	_log_injection(&"kill", {"unit": unit.id}, "unit %d killed" % unit.id)
	return true


## Shared by `set_position`/`move_object` (taskblock-30 follow-up) — the
## grid-occupancy mutation itself, no guard, no log: each public verb logs
## under its OWN name (the same split `_attach` already uses for
## `hand_weapon`/`attach_part`). Refuses (no mutation) onto an
## out-of-bounds or already-occupied cell.
## taskblock-41 Pass C: returns the REFUSAL REASON (`&""` on success) rather
## than a bare bool — a shared helper that only answers "no" gives its callers
## nothing to log, which is exactly the silent no-op this pass exists to
## delete.
func _move_unit(unit: Unit, cell: Vector2i) -> StringName:
	if not state.grid.in_bounds(cell):
		return &"destination_out_of_bounds"
	if state.grid.get_occupant_id(cell) != -1:
		return &"destination_occupied"
	if unit.alive:
		state.grid.set_occupant_id(unit.cell, -1)
	unit.cell = cell
	if unit.alive:
		state.grid.set_occupant_id(cell, unit.id)
	# taskblock-42 Pass E: `height`/`level` re-derived from the destination, the
	# same thing `CombatState.add_unit` and `MoveAction` both already do on every
	# real move. This was missing, so a debug move onto a raised cell left the
	# unit rendering at its OLD elevation — it moved in X/Z and stayed at the
	# wrong height. Invisible on a flat map, which is why it survived: every
	# headless fixture that exercised this verb was flat.
	unit.height = UnitGeometry.true_height_for_cell(cell, state.grid)
	unit.level = unit.height / UnitGeometry.LEVEL_HEIGHT
	return &""


## Moves `unit` to `cell` directly — no pathing, no AP/MP cost — updating
## `Grid`'s own occupancy the same way `MoveAction`/`CombatState.add_unit`
## already do, never a bare field write that leaves the grid stale.
## Refuses (no mutation) onto an out-of-bounds or already-occupied cell.
func set_position(unit: Unit, cell: Vector2i) -> bool:
	if not _guard(&"set_position", {"unit": unit.id, "cell": cell}):
		return false
	var from_cell: Vector2i = unit.cell
	var move_refusal: StringName = _move_unit(unit, cell)
	if move_refusal != &"":
		return _refuse(&"set_position", move_refusal, {"unit": unit.id, "cell": cell})
	_log_injection(
		&"set_position",
		{"unit": unit.id, "from": from_cell, "to": cell},
		"unit %d: %s -> %s" % [unit.id, from_cell, cell]
	)
	return true


## taskblock-30 follow-up (supervisor): "generalize move unit to move
## object, so I can move cover, units, or dropped objects." `target` is
## the SAME hit-shaped `{kind, unit, cell}` dict `board_clicked` already
## emits — the debug panel's own "active target" IS this verb's object
## param, no separate identity model. A UNIT hit moves the unit (through
## the SAME `_move_unit` helper `set_position` fronts, logged under this
## verb's own name instead — the `_attach` split, applied here). A CELL
## hit moves whatever `Grid.blockers` (authored cover, or a dropped
## subtree `DamageResolver._register_dropped` wrote there) and/or
## `Grid.field_items` (loose dropped weapons/matrices — `Grid`'s own
## "loose items lying on the ground") actually hold at that cell — a real
## dictionary re-key, preserving the Part's own state, never
## `place_cover`'s fresh-template duplicate. Refuses (no mutation) if the
## source cell holds neither, if a blocker would collide with one already
## at the destination, or if source and destination are the same cell.
func move_object(target: Dictionary, to_cell: Vector2i) -> bool:
	if not _guard(&"move_object", {"to_cell": to_cell}):
		return false
	if target.get("kind") == Enums.HitKind.UNIT:
		var unit: Variant = target.get("unit")
		if unit == null:
			return _refuse(&"move_object", &"target_names_no_unit")
		var unit_from_cell: Vector2i = (unit as Unit).cell
		var unit_refusal: StringName = _move_unit(unit, to_cell)
		if unit_refusal != &"":
			return _refuse(&"move_object", unit_refusal, {"unit": (unit as Unit).id})
		_log_injection(
			&"move_object",
			{"unit": (unit as Unit).id, "from": unit_from_cell, "to": to_cell},
			"unit %d: %s -> %s" % [(unit as Unit).id, unit_from_cell, to_cell]
		)
		return true
	var from_cell: Variant = target.get("cell")
	if from_cell == null:
		return _refuse(&"move_object", &"target_names_no_cell")
	if from_cell == to_cell:
		return _refuse(&"move_object", &"source_is_destination", {"cell": from_cell})
	if not state.grid.in_bounds(from_cell) or not state.grid.in_bounds(to_cell):
		return _refuse(&"move_object", &"out_of_bounds", {"from": from_cell, "to": to_cell})
	var has_blocker: bool = state.grid.blockers.has(from_cell)
	var has_items: bool = state.grid.field_items.has(from_cell)
	if not has_blocker and not has_items:
		return _refuse(&"move_object", &"nothing_at_source", {"from": from_cell})
	if has_blocker and state.grid.blockers.has(to_cell):
		return _refuse(&"move_object", &"destination_already_blocked", {"to": to_cell})
	if has_blocker:
		state.grid.blockers[to_cell] = state.grid.blockers[from_cell]
		state.grid.blockers.erase(from_cell)
	if has_items:
		var moving: Array = state.grid.field_items[from_cell]
		var existing: Array = state.grid.field_items.get(to_cell, [])
		state.grid.field_items[to_cell] = existing + moving
		state.grid.field_items.erase(from_cell)
	_log_injection(
		&"move_object",
		{"from": from_cell, "to": to_cell},
		"cell contents %s -> %s" % [from_cell, to_cell]
	)
	return true


## Shared by `place_cover`/`spawn_object` (taskblock-30 follow-up) — the
## raw blocker write, no guard, no log (the `_move_unit`/`_attach` split
## applied here too). Refuses (no mutation) onto an out-of-bounds or
## already-blocked cell, or an unknown pool id.
func _place_cover(cell: Vector2i, part_id: StringName, pool: Dictionary) -> StringName:
	if not state.grid.in_bounds(cell):
		return &"out_of_bounds"
	if state.grid.blockers.has(cell):
		return &"cell_already_blocked"
	var template: Part = pool.get(part_id)
	if template == null:
		return &"unknown_part_id"
	state.grid.blockers[cell] = template.duplicate(true)
	return &""


## Shared by `clear_cover`/`remove_object` — the raw blocker erase, no
## guard, no log. Refuses (no mutation) on a cell with no blocker.
func _clear_cover(cell: Vector2i) -> StringName:
	if not state.grid.blockers.has(cell):
		return &"no_blocker_at_cell"
	state.grid.blockers.erase(cell)
	return &""


## Shared by `spawn_object` — the raw `Grid.field_items` write, no guard,
## no log. A cell can hold several loose items at once (`Grid`'s own
## `Vector2i -> Array[Part|Matrix]` shape), so this appends, never
## overwrites. Refuses (no mutation) on an out-of-bounds cell or an
## unknown pool id.
func _spawn_field_item(cell: Vector2i, part_id: StringName, pool: Dictionary) -> StringName:
	if not state.grid.in_bounds(cell):
		return &"out_of_bounds"
	var template: Part = pool.get(part_id)
	if template == null:
		return &"unknown_part_id"
	if not state.grid.field_items.has(cell):
		state.grid.field_items[cell] = []
	state.grid.field_items[cell].append(template.duplicate(true))
	return &""


## taskblock-31 (rolled into tb30) Pass A: places a real field-object
## blocker at `cell` — the SAME mechanism `MapGen._scatter_cover` already
## uses (`grid.blockers[cell] = <a Part>`), never a parallel cover system.
## `Pathfinder.move_cost` already treats any `blockers` entry as
## impassable regardless of terrain, and `ShotPlane.build` already
## projects every `blockers` entry into the plane — so a placed cover
## part is real cover for free, nothing extra to wire. Refuses (no
## mutation) onto an out-of-bounds or already-blocked cell.
func place_cover(cell: Vector2i, part_id: StringName, pool: Dictionary) -> bool:
	if not _guard(&"place_cover", {"cell": cell, "part": part_id}):
		return false
	var place_refusal: StringName = _place_cover(cell, part_id, pool)
	if place_refusal != &"":
		return _refuse(&"place_cover", place_refusal, {"cell": cell, "part": part_id})
	_log_injection(
		&"place_cover", {"cell": cell, "part": part_id}, "cover %s at %s" % [part_id, cell]
	)
	return true


## The opposite of `place_cover` — `blockers.erase`, the same call
## `MapGen._set_open` already makes when it needs a cell genuinely clear.
## Refuses (no mutation) on a cell with no blocker to clear.
func clear_cover(cell: Vector2i) -> bool:
	if not _guard(&"clear_cover", {"cell": cell}):
		return false
	var clear_refusal: StringName = _clear_cover(cell)
	if clear_refusal != &"":
		return _refuse(&"clear_cover", clear_refusal, {"cell": cell})
	_log_injection(&"clear_cover", {"cell": cell}, "cover cleared at %s" % cell)
	return true


## taskblock-30 follow-up (supervisor): "spawn object (discrete from spawn
## unit)... currently cover items, and loose parts" — generalizes
## `place_cover` to also cover the OTHER half `Grid` itself already models
## (`field_items`, loose dropped Parts), one verb either way instead of
## two narrower ones. `as_cover` picks which real mechanism fronts it —
## `_place_cover` (a physical, shootable blocker) or `_spawn_field_item`
## (a loose item lying on the ground, pickable, never blocking). Refuses
## (no mutation) on whatever the chosen mechanism itself refuses on.
func spawn_object(cell: Vector2i, part_id: StringName, pool: Dictionary, as_cover: bool) -> bool:
	if not _guard(&"spawn_object", {"cell": cell, "part": part_id, "as_cover": as_cover}):
		return false
	var spawn_refusal: StringName = (
		_place_cover(cell, part_id, pool) if as_cover else _spawn_field_item(cell, part_id, pool)
	)
	if spawn_refusal != &"":
		return _refuse(&"spawn_object", spawn_refusal, {"cell": cell, "part": part_id})
	_log_injection(
		&"spawn_object",
		{"cell": cell, "part": part_id, "as_cover": as_cover},
		"spawned %s at %s (%s)" % [part_id, cell, "cover" if as_cover else "loose item"]
	)
	return true


## taskblock-30 follow-up (supervisor): "remove can be generalized to
## objects, covers, and things on tiles — fully vanishing it." `target` is
## the SAME hit-shaped `{kind, unit, cell}` dict `move_object` already
## consumes — one active-target-driven verb covers all three: a UNIT hit
## kills the unit through the real `CombatState.kill_unit` path (bare, no
## matrix ejection — that's `kill`'s own, narratively distinct verb; the
## VIEW-layer counterpart, `BattleScene.remove_unit_view`, is what makes
## it actually vanish from the board rather than linger as a downed
## corpse). Always "succeeds" for a real unit reference, alive or already
## dead — the debug intent ("make this go away") is achievable either way,
## unlike a narrative kill which can't happen twice. A CELL hit erases
## BOTH `Grid.blockers` and `Grid.field_items` at that cell if present —
## whatever's there, gone, not just one or the other. Refuses (no
## mutation) if the cell held neither.
func remove_object(target: Dictionary) -> bool:
	if not _guard(&"remove_object", {}):
		return false
	if target.get("kind") == Enums.HitKind.UNIT:
		var unit: Variant = target.get("unit")
		if unit == null:
			return _refuse(&"remove_object", &"target_names_no_unit")
		state.kill_unit(unit)
		_log_injection(
			&"remove_object", {"unit": (unit as Unit).id}, "unit %d removed" % (unit as Unit).id
		)
		return true
	var cell: Variant = target.get("cell")
	if cell == null:
		return _refuse(&"remove_object", &"target_names_no_cell")
	var removed_blocker: bool = _clear_cover(cell) == &""
	var removed_items: bool = state.grid.field_items.has(cell)
	if removed_items:
		state.grid.field_items.erase(cell)
	if not removed_blocker and not removed_items:
		return _refuse(&"remove_object", &"nothing_at_cell", {"cell": cell})
	_log_injection(&"remove_object", {"cell": cell}, "cell %s cleared" % cell)
	return true


## Flips `cell` between navigable and non-navigable — the real
## passability primitive every existing wall/cover fixture in this
## codebase already builds by hand, not a parallel mechanism layered over
## `place_cover`'s own `blockers` dictionary (those answer "is a
## physical, shootable thing here," this answers "can anything path
## through here at all").
##
## taskblock-39 Pass C: `Pathfinder` reads placed surfaces now, with no
## legacy terrain fallback — writing a raw WALL terrain code directly, as
## this used to, had already gone silently inert on any real (non-legacy)
## bout grid since tb38 Pass D shipped the surface-based path; only a
## bare legacy fixture ever actually saw it block. tb31 Pass C's own
## settled wall model, verbatim (`MapGen._finalize_walls_and_empty`'s
## "exposed wall" branch): floored ground stays floored — never
## re-placed, so an already-authored height survives — and passability
## comes from a real, destructible `wall` Part `blockers` entry plus
## opacity, the same "impassable and opaque together" pairing every real
## wall already carries.
func set_passable(cell: Vector2i, passable: bool) -> bool:
	if not _guard(&"set_passable", {"cell": cell, "passable": passable}):
		return false
	if not state.grid.in_bounds(cell):
		return _refuse(&"set_passable", &"out_of_bounds", {"cell": cell})
	if Surface.first_walkable(state.grid.surfaces_at(cell)) == null:
		GridPlacement.place(state.grid, cell, DataLibrary.get_part(&"ship_floor"), 0.0)
	if passable:
		state.grid.blockers.erase(cell)
		state.grid.set_opacity(cell, 0.0)
	else:
		state.grid.blockers[cell] = DataLibrary.get_part(&"wall")
		state.grid.set_opacity(cell, 1.0)
	_log_injection(
		&"set_passable",
		{"cell": cell, "passable": passable},
		"cell %s passable=%s" % [cell, passable]
	)
	return true


## taskblock-36 Pass D: forces a cell's own elevation — "the supervisor can
## then force a height scenario and watch it, which is the only way this
## gets visually confirmed before movement verbs exist." Also re-syncs any
## unit ALREADY standing on `cell` (the same `CombatState.add_unit` derives
## at spawn time), so forcing a scenario never requires respawning the
## unit that's already there.
## taskblock-37 Pass E follow-up (supervisor): `level` is a real `float`
## now, not a whole number — genuinely arbitrary elevation for a forced
## scenario, not just whole levels plus a ramp's own fixed half-step.
##
## taskblock-39 Pass C: elevation now lives on the cell's own placed
## `Surface`, so forcing it re-places one — keeping whatever `Part`
## (plain floor or ramp) and facing were already there, at the new
## height, rather than writing a `Grid.level` nothing reads anymore.
func set_cell_level(cell: Vector2i, level: float) -> bool:
	if not _guard(&"set_cell_level", {"cell": cell, "level": level}):
		return false
	if not state.grid.in_bounds(cell):
		return _refuse(&"set_cell_level", &"out_of_bounds", {"cell": cell})
	var existing: Surface = Surface.first_walkable(state.grid.surfaces_at(cell))
	var part: Part = existing.part if existing != null else DataLibrary.get_part(&"ship_floor")
	var facing: float = existing.facing if existing != null else 0.0
	state.grid.clear_surfaces(cell)
	GridPlacement.place(state.grid, cell, part, level * UnitGeometry.LEVEL_HEIGHT, facing)
	for unit: Unit in state.units:
		if unit.alive and unit.cell == cell:
			unit.level = level
			unit.height = UnitGeometry.true_height_for_cell(cell, state.grid)
	_log_injection(
		&"set_cell_level", {"cell": cell, "level": level}, "cell %s level=%.2f" % [cell, level]
	)
	return true


## Shared by `hand_weapon`/`attach_part` (taskblock-30/31) — attaches a
## fresh `part_id` duplicate (drawn from `pool`) into `socket_id` on
## `unit`, via `PartGraph.find_host_of_socket` (tb28)/`PartGraph.attach`,
## the same ops any ordinary assembly uses. Returns the attached Part, or
## null on any failure (unknown pool id, unknown socket, illegal
## attachment) — never logs itself; each caller logs under its OWN verb
## name, since "hand a weapon" and "attach a part" are readably distinct
## verbs in the combat log even though they share one mechanism.
## taskblock-41 Pass C: returns `{"part": Part, "reason": StringName}` rather
## than a bare Part-or-null. Three genuinely different failures used to
## collapse into one null, so neither caller could say WHICH — "attach_part
## rejected" with no reason is exactly the outcome this pass deletes.
func _attach(
	unit: Unit, part_id: StringName, socket_id: StringName, pool: Dictionary
) -> Dictionary:
	var template: Part = pool.get(part_id)
	if template == null:
		return {"part": null, "reason": &"unknown_part_id"}
	var host: Part = PartGraph.find_host_of_socket(unit.shell.root, socket_id)
	if host == null:
		return {"part": null, "reason": &"no_such_socket"}
	var socket: Socket = PartGraph.find_socket(host, socket_id)
	var attached: Part = template.duplicate(true)
	if not PartGraph.attach(attached, host, socket):
		return {"part": null, "reason": &"attachment_illegal"}
	return {"part": attached, "reason": &""}


## Directly attaches a fresh `weapon_id` duplicate into `socket_id` on
## `unit` — the blunt one-part version of `equip_from_kit`, for when a
## scenario just needs SOME weapon in hand rather than a whole authored
## kit. A named convenience over `attach_part` (below) — same mechanism,
## a clearer verb at the call site for the common case.
func hand_weapon(
	unit: Unit, weapon_id: StringName, socket_id: StringName, pool: Dictionary
) -> bool:
	if not _guard(&"hand_weapon", {"unit": unit.id, "weapon": weapon_id, "socket": socket_id}):
		return false
	var hand_result: Dictionary = _attach(unit, weapon_id, socket_id, pool)
	if hand_result["part"] == null:
		return _refuse(
			&"hand_weapon",
			hand_result["reason"],
			{"unit": unit.id, "weapon": weapon_id, "socket": socket_id}
		)
	_log_injection(
		&"hand_weapon",
		{"unit": unit.id, "weapon": weapon_id, "socket": socket_id},
		"unit %d hands %s at %s" % [unit.id, weapon_id, socket_id]
	)
	return true


## taskblock-31 (rolled into tb30) Pass B: the general case beneath
## `hand_weapon`/`equip_from_kit` — attach ANY part (an arm, a cladding
## plate, a backpack), not just a weapon. Same `_attach` mechanism, own
## verb name/log text.
func attach_part(unit: Unit, part_id: StringName, socket_id: StringName, pool: Dictionary) -> bool:
	if not _guard(&"attach_part", {"unit": unit.id, "part": part_id, "socket": socket_id}):
		return false
	var attach_result: Dictionary = _attach(unit, part_id, socket_id, pool)
	if attach_result["part"] == null:
		return _refuse(
			&"attach_part",
			attach_result["reason"],
			{"unit": unit.id, "part": part_id, "socket": socket_id}
		)
	_log_injection(
		&"attach_part",
		{"unit": unit.id, "part": part_id, "socket": socket_id},
		"unit %d: %s -> %s" % [unit.id, part_id, socket_id]
	)
	return true


## Runs `kit`'s own stock-then-equip (tb28 `KitEquipper`) on `unit`
## mid-bout — the exact self-arming path a bout-setup spawn already runs,
## forced after the fact instead of at spawn.
func equip_from_kit(unit: Unit, kit: Kit, pool: Dictionary) -> bool:
	if not _guard(&"equip_from_kit", {"unit": unit.id}):
		return false
	if not KitEquipper.stock(unit, kit, pool):
		return _refuse(&"equip_from_kit", &"kit_stock_failed", {"unit": unit.id})
	if not KitEquipper.equip(unit, kit):
		return _refuse(&"equip_from_kit", &"kit_equip_failed", {"unit": unit.id})
	_log_injection(
		&"equip_from_kit",
		{"unit": unit.id, "weapon": kit.weapon_part_id},
		"unit %d equips %s from its kit" % [unit.id, kit.weapon_part_id]
	)
	return true


## Forces `part_id`'s own `hp` on `unit` — no clamping, deliberately: the
## whole point of injection is forcing states a UI wouldn't let you reach,
## not re-guarding against them. Refuses (no mutation) if `unit` has no
## part by that id.
## taskblock-51 (`BR51.02`): **takes an object target, so it reaches parts that are not on a
## unit.**
##
## It required a `Unit`, which meant a goo barrel, a wall or any other field object could
## not be given an HP — and zeroing a barrel's HP is the deterministic route to forcing a
## detonation. Three open entries were unreachable behind that gap.
##
## The target is the same `{kind, unit, cell}` dict `move_object` and `remove_object`
## already take, resolved by the panel's own active-target memory. **Reused rather than
## given a new cell parameter**, because a second way to name the same thing is the
## duplicate-gesture problem `BR51.06` is already open about.
##
## `part_id` is optional for a cell target: empty means the blocker itself, which is what
## you want nine times in ten and saves typing an id to kill a barrel.
func set_part_hp(target: Variant, part_id: StringName, hp: int) -> bool:
	var resolved: Dictionary = _object_target(target)
	# `hp` stays in the recorded arguments: `test_command_log.gd` requires the call to be
	# reconstructable from the log alone, and dropping it while widening the target made
	# the command half of the pair incomplete.
	if not _guard(
		&"set_part_hp",
		{"target": resolved.get("describe", ""), "part": part_id, "hp": hp},
	):
		return false
	if resolved.has("refusal"):
		return _refuse(&"set_part_hp", resolved["refusal"], {"part": part_id})

	var part: Part = _find_part_in(resolved["root"], part_id)
	if part == null:
		return _refuse(
			&"set_part_hp",
			&"no_such_part",
			{"target": resolved.get("describe", ""), "part": part_id}
		)
	part.hp = hp
	_log_injection(
		&"set_part_hp",
		{"target": resolved.get("describe", ""), "part": part.id, "hp": hp},
		"%s: %s hp -> %d" % [resolved.get("describe", "?"), part.id, hp]
	)
	return true


## Resolve an object target to the part tree it names.
##
## Accepts a bare `Unit` as well as the `{kind, unit, cell}` dict, because the injector's
## own tests and the inspect panel call these methods directly with a unit and there is no
## reason to make them build a dict to do it.
func _object_target(target: Variant) -> Dictionary:
	if target is Unit:
		var unit := target as Unit
		return {"root": unit.shell.root, "describe": "unit %d" % unit.id}
	if target is Dictionary:
		var dict := target as Dictionary
		if dict.get("kind") == Enums.HitKind.UNIT:
			var hit_unit: Variant = dict.get("unit")
			if hit_unit == null:
				return {"refusal": &"target_names_no_unit"}
			return {
				"root": (hit_unit as Unit).shell.root,
				"describe": "unit %d" % (hit_unit as Unit).id,
			}
		# **The hit already knows which part it struck — use it rather than re-deriving.**
		# A click on cover resolves to a `PART` hit carrying the exact `Part`; looking the
		# cell up again in `blockers` is a second computation that can disagree with the
		# first, which is the substitution `docs/02` exists to forbid.
		if dict.get("kind") == Enums.HitKind.PART and dict.get("part") != null:
			var struck: Part = dict.get("part")
			return {"root": struck, "describe": "%s at %s" % [struck.id, dict.get("cell")]}
		var cell: Variant = dict.get("cell")
		if cell == null:
			return {"refusal": &"target_names_no_cell"}
		if state.grid.blockers.has(cell):
			return {
				"root": state.grid.blockers[cell] as Part,
				"describe": "blocker at %s" % [cell],
			}
		var items: Array = state.grid.field_items.get(cell, [])
		for item: Variant in items:
			if item is Part:
				return {"root": item as Part, "describe": "field item at %s" % [cell]}
		return {"refusal": &"nothing_at_cell"}
	return {"refusal": &"target_names_nothing"}


## The named part inside `root`'s own tree, or `root` itself when no id is given.
func _find_part_in(root: Part, part_id: StringName) -> Part:
	if root == null:
		return null
	if part_id == &"":
		return root
	for part: Part in PartGraph.walk(root):
		if part.id == part_id:
			return part
	return null


## Forces a status stack onto `part_id` on `unit`, through the SAME
## `WoundEffects.apply_if_status_crosses_threshold` the inspect panel's
## own `[*] Inflict Status: Burn` debug menu already calls — no separate
## status-injection mechanism.
func inflict_wound(
	unit: Unit, part_id: StringName, stack: float, threshold: float, wound_id: StringName
) -> bool:
	if not _guard(&"inflict_wound", {"unit": unit.id, "part": part_id, "wound": wound_id}):
		return false
	var part: Part = unit.shell.find_part(part_id)
	if part == null:
		return _refuse(&"inflict_wound", &"no_such_part", {"unit": unit.id, "part": part_id})
	WoundEffects.apply_if_status_crosses_threshold(part, stack, threshold, wound_id)
	_log_injection(
		&"inflict_wound",
		{"unit": unit.id, "part": part_id, "stack": stack, "wound": wound_id},
		"unit %d: %s stack %.1f against %s" % [unit.id, part_id, stack, wound_id]
	)
	return true


func set_ap(unit: Unit, ap: int) -> bool:
	if not _guard(&"set_ap", {"unit": unit.id, "ap": ap}):
		return false
	unit.ap = ap
	_log_injection(&"set_ap", {"unit": unit.id, "ap": ap}, "unit %d ap -> %d" % [unit.id, ap])
	return true


func set_mp(unit: Unit, mp: float) -> bool:
	if not _guard(&"set_mp", {"unit": unit.id, "mp": mp}):
		return false
	unit.mp = mp
	_log_injection(&"set_mp", {"unit": unit.id, "mp": mp}, "unit %d mp -> %.2f" % [unit.id, mp])
	return true


## taskblock-43 Pass C: assigns `unit` to a planning batch, or back to
## independence with `batch_id` 0 — the one way batches are assigned at all in
## this block (generated missions deliberately assign none). A plain field write
## with no backing mechanism to front, like `set_ap`/`set_facing` above; the
## behaviour it unlocks is the planner's, not this verb's.
##
## Deliberately NOT clamped or validated against existing batch ids: a batch is
## an open integer grouping, so "put this unit in a batch nothing else is in yet"
## is a legitimate thing to force, and inventing a registry to check against
## would be a second source of truth for something `Unit.batch_id` already fully
## describes.
func set_batch(unit: Unit, batch_id: int) -> bool:
	if not _guard(&"set_batch", {"unit": unit.id, "batch": batch_id}):
		return false
	unit.batch_id = batch_id
	_log_injection(
		&"set_batch",
		{"unit": unit.id, "batch": batch_id},
		(
			"unit %d -> batch %d" % [unit.id, batch_id]
			if batch_id != 0
			else "unit %d -> independent" % unit.id
		)
	)
	return true


func set_facing(unit: Unit, orientation: float) -> bool:
	if not _guard(&"set_facing", {"unit": unit.id, "orientation": orientation}):
		return false
	unit.orientation = orientation
	_log_injection(
		&"set_facing",
		{"unit": unit.id, "orientation": orientation},
		"unit %d facing -> %.2f" % [unit.id, orientation]
	)
	return true


## `Poses.by_id` (docs/10 taskblock05 G5) never returns null — an
## unrecognized id already falls back to `idle()` there, the same posture
## every other caller of it gets, not a special case here.
func set_pose(unit: Unit, pose_id: StringName) -> bool:
	if not _guard(&"set_pose", {"unit": unit.id, "pose": pose_id}):
		return false
	var pose: Pose = Poses.by_id(pose_id)
	unit.pose = pose
	_log_injection(
		&"set_pose", {"unit": unit.id, "pose": pose_id}, "unit %d pose -> %s" % [unit.id, pose_id]
	)
	return true


## taskblock-29 Pass B: therms (docs/PLAN.md "Power + Therms") are not
## built yet — no real backing path exists to front, so this is a
## flagged stub, never a faked mutation. Always refuses.
func set_therms(unit: Unit, part_id: StringName, _amount: float) -> bool:
	CommandLog.issued(state, &"set_therms", {"unit": unit.id, "part": part_id})
	push_error("BoutInjector: set_therms is a stub — therms are not built yet (docs/PLAN.md)")
	return _refuse(&"set_therms", &"not_implemented", {"unit": unit.id, "part": part_id})


## Arms an overwatch watch directly — the same `Unit.overwatch_weapon_id`
## field `OverwatchAction.apply` sets, un-gated (no legality/qualification
## check): a scenario forcing "this unit is watching with this weapon" may
## deliberately want a state a real `OverwatchAction` could never reach.
func force_overwatch_arm(unit: Unit, weapon_id: StringName) -> bool:
	if not _guard(&"force_overwatch_arm", {"unit": unit.id, "weapon": weapon_id}):
		return false
	unit.overwatch_weapon_id = weapon_id
	_log_injection(
		&"force_overwatch_arm",
		{"unit": unit.id, "weapon": weapon_id},
		"unit %d arms overwatch with %s" % [unit.id, weapon_id]
	)
	return true


## Forces a specific `CombatAction` into the live state right now —
## `CombatState.try_apply`, the SAME re-validating apply every ordinary
## action already goes through (never a bypass of `is_legal`). Refuses
## (no mutation, no log) if the action isn't actually legal — injection
## forces WHEN, never WHETHER, an action is allowed.
func force_action(action: CombatAction) -> bool:
	if not _guard(&"force_action", {"action": action.describe()}):
		return false
	if not state.try_apply(action):
		return _refuse(&"force_action", &"action_illegal", {"action": action.describe()})
	_log_injection(&"force_action", {"action": action.describe()}, "forced: %s" % action.describe())
	return true


## taskblock-37 Pass E: `force_action(ClimbAction.new(...))` under a name
## the debug panel can surface with plain scalar params (unit + cell) —
## nothing else can trigger a real climb yet (no AI path queues one,
## docs/PLAN.md's own follow-up item), and the supervisor needs a way to
## actually SEE one play before signing off on Pass E's own animation
## work. Real legality still applies (capability, rise cap, affordability)
## — this forces WHEN, never WHETHER, same as `force_action` itself.
func force_climb(unit: Unit, target_cell: Vector2i) -> bool:
	return force_action(ClimbAction.new(unit, target_cell))


## The mirror of `force_climb`, for `HopDownAction`.
func force_hop_down(unit: Unit, target_cell: Vector2i) -> bool:
	return force_action(HopDownAction.new(unit, target_cell))
