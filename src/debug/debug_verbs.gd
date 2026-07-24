class_name DebugVerbs
extends RefCounted

## taskblock-30/31 Pass C: the full verb table the debug control panel
## renders generically. Every `_apply_*` method is a one-line call into a
## real `BoutInjector` verb — the panel is a pure wrapper, never a second
## path (CLAUDE.md "no parallel systems"). Named static methods, not
## inline lambdas: a multi-line lambda body as a constructor argument
## trips this project's own GDScript parser (indentation-sensitive,
## confirmed the hard way) once a line runs past the 100-column gate and
## gdformat wraps it — a named method sidesteps that entirely and reads
## the same either way.
##
## Three real `BoutInjector` verbs are deliberately NOT here:
## `force_action` (needs an arbitrary `CombatAction` object, not a simple
## param form — no generic "build me any action" widget exists or should);
## `equip_from_kit` (needs a whole authored `Kit` resource, not scalar
## params — `hand_weapon`/`attach_part` already cover the single-item
## case a form CAN express); `set_therms` (a stub with nothing real to
## configure yet — docs/PLAN.md, therms aren't built).
##
## `set_position` (unit-only move), `place_cover`/`clear_cover` (blocker-
## only spawn/erase), and the old matrix-ejecting `remove_unit` (renamed
## `kill`, still its own row below — see next paragraph) are ALSO not
## their own rows anymore (taskblock-30 follow-up) — `move_object`,
## `spawn_object`, and `remove_object` generalize each across units,
## cover, and loose `Grid.field_items` alike, calling the narrower verbs
## internally where that's the real mechanism, so each underlying verb
## still exists and is still exercised, just never surfaced as a second,
## narrower panel entry next to its own generalization.
##
## `kill` vs `remove_object` (taskblock-30 follow-up, supervisor): two
## deliberately distinct debug verbs, not one. `kill` is a REAL,
## narratively true death (matrix ejected, a visible downed corpse — the
## exact thing a real in-bout kill leaves behind). `remove_object` is
## debug-only cleanup: whatever the active target is (a unit, cover, or a
## loose item) vanishes ENTIRELY — no corpse, nothing left to look at.

const P := DebugVerbSpec.ParamType


