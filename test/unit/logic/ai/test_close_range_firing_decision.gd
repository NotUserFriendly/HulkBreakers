extends GutTest

## taskblock-64 Pass A3 — **does a unit DECIDE to shoot at close range?**
##
## Passes A1 and A2 both measured `LoS.has_los` — a ray between two cell centres. That is
## **not the question `BR63.04`/`BR63.05` ask.** Sight is not the shot gate here:
## `AttackAction.is_legal`'s `has_los` check was deleted in taskblock-61 Pass D on the
## supervisor's own call, and `WorldView._has_direct_sight` says in its own comment that it is
## deliberately `LoS` and not `LineOfFire`. So a pair can pass every sweep in
## `test_generated_board_sight_sweep.gd` and still never produce a round.
##
## This file asks the planner instead, through the **real preset library**, on a **bare flat
## board with no geometry on it at all** — no wall, no cover, no ladder, nothing to occlude.
## Any refusal measured here cannot be blamed on sight, and that is the entire point of
## building it this way.
##
## **The seam this crosses is the one taskblock-63's gate did not.** Its 481 rounds were fired
## by `test_utility_planner.gd`-style synthetic units carrying a hand-authored `Part` with
## `provides_actions = [&"shoot"]` and `max_range = 30.0`. Every real preset in the library is
## armed differently, and two of the three cannot fire close in.

const PROFILE := &"aggressive"
## Big enough that nothing is ever near an edge, small enough to plan on quickly.
const BOARD := 24
## Which presets are held to "must be able to fire what it carries".
##
## **Read off `profile_family`, never a list in this file** — a designer adding a fourth combat
## tester sets the family on the `.tres` and is swept with no code edit (CLAUDE.md).
const COMBAT_FAMILY := &"combat_tester"


func should_skip_script():
	return SuiteTier.skip_if_fast()


## Every combat preset the library holds.
##
## **Scoped deliberately, and the exclusions are not incidental.** `kitted_chaingun` and the
## `a_brand_laborer` pair were built as fixtures for other tests rather than designed as
## fighting units — `kitted_chaingun` does not even assemble with a weapon (`KitEquipper:
## chaingun never made it into its own kit container backpack`). Holding them to a combat
## contract measures the fixtures, not the game. `kitted_chaingun`'s assembly failure is real
## and is filed rather than asserted here, because it is an equipping defect and this file is
## about what a planner decides.
func _presets() -> Array[BotPreset]:
	var presets: Array[BotPreset] = []
	for preset: BotPreset in DataLibrary.presets_pool():
		if preset.profile_family == COMBAT_FAMILY:
			presets.append(preset)
	presets.sort_custom(
		func(a: BotPreset, b: BotPreset) -> bool: return a.preset_name < b.preset_name
	)
	return presets


func _unit_from(preset: BotPreset, cell: Vector2i, squad_id: int) -> Unit:
	var matrix := Matrix.new()
	matrix.id = StringName("%s_%d" % [preset.preset_name, squad_id])
	var unit: Unit = DeepStrike.assemble_from_preset(preset, matrix, cell, squad_id)
	if unit != null and preset.kit != null:
		KitEquipper.equip(unit, preset.kit)
	return unit


## The weapon the planner would pick, and what it can offer — read off the real part rather
## than restated, so this reports the library and not a second copy of it.
func _weapon_note(unit: Unit) -> String:
	var best: Part = null
	for part: Part in unit.shell.operable_parts():
		if part.damage > 0.0 and (best == null or part.damage > best.damage):
			best = part
	if best == null:
		return "no weapon"
	var provides: Array[String] = []
	for id: StringName in best.provides_actions:
		provides.append(str(id))
	var minimum: float = RangeModel.min_range(best)
	var maximum: float = RangeModel.max_range(best)
	return (
		"%s provides[%s] min_range %.0f max_range %.0f"
		% [best.id, ", ".join(provides), minimum, maximum]
	)


