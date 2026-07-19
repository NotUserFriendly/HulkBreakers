extends GutTest

## taskblock-14 Pass D / taskblock-15 Pass A: GenerateBoutOverlay — the
## thin UI wrapper around BoutSetup (already covered headlessly by
## test_bout_setup.gd). This checks the overlay actually wires up (profile
## dropdowns list the loaded profiles), Start Bout is rejected-not-crashed
## on a bad setup, and — A2's own requirement — a valid Start Bout hands
## off to a live SpectatorOverlay, never leaving this one installed.


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
## taskblock-14 Pass A show up as dropdown entries.
func test_setup_populates_the_profile_dropdowns_from_loaded_presets() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay

	assert_gt(overlay._squad_a_dropdown.item_count, 0)
	assert_eq(overlay._squad_a_dropdown.item_count, overlay._squad_b_dropdown.item_count)
	assert_eq(overlay._squad_a_dropdown.item_count, overlay._ordered_presets.size())


func test_a_variant_is_listed_under_its_own_family_label() -> void:
	var overlay: GenerateBoutOverlay = _menu().overlay

	var found_variant := false
	for i in range(overlay._squad_a_dropdown.item_count):
		if overlay._squad_a_dropdown.get_item_text(i).contains("Battery Mods"):
			found_variant = true
	assert_true(found_variant, "the a_brand_laborer_battery_mods variant must appear in the list")


## "An invalid setup (empty squad) is rejected, not crashed" — no profile
## selected (SpinBox itself refuses to go below its own min_value of 1, so
## an empty selection is the reachable way to make BoutSetup refuse).
func test_start_bout_with_no_profile_selected_is_rejected_not_crashed() -> void:
	var wired: Dictionary = _menu()
	var overlay: GenerateBoutOverlay = wired.overlay
	var battle: BattleScene = wired.battle
	overlay._squad_a_dropdown.selected = -1

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
