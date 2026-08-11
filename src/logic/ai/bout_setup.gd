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


## taskblock-17 Pass D: the AI choice moved from per-team to per-bot — each
## team is now a LIST of `BoutRosterEntry` (profile + that bot's own
## AI profile), not a list of presets plus one shared choice. "The
## list length IS the count" (taskblock-16 E) still holds. An empty list,
## or any entry within one carrying no profile (a slot the menu never
## actually produces — an [+ Add] row only appends once a profile is
## picked — but `build_bout` itself never trusts its caller to enforce
## that), is refused with a named `error` — never a crash, matching every
## other assembly path's "never crash, never silently invent" posture.
## Returns `{"state": CombatState, "mission": MissionState, "error": ""}`
## on success, or `{"error": "<reason>"}` (no state/mission keys at all)
## on refusal.
## tb64 Pass E: `victory_mode` defaults to `MissionState.VICTORY_EXTRACTION`, so every existing
## caller — the completion sampler, every headless fixture — keeps the behaviour it had.
static func build_bout(
	roster_a: Array[BoutRosterEntry],
	roster_b: Array[BoutRosterEntry],
	map_seed: int,
	victory_mode: StringName = MissionState.VICTORY_EXTRACTION
) -> Dictionary:
	if roster_a.is_empty() or roster_b.is_empty():
		return {"error": "both squads need at least one unit"}
	if roster_a.any(_entry_missing_profile) or roster_b.any(_entry_missing_profile):
		return {"error": "every roster entry needs a chosen profile"}

	# taskblock-47 Pass A: counted after the validation gates, so a rejected roster
	# is not reported as a bout that was played.
	CombatState.bouts_built += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed

	# tb62 Pass A: **the roster is assembled BEFORE the map, because the map's own
	# navigability invariant is judged against the roster.** `step_height` is a per-unit
	# stat now, so "is every cell reachable" has no answer until you know who is walking —
	# a 0.6 rise is a stair to a long-legged body and a wall to a standard one, and the
	# generator has to certify against whoever steps shortest (`Unit.lowest_step_height`).
	#
	# **Deliberately rng-neutral.** `DeepStrike.assemble_from_preset` draws no randomness at
	# all, so moving assembly ahead of `MapGen.generate` leaves the `rng.randi()` sequence —
	# map seed, then combat seed — exactly as it was. Every existing bout seed still builds
	# the map it built before. Seating is the half that genuinely needs the board, so it
	# stays below and is applied to units that already exist.
	var units: Array[Unit] = []
	units.append_array(_spawn_squad(roster_a, 0))
	units.append_array(_spawn_squad(roster_b, 1))
	if units.is_empty():
		return {"error": "neither roster could actually assemble (bad template_id?)"}
	var step_height: float = Unit.lowest_step_height(units)

	var grid: Grid = MapGen.generate(rng.randi(), GRID_WIDTH, GRID_HEIGHT, step_height)
	var spawn_a_cells: Array[Vector2i] = _cells_of_marker(grid, Enums.SpawnMarker.SPAWN_A)
	var spawn_b_cells: Array[Vector2i] = _cells_of_marker(grid, Enums.SpawnMarker.SPAWN_B)

	# `BR51.19`: one `taken` set across BOTH squads, so squad B cannot spill onto a cell
	# squad A already holds. The two zones are the farthest-apart rooms and will not
	# normally meet, but "normally" is what let the wrap survive five blocks.
	var taken: Dictionary = {}
	var cells_a: Array[Vector2i] = _placement_cells(
		grid, spawn_a_cells, roster_a.size(), taken, step_height
	)
	var cells_b: Array[Vector2i] = _placement_cells(
		grid, spawn_b_cells, roster_b.size(), taken, step_height
	)
	# A grid carrying no spawn markers at all has no zone to spill from, and
	# `_spawn_squad`'s own `Vector2i(i, squad_id)` fallback still hands out distinct
	# cells — so an empty zone is the pre-existing marker-less case, not a map too small
	# to seat the roster. Only a zone that EXISTS and runs out is a refusal.
	var short_a: bool = not spawn_a_cells.is_empty() and cells_a.size() < roster_a.size()
	var short_b: bool = not spawn_b_cells.is_empty() and cells_b.size() < roster_b.size()
	if short_a or short_b:
		return {
			"error":
			(
				(
					"map seed %d cannot seat this roster: squad A needs %d cells and its spawn "
					+ "zone reaches %d, squad B needs %d and reaches %d"
				)
				% [map_seed, roster_a.size(), cells_a.size(), roster_b.size(), cells_b.size()]
			)
		}

	_seat_squad(units, 0, cells_a)
	_seat_squad(units, 1, cells_b)

	var state := CombatState.new(grid, units, rng.randi())
	# taskblock-52 `BR52.11`: the origin seed travels with the bout, so
	# `BattleScene.load_battle` can log it without its caller remembering to. This
	# one line covers every path that builds a bout through here — the Generate Bout
	# overlay, `CompletionSampler.build_for_seed`, `ReplayHandle.from_seed` and the
	# watched-run panel. Note it is `map_seed`, NOT `state.rng.seed`: the latter is
	# the derived `rng.randi()` above and would not regenerate this map.
	state.bout_seed = map_seed
	state.set_squad_controller(0, Enums.SquadController.AI)
	state.set_squad_controller(1, Enums.SquadController.AI)

	var mission := MissionState.new(RunState.new(), state)
	mission.victory_mode = victory_mode
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


