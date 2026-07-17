extends GutTest

## docs/10 taskblock05 G: "the builder is the best test the assembler will
## ever get." BuilderController assembles ONLY through BodyAssembler —
## every test here proves that, never a parallel path.


func test_assemble_produces_a_unit_structurally_identical_to_code() -> void:
	var controller := BuilderController.new()
	controller.loadout = DeepStrike.default_loadout()
	var built: Unit = controller.assemble()
	var reference: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i.ZERO)

	var built_ids: Array[StringName] = []
	for part: Part in built.shell.all_parts():
		built_ids.append(part.id)
	var reference_ids: Array[StringName] = []
	for part: Part in reference.shell.all_parts():
		reference_ids.append(part.id)

	assert_eq(built_ids, reference_ids)


func test_an_unknown_template_id_returns_null() -> void:
	var controller := BuilderController.new()
	controller.template_id = &"nonexistent"
	assert_null(controller.assemble())


func test_set_part_fills_an_empty_socket() -> void:
	var controller := BuilderController.new()
	controller.set_part(&"GRIP_R", &"pistol")
	var unit: Unit = controller.assemble()
	assert_not_null(unit.shell.find_part(&"pistol"))


func test_set_part_replaces_an_already_filled_socket() -> void:
	var controller := BuilderController.new()
	controller.loadout = DeepStrike.default_loadout()  # both grips start as pistol
	controller.set_part(&"GRIP_R", &"rifle")
	var unit: Unit = controller.assemble()

	var hand_r: Part = unit.shell.find_part(&"hand_r")
	var grip_r: Socket = PartGraph.find_socket(hand_r, &"GRIP_R")
	assert_eq(grip_r.occupant.id, &"rifle")
	var hand_l: Part = unit.shell.find_part(&"hand_l")
	var grip_l: Socket = PartGraph.find_socket(hand_l, &"GRIP_L")
	assert_eq(grip_l.occupant.id, &"pistol", "only the socket that was set must change")


func test_clear_socket_empties_a_loadout_only_socket() -> void:
	var controller := BuilderController.new()
	controller.loadout = DeepStrike.default_loadout()
	controller.clear_socket(&"GRIP_R")
	var unit: Unit = controller.assemble()

	var hand_r: Part = unit.shell.find_part(&"hand_r")
	var grip_r: Socket = PartGraph.find_socket(hand_r, &"GRIP_R")
	assert_null(grip_r.occupant)


## docs/10 taskblock05 G4: at the reference humanoid's own (generous)
## budget, no single candidate part can ever trip the mass/RAM checks —
## so the legal set here is exactly PartGraph.is_legal_attachment's own
## true set, proving the picker never invents its own attachment rule.
func test_the_pickers_legal_set_matches_bodyassemblers_own_attachment_rule() -> void:
	var controller := BuilderController.new()
	var unit: Unit = controller.assemble()
	var head: Part = unit.shell.find_part(&"head")
	var armor_socket: Socket = PartGraph.find_socket(head, &"ARMOR")

	var candidates: Dictionary = controller.candidates_for(unit.shell, armor_socket)
	var legal: Array = candidates.legal
	var illegal: Array = candidates.illegal

	for candidate: Part in legal:
		assert_true(PartGraph.is_legal_attachment(candidate, armor_socket))
	for entry: Dictionary in illegal:
		assert_false(PartGraph.is_legal_attachment(entry.part as Part, armor_socket))
	assert_eq(legal.size() + illegal.size(), controller.pool.size())


## Every illegal part must carry a reason string — never a silently empty
## one — and it must actually explain something checkable (docs/10
## taskblock05 D1: a keyed cladding mismatch reads as a wrong attaches_to).
func test_every_illegal_part_carries_a_non_empty_reason() -> void:
	var controller := BuilderController.new()
	var unit: Unit = controller.assemble()
	var leg: Part = unit.shell.find_part(&"leg")
	var cladding_socket: Socket = PartGraph.find_socket(leg, &"CLADDING")

	var candidates: Dictionary = controller.candidates_for(unit.shell, cladding_socket)
	var illegal: Array = candidates.illegal
	assert_true(illegal.size() > 0, "the leg's own keyed cladding socket must reject something")
	for entry: Dictionary in illegal:
		var reason: String = entry.reason
		assert_false(reason.is_empty())


