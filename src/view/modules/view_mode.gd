class_name ViewMode
extends RefCounted

## taskblock-56 Pass D: a mode is a **declaration of which modules are on** — data, not a subclass.
##
## ## What a mode actually is
##
## Four things, and none of them is behaviour:
##
## - `modules` — which `ViewModule`s to mount, **in order**. Order is meaningful: a module that
##   reads another must come after it (`unit_input` publishes the `TacticsController` every
##   display module reads at its own mount time; `tooltip` before the three modules that share its
##   `TooltipView`).
## - `chrome` — which named layout to build (`ModeChrome`). Layout belongs to the mode; behaviour
##   belongs to the module.
## - `options` — per-module pre-mount configuration, keyed by module id. The handful of fields a
##   module exposes for this (`with_button`, `include_new_battle`, `announce_passes`) are fields
##   rather than constructor arguments precisely so a mode can set them as data.
## - `turn_policy` — who drives a unit's turn. Three closed answers, so this is the one `enum` here.
##
## **The acceptance is that adding a mode is a table entry, not a file** — asserted in
## `test_view_modes.gd` by building a mode nothing in `src/` declares and mounting it.
##
## ## Why `turn_policy` is an enum and everything else is an open `StringName`
##
## CLAUDE.md's rule: enums for closed engine states, open vocabularies for content. "Who drives this
## turn" has exactly three answers and each one is a different code path in `ControlOverlay`
## (`BoutRunner` asks `wants_turn_for` and gets AI, a squad check, or a single unit). Module ids,
## chrome names and option keys are all things a later mode may invent, so none of them is closed.

## Who drives a unit's turn under this mode.
##
## - `NONE` — nobody; every unit is AI-driven. The spectator's answer, and the reason its
##   `BoutRunner` needs no injected predicate at all.
## - `HUMAN_SQUADS` — whatever `CombatState.controller_for` says. There is no silent HUMAN
##   default to fall back on; every real entry point assigns explicitly, so this reads exactly
##   what was assigned.
## - `SINGLE_UNIT` — exactly one named unit, `controlled_unit`. **Unset never means "drive
##   everything"**: that would blow through the whole battle the instant the mode installs, before a
##   caller got around to naming the unit. It means "nothing configured yet, drive nothing
##   automatically", the same fail-safe direction every other unconfigured-input case takes.
enum TurnPolicy { NONE, HUMAN_SQUADS, SINGLE_UNIT }

var id: StringName = &""
## Human-readable, for the overlay-activated/deactivated log lines. Before this pass those printed
## `overlay.get_class()`, which stops meaning anything once there is one class.
var display_name: String = ""
var chrome: StringName = &""
var modules: Array[StringName] = []
var options: Dictionary = {}
var turn_policy: TurnPolicy = TurnPolicy.NONE


## The pre-mount configuration for `module_id`, or an empty dictionary. A module with no entry gets
## its own defaults, which is what every module is written to work with.
func options_for(module_id: StringName) -> Dictionary:
	return options.get(module_id, {})


## True if this mode declares any module that queues actions against a unit.
##
## **Answered from the declaration, not from what mounted.** A mode's contract is a property of what
## it says, so it is checkable before anything is built — which is what lets
## `test_view_modes.gd` assert "the spectator mode cannot mutate state through the view" without
## constructing a battle to try it on.
func has_unit_input() -> bool:
	for module_id: StringName in modules:
		var module: ViewModule = ModuleCatalog.build(module_id)
		if module == null:
			continue
		var is_input: bool = module.is_input()
		module.free()
		if is_input:
			return true
	return false
