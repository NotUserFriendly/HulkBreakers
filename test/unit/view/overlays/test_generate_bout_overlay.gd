extends GutTest

## taskblock-14 Pass D / taskblock-15 Pass A: ControlOverlay — the
## thin UI wrapper around BoutSetup (already covered headlessly by
## test_bout_setup.gd). This checks the overlay actually wires up (profile
## dropdowns list the loaded profiles), Start Bout is rejected-not-crashed
## on a bad setup, and — A2's own requirement — a valid Start Bout hands
## off to a live spectator surface, never leaving this one installed.
##
## taskblock-16 Pass E: teams are expanding lists now, no count field —
## these tests drive the same `_add_to_squad`/`_remove_from_squad`/
## `_replace_profile_in_squad` handlers the row widgets themselves call,
## the same "call the handler directly" convention `_on_start_bout_pressed`
## already used above (this menu is data-driven, not spatial input — real
## click simulation is for gameplay tests like test_battle_scene_input.gd).
##
## taskblock-17 Pass D: playstyle moved from one per-team dropdown to a
## per-bot one on each row (`_replace_ai_profile_in_squad`), and each row
## gained a duplicate handler (`_duplicate_in_squad`) — rosters are
## `Array[BoutRosterEntry]` now, not `Array[BotPreset]`.


## taskblock-47 Pass C: this file builds bouts, so the fast gate skips it. The list it
## is on is checked against the profile's own bout counter every run — see `SuiteTier`.
##
## **Untyped on purpose, against this project's static-typing rule.** GUT declares
## `func should_skip_script():` with no return type, and Godot treats an override that
## adds `-> Variant` as a signature mismatch — the script then fails to parse and GUT
## reports it as "does not extend GutTest", which is a long way from the real cause.
func should_skip_script():
	return SuiteTier.skip_if_fast()


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## Neutralizes _ready()'s own default player mode first — same
## reasoning as test_spectator_overlay.gd's own `_spectate()` helper,
## though the bout-setup mode itself never touches battle_loaded, so this
## is only for symmetry/hygiene here, not a hazard this overlay has.
func _menu() -> Dictionary:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(ControlOverlay.for_mode(ViewModes.bout_setup()))
	return {"battle": battle, "overlay": battle.overlay as ControlOverlay}


## "The menu lists loaded profiles" — both reference profiles from
## taskblock-14 Pass A are available to add to a roster.
func test_setup_populates_ordered_presets_from_loaded_presets() -> void:
	var overlay: ControlOverlay = _menu().overlay

	assert_gt(overlay.bout_setup()._ordered_presets.size(), 0)


func test_a_variant_is_listed_under_its_own_family_label() -> void:
	var overlay: ControlOverlay = _menu().overlay

	var found_variant := false
	for preset: BotPreset in overlay.bout_setup()._ordered_presets:
		if overlay.bout_setup()._preset_label(preset).contains("Battery Mods"):
			found_variant = true
	assert_true(found_variant, "the a_brand_laborer_battery_mods variant must appear in the list")


## Both teams start pre-populated (a flagged UX default, `DEFAULT_ROSTER`
## — see the overlay's own doc comment) rather than empty, so a fresh
## Start Bout is still a one-click smoke test: one of each armed "Combat
## Tester" variant, identical on both sides — a full weapon spread on
## each team, each bot paired with a different AI profile. taskblock-46
## Pass E changed WHY they differ: the pairing used to be range-matched
## because a playstyle carried a preferred range, and now standoff is
## scored against the unit's own weapon, so what the default spreads is
## temperament. Asserted as the exact pairing rather than "three distinct
## profiles" because the pairing is the flagged UX default, and a silent
## drift in it is a change to what a one-click Start Bout demonstrates.
func test_setup_seeds_both_rosters_with_one_of_each_combat_tester_variant() -> void:
	var overlay: ControlOverlay = _menu().overlay

	var expected: Dictionary = {
		&"combat_tester_chaingun": &"cautious",
		&"combat_tester_sniper_rifle": &"defensive",
		&"combat_tester_pump_shotgun": &"aggressive",
	}
	var authored: Array[StringName] = []
	for profile: UtilityProfile in DataLibrary.utility_profiles_pool():
		authored.append(profile.id)
	for roster: Array[BoutRosterEntry] in [
		overlay.bout_setup().roster(0), overlay.bout_setup().roster(1)
	]:
		assert_eq(roster.size(), expected.size())
		for entry: BoutRosterEntry in roster:
			assert_true(
				expected.has(entry.profile.preset_name),
				"unexpected default roster entry: %s" % entry.profile.preset_name
			)
			assert_eq(entry.ai_profile, expected[entry.profile.preset_name])
			# A default naming a profile that is not on disk does not throw — the
			# scorer just falls back to unweighted. This is the assertion that
			# would notice.
			assert_has(authored, entry.ai_profile, "and it is a profile that exists")


