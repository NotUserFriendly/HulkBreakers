extends GutTest

## docs/07: "the map is generated once from a seed and stays that way...
## enemy presence and behavior are dynamic — it repopulates."


func test_revisiting_a_hulk_yields_an_identical_map() -> void:
	var hulk := Hulk.new()
	hulk.id = &"derelict_alpha"
	hulk.map_seed = 12345

	var first_visit: Grid = hulk.generate_map(20, 12)
	hulk.record_visit()
	var second_visit: Grid = hulk.generate_map(20, 12)

	assert_eq(AsciiRender.grid_to_text(first_visit), AsciiRender.grid_to_text(second_visit))


func test_population_seed_changes_every_visit_while_map_seed_does_not() -> void:
	var hulk := Hulk.new()
	hulk.map_seed = 99

	var seed_a: int = hulk.population_seed()
	hulk.record_visit()
	var seed_b: int = hulk.population_seed()
	hulk.record_visit()
	var seed_c: int = hulk.population_seed()

	assert_ne(seed_a, seed_b)
	assert_ne(seed_b, seed_c)
	assert_eq(hulk.map_seed, 99, "the map seed itself must never change")


func test_different_visit_counts_actually_repopulate_a_deep_strike_roster() -> void:
	# The concrete payoff: the same hulk, revisited, hands a different
	# population seed to DeepStrike and gets a different squad — while the
	# map underneath stays byte-identical.
	var hulk := Hulk.new()
	hulk.map_seed = 7
	var pool: Array[Part] = DeepStrike.default_part_pool()

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = hulk.population_seed()
	var unit_a := DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng_a, Vector2i(0, 0))

	hulk.record_visit()
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = hulk.population_seed()
	var unit_b := DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng_b, Vector2i(0, 0))

	var ids_a: Array[StringName] = []
	for part: Part in unit_a.frame.all_parts():
		ids_a.append(part.id)
	var ids_b: Array[StringName] = []
	for part: Part in unit_b.frame.all_parts():
		ids_b.append(part.id)
	assert_ne(ids_a, ids_b)
