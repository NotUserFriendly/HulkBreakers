class_name BoutSetup
extends RefCounted

## taskblock-14 Pass D: the actual matchup-building logic behind
## "Simulate Bout" — headless, testable without the menu scene itself
## (docs/00 golden rule: logic is view-agnostic). Builds two squads from
## named profiles through the real `DeepStrike.assemble_from_preset`
## (Pass A: no parallel spawn path), a real generated map, and a
## `MissionState` with a genuine extraction zone so a winning squad can
## actually reach EXTRACTED (Pass C's own `BoutRunner` terminal-state
## model, unchanged) — this is the "in-engine 2v2 demo" the block exists
## for, wired to real content instead of hand-typed test fixtures.

const GRID_WIDTH := 20
const GRID_HEIGHT := 14


## `profile_a`/`profile_b` null, or either count `<= 0`, is refused with
## a named `error` — never a crash, matching every other assembly path's
## "never crash, never silently invent" posture. Returns
## `{"state": CombatState, "mission": MissionState, "error": ""}` on
## success, or `{"error": "<reason>"}` (no state/mission keys at all) on
## refusal.
static func build_bout(
	profile_a: BotPreset,
	count_a: int,
	playstyle_a: StringName,
	profile_b: BotPreset,
	count_b: int,
	playstyle_b: StringName,
	map_seed: int
) -> Dictionary:
	if profile_a == null or profile_b == null:
		return {"error": "both squads need a chosen profile"}
	if count_a <= 0 or count_b <= 0:
		return {"error": "both squads need at least one unit"}

	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var grid: Grid = MapGen.generate(rng.randi(), GRID_WIDTH, GRID_HEIGHT)
	var spawn_a_cells: Array[Vector2i] = _cells_of_terrain(grid, Enums.TerrainType.SPAWN_A)
	var spawn_b_cells: Array[Vector2i] = _cells_of_terrain(grid, Enums.TerrainType.SPAWN_B)

	var units: Array[Unit] = []
	units.append_array(_spawn_squad(profile_a, count_a, playstyle_a, 0, spawn_a_cells))
	units.append_array(_spawn_squad(profile_b, count_b, playstyle_b, 1, spawn_b_cells))
	if units.is_empty():
		return {"error": "neither profile could actually assemble (bad template_id?)"}

	var state := CombatState.new(grid, units, rng.randi())
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)

	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	mission.extraction_cells = (spawn_a_cells if not spawn_a_cells.is_empty() else [Vector2i.ZERO])

	return {"state": state, "mission": mission, "error": ""}


static func _spawn_squad(
	profile: BotPreset,
	count: int,
	playstyle: StringName,
	squad_id: int,
	spawn_cells: Array[Vector2i]
) -> Array[Unit]:
	var units: Array[Unit] = []
	for i in range(count):
		var matrix := Matrix.new()
		matrix.id = StringName("%s_%d" % [profile.preset_name, i])
		matrix.playstyle = playstyle
		var cell: Vector2i = (
			spawn_cells[i % spawn_cells.size()]
			if not spawn_cells.is_empty()
			else Vector2i(i, squad_id)
		)
		var unit: Unit = DeepStrike.assemble_from_preset(profile, matrix, cell, squad_id)
		if unit != null:
			units.append(unit)
	return units


static func _cells_of_terrain(grid: Grid, terrain: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_terrain(cell) == terrain:
				cells.append(cell)
	return cells


## taskblock-14 Pass D: "profile dropdowns list the .tres profiles
## (grouped by profile_family, variants shown under their base label)."
## `profile_family -> Array[BotPreset]`, base (empty `variant_label`)
## always first within its own group, variants after — so a dropdown can
## render a group heading followed by its own variants with no further
## sorting.
static func group_by_family(presets: Array[BotPreset]) -> Dictionary:
	var groups: Dictionary = {}  # StringName -> Array[BotPreset]
	for preset: BotPreset in presets:
		var family: StringName = (
			preset.profile_family
			if preset.profile_family != &""
			else StringName(preset.preset_name)
		)
		if not groups.has(family):
			groups[family] = [] as Array[BotPreset]
		(groups[family] as Array[BotPreset]).append(preset)
	for family: StringName in groups:
		var members: Array[BotPreset] = groups[family]
		members.sort_custom(
			func(a: BotPreset, b: BotPreset) -> bool: return a.variant_label < b.variant_label
		)
	return groups