## Every DataLibrary accessor hands back a fresh `.duplicate(true)` on
## every call — a default roster entry built from a SEPARATE lookup than
## `_ordered_presets` used is a different object, `_entry_row`'s own
## `_ordered_presets.find(entry.profile)` finds nothing, and the row's
## dropdown shows blank instead of the preset name even though the
## roster's own DATA is completely correct. A data-only assertion (the
## test above) can't see this — it has to read the real built
## `OptionButton` node back (CLAUDE.md: verify against the real node,
## never a re-derived formula that would just agree with the same bug).
func test_default_roster_rows_actually_render_a_selected_bot_name() -> void:
	var overlay: ControlOverlay = _menu().overlay

	for rows: VBoxContainer in [overlay.bout_setup()._rows(0), overlay.bout_setup()._rows(1)]:
		for i in range(
			overlay.bout_setup().roster(0 if rows == overlay.bout_setup()._rows(0) else 1).size()
		):
			var row: HBoxContainer = rows.get_child(i) as HBoxContainer
			var profile_dropdown: OptionButton = row.get_child(0) as OptionButton
			assert_ne(
				profile_dropdown.selected, -1, "row %d must have a real selection, not blank" % i
			)
			assert_ne(profile_dropdown.text, "", "row %d's dropdown must show a real bot name" % i)


## "Adding appends a unit."
func test_add_to_squad_appends_to_the_end_of_the_roster() -> void:
	var overlay: ControlOverlay = _menu().overlay
	var starting_size: int = overlay.bout_setup().roster(0).size()
	var preset: BotPreset = overlay.bout_setup()._ordered_presets[0]

	overlay.bout_setup()._add_to_squad(0, preset)

	assert_eq(overlay.bout_setup().roster(0).size(), starting_size + 1)
	assert_eq(
		overlay.bout_setup().roster(0)[overlay.bout_setup().roster(0).size() - 1].profile, preset
	)


## "Removing drops exactly that entry" — every other entry keeps its own
## profile, only the removed one's gone.
func test_remove_from_squad_drops_exactly_that_entry() -> void:
	var overlay: ControlOverlay = _menu().overlay
	(
		overlay
		. bout_setup()
		. set_roster(
			0,
			[
				BoutRosterEntry.new(overlay.bout_setup()._ordered_presets[0], &"aggressive"),
				BoutRosterEntry.new(overlay.bout_setup()._ordered_presets[1], &"aggressive"),
				BoutRosterEntry.new(overlay.bout_setup()._ordered_presets[0], &"aggressive"),
			]
		)
	)
	var kept_middle: BoutRosterEntry = overlay.bout_setup().roster(0)[1]

	overlay.bout_setup()._remove_from_squad(0, 0)

	assert_eq(overlay.bout_setup().roster(0).size(), 2)
	assert_eq(
		overlay.bout_setup().roster(0)[0],
		kept_middle,
		"the surviving entries must not shift identity"
	)


## "Clicking a name replaces it" — same slot, new profile, its own
## AI profile untouched, roster size unchanged.
func test_replace_profile_in_squad_swaps_the_profile_at_that_index() -> void:
	var overlay: ControlOverlay = _menu().overlay
	overlay.bout_setup().set_roster(
		0, [BoutRosterEntry.new(overlay.bout_setup()._ordered_presets[0], &"defensive")]
	)
	var replacement: BotPreset = overlay.bout_setup()._ordered_presets[1]

	overlay.bout_setup()._replace_profile_in_squad(0, 0, replacement)

	assert_eq(overlay.bout_setup().roster(0).size(), 1)
	assert_eq(overlay.bout_setup().roster(0)[0].profile, replacement)
	assert_eq(
		overlay.bout_setup().roster(0)[0].ai_profile,
		&"defensive",
		"replacing the preset must not touch AI"
	)


