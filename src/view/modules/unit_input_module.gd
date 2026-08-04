class_name UnitInputModule
extends ViewModule

## taskblock-56 Pass C: the unit-input path — `TacticsController`, its signal wiring, the selection
## and highlight reactions, and the repair picker the action bar dispatches to.
##
## **This is the module `SpectatorOverlay` could not decline.** Inheriting `SquadControlOverlay`
## meant inheriting all of this; declining it meant declining every panel with it. That is the fork
## Pass C exists to remove, and it is why the display/input axis is drawn exactly at this class:
## everything here ends in `ActionQueue.enqueue`, and nothing outside it does.
##
## **A mode with no `UnitInputModule` has no `TacticsController` in its context**, so every
## display module in that mode sees `context.tactics == null` and renders its idle shape. That is
## Spectator's whole contract, expressed as a module set rather than as a subclass.
##
## ## What this module does NOT own
##
## The panels `TacticsController` feeds — stat block, aim readout, action bar, queue, pips — are
## their own modules. This one owns the controller and the reactions that are *about the units*: who
## is selected, which body previews which facing, which part is highlighted. Those touch
## `HitVolumeView` directly and belong with the input that changes them.

## Emitted after a human turn has fully resolved and animated, so the mode can advance any AI squads
## behind it. Carries the events, already played.
signal turn_resolved(events: Array[LogEvent])
## Emitted whenever the selection or the aim changed, so display modules can refresh.
signal selection_changed

var tactics: TacticsController = null
## taskblock-57 Pass F: **the dartboard, and it belongs here.**
##
## `AimView` is a `Node3D` — the window quad, its decal, the targeting line — driven entirely by
## `TacticsController.aim_changed`. It lived in `stat_panels_module` because that module also built
## the text readout beside it, which is a UI panel and a different kind of thing.
##
## Two reasons it moved. The taskblock is explicit that **the aim view and the dartboard are not UI
## modules and do not become ones — they are what the aim mode switches *to***; a module that turns
## off while aiming is exactly the wrong owner for the thing you aim with. And Pass D retires
## `stat_panels`, which would have taken the dartboard with it.
##
## Owned by the module that owns the controller it reads, which is the only pairing that cannot come
## apart.
var aim_view: AimView = null
## The repair picker, or null when none is open. Rebuilt fresh on every open, the same "free the old
## one first" convention `InspectPanel`'s own debug menu already has. **Public**, because whether a
## picker opened and what it listed is exactly what a test needs to see and the only way to see it.
var repair_menu: PopupMenu = null


func module_id() -> StringName:
	return &"unit_input"


func kind() -> Kind:
	return Kind.INPUT


## Builds the controller and publishes it on the context **before** anything else mounts, which is
## why a mode declaring this module must declare it first. Every display module reads
## `context.tactics` at its own mount time; one that mounted earlier would see null forever.
func _mount() -> void:
	tactics = TacticsController.new()
	add_child(tactics)
	if context != null:
		context.tactics = tactics
	tactics.turn_ended.connect(_on_turn_ended)
	# docs/10 taskblock06 G1: "Resolve to Here" mutates authoritative state exactly like End Turn
	# does, so the same view resync applies either way.
	tactics.queue_partially_resolved.connect(_on_turn_ended)
	tactics.selection_changed.connect(_on_selection_changed)
	# Entering or cancelling aim must refresh the previewed facing too — `aim_facing()` depends on
	# `aiming_at`, which nothing `selection_changed` covers ever touches.
	tactics.aim_changed.connect(_on_selection_changed)
	tactics.highlight_changed.connect(_on_highlight_changed)
	# tb31 Pass D: the action bar dispatches by action id, never a direct call, so a future
	# PART_PICKER action routes through here too.
	tactics.picker_action_requested.connect(_on_picker_action_requested)

	# Parented to the HOST, not to this module: it is world geometry and has to sit in the 3D scene
	# rather than under a `Node` hanging off the control surface. `context.host` is where every other
	# non-`Control` helper goes.
	aim_view = AimView.new()
	var world: Node = context.host if context != null and context.host != null else self
	world.add_child(aim_view)
	# A null readout is legal — see `AimView.set_readout`. Whichever module currently owns a text
	# panel hands one over in its own `link()`.
	aim_view.setup(tactics, null, DataLibrary.material_table())


func _unmount() -> void:
	if context != null and context.tactics == tactics:
		context.tactics = null


## Re-points the controller at whichever `CombatState`/`MissionState` is now current.
func rebind() -> void:
	if tactics == null or context == null or context.battle == null:
		return
	var battle: BattleScene = context.battle
	tactics.setup(battle.combat_state, battle.board_view, battle.camera_rig, battle.mission)


