class_name SimulateBoutMenu
extends Control

## taskblock-14 Pass D: the minimal "Simulate Bout" setup screen — not a
## full main menu, just the one entry point (per the taskblock's own
## call: "the seed of a real main menu later without being one").
## Reachable via ControlBindings.SIMULATE_BOUT_KEY from BattleScene.
## "Start Bout" spawns the matchup through BoutSetup (Pass D's own
## headless logic, no parallel spawn path) and hands the result to a
## BoutView (Pass C) — this is the in-engine version of "build me a 2v2
## demo": a player sets it up here instead of asking CC, and CC can
## drive the exact same entry point for its own combat verification
## (taskblock-13's own weapon work is the whole reason this block
## exists now).

const PLAYSTYLES: Array[StringName] = [&"AGGRESSIVE", &"COVER_SEEKER"]
const DEFAULT_COUNT := 2

var _profiles_by_family: Dictionary = {}
var _ordered_presets: Array[BotPreset] = []

var _squad_a_dropdown: OptionButton
var _squad_b_dropdown: OptionButton
var _count_a_field: SpinBox
var _count_b_field: SpinBox
var _playstyle_a_dropdown: OptionButton
var _playstyle_b_dropdown: OptionButton
var _seed_field: LineEdit
var _error_label: Label


func _ready() -> void:
	theme = HulkTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_profiles_by_family = BoutSetup.group_by_family(DataLibrary.presets_pool())
	_build_ui()


func _build_ui() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(layout)

	var title := Label.new()
	title.text = "Simulate Bout"
	layout.add_child(title)

	var squads := HBoxContainer.new()
	layout.add_child(squads)

	var squad_a := VBoxContainer.new()
	squads.add_child(squad_a)
	var squad_a_label := Label.new()
	squad_a_label.text = "Squad A"
	squad_a.add_child(squad_a_label)
	_squad_a_dropdown = _profile_dropdown()
	squad_a.add_child(_squad_a_dropdown)
	_count_a_field = _count_field()
	squad_a.add_child(_count_a_field)
	_playstyle_a_dropdown = _playstyle_dropdown()
	squad_a.add_child(_playstyle_a_dropdown)

	var squad_b := VBoxContainer.new()
	squads.add_child(squad_b)
	var squad_b_label := Label.new()
	squad_b_label.text = "Squad B"
	squad_b.add_child(squad_b_label)
	_squad_b_dropdown = _profile_dropdown()
	squad_b.add_child(_squad_b_dropdown)
	_count_b_field = _count_field()
	squad_b.add_child(_count_b_field)
	_playstyle_b_dropdown = _playstyle_dropdown()
	squad_b.add_child(_playstyle_b_dropdown)
	# "COVER_SEEKER" — the second entry — as squad B's own default, so a
	# fresh Start Bout already shows the two playstyles facing off.
	_playstyle_b_dropdown.selected = 1

	var seed_row := HBoxContainer.new()
	layout.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "map/seed:"
	seed_row.add_child(seed_label)
	_seed_field = LineEdit.new()
	_seed_field.text = str(Time.get_ticks_usec())
	seed_row.add_child(_seed_field)

	var start_button := Button.new()
	start_button.text = "Start Bout"
	start_button.pressed.connect(_on_start_bout_pressed)
	layout.add_child(start_button)

	_error_label = Label.new()
	_error_label.modulate = HulkTheme.WARN
	layout.add_child(_error_label)


## "Profile dropdowns list the .tres profiles (grouped by
## profile_family, variants shown under their base label)." A plain
## `OptionButton` has no native group-heading support — each entry's own
## text carries the grouping instead ("Family — Variant"), keeping
## `_ordered_presets`'s index aligned with the dropdown's `selected`
## index one-to-one.
func _profile_dropdown() -> OptionButton:
	var dropdown := OptionButton.new()
	if _ordered_presets.is_empty():
		var families: Array = _profiles_by_family.keys()
		families.sort()
		for family: StringName in families:
			for preset: BotPreset in _profiles_by_family[family]:
				_ordered_presets.append(preset)
	for preset: BotPreset in _ordered_presets:
		var label: String = (
			"%s — %s" % [preset.profile_family, preset.variant_label]
			if preset.variant_label != ""
			else String(
				preset.profile_family if preset.profile_family != &"" else preset.preset_name
			)
		)
		dropdown.add_item(label)
	return dropdown


func _count_field() -> SpinBox:
	var field := SpinBox.new()
	field.min_value = 1
	field.max_value = 8
	field.value = DEFAULT_COUNT
	return field


func _playstyle_dropdown() -> OptionButton:
	var dropdown := OptionButton.new()
	for playstyle: StringName in PLAYSTYLES:
		dropdown.add_item(String(playstyle))
	return dropdown


func _selected_preset(dropdown: OptionButton) -> BotPreset:
	if dropdown.selected < 0 or dropdown.selected >= _ordered_presets.size():
		return null
	return _ordered_presets[dropdown.selected]


func _on_start_bout_pressed() -> void:
	var map_seed: int = int(_seed_field.text) if _seed_field.text.is_valid_int() else 0
	var result: Dictionary = BoutSetup.build_bout(
		_selected_preset(_squad_a_dropdown),
		int(_count_a_field.value),
		PLAYSTYLES[_playstyle_a_dropdown.selected],
		_selected_preset(_squad_b_dropdown),
		int(_count_b_field.value),
		PLAYSTYLES[_playstyle_b_dropdown.selected],
		map_seed
	)
	if result.error != "":
		_error_label.text = result.error
		return
	_error_label.text = ""
	_launch_bout(result.state, result.mission)


## Swaps in a freshly built `BoutView` as the tree's own current scene —
## `BoutView` is built entirely in code (no `.tscn` of its own, same
## "no hand-authored scene for logic" convention every other scene here
## follows), so this is a manual scene swap rather than
## `change_scene_to_file` (which needs a packed `.tscn` resource to load
## from).
func _launch_bout(state: CombatState, mission: MissionState) -> void:
	var bout_view := BoutView.new()
	get_tree().root.add_child(bout_view)
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	get_tree().current_scene = bout_view
	bout_view.setup(state, mission)
