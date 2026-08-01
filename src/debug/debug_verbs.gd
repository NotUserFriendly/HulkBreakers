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

## taskblock-42 Pass E (BR35.03): which verbs actually change the BOARD — the
## grid's own surfaces, blockers or loose field items — and therefore need
## `BattleScene.sync_board_view()`, a full `BoardView.build()` of terrain, grid
## lines, every blocker and every field item.
##
## Every debug verb triggered that rebuild, including the ~20 that only ever
## touch one unit's AP, facing, pose or parts. **One authority for the answer,**
## read by both overlays' `_on_debug_panel_applied` — the same question answered
## twice in two files is how they drift.
##
## The list is checked against `all()` by a test — `place_cover`/`clear_cover`
## were in the first draft of it and are NOT panel verbs (the panel exposes
## `spawn_object`/`remove_object`, which front both). They matched nothing and
## would have quietly misled the next reader into thinking cover placement was
## covered by a different id than it is.
##
## `move_object` and `remove_object` are in the list unconditionally because
## either can target a cell OR a unit (their `target` dict decides at call
## time); claiming "unit only" for them would be wrong exactly half the time,
## and a missed board rebuild is an invisible-until-noticed bug rather than a
## slow one.
const BOARD_CHANGING_VERBS: Array[StringName] = [
	&"spawn_object",
	&"remove_object",
	&"move_object",
	&"set_passable",
	&"set_cell_level",
	# taskblock-51 `BR51.21`: added once `set_part_hp` could destroy things. Zeroing a part now
	# runs its failure mode (`BR51.20`), so a barrel forced to 0 hp leaves `grid.blockers` — and
	# without a board rebuild it stayed drawn while inspect showed an empty tile, which is
	# exactly what the supervisor saw.
	&"set_part_hp",
]


