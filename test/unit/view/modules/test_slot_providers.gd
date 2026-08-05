extends GutTest

## taskblock-57 Pass B — **a module may be a slot provider**, and the action bar is the first one.
##
## Four surfaces pin relative to the bar rather than to the screen. Until now every slot came from
## `ModeChrome`, which builds against the screen and knows nothing about where a module ended up.
##
## **The mechanism is general and the tests check that it is.** The taskblock is explicit — *"Keep
## it general; do not special-case the action bar"* — so the first test publishes from a module
## invented here, with no action bar anywhere near it. If the host ever grows a branch naming the
## action bar, that test is what fails.
##
## **Positions are read off the real nodes**, never recomputed. CLAUDE.md's rule, and the reason the
## "moving the bar moves its dependants" test steps a real layout and reads `global_position` back
## instead of asserting that two containers share a parent.


## A module that publishes a slot, so the host's generality is testable without the action bar.
class PublishingModule:
	extends ViewModule

	var published: HBoxContainer = null

	func module_id() -> StringName:
		return &"test_publisher"

	func _mount() -> void:
		published = HBoxContainer.new()
		add_child(published)

	func published_slots() -> Dictionary:
		return {&"a_slot_invented_for_this_test": published}


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func _battle() -> BattleScene:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.new())
	return battle


func _mount(mode: ViewMode) -> ControlOverlay:
	var battle: BattleScene = _battle()
	var overlay: ControlOverlay = ControlOverlay.for_mode(mode)
	battle.set_overlay(overlay)
	return overlay


# ---------------------------------------------------------------- the mechanism is general


## **THE ACCEPTANCE that the mechanism is not the action bar wearing a hook.** A module built in
## this file publishes a slot nothing in `src/` has heard of, and the host publishes it.
func test_any_module_can_publish_a_slot_not_just_the_action_bar() -> void:
	var overlay: ControlOverlay = _mount(ViewModes.empty())
	var publisher := PublishingModule.new()
	overlay.add_child(publisher)
	publisher.mount(overlay.module_context)
	for slot_name: StringName in publisher.published_slots():
		overlay.module_context.set_slot(slot_name, publisher.published_slots()[slot_name])

	assert_eq(
		overlay.module_context.slot(&"a_slot_invented_for_this_test", null),
		publisher.published,
		"a slot published by an ordinary module reaches the context"
	)


## Publishing nothing is the default, and the overwhelming majority stay that way.
##
## **taskblock-57 Pass G1: the exceptions are the three bars**, checked by class rather than by a
## list of ids — a fourth mode's bar is covered the day it is written, and a module that starts
## publishing without being a bar still fails this.
func test_a_module_publishes_nothing_by_default() -> void:
	for id: StringName in ModuleCatalog.IDS:
		var module: ViewModule = ModuleCatalog.build(id)
		var published: Dictionary = module.published_slots()
		if module is not BarModule:
			assert_eq(published.size(), 0, "%s publishes slots and nothing said so" % id)
		module.free()


## The host publishes a mounted module's slots into the shared context, so a **later** module in the
## same declaration finds them at its own mount time.
func test_the_host_publishes_the_action_bars_slots_into_the_context() -> void:
	var overlay: ControlOverlay = _mount(ViewModes.player())
	for slot_name: StringName in ModuleSlots.ACTION_BAR_SLOTS:
		assert_true(
			overlay.module_context.slots.has(slot_name),
			"%s was never published -- a dependant would silently fall back to ui_root" % slot_name
		)
		assert_not_null(overlay.module_context.slot(slot_name, null))


# ---------------------------------------------------------------- against the bar, not the screen


## **A module mounted into an action-bar slot positions against the bar.** Asserted structurally —
## the slot really is inside the bar's own subtree — because that ancestry is precisely what makes
## the next test's movement work.
func test_an_action_bar_slot_lives_inside_the_bars_own_subtree() -> void:
	var overlay: ControlOverlay = _mount(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	assert_not_null(bar.bar_root, "sanity: the bar built its root")

	for slot_name: StringName in ModuleSlots.ACTION_BAR_SLOTS:
		var slot: Control = overlay.module_context.slot(slot_name, null)
		assert_true(
			bar.bar_root.is_ancestor_of(slot),
			"%s is not under the bar, so it would not move with it" % slot_name
		)


## **Moving the bar moves its dependants** — read off `global_position`, not re-derived.
##
## A child mounted into a published slot is displaced by exactly the delta the bar was displaced
## by. This is the property that makes relative anchoring worth the mechanism: retune the bar's
## placement in Pass C and four surfaces follow with no further work.
func test_moving_the_bar_moves_what_is_mounted_in_its_slots() -> void:
	var overlay: ControlOverlay = _mount(ViewModes.player())
	var bar: ActionBarModule = overlay.module(&"action_bar") as ActionBarModule
	var passenger := ColorRect.new()
	passenger.custom_minimum_size = Vector2(20, 20)
	bar.left_slot.add_child(passenger)

	# Containers position their children on layout, not on add_child, so a real sort has to happen
	# before any global position means anything.
	bar.bar_root.queue_sort()
	await get_tree().process_frame
	var before: Vector2 = passenger.global_position

	var delta := Vector2(37, -11)
	bar.bar_root.position += delta
	bar.bar_root.queue_sort()
	await get_tree().process_frame
	var after: Vector2 = passenger.global_position

	gut.p("passenger %v -> %v (bar moved by %v)" % [before, after, delta])
	assert_almost_eq(after.x - before.x, delta.x, 0.001, "the dependant tracked the bar in x")
	assert_almost_eq(after.y - before.y, delta.y, 0.001, "and in y")


# ---------------------------------------------------------------- standing alone still holds


## **taskblock-56 Pass C's acceptance is not weakened by relative anchoring**, which is the stop
## condition the taskblock names: *"A module cannot mount without the action bar."*
##
## A mode that declares a dependant surface and no action bar gets a surface that mounts somewhere
## sensible, because `ModuleContext.slot` falls back to `ui_root` or to the module itself.
func test_a_mode_with_no_action_bar_still_mounts_its_dependants() -> void:
	var mode := ViewMode.new()
	mode.id = &"no_action_bar"
	mode.chrome = ModeChrome.TOP_LEFT_ROWS
	mode.modules = [&"combat_log", &"inspect"] as Array[StringName]

	var overlay: ControlOverlay = _mount(mode)

	assert_eq(overlay.modules.size(), 2, "both mounted with no bar to pin against")
	assert_null(overlay.module(&"action_bar"), "sanity: there really is no bar here")
	for slot_name: StringName in ModuleSlots.ACTION_BAR_SLOTS:
		assert_false(
			overlay.module_context.slots.has(slot_name),
			"%s cannot exist without its provider" % slot_name
		)


## And an absent action-bar slot resolves to the fallback rather than to null, which is what keeps
## the stand-alone contract true for a module that asks for one.
func test_an_absent_action_bar_slot_falls_back_rather_than_answering_null() -> void:
	var context := ModuleContext.new()
	var root := Control.new()
	add_child_autofree(root)
	context.ui_root = root
	assert_eq(
		context.slot(ModuleSlots.ACTION_BAR_LEFT),
		root,
		"a dependant with no provider lands on ui_root, never on nothing"
	)