## `BR51.19`: the distinct cells a roster of `count` units will stand on — the spawn
## zone's own cells first, then spilling outward onto ground connected to it. Cells
## chosen here are added to `taken`, which is shared across both squads.
##
## **The zone is 2x2 — exactly four cells (`MapGen.SPAWN_ZONE_SIZE` squared), and fewer
## once `_mark_zone`'s height filter drops one.** A fifth unit has nowhere authored to
## stand, and the placement this replaced answered that with `spawn_cells[i %
## spawn_cells.size()]`: the fifth unit wrapped onto the first's cell. Nothing refused
## it, because `Grid.set_occupant_id` holds one occupant per cell and `CombatState`'s
## registration loop simply overwrote the earlier arrival — so the units drew stacked and
## then moved apart to sensible cells, which is exactly how it was reported.
##
## **The spill's edge rule is two-way traversability, not reachability**, and that is the
## load-bearing choice rather than a detail. A `HOP_DOWN` edge is a legal step *out* of
## the zone that a non-climbing shell cannot take back, so a one-way spill would drop a
## unit off a ledge and spawn it stranded — `BR40.04` again by a different route.
## Requiring `move_cost` to exist in BOTH directions keeps every spawned unit on ground
## mutually connected to its own zone.
##
## The mover is the conservative one: no climbing, and — tb62 Pass A — the roster's own
## **lowest** `step_height` rather than the unmodified body's. That is what makes the
## sentence below literally true instead of nearly true: a cell this pathfinder can reach
## is one every shell in the roster can reach, whatever it is made of. Passing the base
## would have been right only while no part authored the stat.
## Deterministic by construction — a FIFO flood seeded with the zone's own cells in
## the order `_cells_of_marker` found them, expanded through `Grid.NEIGHBOR_OFFSETS` in
## its fixed order. No RNG; the same board always seats the same roster the same way.
##
## Returns fewer than `count` cells when the connected ground genuinely runs out.
## `build_bout` refuses the bout by name rather than stacking, per this file's own
## "never crash, never silently invent" posture.
static func _placement_cells(
	grid: Grid,
	zone_cells: Array[Vector2i],
	count: int,
	taken: Dictionary,
	step_height: float = Unit.BASE_STEP_HEIGHT
) -> Array[Vector2i]:
	var pathfinder := Pathfinder.new(grid, false, step_height)
	var placed: Array[Vector2i] = []
	var queue: Array[Vector2i] = zone_cells.duplicate()
	var visited: Dictionary = {}
	for cell: Vector2i in zone_cells:
		visited[cell] = true

	var head: int = 0
	while head < queue.size() and placed.size() < count:
		var cell: Vector2i = queue[head]
		head += 1
		# Unwalkable ground is neither somewhere a unit may stand nor somewhere the
		# spill may route through — and skipping expansion is what makes the reverse
		# `move_cost` check below a pure height question rather than a repeat of this one.
		if not pathfinder.is_walkable(cell):
			continue
		if not taken.has(cell):
			taken[cell] = true
			placed.append(cell)
		for offset: Vector2i in Grid.NEIGHBOR_OFFSETS:
			var next: Vector2i = cell + offset
			if visited.has(next) or not grid.in_bounds(next):
				continue
			visited[next] = true
			if pathfinder.move_cost(cell, next) < 0.0 or pathfinder.move_cost(next, cell) < 0.0:
				continue
			queue.append(next)
	return placed


## tb62 Pass A: **assembly, with no board involved.** Split from seating because the
## roster's own `step_height` is an input to generating the map it will stand on, and a
## body cannot be asked what it steps until it has been built. Units come back at the
## marker-less `Vector2i(i, squad_id)` positions; `_seat_squad` moves them once the board
## exists.
static func _spawn_squad(roster: Array[BoutRosterEntry], squad_id: int) -> Array[Unit]:
	var units: Array[Unit] = []
	for i in range(roster.size()):
		var entry: BoutRosterEntry = roster[i]
		var matrix := Matrix.new()
		matrix.id = StringName("%s_%d" % [entry.profile.preset_name, i])
		matrix.ai_profile = entry.ai_profile
		var unit: Unit = DeepStrike.assemble_from_preset(
			entry.profile, matrix, Vector2i(i, squad_id), squad_id
		)
		if unit != null:
			# taskblock-28 Pass B: "a bout starts by units equipping
			# themselves from their kit" — a no-op for the overwhelming
			# majority of presets (kit == null, already armed via
			# `loadout` the old way); only a kitted preset resolves this.
			if entry.profile.kit != null:
				KitEquipper.stock(unit, entry.profile.kit, DeepStrike.reference_humanoid_pool())
				KitEquipper.equip(unit, entry.profile.kit)
			units.append(unit)
	return units


## `BR51.19`, unchanged in rule and moved in time: one distinct cell per unit, chosen by
## `_placement_cells` and already checked walkable. The old `spawn_cells[i %
## spawn_cells.size()]` wrap is what stacked every unit past the fourth. The
## `Vector2i(i, squad_id)` fallback survives only for a grid carrying no spawn markers at
## all, where there is no zone to spill from — still distinct per unit, which is what it
## was always for, and it is also the position `_spawn_squad` already assembled at.
##
## **One deliberate difference from the pre-tb62 shape**, stated rather than left to be
## found: cells are handed out by *seated* index, not by *roster* index, so a roster entry
## that failed to assemble no longer burns the spawn cell it would have stood on. Only
## reachable when `assemble_from_preset` returns null, which `build_bout` already treats as
## a broken roster.
static func _seat_squad(
	units: Array[Unit], squad_id: int, placement_cells: Array[Vector2i]
) -> void:
	var seated: int = 0
	for unit: Unit in units:
		if unit.squad_id != squad_id:
			continue
		if seated < placement_cells.size():
			unit.cell = placement_cells[seated]
		seated += 1


static func _cells_of_marker(grid: Grid, marker: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_spawn_marker(cell) == marker:
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
