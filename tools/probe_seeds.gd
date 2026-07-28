extends SceneTree

## Temporary measuring probe — same fixture as test_full_mission.gd (same presets,
## same 1v1 AGGRESSIVE shape, same turn cap, same EXTRACTED-means-completed
## definition). Copied verbatim into both trees so the two halves of a comparison
## cannot come from different code paths.

const TURN_CAP := 100


func _roster(profile: BotPreset) -> Array[BoutRosterEntry]:
	return [BoutRosterEntry.new(profile, &"AGGRESSIVE")] as Array[BoutRosterEntry]


func _initialize() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()
	var a: BotPreset = DataLibrary.get_preset(&"a_brand_laborer")
	var b: BotPreset = DataLibrary.get_preset(&"a_brand_laborer_battery_mods")
	var first: int = int(OS.get_cmdline_user_args()[0])
	var count: int = int(OS.get_cmdline_user_args()[1])
	var tally: Dictionary = {}
	var extracted := 0
	var turns_when_extracted := 0
	for map_seed in range(first, first + count):
		var built: Dictionary = BoutSetup.build_bout(_roster(a), _roster(b), map_seed)
		if built.get("error", "") != "":
			print("RESULT seed %d: BUILD FAILED" % map_seed)
			continue
		var runner := BoutRunner.new(built["state"], built["mission"], TURN_CAP)
		await runner.run_to_completion()
		var outcome: int = built["mission"].outcome
		var outcome_name: String = Enums.MissionOutcome.keys()[outcome]
		tally[outcome_name] = int(tally.get(outcome_name, 0)) + 1
		if outcome == Enums.MissionOutcome.EXTRACTED:
			extracted += 1
			turns_when_extracted += runner.turns_taken
		print("RESULT seed %d: %s in %d turns" % [map_seed, outcome_name, runner.turns_taken])
	var mean: float = float(turns_when_extracted) / float(extracted) if extracted > 0 else 0.0
	print(
		(
			"RATE %d/%d (%.1f%%) mean_turns=%.1f %s"
			% [extracted, count, 100.0 * extracted / count, mean, tally]
		)
	)
	quit()
