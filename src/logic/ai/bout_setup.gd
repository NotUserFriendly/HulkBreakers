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

## taskblock-17 Pass A: the old 20x14 was under `MapGen.MIN_LEAF_SIZE * 2`
## (24) on both axes — the same single-room-forever regression
## `BattleScene`'s own default had, just with a smaller bout map. A bout
## can afford to stay smaller than a full battle's board (`BattleScene`'s
## own 40x30), but still needs real room to split — 32x24 matches the
## size `test_map_gen.gd`'s own 50-seed sweep already exercises.
const GRID_WIDTH := 32
const GRID_HEIGHT := 24


## taskblock-17 Pass D: playstyle moved from per-team to per-bot — each
## team is now a LIST of `BoutRosterEntry` (profile + that bot's own
## playstyle), not a list of profiles plus one shared playstyle. "The
## list length IS the count" (taskblock-16 E) still holds. An empty list,
## or any entry within one carrying no profile (a slot the menu never
## actually produces — an [+ Add] row only appends once a profile is
## picked — but `build_bout` itself never trusts its caller to enforce
## that), is refused with a named `error` — never a crash, matching every
## other assembly path's "never crash, never silently invent" posture.
## Returns `{"state": CombatState, "mission": MissionState, "error": ""}`
## on success, or `{"error": "<reason>"}` (no state/mission keys at all)
## on refusal.
static func build_bout(
	roster_a: Array[BoutRosterEntry], roster_b: Array[BoutRosterEntry], map_seed: int
) -> Dictionary:
	if roster_a.is_empty() or roster_b.is_empty():
		return {"error": "both squads need at least one unit"}
	if roster_a.any(_entry_missing_profile) or roster_b.any(_entry_missing_profile):
		return {"error": "every roster entry needs a chosen profile"}

	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var grid: Grid = MapGen.generate(rng.randi(), GRID_WIDTH, GRID_HEIGHT)
	var spawn_a_cells: Array[Vector2i] = _cells_of_terrain(grid, Enums.TerrainType.SPAWN_A)
	var spawn_b_cells: Array[Vector2i] = _cells_of_terrain(grid, Enums.TerrainType.SPAWN_B)

	var units: Array[Unit] = []
	units.append_array(_spawn_squad(roster_a, 0, spawn_a_cells))
	units.append_array(_spawn_squad(roster_b, 1, spawn_b_cells))
	if units.is_empty():
		return {"error": "neither roster could actually assemble (bad template_id?)"}

	var state := CombatState.new(grid, units, rng.randi())
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)

	var mission := MissionState.new(RunState.new(), state)
	mission.objectives = []
	# taskblock-23 Pass E1: "in bout setup, place each team's extraction
	# near the OPPOSING team's spawn — this pulls the teams through each
	# other and forces engagement." Superseded from tb21 D's own original
	# placement (each squad's own spawn doubling as its own extraction,
	# so both teams could sit still on their own side with no reason to
	# cross at all) — a BOUT-SETUP-ONLY choice, never real mission-gen
	# (later, map-design-driven) extraction placement, which this file
	# has no bearing on at all.
	mission.team_extraction_cells = {
		0: spawn_b_cells if not spawn_b_cells.is_empty() else [Vector2i.ZERO],
		1: spawn_a_cells if not spawn_a_cells.is_empty() else [Vector2i.ZERO],
	}
	# The flat, legacy fallback field (tb22 A: only ever consulted for the
	# mission's OWN player squad, squad 0 here) kept consistent with squad
	# 0's real extraction above, rather than left pointing at its own
	# spawn — a stale value `team_extraction_cells` no longer agrees with.
	mission.extraction_cells = (spawn_b_cells if not spawn_b_cells.is_empty() else [Vector2i.ZERO])

	return {"state": state, "mission": mission, "error": ""}


static func _entry_missing_profile(entry: BoutRosterEntry) -> bool:
	return entry.profile == null


static func _spawn_squad(
	roster: Array[BoutRosterEntry], squad_id: int, spawn_cells: Array[Vector2i]
) -> Array[Unit]:
	var units: Array[Unit] = []
	for i in range(roster.size()):
		var entry: BoutRosterEntry = roster[i]
		var matrix := Matrix.new()
		matrix.id = StringName("%s_%d" % [entry.profile.preset_name, i])
		matrix.playstyle = entry.playstyle
		var cell: Vector2i = (
			spawn_cells[i % spawn_cells.size()]
			if not spawn_cells.is_empty()
			else Vector2i(i, squad_id)
		)
		var unit: Unit = DeepStrike.assemble_from_preset(entry.profile, matrix, cell, squad_id)
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
