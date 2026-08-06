extends GutTest

## taskblock-57 Pass A — **a slot's properties, and the collapsible rule derived from them.**
##
## The rule: *everything pinned to a side is collapsible or off by default, so a square-ratio player
## is never forced to shrink the UI to play.* A module answers that about itself by asking which
## slot it wants, rather than each one carrying a flag that can drift from where it actually sits.
##
## ## Written to be non-vacuous before it had anything to sweep
##
## Pass A's own test reads "every side-pinned module reports itself collapsible", and at Pass A no
## module declared a `preferred_slot()` at all — so iterating `ModuleCatalog` would have ranged over
## an empty set and passed while proving nothing, which is the failure shape `docs/TEST-AUDIT.md`
## keeps finding. So the file was built in three parts: the **derivation** tested against synthetic
## modules, the **current state** pinned explicitly, and the **sweep** written but asserting against
## that pin.
##
## **It worked.** Pass C declared the first slots and this file went red on the pin rather than
## quietly going green on an empty loop, which is the whole reason the pin exists.

## Every module that declares an edge-pinned slot, in `ModuleCatalog.IDS` order. **Pinned as a list
## rather than left implicit** so the sweep below always asserts something instead of ranging over
## nothing and reporting green — GUT called the first version of that sweep *risky — did not
## assert*, which was the right verdict.
##
## **taskblock-57 Pass C filled it, and it fired to say so.** Three modules, and each is here for a
## reason worth reading rather than because it happened to land on an edge:
##
## - `debug_panel` — `DEBUG_MENU`, top. Already off by default; the toggle is now explicit.
## - `inspect` — `INSPECT_PANEL`, right. The largest surface on the screen and the one a cramped
##   ratio most needs to reclaim.
## - `inspect_viewer` — `INSPECT_VIEWER`, left. Added by Pass C3, which split the 3D view out of
##   `InspectPanel` so it could sit in the table's own top-left row. The largest 3D surface on the
##   screen, and the one a cramped ratio most wants to fold away.
## - `action_bar` — `ACTION_ROW`, bottom. **This one reverses an earlier call in the same block**
##   ("the action bar and its four satellites are not collapsible"). That decision was already
##   inconsistent with the data shipped beside it: `SLOT_EDGES` carries `ACTION_ROW: EDGE_BOTTOM`,
##   and the test below pins "bottom is a side too". Nothing surfaced the contradiction while no
##   module declared a slot. The consistent reading — every edge-pinned slot, no exceptions — is
##   taken, and it costs nothing: the bar is not collapsed by default.
##
## The four action-bar satellites are **absent and should stay absent**: they ride the bar, which is
## centred, so they are not edge-pinned and fold with it rather than each carrying its own toggle.
##
## **taskblock-57 Pass G1 adds `spectator_bar` and `editor_bar`**, and they are not two new
## decisions. All three bars share `ACTION_ROW` — that is what "three action bars, not one with
## three contents" means structurally — so the derivation that made the player's bar collapsible
## makes theirs collapsible, from `BarModule.preferred_slot()`, with nothing declared per bar. A
## fourth mode's bar joins this list the day it is written, which is the property worth having.
##
## **taskblock-57 Pass G2 adds `editor`**, for the same derivation and not a fourth decision. G2
## puts the section-details panel in `INSPECT_VIEWER` — *"section details go where the Inspect
## Viewer sits, with a toggle in UI buttons"* — and that slot is left-edge-pinned, so it reports
## itself collapsible and `UiButtonsModule` builds the toggle by sweeping for exactly that. **The
## taskblock asked for a toggle and the answer was a `preferred_slot()`**, with no line in either
## file naming the other.
## **taskblock-58 Pass E adds `parts_list`, and it is the same derivation a fourth time.** The
## taskblock asks for the parts list to be *"toggleable from UI buttons"*; it takes
## `ModuleSlots.INSPECT_PANEL` — the slot it shares with `inspect`, because while placing you
## cannot be selecting — and that slot is edge-pinned, so it reports itself collapsible and
## `UiButtonsModule` builds the toggle by sweeping for exactly that. **Nothing in either file names
## the other**, which is the property this list exists to keep visible: asking for a toggle is
## still answered by a `preferred_slot()`.
const EXPECTED_SIDE_PINNED: Array[StringName] = [
	&"debug_panel",
	&"inspect",
	&"action_bar",
	&"editor",
	&"inspect_viewer",
	&"spectator_bar",
	&"editor_bar",
	&"parts_list",
]


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
	assert_true(ModuleSlots.is_side_pinned(ModuleSlots.DEBUG_MENU), "the top is a side too")
	assert_true(ModuleSlots.is_side_pinned(ModuleSlots.ACTION_ROW), "bottom is a side too")
	assert_false(ModuleSlots.is_side_pinned(ModuleSlots.MENU_COLUMN))


## taskblock-57 Pass G1: **a slot two providers publish at two different edges has no edge**, and
## the table says so by leaving it out rather than by picking one. `PACING_ROW` is top-left under
## `TOP_LEFT_ROWS` and bottom-centre inside `SpectatorBarModule`'s bar; anything mounted into it
## folds with whatever it is riding.
func test_the_pacing_row_claims_no_edge_because_two_providers_place_it_differently() -> void:
	assert_false(
		ModuleSlots.is_side_pinned(ModuleSlots.PACING_ROW),
		"the pacing row is published at two different edges -- it cannot claim one"
	)
	assert_false(ModuleSlots.is_side_pinned(ModuleSlots.TUNABLES))


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
