extends GutTest

## taskblock-57 Pass C — **the two rules behind Pass C's behaviours, as arithmetic.**
##
## Both are things the taskblock states as UI behaviour and both have a decidable core, so the core
## lives in `src/logic` and is asserted here without a window:
##
## - `HoverDwell` — 1.5 s motionless, **one timer shared by two behaviours**. Tested by advancing an
##   explicit delta, never by sleeping.
## - `TurnEndPrompt` — whether ending a turn would waste AP or MP, and what the dialog says about
##   it. The prompt is a `ConfirmationDialog`; whether there is anything to prompt about is this.

# ---------------------------------------------------------------- the shared dwell


## The delay is the taskblock's stated number, not a leftover tuning value. Asserted directly
## because it was 0.4 s before this pass and a silent regression to a "feels about right" number is
## exactly what a specified value exists to prevent.
func test_the_dwell_is_the_specified_one_and_a_half_seconds() -> void:
	assert_almost_eq(HoverDwell.DELAY_SEC, 1.5, 0.0001, "the taskblock specifies 1.5 s")
	assert_almost_eq(
		TooltipView.HOVER_DELAY_SEC,
		HoverDwell.DELAY_SEC,
		0.0001,
		"the tooltip must read the shared clock, not keep a second number"
	)


## **Fires once, on the tick it crosses**, so an expensive reveal happens once rather than every
## frame for as long as the cursor sits still.
func test_it_fires_exactly_once_when_the_delay_is_crossed() -> void:
	var dwell := HoverDwell.new()
	dwell.aim_at("a button")

	assert_false(dwell.tick(HoverDwell.DELAY_SEC * 0.5), "half way is not there yet")
	assert_true(dwell.pending, "and it is still waiting")
	assert_true(dwell.tick(HoverDwell.DELAY_SEC * 0.5 + 0.001), "crossing it fires")
	assert_true(dwell.fired)
	assert_false(dwell.tick(1.0), "and it does not fire again while nothing has changed")


## **A repeated aim at the same target does not restart the wait.** This is taskblock-08 D1's rule —
## a tooltip follows the cursor across one button rather than resetting every frame — and it is the
## reason `aim_at` takes a target rather than a position.
func test_aiming_at_the_same_target_does_not_restart_the_clock() -> void:
	var dwell := HoverDwell.new()
	dwell.aim_at("a button")
	dwell.tick(HoverDwell.DELAY_SEC - 0.1)
	dwell.aim_at("a button")

	assert_true(dwell.tick(0.101), "the wait carried on rather than starting over")


func test_aiming_at_a_new_target_starts_the_wait_again() -> void:
	var dwell := HoverDwell.new()
	dwell.aim_at("a button")
	dwell.tick(HoverDwell.DELAY_SEC - 0.1)
	dwell.aim_at("a different button")

	assert_false(dwell.tick(0.101), "a new target waits the full delay")
	assert_almost_eq(dwell.elapsed, 0.101, 0.0001, "the clock restarted")


func test_cancelling_clears_both_the_wait_and_the_reveal() -> void:
	var dwell := HoverDwell.new()
	dwell.aim_at(3)
	dwell.tick(HoverDwell.DELAY_SEC + 0.1)
	assert_true(dwell.fired)

	dwell.cancel()

	assert_false(dwell.fired)
	assert_false(dwell.pending)
	assert_null(dwell.target())


## **Two callers, one clock, and neither can drift from the other.** The point of the class rather
## than a shared constant: two independent accumulate-and-compare loops agree until one of them
## forgets to reset.
func test_two_independent_dwells_agree_on_when_to_fire() -> void:
	var tooltip := HoverDwell.new()
	var preview := HoverDwell.new()
	tooltip.aim_at("End Turn")
	preview.aim_at(7)

	for i in range(15):
		var a: bool = tooltip.tick(0.1)
		var b: bool = preview.tick(0.1)
		assert_eq(a, b, "the two behaviours must fire on the same tick (step %d)" % i)


# ---------------------------------------------------------------- ending a turn with something left


func _unit(ap: int, mp: float) -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	var unit := Unit.new(Matrix.new(), Shell.new(torso), Vector2i.ZERO, 0)
	unit.ap = ap
	unit.mp = mp
	return unit


