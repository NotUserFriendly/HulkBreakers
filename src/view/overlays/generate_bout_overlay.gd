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
##
## taskblock-16 Pass E: each team used to be one profile dropdown plus a
## count SpinBox (one profile repeated N times). Now each team is an
## arbitrarily expanding LIST of per-unit entries — no count field at
## all, "add/remove IS the count."
##
## taskblock-17 Pass D: each entry row widened from `[Bot ▾][-]` to
## `[Bot ▾][AI ▾][D][-]` — playstyle moved from one shared per-team
## dropdown to a per-bot one on each row (`BoutSetup.build_bout` already
## takes a `BoutRosterEntry` per bot, profile + that bot's own
## playstyle), and `[D]` duplicates the row (same profile + playstyle)
## right below itself, the fast way to build "4 of these, 1 of those."

const PLAYSTYLES: Array[StringName] = [&"AGGRESSIVE", &"COVER_SEEKER", &"SKIRMISHER", &"MARKSMAN"]
## Flagged UX default, not a spec literal: a completely empty menu would
## still work (Start Bout is rejected-not-crashed on an empty roster,
## same as always), but starting both teams pre-populated keeps "open the
## menu, hit Start Bout" a one-click smoke test the way the old
## profile+count default was — add/remove is still the ONLY way to change
## the roster afterward, this only seeds its starting contents. Squad B
## starts on COVER_SEEKER (PLAYSTYLES[1]), squad A on the default
## AGGRESSIVE, so a fresh Start Bout already shows two playstyles facing
## off, the same as the old per-team default did.
const DEFAULT_STARTING_COUNT := 2
## "min 5 rows shown for readability" — real entries plus the trailing
## Add row plus blank spacer rows, never fewer than this many rows tall.
const MIN_VISIBLE_ROWS := 5
const ADD_LABEL := "+ Add"
const ROW_MIN_HEIGHT := 32.0

var battle: BattleScene
var _profiles_by_family: Dictionary = {}
var _ordered_presets: Array[BotPreset] = []

var _roster_a: Array[BoutRosterEntry] = []
var _roster_b: Array[BoutRosterEntry] = []
var _rows_a: VBoxContainer
var _rows_b: VBoxContainer
var _seed_field: LineEdit
var _error_label: Label


func setup(p_battle: BattleScene) -> void:
	battle = p_battle
	_profiles_by_family = BoutSetup.group_by_family(DataLibrary.presets_pool())
	_build_ordered_presets()
	for i in range(DEFAULT_STARTING_COUNT):
		if not _ordered_presets.is_empty():
			_roster_a.append(BoutRosterEntry.new(_ordered_presets[0], PLAYSTYLES[0]))
			_roster_b.append(BoutRosterEntry.new(_ordered_presets[0], PLAYSTYLES[1]))
	_build_ui()


func _build_ordered_presets() -> void:
	var families: Array = _profiles_by_family.keys()
	families.sort()
	for family: StringName in families:
		for preset: BotPreset in _profiles_by_family[family]:
			_ordered_presets.append(preset)


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
	_rows_a = VBoxContainer.new()
	squad_a.add_child(_rows_a)

	var squad_b := VBoxContainer.new()
	squads.add_child(squad_b)
	var squad_b_label := Label.new()
	squad_b_label.text = "Squad B"
	squad_b.add_child(squad_b_label)
	_rows_b = VBoxContainer.new()
	squad_b.add_child(_rows_b)

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

	_rebuild_team(0)
	_rebuild_team(1)


func _roster(squad_id: int) -> Array[BoutRosterEntry]:
	return _roster_a if squad_id == 0 else _roster_b


func _rows(squad_id: int) -> VBoxContainer:
	return _rows_a if squad_id == 0 else _rows_b


## "Adding appends a unit" — always to the end of that team's own list,
## starting on the default playstyle (its own row's [AI ▾] can change it
## afterward, same as any other entry's).
func _add_to_squad(squad_id: int, preset: BotPreset) -> void:
	_roster(squad_id).append(BoutRosterEntry.new(preset, PLAYSTYLES[0]))
	_rebuild_team(squad_id)


## "Removing drops exactly that entry" — every other entry keeps its own
## position; nothing shifts identity, only index.
func _remove_from_squad(squad_id: int, index: int) -> void:
	_roster(squad_id).remove_at(index)
	_rebuild_team(squad_id)


