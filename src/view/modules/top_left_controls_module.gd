class_name TopLeftControlsModule
extends ViewModule

## taskblock-56 Pass C: the shared Inject / New Battle / Watch cluster.
##
## `TopLeftControls` was already one class both overlays instantiated — tb31 Pass A's own collapse,
## and the second working precedent for Pass C after `CombatLogPanel`. What is added here is only
## the wiring around it that each overlay still wrote separately: where it is anchored, which
## trailing arguments it gets, and which handler the Inject button calls.
##
## **Anchoring differs by mode and that is why it stays a parameter.** `SpectatorOverlay` already
## had a top-left row of its own (Play/Step/Speed) and added this as a plain child alongside;
## `SquadControlOverlay` had no such row and anchored the cluster itself. Anchoring unconditionally
## here would fight whichever parent already owns real positioning — `TopLeftControls`' own header
## says so, and it stays true.
##
## ## taskblock-57 Pass G1: this cluster is in the spectator's bar now, and this file did not change
##
## Pass D's last unlanded line was *"`top_left_controls_module` → the spectator action bar"*, which
## had nowhere to go until `SpectatorBarModule` existed. It exists, it publishes `PACING_ROW`, and
## the move cost this module one renamed constant. **The name is now historical**: the cluster is
## bottom-centre in every mode that still declares it. The id is kept because it is what a mode
## table, a catalog row and several tests name it by, and renaming an identity to describe a
## position is what put this module in the wrong place to begin with.

const ANCHOR_MARGIN := Vector2(16, 16)

## Set before `mount`. `SquadControlOverlay` had New Battle; a spectated bout has no "New Battle"
## concept of its own and opted out.
var include_new_battle: bool = false
## "Watch" from the player view, "Assume Control" from the spectator — the same
## `battle.toggle_blue_control()` either way, only the label says which direction you are going.
var watch_label: String = "Watch"

var controls: TopLeftControls = null


func module_id() -> StringName:
	return &"top_left_controls"


func _mount() -> void:
	controls = TopLeftControls.new()
	var row: Control = context.slot(ModuleSlots.PACING_ROW, null)
	if row != null:
		row.add_child(controls)
	elif context.ui_root != null:
		# No pre-existing row — anchor directly at the top-left corner, the one
		# `DebugControlPanel._center_top` already steers clear of.
		controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
		controls.position = ANCHOR_MARGIN
		context.ui_root.add_child(controls)
	else:
		add_child(controls)
	if context.battle != null:
		controls.setup(context.battle, _on_inject_pressed, include_new_battle, watch_label)


func new_battle_button() -> Button:
	return controls.new_battle_button if controls != null else null


func watch_button() -> Button:
	return controls.watch_button if controls != null else null


func inject_button() -> Button:
	return controls.inject_button if controls != null else null


## Routed through the debug module rather than reimplemented, so the two overlays' identical
## "toggle the panel, setting it up lazily" handlers become one.
func _on_inject_pressed() -> void:
	var module: ViewModule = context.module(&"debug_panel") if context != null else null
	if module != null:
		(module as DebugPanelModule).toggle()
