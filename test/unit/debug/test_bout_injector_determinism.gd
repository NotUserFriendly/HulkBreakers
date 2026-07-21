extends GutTest

## taskblock-29 Pass C: determinism & safety guards. Pass A/B already
## cover the mid-resolution guard, the `&"inject"` log, and `was_injected`
## being set — this file covers what's left: injection is unreachable
## from a normal player-controlled overlay, and the same injections in the
## same order on the same seed reproduce the same result.


## "Compile/route it so a shipping player path cannot invoke it." Since
## GDScript has no real access-control keyword, the actual guarantee is
## structural — but taskblock-30 moves the real seam: it's not "no overlay
## installed under player control may reference BoutInjector" anymore
## (SquadControlOverlay legitimately does, behind its own OS.is_debug_
## build() gate), it's "no gameplay-INPUT class may" — TacticsController
## (the click/arm/confirm state machine) and ActionBar (what turns an
## action-bar click into an armed action) are the two files that translate
## raw player input into game state; neither may reference BoutInjector at
## all, read straight from source.
func test_bout_injector_is_never_referenced_by_a_gameplay_input_class() -> void:
	var input_paths: Array[String] = [
		"res://src/view/tactics_controller.gd",
		"res://src/view/action_bar.gd",
	]
	for path: String in input_paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "sanity: %s must exist to check at all" % path)
		var source: String = file.get_as_text()
		assert_false(
			source.contains("BoutInjector"),
			"%s must never reference BoutInjector — no ordinary click/action may reach it" % path
		)


## taskblock-29 Pass D / taskblock-30: the two legitimate debug contexts
## this ever gets constructed in — spectator (unconditionally, its own
## whole purpose) and the player-controlled overlay (behind its own real
## `OS.is_debug_build()` gate, taskblock-30's own extension) — never
## `TacticsController`/`ActionBar` themselves (see the guard test above).
## Case-insensitive: taskblock-30/31 Pass C's own doc comments moved to
## naming the lowercase `bout_injector` FIELD rather than the class name
## directly in places (both still legitimately touch the real channel,
## via `battle.bout_injector`/`DebugControlPanel`) — the claim under test
## is "this file has something to do with injection," not "the literal
## class name string appears."
func test_bout_injector_is_referenced_by_both_overlays() -> void:
	var overlay_paths: Array[String] = [
		"res://src/view/overlays/spectator_overlay.gd",
		"res://src/view/overlays/squad_control_overlay.gd",
	]
	for path: String in overlay_paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "sanity: %s must exist to check at all" % path)
		assert_true(
			file.get_as_text().to_lower().contains("bout_injector"),
			"%s is a legitimate debug context for this, gated its own way" % path
		)


## taskblock-30 (tempnotes review): "the [*] affordance needs real
## debug-gating, not just the prefix." Both overlays must gate their own
## Inject button behind the SAME real check (`OS.is_debug_build()`), not
## merely label it `[*]` — the false branch (a release export) can't be
## exercised in this harness (there's no separate release build to run
## against), so this pins the STRUCTURAL claim instead: the literal gate
## call actually guards the button construction in both files' own
## source, not just documented intent in a comment.
func test_both_overlays_gate_their_inject_button_behind_a_real_debug_check() -> void:
	var overlay_paths: Array[String] = [
		"res://src/view/overlays/spectator_overlay.gd",
		"res://src/view/overlays/squad_control_overlay.gd",
	]
	for path: String in overlay_paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "sanity: %s must exist to check at all" % path)
		var lines: PackedStringArray = file.get_as_text().split("\n")
		var gate_line := -1
		for i in range(lines.size()):
			if lines[i].strip_edges() == "if OS.is_debug_build():":
				gate_line = i
				break
		assert_true(gate_line >= 0, "%s must gate on OS.is_debug_build() somewhere" % path)
		var found_inject_nearby := false
		for i in range(gate_line, mini(gate_line + 4, lines.size())):
			if "inject_button" in lines[i] and "Button.new()" in lines[i]:
				found_inject_nearby = true
		assert_true(
			found_inject_nearby,
			"%s must construct inject_button INSIDE the debug-build check, not just near it" % path
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