func test_a_spent_unit_ends_its_turn_without_being_asked() -> void:
	assert_false(TurnEndPrompt.should_confirm(_unit(0, 0.0)), "nothing left, nothing to ask about")


func test_unspent_ap_or_mp_each_raise_the_prompt_on_their_own() -> void:
	assert_true(TurnEndPrompt.should_confirm(_unit(1, 0.0)), "AP alone is worth asking about")
	assert_true(TurnEndPrompt.should_confirm(_unit(0, 2.5)), "and so is MP alone")


## Float residue is not unspent movement. Without this, arithmetic noise would raise a dialog on a
## unit that has genuinely moved everywhere it can — and a confirmation that fires when it should
## not is one players learn to click through without reading.
func test_floating_point_residue_does_not_raise_a_prompt() -> void:
	assert_false(
		TurnEndPrompt.should_confirm(_unit(0, TurnEndPrompt.MP_EPSILON * 0.5)),
		"1e-7 of MP is arithmetic noise, not movement"
	)
	assert_true(
		TurnEndPrompt.should_confirm(_unit(0, TurnEndPrompt.MP_EPSILON * 10.0)),
		"but real leftover movement still asks"
	)


func test_a_null_selection_is_a_real_state_and_never_asks() -> void:
	assert_false(TurnEndPrompt.should_confirm(null))
	assert_eq(TurnEndPrompt.message(null), "")


## **The message says only what is actually left**, and it comes from the same call that decided to
## ask — `docs/08`: the number shown is the number computed.
func test_the_message_names_exactly_what_is_unspent() -> void:
	var ap_only: String = TurnEndPrompt.message(_unit(2, 0.0))
	gut.p("ap only: %s" % ap_only)
	assert_true(ap_only.contains("2 AP"), "it says how much AP")
	assert_false(ap_only.contains("MP"), "and does not mention MP the unit does not have")

	var both: String = TurnEndPrompt.message(_unit(1, 3.0))
	gut.p("both: %s" % both)
	assert_true(both.contains("1 AP") and both.contains("3.0 MP"), "both, when both are left")


# ------------------------------------------------------------- which log line is under the cursor


func test_the_line_under_a_point_is_the_last_one_starting_at_or_above_it() -> void:
	var offsets := PackedFloat32Array([0.0, 20.0, 40.0, 60.0])
	assert_eq(LogLineProbe.line_at(offsets, 0.0), 0, "exactly on the first line's top")
	assert_eq(LogLineProbe.line_at(offsets, 19.9), 0, "still inside the first line")
	assert_eq(LogLineProbe.line_at(offsets, 20.0), 1, "the next line's top belongs to that line")
	assert_eq(LogLineProbe.line_at(offsets, 1000.0), 3, "past the end is the last line")


## **-1 rather than a clamp.** "The cursor is not on a line" is a real answer; clamping it to line 0
## would reveal the top line whenever the cursor sat in the padding above the text.
func test_a_point_above_the_first_line_is_on_no_line_at_all() -> void:
	assert_eq(LogLineProbe.line_at(PackedFloat32Array([10.0, 30.0]), 4.0), -1)
	assert_eq(LogLineProbe.line_at(PackedFloat32Array(), 0.0), -1, "and an empty log has no lines")


func test_a_line_overflows_only_when_it_is_genuinely_wider_than_the_view() -> void:
	assert_true(LogLineProbe.overflows(600.0, 520.0), "80 px cut off is cut off")
	assert_false(LogLineProbe.overflows(520.0, 520.0), "exactly fitting is not overflow")
	assert_false(
		LogLineProbe.overflows(520.0 + LogLineProbe.OVERFLOW_EPSILON * 0.5, 520.0),
		"and hinting slack must not flicker a preview over readable text"
	)


## Bounds-checked, because the offsets and the text are two separate reads off a live label and a
## render landing between them would otherwise index past the end.
func test_reading_a_line_outside_the_text_is_empty_rather_than_an_error() -> void:
	var lines := PackedStringArray(["first", "second"])
	assert_eq(LogLineProbe.text_of(lines, 1), "second")
	assert_eq(LogLineProbe.text_of(lines, 2), "")
	assert_eq(LogLineProbe.text_of(lines, -1), "")
