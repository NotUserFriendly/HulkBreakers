extends GutTest

## taskblock-53 Pass B: the cell format's own acceptance — round-trip equivalence, a bout on
## a loaded map resolving identically to the same bout on the generated original, and a
## malformed file producing a readable error rather than a crash.


## taskblock-47 Pass C: this file builds a bout, so the fast gate skips it.
##
## **Untyped on purpose, against this project's static-typing rule** — GUT declares
## `should_skip_script()` with no return type and Godot treats an added `-> Variant` as a
## signature mismatch, which reports as "does not extend GutTest" and hides the real cause.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func _generated_grid(map_seed: int = 4242) -> Grid:
	return MapGen.generate(map_seed, 40, 30)


## **The equivalence the round trip is judged against, spelled out here rather than
## borrowed.** `Grid.dup()` is the codebase's own idea of "the same board", but it deep-copies
## `Part` objects, so comparing by identity would fail against any freshly-loaded map by
## construction. Equivalence for a *map* is: same dimensions, same surfaces in the same order
## with the same heights and facings, same blockers, same field items, same spawns, same
## opacity — parts compared by **id**, which is exactly what the format stores.
func _differences(a: Grid, b: Grid) -> Array[String]:
	var diffs: Array[String] = []
	if a.width != b.width or a.rows != b.rows:
		diffs.append("dimensions %dx%d against %dx%d" % [a.width, a.rows, b.width, b.rows])
		return diffs
	for y: int in range(a.rows):
		for x: int in range(a.width):
			var cell := Vector2i(x, y)
			var sa: Array[Surface] = a.surfaces_at(cell)
			var sb: Array[Surface] = b.surfaces_at(cell)
			if sa.size() != sb.size():
				diffs.append("%s: %d surfaces against %d" % [cell, sa.size(), sb.size()])
				continue
			for i: int in range(sa.size()):
				if sa[i].part.id != sb[i].part.id:
					diffs.append(
						"%s surface %d: %s against %s" % [cell, i, sa[i].part.id, sb[i].part.id]
					)
				if not is_equal_approx(sa[i].height, sb[i].height):
					diffs.append(
						(
							"%s surface %d height: %f against %f"
							% [cell, i, sa[i].height, sb[i].height]
						)
					)
				if not is_equal_approx(sa[i].facing, sb[i].facing):
					diffs.append(
						(
							"%s surface %d facing: %f against %f"
							% [cell, i, sa[i].facing, sb[i].facing]
						)
					)
			var ba: Variant = a.blockers.get(cell)
			var bb: Variant = b.blockers.get(cell)
			var ba_id: StringName = (ba as Part).id if ba != null else &""
			var bb_id: StringName = (bb as Part).id if bb != null else &""
			if ba_id != bb_id:
				diffs.append("%s blocker: %s against %s" % [cell, ba_id, bb_id])
			var ia: Array = a.field_items.get(cell, [])
			var ib: Array = b.field_items.get(cell, [])
			if ia.size() != ib.size():
				diffs.append("%s: %d field items against %d" % [cell, ia.size(), ib.size()])
			if a.get_spawn_marker(cell) != b.get_spawn_marker(cell):
				diffs.append(
					(
						"%s spawn: %d against %d"
						% [cell, a.get_spawn_marker(cell), b.get_spawn_marker(cell)]
					)
				)
	return diffs


func test_a_generated_map_round_trips_through_the_format() -> void:
	var original: Grid = _generated_grid()
	var map: MapFile = MapSerializer.to_map_file(original, "round trip")
	var loaded: Dictionary = MapSerializer.to_grid(map)

	assert_eq(loaded.get("error", ""), "", "a generated map must load without complaint")
	assert_true(loaded.has("grid"), "and produce a grid")
	if not loaded.has("grid"):
		return
	var diffs: Array[String] = _differences(original, loaded["grid"])
	gut.p("%d placements, %d spawns" % [map.placements.size(), map.spawn_cells.size()])
	assert_eq(diffs, [] as Array[String], "the loaded grid must be equivalent to the original")


## **Order within a cell is meaningful and must survive.** `Surface.first_walkable` takes the
## first match, so a catwalk stacked over a floor resolves differently if the two swap. Built
## by hand rather than hunting a generated map that happens to stack, because nothing in
## `MapGen` authors a second surface yet — this pins the format's promise ahead of the content
## that will rely on it.
func test_stacked_surfaces_keep_their_authored_order() -> void:
	var grid := Grid.new(3, 3)
	var cell := Vector2i(1, 1)
	grid.add_surface(cell, Surface.new(DataLibrary.get_part(&"ship_floor"), 0.0, 0.0))
	grid.add_surface(cell, Surface.new(DataLibrary.get_part(&"ramp"), 2.5, PI / 2.0))

	var loaded: Dictionary = MapSerializer.to_grid(MapSerializer.to_map_file(grid, "stack"))
	assert_eq(loaded.get("error", ""), "")
	var reloaded: Array[Surface] = (loaded["grid"] as Grid).surfaces_at(cell)
	assert_eq(reloaded.size(), 2, "both surfaces survive")
	assert_eq(reloaded[0].part.id, &"ship_floor", "and in the order they were authored")
	assert_eq(reloaded[1].part.id, &"ramp")
	assert_almost_eq(reloaded[1].height, 2.5, 0.001, "the raised surface keeps its height")
	assert_almost_eq(reloaded[1].facing, PI / 2.0, 0.001, "and its facing")


