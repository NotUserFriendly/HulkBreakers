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

## Emitted once a launched run reaches its exit marker. **The panel does not reach
## into the replay panel** — the overlay owns both and wires them, which is what keeps
## this a status surface rather than a coordinator.
signal run_completed(finished_run: SuiteRun)

## taskblock-51: **the run panels are spectator-only for the duration of the bug hunt.**
##
## They mount identically under both overlays, and under the player view they sit on top
## of the surfaces the hunt is actually looking at — the supervisor reported them
## interfering while reproducing. Spectating is where a run is watched from anyway; the
## player view is where the bugs are.
##
## **A flag rather than a deletion, and read from one place**, so putting them back is
## this constant and nothing else. `test_debug_panel_layout.gd` asserts the split in both
## directions, so flipping this without updating the test fails loudly rather than
## quietly restoring a panel nobody wanted back yet.
const SHOW_IN_PLAYER_VIEW := false

## taskblock-50 Pass F: **a run finishes into a window nobody is looking at.**
##
## The panel is watched intermittently by definition — a full gate takes minutes and the
## whole point of running it in the game is to do something else meanwhile. A finished run
## that only announces itself visually is a finished run you notice late.
##
## Synthesised rather than shipped as an asset: two short tones, so pass and fail are
## distinguishable without looking. A rising pair means green, a falling pair means red —
## a chime that sounded the same either way would just say "go and look", which the
## progress feed already does.
const CHIME_PASS_HZ: Array[float] = [660.0, 990.0]
const CHIME_FAIL_HZ: Array[float] = [440.0, 330.0]
const CHIME_TONE_MSEC := 110
const CHIME_VOLUME_DB := -12.0

## How many lines the feed shows. A tail, not a scrollback: the interesting part of a
## running suite is always the end, and keeping the whole thing on screen would make
## the panel a log viewer instead of a status light.
const VISIBLE_LINES := 18
## How often the subprocess is polled, in seconds. Fast enough to read as live, slow
## enough that it is not doing a file seek every frame for a ten-minute run.
const POLL_INTERVAL := 0.25

## **Pinned, because a test feed's line lengths are wild.** GUT prints everything from
## `* test_x` to a full `res://` path to a wrapped assertion message, so a panel that
## sized itself to its content jumped about on every poll — unreadable while the thing
## you are watching is the text. Flagged, not derived; it is wide enough for the
## longest ordinary line (a `res://test/unit/...` path) without crowding the board.
const PANEL_WIDTH := 560.0
## Height reserved for the feed. Flagged: `VISIBLE_LINES` rows at roughly a monospace
## line's height, so the panel does not resize vertically as the tail fills either.
const FEED_HEIGHT := 260.0
## Matches `CombatLogPanel`'s own alpha so the two read as the same kind of surface.
const BACKGROUND_ALPHA := 0.82

## The size of the cleared board. Matches `BoutSetup`'s own so the camera does not jump
## between the empty state and a replayed bout.
const CLEARED_WIDTH := 32
const CLEARED_ROWS := 24

var run: SuiteRun = null
## Set by the host overlay so a launch can clear the board.
var battle: BattleScene = null

var _force_failure: CheckBox = null

var _body: PanelContainer = null
var _status: Label = null
var _feed: Label = null
var _counts: Label = null
var _filter: String = ""
var _since_poll: float = 0.0


func _ready() -> void:
	# The container itself draws nothing; the background lives on `_body`, the same
	# split `CombatLogPanel` uses so the two surfaces match rather than merely
	# resemble each other.
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_body = PanelContainer.new()
	_body.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		HulkTheme.BACKGROUND.r, HulkTheme.BACKGROUND.g, HulkTheme.BACKGROUND.b, BACKGROUND_ALPHA
	)
	_body.add_theme_stylebox_override("panel", style)
	add_child(_body)

	var column := VBoxContainer.new()
	_body.add_child(column)

	_status = Label.new()
	_status.clip_text = true
	_status.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	column.add_child(_status)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for rung: StringName in SuiteRun.RUNGS:
		var button := Button.new()
		button.text = String(rung)
		button.pressed.connect(_start.bind(rung))
		buttons.add_child(button)
	var stop := Button.new()
	stop.text = "kill"
	stop.pressed.connect(_stop)
	buttons.add_child(stop)

	# **Reachable without knowing a variable name.** Proving the replay path end to end
	# needs a failing run, and requiring `HB_FORCE_TEST_FAILURE=1` on the shell that
	# launched the game is exactly the "incantation" this surface exists to avoid.
	_force_failure = CheckBox.new()
	_force_failure.text = "force a failure"
	_force_failure.tooltip_text = (
		"Makes test_exit_code_probe.gd fail on purpose," + " so a run has something to replay"
	)
	buttons.add_child(_force_failure)

	_counts = Label.new()
	_counts.clip_text = true
	_counts.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	column.add_child(_counts)

	# **The feed is clipped by its parent, not by itself.**
	#
	# `Label.clip_text` clips what is *drawn* and does not stop the label reporting a
	# minimum size as wide as its longest line — a 400-character assertion message
	# pushed the panel from 560 to 699, which the layout test caught. A plain `Control`
	# ignores its children's minimum sizes entirely, so the label can be any width it
	# likes inside one and the panel stays put.
	var feed_clip := Control.new()
	feed_clip.clip_contents = true
	feed_clip.custom_minimum_size = Vector2(PANEL_WIDTH, FEED_HEIGHT)
	feed_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(feed_clip)

	_feed = Label.new()
	_feed.clip_text = true
	_feed.autowrap_mode = TextServer.AUTOWRAP_OFF
	_feed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_clip.add_child(_feed)
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
	if run.finished:
		_chime(run.passed())
		run_completed.emit(run)


