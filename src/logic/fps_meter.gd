class_name FpsMeter
extends RefCounted

## taskblock-41 Pass F: the arithmetic behind the on-screen FPS readout —
## instantaneous AND a rolling average over a short window. Pure logic, no
## SceneTree: there is no real framerate headless, but "given these frame
## deltas, what does the readout say" is exactly the kind of rule that must be
## testable without rendering (CLAUDE.md's own golden rule).
##
## ## This is SUPPOSED to disagree with `FpsDumpSink`
## `FpsDumpSink` samples deliberately LATE — a fixed delay after `turn_start`,
## past the turn-boundary hitch and into settled steady state — because it
## answers "is the game slow in general," for CC to grep out of `combat.log`.
## This answers the opposite question: it shows the hitch AS IT HAPPENS, for a
## human watching the screen.
##
## **The divergence is intended and must not be reconciled.** When the two
## agree, that is a positive indicator. When they disagree, the disagreement is
## itself the clue — the gap between them measures transient cost that neither
## number shows alone. Do not "fix" the discrepancy; see docs/09.

## The rolling window, in seconds. One second is a reasonable starting point —
## long enough to be readable, short enough that a real hitch still moves it.
## Flagged and tunable (CLAUDE.md: never invent a final balance number).
const DEFAULT_WINDOW_SECONDS := 1.0
## A delta of zero (or worse) would divide by zero on the way to a frame rate.
## Dropped rather than clamped: a zero-length frame is a measurement error, and
## inventing a rate for it would quietly bias the average.
const MIN_VALID_DELTA := 0.000001

var window_seconds: float

## Frame deltas inside the current window, oldest first, with their running
## total kept alongside so `average()` never re-walks the whole window.
var _deltas: Array[float] = []
var _window_total := 0.0
var _last_delta := 0.0


func _init(p_window_seconds: float = DEFAULT_WINDOW_SECONDS) -> void:
	window_seconds = p_window_seconds


## Feeds one frame's delta. Deltas older than `window_seconds` fall out the
## back, so the average always describes the last second of real time rather
## than the last N frames — at 5 FPS and at 500 FPS it means the same thing.
func sample(delta: float) -> void:
	if delta < MIN_VALID_DELTA:
		return
	_last_delta = delta
	_deltas.append(delta)
	_window_total += delta
	while _deltas.size() > 1 and _window_total - _deltas[0] >= window_seconds:
		_window_total -= _deltas[0]
		_deltas.remove_at(0)


## The most recent frame's rate. This is the number that spikes on a hitch —
## the whole reason a continuous readout exists alongside the dumps.
func instantaneous() -> float:
	return 0.0 if _last_delta < MIN_VALID_DELTA else 1.0 / _last_delta


## Frames per second across the window: frame COUNT over elapsed time, not the
## mean of per-frame rates. Those differ, and only this one is a frame rate —
## averaging rates over-weights short frames and would read high exactly when
## a hitch made it matter.
func average() -> float:
	if _deltas.is_empty() or _window_total < MIN_VALID_DELTA:
		return 0.0
	return _deltas.size() / _window_total


func sample_count() -> int:
	return _deltas.size()


func reset() -> void:
	_deltas.clear()
	_window_total = 0.0
	_last_delta = 0.0


## What the readout draws. Both numbers, always — a single blended figure would
## hide precisely the gap this is for.
func readout_text() -> String:
	return "%.0f FPS (avg %.0f)" % [instantaneous(), average()]
