extends GutTest

## taskblock-29 Pass C: determinism & safety guards. Pass A/B already
## cover the mid-resolution guard, the `&"inject"` log, and `was_injected`
## being set — this file covers what's left: injection is unreachable
## from a normal player-controlled overlay, and the same injections in the
## same order on the same seed reproduce the same result.


## "Compile/route it so a shipping player path cannot invoke it." Since
## GDScript has no real access-control keyword, the actual guarantee is
## structural: neither of the two PLAYER-facing view files (the ones a
## normal, human-controlled bout actually runs through) may reference
## `BoutInjector` at all — read straight from source, the literal claim
## the taskblock makes ("a routing/guard test"), not a re-derivation of it.
func test_bout_injector_is_never_referenced_by_a_player_controlled_view() -> void:
	var player_facing_paths: Array[String] = [
		"res://src/view/overlays/squad_control_overlay.gd",
		"res://src/view/tactics_controller.gd",
	]
	for path: String in player_facing_paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "sanity: %s must exist to check at all" % path)
		var source: String = file.get_as_text()
		assert_false(
			source.contains("BoutInjector"),
			"%s must never reference BoutInjector — a real player bout can't reach it" % path
		)


## taskblock-29 Pass D: the sibling of the guard test above — the ONE
## legitimate debug/spectator context this ever gets constructed in.
func test_bout_injector_is_referenced_by_the_spectator_overlay() -> void:
	var file := FileAccess.open("res://src/view/overlays/spectator_overlay.gd", FileAccess.READ)
	assert_not_null(file)
	assert_true(
		file.get_as_text().contains("BoutInjector"),
		"the spectator overlay is the one legitimate debug/spectator context for this"
	)


func _make_unit(id_hint: String, cell: Vector2i, squad: int) -> Unit:
	var torso := Part.new()
	torso.id = StringName("%s_torso" % id_hint)
	torso.hp = 10
	torso.max_hp = 10
	return Unit.new(Matrix.new(), Shell.new(torso), cell, squad)


func _snapshot(state: CombatState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for unit: Unit in state.units:
		rows.append(
			{
				"id": unit.id,
				"cell": unit.cell,
				"squad_id": unit.squad_id,
				"hp": unit.shell.root.hp,
				"alive": unit.alive,
			}
		)
	return rows


## "The same injections in the same order on the same seed reproduce the
## same result" — build the exact same bout twice from the same seed,
## drive a few real turns through BoutRunner, apply the exact same
## injection sequence at the exact same points, drive more turns, and
## compare the full resulting roster.
func test_the_same_injections_in_the_same_order_reproduce_the_same_result() -> void:
	var snapshots: Array[Array] = []
	for _run in range(2):
		var a := _make_unit("a", Vector2i(0, 0), 0)
		var b := _make_unit("b", Vector2i(9, 0), 1)
		var state := CombatState.new(Grid.new(12, 12), [a, b], 4242)
		state.set_squad_controller(0, Enums.SquadController.AI)
		state.set_squad_controller(1, Enums.SquadController.AI)
		var mission := MissionState.new(RunState.new(), state)
		mission.objectives = []
		mission.extraction_cells = [Vector2i(0, 0)]
		var runner := BoutRunner.new(state, mission, 20)
		var injector := BoutInjector.new(state)

		runner.step()
		injector.set_position(state.find_unit(a.id), Vector2i(4, 4))
		injector.set_ap(state.find_unit(b.id), 1)
		runner.step()
		runner.step()

		snapshots.append(_snapshot(state))

	assert_eq(snapshots[0], snapshots[1])
