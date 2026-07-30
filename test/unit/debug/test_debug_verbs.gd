extends GutTest


## taskblock-42 Pass E (BR35.03): the one authority for "does this debug verb
## change the BOARD", read by both overlays so the same question is never
## answered twice in two files.
## taskblock-42 Pass E (BR35.03): every debug verb used to trigger a full
## `BoardView.build()` — terrain, grid lines, every blocker, every field item —
## including the ~20 that only ever touch one unit's AP, facing, pose or parts.
func test_only_board_changing_verbs_ask_for_a_board_rebuild() -> void:
	assert_true(DebugVerbs.affects_board(&"spawn_object"))
	assert_true(DebugVerbs.affects_board(&"set_cell_level"))
	assert_true(DebugVerbs.affects_board(&"set_passable"))

	assert_false(DebugVerbs.affects_board(&"set_ap"), "an AP change is not a board change")
	assert_false(DebugVerbs.affects_board(&"set_facing"))
	assert_false(DebugVerbs.affects_board(&"inflict_wound"))
	assert_false(DebugVerbs.affects_board(&"kill"))


## Either can target a cell OR a unit, decided at call time by its own target
## dict — so both stay in the list unconditionally. A missed board rebuild is an
## invisible-until-noticed bug; an extra one is merely slow.
func test_move_object_and_remove_object_always_rebuild_either_can_target_a_cell() -> void:
	assert_true(DebugVerbs.affects_board(&"move_object"))
	assert_true(DebugVerbs.affects_board(&"remove_object"))


## The list names real verbs — a typo here would silently stop a board rebuild
## that is genuinely needed.
func test_every_board_changing_verb_is_a_real_verb() -> void:
	var ids: Array[StringName] = []
	for spec: DebugVerbSpec in DebugVerbs.all():
		ids.append(spec.id)
	for verb: StringName in DebugVerbs.BOARD_CHANGING_VERBS:
		assert_true(verb in ids, "%s is not a real debug verb" % verb)
