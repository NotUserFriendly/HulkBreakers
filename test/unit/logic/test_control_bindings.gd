extends GutTest

## docs/10 taskblock03 J: "generate it from the binding table" — this table
## is the whole contract; ControlsOverlay just formats it.


func test_all_returns_a_non_empty_list_of_trigger_action_pairs() -> void:
	var rows: Array[Dictionary] = ControlBindings.all("res://out/combat.log")
	assert_true(rows.size() > 0)
	for row: Dictionary in rows:
		assert_true(row.has("trigger"))
		assert_true(row.has("action"))
		assert_true((row["trigger"] as String).length() > 0)
		assert_true((row["action"] as String).length() > 0)


func test_the_log_path_is_folded_into_one_of_the_rows() -> void:
	var rows: Array[Dictionary] = ControlBindings.all("res://out/combat.log")
	var found := false
	for row: Dictionary in rows:
		if (row["action"] as String) == "res://out/combat.log":
			found = true
	assert_true(found, "the actual session log path must appear verbatim")


## docs/10 taskblock03 J: "or it will drift the first time a key changes" —
## the displayed trigger text must be derived from the real keycode
## constant, not a separately hand-typed letter.
func test_reset_turn_row_shows_the_real_reset_turn_keys_own_letter() -> void:
	var rows: Array[Dictionary] = ControlBindings.all("")
	var reset_row: Dictionary = {}
	for row: Dictionary in rows:
		if (row["action"] as String) == "reset turn":
			reset_row = row
	assert_true(
		(reset_row["trigger"] as String).contains(
			OS.get_keycode_string(ControlBindings.RESET_TURN_KEY)
		)
	)


func test_toggle_key_is_h() -> void:
	assert_eq(ControlBindings.TOGGLE_KEY, KEY_H)
