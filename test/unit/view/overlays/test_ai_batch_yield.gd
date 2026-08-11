extends GutTest

## taskblock-58 Pass C.2: the wall-clock budget `test_a_yielding_batch_produces_the_identical_bout`
## raises so it cannot trip. Ten minutes — far past any turn, so reaching it is a real defect
## rather than a slow machine. That test's own header has why.
const UNREACHABLE_BUDGET_MSEC := 1000 * 60 * 10

## tb65 Pass D: **how many turns each driver resolves before both stop.** Near the suite's own
## per-bout average of 14 — the number this file was 164 against.
##
## **Deliberately a cap both paths hit, not a length one path happens to reach.** `BoutRunner`
## marks itself finished at `turns_taken >= turn_cap` and terminates the mission, so the tight
## loop and the yielding batch stop at the *same turn* on the same board — which is what makes
## the fingerprints comparable at all. A cap only one side honoured would be a bug wearing a
## constant.
const TURN_CAP := 16

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
## either way.
##
## Worth knowing if this ever looks like the place to optimise: **the yield is nearly
## free, and the turns are the bill.**
##
## ## tb65 Pass D: the turns are the bill, so the turns are what was cut
##
## By the tb64 profile rebuild this file was **279.9 s — 19.6% of the entire full gate** — and
## **493 turns across 3 bouts, 46.4% of every turn the suite resolves.** 164 turns a bout
## against a suite average of 14. Nothing in tb64 touched the file; it had simply been growing
## with the AI's own bout lengths since tb48 measured it at 54.
##
## **tb48's objection is answered rather than overruled.** It declined to cut, on the grounds
## that *"comparing a shorter one would mean seed-shopping for a cheap map and calling it a
## saving"* — and it was right about that. **This is not that.** The seed is unchanged at 4242,
## the board is unchanged, and the AI is unchanged; what changed is that **both** drivers stop
## at the same declared `TURN_CAP` instead of both playing to a mission ending. The equality is
## over whatever turns run, so it holds at any length, and a divergence now lands at the turn it
## happens on rather than being one difference buried in a several-hundred-turn fingerprint.
##
## **Both paths must be capped or the test is meaningless**, which is the whole reason
## `ControlOverlay.turn_cap` exists: the tight loop constructs its own `BoutRunner` and the
## yielding path constructs one inside `advance_ai_turns`, so capping only the reachable one
## would compare a 16-turn bout against a 164-turn bout and fail for the most boring reason
## available.


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
##
## ## taskblock-58 Pass C.2: the budget is not this test's subject
##
## **`PlanPacer`'s wall-clock budget is raised here so it cannot trip, and that is the point of the
## raise.** This test was written to assert one thing — the same seed lands in the same state
## whether driven through the yielding overlay or through a tight loop — and it was accidentally
## asserting something about wall-clock as well, because the yielding path aborts on a deadline and
## the tight loop has no pacer to abort. A slower machine then fails a test about determinism for a
## reason that has nothing to do with determinism, which is what happened when taskblock-58 Pass C
## raised planning cost.
##
## **This is not the regression being hidden.** `BR58.01` owns it, with the numbers and the
## mechanism: the defect is that the budget is wall-clock **at all**, so the same seed produces
## different bouts on different hardware — latent since taskblock-44 and unobserved while planning
## stayed under the number. Raising it here refuses to let one test carry two claims; the fix is
## `PLAN.md`'s own item.
##
## **The comparison itself is untouched.** The fingerprint equality is the whole test, and the
## companion assertion below checks the raise was genuinely enough rather than assuming headroom.
func test_a_yielding_batch_produces_the_identical_bout() -> void:
	var tight: Dictionary = _bout(4242)
	assert_eq(tight.get("error", ""), "", "sanity: the bout built")
	var tight_runner := BoutRunner.new(tight.state, tight.mission, TURN_CAP)
	# The guard stays, above the cap, so it is a backstop against a runner that never reports
	# finished rather than the thing that ends the loop. If it is ever what stops this, the
	# fingerprints will not match and that is the correct outcome.
	var guard := 0
	while not tight_runner.finished and guard < TURN_CAP * 4:
		await tight_runner.step()
		guard += 1
	var expected: String = _fingerprint(tight.state)

	var yielded: Dictionary = _bout(4242)
	var battle := BattleScene.new()
	add_child_autofree(battle)
	# **Both fields are set before `load_battle`, and that ordering is load-bearing.**
	# `load_battle` emits `battle_loaded`, which `_on_battle_loaded` answers by awaiting
	# `advance_ai_turns` — so a field set afterwards does not reach the batch that call starts.
	# That is precisely what left `test_frames_pass_during_the_batch` playing 400 turns while its
	# own header claimed a handful, and configuring after handing off would have reintroduced it
	# here with an uncapped batch racing the capped one.
	var overlay := ControlOverlay.new()
	overlay.pacer_budget_msec = UNREACHABLE_BUDGET_MSEC
	overlay.turn_cap = TURN_CAP
	battle.set_overlay(overlay)
	battle.load_battle(yielded.state, yielded.mission)
	await overlay.advance_ai_turns(battle)

	# **The turns actually ran.** A cap that stopped the bout at zero would make the equality
	# vacuous — two untouched states match trivially — so the length is asserted rather than
	# trusted, which is the failure mode a shorter bout genuinely does introduce.
	# `turns_taken` for the tight loop; the yielding path builds its runner inside
	# `advance_ai_turns`, so `round_number` off the state is what is readable from here.
	(
		gut
		. p(
			(
				"cap %d: tight took %d turns to round %d, yielding reached round %d"
				% [
					TURN_CAP,
					tight_runner.turns_taken,
					tight.state.round_number,
					yielded.state.round_number,
				]
			)
		)
	)
	assert_eq(
		tight_runner.turns_taken,
		TURN_CAP,
		"the bout must actually reach the cap, or this is comparing two bouts that never ran"
	)
	assert_eq(_fingerprint(yielded.state), expected, "yielding must not change the sim at all")
	# **Otherwise the raise is a guess about headroom.** If this ever fires, the two paths diverged
	# for the reason `BR58.01` describes and the equality above became untrustworthy rather than
	# false — a distinction worth being told about.
	assert_not_null(overlay.last_pacer, "the overlay really did pace this run")
	assert_false(
		(overlay.last_pacer as PlanPacer).aborted,
		"the raised budget must genuinely not be reached, or this test is measuring it again"
	)


