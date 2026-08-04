class_name CombatLogModule
extends ViewModule

## taskblock-56 Pass C: the combat log window, as a module.
##
## **This one is the pattern's own proof, extracted last-first.** `CombatLogPanel` was already a
## plain `VBoxContainer` both overlays instantiated — the precedent Pass C generalises. What was
## still duplicated around it is everything this module now owns: constructing the panel,
## building a `HierarchicalUiSink` over its label, adding that sink to whichever `CombatLog` is
## current, re-pointing it when a new battle loads, removing it on teardown, and driving the
## once-per-frame render.
##
## Both overlays had all six of those, written twice, differing in one respect that mattered
## (`SquadControlOverlay` re-points `sink.fold.state` at the new `CombatState`; `SpectatorOverlay`
## did not, because it constructs its sink with the state already in hand and its lifetime used to
## be exactly one bout — until replay gave it a second one). **The module keeps the re-point, which
## is a strict superset**: pointing the fold at the current state is what "unit N down" in a folded
## attack summary is derived from, and doing it unconditionally cannot be wrong for a sink whose
## state has not changed.
##
## ## Placement
##
## `slot` is set before `mount` by a host that wants the panel inside one of its own containers;
## left null, the panel anchors itself hard into the bottom-left corner of `ui_root`.
##
## **Both existing overlays were aiming at the same corner by different means** —
## `SquadControlOverlay` made it the last child of a full-height left column, `SpectatorOverlay`
## anchored it explicitly, and that file's own comment records a margin being deleted so the two
## views' logs would stop sitting in visibly different places. Preserving both placements rather
## than picking one is what makes this pass an extraction: the choice belongs to the mode, in Pass
## D, not to the module.

## Set before `mount` to place the panel inside an existing container. Null anchors it bottom-left.
var slot: Control = null

var panel: CombatLogPanel = null
var sink: HierarchicalUiSink = null
## The `CombatLog` this module's sink is currently attached to, so `_unmount` detaches from the one
## it actually joined rather than from whatever `context.battle` happens to hold by then. A replay
## swaps `combat_state` underneath a live overlay, which is exactly when those two differ.
var _attached_to: CombatLog = null


func module_id() -> StringName:
	return &"combat_log"


func _mount() -> void:
	panel = CombatLogPanel.new()
	if slot != null:
		slot.add_child(panel)
	elif context.ui_root != null:
		# Flush into the bottom-left corner. `SpectatorOverlay`'s own version of this, verbatim —
		# the offset is negative because `PRESET_BOTTOM_LEFT` puts the origin on the bottom edge.
		panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		panel.position = Vector2(0.0, -CombatLogPanel.DEFAULT_HEIGHT)
		panel.size = Vector2(CombatLogPanel.DEFAULT_WIDTH, CombatLogPanel.DEFAULT_HEIGHT)
		context.ui_root.add_child(panel)
	else:
		# No host surface at all — the stand-alone case Pass C's acceptance requires. The panel is
		# still built and still owns a real label, so the sink below is real too; it simply has
		# nowhere to be drawn. A module that refused to mount here would be one that needs a parent.
		add_child(panel)
	sink = HierarchicalUiSink.new(panel.log_label, _current_state())
	rebind()


func _unmount() -> void:
	if _attached_to != null and sink != null:
		_attached_to.remove_sink(sink)
	_attached_to = null


## Points the sink at whichever `CombatLog` is current, and its fold at the matching `CombatState`.
##
## **Idempotent, deliberately.** `remove_sink` is a documented no-op on a sink that was never added,
## so the first call after `_mount` is safe and so is a re-load under an already-mounted module.
func rebind() -> void:
	var state: CombatState = _current_state()
	if state == null or sink == null:
		return
	attach_to(state.combat_log, state)


## The explicit form, for a host that has a `CombatLog` in hand before `context.battle` has been
## updated to match. `BattleScene.load_battle` needs exactly this: the session header and the
## bout-build log both fire during the load, so a sink that only attaches at the end of it misses
## every line.
func attach_to(log: CombatLog, state: CombatState) -> void:
	if sink == null or log == null:
		return
	if _attached_to != null:
		_attached_to.remove_sink(sink)
	sink.fold.state = state
	log.add_sink(sink)
	_attached_to = log


## At most one `label.text` reassignment per frame regardless of how many events landed — the whole
## point of the dirty flag, and what makes the log's deliberate verbosity affordable.
func tick(_delta: float) -> void:
	if sink != null:
		sink.render_if_dirty()


func _current_state() -> CombatState:
	return context.battle.combat_state if context != null and context.battle != null else null
