extends GutTest

## taskblock-68 Pass A1: the guard on `RealUnit`, the support helper that decides what "a real
## unit" means for every headless measurement in the suite.
##
## **Two halves, and the second is the one that matters.** That the helper builds a 48-box
## chaingunner is easy and would stay true if the check were deleted. What has to be true is
## that the check **goes red** rather than handing a stand-in back to be timed — so the failure
## path is exercised directly, against a spy `GutTest` whose fail count can be read. Without
## that, this file would assert the helper works on the input it already works on, which is
## taskblock-50's vacuity class.


func before_each() -> void:
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## The one-box torso from `test_unit_geometry.gd` — the exact shape of fixture that reported
## 41 usec and shipped 13 fps.
##
## **It docks a matrix in a real MATRIX socket on purpose.** Without that, `validate_assembly`
## rejects it for the root not hosting the deep-struck matrix and the box-count branch is never
## reached — so the test would pass while proving nothing about the count. This is a *sound*
## one-box assembly: everything the game checks is satisfied, and it is still a stand-in.
func _one_box_unit() -> Unit:
	var socket := Socket.new()
	socket.socket_type = &"MATRIX"
	socket.id = &"MATRIX"

	# **Not `&"torso"`.** The census scans for fixtures that borrow a real part's id and then
	# disagree with the game's data about it, and this file's deliberate stand-in would sit in
	# that evidence table as three findings against itself.
	var torso := Part.new()
	torso.id = &"stand_in_torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.material = &"steel"
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	torso.sockets = [socket]

	var matrix := Matrix.new()
	assert_true(torso.dock_matrix(matrix), "the stand-in must be a SOUND one-box assembly")
	return Unit.new(matrix, Shell.new(torso), Vector2i(3, 4))


func test_build_returns_a_real_assembled_shell() -> void:
	var unit: Unit = RealUnit.build(self, Vector2i(5, 6))

	assert_not_null(unit, "the canonical build must produce a unit")
	assert_eq(unit.cell, Vector2i(5, 6), "built at the cell it was asked for")
	assert_eq(
		DeepStrike.validate_assembly(unit),
		[] as Array[String],
		"the game's own soundness check must pass on the helper's output"
	)
	assert_eq(
		UnitGeometry.placements(unit).size(),
		RealUnit.BOX_COUNT,
		"the assembled chaingunner's box count, the figure every cost probe rides on"
	)
	gut.p("real unit: %d boxes" % UnitGeometry.placements(unit).size())


## `BOX_COUNT` is quoted from `BR61.04`; this is the line that notices if content moved it.
func test_the_assembled_box_count_is_not_a_number_the_helper_invented() -> void:
	var preset: BotPreset = DataLibrary.get_preset(RealUnit.PRESET_ID)
	assert_not_null(preset, "the preset the helper names must exist in the data library")
	var unit: Unit = DeepStrike.assemble_from_preset(preset, Matrix.new(), Vector2i.ZERO, 0)
	assert_eq(
		UnitGeometry.placements(unit).size(),
		RealUnit.BOX_COUNT,
		"assembled straight from the preset, bypassing the helper entirely"
	)


func test_a_one_box_stand_in_is_reported_with_both_counts() -> void:
	var reason: String = RealUnit.degeneracy(_one_box_unit())

	assert_ne(reason, "", "a one-box body is exactly what this helper exists to refuse")
	assert_string_contains(reason, "1 boxes", "the reason names what it got")
	assert_string_contains(reason, str(RealUnit.BOX_COUNT), "and what a real shell is")


func test_a_real_unit_is_not_reported_as_degenerate() -> void:
	assert_eq(
		RealUnit.degeneracy(RealUnit.build(self, Vector2i.ZERO)),
		"",
		"the helper must not refuse its own output"
	)


func test_degeneracy_of_a_null_assembly_names_the_preset_that_did_not_resolve() -> void:
	var reason: String = RealUnit.degeneracy(null)

	assert_ne(reason, "", "a null assembly is degenerate")
	assert_string_contains(reason, str(RealUnit.PRESET_ID), "so the setup error is actionable")


## **The half that stops this file being vacuous.** `check()` is handed a stand-in and a spy
## test; the spy must go red. A helper that quietly returned the stand-in would pass every
## other test in this file.
func test_check_fails_the_calling_test_when_handed_a_stand_in() -> void:
	var spy: GutTest = autofree(GutTest.new())

	RealUnit.check(spy, _one_box_unit())

	assert_eq(spy.get_fail_count(), 1, "a degenerate unit must fail the test that asked for it")


func test_check_leaves_a_real_unit_alone() -> void:
	var spy: GutTest = autofree(GutTest.new())

	var unit: Unit = RealUnit.check(spy, RealUnit.build(self, Vector2i.ZERO))

	assert_eq(spy.get_fail_count(), 0, "a real assembled shell must not trip the check")
	assert_not_null(unit, "and must be handed straight back")


## Returning the bad unit rather than `null` is deliberate: the named failure is the signal, and
## a nil access on the caller's next line would bury it under an unrelated crash.
func test_check_returns_the_degenerate_unit_rather_than_null() -> void:
	var spy: GutTest = autofree(GutTest.new())
	var stand_in: Unit = _one_box_unit()

	assert_eq(RealUnit.check(spy, stand_in), stand_in, "the failure is the signal, not a null")
