extends GutTest

## taskblock-41 Pass F: there is no real framerate headless, but "given these
## frame deltas, what does the readout say" is ordinary arithmetic and belongs
## in a test rather than on screen only.


func test_instantaneous_is_the_last_frames_own_rate() -> void:
	var meter := FpsMeter.new()
	meter.sample(1.0 / 60.0)
	assert_almost_eq(meter.instantaneous(), 60.0, 0.01)

	meter.sample(1.0 / 10.0)
	assert_almost_eq(meter.instantaneous(), 10.0, 0.01, "the hitch shows immediately")


## The average is frame COUNT over elapsed time, not the mean of per-frame
## rates. Averaging rates over-weights short frames and would read high exactly
## when a hitch made it matter — so this pins the difference explicitly.
func test_the_average_is_a_real_frame_rate_not_a_mean_of_rates() -> void:
	var meter := FpsMeter.new()
	# Nine 120 FPS frames and one 10 FPS frame: 9/120 + 1/10 = 0.175s for 10
	# frames, so ~57 FPS. The mean of the RATES would be ~109 — nearly double,
	# and wrong.
	for _i in range(9):
		meter.sample(1.0 / 120.0)
	meter.sample(1.0 / 10.0)

	assert_almost_eq(meter.average(), 57.14, 0.5)
	assert_true(meter.average() < 70.0, "a mean-of-rates would read ~109 here")


func test_samples_older_than_the_window_fall_out() -> void:
	var meter := FpsMeter.new(1.0)
	# Two seconds of 100 FPS frames; only the last second may count.
	for _i in range(200):
		meter.sample(0.01)

	assert_almost_eq(meter.average(), 100.0, 1.0)
	assert_true(meter.sample_count() <= 101, "the window is time-bounded, not frame-bounded")


## At 5 FPS and at 500 FPS a one-second window must still mean one second.
func test_the_window_is_time_bounded_at_wildly_different_frame_rates() -> void:
	var slow := FpsMeter.new(1.0)
	for _i in range(20):
		slow.sample(0.2)  # 5 FPS, 4 seconds of it
	assert_almost_eq(slow.average(), 5.0, 0.5)
	assert_true(slow.sample_count() <= 6, "one second at 5 FPS is ~5 frames")

	var fast := FpsMeter.new(1.0)
	for _i in range(2000):
		fast.sample(0.002)  # 500 FPS
	assert_almost_eq(fast.average(), 500.0, 5.0)


## A zero delta would divide by zero on the way to a rate. Dropped rather than
## clamped: inventing a rate for a zero-length frame biases the average.
func test_a_zero_or_negative_delta_is_dropped_not_clamped() -> void:
	var meter := FpsMeter.new()
	meter.sample(1.0 / 60.0)
	var before: float = meter.average()

	meter.sample(0.0)
	meter.sample(-1.0)

	assert_eq(meter.sample_count(), 1, "neither bogus sample was recorded")
	assert_almost_eq(meter.average(), before, 0.001)
	assert_almost_eq(meter.instantaneous(), 60.0, 0.01, "and the last VALID frame still stands")


func test_a_meter_with_no_samples_reports_zero_rather_than_dividing_by_zero() -> void:
	var meter := FpsMeter.new()
	assert_eq(meter.instantaneous(), 0.0)
	assert_eq(meter.average(), 0.0)
	assert_eq(meter.sample_count(), 0)


## Both numbers are always shown. A single blended figure would hide exactly
## the gap between "right now" and "over the last second" that the readout
## exists to expose.
func test_the_readout_always_shows_both_numbers() -> void:
	var meter := FpsMeter.new()
	for _i in range(30):
		meter.sample(1.0 / 60.0)
	meter.sample(1.0 / 4.0)

	var text: String = meter.readout_text()
	assert_true(text.find("4 FPS") != -1, "the instantaneous hitch: %s" % text)
	assert_true(text.find("avg") != -1, "and the rolling average alongside it: %s" % text)


func test_reset_clears_the_window() -> void:
	var meter := FpsMeter.new()
	for _i in range(10):
		meter.sample(1.0 / 60.0)
	meter.reset()

	assert_eq(meter.sample_count(), 0)
	assert_eq(meter.average(), 0.0)