## taskblock-17 Pass D: "`[AI ▾]` — per-bot AI" — same slot, new profile,
## preset untouched.
func test_replace_ai_profile_in_squad_swaps_the_profile_at_that_index() -> void:
	var overlay: ControlOverlay = _menu().overlay
	var preset: BotPreset = overlay.bout_setup()._ordered_presets[0]
	overlay.bout_setup().set_roster(0, [BoutRosterEntry.new(preset, &"aggressive")])

	overlay.bout_setup()._replace_ai_profile_in_squad(0, 0, &"cautious")

	assert_eq(overlay.bout_setup().roster(0).size(), 1)
	assert_eq(overlay.bout_setup().roster(0)[0].ai_profile, &"cautious")
	assert_eq(
		overlay.bout_setup().roster(0)[0].profile, preset, "changing AI must not touch the preset"
	)


## taskblock-17 Pass D: "`[D]` — duplicate. Appends a copy of that entry
## (same preset + same AI profile) below it."
func test_duplicate_in_squad_inserts_an_identical_entry_right_below() -> void:
	var overlay: ControlOverlay = _menu().overlay
	var preset: BotPreset = overlay.bout_setup()._ordered_presets[0]
	var other: BotPreset = overlay.bout_setup()._ordered_presets[1]
	overlay.bout_setup().set_roster(
		0, [BoutRosterEntry.new(preset, &"defensive"), BoutRosterEntry.new(other, &"aggressive")]
	)

	overlay.bout_setup()._duplicate_in_squad(0, 0)

	assert_eq(overlay.bout_setup().roster(0).size(), 3)
	assert_eq(overlay.bout_setup().roster(0)[0].profile, preset)
	assert_eq(overlay.bout_setup().roster(0)[0].ai_profile, &"defensive")
	assert_eq(
		overlay.bout_setup().roster(0)[1].profile,
		preset,
		"the duplicate must land directly below its source"
	)
	assert_eq(overlay.bout_setup().roster(0)[1].ai_profile, &"defensive")
	assert_eq(
		overlay.bout_setup().roster(0)[2].profile, other, "every later entry keeps its own position"
	)


## "No count field remains" — SpinBox is gone outright, not just unused.
func test_no_count_field_exists_on_the_overlay() -> void:
	var overlay: ControlOverlay = _menu().overlay

	assert_false("_count_a_field" in overlay, "the old count SpinBox must be fully retired")
	assert_false("_count_b_field" in overlay, "the old count SpinBox must be fully retired")


## taskblock-17 Pass D: the old per-team AI dropdowns are fully
## retired, not just unused — the AI choice lives per-row now.
func test_no_per_team_ai_dropdown_exists_on_the_overlay() -> void:
	var overlay: ControlOverlay = _menu().overlay

	assert_false("_playstyle_a_dropdown" in overlay, "the old per-team AI dropdown must be retired")
	assert_false("_playstyle_b_dropdown" in overlay, "the old per-team AI dropdown must be retired")


## "An empty team is refused, not crashed."
func test_start_bout_with_an_empty_roster_is_rejected_not_crashed() -> void:
	var wired: Dictionary = _menu()
	var overlay: ControlOverlay = wired.overlay
	var battle: BattleScene = wired.battle
	overlay.bout_setup().set_roster(0, [])

	overlay.bout_setup().start_bout()

	assert_ne(overlay.bout_setup().error_label.text, "")
	assert_eq(battle.overlay, overlay, "a rejected setup must never swap the overlay")


## taskblock-15 Pass A2: "generate-bout hands off to spectator cleanly."
func test_a_valid_start_bout_hands_off_to_a_live_spectator_overlay() -> void:
	var wired: Dictionary = _menu()
	var overlay: ControlOverlay = wired.overlay
	var battle: BattleScene = wired.battle

	overlay.bout_setup().start_bout()

	assert_true(
		battle.overlay is ControlOverlay, "Start Bout must swap to a real spectator surface"
	)
	var spectator: ControlOverlay = battle.overlay as ControlOverlay
	assert_not_null(spectator.playback().runner)
	assert_eq(
		spectator.playback().runner.state,
		battle.combat_state,
		"the same bout, not a stale reference"
	)


