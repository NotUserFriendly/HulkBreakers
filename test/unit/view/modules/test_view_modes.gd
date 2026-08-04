extends GutTest

## taskblock-56 Pass D — **THE ACCEPTANCE: "a mode is a declaration; adding one is a table entry."**
##
## Four overlay subclasses (942 + 718 + 373 + 54 lines) became four rows in `ViewModes`. The claim
## this file has to make good on is not "the four still work" — the migrated overlay tests cover
## that — it is that **the fifth one costs a table entry and nothing else**.
##
## So the central test builds a mode that exists nowhere in `src/`, mounts it against a real
## `BattleScene`, and asserts it produced exactly the modules it declared. If that ever needs a new
## file, a subclass, or a branch in `ControlOverlay`, this is what fails.
##
## The second claim is Spectator's contract, which used to be expressed by *not inheriting* the
## player overlay: **a mode with no input modules cannot mutate state through the view.** Asserted
## twice over — once from the declaration alone (no battle needed) and once against a mounted
## surface, because a declaration that says the right thing and a surface that does the right thing
## are different facts.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _battle() -> BattleScene:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	# `_ready()` installs the player mode; a bare surface neutralises it so nothing drives a turn
	# out from under the mode under test.
	battle.set_overlay(ControlOverlay.new())
	return battle


func _mount(mode: ViewMode) -> ControlOverlay:
	var battle: BattleScene = _battle()
	var overlay: ControlOverlay = ControlOverlay.for_mode(mode)
	battle.set_overlay(overlay)
	return overlay


## **THE ACCEPTANCE.** A mode nothing in `src/` declares, built here in six lines and mounted.
##
## Deliberately an odd combination no shipped mode uses — the combat log and the inspect modal, with
## no board picking, no playback and no input — so it cannot accidentally be satisfied by one of the
## four real modes' code paths.
func test_a_mode_nothing_in_src_declares_can_be_built_and_mounted() -> void:
	var mode := ViewMode.new()
	mode.id = &"invented_for_this_test"
	mode.display_name = "Invented"
	mode.chrome = ModeChrome.TOP_LEFT_ROWS
	mode.modules = [&"combat_log", &"inspect"] as Array[StringName]
	mode.turn_policy = ViewMode.TurnPolicy.NONE

	var overlay: ControlOverlay = _mount(mode)

	assert_eq(overlay.modules.size(), 2, "the surface built exactly what the table entry declared")
	assert_not_null(overlay.module(&"combat_log"))
	assert_not_null(overlay.module(&"inspect"))
	assert_null(overlay.module(&"unit_input"), "a module it did not declare must not appear")
	assert_false(overlay.has_unit_input(), "and it declared no input, so it has none")


## Every shipped mode composes exactly the module set it declares — in order, with no extras and
## none missing. The "renders identically before and after, by the module set it produces rather
## than by pixels" half of the pass's own acceptance.
func test_every_mode_composes_the_module_set_it_declares() -> void:
	for mode: ViewMode in ViewModes.all():
		var overlay: ControlOverlay = _mount(mode)
		var produced: Array[StringName] = []
		for mounted: ViewModule in overlay.modules:
			produced.append(mounted.module_id())
		gut.p("%s -> %s" % [mode.id, ", ".join(produced) if not produced.is_empty() else "(none)"])
		assert_eq(
			produced, mode.modules, "%s produced a different module set than it declared" % mode.id
		)


## **Spectator's whole contract, asserted from the declaration.** Checkable without building
## anything, which is the point of a mode being data.
func test_the_spectator_mode_declares_no_unit_input() -> void:
	assert_false(
		ViewModes.spectator().has_unit_input(),
		"a spectator cannot play the battle -- no module here may queue an action"
	)
	assert_false(ViewModes.bout_setup().has_unit_input(), "a pre-battle menu drives no unit")
	assert_false(ViewModes.empty().has_unit_input(), "an empty surface drives nothing")
	assert_true(ViewModes.player().has_unit_input(), "and the player mode does, or nothing works")
	assert_true(ViewModes.single_unit().has_unit_input())


