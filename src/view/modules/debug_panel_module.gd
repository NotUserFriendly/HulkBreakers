class_name DebugPanelModule
extends ViewModule

## taskblock-56 Pass C: the debug control panel and the performance readout, as one module.
##
## **The most literally duplicated pair in the two overlays.** `_on_debug_panel_applied`,
## `_on_ui_element_toggled` and `_on_perf_stats_ticked` were byte-for-byte identical in
## `SquadControlOverlay` and `SpectatorOverlay`, doc comments included, and the construction blocks
## differed only in which trailing refresh they called. That is the shape the collapse exists to
## remove: two copies of one decision, kept in step by hand for twenty taskblocks.
##
## ## Why this is a DISPLAY module even though injection mutates the board
##
## The display/input axis is drawn at **unit input** — the `TacticsController` path that ends in
## `ActionQueue.enqueue`. Debug injection is not on it: it is a debug-build-only verb path reached
## through `BoutInjector`, both a spectator and a player already have it, and `SpectatorOverlay` has
## carried it since taskblock-30 while still being the view whose entire contract is "you cannot
## play this battle."
##
## Classifying it `INPUT` would therefore make Spectator an input mode and destroy the very
## distinction Pass C exists to express. **The honest reading is that debug verbs sit outside the
## classification altogether**, gated by `OS.is_debug_build()` rather than by mode — and
## taskblock-56 explicitly leaves the debug-menu overhaul for a block with the supervisor watching.
## Recorded here rather than quietly decided.
##
## ## The perf panel left, and the toggle stayed
##
## taskblock-57 Pass C gives the performance readout its own placement in the table, and a module
## declares one `preferred_slot()` — so the readout is `PerfMonitorModule` now. **The rule it was
## built under is unchanged**: closing this panel must not close the readout. What this module still
## owns is *offering* the toggle, which is what `ui_element_toggled` below re-publishes.

## Emitted after a verb applies, once this module has done the view resync both overlays shared.
## The player view refreshed its readout header here and the spectator its status line — the one
## genuine difference between the two copies, and now a signal each of them subscribes to rather
## than a callback the host had to thread through.
##
## **`BR51.21`: `events` rides along**, because a listener that wants to animate the injection
## cannot recover them any other way — the verb has already run by the time this fires. Carried
## through rather than consumed here: this module owns the view *resync*, and playing an event list
## is `ResolutionModule`'s job.
signal verb_applied(verb_id: StringName, events: Array[LogEvent])

## taskblock-57 Pass C: **a debug UI element was switched on or off**, re-published from
## `DebugControlPanel` so the module that owns the surface can consume it without either of them
## holding the other. `PerfMonitorModule` is the first subscriber; a `DebugUiElements` row added
## later needs no change here.
signal ui_element_toggled(element: StringName, shown: bool)

## The object `DebugControlPanel` borrows a board click from: anything carrying a `board_clicked`
## signal and an `input_capture_mode` property. **Resolved in `link()`, not set by the host** — the
## board module if the mode has one, otherwise the `TacticsController` the unit-input module
## published. One place decides, so two modules cannot each set it and let declaration order pick
## the winner.
var input_owner: Object = null

var panel: DebugControlPanel = null


func module_id() -> StringName:
	return &"debug_panel"


## Top edge, centred, a quarter of the 16:9 width. **Edge-pinned, so this module is collapsible**
## by the derivation in `ViewModule.is_collapsible` — which for a debug surface it already was in
## spirit: it starts hidden and a button opens it.
func preferred_slot() -> StringName:
	return ModuleSlots.DEBUG_MENU


## **`UiButtonsModule` builds this module's control by name** (the `DBG` square), so the derived
## collapse toggle would be a second debug button doing a subtly different thing — which is what the
## UI review saw as *"two debug options as well"*.
func provides_own_button() -> bool:
	return true


## Never constructed at all in a release export — the same hard gate both overlays enforced
## independently, not a hidden label.
func _mount() -> void:
	if not OS.is_debug_build():
		return
	panel = DebugControlPanel.new()
	panel.visible = false
	panel.applied.connect(_on_debug_panel_applied)
	panel.ui_element_toggled.connect(_on_ui_element_toggled)
	# **Asked of `slots` directly, NOT through `context.slot`**, and the difference is load-bearing:
	# `slot()` falls back to `ui_root`, so a mode with no battle layout would come back with a
	# non-null answer and be placed at the root's origin — which is (0,0), on top of the spectator's
	# own top-left cluster. Measured: that is exactly what the first version of this did.
	var slot: Control = context.slots.get(preferred_slot())
	if slot == null:
		var root: Node = context.ui_root if context.ui_root != null else self
		root.add_child(panel)
		return
	# **Positioned by the slot, sized by its own content.** The slot is a real rect, but the panel
	# carries a 520 px minimum width against a slot that is a quarter of the 16:9 safe width — 480
	# px at 1x — so stretching it to fill would clip the verb list rather than lay it out. The top
	# corner is what the table actually specifies ("top edge, centred"), and the budge moves this
	# slot, which moves the panel with it.
	panel.placed_by_host = true
	slot.add_child(panel)
	panel.position = Vector2.ZERO