## **A map is the pristine board, not a savegame.** A blocker that took damage saves as its
## authored id and reloads intact — otherwise every map ever saved would freeze whatever hp a
## part happened to have, and a later `.tres` balance edit would silently stop applying.
func test_a_damaged_blocker_reloads_intact_because_parts_are_stored_by_id() -> void:
	var grid := Grid.new(3, 3)
	var wall: Part = DataLibrary.get_part(&"wall")
	var authored_hp: int = wall.max_hp
	wall.hp = 1
	grid.blockers[Vector2i(2, 2)] = wall

	var loaded: Dictionary = MapSerializer.to_grid(MapSerializer.to_map_file(grid, "damaged"))
	assert_eq(loaded.get("error", ""), "")
	var reloaded: Part = (loaded["grid"] as Grid).blockers[Vector2i(2, 2)]
	assert_eq(reloaded.id, &"wall")
	assert_eq(reloaded.hp, authored_hp, "the map stores the part, not the damage it had taken")


## **Runtime state is not a map's to carry.** `occupant_id` says who is standing where, which
## belongs to a bout. A loaded map must come back unoccupied regardless of what the board it
## was captured from was doing at the time.
func test_occupancy_is_not_saved() -> void:
	var grid: Grid = _generated_grid()
	grid.set_occupant_id(Vector2i(5, 5), 7)

	var loaded: Dictionary = MapSerializer.to_grid(MapSerializer.to_map_file(grid))
	assert_eq(loaded.get("error", ""), "")
	assert_eq(
		(loaded["grid"] as Grid).get_occupant_id(Vector2i(5, 5)),
		-1,
		"a loaded map is unoccupied — occupancy is a bout's, not a map's"
	)


# --- malformed files: a readable error, never a crash -----------------------------------


func _one_placement_map(placement: MapPlacement) -> MapFile:
	var map := MapFile.new()
	map.map_name = "malformed"
	map.width = 4
	map.rows = 4
	map.placements = [placement]
	return map


func test_a_placement_naming_an_unknown_part_is_rejected_with_the_name_in_it() -> void:
	var result: Dictionary = MapSerializer.to_grid(
		_one_placement_map(
			MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_SURFACE, &"no_such_part")
		)
	)
	assert_false(result.has("grid"), "a map naming a part that does not exist is not loadable")
	assert_true(
		String(result["error"]).contains("no_such_part"),
		"and the error names it: %s" % result["error"]
	)


func test_a_placement_outside_the_grid_is_rejected_with_the_cell_in_it() -> void:
	var result: Dictionary = MapSerializer.to_grid(
		_one_placement_map(
			MapPlacement.new(Vector2i(99, 99), MapPlacement.KIND_SURFACE, &"ship_floor")
		)
	)
	assert_false(result.has("grid"))
	assert_true(String(result["error"]).contains("99"), "the error names the cell")


func test_an_unknown_placement_kind_is_rejected() -> void:
	var result: Dictionary = MapSerializer.to_grid(
		_one_placement_map(MapPlacement.new(Vector2i(1, 1), &"catwalk_maybe", &"ship_floor"))
	)
	assert_false(result.has("grid"))
	assert_true(String(result["error"]).contains("catwalk_maybe"))


func test_two_blockers_on_one_cell_is_rejected_rather_than_silently_keeping_the_last() -> void:
	var map: MapFile = _one_placement_map(
		MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_BLOCKER, &"wall")
	)
	map.placements.append(MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_BLOCKER, &"wall"))
	var result: Dictionary = MapSerializer.to_grid(map)
	assert_false(result.has("grid"))
	assert_true(String(result["error"]).contains("second blocker"))


func test_non_positive_dimensions_are_rejected() -> void:
	var map := MapFile.new()
	map.width = 0
	map.rows = 10
	assert_false(MapSerializer.to_grid(map).has("grid"))


func test_a_null_map_is_an_error_not_a_crash() -> void:
	var result: Dictionary = MapSerializer.to_grid(null)
	assert_false(result.has("grid"))
	assert_eq(result["error"], "no map resource")