## taskblock-17 Pass D: "each bot entry carries its own AI into the built
## bout" — end to end, through the real Start Bout path.
func test_start_bout_threads_each_entrys_own_profile_into_the_built_units() -> void:
	var wired: Dictionary = _menu()
	var overlay: ControlOverlay = wired.overlay
	var preset: BotPreset = overlay.bout_setup()._ordered_presets[0]
	overlay.bout_setup().set_roster(
		0, [BoutRosterEntry.new(preset, &"defensive"), BoutRosterEntry.new(preset, &"cautious")]
	)
	overlay.bout_setup().set_roster(1, [BoutRosterEntry.new(preset, &"cowardly")])

	overlay.bout_setup().start_bout()

	var state: CombatState = wired.battle.combat_state
	var squad_a: Array[Unit] = state.units.filter(func(u: Unit) -> bool: return u.squad_id == 0)
	assert_eq(squad_a[0].matrix.ai_profile, &"defensive")
	assert_eq(squad_a[1].matrix.ai_profile, &"cautious")
	var squad_b: Array[Unit] = state.units.filter(func(u: Unit) -> bool: return u.squad_id == 1)
	assert_eq(squad_b[0].matrix.ai_profile, &"cowardly")


## taskblock-26 Pass C1 wanted the menu populated from the real AI set
## rather than a hand-copied list. taskblock-46 Pass E deleted the list
## it copied from: the menu now reads the profile `.tres` files
## themselves, so **dropping a file into `res://data/utility_profiles/`
## is the whole of adding a menu entry.**
##
## Asserted against `DataLibrary`, which is what the overlay reads —
## comparing it to a second hardcoded list here would just move the
## hand-copy into the test.
func test_the_menu_lists_exactly_the_profiles_on_disk() -> void:
	var overlay: ControlOverlay = _menu().overlay
	var authored: Array[StringName] = []
	for profile: UtilityProfile in DataLibrary.utility_profiles_pool():
		authored.append(profile.id)

	assert_eq(overlay.bout_setup()._profile_ids(), authored)
	assert_gt(authored.size(), 1, "sanity: the menu is not a single fixed entry")
	assert_false(
		"PLAYSTYLES" in BoutSetupModule, "the playstyle vocabulary must be gone, not unused"
	)


## taskblock-26 Pass C2: "adding/duplicating an entry shouldn't reflow
## jarringly — stabilize the layout (fixed row heights)." A real entry
## row, the trailing add-row, and a padding spacer must all reserve the
## SAME minimum height — the mismatch (spacers pinned to ROW_MIN_HEIGHT,
## real rows left at their own natural theme height) is what made the
## total layout height jump unpredictably as the roster crossed the
## MIN_VISIBLE_ROWS threshold.
func test_every_row_shape_reserves_the_same_minimum_height() -> void:
	var overlay: ControlOverlay = _menu().overlay
	overlay.bout_setup()._add_to_squad(0, overlay.bout_setup()._ordered_presets[0])

	var rows: VBoxContainer = overlay.bout_setup()._rows(0)
	assert_gt(rows.get_child_count(), 0, "sanity: at least the real entry + the add row exist")
	for row: Control in rows.get_children():
		assert_almost_eq(
			row.custom_minimum_size.y,
			BoutSetupModule.ROW_MIN_HEIGHT,
			0.01,
			"every row shape (entry, add, spacer) must reserve the same height"
		)


## taskblock-26 Pass C2: "center the menu (review notes it reads as
## intended-centered but isn't)." The old `set_anchors_and_offsets_preset`
## baked a one-time pixel offset from the layout's size AT CONSTRUCTION —
## before a single child existed — so it was centered for an empty
## control, not the real, populated menu. Anchors pinned to 0.5 with
## GROW_BOTH and no baked offset keeps the control's own center pinned to
## the parent's midpoint regardless of how its size changes afterward.
func test_the_menu_layout_stays_centered_regardless_of_its_own_size() -> void:
	var overlay: ControlOverlay = _menu().overlay
	var layout: VBoxContainer = overlay.bout_setup().layout

	assert_almost_eq(layout.anchor_left, 0.5, 0.001)
	assert_almost_eq(layout.anchor_right, 0.5, 0.001)
	assert_almost_eq(layout.anchor_top, 0.5, 0.001)
	assert_almost_eq(layout.anchor_bottom, 0.5, 0.001)
	assert_eq(layout.grow_horizontal, Control.GROW_DIRECTION_BOTH)
	assert_eq(layout.grow_vertical, Control.GROW_DIRECTION_BOTH)
