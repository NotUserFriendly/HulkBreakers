extends GutTest

## taskblock-57 Pass A — **a slot's properties, and the collapsible rule derived from them.**
##
## The rule: *everything pinned to a side is collapsible or off by default, so a square-ratio player
## is never forced to shrink the UI to play.* A module answers that about itself by asking which
## slot it wants, rather than each one carrying a flag that can drift from where it actually sits.
##
## ## The vacuity is stated rather than hidden
##
## Pass A's own test reads "every side-pinned module reports itself collapsible". **No module
## declares a `preferred_slot()` yet** — that lands in Pass C, when the modules are re-slotted — so
## iterating `ModuleCatalog` today would range over an empty set and pass while proving nothing.
## That is the failure shape `docs/TEST-AUDIT.md` keeps finding, so instead:
##
## - the **derivation** is tested against synthetic modules, which is a real assertion today;
## - the **current state** is asserted explicitly, so this file goes red the moment a module starts
##   declaring a slot and the real sweep below stops being vacuous;
## - the sweep itself is written and runs, so Pass C inherits it rather than having to remember it.

## Every module that declares an edge-pinned slot, as of this pass. **Empty, because Pass C is
## where modules are re-slotted** — and pinned as a list rather than left implicit so the sweep
## below always asserts something instead of ranging over nothing and reporting green.
##
## GUT called the first version of that sweep *risky — did not assert*, which was the right verdict:
## a loop over an empty catalog is the "passes while proving nothing" shape `docs/TEST-AUDIT.md`
## keeps finding. **Pass C updates this list**, and until it does the test still has teeth: a module
## that starts declaring a slot fails here immediately.
const EXPECTED_SIDE_PINNED: Array[StringName] = []


## A module that wants a named slot. Built here rather than picked from the catalog so the
## derivation is tested independently of whichever modules happen to exist.
class SlottedModule:
	extends ViewModule

	var slot_name: StringName = &""

	func module_id() -> StringName:
		return &"test_slotted"

	func preferred_slot() -> StringName:
		return slot_name


func _module(slot: StringName) -> SlottedModule:
	var module := SlottedModule.new()
	module.slot_name = slot
	add_child_autofree(module)
	return module


# ---------------------------------------------------------------- the slot's own properties


func test_an_edge_pinned_slot_reports_its_edge_and_a_floating_one_does_not() -> void:
	assert_eq(ModuleSlots.edge_of(ModuleSlots.LEFT_COLUMN), ModuleSlots.EDGE_LEFT)
	assert_eq(ModuleSlots.edge_of(ModuleSlots.ACTION_ROW), ModuleSlots.EDGE_BOTTOM)
	assert_eq(ModuleSlots.edge_of(ModuleSlots.MENU_COLUMN), &"", "a centred menu floats")
	assert_eq(ModuleSlots.edge_of(&"nobody_declared_this"), &"", "an unknown slot floats")


## **Every edge counts, not just left and right.** The rule exists so a cramped player can reclaim
## space, and a bottom-pinned bar costs vertical room exactly as a left column costs horizontal —
## which is the axis a square ratio is short of.
func test_side_pinned_covers_every_edge_rather_than_only_the_sides() -> void:
	assert_true(ModuleSlots.is_side_pinned(ModuleSlots.LEFT_COLUMN))
	assert_true(ModuleSlots.is_side_pinned(ModuleSlots.TOP_LEFT))
	assert_true(ModuleSlots.is_side_pinned(ModuleSlots.ACTION_ROW), "bottom is a side too")
	assert_false(ModuleSlots.is_side_pinned(ModuleSlots.MENU_COLUMN))


# ---------------------------------------------------------------- the derivation


## **The real assertion in this file today.** A module that wants an edge-pinned slot is
## collapsible; one that floats is not; one that declares nothing is not.
func test_a_module_is_collapsible_exactly_when_its_slot_is_edge_pinned() -> void:
	assert_true(
		_module(ModuleSlots.LEFT_COLUMN).is_collapsible(), "a left column must be toggleable"
	)
	assert_true(_module(ModuleSlots.ACTION_ROW).is_collapsible())
	assert_false(_module(ModuleSlots.MENU_COLUMN).is_collapsible(), "a modal menu is not a panel")
	assert_false(_module(&"").is_collapsible(), "a module that anchors itself declares nothing")


## The flag is real state with a hook, so a module that has not implemented hiding yet degrades to
## "the toggle exists and does nothing visible" rather than crashing.
func test_the_collapsed_flag_round_trips_and_calls_its_hook() -> void:
	var module: SlottedModule = _module(ModuleSlots.LEFT_COLUMN)
	assert_false(module.collapsed, "nothing starts collapsed")
	module.collapsed = true
	assert_true(module.collapsed)
	module.collapsed = false
	assert_false(module.collapsed)


# ---------------------------------------------------------------- the sweep, and its honesty


## **The sweep Pass A's text asks for**, in the form that cannot pass vacuously: every module whose
## slot is edge-pinned must report itself collapsible, *and* the set of such modules must be exactly
## the one declared above.
func test_every_side_pinned_module_reports_itself_collapsible() -> void:
	var checked: Array[StringName] = []
	for id: StringName in ModuleCatalog.IDS:
		var module: ViewModule = ModuleCatalog.build(id)
		var slot: StringName = module.preferred_slot()
		if ModuleSlots.is_side_pinned(slot):
			checked.append(id)
			assert_true(
				module.is_collapsible(),
				"%s sits on the %s edge and cannot be turned off" % [id, slot]
			)
		module.free()
	gut.p(
		(
			"side-pinned modules: %s"
			% ("(none yet -- Pass C re-slots them)" if checked.is_empty() else ", ".join(checked))
		)
	)
	assert_eq(
		checked,
		EXPECTED_SIDE_PINNED,
		"the side-pinned set moved -- update EXPECTED_SIDE_PINNED and say so in the pass"
	)
