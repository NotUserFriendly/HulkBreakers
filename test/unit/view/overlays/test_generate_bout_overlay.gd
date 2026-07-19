extends GutTest

## taskblock-14 Pass D / taskblock-15 Pass A: GenerateBoutOverlay — the
## thin UI wrapper around BoutSetup (already covered headlessly by
## test_bout_setup.gd). This checks the overlay actually wires up (profile
## dropdowns list the loaded profiles), Start Bout is rejected-not-crashed
## on a bad setup, and — A2's own requirement — a valid Start Bout hands
## off to a live SpectatorOverlay, never leaving this one installed.
##
## taskblock-16 Pass E: teams are expanding lists now, no count field —
## these tests drive the same `_add_to_squad`/`_remove_from_squad`/
## `_replace_profile_in_squad` handlers the row widgets themselves call,
## the same "call the handler directly" convention `_on_start_bout_pressed`
## already used above (this menu is data-driven, not spatial input — real
## click simulation is for gameplay tests like test_battle_scene_input.gd).
##
## taskblock-17 Pass D: playstyle moved from one per-team dropdown to a
## per-bot one on each row (`_replace_playstyle_in_squad`), and each row
## gained a duplicate handler (`_duplicate_in_squad`) — rosters are
## `Array[BoutRosterEntry]` now, not `Array[BotPreset]`.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## Neutralizes _ready()'s own default SquadControlOverlay first — same
## reasoning as test_spectator_overlay.gd's own `_spectate()` helper,
## though GenerateBoutOverlay itself never touches battle_loaded, so this
## is only for symmetry/hygiene here, not a hazard this overlay has.
func _menu() -> Dictionary:
	var battle := BattleScene.new()
	add_child_autofree(battle)
	battle.set_overlay(GenerateBoutOverlay.new())
	return {"battle": battle, "overlay": battle.overlay as GenerateBoutOverlay}


## "The menu lists loaded profiles" — both reference profiles from
## taskblock-14 Pass A are available to add to a roster.
func test_setup_populates_ordered_presets_from_loaded_presets() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay

	assert_gt(overlay._ordered_presets.size(), 0)


func test_a_variant_is_listed_under_its_own_family_label() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay

	var found_variant := false
	for preset: BotPreset in overlay._ordered_presets:
		if overlay._preset_label(preset).contains("Battery Mods"):
			found_variant = true
	assert_true(found_variant, "the a_brand_laborer_battery_mods variant must appear in the list")


## Both teams start pre-populated (a flagged UX default, `DEFAULT_STARTING_COUNT`
## — see the overlay's own doc comment) rather than empty, so a fresh
## Start Bout is still a one-click smoke test. Squad B starts on
## COVER_SEEKER, squad A on AGGRESSIVE — "two playstyles facing off" —
## same intent the old per-team default carried, now expressed per-bot.
func test_setup_seeds_both_rosters_with_a_starting_default() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay

	assert_eq(overlay._roster_a.size(), GenerateBoutOverlay.DEFAULT_STARTING_COUNT)
	assert_eq(overlay._roster_b.size(), GenerateBoutOverlay.DEFAULT_STARTING_COUNT)
	for entry: BoutRosterEntry in overlay._roster_a:
		assert_eq(entry.playstyle, &"AGGRESSIVE")
	for entry: BoutRosterEntry in overlay._roster_b:
		assert_eq(entry.playstyle, &"COVER_SEEKER")


## "Adding appends a unit."
func test_add_to_squad_appends_to_the_end_of_the_roster() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay
	var starting_size: int = overlay._roster_a.size()
	var preset: BotPreset = overlay._ordered_presets[0]

	overlay._add_to_squad(0, preset)

	assert_eq(overlay._roster_a.size(), starting_size + 1)
	assert_eq(overlay._roster_a[overlay._roster_a.size() - 1].profile, preset)


## "Removing drops exactly that entry" — every other entry keeps its own
## profile, only the removed one's gone.
func test_remove_from_squad_drops_exactly_that_entry() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay
	overlay._roster_a = [
		BoutRosterEntry.new(overlay._ordered_presets[0], &"AGGRESSIVE"),
		BoutRosterEntry.new(overlay._ordered_presets[1], &"AGGRESSIVE"),
		BoutRosterEntry.new(overlay._ordered_presets[0], &"AGGRESSIVE"),
	]
	var kept_middle: BoutRosterEntry = overlay._roster_a[1]

	overlay._remove_from_squad(0, 0)

	assert_eq(overlay._roster_a.size(), 2)
	assert_eq(overlay._roster_a[0], kept_middle, "the surviving entries must not shift identity")


## "Clicking a name replaces it" — same slot, new profile, its own
## playstyle untouched, roster size unchanged.
func test_replace_profile_in_squad_swaps_the_profile_at_that_index() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay
	overlay._roster_a = [BoutRosterEntry.new(overlay._ordered_presets[0], &"MARKSMAN")]
	var replacement: BotPreset = overlay._ordered_presets[1]

	overlay._replace_profile_in_squad(0, 0, replacement)

	assert_eq(overlay._roster_a.size(), 1)
	assert_eq(overlay._roster_a[0].profile, replacement)
	assert_eq(
		overlay._roster_a[0].playstyle, &"MARKSMAN", "replacing the profile must not touch AI"
	)


