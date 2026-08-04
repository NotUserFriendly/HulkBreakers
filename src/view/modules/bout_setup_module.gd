class_name BoutSetupModule
extends ViewModule

## taskblock-56 Pass D: the Simulate Bout roster menu, moved out of `GenerateBoutOverlay` verbatim.
##
## Pre-battle SETUP, not a peer control scheme: it never drives a unit's turn. **Start Bout** builds
## the matchup through `BoutSetup` (headless logic, no parallel spawn path), installs it into the
## shared world via `battle.load_battle()`, and asks the host to swap to the spectator mode — a
## transition, not a persistent mode.
##
## **Each team is an arbitrarily expanding LIST of per-unit entries.** There is no count field:
## "add/remove IS the count". A row is `[Bot ▾][AI ▾][D][-]` — the AI choice is per-bot, not
## per-team, because `BoutSetup.build_bout` takes a `BoutRosterEntry` per bot, and `[D]` duplicates
## the row in place, which is the fast way to build "4 of these, 1 of those".
##
## Display: it queues nothing against a unit. What it does is build a bout and hand it over.

## Emitted once a bout has been built and loaded, carrying whether Squad A should be human-driven.
## The host owns the mode swap; this module owns the menu.
signal bout_started(assume_control: bool)

## Flagged UX default, not a spec literal. A completely empty menu still works — Start Bout is
## rejected-not-crashed on an empty roster — but starting both teams pre-populated keeps "open the
## menu, hit Start Bout" a one-click smoke test. Add/remove remains the ONLY way to change the
## roster afterward; this seeds its starting contents.
##
## **The pairing rationale changed with taskblock-46 Pass E.** These used to be range-matched —
## MARKSMAN on the sniper, SKIRMISHER on the chaingun — because a playstyle carried a preferred
## range. It does not any more: standoff is scored against the unit's OWN weapon range, so every
## profile holds the range its gun wants without being told. Pairing by weapon would be pairing on a
## property the profile no longer has. What is left to spread is temperament, so the default spreads
## that instead, identically on both teams.
const DEFAULT_ROSTER: Array[Array] = [
	[&"combat_tester_chaingun", &"cautious"],
	[&"combat_tester_sniper_rifle", &"defensive"],
	[&"combat_tester_pump_shotgun", &"aggressive"],
]
## Real entries plus the trailing Add row plus blank spacers, never fewer than this many rows tall.
const MIN_VISIBLE_ROWS := 5
const ADD_LABEL := "+ Add"
const ROW_MIN_HEIGHT := 32.0

## Exposed as real references (never re-found by node path) so both the centering logic and the
## tests read them back directly.
var layout: VBoxContainer = null
var seed_field: LineEdit = null
var error_label: Label = null
var assume_control_checkbox: CheckBox = null

var _profiles_by_family: Dictionary = {}
var _ordered_presets: Array[BotPreset] = []
var _roster_a: Array[BoutRosterEntry] = []
var _roster_b: Array[BoutRosterEntry] = []
var _rows_a: VBoxContainer = null
var _rows_b: VBoxContainer = null


func module_id() -> StringName:
	return &"bout_setup"


func _mount() -> void:
	_profiles_by_family = BoutSetup.group_by_family(DataLibrary.presets_pool())
	_build_ordered_presets()
	_seed_default_roster(_roster_a)
	_seed_default_roster(_roster_b)
	_build_ui()


## The rosters, for a caller that wants to inspect them.
func roster(squad_id: int) -> Array[BoutRosterEntry]:
	return _roster_a if squad_id == 0 else _roster_b


## Replaces a squad's roster wholesale. **Does not rebuild the rows** — a caller that wants the
## menu redrawn drives whichever real verb it is testing, exactly as a click would, and that verb
## rebuilds on its own. Seeding the model and then asserting what a verb did to it is the point.
func set_roster(squad_id: int, entries: Array[BoutRosterEntry]) -> void:
	if squad_id == 0:
		_roster_a = entries
	else:
		_roster_b = entries


## Builds the bout and loads it, or writes the refusal into the error label and does nothing else.
##
## **`load_battle()` first, then the swap.** This module is still the active surface and does not
## react to `battle_loaded`, so no premature auto-advance happens; the spectator mode then reads
## `combat_state`/`mission` fresh, with no stale reference possible.
func start_bout() -> void:
	var map_seed: int = int(seed_field.text) if seed_field.text.is_valid_int() else 0
	var result: Dictionary = BoutSetup.build_bout(_roster_a, _roster_b, map_seed)
	if result.error != "":
		error_label.text = result.error
		return
	error_label.text = ""
	var battle: BattleScene = context.battle
	if battle == null:
		return
	battle.load_battle(result.state, result.mission)
	bout_started.emit(assume_control_checkbox.button_pressed)


