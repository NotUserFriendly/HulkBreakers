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
## that set it up, and a rejected call is a true no-op (nothing mutated,
## no log entry, no RNG draw).
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


func _reject(kind: StringName) -> void:
	push_error("BoutInjector: %s rejected — injection mid-resolution is forbidden" % kind)


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


## Forces whose turn it is — `CombatState.force_current_unit`, which
## (deliberately, see its own doc comment) never resets AP/MP/facing the
## way a real `_begin_turn` would; a scenario that wants a fresh turn too
## should follow this with a real `set_ap`/`set_mp` call, not get one
## silently bundled in.
func force_current_unit(unit: Unit) -> bool:
	if not can_inject():
		_reject(&"force_current_unit")
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
	if not can_inject():
		_reject(&"spawn_unit")
		return null
	var matrix := Matrix.new()
	matrix.id = matrix_id if matrix_id != &"" else StringName("injected_%d" % state.rng.randi())
	var unit: Unit = DeepStrike.assemble_from_preset(preset, matrix, cell, squad_id)
	if unit == null:
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


## taskblock-31 (rolled into tb30) Pass C: `spawn_unit`'s own opposite —
## `CombatState.kill_unit`, the ONE place a unit's alive flag ever flips
## (vacates its cell, stays in `state.units` as a dead entry, same posture
## a real kill leaves behind) — never an actual array deletion, which
## would break any code still holding a reference to it. Refuses (no
## mutation) on an already-dead unit.
##
## taskblock-30 follow-up (supervisor report): "removing a unit doesn't
## visually do anything." `HitVolumeView.is_downed()`/the view's own DOWN
## pose read `Unit.resolve_matrix() == null` — never `alive` directly —
## because that's also exactly what a REAL kill leaves behind
## (`DamageResolver.eject_matrix_if_needed`/`eject_surrogate_if_needed`:
## null the hosting part's `hosted_matrix`, drop it as a loose field item,
## THEN `kill_unit`). `kill_unit` alone was only ever half of that in this
## verb — flipping `alive` with the matrix still docked left `resolve_
## matrix()` still finding it, so the view kept rendering the unit exactly
## as before. Ejecting the matrix here too — the same field-item drop, not
## a parallel mechanism — makes a debug removal read exactly like a real
## kill, not a half-measure invisible to the one thing that actually
## checks it.
func remove_unit(unit: Unit) -> bool:
	if not can_inject():
		_reject(&"remove_unit")
		return false
	if not unit.alive:
		return false
	for part: Part in unit.shell.all_parts():
		if part.hosts_matrix() and part.hosted_matrix != null:
			var ejected: Matrix = part.hosted_matrix
			part.hosted_matrix = null
			if not state.grid.field_items.has(unit.cell):
				state.grid.field_items[unit.cell] = []
			state.grid.field_items[unit.cell].append(ejected)
			break
	state.kill_unit(unit)
	_log_injection(&"remove_unit", {"unit": unit.id}, "unit %d removed" % unit.id)
	return true


## Shared by `set_position`/`move_object` (taskblock-30 follow-up) — the
## grid-occupancy mutation itself, no guard, no log: each public verb logs
## under its OWN name (the same split `_attach` already uses for
## `hand_weapon`/`attach_part`). Refuses (no mutation) onto an
## out-of-bounds or already-occupied cell.
func _move_unit(unit: Unit, cell: Vector2i) -> bool:
	if not state.grid.in_bounds(cell) or state.grid.get_occupant_id(cell) != -1:
		return false
	if unit.alive:
		state.grid.set_occupant_id(unit.cell, -1)
	unit.cell = cell
	if unit.alive:
		state.grid.set_occupant_id(cell, unit.id)
	return true