static func affects_board(verb_id: StringName) -> bool:
	return verb_id in BOARD_CHANGING_VERBS


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
		# taskblock-46 Pass B: **the one entry here that is not a `BoutInjector`
		# call, and the exception is deliberate.** Every other row wraps a verb that
		# MUTATES the bout; this one mutates nothing at all — it plays a sample of
		# throwaway missions elsewhere and writes what happened into the combat log.
		# It sits here because this table is the only surface that already turns "a
		# thing you can do from the game window" into a form with typed parameters,
		# and rebuilding that for one button would be the duplication this table
		# exists to avoid.
		# taskblock-47 Pass D: the other non-mutating row, and the reason the 100-seed
		# escalation could leave the gate. `sample_completion` says how many finished;
		# this shows you the ones that did not. A seed is already a complete
		# reproduction handle, so it takes a seed list and nothing else.
		DebugVerbSpec.new(
			&"watch_seeds",
			"Watch Seeds",
			[DebugVerbSpec.param(&"seeds", P.STRING_NAME)],
			Callable(DebugVerbs, &"_apply_watch_seeds")
		),
		DebugVerbSpec.new(
			&"sample_completion",
			"Sample Completion",
			[DebugVerbSpec.param(&"rng_seed", P.INT), DebugVerbSpec.param(&"seeds", P.INT)],
			Callable(DebugVerbs, &"_apply_sample_completion")
		),
		(
			DebugVerbSpec
			. new(
				&"set_aim_visual",
				"Aim Visual On/Off",
				[
					DebugVerbSpec.choice(&"element", AimView.TOGGLEABLE),
					DebugVerbSpec.param(&"on", P.BOOL),
				],
				Callable(DebugVerbs, &"_apply_set_aim_visual")
			)
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
			&"set_batch",
			"Set Batch",
			[DebugVerbSpec.param(&"unit", P.UNIT), DebugVerbSpec.param(&"batch_id", P.INT)],
			Callable(DebugVerbs, &"_apply_set_batch")
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
					DebugVerbSpec.param(&"target", P.OBJECT),
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


static func _apply_set_batch(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_batch(a.unit, a.batch_id)


static func _apply_set_pose(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_pose(a.unit, a.pose_id)


static func _apply_attach_part(inj: BoutInjector, pool: Dictionary, a: Dictionary) -> bool:
	return inj.attach_part(a.unit, a.part_id, a.socket_id, pool)


static func _apply_hand_weapon(inj: BoutInjector, pool: Dictionary, a: Dictionary) -> bool:
	return inj.hand_weapon(a.unit, a.weapon_id, a.socket_id, pool)


## taskblock-51 (`BR26.02`): turn one aim visual off and see what the framerate does.
##
## CC measured the aim view's per-frame *logic* at ~1 ms with no clones and no plane
## builds, against a reported 6 fps — so the cost is on the GPU, where CC is blind. This
## exists so the supervisor can bisect it in three clicks instead of CC guessing which
## draw is expensive.
##
## Element names are the `AimView` switches: `window`, `decal`, `targeting_line`,
## `pellet_circle`, `part_label`. An unknown name is refused by name rather than silently
## doing nothing, so a typo does not read as "that element is free".
static func _apply_set_aim_visual(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	var element: StringName = StringName(String(a.element))
	var on: bool = bool(a.on)
	match element:
		&"window":
			AimView.show_window = on
		&"decal":
			AimView.show_decal = on
		&"targeting_line":
			AimView.show_targeting_line = on
		&"pellet_circle":
			AimView.show_pellet_circle = on
		&"part_label":
			AimView.show_part_label = on
		&"wall_cutout":
			BoardView.show_wall_cutout = on
		&"occlusion_fade":
			BattleScene.show_occlusion_fade = on
		_:
			_note_aim_visual(inj, "aim visual: unknown element %s" % element, element, on)
			return false
	_note_aim_visual(inj, "aim visual %s -> %s" % [element, "on" if on else "off"], element, on)
	return true


## **Logged, but never as an injection.** This changes what is drawn and nothing about the
## simulation, so it must not set `was_injected` — that flag exists to mark a bout whose
## *results* cannot be trusted, and a hidden decal does not make a bout dirty. Same
## reasoning `_apply_sample_completion` already follows.
static func _note_aim_visual(
	inj: BoutInjector, text: String, element: StringName, on: bool
) -> void:
	inj.state.combat_log.emit(
		LogEvent.new(
			inj.state.round_number,
			Enums.Phase.RESOLUTION,
			-1,
			&"aim_visual",
			{"element": element, "on": on},
			text
		)
	)


static func _apply_set_part_hp(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	return inj.set_part_hp(a.target, a.part_id, a.hp)


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


## taskblock-46 Pass B: runs a completion sample and reports it into the combat log.
##
## **This blocks the window for roughly thirty seconds** — ten full missions, and
## nothing in the sampler suspends without a `PlanPacer`. That is stated rather than
## hidden because a debug tool that freezes silently reads as a crash. It is worth
## the freeze: the alternative to a button is a CC session, and `BR45.03`'s whole
## lesson was that a number nobody can re-take goes stale attached to a decision.
##
## **Reports through `CompletionSampler.describe`, the same function the headless
## test prints.** The in-window numbers cannot drift from the measured ones because
## there is only one formatter.
##
## `rng_seed` is a parameter rather than a clock read so a sample is reproducible:
## the log records which seeds were drawn, and the same `rng_seed` draws them again.
## taskblock-47 Pass D: play `seeds` as real, rendered bouts, in the order given.
##
## **Writes the criteria and the table into the combat log as well as the overlay.**
## The overlay is where you watch; the log is where it stays after you have stopped
## watching, and the two cannot disagree because both render through `WatchedRun`.
##
## Mutates nothing about the bout it was invoked from — it replaces it. That is worth
## saying plainly: this row swaps the board for a different one, which no other verb
## in this table does.
static func _apply_watch_seeds(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	var seeds: Array[int] = WatchedRun.parse_seeds(String(a.seeds))
	if seeds.is_empty():
		return false
	var run: WatchedRun = WatchedRun.of(seeds)
	for line: String in WatchedRun.describe_criteria(CompletionSampler.TURN_CAP, 0.35):
		inj.state.combat_log.emit(
			LogEvent.new(
				inj.state.round_number,
				Enums.Phase.RESOLUTION,
				-1,
				&"watched_run",
				{"seeds": seeds},
				line
			)
		)
	for line: String in run.describe_table():
		inj.state.combat_log.emit(
			LogEvent.new(
				inj.state.round_number, Enums.Phase.RESOLUTION, -1, &"watched_run", {}, line
			)
		)
	return true


static func _apply_sample_completion(inj: BoutInjector, _pool: Dictionary, a: Dictionary) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a.rng_seed)
	# **Sample size is a parameter, defaulting to the real one.** A spot check from the
	# panel, or a test of the reporting path, does not need eight full missions to see
	# whether the report comes out in the right shape.
	var seeds: int = int(a.get("seeds", CompletionSampler.SAMPLE_SEEDS))
	if seeds <= 0:
		seeds = CompletionSampler.SAMPLE_SEEDS
	var result: Dictionary = await CompletionSampler.sample(rng, 10000, seeds)
	for line: String in CompletionSampler.describe(result):
		inj.state.combat_log.emit(
			LogEvent.new(
				inj.state.round_number,
				Enums.Phase.RESOLUTION,
				-1,
				&"completion_sample",
				{"rng_seed": int(a.rng_seed), "rate": result.get("rate", 0.0)},
				line
			)
		)
	return true
