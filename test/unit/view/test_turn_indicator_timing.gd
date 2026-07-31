extends GutTest

## taskblock-51 Pass L (`BR27.07` / `BR32.09`): **the active-turn indicator must not advance
## while playback is still drawing the previous unit's move.**
##
## The supervisor's controlled comparison is the diagnosis, and it was worth more than the
## other three reports combined:
##
## > *"The indicator moves to the next unit before the animation completes when the AI is
## > controlling. It moves with the unit correctly when the player is controlling."*
##
## A human turn ends *after* its own animation, so the player path never exposes the gap.
## tb32 Pass D fixed exactly this and its comment on `SquadControlOverlay` calls it "a real
## confirmed bug" — but only that one call site was changed. `SpectatorOverlay._advance()` went
## on applying the highlight *before* `resolution_player.play()`, which is the AI path.
##
## ## What these cover, and what they do not
##
## They pin the **deferral primitive**: that `apply_highlight = false` genuinely withholds the
## flip, and that `apply_active_turn_highlight()` genuinely performs it. The fix itself is
## reordering two lines in `SpectatorOverlay._advance()` to use them the way the player path
## already does.
##
## **Driving `_advance()` end-to-end headlessly is not covered here, and that is a real gap,
## not an omission**: a spy standing in for `ResolutionPlayer` hangs the runner rather than
## failing it (a runtime error under `-d` becomes a debugger break). So the ordering inside
## `_advance` is verified by reading it against the player path it now matches, and the
## primitive it depends on is verified here.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _battle() -> BattleScene:
	var grid: Grid = GridFixture.flat(12, 12)
	var first: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var second: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(8, 8), 1)
	var state := CombatState.new(grid, [first, second])
	state.assign_rest_to_ai([] as Array[int])
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, MissionState.new(RunState.new(), state))
	return battle


func _highlighted(battle: BattleScene) -> Array[int]:
	var out: Array[int] = []
	for view: HitVolumeView in battle.unit_views:
		if view._is_active_turn and view.unit != null:
			out.append(view.unit.id)
	return out


## **The deferral actually withholds the flip.** If `apply_highlight = false` still applied it,
## every caller that carefully deferred would be deferring nothing — and both AI and player
## paths would have the bug with no way to tell from the call site.
func test_deferring_leaves_the_indicator_where_it_was() -> void:
	var battle: BattleScene = _battle()
	var acting: Unit = battle.combat_state.current_unit()
	battle.apply_active_turn_highlight()
	assert_eq(_highlighted(battle), [acting.id] as Array[int], "sanity: it starts on the actor")

	battle.combat_state.advance_turn()
	battle.refresh_unit_views(null, false)

	gut.p("after a deferred refresh, highlighted: %s" % str(_highlighted(battle)))
	assert_eq(
		_highlighted(battle),
		[acting.id] as Array[int],
		"the indicator stayed on the unit whose move is still being drawn"
	)
	assert_ne(battle.combat_state.current_unit(), acting, "even though the turn has moved on")


## And the explicit call performs it — deferring must not mean never applying.
func test_applying_it_afterwards_moves_the_indicator() -> void:
	var battle: BattleScene = _battle()
	var acting: Unit = battle.combat_state.current_unit()
	battle.apply_active_turn_highlight()
	battle.combat_state.advance_turn()
	battle.refresh_unit_views(null, false)

	battle.apply_active_turn_highlight()

	var current: Unit = battle.combat_state.current_unit()
	assert_eq(_highlighted(battle), [current.id] as Array[int], "it caught up, and only it")
	assert_false(_highlighted(battle).has(acting.id), "the previous actor let go")


## **The default is still to apply**, so a caller that never opts into deferring is unchanged.
func test_an_undeferred_refresh_still_applies_the_highlight() -> void:
	var battle: BattleScene = _battle()
	var acting: Unit = battle.combat_state.current_unit()
	battle.apply_active_turn_highlight()
	battle.combat_state.advance_turn()

	battle.refresh_unit_views()

	assert_false(_highlighted(battle).has(acting.id), "the flip happened without being asked for")
