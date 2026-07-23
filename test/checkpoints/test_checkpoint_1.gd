extends GutTest

## Checkpoint 1 artifact (docs/09): ASCII maps across several seeds, plus a
## combat-log line, so a human can eyeball "does this look like a place?"
## and "are seeds actually different?" Run via ./checkpoint.sh 1 — its
## stdout is what lands in out/checkpoints/01/output.txt.

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
				var terrain: int = grid.get_terrain(Vector2i(x, y))
				if terrain == Enums.TerrainType.SPAWN_A:
					spawn_a_found = true
				elif terrain == Enums.TerrainType.SPAWN_B:
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
