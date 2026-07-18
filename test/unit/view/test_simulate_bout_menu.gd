extends GutTest

## taskblock-14 Pass D: SimulateBoutMenu — the thin UI wrapper around
## BoutSetup (already covered headlessly by test_bout_setup.gd). This only
## checks the scene actually wires up: the profile dropdowns list the
## loaded profiles, and Start Bout is rejected-not-crashed on a bad setup.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## "The menu lists loaded profiles" — both reference profiles from
## taskblock-14 Pass A show up as dropdown entries.
func test_ready_populates_the_profile_dropdowns_from_loaded_presets() -> void:
	var menu := SimulateBoutMenu.new()
	add_child_autofree(menu)

	assert_gt(menu._squad_a_dropdown.item_count, 0)
	assert_eq(menu._squad_a_dropdown.item_count, menu._squad_b_dropdown.item_count)
	assert_eq(menu._squad_a_dropdown.item_count, menu._ordered_presets.size())


func test_a_variant_is_listed_under_its_own_family_label() -> void:
	var menu := SimulateBoutMenu.new()
	add_child_autofree(menu)

	var found_variant := false
	for i in range(menu._squad_a_dropdown.item_count):
		if menu._squad_a_dropdown.get_item_text(i).contains("Battery Mods"):
			found_variant = true
	assert_true(found_variant, "the a_brand_laborer_battery_mods variant must appear in the list")


## "An invalid setup (empty squad) is rejected, not crashed" — no profile
## selected (SpinBox itself refuses to go below its own min_value of 1, so
## an empty selection is the reachable way to make BoutSetup refuse).
func test_start_bout_with_no_profile_selected_is_rejected_not_crashed() -> void:
	var menu := SimulateBoutMenu.new()
	add_child_autofree(menu)
	menu._squad_a_dropdown.selected = -1

	menu._on_start_bout_pressed()

	assert_ne(menu._error_label.text, "")
