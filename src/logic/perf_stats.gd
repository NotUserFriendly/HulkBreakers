class_name PerfStats
extends RefCounted

## taskblock-51: **the performance numbers, computed where they can be tested.**
##
## The supervisor's own framing, and it is the reason this exists:
##
## > *"Uncapped, framerate even in debug could easily be in the 1000s of frames per second.
## > Because of this, averages are almost useless. Lag drops to 8 fps, but when it isn't
## > lagging it's topping out the meter. So the average gives very reasonable framerates,
## > despite it feeling terrible."*
##
## Taskblock-51 proved that the hard way: one session read **min 7.5, avg 140.1**, and the
## average was the number that lied. Four framerate defects were found in that block and the
## mean never once pointed at any of them.
##
## ## The four figures, and exactly what each means
##
## - **Instant** — the last frame's own rate, `1 / delta`. Noisy by nature; it is the one
##   that moves when you move the mouse.
## - **Rolling** — a true rate over the last `ROLLING_WINDOW_SECONDS`, republished on that
##   same cadence rather than every frame. Frames divided by seconds, never a mean of rates
##   (`FpsMeter`'s own header explains why that distinction matters).
## - **1% low** — **the mean of the slowest 1% of frames**, which is the hardware-review
##   statistic. Not the 99th-percentile frame itself; the supervisor asked for the common
##   reading and this is it.
## - **Average dropping the top 1%** — the mean of every frame **below `0.99 × the fastest
##   frame seen`**. The cut is on *speed*, not on a count of entries: on the supervisor's
##   own example — 100 frames at 10 fps, 20 at 159, 30 at 160 — the cut lands at 158.4, both
##   fast groups fall away, and the figure reads **10 fps** rather than ~40.
##
## Reported beside that last one is **what fraction of frames survived the cut**, because a
## number computed from 15% of the data should say so.
##
## ## Cost, since this is a performance tool
##
## `sample()` is an append and two comparisons. **Nothing sorts per frame** — the derived
## figures are computed only when asked, which the panel does once per rolling tick. A
## profiler that costs frames measures its own overhead.

## The rolling window, and the republish cadence — deliberately the same number, per the
## supervisor's "avg of last 2 seconds, updated every 2 seconds".
const ROLLING_WINDOW_SECONDS := 2.0

## The fastest 1% of *speeds* are dropped: anything at or above `(1 - TOP_BAND) * max`.
const TOP_BAND := 0.01

## The slowest 1% of frames make up the 1% low.
const LOW_FRACTION := 0.01

## Below this many frames a 1% figure is arithmetic theatre — 1% of 40 frames is a single
## sample dressed up as a statistic. Readers get `UNAVAILABLE` until there is enough.
const MIN_SAMPLES := 100

## A long session at 160 fps is ~10 000 frames a minute. The cap keeps a forgotten panel
## from growing without bound; when it is hit the **oldest** frames go, so the figures
## describe recent play rather than a session that started an hour ago.
const MAX_SAMPLES := 240000

## Returned by any figure that does not have the data to be honest yet.
const UNAVAILABLE := -1.0

var _fps: PackedFloat32Array = PackedFloat32Array()
var _fastest: float = 0.0
var _slowest: float = 0.0
var _instant: float = 0.0
var _rolling: float = UNAVAILABLE
var _window_seconds: float = 0.0
var _window_frames: int = 0


## Feed one frame. **Returns `true` on the frame that completes a rolling window**, so a
## caller wanting to report on that cadence has one without running a second timer.
func sample(delta: float) -> bool:
	if delta <= 0.0:
		# A zero or negative delta is not a frame that happened — `FpsMeter` drops these
		# rather than clamping them, and a clamped 1/0 would be the fastest frame ever
		# recorded, which would then define the top-1% cut for the whole session.
		return false
	var fps: float = 1.0 / delta
	_instant = fps
	if _fps.size() >= MAX_SAMPLES:
		_fps.remove_at(0)
	_fps.append(fps)
	if fps > _fastest:
		_fastest = fps
	if _slowest <= 0.0 or fps < _slowest:
		_slowest = fps
	_window_seconds += delta
	_window_frames += 1
	# **Epsilon, and the remainder carries.** 120 frames of `1.0/60.0` sum to 1.999999…, so
	# a bare `>= 2.0` never fires and the window silently stretches — six seconds reported
	# two ticks instead of three. Subtracting the window rather than zeroing keeps the
	# cadence from drifting later by the overshoot it would otherwise discard.
	if _window_seconds < ROLLING_WINDOW_SECONDS - 0.000001:
		return false
	_rolling = float(_window_frames) / _window_seconds
	_window_seconds = maxf(0.0, _window_seconds - ROLLING_WINDOW_SECONDS)
	_window_frames = 0
	return true