## Board picking if the mode has it, the unit-input path otherwise, and null in a mode with
## neither — in which case `DebugControlPanel`'s own picking mode simply has nothing to borrow
## from, which is the honest answer for a surface with no board.
##
## Also wires **the one-off budge**: the menu shifts left while Inspect is open and nothing else on
## the surface budges for anything. Driven off Inspect's own open/close signals rather than polled,
## so there is no per-frame check for a thing that changes twice a minute.
func link() -> void:
	var inspect: ViewModule = context.module(&"inspect")
	if inspect != null:
		(inspect as InspectModule).opened.connect(_on_inspect_opened)
		(inspect as InspectModule).closed.connect(_on_inspect_closed)
	var picking: ViewModule = context.module(&"board_inspect")
	if picking != null:
		input_owner = picking
		return
	var input: ViewModule = context.module(&"unit_input")
	if input != null:
		input_owner = (input as UnitInputModule).tactics


func _on_inspect_opened() -> void:
	_budge(true)


func _on_inspect_closed() -> void:
	_budge(false)


## **The one module that has to re-derive after a resize.** Everything else on the surface is a
## child of a slot region and moves with it; the budge is a position read off the layout and applied
## to a region, so a resize while Inspect is open would otherwise leave the menu at its home rect,
## back under the panel it was moved out from under.
##
## Re-asked from Inspect's *current* state rather than from a remembered flag, so there is nothing
## to keep in step.
func relaid_out() -> void:
	_budge(_inspect_is_open())


func _inspect_is_open() -> bool:
	var inspect: ViewModule = context.module(&"inspect") if context != null else null
	if inspect == null:
		return false
	var inspect_panel: InspectPanel = (inspect as InspectModule).panel
	return inspect_panel != null and inspect_panel.visible


func _budge(inspect_open: bool) -> void:
	if context == null or context.ui_root == null:
		return
	ModeChrome.budge_debug_menu(context, context.ui_root.size, inspect_open)


## Hides the menu without forgetting it exists. `visible` is already how `toggle()` works, so a
## collapse and a close are the same gesture reaching the same field.
func _on_collapsed(value: bool) -> void:
	if value and panel != null:
		panel.visible = false


## Toggles the panel. A silent no-op outside a debug build, where `panel` was never constructed —
## the same posture the button's own absence already gives it.
##
## `battle.bout_injector` is read lazily, here, never cached at mount time: it only exists inside
## `load_battle()`, so anything baked in earlier would be null, and anything cached would go stale
## across the replay path's second bout. Both overlays converged on this read by different routes.
func toggle() -> void:
	if panel == null:
		return
	if panel.visible:
		panel.visible = false
		return
	if context == null or context.battle == null or context.battle.bout_injector == null:
		return
	panel.setup(context.battle.bout_injector, DeepStrike.reference_humanoid_pool(), input_owner)
	panel.visible = true


## Refreshes the way a debug HP/state mutation already does elsewhere — a forced HP-to-0 can kill a
## part the header and the views need to know about.
##
## `remove_object` on a unit is the one verb that must REMOVE a view rather than add or refresh one,
## done before `sync_unit_views()` runs so the same call never resurrects what it was just told to
## vanish.
##
## **`BR51.21`: the syncs below run BEFORE the events are re-published, and that order is load-
## bearing rather than incidental.** `ResolutionPlayer._prime` is documented as running in the same
## frame `refresh_unit_views()` did — it is what stops a unit flashing at its destination and
## jumping back — so a listener that plays the injection must be handed it *after* the resync, not
## instead of it.
func _on_debug_panel_applied(
	verb_id: StringName, args: Dictionary, events: Array[LogEvent]
) -> void:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null:
		return
	if verb_id == &"remove_object":
		var object: Dictionary = args.get("object", {})
		if object.get("kind") == Enums.HitKind.UNIT and object.get("unit") != null:
			battle.remove_unit_view(object.unit)
	battle.sync_unit_views()
	# taskblock-42 Pass E (`BR35.03`): only when the verb actually changed the board. Rebuilding
	# terrain, grid lines and every blocker to reflect a changed AP value was the whole of that
	# entry.
	if DebugVerbs.affects_board(verb_id):
		battle.sync_board_view()
	battle.refresh_unit_views()
	verb_applied.emit(verb_id, events)
	_play_injection(events)


## `BR51.21`: animates what the verb actually caused, through the same `ResolutionModule.play` both
## real resolution paths use (`PlaybackModule` with `runner.last_events`, `UnitInputModule` with its
## own). **Not a third resolution path** — one call, reached from a third place.
##
## **Here rather than in `PlaybackModule`, and that is the correction worth recording.** The
## obvious home is that module's existing `_on_verb_applied`, and it is wrong: `playback` is
## mounted by the spectator and editor modes and **is not in `PLAYER_MODULES`**, while
## `debug_panel` is in all three. Playing from there would have animated an injection while
## spectating and silently not while playing — the same one-path defect this entry is about.
##
## **`PlaybackModule.play()` would also have been the wrong call**: it resumes the *bout runner* and
## auto-plays turns, which is not what pressing Apply on a debug verb should do.
##
## An empty list returns early rather than calling `play([])`, because `ResolutionPlayer.play`
## raises its banner and waits out `RESOLVE_LEAD_IN` before it looks at the list — so an empty
## playback is a visible pause on every Apply press, not a no-op.
func _play_injection(events: Array[LogEvent]) -> void:
	if events.is_empty():
		return
	var resolution: ViewModule = context.module(&"resolution") if context != null else null
	if resolution != null:
		await (resolution as ResolutionModule).play(events)


## Re-published rather than acted on. **This module no longer owns any of the surfaces the debug
## panel names** — the performance readout moved to `PerfMonitorModule` in taskblock-57 Pass C — so
## forwarding is the whole job, and a `DebugUiElements` row added later reaches its own module
## without a branch here. That is the "adding content is data, not a code edit" rule applied to a
## debug surface.
func _on_ui_element_toggled(element: StringName, shown: bool) -> void:
	ui_element_toggled.emit(element, shown)