## Resolution has already mutated `combat_state` for real (docs/09) — every `HitVolumeView` rebuilds
## from the unit it already tracks, so a destroyed part disappears and a moved unit redraws at its
## new cell. `events` is then handed to playback purely as a cosmetic replay; it never re-drives the
## sim, which has already finished.
##
## **The active-turn flip is deferred until after the animation** (`BR27.07`). Bundled in with the
## mesh rebuild it flipped the indicator to the NEXT unit while THIS unit's action was still
## visibly animating — a real confirmed bug.
func _on_turn_ended(events: Array[LogEvent]) -> void:
	var battle: BattleScene = context.battle
	if battle == null:
		return
	# Only the units THIS turn's events named, never the whole board (taskblock-19 I2).
	battle.refresh_unit_views(LogPlayback.affected_unit_ids(events), false)
	_on_selection_changed()
	var resolution: ViewModule = context.module(&"resolution")
	if resolution != null:
		await (resolution as ResolutionModule).play(events)
	battle.apply_active_turn_highlight()
	turn_resolved.emit(events)
	# **Awaited here rather than connected to `turn_resolved`, and the difference is not cosmetic.**
	# `emit` does not await a coroutine handler: it runs the handler to its first `await` and then
	# detaches, so a caller awaiting this function would return with the AI batch still in flight.
	# That is exactly the bug tb45 Pass E fixed by adding an `await` to the old fire-and-forget call,
	# and routing it through a signal would have reintroduced it wearing a nicer shape.
	#
	# **And it must come after the playback above**, not before: `advance_ai_turns` fast-forwards
	# every AI turn with no animation at all, so triggering it earlier made the AI squad visibly snap
	# to its new positions while the human's own tracer had not fired yet.
	if context.advance_ai_turns.is_valid():
		await context.advance_ai_turns.call()


## docs/10 team flagging: the selected unit's ground marker brightens and no other unit's does — a
## pure overlay, never touching a part's material.
##
## The selected unit's own view renders `SelectionController.previewed_orientation()` (queued but
## unresolved facing), never the committed `unit.orientation`; while aiming, that preview is
## overridden to face the target instead. Cancelling aim makes `aim_facing()` return null again and
## the preview falls straight back to the queued orientation, with no separate "unface" step.
##
## **Only while nothing is queued to move.** Once a move is queued, the still-stationary live model
## previewing its post-move facing read as wrong — it has not gone anywhere yet — and duplicated
## what the end-position ghost already shows. The ghost alone carries the preview from then on.
func _on_selection_changed() -> void:
	var battle: BattleScene = context.battle
	if battle == null or tactics == null:
		return
	var selected: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	# tb32 Pass B: "in dartboard/aiming view only" — `aiming_at` (the TARGET) is what marks the
	# player actually aiming, not merely having a unit selected.
	battle.board_view.aim_active_unit = selected if tactics.aiming_at != null else null
	for view: HitVolumeView in battle.unit_views:
		view.set_selected(view.unit == selected)
		var target_preview: Variant = null
		if view.unit == selected and not tactics.has_queued_move():
			var facing: Variant = tactics.aim_facing()
			target_preview = facing if facing != null else tactics.selection.previewed_orientation()
		if view.preview_orientation != target_preview:
			view.preview_orientation = target_preview
			# taskblock-42 Pass B: fires on EVERY orientation preview change while aiming, and an
			# orientation change moves boxes without adding or removing any — the cheap path's best
			# case, measured rather than assumed.
			if not view.refresh_transforms():
				view.refresh()
	selection_changed.emit()


## docs/10 taskblock05 C: bidirectional hover highlight — only the selected unit's own view can
## ever have a matching part.
func _on_highlight_changed() -> void:
	var battle: BattleScene = context.battle
	if battle == null or tactics == null:
		return
	var selected: Unit = tactics.selection.selected_unit if tactics.selection != null else null
	for view: HitVolumeView in battle.unit_views:
		if view.unit == selected:
			view.highlight_part(tactics.highlighted_part)
		else:
			view.clear_highlight()


## tb31 Pass D: repair is the one PART_PICKER action today, so this is a one-arm match rather than
## something overbuilt for ids that do not exist yet.
func _on_picker_action_requested(action_id: StringName) -> void:
	if action_id == &"repair":
		open_repair_picker()


## "Prompts with all repairable damaged parts, each with its own scrap cost." A silent no-op with
## nothing selected or nothing damaged — never an empty popup. Anchored on the mouse position rather
## than a button's screen rect, the same convention `InspectPanel`'s context popup already uses.
func open_repair_picker() -> void:
	var selected: Unit = (
		tactics.selection.selected_unit if tactics != null and tactics.selection != null else null
	)
	if selected == null:
		return
	var damaged: Array[Part] = RepairResolver.repairable_parts(selected)
	if damaged.is_empty():
		return

	if repair_menu != null:
		repair_menu.queue_free()
	repair_menu = PopupMenu.new()
	add_child(repair_menu)
	var welder: Part = RepairResolver.find_operable_welder(selected)
	var mission: MissionState = tactics.selection.mission
	for i in range(damaged.size()):
		var part: Part = damaged[i]
		var cost: int = RepairResolver.scrap_cost_for(part)
		var scrap_id: StringName = RepairResolver.scrap_resource_id_for(part)
		var available: int = (
			int(mission.gathered_resources.get(scrap_id, 0)) if mission != null else 0
		)
		repair_menu.add_item("%s (%d %s)" % [part.id, cost, scrap_id], i)
		if welder == null or available < cost:
			repair_menu.set_item_disabled(repair_menu.get_item_index(i), true)
	repair_menu.id_pressed.connect(pick_repair.bind(damaged, welder))
	repair_menu.close_requested.connect(repair_menu.queue_free)
	repair_menu.id_pressed.connect(repair_menu.queue_free, CONNECT_DEFERRED)
	repair_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


## Queues the chosen repair. Public because the popup is a real `PopupMenu` whose `id_pressed` no
## headless test can emit for it — driving this directly is the only way to assert what a pick
## actually queues.
func pick_repair(id: int, damaged: Array[Part], welder: Part) -> void:
	if welder == null or id < 0 or id >= damaged.size():
		return
	tactics.selection.queue_repair(welder.id, damaged[id].id)
