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
## ## The perf panel's lifetime
##
## Owned here, not by the panel that offers its toggle — the supervisor's "if the debug panel is
## closed the perf panel stays open". Both overlays already did this; the reason is preserved with
## the code.

## Called after a verb applies, once the module has done the view resync both overlays shared.
## `SquadControlOverlay` refreshed its readout header here and `SpectatorOverlay` its status line —
## the one genuine difference between the two copies, and the only thing that had to become a
## parameter.
var on_applied: Callable = Callable()

## The object `DebugControlPanel` borrows a board click from: anything carrying a `board_clicked`
## signal and an `input_capture_mode` property. `SquadControlOverlay` passed its
## `TacticsController`; `SpectatorOverlay` passed itself. A mode supplies whichever of its modules
## owns board picking, which is why this is set rather than derived.
var input_owner: Object = null

var panel: DebugControlPanel = null
var perf_panel: PerfPanel = null


func module_id() -> StringName:
	return &"debug_panel"


## Never constructed at all in a release export — the same hard gate both overlays enforced
## independently, not a hidden label.
func _mount() -> void:
	if not OS.is_debug_build():
		return
	var root: Node = context.ui_root if context.ui_root != null else self
	panel = DebugControlPanel.new()
	panel.visible = false
	panel.applied.connect(_on_debug_panel_applied)
	panel.ui_element_toggled.connect(_on_ui_element_toggled)
	root.add_child(panel)
	# taskblock-51: the performance readout. Offered by the debug panel, owned here — closing the
	# debug panel must not take the readout down with it.
	perf_panel = PerfPanel.new()
	perf_panel.visible = false
	perf_panel.stats_ticked.connect(_on_perf_stats_ticked)
	root.add_child(perf_panel)


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
func _on_debug_panel_applied(verb_id: StringName, args: Dictionary) -> void:
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
	if on_applied.is_valid():
		on_applied.call()


## The readout's own visibility, independent of the panel that offers it. The module owns the nodes;
## the debug panel only names them. A `match` rather than a lookup table because each element is a
## different node shown a different way, and an unknown id is ignored rather than crashing a debug
## surface.
func _on_ui_element_toggled(element: StringName, shown: bool) -> void:
	match element:
		DebugUiElements.PERF_PANEL:
			if perf_panel != null:
				perf_panel.visible = shown


## The panel emits; this writes. A view reaching into a `CombatState` to log would be the second
## logging path this project keeps deleting.
func _on_perf_stats_ticked(snapshot: Dictionary) -> void:
	var battle: BattleScene = context.battle if context != null else null
	if battle == null or battle.combat_state == null:
		return
	battle.combat_state.combat_log.emit(
		LogEvent.new(
			battle.combat_state.round_number,
			Enums.Phase.RESOLUTION,
			-1,
			&"fps_dump",
			snapshot,
			"perf: %s" % " | ".join(perf_panel.stats.describe())
		)
	)