## The yield itself: frames actually pass while the batch runs, which is what
## keeps input alive and the board drawing.
##
## taskblock-47 Pass E1: **squad 0 is HUMAN here, and that is the scenario the
## function is for.** `advance_ai_turns` exits on `wants_turn_for`, so an all-AI bout
## never hits that condition and plays the entire mission — this test was spending a
## whole bout to prove that at least one frame passed. Handing over to a human is what
## the game actually does, it exercises the same yield, and it costs a handful of
## turns instead of hundreds.
##
## ## tb65 Pass D: the handover was happening one line too late, and had been since tb47
##
## **`battle.load_battle()` drives the batch itself.** It emits `battle_loaded`, which
## `_on_battle_loaded` answers by *awaiting* `advance_ai_turns` — so by the time the line below
## it flipped squad 0 to HUMAN, `BoutSetup`'s two-AI-squads bout had already been played to the
## 400-turn cap. tb47's saving was written, committed, and then not collected: **measured at 400
## of this file's 432 turns**, which is most of what made it 19.6% of the full gate.
##
## The controller is set **before** `load_battle` now, which is also what a real caller does —
## `BattleScene.toggle_blue_control` flips the squad and then loads. The assertion is unchanged.
##
## **`turn_cap` is set too, as a backstop rather than as the mechanism.** If the handover ever
## breaks again the cap keeps the damage to sixteen turns instead of four hundred, and the turn
## counter in `test_suite_budget.gd` is what would say so.
func test_frames_pass_during_the_batch() -> void:
	var built: Dictionary = _bout(77)
	var battle := BattleScene.new()
	add_child_autofree(battle)
	var overlay := ControlOverlay.new()
	overlay.turn_cap = TURN_CAP
	battle.set_overlay(overlay)
	built.state.set_squad_controller(0, Enums.SquadController.HUMAN)
	battle.load_battle(built.state, built.mission)

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
