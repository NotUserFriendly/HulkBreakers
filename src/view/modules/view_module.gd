class_name ViewModule
extends Node

## taskblock-56 Pass C: one toggleable piece of the control surface.
##
## ## Why this exists
##
## `SquadControlOverlay` was 942 lines and `SpectatorOverlay` 718, and they duplicated each other
## because Spectator could not inherit Squad without dragging in `TacticsController` and the whole
## unit-input path. `SingleUnitOverlay` is 54 lines *because* inheritance was available to it —
## it wanted everything Squad had. **Inheritance forced the fork**: it offers all-or-nothing, and
## Spectator's requirement was "all of the panels, none of the input."
##
## **The precedent already worked.** `CombatLogPanel` is a plain `VBoxContainer` that both overlays
## instantiate. It never joined the class hierarchy and never needed to. Every module here is that
## pattern applied to the rest of the surface.
##
## ## Two axes, not one
##
## A module is a **display** module or an **input** module, and the two toggle independently. That
## separation is the thing inheritance could not express.
##
## - `DISPLAY` — reads the simulation and draws it. May be interactive (the inspect panel opens on
##   a click) but **cannot queue an action against a unit**.
## - `INPUT` — accepts player input that queues actions through `TacticsController`, i.e. the path
##   that ends in `ActionQueue.enqueue`.
##
## **The line is drawn at unit input specifically, not at "does anything happen when I click".**
## Spectator's contract is that a spectator cannot play the battle, and that is exactly the
## `TacticsController` path. Debug injection is deliberately outside this classification: it is a
## debug-build-only verb path that both a spectator and a player already have, it does not go
## through the view's input path, and taskblock-56 explicitly leaves the debug-menu overhaul alone.
## `DebugPanelModule` is therefore `DISPLAY`, and its own header says why in more detail.
##
## ## The contract
##
## A module is constructed with no arguments, mounted once against a `ModuleContext`, and unmounted
## once. **It must be mountable against a context whose every field is null** — that is Pass C's
## stated acceptance, and `test_view_modules_stand_alone.gd` asserts it for every module in
## `ModuleCatalog`. A module that needs its parent is not a module.
##
## Nothing here is abstract-with-a-crash: every hook has a working default, so a module overrides
## only what it actually does. A module that is pure construction overrides `_mount` alone.

enum Kind { DISPLAY, INPUT }

## The context this module was mounted against. Null before `mount`, and again after `unmount`.
var context: ModuleContext = null

## taskblock-57 Pass A: whether this module is currently hidden by its own collapse toggle.
## Meaningless on a module that is not collapsible, and left false there. See `is_collapsible()`.
var collapsed: bool = false:
	set(value):
		collapsed = value
		_on_collapsed(value)


## Stable identity, used as the key in a mode's declaration and in `ModuleContext.modules`. Every
## concrete module overrides this; the base value is deliberately empty rather than a guessed
## default, so a module that forgot to declare one fails `ModuleCatalog`'s own registry test rather
## than silently colliding with another.
func module_id() -> StringName:
	return &""


## `DISPLAY` unless the module queues actions against a unit. See the class note.
func kind() -> Kind:
	return Kind.DISPLAY


func is_input() -> bool:
	return kind() == Kind.INPUT


## taskblock-57 Pass A: **which `ModuleSlots` name this module wants to live in**, or `&""` for one
## that anchors itself.
##
## Declared rather than only passed inline to `context.slot(...)` at mount time, because two things
## need to know it *before* anything is built: whether the module is collapsible (below), and — from
## Pass B — whether it pins against the action bar rather than the screen. A mount-time argument
## cannot answer either without mounting.
##
## A module may still pass a different name to `context.slot()`; this is the declaration, and
## `_mount` remains free. They agree for every module that has been through Pass C.
func preferred_slot() -> StringName:
	return &""


## True if this module must offer a way to be turned off.
##
## **Derived from the slot, not carried per module.** taskblock-57 A2's rule is that everything
## pinned to a side is collapsible or off by default, so a square-ratio player toggles a panel
## instead of being forced to shrink the whole UI to play. That is a fact about *placement*, and
## placement belongs to the slot — so a module answers it by asking which slot it wants rather than
## by each one remembering a flag that can drift from where it actually sits.
func is_collapsible() -> bool:
	return ModuleSlots.is_side_pinned(preferred_slot())


