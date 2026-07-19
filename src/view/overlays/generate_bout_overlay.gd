class_name GenerateBoutOverlay
extends ControlOverlay

## taskblock-14 Pass D / taskblock-15 Pass A: "setup — the Simulate Bout
## menu, then hands off to spectator." Everything `SimulateBoutMenu` used
## to own as its own scene folds in here — reachable via
## `ControlBindings.SIMULATE_BOUT_KEY` from `BattleScene`
## (`battle.set_overlay(GenerateBoutOverlay.new())`, no scene swap left to
## do it). This is pre-battle SETUP, not a peer control scheme (A2): it
## never drives a unit's turn (`wants_turn_for` stays the base class's own
## always-false default, and nothing here calls `advance_ai_turns`) — Start
## Bout builds the matchup through `BoutSetup` (taskblock-14 Pass D's own
## headless logic, no parallel spawn path), installs it into the shared
## world via `battle.load_battle()`, and REPLACES this overlay with a
## `SpectatorOverlay` — a transition, not a persistent mode.

const PLAYSTYLES: Array[StringName] = [&"AGGRESSIVE", &"COVER_SEEKER"]
const DEFAULT_COUNT := 2

var battle: BattleScene
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


func setup(p_battle: BattleScene) -> void:
	battle = p_battle
	_profiles_by_family = BoutSetup.group_by_family(DataLibrary.presets_pool())
	_build_ui()


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var theme_root := Control.new()
	theme_root.theme = HulkTheme.build()
	theme_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(theme_root)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	theme_root.add_child(layout)

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


## "Profile dropdowns list the .tres profiles (grouped by profile_family,
## variants shown under their base label)." A plain `OptionButton` has no
## native group-heading support — each entry's own text carries the
## grouping instead ("Family — Variant"), keeping `_ordered_presets`'s
## index aligned with the dropdown's `selected` index one-to-one.
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
	# A2: "hands off to spectator" — battle.load_battle() FIRST (this
	# overlay is still the active one and does not react to battle_loaded,
	# so no premature auto-advance happens), THEN swap the overlay itself —
	# SpectatorOverlay.setup() reads battle.combat_state/mission fresh, no
	# stale reference possible.
	battle.load_battle(result.state, result.mission)
	battle.set_overlay(SpectatorOverlay.new())