## Moves `unit` to `cell` directly — no pathing, no AP/MP cost — updating
## `Grid`'s own occupancy the same way `MoveAction`/`CombatState.add_unit`
## already do, never a bare field write that leaves the grid stale.
## Refuses (no mutation) onto an out-of-bounds or already-occupied cell.
func set_position(unit: Unit, cell: Vector2i) -> bool:
	if not can_inject():
		_reject(&"set_position")
		return false
	var from_cell: Vector2i = unit.cell
	if not _move_unit(unit, cell):
		return false
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
	if not can_inject():
		_reject(&"move_object")
		return false
	if target.get("kind") == Enums.HitKind.UNIT:
		var unit: Variant = target.get("unit")
		if unit == null:
			return false
		var unit_from_cell: Vector2i = (unit as Unit).cell
		if not _move_unit(unit, to_cell):
			return false
		_log_injection(
			&"move_object",
			{"unit": (unit as Unit).id, "from": unit_from_cell, "to": to_cell},
			"unit %d: %s -> %s" % [(unit as Unit).id, unit_from_cell, to_cell]
		)
		return true
	var from_cell: Variant = target.get("cell")
	if from_cell == null or from_cell == to_cell:
		return false
	if not state.grid.in_bounds(from_cell) or not state.grid.in_bounds(to_cell):
		return false
	var has_blocker: bool = state.grid.blockers.has(from_cell)
	var has_items: bool = state.grid.field_items.has(from_cell)
	if not has_blocker and not has_items:
		return false
	if has_blocker and state.grid.blockers.has(to_cell):
		return false
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


## taskblock-31 (rolled into tb30) Pass A: places a real field-object
## blocker at `cell` — the SAME mechanism `MapGen._scatter_cover` already
## uses (`grid.blockers[cell] = <a Part>`), never a parallel cover system.
## `Pathfinder.move_cost` already treats any `blockers` entry as
## impassable regardless of terrain, and `ShotPlane.build` already
## projects every `blockers` entry into the plane — so a placed cover
## part is real cover for free, nothing extra to wire. Refuses (no
## mutation) onto an out-of-bounds or already-blocked cell.
func place_cover(cell: Vector2i, part_id: StringName, pool: Dictionary) -> bool:
	if not can_inject():
		_reject(&"place_cover")
		return false
	if not state.grid.in_bounds(cell) or state.grid.blockers.has(cell):
		return false
	var template: Part = pool.get(part_id)
	if template == null:
		return false
	state.grid.blockers[cell] = template.duplicate(true)
	_log_injection(
		&"place_cover", {"cell": cell, "part": part_id}, "cover %s at %s" % [part_id, cell]
	)
	return true


## The opposite of `place_cover` — `blockers.erase`, the same call
## `MapGen._set_open` already makes when it needs a cell genuinely clear.
## Refuses (no mutation) on a cell with no blocker to clear.
func clear_cover(cell: Vector2i) -> bool:
	if not can_inject():
		_reject(&"clear_cover")
		return false
	if not state.grid.blockers.has(cell):
		return false
	state.grid.blockers.erase(cell)
	_log_injection(&"clear_cover", {"cell": cell}, "cover cleared at %s" % cell)
	return true


