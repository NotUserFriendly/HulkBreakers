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
## **taskblock-57 Pass C: immediately left of the action bar**, which is a slot the bar publishes,
## so the log travels with the bar instead of being anchored near where it expects to find one.
##
## The older placements survive as fallbacks and that is deliberate. `slot` is still honoured for a
## host that hands over a container directly, and with neither that nor an action bar the panel
## anchors itself hard into the bottom-left corner of `ui_root` — which is where both pre-Pass-D
## overlays put it by different means, and which is what taskblock-56 Pass C's stand-alone
## acceptance mounts against. **Relative anchoring must not weaken that**, and the taskblock says
## so in its own stop-and-report list.

## Set before `mount` to place the panel inside an existing container. Overrides the declared slot;
## null falls back to the action bar's, then to the bottom-left corner.
var slot: Control = null

var panel: CombatLogPanel = null
var sink: HierarchicalUiSink = null
## The `CombatLog` this module's sink is currently attached to, so `_unmount` detaches from the one
## it actually joined rather than from whatever `context.battle` happens to hold by then. A replay
## swaps `combat_state` underneath a live overlay, which is exactly when those two differ.
var _attached_to: CombatLog = null


func module_id() -> StringName:
	return &"combat_log"


## Immediately left of the action bar. **Not edge-pinned** — it rides the bar, which is centred —
## so this module is not collapsible by the `SLOT_EDGES` derivation. It has its own affordance
## instead: the table's "minimises to a button flush against the bar", which is `CombatLogPanel`'s
## own minimize toggle and predates the collapse rule.
func preferred_slot() -> StringName:
	return ModuleSlots.ACTION_BAR_LEFT


func _mount() -> void:
	panel = CombatLogPanel.new()
	var declared: Control = context.slots.get(preferred_slot())
	if slot == null and declared != null:
		slot = declared
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
