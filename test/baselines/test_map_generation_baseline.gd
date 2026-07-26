extends GutTest

## An ordinary regression baseline: ASCII maps across several seeds, plus a
## combat-log line, so "does this read as a place?" and "are seeds actually
## different?" are answerable from the test log alone (docs/00's own "a spatial
## system without a dump is one nobody can verify").
##
## taskblock-41 Pass E: was `test_checkpoint_1.gd`, run through a retired
## `./checkpoint.sh 1` ritual. Nothing about what it checks changed — only the
## name, which used to imply a gate that no longer exists. It runs every
## `./run_tests.sh` like any other test, and always did.

const SEEDS: Array[int] = [1, 2, 3, 4, 5]
const WIDTH := 28
const HEIGHT := 16


func test_dump_ascii_maps_across_several_seeds() -> void:
	var dumps: Array[String] = []

	for map_seed: int in SEEDS:
		var grid: Grid = MapGen.generate(map_seed, WIDTH, HEIGHT)
		var text: String = AsciiRender.grid_to_text(grid)
		dumps.append(text)

		print("\n=== seed %d ===" % map_seed)
		print(text)

		var spawn_a_found := false
		var spawn_b_found := false
		for y in range(grid.rows):
			for x in range(grid.width):
				var marker: int = grid.get_spawn_marker(Vector2i(x, y))
				if marker == Enums.SpawnMarker.SPAWN_A:
					spawn_a_found = true
				elif marker == Enums.SpawnMarker.SPAWN_B:
					spawn_b_found = true
		assert_true(spawn_a_found, "seed %d: spawn zone A must exist" % map_seed)
		assert_true(spawn_b_found, "seed %d: spawn zone B must exist" % map_seed)

	for i in range(1, dumps.size()):
		assert_ne(
			dumps[0], dumps[i], "different seeds should (almost always) produce different maps"
		)

	# Prove the combat log is wired and readable in the same artifact.
	var combat_log := CombatLog.new()
	combat_log.add_sink(StdoutSink.new())
	print("\n=== combat log sample ===")
	combat_log.emit(
		LogEvent.new(
			0, Enums.Phase.RESOLUTION, 0, &"checkpoint", {}, "Checkpoint 1 artifact generated"
		)
	)
