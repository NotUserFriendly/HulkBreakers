extends GutTest

## taskblock-51: the performance figures.
##
## Every case here is arithmetic the supervisor can check by hand, which is the point — a
## statistic nobody can verify is a statistic nobody will trust when it disagrees with what
## they are feeling. Taskblock-51 spent four passes with an instrument that was wrong.


func _feed(stats: PerfStats, fps: float, count: int) -> void:
	for i in range(count):
		stats.sample(1.0 / fps)


## **The supervisor's own worked example, verbatim.**
##
## > *"if you have a framerate with 100 x 10fps entries, 20 x 159fps entries, and 30 x
## > 160fps entries, then you end up with an average of 10fps, instead of ~40fps."*
##
## The cut is on speed, not on a count of entries: 1% of 160 is 158.4, so both fast groups
## fall away and only the hundred slow frames are averaged.
func test_the_supervisors_worked_example_reads_ten_not_forty() -> void:
	var stats := PerfStats.new()
	_feed(stats, 10.0, 100)
	_feed(stats, 159.0, 20)
	_feed(stats, 160.0, 30)

	assert_almost_eq(stats.average_dropping_top(), 10.0, 0.05, "the fast frames are dropped")

	# **The supervisor's example said the plain mean would read "~40fps"; it is 59.9.** The
	# conclusion they drew from it — that the plain mean is useless and this figure is not —
	# holds either way, and holds harder: the mean overstates by 6x here, not 4x.
	var plain: float = (10.0 * 100 + 159.0 * 20 + 160.0 * 30) / 150.0
	gut.p("plain mean would have read %.1f fps against this figure's 10.0" % plain)
	assert_almost_eq(plain, 59.9, 0.1, "the mean this replaces")


## And it says how much of the data it used, because 100 of 150 frames is a real caveat.
func test_it_reports_what_fraction_of_frames_it_kept() -> void:
	var stats := PerfStats.new()
	_feed(stats, 10.0, 100)
	_feed(stats, 160.0, 50)

	assert_almost_eq(stats.reporting_fraction(), 100.0 / 150.0, 0.001, "100 of 150 frames")


## **The cut is 99% of the fastest frame** — the supervisor chose this over a
## proportion-of-range reading, and the two differ once the spread is narrow.
func test_the_cut_sits_at_ninety_nine_percent_of_the_fastest_frame() -> void:
	var stats := PerfStats.new()
	_feed(stats, 150.0, 10)
	_feed(stats, 159.0, 10)
	_feed(stats, 160.0, 10)

	# 0.99 x 160 = 158.4, so 159 and 160 go and 150 stays — a range-based reading would
	# have kept the 159s.
	assert_almost_eq(stats.average_dropping_top(), 150.0, 0.05)


## A flat framerate has no fast outliers masking anything, so the plain mean is the honest
## answer rather than a caveat about having dropped everything.
func test_a_perfectly_steady_framerate_reports_its_own_average() -> void:
	var stats := PerfStats.new()
	_feed(stats, 120.0, 200)

	assert_almost_eq(stats.average_dropping_top(), 120.0, 0.05)
	assert_almost_eq(stats.reporting_fraction(), 1.0, 0.001, "nothing was dropped")


## **The 1% low is the mean of the slowest 1%**, not the boundary frame — the supervisor
## asked for the common hardware-review reading and confirmed which one.
func test_the_one_percent_low_averages_the_slowest_one_percent() -> void:
	var stats := PerfStats.new()
	_feed(stats, 5.0, 5)
	_feed(stats, 15.0, 5)
	_feed(stats, 160.0, 990)

	# 1% of 1000 frames is 10: the five 5s and the five 15s, averaging 10.
	assert_almost_eq(stats.one_percent_low(), 10.0, 0.05)


## 1% of forty frames is one sample wearing a statistic's clothes. Better to say nothing.
func test_a_one_percent_figure_waits_for_enough_frames() -> void:
	var stats := PerfStats.new()
	_feed(stats, 60.0, PerfStats.MIN_SAMPLES - 1)

	assert_eq(stats.one_percent_low(), PerfStats.UNAVAILABLE, "not enough frames to be honest")

	stats.sample(1.0 / 60.0)

	assert_ne(stats.one_percent_low(), PerfStats.UNAVAILABLE, "and it reports once there are")


## **Rolling is a real rate over the window** — frames divided by seconds, republished on
## the same cadence rather than every frame.
func test_rolling_publishes_once_per_window_as_a_real_rate() -> void:
	var stats := PerfStats.new()
	assert_eq(stats.rolling(), PerfStats.UNAVAILABLE, "nothing to report before a window closes")

	var ticked := false
	for i in range(120):
		ticked = stats.sample(1.0 / 60.0) or ticked

	assert_true(ticked, "two seconds at 60 fps closes a window")
	assert_almost_eq(stats.rolling(), 60.0, 1.0)