## taskblock-17 Pass D: "`[AI ▾]` — per-bot playstyle" — same slot, new
## playstyle, profile untouched.
func test_replace_playstyle_in_squad_swaps_the_playstyle_at_that_index() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay
	var preset: BotPreset = overlay._ordered_presets[0]
	overlay._roster_a = [BoutRosterEntry.new(preset, &"AGGRESSIVE")]

	overlay._replace_playstyle_in_squad(0, 0, &"SKIRMISHER")

	assert_eq(overlay._roster_a.size(), 1)
	assert_eq(overlay._roster_a[0].playstyle, &"SKIRMISHER")
	assert_eq(overlay._roster_a[0].profile, preset, "changing AI must not touch the profile")


## taskblock-17 Pass D: "`[D]` — duplicate. Appends a copy of that entry
## (same profile + same playstyle) below it."
func test_duplicate_in_squad_inserts_an_identical_entry_right_below() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay
	var preset: BotPreset = overlay._ordered_presets[0]
	var other: BotPreset = overlay._ordered_presets[1]
	overlay._roster_a = [
		BoutRosterEntry.new(preset, &"MARKSMAN"), BoutRosterEntry.new(other, &"AGGRESSIVE")
	]

	overlay._duplicate_in_squad(0, 0)

	assert_eq(overlay._roster_a.size(), 3)
	assert_eq(overlay._roster_a[0].profile, preset)
	assert_eq(overlay._roster_a[0].playstyle, &"MARKSMAN")
	assert_eq(
		overlay._roster_a[1].profile, preset, "the duplicate must land directly below its source"
	)
	assert_eq(overlay._roster_a[1].playstyle, &"MARKSMAN")
	assert_eq(overlay._roster_a[2].profile, other, "every later entry keeps its own position")


## "No count field remains" — SpinBox is gone outright, not just unused.
func test_no_count_field_exists_on_the_overlay() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay

	assert_false("_count_a_field" in overlay, "the old count SpinBox must be fully retired")
	assert_false("_count_b_field" in overlay, "the old count SpinBox must be fully retired")


## taskblock-17 Pass D: the old per-team playstyle dropdowns are fully
## retired, not just unused — playstyle lives per-row now.
func test_no_per_team_playstyle_dropdown_exists_on_the_overlay() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay

	assert_false(
		"_playstyle_a_dropdown" in overlay, "the old per-team playstyle dropdown must be retired"
	)
	assert_false(
		"_playstyle_b_dropdown" in overlay, "the old per-team playstyle dropdown must be retired"
	)


## "An empty team is refused, not crashed."
func test_start_bout_with_an_empty_roster_is_rejected_not_crashed() -> void:
	var wired: Dictionary = _menu()
	var overlay: GenerateBoutOverlay = wired.overlay
	var battle: BattleScene = wired.battle
	overlay._roster_a = []

	overlay._on_start_bout_pressed()

	assert_ne(overlay._error_label.text, "")
	assert_eq(battle.overlay, overlay, "a rejected setup must never swap the overlay")


## taskblock-15 Pass A2: "generate-bout hands off to spectator cleanly."
func test_a_valid_start_bout_hands_off_to_a_live_spectator_overlay() -> void:
	var wired: Dictionary = _menu()
	var overlay: GenerateBoutOverlay = wired.overlay
	var battle: BattleScene = wired.battle

	overlay._on_start_bout_pressed()

	assert_true(
		battle.overlay is SpectatorOverlay, "Start Bout must swap to a real SpectatorOverlay"
	)
	var spectator: SpectatorOverlay = battle.overlay as SpectatorOverlay
	assert_not_null(spectator.runner)
	assert_eq(spectator.runner.state, battle.combat_state, "the same bout, not a stale reference")


## taskblock-17 Pass D: "each bot entry carries its own playstyle into
## the built bout" — end to end, through the real Start Bout path.
func test_start_bout_threads_each_entrys_own_playstyle_into_the_built_units() -> void:
	var wired: Dictionary = _menu()
	var overlay: GenerateBoutOverlay = wired.overlay
	var preset: BotPreset = overlay._ordered_presets[0]
	overlay._roster_a = [
		BoutRosterEntry.new(preset, &"MARKSMAN"), BoutRosterEntry.new(preset, &"SKIRMISHER")
	]
	overlay._roster_b = [BoutRosterEntry.new(preset, &"COVER_SEEKER")]

	overlay._on_start_bout_pressed()

	var state: CombatState = wired.battle.combat_state
	var squad_a: Array[Unit] = state.units.filter(func(u: Unit) -> bool: return u.squad_id == 0)
	assert_eq(squad_a[0].matrix.playstyle, &"MARKSMAN")
	assert_eq(squad_a[1].matrix.playstyle, &"SKIRMISHER")
	var squad_b: Array[Unit] = state.units.filter(func(u: Unit) -> bool: return u.squad_id == 1)
	assert_eq(squad_b[0].matrix.playstyle, &"COVER_SEEKER")