## Sound the run's verdict.
##
## **Never fatal and never blocking.** A machine with no audio device, or a headless test
## run, must finish a suite exactly as it would have otherwise — the chime is a courtesy,
## and a courtesy that can fail a run is a defect. Everything here is guarded and the
## whole thing is skipped when there is no audio server to speak to.
func _chime(passed: bool) -> void:
	if Engine.is_editor_hint() or AudioServer.get_bus_count() == 0:
		return
	var tones: Array[float] = CHIME_PASS_HZ if passed else CHIME_FAIL_HZ
	for i in range(tones.size()):
		var player := AudioStreamPlayer.new()
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = 22050.0
		generator.buffer_length = float(CHIME_TONE_MSEC) / 1000.0
		player.stream = generator
		player.volume_db = CHIME_VOLUME_DB
		add_child(player)
		player.play()
		var playback: Variant = player.get_stream_playback()
		if playback != null:
			_fill_tone(playback, tones[i], generator.mix_rate)
		# Freed on its own so a finished chime leaves no nodes behind on a panel that may
		# run a hundred suites in a session.
		get_tree().create_timer(float(CHIME_TONE_MSEC) / 1000.0 * float(i + 2)).timeout.connect(
			player.queue_free
		)


## A short sine with a linear fade-out, so it reads as a chime rather than a click.
func _fill_tone(playback: Variant, hz: float, mix_rate: float) -> void:
	var frames: int = int(mix_rate * float(CHIME_TONE_MSEC) / 1000.0)
	var available: int = playback.get_frames_available()
	frames = mini(frames, available)
	for i in range(frames):
		var t: float = float(i) / mix_rate
		var fade: float = 1.0 - float(i) / float(maxi(1, frames))
		var value: float = sin(TAU * hz * t) * fade * 0.4
		playback.push_frame(Vector2(value, value))


## Whether the "force a failure" box is ticked. A named reader rather than a poke at
## the control, so a test can drive the real path instead of the flag behind it.
func set_force_failure(pressed: bool) -> void:
	if _force_failure != null:
		_force_failure.button_pressed = pressed


func force_failure_requested() -> bool:
	return _force_failure != null and _force_failure.button_pressed


func _start(rung: StringName) -> void:
	run = SuiteRun.new()
	run.force_failure = force_failure_requested()
	if not run.start(rung):
		_status.text = "could not launch — is run_tests.sh executable?"
		return
	# **The board is cleared the moment a run starts**, and that is the point rather
	# than tidiness. Without it the window keeps showing whatever bout was already
	# there, so a replay that works and a replay that does nothing look identical —
	# which is exactly what the supervisor was unable to tell apart. An empty board is
	# an unambiguous "this is not the old bout".
	clear_board()
	# The exact command, first line of the feed. A mis-resolved path or a missing
	# prefix is then visible rather than something to deduce from the verdict.
	run.lines.append("$ %s" % run.launched_command)
	_refresh()


## Replaces whatever is on screen with an empty board. Unfloored cells, no units: it
## renders as bare cells, which reads as *cleared* rather than as a map that happens to
## be dull.
func clear_board() -> void:
	if battle == null:
		return
	var blank := Grid.new(CLEARED_WIDTH, CLEARED_ROWS)
	var empty := CombatState.new(blank, [] as Array[Unit])
	battle.load_battle(empty, MissionState.new(RunState.new(), empty))


func _stop() -> void:
	if run == null:
		return
	run.kill()
	run.poll()
	_refresh()
	run_completed.emit(run)


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
