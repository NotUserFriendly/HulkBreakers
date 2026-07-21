class_name TopLeftControls
extends HBoxContainer

## tb31 Pass A: the shared "Inject / New Battle / Watch" cluster — before
## this, `SpectatorOverlay` and `SquadControlOverlay` each built their own
## Inject button and their own Watch/Assume Control toggle (the exact
## same `battle.toggle_blue_control()` call in both, just a different
## hardcoded label depending on which direction you're toggling FROM) —
## and only `SquadControlOverlay` had New Battle at all. One construction
## path now, the same "shared, not duplicated" posture `DebugControlPanel`/
## `InspectPanel` already have. Anchored top-left — the exact corner
## `DebugControlPanel`'s own `_center_top` fix already learned to steer
## clear of (its own test file's header: a freshly opened panel used to
## spawn with no anchor at all, right on top of this row).
##
## `on_inject_pressed` stays each overlay's OWN existing handler (passed
## in, not reimplemented here) — `SquadControlOverlay` reads
## `battle.bout_injector` live at click time, `SpectatorOverlay` reads its
## own `bout_injector` field; `_build_ui()` runs BEFORE `battle.
## bout_injector` necessarily exists (it's only built inside
## `load_battle()`), so baking either one in in ADVANCE here would go
## stale. `include_new_battle` lets `SquadControlOverlay` opt in and
## `SpectatorOverlay` opt out. `watch_label` is a plain caller-supplied
## string, same as before the move ("Watch" / "Assume Control") — a pure
## relocation, not a new behavior.

## Plain, unanchored by design — `SpectatorOverlay` already has its own
## top-left-anchored `controls` row (Play/Step/Speed) and adds this as a
## plain child alongside them; `SquadControlOverlay` has no such row and
## anchors this directly, top-left, itself after construction. Anchoring
## here unconditionally would fight whichever parent container already
## owns real positioning.
var inject_button: Button
var new_battle_button: Button
var watch_button: Button


func _init() -> void:
	# docs/09 taskblock07 Pass B4's own rule: a plain wrapping container
	# gets IGNORE so a click in the gap between buttons falls through to
	# the board underneath — same convention `left_layout`/`top_right`
	# (squad_control_overlay.gd) already use. The Buttons inside keep their
	# own natural STOP (Godot's own default for Button), which is what
	# actually needs to catch a click ON one of them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(
	battle: BattleScene, on_inject_pressed: Callable, include_new_battle: bool, watch_label: String
) -> void:
	# taskblock-30/31 Pass C: `OS.is_debug_build()` is a real gate — the
	# button is never added to the tree in a release export, same as both
	# overlays already enforced independently.
	if OS.is_debug_build():
		inject_button = Button.new()
		inject_button.text = "Inject..."
		inject_button.pressed.connect(on_inject_pressed)
		add_child(inject_button)

	if include_new_battle:
		new_battle_button = Button.new()
		new_battle_button.text = "New Battle"
		new_battle_button.pressed.connect(
			func() -> void: battle.new_battle(int(Time.get_ticks_usec()))
		)
		add_child(new_battle_button)

	watch_button = Button.new()
	watch_button.text = watch_label
	watch_button.pressed.connect(battle.toggle_blue_control)
	add_child(watch_button)
