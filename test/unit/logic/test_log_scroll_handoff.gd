extends GutTest

## taskblock-41 Pass F: the scroll hand-off threshold. A panel that always
## consumes the wheel turns "I scrolled to the bottom and kept scrolling" into
## a dead zone over part of the screen, and the next thing the player concludes
## is that zoom is broken.

const UP := LogScrollHandoff.Direction.UP
const DOWN := LogScrollHandoff.Direction.DOWN


func test_mid_content_the_log_takes_the_wheel_in_both_directions() -> void:
	assert_true(LogScrollHandoff.consumes(UP, 50.0, 200.0, 100.0))
	assert_true(LogScrollHandoff.consumes(DOWN, 50.0, 200.0, 100.0))


func test_at_the_top_scrolling_up_falls_through_but_down_still_scrolls() -> void:
	assert_false(LogScrollHandoff.consumes(UP, 0.0, 200.0, 100.0), "nothing above — hand off")
	assert_true(LogScrollHandoff.consumes(DOWN, 0.0, 200.0, 100.0), "but there is content below")


## The bottom is `max_value - page`, not `max_value` — a scrollbar never
## reaches its own max_value. Getting this wrong makes the hand-off fire a
## page early, which reads as the log refusing to scroll the last screenful.
func test_at_the_bottom_scrolling_down_falls_through_but_up_still_scrolls() -> void:
	assert_false(LogScrollHandoff.consumes(DOWN, 100.0, 200.0, 100.0), "nothing below — hand off")
	assert_true(LogScrollHandoff.consumes(UP, 100.0, 200.0, 100.0))


func test_one_line_short_of_the_bottom_still_belongs_to_the_log() -> void:
	assert_true(
		LogScrollHandoff.consumes(DOWN, 99.0, 200.0, 100.0),
		"the bottom is max_value - page (100), so 99 is still inside the content"
	)


## A nearly-empty log has nothing to scroll, so every wheel event is the
## camera's — otherwise it silently eats the wheel over its own rect.
func test_content_shorter_than_the_viewport_never_consumes() -> void:
	assert_false(LogScrollHandoff.consumes(UP, 0.0, 40.0, 100.0))
	assert_false(LogScrollHandoff.consumes(DOWN, 0.0, 40.0, 100.0))
	assert_false(LogScrollHandoff.consumes(DOWN, 0.0, 100.0, 100.0), "exactly full is still full")


func test_a_null_scrollbar_hands_off_rather_than_crashing() -> void:
	assert_false(LogScrollHandoff.consumes_scrollbar(DOWN, null))


## Read against a real ScrollBar, not a second copy of the same arithmetic.
func test_it_reads_a_real_scrollbar_the_same_way() -> void:
	var bar := VScrollBar.new()
	autofree(bar)
	bar.min_value = 0.0
	bar.max_value = 200.0
	bar.page = 100.0
	bar.value = 0.0

	assert_false(LogScrollHandoff.consumes_scrollbar(UP, bar), "at the top")
	assert_true(LogScrollHandoff.consumes_scrollbar(DOWN, bar))

	bar.value = bar.max_value - bar.page
	assert_true(LogScrollHandoff.consumes_scrollbar(UP, bar))
	assert_false(LogScrollHandoff.consumes_scrollbar(DOWN, bar), "at the bottom")