static func all() -> Array[DebugVerbSpec]:
	return [
		DebugVerbSpec.new(
			&"move_object",
			"Move Object",
			[DebugVerbSpec.param(&"object", P.OBJECT), DebugVerbSpec.param(&"to_cell", P.CELL)],
			Callable(DebugVerbs, &"_apply_move_object")
		),
		(
			DebugVerbSpec
			. new(
				&"spawn_unit",
				"Spawn Unit",
				[
					DebugVerbSpec.param(&"preset", P.PRESET),
					DebugVerbSpec.param(&"cell", P.CELL),
					DebugVerbSpec.param(&"squad_id", P.INT),
				],
				Callable(DebugVerbs, &"_apply_spawn_unit")
			)
		),
		DebugVerbSpec.new(
			&"remove_object",
			"Remove Object",
			[DebugVerbSpec.param(&"object", P.OBJECT)],
			Callable(DebugVerbs, &"_apply_remove_object")
		),
		DebugVerbSpec.new(
			&"kill",
			"Kill",
			[DebugVerbSpec.param(&"unit", P.UNIT)],
			Callable(DebugVerbs, &"_apply_kill")
		),
		DebugVerbSpec.new(
			&"force_current_unit",
			"Make Current",
			[DebugVerbSpec.param(&"unit", P.UNIT)],
			Callable(DebugVerbs, &"_apply_force_current_unit")
		),
		DebugVerbSpec.new(
			&"set_ap",
			"Set AP",
			[DebugVerbSpec.param(&"unit", P.UNIT), DebugVerbSpec.param(&"ap", P.INT)],
			Callable(DebugVerbs, &"_apply_set_ap")
		),
		DebugVerbSpec.new(
			&"set_mp",
			"Set MP",
			[DebugVerbSpec.param(&"unit", P.UNIT), DebugVerbSpec.param(&"mp", P.FLOAT)],
			Callable(DebugVerbs, &"_apply_set_mp")
		),
		DebugVerbSpec.new(
			&"set_facing",
			"Set Facing",
			[DebugVerbSpec.param(&"unit", P.UNIT), DebugVerbSpec.param(&"orientation", P.FLOAT)],
			Callable(DebugVerbs, &"_apply_set_facing")
		),
		DebugVerbSpec.new(
			&"set_pose",
			"Set Pose",
			[DebugVerbSpec.param(&"unit", P.UNIT), DebugVerbSpec.param(&"pose_id", P.POSE)],
			Callable(DebugVerbs, &"_apply_set_pose")
		),
		(
			DebugVerbSpec
			. new(
				&"attach_part",
				"Attach Part",
				[
					DebugVerbSpec.param(&"unit", P.UNIT),
					DebugVerbSpec.param(&"part_id", P.STRING_NAME),
					DebugVerbSpec.param(&"socket_id", P.STRING_NAME),
				],
				Callable(DebugVerbs, &"_apply_attach_part")
			)
		),
		(
			DebugVerbSpec
			. new(
				&"hand_weapon",
				"Hand Weapon",
				[
					DebugVerbSpec.param(&"unit", P.UNIT),
					DebugVerbSpec.param(&"weapon_id", P.STRING_NAME),
					DebugVerbSpec.param(&"socket_id", P.STRING_NAME),
				],
				Callable(DebugVerbs, &"_apply_hand_weapon")
			)
		),
		(
			DebugVerbSpec
			. new(
				&"set_part_hp",
				"Set Part HP",
				[
					DebugVerbSpec.param(&"unit", P.UNIT),
					DebugVerbSpec.param(&"part_id", P.STRING_NAME),
					DebugVerbSpec.param(&"hp", P.INT),
				],
				Callable(DebugVerbs, &"_apply_set_part_hp")
			)
		),
		(
			DebugVerbSpec
			. new(
				&"inflict_wound",
				"Inflict Wound",
				[
					DebugVerbSpec.param(&"unit", P.UNIT),
					DebugVerbSpec.param(&"part_id", P.STRING_NAME),
					DebugVerbSpec.param(&"stack", P.FLOAT),
					DebugVerbSpec.param(&"threshold", P.FLOAT),
					DebugVerbSpec.param(&"wound_id", P.STRING_NAME),
				],
				Callable(DebugVerbs, &"_apply_inflict_wound")
			)
		),
		(
			DebugVerbSpec
			. new(
				&"spawn_object",
				"Spawn Object",
				[
					DebugVerbSpec.param(&"cell", P.CELL),
					DebugVerbSpec.param(&"part_id", P.STRING_NAME),
					DebugVerbSpec.param(&"as_cover", P.BOOL),
				],
				Callable(DebugVerbs, &"_apply_spawn_object")
			)
		),
		DebugVerbSpec.new(
			&"set_passable",
			"Set Passable",
			[DebugVerbSpec.param(&"cell", P.CELL), DebugVerbSpec.param(&"passable", P.BOOL)],
			Callable(DebugVerbs, &"_apply_set_passable")
		),
		(
			DebugVerbSpec
			. new(
				&"set_cell_level",
				"Set Cell Level",
				# taskblock-37 Pass E follow-up (supervisor): FLOAT, not INT --
				# Grid.level is a real, arbitrary-precision elevation now.
				[DebugVerbSpec.param(&"cell", P.CELL), DebugVerbSpec.param(&"level", P.FLOAT)],
				Callable(DebugVerbs, &"_apply_set_cell_level")
			)
		),
		(
			DebugVerbSpec
			. new(
				&"force_overwatch_arm",
				"Force Overwatch Arm",
				[
					DebugVerbSpec.param(&"unit", P.UNIT),
					DebugVerbSpec.param(&"weapon_id", P.STRING_NAME),
				],
				Callable(DebugVerbs, &"_apply_force_overwatch_arm")
			)
		),
		DebugVerbSpec.new(
			&"force_climb",
			"Force Climb",
			[DebugVerbSpec.param(&"unit", P.UNIT), DebugVerbSpec.param(&"target_cell", P.CELL)],
			Callable(DebugVerbs, &"_apply_force_climb")
		),
		DebugVerbSpec.new(
			&"force_hop_down",
			"Force Hop Down",
			[DebugVerbSpec.param(&"unit", P.UNIT), DebugVerbSpec.param(&"target_cell", P.CELL)],
			Callable(DebugVerbs, &"_apply_force_hop_down")
		),
	]


static func _apply_move_object(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.move_object(a.object, a.to_cell)


static func _apply_spawn_unit(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.spawn_unit(a.preset, a.cell, a.squad_id) != null


static func _apply_remove_object(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.remove_object(a.object)


static func _apply_kill(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.kill(a.unit)


static func _apply_force_current_unit(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.force_current_unit(a.unit)


static func _apply_set_ap(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_ap(a.unit, a.ap)


static func _apply_set_mp(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_mp(a.unit, a.mp)


static func _apply_set_facing(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_facing(a.unit, a.orientation)


static func _apply_set_pose(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_pose(a.unit, a.pose_id)


static func _apply_attach_part(inj: BoutInjector, pool: Dictionary, a: Dictionary) -> bool:
	return inj.attach_part(a.unit, a.part_id, a.socket_id, pool)


static func _apply_hand_weapon(inj: BoutInjector, pool: Dictionary, a: Dictionary) -> bool:
	return inj.hand_weapon(a.unit, a.weapon_id, a.socket_id, pool)


static func _apply_set_part_hp(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_part_hp(a.unit, a.part_id, a.hp)


static func _apply_inflict_wound(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.inflict_wound(a.unit, a.part_id, a.stack, a.threshold, a.wound_id)


static func _apply_spawn_object(inj: BoutInjector, pool: Dictionary, a: Dictionary) -> bool:
	return inj.spawn_object(a.cell, a.part_id, pool, a.as_cover)


static func _apply_set_passable(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_passable(a.cell, a.passable)


static func _apply_set_cell_level(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_cell_level(a.cell, a.level)


static func _apply_force_overwatch_arm(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.force_overwatch_arm(a.unit, a.weapon_id)


static func _apply_force_climb(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.force_climb(a.unit, a.target_cell)


static func _apply_force_hop_down(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.force_hop_down(a.unit, a.target_cell)
