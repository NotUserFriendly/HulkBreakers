class_name ReplayModule
extends ViewModule

## taskblock-56 Pass C: the suite-run panel and the watched-run replay panel.
##
## **These two panels are the reason `docs/11`'s failure mode has a name here.** Both existed, both
## were tested, and for a whole taskblock nothing in the running game called either of them — the
## replay path was reachable only from its own tests. The mechanism passed every test asserting it
## worked when called, and nothing asserted it got called. The wiring below is that missing half,
## moved rather than rewritten.
##
## ## The two modes genuinely differed, and both behaviours are kept
##
## - **Visibility.** The player view is gated on `SuiteRunPanel.SHOW_IN_PLAYER_VIEW` as well as
##   `OS.is_debug_build()` — taskblock-51 made these spectator-only while the bug hunt ran, because
##   they crowd the surfaces the hunt reproduces against and a run is watched from the spectator
##   view anyway. The Inject panel was deliberately left alone: it is a hunting tool, not a test
##   surface.
## - **What a finished run says.** The spectator announces *every* outcome, including a pass —
##   silence after a run is indistinguishable from a broken replay, which is exactly what the
##   supervisor could not tell apart. The player view stayed quiet on a pass.
##
## Both are parameters rather than a choice made here, because Pass C moves code and changes
## nothing.
##
## **Parented to `ui_root`, not to the module.** An overlay is a `Node3D`; a `Control` under one
## gets no layout at all and every panel piles up at the origin in the same corner. Third
## full-rect container to hit that, which is why `test_debug_panel_layout.gd` asserts it rather than
## anyone eyeballing it once.

## Emitted with the message a finished run produced, so the mode puts it wherever it shows status —
## the player view used its thinking label, the spectator the replay panel's own notice line.
signal notice(text: String)

## Emitted when a replayed fixture has been loaded into the board. The player view does nothing (it
## is a board to drive by hand); the spectator rebinds and plays.
signal replay_loaded(map_seed: int)

## Set before `mount`. False keeps the panels out of a mode entirely.
var enabled: bool = true
## Whether a passing run says so. See the class note.
var announce_passes: bool = false

var suite_run_panel: SuiteRunPanel = null
var watched_run_panel: WatchedRunPanel = null


func module_id() -> StringName:
	return &"replay"


## **Collapsible, declared rather than derived.** `ViewModule.is_collapsible()` normally reads the
## slot's edge, and these two panels anchor themselves rather than taking a slot — so the derivation
## answers false and `UiButtonsModule` would build no button for them.
##
## The UI review asked for one outright: *"The run tests window needs to be a button within the UI
## BUTTONS module, and default off."* Overriding is the honest way to say "this is toggleable for a
## reason the slot cannot express", rather than inventing a slot so the derivation comes out right.
##
## **Only where the panels exist**, which is the follow-up review's *"REP doesn't show or hide
## anything."* The player view never constructs them (`SuiteRunPanel.SHOW_IN_PLAYER_VIEW`) and a
## release export never constructs them at all — so a button was being built for a surface that was
## not there, and pressing it flipped a flag nothing read.
func is_collapsible() -> bool:
	return suite_run_panel != null


## What the button's border reads. The panels are hidden together, so either answers for both.
func is_showing() -> bool:
	return suite_run_panel != null and suite_run_panel.visible


## Hides both panels together. They are one debug surface from the player's point of view, and a
## button that hid half of it would be worse than none.
func _on_collapsed(value: bool) -> void:
	if suite_run_panel != null:
		suite_run_panel.visible = not value
	if watched_run_panel != null:
		watched_run_panel.visible = not value


## The one shared tooltip renderer, if this mode declared it. Null means the `[?]` carries no text.
func _tooltip_view() -> TooltipView:
	var module: ViewModule = context.module(&"tooltip") if context != null else null
	return (module as TooltipModule).view if module != null else null