func test_mismatched_sparse_arrays_are_rejected() -> void:
	var map := MapFile.new()
	map.width = 4
	map.rows = 4
	map.spawn_cells = [Vector2i(1, 1)]
	map.spawn_markers = []
	assert_false(MapSerializer.to_grid(map).has("grid"), "a half-written spawn pair is malformed")


# --- authoring warnings are warnings ------------------------------------------------------


## taskblock-53: "an authored map that fails the invariant still loads (warning, not
## rejection)." A map with no walkable surface is nonsense to play and must still load, so the
## editor can show you what is wrong with it rather than refusing to open it.
func test_a_map_with_no_walkable_surface_still_loads_and_is_reported() -> void:
	var map: MapFile = _one_placement_map(
		MapPlacement.new(Vector2i(1, 1), MapPlacement.KIND_BLOCKER, &"wall")
	)
	var result: Dictionary = MapSerializer.to_grid(map)
	assert_true(result.has("grid"), "a broken-on-purpose map still loads")

	var problems: Array[String] = MapSerializer.describe_problems(map)
	assert_gt(problems.size(), 0, "and its problems are described")
	gut.p("problems: %s" % str(problems))


func test_a_generated_map_reports_no_authoring_problems() -> void:
	var map: MapFile = MapSerializer.to_map_file(_generated_grid(), "generated")
	assert_eq(
		MapSerializer.describe_problems(map),
		[] as Array[String],
		"a generated map is well-formed by the authoring checks"
	)


# --- a bout on a loaded map plays identically ---------------------------------------------


func _roster(preset_id: StringName) -> Array[BoutRosterEntry]:
	var preset: BotPreset = DataLibrary.get_preset(preset_id)
	return [BoutRosterEntry.new(preset, &"aggressive")] as Array[BoutRosterEntry]


## Every event a bout emitted, as `kind|text` lines — the same shape a log diff would take.
func _bout_transcript(state: CombatState, mission: MissionState, cap: int) -> Array[String]:
	var sink := MemorySink.new()
	state.combat_log.add_sink(sink)
	var runner := BoutRunner.new(state, mission, cap)
	runner.run_to_completion()
	var lines: Array[String] = []
	for event: LogEvent in sink.events:
		lines.append("%s|%s" % [event.kind, event.text])
	return lines


## **The acceptance: "a seeded bout on the loaded map resolves identically to the same bout
## on the generated one."**
##
## Both bouts are built from the same seed, so the units, rosters and rng are identical by
## construction; the *only* difference is that the second one's board has been through the
## format. Occupancy is re-applied after the swap because `CombatState._init` wrote it into
## the grid it was handed, and a loaded map is deliberately unoccupied.
##
## Compared as a full event transcript rather than as an outcome: two bouts can reach the
## same result down different paths, and it is the path that would expose a surface whose
## height or facing shifted by a rounding step.
func test_a_bout_on_a_round_tripped_map_is_identical_to_one_on_the_generated_map() -> void:
	const SEED := 90210
	const CAP := 8
	var a: Dictionary = BoutSetup.build_bout(
		_roster(&"a_brand_laborer"), _roster(&"a_brand_laborer_battery_mods"), SEED
	)
	var b: Dictionary = BoutSetup.build_bout(
		_roster(&"a_brand_laborer"), _roster(&"a_brand_laborer_battery_mods"), SEED
	)
	assert_true(a.has("state") and b.has("state"), "sanity: both bouts built")
	if not (a.has("state") and b.has("state")):
		return

	var loaded: Dictionary = MapSerializer.to_grid(
		MapSerializer.to_map_file((b["state"] as CombatState).grid, "bout parity")
	)
	assert_eq(loaded.get("error", ""), "", "the generated board round-trips")
	var swapped: Grid = loaded["grid"]
	for unit: Unit in (b["state"] as CombatState).units:
		swapped.set_occupant_id(unit.cell, unit.id)
	(b["state"] as CombatState).grid = swapped

	var transcript_a: Array[String] = _bout_transcript(a["state"], a["mission"], CAP)
	var transcript_b: Array[String] = _bout_transcript(b["state"], b["mission"], CAP)

	gut.p(
		(
			"%d events on the generated board, %d on the loaded one"
			% [transcript_a.size(), transcript_b.size()]
		)
	)
	assert_gt(transcript_a.size(), 0, "sanity: the bout actually did something")
	assert_eq(
		transcript_b.size(), transcript_a.size(), "the same bout emits the same number of events"
	)
	var first_divergence := -1
	for i: int in range(mini(transcript_a.size(), transcript_b.size())):
		if transcript_a[i] != transcript_b[i]:
			first_divergence = i
			break
	if first_divergence >= 0:
		gut.p("first divergence at event %d:" % first_divergence)
		gut.p("  generated: %s" % transcript_a[first_divergence])
		gut.p("  loaded:    %s" % transcript_b[first_divergence])
	assert_eq(
		first_divergence, -1, "a bout on a loaded map must resolve identically, event for event"
	)