## The tick is what a caller uses to report on cadence, so it must fire on the window
## boundary and not on every frame after it.
func test_the_window_tick_fires_once_per_window() -> void:
	var stats := PerfStats.new()
	var ticks := 0
	for i in range(360):
		if stats.sample(1.0 / 60.0):
			ticks += 1

	assert_eq(ticks, 3, "six seconds is three two-second windows")


## **A zero delta is not a frame.** Clamping it would record the fastest frame ever seen,
## and that frame would then define the top-1% cut for the rest of the session.
func test_a_zero_delta_is_dropped_rather_than_clamped() -> void:
	var stats := PerfStats.new()
	_feed(stats, 100.0, 10)

	assert_false(stats.sample(0.0), "a zero delta is not a frame")
	assert_eq(stats.sample_count(), 10)
	assert_almost_eq(stats.fastest(), 100.0, 0.05, "and it did not become the fastest frame")


func test_reset_clears_every_figure() -> void:
	var stats := PerfStats.new()
	_feed(stats, 30.0, 300)

	stats.reset()

	assert_eq(stats.sample_count(), 0)
	assert_eq(stats.rolling(), PerfStats.UNAVAILABLE)
	assert_eq(stats.one_percent_low(), PerfStats.UNAVAILABLE)
	assert_almost_eq(stats.fastest(), 0.0, 0.001, "the fastest frame goes too — it sets the cut")


## The prose and the data must describe one measurement, not two.
func test_the_readout_and_the_snapshot_agree() -> void:
	var stats := PerfStats.new()
	_feed(stats, 20.0, 150)

	var snapshot: Dictionary = stats.snapshot()
	var lines: Array[String] = stats.describe()

	assert_eq(lines.size(), 6, "one line per figure, plus the catch-up read")
	assert_eq(int(snapshot["frames"]), 150)
	assert_true(lines[4].contains("150 frames"), "the readout states its own sample size")
	assert_almost_eq(float(snapshot["slowest"]), 20.0, 0.05, "the worst frame is carried too")


## **The supervisor's catch-up hypothesis, made answerable.**
##
## > *"Is it queuing frames for some reason, and when those finally get to hit, they run over?"*
##
## A frame that takes almost no time because the previous one overran reports a huge
## `1 / delta`. That is bookkeeping, not throughput — and it is the reading that anchors the
## top-1% cut in `BR51.17`. The signature is adjacency, so the fastest frame is reported with
## the frames either side of it and the pattern reads straight off the dump.
func test_a_catch_up_frame_is_visible_by_what_precedes_it() -> void:
	var stats := PerfStats.new()
	_feed(stats, 160.0, 50)
	stats.sample(1.0 / 8.0)  # the stall
	stats.sample(1.0 / 2000.0)  # the frame that pays it back
	_feed(stats, 160.0, 50)

	var neighbourhood: Dictionary = stats.fastest_neighbourhood()

	gut.p(
		(
			"fastest %.1f, preceded by %.1f, followed by %.1f"
			% [neighbourhood["value"], neighbourhood["previous"], neighbourhood["next"]]
		)
	)
	assert_almost_eq(float(neighbourhood["value"]), 2000.0, 1.0)
	assert_almost_eq(float(neighbourhood["previous"]), 8.0, 0.1, "a stall sits right before it")
	assert_almost_eq(float(neighbourhood["next"]), 160.0, 1.0, "and normal service resumes")


## **The contrast case, so the reading means something.** The fastest frame of a healthy run is
## surrounded by frames like itself — that is what distinguishes it from a payback spike, and
## without this case the figure above could not tell the two apart.
func test_the_fastest_frame_of_a_steady_run_has_ordinary_neighbours() -> void:
	var stats := PerfStats.new()
	_feed(stats, 158.0, 40)
	stats.sample(1.0 / 161.0)
	_feed(stats, 159.0, 40)

	var neighbourhood: Dictionary = stats.fastest_neighbourhood()

	assert_almost_eq(float(neighbourhood["value"]), 161.0, 0.5)
	assert_almost_eq(float(neighbourhood["previous"]), 158.0, 0.5, "nothing stalled before it")


## A neighbour that does not exist reads as unavailable rather than as a zero-fps frame, which
## would be indistinguishable from a real stall.
func test_a_fastest_frame_at_the_edge_reports_no_neighbour() -> void:
	var stats := PerfStats.new()
	stats.sample(1.0 / 500.0)
	_feed(stats, 60.0, 5)

	var neighbourhood: Dictionary = stats.fastest_neighbourhood()

	assert_eq(float(neighbourhood["previous"]), PerfStats.UNAVAILABLE, "nothing came before it")
	assert_almost_eq(float(neighbourhood["next"]), 60.0, 0.5)


func test_the_readout_carries_the_fastest_frames_neighbourhood() -> void:
	var stats := PerfStats.new()
	_feed(stats, 60.0, 10)
	var lines: Array[String] = stats.describe()

	assert_eq(lines.size(), 6, "the sixth line is the catch-up read")
	assert_true(lines[5].contains("fastest"), lines[5])