## The same contract against a **mounted** surface, because a declaration saying the right thing and
## a surface doing the right thing are two facts. A mode with no input modules has no
## `TacticsController` at all — which is the concrete reason there is no path from a click in that
## mode to `ActionQueue.enqueue`.
func test_a_mode_with_no_input_modules_has_no_tactics_controller() -> void:
	var spectator: ControlOverlay = _mount(ViewModes.spectator())
	assert_false(spectator.has_unit_input())
	assert_null(spectator.tactics(), "no TacticsController means no path from a click to the queue")
	assert_null(
		spectator.module_context.tactics, "and nothing published one into the shared context"
	)

	var player: ControlOverlay = _mount(ViewModes.player())
	assert_true(player.has_unit_input())
	assert_not_null(player.tactics(), "the player mode must have one, or the contrast is vacuous")


## **`single_unit` is `player` plus one field.** Stated as a test because it is the clearest
## evidence that the collapse worked: what used to be a 54-line subclass is now a difference of one
## value.
func test_the_single_unit_mode_differs_from_the_player_mode_by_exactly_one_field() -> void:
	var player: ViewMode = ViewModes.player()
	var single: ViewMode = ViewModes.single_unit()
	assert_eq(single.modules, player.modules, "same modules")
	assert_eq(single.chrome, player.chrome, "same chrome")
	assert_eq(single.options, player.options, "same options")
	assert_ne(single.turn_policy, player.turn_policy, "and exactly one thing different")
	assert_eq(single.turn_policy, ViewMode.TurnPolicy.SINGLE_UNIT)


## A mode listing an id the catalog does not know gets a surface without it, not a crash — the same
## "no further action, no silent rollback" posture `ActionCatalog.build_firing_action` has.
func test_an_unknown_module_id_is_skipped_rather_than_fatal() -> void:
	var mode := ViewMode.new()
	mode.id = &"has_a_typo"
	mode.modules = [&"combat_log", &"comabt_log"] as Array[StringName]

	var overlay: ControlOverlay = _mount(mode)

	assert_eq(overlay.modules.size(), 1, "the known one mounted, the typo was skipped")
	assert_not_null(overlay.module(&"combat_log"))


## Options are applied before mount, by name, with no code in `ControlOverlay` knowing what any of
## them mean. That genericity is what makes an option a table entry too.
func test_a_modes_options_reach_its_modules_before_they_mount() -> void:
	var mode := ViewMode.new()
	mode.id = &"inspect_with_a_button"
	mode.modules = [&"inspect"] as Array[StringName]
	mode.options[&"inspect"] = {&"with_button": true}

	var overlay: ControlOverlay = _mount(mode)
	var inspect: InspectModule = overlay.inspect()

	assert_true(inspect.with_button, "the option was applied")
	assert_not_null(inspect.button, "and it was applied BEFORE mount, so the button got built")


func test_the_same_module_with_no_option_keeps_its_own_default() -> void:
	var mode := ViewMode.new()
	mode.id = &"inspect_bare"
	mode.modules = [&"inspect"] as Array[StringName]

	var overlay: ControlOverlay = _mount(mode)

	assert_false(overlay.inspect().with_button, "no entry means the module's own default")
	assert_null(overlay.inspect().button)


## Every mode is reachable by id, and a name nobody declared refuses rather than defaulting — a
## silent fall-back to the player mode would hand unit input to a caller that asked for a spectator.
func test_modes_resolve_by_id_and_an_unknown_one_refuses() -> void:
	for mode: ViewMode in ViewModes.all():
		assert_not_null(ViewModes.by_id(mode.id), "%s must be findable by its own id" % mode.id)
		assert_eq(ViewModes.by_id(mode.id).id, mode.id)
	assert_null(ViewModes.by_id(&"no_such_mode"))


## A modeless surface is the empty one. **Not the player one** — that default was briefly in place
## and was actively wrong: the player mode has unit input, so it drives the AI batch, and every
## fixture that installs a bare placeholder to neutralise `_ready()` found its bout a turn further
## on with units standing somewhere else.
func test_a_modeless_surface_mounts_nothing_and_drives_nothing() -> void:
	var battle: BattleScene = _battle()
	var overlay: ControlOverlay = battle.overlay as ControlOverlay

	assert_eq(overlay.mode.id, &"empty", "a modeless surface resolves to the empty mode")
	assert_eq(overlay.modules.size(), 0, "and mounts nothing at all")
	assert_false(overlay.has_unit_input())
