class_name SuiteRunPanel
extends VBoxContainer

## taskblock-48 Pass B: **the window on the run.** Pick a rung, watch it go, kill it
## when you have seen enough.
##
## A panel rather than an overlay, for the same reason `WatchedRunPanel` is one: it
## has to be mountable under whichever overlay happens to be up, and subclassing an
## overlay to reuse its toolbar is how a hierarchy gets a sixth member.
##
## ## Sized as a calibration instrument
##
## The expectation is that the first few watched runs carry most of the value, after
## which this becomes a review step rather than a daily driver. **Built to that**: no
## run history, no charting, nothing persisted past the current run. Legible,
## killable, honest about what ran — and nothing else, because everything else is a
## guess about a usage pattern nobody has yet.
##
## ## Unmediated on purpose
##
## The feed is the real output of the real script. A curated list would be CC's own
## selection of what is worth watching, which makes it the wrong instrument for
## checking CC's work. **Filtering is a view over this feed, never a second source**,
## so it cannot drift from what actually happened — which is why `_filter` narrows
## what is drawn and never what is stored.

## How many lines the feed shows. A tail, not a scrollback: the interesting part of a
## running suite is always the end, and keeping the whole thing on screen would make
## the panel a log viewer instead of a status light.
const VISIBLE_LINES := 18
## How often the subprocess is polled, in seconds. Fast enough to read as live, slow
## enough that it is not doing a file seek every frame for a ten-minute run.
const POLL_INTERVAL := 0.25

var run: SuiteRun = null

var _status: Label = null
var _feed: Label = null
var _counts: Label = null
var _filter: String = ""
var _since_poll: float = 0.0


func _ready() -> void:
	_status = Label.new()
	add_child(_status)

	var buttons := HBoxContainer.new()
	add_child(buttons)
	for rung: StringName in SuiteRun.RUNGS:
		var button := Button.new()
		button.text = String(rung)
		button.pressed.connect(_start.bind(rung))
		buttons.add_child(button)
	var stop := Button.new()
	stop.text = "kill"
	stop.pressed.connect(_stop)
	buttons.add_child(stop)

	_counts = Label.new()
	add_child(_counts)
	_feed = Label.new()
	add_child(_feed)
	_refresh()


## Polled rather than signalled because the subprocess has nothing to signal with.
## **Stops polling the moment the run finishes**, so a finished panel costs nothing.
func _process(delta: float) -> void:
	if run == null or run.finished:
		return
	_since_poll += delta
	if _since_poll < POLL_INTERVAL:
		return
	_since_poll = 0.0
	run.poll()
	_refresh()


func _start(rung: StringName) -> void:
	run = SuiteRun.new()
	if not run.start(rung):
		_status.text = "could not launch — is run_tests.sh executable?"
		return
	_refresh()


func _stop() -> void:
	if run == null:
		return
	run.kill()
	run.poll()
	_refresh()


## Narrows what is **drawn**, never what is held. `run.lines` stays the unedited feed,
## so clearing the filter shows everything that happened rather than everything that
## happened since the filter was set.
func set_filter(text: String) -> void:
	_filter = text
	_refresh()


func visible_lines() -> Array[String]:
	if run == null:
		return []
	var shown: Array[String] = []
	for line: String in run.lines:
		if _filter == "" or line.contains(_filter):
			shown.append(line)
	if shown.size() <= VISIBLE_LINES:
		return shown
	return shown.slice(shown.size() - VISIBLE_LINES)


func _refresh() -> void:
	if _status == null:
		return
	_status.text = "no run started" if run == null else run.status_line()
	_feed.text = "\n".join(visible_lines())
	var counts: Dictionary = {} if run == null else run.work_counts()
	if counts.is_empty():
		_counts.text = ""
		return
	var parts: Array[String] = []
	for key: String in counts:
		parts.append("%s %d" % [key, int(counts[key])])
	_counts.text = "  ".join(parts)