func instant() -> float:
	return _instant


## `UNAVAILABLE` until the first window closes — a rolling figure over half a window is not
## the thing it claims to be.
func rolling() -> float:
	return _rolling


func sample_count() -> int:
	return _fps.size()


## The mean of the slowest 1% of frames.
func one_percent_low() -> float:
	if _fps.size() < MIN_SAMPLES:
		return UNAVAILABLE
	var sorted: Array[float] = _sorted_ascending()
	var take: int = maxi(1, int(floor(float(sorted.size()) * LOW_FRACTION)))
	var total := 0.0
	for i in range(take):
		total += sorted[i]
	return total / float(take)


## The mean of every frame slower than `(1 - TOP_BAND)` of the fastest frame seen.
##
## **When nothing is dropped, the plain mean is the honest answer.** A framerate that never
## varied has no fast outliers masking anything, and reporting `UNAVAILABLE` there would
## hide a genuinely healthy result behind a caveat.
func average_dropping_top() -> float:
	if _fps.is_empty():
		return UNAVAILABLE
	var cut: float = _fastest * (1.0 - TOP_BAND)
	var total := 0.0
	var kept := 0
	for fps: float in _fps:
		if fps < cut:
			total += fps
			kept += 1
	if kept == 0:
		return _mean_of_all()
	return total / float(kept)


## The fraction of frames that survived the top-1% cut, as 0..1. **A number computed from
## 15% of the data should say so**, which is what the supervisor asked for with "Reporting
## 85% of Frames".
func reporting_fraction() -> float:
	if _fps.is_empty():
		return 0.0
	var cut: float = _fastest * (1.0 - TOP_BAND)
	var kept := 0
	for fps: float in _fps:
		if fps < cut:
			kept += 1
	# Nothing dropped means everything is being reported on — see `average_dropping_top`.
	return 1.0 if kept == 0 else float(kept) / float(_fps.size())


func fastest() -> float:
	return _fastest


## The single worst frame. **Kept alongside the 1% low rather than replaced by it**: the
## supervisor has been reading a session minimum all through taskblock-51 and it is the
## figure that matched what they were feeling. The 1% low is the better statistic; the
## minimum is the one that says "something stalled hard, once".
func slowest() -> float:
	return _slowest if _slowest > 0.0 else UNAVAILABLE


func reset() -> void:
	_fps = PackedFloat32Array()
	_fastest = 0.0
	_slowest = 0.0
	_instant = 0.0
	_rolling = UNAVAILABLE
	_window_seconds = 0.0
	_window_frames = 0


## One line per figure, in the order the panel shows them — shared so the panel and the
## combat-log dump cannot drift into two different descriptions of one measurement.
func describe() -> Array[String]:
	return [
		"instant %s" % _format(_instant),
		"rolling %ds %s" % [int(ROLLING_WINDOW_SECONDS), _format(_rolling)],
		"min %s" % _format(slowest()),
		"1%% low %s" % _format(one_percent_low()),
		(
			"avg less top 1%% %s (reporting %d%% of %d frames)"
			% [
				_format(average_dropping_top()),
				int(round(reporting_fraction() * 100.0)),
				_fps.size(),
			]
		),
	]


## The same figures as data, for a `LogEvent` that something later wants to read back
## without parsing prose.
func snapshot() -> Dictionary:
	return {
		"instant": _instant,
		"rolling": _rolling,
		"slowest": slowest(),
		"one_percent_low": one_percent_low(),
		"avg_less_top": average_dropping_top(),
		"reporting": reporting_fraction(),
		"frames": _fps.size(),
		"fastest": _fastest,
	}


static func _format(value: float) -> String:
	return "--" if value == UNAVAILABLE else "%.1f" % value


func _mean_of_all() -> float:
	var total := 0.0
	for fps: float in _fps:
		total += fps
	return total / float(_fps.size())


func _sorted_ascending() -> Array[float]:
	var out: Array[float] = []
	for fps: float in _fps:
		out.append(fps)
	out.sort()
	return out