## Override to actually hide something. The default does nothing, so a module that declares itself
## collapsible and has not implemented it yet degrades to "the toggle exists and does nothing
## visible" rather than crashing — and the test for the toggle is about the flag, not the pixels.
func _on_collapsed(_value: bool) -> void:
	pass


## Applies a mode's pre-mount `options` for this module by setting properties directly.
##
## **Deliberately generic.** A mode is data, so adding an option must be a table entry rather than a
## branch here — the same standing rule that keeps socket types and AP costs out of code. The keys
## are the module's own public field names; an unknown key sets nothing, which is the same
## degrade-quietly posture the rest of the module system has.
func configure(options: Dictionary) -> void:
	for key: StringName in options:
		set(key, options[key])


## Builds this module against `p_context` and registers it there. Idempotent guard included: a
## double mount is a host bug, and returning quietly beats building a second copy of every panel.
func mount(p_context: ModuleContext) -> void:
	if context != null:
		return
	context = p_context
	if context != null:
		context.modules[module_id()] = self
	_mount()


## Tears down whatever `_mount` built. The `Node` children a module added to itself are freed with
## it by the engine; `_unmount` is for the things that outlive it — a sink added to a `CombatLog`,
## a signal connected to something the module does not own.
func unmount() -> void:
	if context == null:
		return
	_unmount()
	if context.modules.get(module_id()) == self:
		context.modules.erase(module_id())
	context = null


## The build. Override this.
func _mount() -> void:
	pass


## The teardown. Override this only if `_mount` reached outside the module.
func _unmount() -> void:
	pass


## taskblock-57 Pass B: **slots this module publishes for other modules to mount into**, as
## `StringName` -> `Control`. Empty for the overwhelming majority.
##
## ## A module may be a slot provider, and that is deliberately general
##
## Four surfaces pin relative to the **action bar** rather than to the screen — the turn-order
## panel to its right, the combat log to its left, unit resources and the UI buttons above it. Until
## now every slot came from `ModeChrome`, which builds against the screen and knows nothing about
## where a module ended up.
##
## **The action bar is not special-cased**, and the taskblock is explicit about that: *"Keep it
## general; do not special-case the action bar. Anything else may want to publish later."* So this
## is a hook on `ViewModule`, the host publishes whatever any module returns, and the action bar is
## simply the first module to use it.
##
## ## Ordering is the existing rule, not a new one
##
## The host publishes a module's slots immediately after mounting it, so **a provider must be
## declared before its dependants** — the same constraint that already governs `unit_input`
## publishing the `TacticsController` every display module reads at its own mount time. Nothing new
## to remember.
##
## ## A dependant must still stand alone
##
## `ModuleContext.slot` falls back to `ui_root`, or to the module itself, when a slot is absent — so
## a mode that declares the combat log and no action bar gets a combat log that mounts somewhere
## sensible rather than failing. **taskblock-56 Pass C's acceptance is not weakened by relative
## anchoring**, and `test_view_modules_stand_alone.gd` still mounts every module against a context
## with no slots at all.
func published_slots() -> Dictionary:
	return {}


## Wires this module to the other modules in its mode. Called on every module **after all of them
## have mounted**, so the connections a module wants do not constrain the declaration order the way
## its mount-time reads do.
##
## Before this pass the equivalent wiring lived in each overlay's own `_wire_modules`, which is the
## last thing that would have had to be written per-mode. A module knowing how to link to whatever
## it
## finds is what makes a new mode a table entry.
func link() -> void:
	pass


## Re-points this module at whatever `context.battle` now holds, without rebuilding anything.
##
## **This is the half of `setup` that is about the bout rather than about the controls**, and it is
## a first-class hook because getting it wrong has bitten twice already: `SpectatorOverlay` had to
## grow `rebind_to_battle()` after calling `setup()` on a replay destroyed the panel that was
## iterating the run, and `SquadControlOverlay._on_battle_loaded` re-points four separate things by
## hand. A host calls this on every `battle_loaded`; a module that has nothing to re-point ignores
## it.
func rebind() -> void:
	pass


## The per-frame draw tick, called by the host rather than by the engine.
##
## **Deliberately not `_process`.** A module is a `Node`, so `_process` would fire on every module
## in the tree whether or not the host wanted it, and the whole point of `UiLogSink.render_if_dirty`
## is that exactly one label assignment happens per frame no matter how many events landed. The host
## owning the tick keeps that property visible in one place.
func tick(_delta: float) -> void:
	pass