## The mass/RAM half of the picker's own reasons, exercised directly by
## shrinking the budget until a real candidate cannot fit.
func test_an_illegal_part_over_the_mass_budget_names_the_overage() -> void:
	var controller := BuilderController.new()
	var unit: Unit = controller.assemble()
	unit.shell.max_mass = 0.0  # nothing can possibly fit now
	var torso: Part = unit.shell.root
	var armor_front: Socket = PartGraph.find_socket(torso, &"ARMOR_FRONT")
	armor_front.occupant = null  # re-open it to test against

	var candidates: Dictionary = controller.candidates_for(unit.shell, armor_front)
	var found := false
	for entry: Dictionary in candidates.illegal:
		if (entry.part as Part).id == &"plate_large_steel":
			assert_true((entry.reason as String).contains("max_mass"))
			found = true
	assert_true(found, "the plate must show up as illegal once nothing fits the budget")


func test_validate_reports_the_same_violations_as_deep_strikes_own_check() -> void:
	var controller := BuilderController.new()
	controller.loadout = DeepStrike.default_loadout()
	var unit: Unit = controller.assemble()

	var report: Dictionary = controller.validate(unit)

	assert_eq(report.mass, unit.shell.carried_mass())
	assert_eq(report.ram, unit.shell.total_ram())
	assert_eq(report.armed, DeepStrike.is_armed(unit))
	assert_eq(report.violations, DeepStrike.validate_assembly(unit))


func test_load_from_unit_reproduces_the_same_assembly_on_the_next_build() -> void:
	var reference: Unit = DeepStrike.assemble_reference_humanoid(Matrix.new(), Vector2i.ZERO)
	var controller := BuilderController.new()

	controller.load_from_unit(reference)
	var rebuilt: Unit = controller.assemble()

	var reference_ids: Array[StringName] = []
	for part: Part in reference.shell.all_parts():
		reference_ids.append(part.id)
	var rebuilt_ids: Array[StringName] = []
	for part: Part in rebuilt.shell.all_parts():
		rebuilt_ids.append(part.id)
	assert_eq(rebuilt_ids, reference_ids)


## docs/10 taskblock05 G5: "a preset round-trips: save -> load -> assemble
## -> structurally identical." Never touches a serialized Unit — only
## template+loadout+pose — so the round trip proves that data alone is
## enough to reproduce the same assembly.
func test_a_preset_round_trips_through_save_and_load() -> void:
	var controller := BuilderController.new()
	controller.loadout = DeepStrike.default_loadout()
	var original: Unit = controller.assemble()

	var preset_name: String = "test_preset_%d" % Time.get_ticks_usec()
	var preset: BotPreset = controller.to_preset(preset_name)
	assert_eq(BotPreset.save(preset), OK)

	var loaded: BotPreset = BotPreset.load_preset(preset_name)
	assert_not_null(loaded)
	var reloaded_controller := BuilderController.new()
	reloaded_controller.apply_preset(loaded)
	var rebuilt: Unit = reloaded_controller.assemble()

	var original_ids: Array[StringName] = []
	for part: Part in original.shell.all_parts():
		original_ids.append(part.id)
	var rebuilt_ids: Array[StringName] = []
	for part: Part in rebuilt.shell.all_parts():
		rebuilt_ids.append(part.id)
	assert_eq(rebuilt_ids, original_ids)

	BotPreset.delete(preset_name)


## "Send to Battle" produces a unit identical to the previewed one" — since
## both are just assemble() called again against the same controller
## state, this is the same guarantee test_assemble_produces_a_unit_
## structurally_identical_to_code already proves; asserted here from the
## angle of "call it twice, get the same shape," the actual contract a
## preview-then-send flow depends on.
func test_calling_assemble_twice_produces_the_same_shape_each_time() -> void:
	var controller := BuilderController.new()
	controller.loadout = DeepStrike.default_loadout()

	var previewed: Unit = controller.assemble()
	var sent: Unit = controller.assemble()

	var previewed_ids: Array[StringName] = []
	for part: Part in previewed.shell.all_parts():
		previewed_ids.append(part.id)
	var sent_ids: Array[StringName] = []
	for part: Part in sent.shell.all_parts():
		sent_ids.append(part.id)
	assert_eq(sent_ids, previewed_ids)