## Missing presets (a data set without the Combat Tester bots) are skipped, never crashed on.
##
## Looks the preset up in `_ordered_presets` rather than calling `DataLibrary.get_preset()` again:
## every accessor hands back a fresh `.duplicate(true)`, so a separately-fetched instance is never
## reference-equal to the one the dropdown searches for — that mismatch left `.selected` at -1
## (nothing found, nothing shown) even though the entry's DATA was correct.
func _seed_default_roster(into: Array[BoutRosterEntry]) -> void:
	for pair: Array in DEFAULT_ROSTER:
		var preset: BotPreset = _find_ordered_preset(pair[0])
		if preset != null:
			into.append(BoutRosterEntry.new(preset, pair[1]))


func _find_ordered_preset(preset_name: StringName) -> BotPreset:
	for preset: BotPreset in _ordered_presets:
		if preset.preset_name == String(preset_name):
			return preset
	return null


func _build_ordered_presets() -> void:
	var families: Array = _profiles_by_family.keys()
	families.sort()
	for family: StringName in families:
		for preset: BotPreset in _profiles_by_family[family]:
			_ordered_presets.append(preset)


func _build_ui() -> void:
	var host: Control = context.slot(ModuleSlots.MENU_COLUMN, null)
	layout = VBoxContainer.new()
	# taskblock-26 Pass C2: "reads as intended-centered but isn't."
	# `set_anchors_and_offsets_preset(PRESET_CENTER)` bakes a ONE-TIME pixel offset from the
	# control's size AT THE MOMENT it is called — here, before a single child exists, so the offset
	# was computed for a near-zero-size control rather than the real populated menu. Anchors alone,
	# plus GROW_BOTH, keeps the centre pinned as content is added and removed rather than once at
	# construction.
	layout.set_anchors_preset(Control.PRESET_CENTER)
	layout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layout.grow_vertical = Control.GROW_DIRECTION_BOTH
	if host != null:
		host.add_child(layout)
	else:
		add_child(layout)

	var title := Label.new()
	title.text = "Simulate Bout"
	layout.add_child(title)

	var squads := HBoxContainer.new()
	layout.add_child(squads)
	_rows_a = _squad_column(squads, "Squad A")
	_rows_b = _squad_column(squads, "Squad B")

	var seed_row := HBoxContainer.new()
	layout.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "map/seed:"
	seed_row.add_child(seed_label)
	seed_field = LineEdit.new()
	seed_field.text = str(Time.get_ticks_usec())
	seed_row.add_child(seed_field)

	# Squad A is "blue" — see `BattleScene.toggle_blue_control` for the convention.
	assume_control_checkbox = CheckBox.new()
	assume_control_checkbox.text = "Assume Control of Squad A"
	layout.add_child(assume_control_checkbox)

	var start_button := Button.new()
	start_button.text = "Start Bout"
	start_button.pressed.connect(start_bout)
	layout.add_child(start_button)

	error_label = Label.new()
	error_label.modulate = HulkTheme.WARN
	layout.add_child(error_label)

	_rebuild_team(0)
	_rebuild_team(1)


