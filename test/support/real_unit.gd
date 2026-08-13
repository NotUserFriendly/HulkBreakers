class_name RealUnit
extends RefCounted

## taskblock-68 Pass A1: **the one place a test says "a real unit"**, so that the phrase means
## the same thing in every file that says it.
##
## ## Why this exists rather than three lines copied per file
##
## The three lines were already the canonical build — `DataLibrary.get_preset` +
## `DeepStrike.assemble_from_preset` — and two cost probes had them copied. The problem was
## never the copying. It was that **nothing checked what came back**, and a fixture that
## degenerates silently is indistinguishable from one that did not.
##
## The receipt is in the archive. The first version of `test_cutout_gate_cost_probe.gd`
## measured a body of **one `Box`**, reported **41 usec per unit**, and the supervisor's next
## live session came back at **13 fps**. `placements_aabb` costs eight corner transforms per
## box, so box count IS the cost, and a one-box fixture measured nothing that mattered. The
## whole suite was green throughout.
##
## ## The contract: it fails, it does not measure
##
## `build()` is the only constructor and it is checked. A degenerate assembly fails the
## calling test **by name**, at the point of construction, instead of being handed back for
## something to time. That is the entire point of the helper — a probe cannot report a figure
## taken against a stand-in, because it never receives one.
##
## `check()` is separated out so the failure path is itself testable: a spy `GutTest` can be
## handed a deliberately degenerate unit and asked whether it went red.
##
## ## What "real" is asserted to mean
##
## - **`DeepStrike.validate_assembly` reports no violations.** The game's own soundness check,
##   not a second copy of it — mass, RAM, bulk, geometry, material, and the matrix being docked
##   in the root all come from there.
## - **The box count is exactly `BOX_COUNT`.** `validate_assembly` cannot catch a one-box body:
##   a single torso with a docked matrix is a *sound* assembly. It is the count that was wrong,
##   so it is the count that is asserted.

## The preset every real-unit fixture is built from. A `GRUNT` chaingunner with a wedge torso
## plate, a leg plate and a chaingun in the right grip — the loadout the combat-tester presets
## were authored to be representative with, and the one the 48 below was measured against.
const PRESET_ID := &"combat_tester_chaingun"

## **48 boxes for an assembled `combat_tester_chaingun` shell** — quoted from `BUGS.md`'s
## `BR61.04` and the `BR32.05` archive entry, and re-measured at tb68 A1 against this helper's
## own build. If content moves it, this constant is a one-line correction carrying a new
## provenance tag; it is not an investigation.
const BOX_COUNT := 48


## The real unit, checked. `test` is the caller, so a degenerate assembly is a red test in the
## file that asked for one rather than a number in a log.
static func build(test: GutTest, cell := Vector2i.ZERO, squad_id: int = 0) -> Unit:
	var preset: BotPreset = DataLibrary.get_preset(PRESET_ID)
	var unit: Unit = null
	if preset != null:
		unit = DeepStrike.assemble_from_preset(preset, Matrix.new(), cell, squad_id)
	return check(test, unit)


## Fails `test` if `unit` is not a real assembled shell, then returns it either way — returning
## the bad unit is deliberate, because the test is already red and a `null` here would bury the
## named failure under a nil access on the next line.
static func check(test: GutTest, unit: Unit) -> Unit:
	var reason: String = degeneracy(unit)
	if reason != "":
		test.fail_test("RealUnit: not a real assembled shell — %s" % reason)
	return unit


## Empty if `unit` is a real assembled shell; otherwise why it is not, in one line.
static func degeneracy(unit: Unit) -> String:
	if unit == null:
		return (
			"assembly returned null (preset %s missing — has DataLibrary.load_all() run?)"
			% PRESET_ID
		)
	if unit.shell == null or unit.shell.root == null:
		return "unit has no shell root, so it has no geometry at all"

	var violations: Array[String] = DeepStrike.validate_assembly(unit)
	if not violations.is_empty():
		return "invalid assembly: %s" % ", ".join(violations)

	# The check `validate_assembly` cannot make: a one-box torso with a matrix docked in it is
	# a perfectly SOUND assembly, and it is what measured 41 usec and shipped 13 fps.
	var boxes: int = UnitGeometry.placements(unit).size()
	if boxes != BOX_COUNT:
		return (
			"body is %d boxes, not %d — a stand-in this size measures nothing that matters"
			% [boxes, BOX_COUNT]
		)
	return ""
