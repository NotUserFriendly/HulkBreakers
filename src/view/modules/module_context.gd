class_name ModuleContext
extends RefCounted

## taskblock-56 Pass C: everything a `ViewModule` is allowed to know about the world it was
## mounted into.
##
## **There is deliberately no `overlay` field, and that absence is the whole design.** The
## acceptance for Pass C is that a module can be instantiated with no overlay at all — "if a module
## needs its parent, it is not a module" — and the cheapest way to make that true is to leave the
## parent out of the vocabulary entirely. A module that wants the battle asks for `battle`; one that
## wants somewhere to hang a `Control` asks for `ui_root`. Neither is a back-door to a
## `SquadControlOverlay`.
##
## **Every field is nullable, and a module must survive each of them being null.** That is not
## defensive coding for its own sake: `SquadControlOverlay._build_ui()` has always had to run before
## a battle exists (the session-start log line needs a live sink the instant it is emitted), and the
## editor mode in Pass F mounts display modules against a board with no `CombatState` behind it at
## all. A module that hard-requires `battle` would work in exactly one of the four modes.
##
## **`tactics` is how the display/input split is expressed.** `TacticsController` is the unit-input
## path; a mode that declares no input modules leaves this null, and every display module that would
## like to read a selection has to cope. That is precisely what `SpectatorOverlay` needed and could
## not get from inheritance — it wanted Squad's panels without Squad's `TacticsController`, and
## inheritance offered no way to take one and not the other.

## The shared world: board, camera, unit views, combat state, mission. Null before a battle is
## loaded, and null forever in a mode that has no battle (the editor's authoring surface).
var battle: BattleScene = null

## Where a module parents its `Control` nodes. Themed and full-rect by the time a module sees it.
##
## **A module never creates a `CanvasLayer` or applies a `Theme` itself.** Two overlays each
## building their own themed root is how the same `HulkTheme.build()` came to be called from two
## places with subtly different anchor presets; the host builds one and every module shares it.
var ui_root: Control = null

## Where a module parents non-`Control` children (`Node`/`Node3D` helpers such as `AimView` or
## `ResolutionPlayer`). Usually the host itself.
var host: Node = null

## The unit-input path, or null in a display-only mode. See the class note above.
var tactics: TacticsController = null

## Named places a module may put its `Control`s, `StringName` -> `Control`.
##
## **Layout belongs to the mode; behaviour belongs to the module.** `SquadControlOverlay._build_ui`
## built one nested container tree and handed sub-containers to a dozen panels, which is why moving
## any panel meant editing the 942-line file rather than the panel. A mode now builds whatever
## chrome it wants and publishes the resulting containers under stable names; a module asks for the
## slot it wants and **falls back to `ui_root`, or to itself, when the slot is absent**. That
## fallback is what lets the same module appear in a mode that has no such column — and what lets it
## mount against an empty context at all.
var slots: Dictionary = {}

## Modules mounted so far, by `module_id()`, so a later module can find an earlier one without
## either of them knowing which mode they are in. Ordering within a mode's declaration is therefore
## meaningful: a module that reads another must be declared after it.
##
## **This is a lookup, not a dependency injector.** A module that cannot find what it wants degrades
## — it never asserts. `QueuePanelModule` with no `tactics` simply renders nothing, the same way it
## already did for a turn with no queued actions.
var modules: Dictionary = {}


## The mounted module registered under `id`, or null. Typed as `ViewModule` at the call site.
func module(id: StringName) -> ViewModule:
	return modules.get(id)


func has_module(id: StringName) -> bool:
	return modules.has(id)


## The `Control` registered under `name`, or `fallback` (default `ui_root`) when there is none.
func slot(name: StringName, fallback: Control = null) -> Control:
	var found: Control = slots.get(name)
	if found != null:
		return found
	return fallback if fallback != null else ui_root


func set_slot(name: StringName, control: Control) -> void:
	slots[name] = control