func _squad_column(parent: HBoxContainer, title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	parent.add_child(column)
	var label := Label.new()
	label.text = title
	column.add_child(label)
	var rows := VBoxContainer.new()
	column.add_child(rows)
	return rows


## taskblock-46 Pass E: the `[AI ▾]` menu reads **the profile `.tres` files themselves**, so
## dropping a new profile into `res://data/utility_profiles/` puts it in this menu with no code edit
## anywhere — the open-vocabulary rule applied to the UI.
func _profile_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for profile: UtilityProfile in DataLibrary.utility_profiles_pool():
		ids.append(profile.id)
	return ids


func _rows(squad_id: int) -> VBoxContainer:
	return _rows_a if squad_id == 0 else _rows_b


## "Adding appends a unit" — always to the end of that team's list, starting on the first profile;
## the row's own `[AI ▾]` can change it afterward like any other entry's.
func _add_to_squad(squad_id: int, preset: BotPreset) -> void:
	var ids: Array[StringName] = _profile_ids()
	roster(squad_id).append(
		BoutRosterEntry.new(preset, ids[0] if not ids.is_empty() else &"aggressive")
	)
	_rebuild_team(squad_id)


## "Removing drops exactly that entry" — every other entry keeps its position; nothing shifts
## identity, only index.
func _remove_from_squad(squad_id: int, index: int) -> void:
	roster(squad_id).remove_at(index)
	_rebuild_team(squad_id)


## "Clicking a name replaces it" — same slot, new profile; that entry's chosen AI profile untouched.
func _replace_profile_in_squad(squad_id: int, index: int, preset: BotPreset) -> void:
	roster(squad_id)[index].profile = preset
	_rebuild_team(squad_id)


func _replace_ai_profile_in_squad(squad_id: int, index: int, profile_id: StringName) -> void:
	roster(squad_id)[index].ai_profile = profile_id
	_rebuild_team(squad_id)


## `[D]` duplicates: a copy of that entry (same preset, same AI profile) inserted right after its
## own index rather than tacked onto the end, so "duplicate" reads as "one more row like this one,
## right here."
func _duplicate_in_squad(squad_id: int, index: int) -> void:
	var source: BoutRosterEntry = roster(squad_id)[index]
	roster(squad_id).insert(index + 1, BoutRosterEntry.new(source.profile, source.ai_profile))
	_rebuild_team(squad_id)


func _preset_label(preset: BotPreset) -> String:
	if preset.variant_label != "":
		return "%s — %s" % [preset.profile_family, preset.variant_label]
	return String(preset.profile_family if preset.profile_family != &"" else preset.preset_name)


## One row per roster entry: `[Bot ▾]` pre-selected to that entry's current profile, `[AI ▾]` the
## same for its AI profile, `[D]` to duplicate, `[-]` to remove.
func _entry_row(squad_id: int, index: int) -> HBoxContainer:
	var entry: BoutRosterEntry = roster(squad_id)[index]
	var row := HBoxContainer.new()
	# taskblock-26 Pass C2: "adding/duplicating an entry shouldn't reflow jarringly." The trailing
	# spacers already reserve `ROW_MIN_HEIGHT` each, so a real row left at its own natural height
	# made the total change by an inconsistent amount as the roster crossed `MIN_VISIBLE_ROWS`.
	# Every row — real, add, or spacer — reserves the same minimum.
	row.custom_minimum_size.y = ROW_MIN_HEIGHT

	var profile_dropdown := OptionButton.new()
	for preset: BotPreset in _ordered_presets:
		profile_dropdown.add_item(_preset_label(preset))
	profile_dropdown.selected = _ordered_presets.find(entry.profile)
	profile_dropdown.item_selected.connect(
		func(item_index: int) -> void:
			_replace_profile_in_squad(squad_id, index, _ordered_presets[item_index])
	)
	row.add_child(profile_dropdown)

	var profile_ids: Array[StringName] = _profile_ids()
	var ai_dropdown := OptionButton.new()
	for profile_id: StringName in profile_ids:
		ai_dropdown.add_item(String(profile_id))
	ai_dropdown.selected = profile_ids.find(entry.ai_profile)
	ai_dropdown.item_selected.connect(
		func(item_index: int) -> void:
			_replace_ai_profile_in_squad(squad_id, index, profile_ids[item_index])
	)
	row.add_child(ai_dropdown)

	var duplicate_button := Button.new()
	duplicate_button.text = "D"
	duplicate_button.pressed.connect(_duplicate_in_squad.bind(squad_id, index))
	row.add_child(duplicate_button)

	var remove_button := Button.new()
	remove_button.text = "-"
	remove_button.pressed.connect(_remove_from_squad.bind(squad_id, index))
	row.add_child(remove_button)

	return row


## Item 0 is a disabled placeholder carrying the "+ Add" label itself — picking any REAL item
## appends that preset and the row rebuilds fresh, with a new unselected Add row at the bottom.
func _add_row(squad_id: int) -> OptionButton:
	var dropdown := OptionButton.new()
	dropdown.custom_minimum_size.y = ROW_MIN_HEIGHT
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

	var entries: Array[BoutRosterEntry] = roster(squad_id)
	for index in range(entries.size()):
		rows.add_child(_entry_row(squad_id, index))
	rows.add_child(_add_row(squad_id))

	var padding: int = maxi(0, MIN_VISIBLE_ROWS - (entries.size() + 1))
	for i in range(padding):
		var spacer := Control.new()
		spacer.custom_minimum_size.y = ROW_MIN_HEIGHT
		rows.add_child(spacer)