## Flips `cell` between navigable (`OPEN`) and non-navigable (`WALL`) —
## the real passability primitive every existing wall/cover fixture in
## this codebase already builds by hand (`Pathfinder.move_cost` reads
## `terrain_costs[WALL]` as impassable by default), not a parallel
## mechanism layered over `place_cover`'s own `blockers` dictionary
## (those answer "is a physical, shootable thing here," this answers "can
## anything path through here at all"). Also sets opacity to match — a
## wall blocks sightlines too, the same "impassable and opaque together"
## pairing every real wall already carries (`passable=true` mirrors
## `MapGen._set_open`'s own reset: `OPEN` + zero opacity).
func set_passable(cell: Vector2i, passable: bool) -> bool:
	if not can_inject():
		_reject(&"set_passable")
		return false
	if not state.grid.in_bounds(cell):
		return false
	state.grid.set_terrain(cell, Enums.TerrainType.OPEN if passable else Enums.TerrainType.WALL)
	state.grid.set_opacity(cell, 0.0 if passable else 1.0)
	_log_injection(
		&"set_passable",
		{"cell": cell, "passable": passable},
		"cell %s passable=%s" % [cell, passable]
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
func _attach(unit: Unit, part_id: StringName, socket_id: StringName, pool: Dictionary) -> Part:
	var template: Part = pool.get(part_id)
	if template == null:
		return null
	var host: Part = PartGraph.find_host_of_socket(unit.shell.root, socket_id)
	if host == null:
		return null
	var socket: Socket = PartGraph.find_socket(host, socket_id)
	var attached: Part = template.duplicate(true)
	if not PartGraph.attach(attached, host, socket):
		return null
	return attached


## Directly attaches a fresh `weapon_id` duplicate into `socket_id` on
## `unit` — the blunt one-part version of `equip_from_kit`, for when a
## scenario just needs SOME weapon in hand rather than a whole authored
## kit. A named convenience over `attach_part` (below) — same mechanism,
## a clearer verb at the call site for the common case.
func hand_weapon(
	unit: Unit, weapon_id: StringName, socket_id: StringName, pool: Dictionary
) -> bool:
	if not can_inject():
		_reject(&"hand_weapon")
		return false
	if _attach(unit, weapon_id, socket_id, pool) == null:
		return false
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
	if not can_inject():
		_reject(&"attach_part")
		return false
	if _attach(unit, part_id, socket_id, pool) == null:
		return false
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
	if not can_inject():
		_reject(&"equip_from_kit")
		return false
	if not KitEquipper.stock(unit, kit, pool):
		return false
	if not KitEquipper.equip(unit, kit):
		return false
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
func set_part_hp(unit: Unit, part_id: StringName, hp: int) -> bool:
	if not can_inject():
		_reject(&"set_part_hp")
		return false
	var part: Part = unit.shell.find_part(part_id)
	if part == null:
		return false
	part.hp = hp
	_log_injection(
		&"set_part_hp",
		{"unit": unit.id, "part": part_id, "hp": hp},
		"unit %d: %s hp -> %d" % [unit.id, part_id, hp]
	)
	return true


## Forces a status stack onto `part_id` on `unit`, through the SAME
## `WoundEffects.apply_if_status_crosses_threshold` the inspect panel's
## own `[*] Inflict Status: Burn` debug menu already calls — no separate
## status-injection mechanism.
func inflict_wound(
	unit: Unit, part_id: StringName, stack: float, threshold: float, wound_id: StringName
) -> bool:
	if not can_inject():
		_reject(&"inflict_wound")
		return false
	var part: Part = unit.shell.find_part(part_id)
	if part == null:
		return false
	WoundEffects.apply_if_status_crosses_threshold(part, stack, threshold, wound_id)
	_log_injection(
		&"inflict_wound",
		{"unit": unit.id, "part": part_id, "stack": stack, "wound": wound_id},
		"unit %d: %s stack %.1f against %s" % [unit.id, part_id, stack, wound_id]
	)
	return true


func set_ap(unit: Unit, ap: int) -> bool:
	if not can_inject():
		_reject(&"set_ap")
		return false
	unit.ap = ap
	_log_injection(&"set_ap", {"unit": unit.id, "ap": ap}, "unit %d ap -> %d" % [unit.id, ap])
	return true


func set_mp(unit: Unit, mp: float) -> bool:
	if not can_inject():
		_reject(&"set_mp")
		return false
	unit.mp = mp
	_log_injection(&"set_mp", {"unit": unit.id, "mp": mp}, "unit %d mp -> %.2f" % [unit.id, mp])
	return true


func set_facing(unit: Unit, orientation: float) -> bool:
	if not can_inject():
		_reject(&"set_facing")
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
	if not can_inject():
		_reject(&"set_pose")
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
func set_therms(_unit: Unit, _part_id: StringName, _amount: float) -> bool:
	push_error("BoutInjector: set_therms is a stub — therms are not built yet (docs/PLAN.md)")
	return false


## Arms an overwatch watch directly — the same `Unit.overwatch_weapon_id`
## field `OverwatchAction.apply` sets, un-gated (no legality/qualification
## check): a scenario forcing "this unit is watching with this weapon" may
## deliberately want a state a real `OverwatchAction` could never reach.
func force_overwatch_arm(unit: Unit, weapon_id: StringName) -> bool:
	if not can_inject():
		_reject(&"force_overwatch_arm")
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
	if not can_inject():
		_reject(&"force_action")
		return false
	if not state.try_apply(action):
		return false
	_log_injection(&"force_action", {"action": action.describe()}, "forced: %s" % action.describe())
	return true
