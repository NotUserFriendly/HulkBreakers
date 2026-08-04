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