## "Clicking a name replaces it" — same slot, new profile; that entry's
## own already-chosen playstyle is untouched.
func _replace_profile_in_squad(squad_id: int, index: int, preset: BotPreset) -> void:
	_roster(squad_id)[index].profile = preset
	_rebuild_team(squad_id)


## The `[AI ▾]` half of a row: same slot, new playstyle, profile untouched.
func _replace_playstyle_in_squad(squad_id: int, index: int, playstyle: StringName) -> void:
	_roster(squad_id)[index].playstyle = playstyle
	_rebuild_team(squad_id)


## "`[D]` — duplicate. Appends a copy of that entry (same profile + same
## playstyle) below it." — inserted right after its own index, not just
## tacked onto the end of the list, so "duplicate" reads as literally
## "one more row like this one, right here."
func _duplicate_in_squad(squad_id: int, index: int) -> void:
	var source: BoutRosterEntry = _roster(squad_id)[index]
	_roster(squad_id).insert(index + 1, BoutRosterEntry.new(source.profile, source.playstyle))
	_rebuild_team(squad_id)


func _preset_label(preset: BotPreset) -> String:
	return (
		"%s — %s" % [preset.profile_family, preset.variant_label]
		if preset.variant_label != ""
		else String(preset.profile_family if preset.profile_family != &"" else preset.preset_name)
	)


## One row per already-added roster entry: `[Bot ▾]` (pre-selected to the
## entry's own current profile — picking a different item REPLACES it),
## `[AI ▾]` (same, for playstyle), `[D]` to duplicate, `[-]` to remove.
func _entry_row(squad_id: int, index: int) -> HBoxContainer:
	var entry: BoutRosterEntry = _roster(squad_id)[index]
	var row := HBoxContainer.new()

	var profile_dropdown := OptionButton.new()
	for preset: BotPreset in _ordered_presets:
		profile_dropdown.add_item(_preset_label(preset))
	profile_dropdown.selected = _ordered_presets.find(entry.profile)
	profile_dropdown.item_selected.connect(
		func(item_index: int) -> void:
			_replace_profile_in_squad(squad_id, index, _ordered_presets[item_index])
	)
	row.add_child(profile_dropdown)

	var playstyle_dropdown := OptionButton.new()
	for playstyle: StringName in PLAYSTYLES:
		playstyle_dropdown.add_item(String(playstyle))
	playstyle_dropdown.selected = PLAYSTYLES.find(entry.playstyle)
	playstyle_dropdown.item_selected.connect(
		func(item_index: int) -> void:
			_replace_playstyle_in_squad(squad_id, index, PLAYSTYLES[item_index])
	)
	row.add_child(playstyle_dropdown)

	var duplicate_button := Button.new()
	duplicate_button.text = "D"
	duplicate_button.pressed.connect(_duplicate_in_squad.bind(squad_id, index))
	row.add_child(duplicate_button)

	var remove_button := Button.new()
	remove_button.text = "-"
	remove_button.pressed.connect(_remove_from_squad.bind(squad_id, index))
	row.add_child(remove_button)

	return row


## Item 0 is a disabled placeholder carrying the "+ Add" label itself —
## picking any REAL item (index > 0) appends that preset and the row
## rebuilds fresh (a new, once-again-unselected Add row at the bottom).
func _add_row(squad_id: int) -> OptionButton:
	var dropdown := OptionButton.new()
	dropdown.add_item(ADD_LABEL)
	dropdown.set_item_disabled(0, true)
	for preset: BotPreset in _ordered_presets:
		dropdown.add_item(_preset_label(preset))
	dropdown.selected = 0
	dropdown.item_selected.connect(
		func(item_index: int) -> void:
			if item_index > 0:
				_add_to_squad(squad_id, _ordered_presets[item_index - 1])
	)
	return dropdown


func _rebuild_team(squad_id: int) -> void:
	var rows: VBoxContainer = _rows(squad_id)
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()

	var roster: Array[BoutRosterEntry] = _roster(squad_id)
	for index in range(roster.size()):
		rows.add_child(_entry_row(squad_id, index))
	rows.add_child(_add_row(squad_id))

	var padding: int = maxi(0, MIN_VISIBLE_ROWS - (roster.size() + 1))
	for i in range(padding):
		var spacer := Control.new()
		spacer.custom_minimum_size.y = ROW_MIN_HEIGHT
		rows.add_child(spacer)


func _on_start_bout_pressed() -> void:
	var map_seed: int = int(_seed_field.text) if _seed_field.text.is_valid_int() else 0
	var result: Dictionary = BoutSetup.build_bout(_roster_a, _roster_b, map_seed)
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
