extends GutTest

## taskblock-51 `BR48.01`: **what the inspector leaves in the battle's world.**
##
## Two diagnoses have now been wrong — an empty modal, then the preview's own lighting nodes —
## and the supervisor reports the board still dims, with *"starting a new bout does fix it"*.
## That last detail is the useful one: whatever it is lives in the battle scene, not in a
## shared resource, because a resource would survive the rebuild too.
##
## So this stops theorising and dumps the actual 3D inventory of the shared `World3D` at three
## points — before, during and after an inspect cycle. Per `docs/00`: a system nobody can dump
## is one nobody can verify, and the same applies to a defect that has already survived two
## confident fixes.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _describe(node: Node, out: Array[String], depth: int = 0) -> void:
	var line := ""
	if node is Light3D:
		var light := node as Light3D
		line = (
			"%s Light3D %s visible=%s energy=%.2f layers=%d"
			% [
				node.name,
				node.get_class(),
				light.visible,
				light.light_energy,
				light.light_cull_mask
			]
		)
	elif node is WorldEnvironment:
		var world_env := node as WorldEnvironment
		line = "%s WorldEnvironment environment=%s" % [node.name, world_env.environment != null]
	elif node is Camera3D:
		var camera := node as Camera3D
		line = (
			"%s Camera3D current=%s environment=%s cull=%d"
			% [node.name, camera.current, camera.environment != null, camera.cull_mask]
		)
	elif node is SubViewport:
		line = "%s SubViewport own_world_3d=%s" % [node.name, (node as SubViewport).own_world_3d]
	if line != "":
		out.append("%s%s" % ["  ".repeat(depth), line])
	# **Do not descend into a viewport that owns its world** — its contents are in a different
	# `World3D` and cannot light the battle. Descending anyway is what made the first version
	# of this comparison fail on the panel's own internals, which are allowed to change.
	if node is SubViewport and (node as SubViewport).own_world_3d:
		return
	for child: Node in node.get_children():
		_describe(child, out, depth + 1)


func _inventory(root: Node) -> Array[String]:
	var out: Array[String] = []
	_describe(root, out)
	return out


## **Only what actually lights the battle's `World3D`**: a light that is visible, or a
## `WorldEnvironment` that still holds an `Environment`, and nothing inside a viewport that
## owns its own world. The full `_inventory` above is the dump for reading; this is the thing
## worth asserting, and keeping them separate is what stopped the panel's own internals — which
## are allowed to change — from failing the comparison.
func _battle_lighting(root: Node) -> Array[String]:
	var out: Array[String] = []
	for line: String in _inventory(root):
		var trimmed: String = line.strip_edges()
		if trimmed.contains("Light3D") and trimmed.contains("visible=true"):
			out.append(trimmed)
		elif trimmed.contains("WorldEnvironment") and trimmed.contains("environment=true"):
			out.append(trimmed)
	return out


## **The invariant, stated once and checked at every stage:** the preview's private lighting
## is either in its own world, or withdrawn — never contributing to the battle's.
func _lighting_is_out_of_the_battle_world(panel: InspectPanel) -> bool:
	if panel._preview_viewport.own_world_3d:
		return true
	return not panel._preview_light.visible and panel._preview_environment.environment == null


## **The dump is the point.** Two confident diagnoses were wrong before this — an empty modal,
## then "closing does not release the world" — and both were argued from reading the code. The
## inventory settled it in one run: `SubViewport.own_world_3d` **defaults to false**, so the
## panel's `WorldEnvironment` and `DirectionalLight3D` were in the battle's `World3D` from the
## moment it was built. The board was quietly double-lit, and the first subject that took the
## fallback path removed that second light permanently.
##
## The supervisor's *"starting a new bout does fix it"* is the detail that proves it: a rebuilt
## panel restores the accidental light, and nothing else in either theory would come back.
func test_the_previews_lighting_never_reaches_the_battle_world() -> void:
	var grid: Grid = GridFixture.flat(10, 10)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	state.assign_rest_to_ai([] as Array[int])
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, MissionState.new(RunState.new(), state))
	battle.set_overlay(SpectatorOverlay.new())
	var overlay: SpectatorOverlay = battle.overlay as SpectatorOverlay
	var panel: InspectPanel = overlay.inspect_panel

	for line: String in _inventory(battle):
		gut.p("at rest: %s" % line)
	assert_true(_lighting_is_out_of_the_battle_world(panel), "at rest, before anything is opened")

	panel.open(unit)
	assert_true(_lighting_is_out_of_the_battle_world(panel), "while isolating a live subject")

	panel.close()
	assert_true(_lighting_is_out_of_the_battle_world(panel), "after closing")

	# The fallback path is what used to take the light away for good — a subject with no live
	# view on the board, which is what a click on cover or a loose item resolves to.
	panel.open_cell(Vector2i(5, 5), null)
	assert_true(_lighting_is_out_of_the_battle_world(panel), "after a subject with no live view")

	panel.close()
	assert_true(_lighting_is_out_of_the_battle_world(panel), "and after closing that")


## **The board's own lighting is unchanged by an inspect cycle**, which is the property the
## supervisor was actually missing: not "it is bright" or "it is dim", but that it is the same
## before and after.
func test_the_boards_own_lighting_is_identical_before_and_after() -> void:
	var grid: Grid = GridFixture.flat(10, 10)
	var unit: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i(2, 2), 0)
	var state := CombatState.new(grid, [unit])
	state.assign_rest_to_ai([] as Array[int])
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	battle.load_battle(state, MissionState.new(RunState.new(), state))
	battle.set_overlay(SpectatorOverlay.new())
	var panel: InspectPanel = (battle.overlay as SpectatorOverlay).inspect_panel

	var before: Array[String] = _battle_lighting(battle)
	panel.open(unit)
	panel.close()
	panel.open_cell(Vector2i(5, 5), null)
	panel.close()
	var after: Array[String] = _battle_lighting(battle)
	gut.p("battle lighting before: %s" % str(before))
	gut.p("battle lighting after:  %s" % str(after))

	for i in range(mini(before.size(), after.size())):
		if before[i] != after[i]:
			gut.p("CHANGED: %s -> %s" % [before[i], after[i]])
	assert_eq(after, before, "two full inspect cycles left the scene's lighting exactly as it was")