func _mount() -> void:
	if not enabled or not OS.is_debug_build():
		return
	var root: Control = context.ui_root
	if root == null:
		return
	suite_run_panel = SuiteRunPanel.new()
	# **Shaped and placed like the Inspect panel**, which the UI review asked for outright: *"Can
	# this be shaped like the inspect panel and put on the right? Along with matching padding. It
	# should draw OVER the inspect panel if both are active."*
	#
	# So it takes `BattleLayout.inspect_rect` — the same rect, the same corner padding — and the mode
	# table declares `replay` after `inspect` so it is the later child of `ui_root` and therefore the
	# one drawn on top. **That is the whole of the z-order**: `Control` draw order is child order,
	# and a mode's module list is what sets it.
	#
	# Its previous home was the top-left, which taskblock-57 G1 moved it to after it collided with
	# the action bar's band in the bottom-right. Two moves in three passes is worth noting: the panel
	# had no declared placement of its own until now, and a surface with no row in the table goes
	# wherever the last person to look at it put it.
	root.add_child(suite_run_panel)
	var rect: Rect2 = BattleLayout.inspect_rect(root.size)
	suite_run_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	suite_run_panel.position = rect.position
	suite_run_panel.custom_minimum_size = rect.size
	suite_run_panel.size = rect.size

	watched_run_panel = WatchedRunPanel.new()
	# **Inside the suite panel, not beside it.** The review: *"There is floating white text in the
	# spectator menu that looks like it's pinned to the middle right that I believe is related to
	# this that needs to be rolled into the Test Suite Module."* It was this panel, anchored
	# centre-right on its own — the run's seed table and notice line, explaining a box in a different
	# corner. One surface now.
	suite_run_panel.adopt(watched_run_panel)

	suite_run_panel.battle = context.battle
	# **The criteria and the run box are one item**, which the UI review asked for: *"The white text
	# and the [?] should be a single item with the run_test box."* They were two panels in two
	# corners explaining each other.
	suite_run_panel.set_criteria(
		"\n".join(WatchedRun.describe_criteria(CompletionSampler.TURN_CAP, 0.35)), _tooltip_view()
	)
	suite_run_panel.dismissed.connect(func() -> void: collapsed = true)
	watched_run_panel.bind(context.battle, null)
	# **Off by default**, which the UI review asked for: *"The run tests window needs to be a button
	# within the UI BUTTONS module, and default off."* A debug surface that is up before anyone asked
	# for it is crowding the surfaces a hunt reproduces against — the same reasoning that made these
	# spectator-only in taskblock-51.
	collapsed = true
	suite_run_panel.run_completed.connect(_on_suite_run_completed)
	watched_run_panel.seed_loaded.connect(_on_replay_loaded)


## Tells the replay panel, if one is watching, that the bout on screen has ended. Without this the
## panel loaded one fixture and stopped, which reads as "the replay does not work" rather than as
## "nobody told it the bout was over".
func report_bout_finished(turns_taken: int) -> void:
	if watched_run_panel == null or watched_run_panel.run == null:
		return
	if watched_run_panel.run.is_done():
		return
	watched_run_panel.turns_taken = turns_taken
	watched_run_panel.on_bout_finished()


## A finished run offers its replayable failures.
func _on_suite_run_completed(finished_run: SuiteRun) -> void:
	if watched_run_panel == null:
		return
	if finished_run.passed():
		# **Every outcome says something** — in the mode that opted into saying so. A green run
		# putting nothing on screen is the player view's deliberate quiet.
		if announce_passes:
			_say("run passed — nothing to replay (board cleared)")
		return
	watched_run_panel.bind(context.battle, null)
	var offered: int = watched_run_panel.offer_failures(finished_run)
	var failed: int = finished_run.failures().size()
	if offered == 0:
		if announce_passes:
			_say("%d failure(s), none with a visual form — nothing to replay" % failed)
		return
	var total: int = watched_run_panel.replayable_total(finished_run)
	if announce_passes:
		_say("replaying %d of %d replayable failure(s), from %d total" % [offered, total, failed])
	else:
		_say("replaying %d of %d replayable failure(s)" % [offered, total])


func _say(text: String) -> void:
	if announce_passes and watched_run_panel != null:
		watched_run_panel.set_notice(text)
	notice.emit(text)


func _on_replay_loaded(map_seed: int) -> void:
	replay_loaded.emit(map_seed)
