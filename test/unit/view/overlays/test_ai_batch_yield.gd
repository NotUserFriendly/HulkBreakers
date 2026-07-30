extends GutTest

## taskblock-42 Pass D (BR27.09 cost #4): `advance_ai_turns` was a bare `while`
## loop with no `await`, so the main thread was blocked for the whole AI batch —
## nothing rendered, no input was processed, and every opposing unit appeared to
## move at once at the end.
##
## **Determinism is this pass's real acceptance, not the speed.** A faster
## non-deterministic sim would be a strictly worse outcome than the hitch.
##
## ## taskblock-48 Pass D: why this file is the worst seconds-per-bout in the suite
##
## It measured **18.4 s per bout** against the completion sampler's 10.7, and
## taskblock-48 guessed the pacer's frame yields were paying for it. **Measured, they are
## not.** The same seed, played tight and paced:
##
## | | wall | turns | frame yields |
## |---|---|---|---|
## | no pacer | 18 485 ms | 54 | — |
## | with pacer | 19 660 ms | 54 | 344 |
##
## **The pacer is 6% — 1175 ms, about 3.4 ms a yield.** The cost is bout *length*: 54
## turns against the sampler's mean of ~13 under the same AI, at roughly 340 ms a turn
## either way. Nothing here is incidental, so nothing was cut: the determinism test needs
## a whole bout twice, and comparing a shorter one would mean seed-shopping for a cheap
## map and calling it a saving.
##
## Worth knowing if this ever looks like the place to optimise: **the yield is nearly
## free, and the turns are the bill.**


## taskblock-47 Pass C: this file builds bouts, so the fast gate skips it. The list it
## is on is checked against the profile's own bout counter every run — see `SuiteTier`.
##
## **Untyped on purpose, against this project's static-typing rule.** GUT declares
## `func should_skip_script():` with no return type, and Godot treats an override that
## adds `-> Variant` as a signature mismatch — the script then fails to parse and GUT
## reports it as "does not extend GutTest", which is a long way from the real cause.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func _bout(map_seed: int) -> Dictionary:
	var roster: Array[BoutRosterEntry] = []
	for i in range(2):
		var entry := BoutRosterEntry.new()
		entry.profile = DataLibrary.presets_pool()[i % DataLibrary.presets_pool().size()]
		roster.append(entry)
	return BoutSetup.build_bout(roster, roster, map_seed)


## A stable description of where the sim ended up — what must not change.
func _fingerprint(state: CombatState) -> String:
	var rows := PackedStringArray()
	for unit: Unit in state.units:
		var hp := 0
		for part: Part in unit.shell.all_parts():
			hp += part.hp
		rows.append("%d:%s:%s:%d:%.2f" % [unit.id, unit.cell, unit.alive, hp, unit.mp])
	rows.append("round=%d" % state.round_number)
	return "|".join(rows)


## The load-bearing test. The same seed, driven through the yielding overlay
## path and through a tight `BoutRunner` loop with no yielding at all, must land
## in the identical state.
func test_a_yielding_batch_produces_the_identical_bout() -> void:
	var tight: Dictionary = _bout(4242)
	assert_eq(tight.get("error", ""), "", "sanity: the bout built")
	var tight_runner := BoutRunner.new(tight.state, tight.mission)
	var guard := 0
	while not tight_runner.finished and guard < 200:
		await tight_runner.step()
		guard += 1
	var expected: String = _fingerprint(tight.state)

	var yielded: Dictionary = _bout(4242)
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(yielded.state, yielded.mission)
	var overlay: ControlOverlay = battle.overlay
	await overlay.advance_ai_turns(battle)

	assert_eq(_fingerprint(yielded.state), expected, "yielding must not change the sim at all")


## The yield itself: frames actually pass while the batch runs, which is what
## keeps input alive and the board drawing.
##
## taskblock-47 Pass E1: **squad 0 is HUMAN here, and that is the scenario the
## function is for.** `advance_ai_turns` exits on `wants_turn_for`, so an all-AI bout
## never hits that condition and plays the entire mission — this test was spending a
## whole bout to prove that at least one frame passed. Handing over to a human is what
## the game actually does, it exercises the same yield, and it costs a handful of
## turns instead of hundreds.
func test_frames_pass_during_the_batch() -> void:
	var built: Dictionary = _bout(77)
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(built.state, built.mission)
	built.state.set_squad_controller(0, Enums.SquadController.HUMAN)

	var frames_before: int = Engine.get_process_frames()
	await (battle.overlay as ControlOverlay).advance_ai_turns(battle)

	assert_gt(
		Engine.get_process_frames(),
		frames_before,
		"the batch no longer blocks the main thread end to end"
	)

## taskblock-47 Pass E3: **`test_the_batch_still_runs_to_completion` was cut here**,
## and the covering test is `test_a_yielding_batch_produces_the_identical_bout` above.
##
## It played a whole 400-turn bout — 178 s, the second most expensive test in the
## suite — to assert `round_number > 0`. Demonstrated rather than assumed, per
## `PLAN.md`'s rule that deleting a redundant test and deleting the only test of a
## real rule look identical in the diff: `advance_ai_turns` was sabotaged to break
## out of its loop after two steps, and the fingerprint test went red on its own
## ("yielding must not change the sim at all"). A loop that strands cannot produce
## the same end state as the tight loop it is compared against, so completion is
## already guarded — by a test that also says *how* it differed.