## Runs one real planning turn and reports what the planner decided **and what it refused**.
func _decide(attacker: Unit, defender: Unit) -> Dictionary:
	var grid: Grid = GridFixture.flat(BOARD, BOARD)
	var state := CombatState.new(grid, [attacker, defender] as Array[Unit], 7)
	state.assign_rest_to_ai([] as Array[int])
	state.force_current_unit(attacker.id)
	for unit: Unit in state.units:
		unit.ap = unit.max_ap
		unit.mp = unit.mp_per_ap(unit.shell.operable_parts())

	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var view: WorldView = WorldView.full(state)
	view.restricted = true
	var queue: ActionQueue = await UtilityPlanner.plan_turn(attacker, view, null, PROFILE)
	state.combat_log.remove_sink(sink)

	# **Both firing classes, and the distinction is not cosmetic.** `BurstAction` extends
	# `CombatAction` beside `AttackAction` rather than under it, so an `is AttackAction` check
	# reads a working burst as silence — which is exactly the false negative this file exists
	# to catch, and it caught the measurement first.
	var fired: bool = false
	for action: CombatAction in queue.actions:
		if action is AttackAction or action is BurstAction:
			fired = true

	var winner: String = "nothing"
	var offered: Array[String] = []
	var refused: Array[String] = []
	var decisions: Array[LogEvent] = sink.events_of_kind(&"ai_utility_decision")
	if not decisions.is_empty():
		var data: Dictionary = decisions[0].data
		winner = str(data.get("winner", "nothing"))
		var seen: Dictionary = {}
		for candidate: Dictionary in data["candidates"] as Array:
			var id: String = str(candidate.get("action_id", "?"))
			if seen.has(id):
				continue
			seen[id] = true
			if bool(candidate.get("offered", false)):
				offered.append(id)
			else:
				refused.append(id)
	offered.sort()
	refused.sort()

	var visible: int = 0
	for other: Unit in view.units_visible_to(attacker):
		if other.squad_id != attacker.squad_id:
			visible += 1

	return {
		"fired": fired,
		"winner": winner,
		"offered": offered,
		"refused": refused,
		"enemies_visible": visible,
	}


## **The measurement.** Every preset, against every preset, at one/two/three cells, on ground
## with nothing on it. A cell reading `-` fired; anything else is a preset that cannot shoot an
## enemy standing next to it.
func test_every_preset_decides_to_shoot_an_adjacent_enemy_on_bare_ground() -> void:
	var presets: Array[BotPreset] = _presets()
	gut.p("presets in the library: %d" % presets.size())
	for preset: BotPreset in presets:
		var probe: Unit = _unit_from(preset, Vector2i(2, 2), 0)
		var tier: String = "?" if probe == null else str(probe.intelligence_tier)
		var note: String = "did not assemble" if probe == null else _weapon_note(probe)
		gut.p("  %-32s %-9s %s" % [preset.preset_name, tier, note])

	var silent: Array[String] = []
	for attacker_preset: BotPreset in presets:
		for distance: int in [1, 2, 3]:
			var attacker: Unit = _unit_from(attacker_preset, Vector2i(6, 6), 0)
			var defender: Unit = _unit_from(presets[0], Vector2i(6 + distance, 6), 1)
			if attacker == null or defender == null:
				continue
			var result: Dictionary = await _decide(attacker, defender)
			gut.p(
				(
					"  %-32s d=%d visible=%d -> %-16s %s"
					% [
						attacker_preset.preset_name,
						distance,
						result["enemies_visible"],
						result["winner"],
						"FIRED" if result["fired"] else "no shot"
					]
				)
			)
			if not bool(result["fired"]):
				gut.p("      offered: %s" % ", ".join(result["offered"] as Array[String]))
				gut.p("      refused: %s" % ", ".join(result["refused"] as Array[String]))
				silent.append("%s@%d" % [attacker_preset.preset_name, distance])

	assert_eq(
		silent,
		[] as Array[String],
		(
			"a preset that carries a weapon must be able to fire it at an enemy in plain sight on "
			+ "bare ground. **Not an assertion that every tier may shoot** — `docs/11` gates "
			+ "`shoot` to Grunt-and-above deliberately, and a MINDLESS unit having no firing "
			+ "action is that design working. What this refuses is a preset ARMED with a weapon "
			+ "its own tier can never fire, which is a library defect either way it is repaired: "
			+ "silent: %s" % ", ".join(silent)
		)
	)
