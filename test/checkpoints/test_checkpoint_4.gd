extends GutTest

## Checkpoint 4 artifact (docs/09): 20 randomly deep-struck cyborgs, ASCII
## shot planes + stat blocks, so a human can eyeball "is any of these
## malformed, unarmed-when-it-shouldn't-be, or otherwise absurd." Run via
## ./checkpoint.sh 4 — its stdout is what lands in
## out/checkpoints/04/output.txt.

const CYBORG_COUNT := 20


func _part_summary(unit: Unit) -> String:
	var names: Array[String] = []
	for part: Part in unit.frame.all_parts():
		names.append(String(part.id))
	return ", ".join(names)


func test_twenty_random_deep_strike_cyborgs() -> void:
	var pool: Array[Part] = DeepStrike.default_part_pool()
	var base := Matrix.new()
	base.id = &"jerry"
	base.level = 8
	base.perks = [&"steady_hands", &"quick_draw", &"iron_will"]

	for seed_value in range(1, CYBORG_COUNT + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var tier_ratio: float = rng.randf_range(0.3, 1.0)
		var unit := DeepStrike.assemble_random(base, tier_ratio, pool, rng, Vector2i(0, 0))

		var violations: Array[String] = DeepStrike.validate_assembly(unit)
		var armed: bool = DeepStrike.is_armed(unit)
		var regions: Array[Region] = BodyProjector.project(unit, Vector2(0, -1))
		regions.sort_custom(func(a: Region, b: Region) -> bool: return a.depth < b.depth)

		print("\n=== cyborg %d/%d (seed %d) ===" % [seed_value, CYBORG_COUNT, seed_value])
		print("parts: %s" % _part_summary(unit))
		print(
			(
				"mass %.1f/%.1f   ram %.1f/%.1f   effective_level %.2f   armed: %s"
				% [
					unit.frame.carried_mass(),
					unit.frame.max_mass,
					unit.frame.total_ram(),
					unit.frame.max_ram,
					unit.matrix.effective_level(),
					armed
				]
			)
		)
		if violations.is_empty():
			print("violations: none")
		else:
			print("violations: %s" % [violations])
		print(AsciiRender.plane_to_text(AsciiRender.recenter(regions, 2.0), 4, 2))

		assert_eq(violations, [] as Array[String], "seed %d must be a valid assembly" % seed_value)
		assert_true(regions.size() > 0, "seed %d must project a sane shot plane" % seed_value)

		var projected_parts: Array[Part] = []
		for region: Region in regions:
			if not projected_parts.has(region.part):
				projected_parts.append(region.part)
		for part: Part in unit.frame.living_parts():
			assert_true(
				projected_parts.has(part),
				"seed %d: living part %s must appear in the shot plane" % [seed_value, part.id]
			)
