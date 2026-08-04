class_name BattleScene
extends Node3D

## docs/10 Phase 12.1: one battle, hand-seeded, from a "New Battle" button.
## No hand-authored .tscn for logic (CLAUDE.md): the .tscn is a bare Node3D
## with this script attached; every child is built here in code.
##
## taskblock-15 Pass A: this is now THE one battle scene — `BoutView` and
## `SimulateBoutMenu` are retired. It builds the world (CameraRig,
## BoardView, one HitVolumeView per unit, the combat-log file sink) exactly
## once and hosts a single swappable `ControlOverlay`, which owns
## everything about HOW a human watches/controls the units (input mapping,
## panels, pacing). Swapping overlays never rebuilds the world — "the world
## is one thing; how you watch and control it is the variable."

## Fires once `load_battle()` has finished rebuilding the world (unit_views,
## board, camera) from a fresh CombatState — the active overlay's own cue
## to re-wire itself (TacticsController.setup(), re-attach its own log
## sink) without a full teardown/setup cycle, e.g. on every "New Battle"
## press. Not fired on the very first `load_battle()` call from `_ready()`
## (there is no overlay yet to hear it) — `set_overlay()` covers that case
## via its own call to `overlay.setup(self)`.
signal battle_loaded

## Temporarily swapped for dartboard verification (runNotes.md follow-up) —
## seed 20260715's blue unit rolls a two-handed sword with only one hand to
## wield it (unarmed in practice). Seed 2 gives both squads a working
## pistol. Revert to 20260715 once verification is done.
const DEFAULT_SEED := 2
## taskblock-17 Pass A: the old 12x10 was well under
## `MapGen.MIN_LEAF_SIZE * 2` (24, taskblock-16's own room-size raise) on
## BOTH axes, so `_split_and_carve` could never split it at all — every
## real battle was silently one room, no hallways, ever since taskblock-16
## landed. 40x30 (~`MIN_LEAF_SIZE * 3` / `MIN_LEAF_SIZE * 2` with room to
## spare) reliably splits 2-3 times per axis instead of just clearing the
## bar once.
const GRID_WIDTH := 40
const GRID_HEIGHT := 30
## runNotes.md: "a 16:9 1080p minimum window should be what we work off
## going forward." project.godot's viewport_width/height sets the launch
## size; this is the actual resize floor.
const MIN_WINDOW_SIZE := Vector2i(1920, 1080)

## taskblock-51 (`BR26.02`): switched by the `set_aim_visual` debug verb so the supervisor
## can bisect a GPU cost CC cannot measure. **Default on — the game behaves normally unless
## someone is deliberately hunting.**
## The occlusion pass gives faded friendlies a translucent `material_override`, and
## transparency disables early-Z too — the same class of suspect as the cutout.
static var show_occlusion_fade: bool = true

var board_view: BoardView
var camera_rig: CameraRig
var unit_views: Array[HitVolumeView] = []
var combat_state: CombatState
## taskblock-15 Pass A: every overlay needs a MissionState to hand
## `AiPlanner.plan_turn`/`BoutRunner` — including the plain hand-seeded
## default battle, which has none of its own yet (Phase 12 scope: "no
## mission loop"). An empty-objectives MissionState is inert for that
## case (the AI just walks to extraction) and
## costs nothing; a squad later set to AI under the player mode
## auto-resolves through this same object, for free.
var mission: MissionState
## docs/09 taskblock03 Pass B: "one stream, many sinks — never two
## streams." A fresh file per `load_battle()` call — one session, one
## replayable log. World-level (every overlay's own combat_state writes to
## disk, regardless of which one is watching); the on-screen log widget
## itself is surface-owned (`CombatLogModule`, mounted by whichever mode wants it,
## place and size it differently).
var file_sink: FileSink
## tb35 Pass A1: world-level like `file_sink` above, same reason — every
## turn's own FPS dump belongs in the one shared log regardless of which
## overlay is watching, and needs re-pointing at the fresh `CombatState`
## on every `load_battle()` the same way `file_sink` already does.
var fps_dump_sink: FpsDumpSink
var overlay: ControlOverlay
## taskblock-30: owned here, not by whichever overlay happens to be
## installed — `ControlOverlay`'s own header already establishes that
## swapping overlays "never rebuilds the world," and `CombatState` is the
## one shared source of truth regardless of who's watching it.
## `BoutInjector` itself only ever held a bare `CombatState` reference
## (never anything overlay-specific), so owning it at the world level
## (rebuilt alongside `file_sink` on every `load_battle()`) is what lets
## it survive a spectator <-> player mode swap
## (`toggle_blue_control()`) instead of being torn down with whichever
## overlay first constructed it. Each overlay's own debug-gated UI
## affordance (see `spectator_overlay.gd`/`squad_control_overlay.gd`) just
## reads this, never constructs its own.
var bout_injector: BoutInjector
## taskblock-30 follow-up (supervisor): unit id -> true, for every unit
## `remove_unit_view()` has deliberately made vanish (debug `remove_object`
## on a unit). `CombatState.kill_unit` never deletes from `state.units`
## (by design — never break a held reference), so the unit is still there
## for `sync_unit_views()` to find on the NEXT debug verb's own sync pass;
## without this it would silently resurrect a view for a unit the operator
## just removed. Reset on every `load_battle()` — a fresh bout starts with
## nothing removed, regardless of what a previous bout's ids meant.
var _removed_unit_ids: Dictionary = {}
## taskblock-52 `BR52.11`: **the current bout's own header event, kept so an overlay
## installed after `load_battle()` can still be shown which bout it is looking at.**
## Owned here for exactly the reason `file_sink` is: it has to outlive the overlay
## swap that loses it. See `_seed_overlay_log_with_the_bout_header()`.
var _bout_start: LogEvent = null


func _ready() -> void:
	if get_window() != null:
		get_window().min_size = MIN_WINDOW_SIZE

	add_child(WorldPalette.world_environment())
	add_child(WorldPalette.directional_light(WorldPalette.BOARD_LIGHT_ENERGY))

	camera_rig = CameraRig.new()
	add_child(camera_rig)

	board_view = BoardView.new()
	add_child(board_view)

	# set_overlay() BEFORE the first new_battle() call — the player mode
	# connects to battle_loaded here with combat_state still null, so its
	# log_sink is already attached by the time load_battle() (inside
	# new_battle(), below) emits that signal, strictly before new_battle()
	# goes on to emit the session-start event. Reversing this order drops
	# that first line silently — nothing was listening yet when it fired.
	set_overlay(ControlOverlay.for_mode(ViewModes.player()))
	new_battle(DEFAULT_SEED)


## tb32 Pass B: "a friendly unit standing between the camera and your
## active unit... fade it." Lives here, not `BoardView`, because the
## actual fade applies to a friendly's own `HitVolumeView` (its real
## rendered body, `HitVolumeView.set_occlusion_faded` — see that doc
## comment for why a separate ghost overlay wasn't enough) and only
## `BattleScene` holds both the live camera (via `board_view`) and
## `unit_views`. Re-evaluated every frame — the camera can move
## continuously (drag-to-orbit) with no signal of its own to react to,
## same reasoning `BoardView.update_wall_cutout` already established.
func _process(_delta: float) -> void:
	if not show_occlusion_fade:
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var occluding: Array[Unit] = _occluding_friendlies(camera)
	for view: HitVolumeView in unit_views:
		view.set_occlusion_faded(view.unit != null and view.unit in occluding)


## Every OTHER unit sharing `board_view.aim_active_unit`'s own squad that
## currently sits within `BoardView.OCCLUSION_RADIUS_CELLS` of, and
## nearer the camera than, the active unit — reuses `WallLegibility.
## occludes_on_screen`/`pixel_radius_for_cells` unchanged, the same
## screen-space-and-nearer test the wall cutout shader's own per-unit
## radius uses, just against `aim_active_unit` instead of a wall.
func _occluding_friendlies(camera: Camera3D) -> Array[Unit]:
	var result: Array[Unit] = []
	var active: Unit = board_view.aim_active_unit if board_view != null else null
	if camera == null or active == null or not is_instance_valid(active):
		return result
	var active_position: Vector3 = UnitGeometry.bounding_sphere(active).center
	if camera.is_position_behind(active_position):
		return result
	var camera_position: Vector3 = camera.global_position
	var active_screen: Vector2 = camera.unproject_position(active_position)
	var active_depth: float = camera_position.distance_to(active_position)
	var viewport_height: float = float(get_viewport().size.y)
	var radius: float = WallLegibility.pixel_radius_for_cells(
		BoardView.OCCLUSION_RADIUS_CELLS, active_depth, camera.fov, viewport_height
	)
	for unit: Unit in board_view.wall_cutout_units:
		if unit == null or not is_instance_valid(unit) or unit == active:
			continue
		if unit.squad_id != active.squad_id:
			continue
		# A unit that's actually left the board (extraction) keeps its
		# stale `.cell` forever and its own HitVolumeView stays live (no
		# remove_unit_view() call on that path) — without this, an
		# extracted friendly would visibly fade as if it were still
		# standing there blocking the shot.
		if unit.extracted:
			continue
		var position: Vector3 = UnitGeometry.bounding_sphere(unit).center
		if camera.is_position_behind(position):
			continue
		var occludes: bool = WallLegibility.occludes_on_screen(
			camera.unproject_position(position),
			camera_position.distance_to(position),
			active_screen,
			active_depth,
			radius
		)
		if occludes:
			result.append(unit)
	return result


## docs/09 taskblock06 Pass I1: "toggleable" — flips every HitVolumeView's
## own overlay together, the same "one flag, every unit" scope
## ControlsOverlay's own H-key toggle already uses for the help legend.
## World-level: every unit's own hit volumes, regardless of which overlay
## is currently watching them.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	if key_event.keycode == ControlBindings.SIMULATE_BOUT_KEY:
		set_overlay(ControlOverlay.for_mode(ViewModes.bout_setup()))
		return
	# taskblock-56 Pass F: **the same two lines the Simulate Bout menu costs**, which is the
	# clearest statement of what the mode table bought. Opening a whole authoring surface is a
	# `ViewModes` row and a keycode; there is nothing else to build or tear down, because
	# `set_overlay` has always been the one place a surface swap happens.
	if key_event.keycode == ControlBindings.EDITOR_KEY:
		set_overlay(ControlOverlay.for_mode(ViewModes.editor()))
		return
	if key_event.keycode != ControlBindings.TOGGLE_HIT_VOLUMES_KEY:
		return
	var show: bool = not (unit_views[0].show_hit_volumes if not unit_views.is_empty() else false)
	for view: HitVolumeView in unit_views:
		view.show_hit_volumes = show
		view.refresh()


## taskblock-15 Pass A: the ONE place a `ControlOverlay` swap happens —
## The bout-setup mode hands off to the spectator mode exactly this
## way, and `_ready()`'s own default (the player mode) goes through
## it too, so there is only ever one code path that installs an overlay.
## Tears the old one down first (its own UI/connections), then wires the
## new one against the world already built.
## taskblock-56 Pass D: the overlay-activated/deactivated log lines used to print
## `overlay.get_class()`, which stops carrying any information once every surface is
## the same class. A mode's own `display_name` is what those lines are actually about.
static func _mode_name(of_overlay: ControlOverlay) -> String:
	if of_overlay == null:
		return ""
	return of_overlay.mode.display_name if of_overlay.mode != null else "ControlOverlay"


func set_overlay(new_overlay: ControlOverlay) -> void:
	# taskblock-41 Pass D: "which overlay is active and when it turns off."
	# Emitted around the swap rather than after it, so the log distinguishes
	# "the old one tore down" from "the new one came up" — a teardown that
	# leaves something behind (a sink still attached, a paused runner) shows as
	# a missing pair, not as silence.
	var previous: String = _mode_name(overlay)
	if overlay != null:
		_log_overlay(&"overlay_deactivated", previous, "overlay %s torn down" % previous)
		overlay.teardown()
		remove_child(overlay)
		overlay.queue_free()
	overlay = new_overlay
	add_child(overlay)
	overlay.setup(self)
	_seed_overlay_log_with_the_bout_header()
	var active: String = _mode_name(overlay)
	_log_overlay(
		&"overlay_activated",
		active,
		"overlay %s active%s" % [active, "" if previous == "" else " (was %s)" % previous]
	)


## **A newly installed overlay is told which bout it is looking at.**
##
## taskblock-52 (`BR52.11`, the second half): the seed reached `out/combat.log` but
## **not the top of the in-game panel**, for every bout started from
## the bout-setup mode. The order is the whole story: `load_battle()` emits the
## header into whichever panel is up, and the caller *then* swaps the overlay — so
## the panel that received it is torn down and the fresh one starts empty. The file
## sink survives the swap because `BattleScene` owns it; a panel does not, because
## the overlay owns it. Nothing was lost before this block only because that path
## emitted no header at all.
##
## **Pushed straight into the sink, deliberately not re-emitted through
## `CombatLog`.** A second `emit()` would reach the file sink too and write two
## `bout_start` lines for one bout — inventing a duplicate event to fix a display
## gap, which is the shape of defect `BR35.04` was filed for one layer up. This is
## the same single event, handed to a panel that came up too late to see it.
##
## `wants()` is honoured rather than bypassed, so a sink that declines a kind still
## declines it here — `CombatLog.emit`'s own rule, not a second policy.
##
## **Scoped to the bout header on purpose.** Replaying arbitrary history to any
## late-attaching sink is a real change to what "one stream, many sinks" means, and
## would hand a `MemorySink` capturing one turn a `bout_start` it never asked for.
## Which bout a panel is showing is a fact about the panel, not about the stream.
func _seed_overlay_log_with_the_bout_header() -> void:
	if _bout_start == null or overlay == null:
		return
	var sink: UiLogSink = overlay.ui_log_sink()
	if sink != null and sink.wants(_bout_start):
		sink.emit(_bout_start)


## Null-safe: `set_overlay` runs before the first `load_battle()` on a fresh
## scene, so there is genuinely no log to write to yet on the very first swap.
func _log_overlay(kind: StringName, overlay_name: String, text: String) -> void:
	if combat_state == null:
		return
	combat_state.combat_log.emit(
		LogEvent.new(
			combat_state.round_number,
			Enums.Phase.TACTICS,
			-1,
			kind,
			{"overlay": overlay_name},
			text
		)
	)


## taskblock-21 Pass C: "assume control of blue team <-> watch." No new
## control system — the overlay swap directly above, exposed as a toggle.
## Squad 0 is "blue" (the same convention `WorldPalette.team_color`/
## `MissionState.player_squad_id` already use); squad 1 ("red") is never
## touched here, so it stays AI regardless of which way this flips.
## `set_overlay`'s own teardown (which the spectator mode's playback
## already routes through `pause()`) is what makes toggling safe mid
## auto-play — nothing new to guard here either.
func toggle_blue_control() -> void:
	var next_controller: Enums.SquadController = (
		Enums.SquadController.AI
		if combat_state.controller_for(0) == Enums.SquadController.HUMAN
		else Enums.SquadController.HUMAN
	)
	combat_state.set_squad_controller(0, next_controller)
	if next_controller == Enums.SquadController.HUMAN:
		set_overlay(ControlOverlay.for_mode(ViewModes.player()))
	else:
		set_overlay(ControlOverlay.for_mode(ViewModes.spectator()))


## Rebuilds the world (board, camera framing, one HitVolumeView per unit)
## from an already-built `CombatState`/`MissionState` — `new_battle()`
## below is the hand-seeded default path through this; the bout-setup mode
## (taskblock-14's `BoutSetup`) is the other. Emits `battle_loaded` so
## whichever overlay is ALREADY active (e.g. "New Battle" pressed again
## under the player mode) can re-wire itself without a full
## teardown/setup cycle.
func load_battle(state: CombatState, p_mission: MissionState) -> void:
	for view: HitVolumeView in unit_views:
		remove_child(view)
		view.queue_free()
	unit_views.clear()
	_removed_unit_ids.clear()

	if file_sink != null:
		file_sink.close()
	file_sink = FileSink.new()

	combat_state = state
	mission = p_mission
	combat_state.combat_log.add_sink(file_sink)
	fps_dump_sink = FpsDumpSink.new(self, combat_state.combat_log)
	combat_state.combat_log.add_sink(fps_dump_sink)
	bout_injector = BoutInjector.new(combat_state)
	# taskblock-41 Pass B: engine and script errors ride this battle's own
	# stream from here on. Re-POINTED, never re-created — `OS.add_logger` is
	# process-global, so one shared tap follows whichever battle is current
	# (see `EngineErrorTap.shared()`'s own doc comment). Installed here rather
	# than in `_ready()` so it is always pointing at a real log by the time
	# it can fire at all.
	EngineErrorTap.shared().watch(combat_state.combat_log, combat_state)
	EngineErrorTap.shared().install()
	# taskblock-41 Pass D: point the bout-build log at this battle's stream
	# BEFORE `board_view.build()` below, or the build it is meant to narrate
	# happens unlogged.
	board_view.build_log = combat_state.combat_log
	# Before the header below and before the build: the active overlay's own
	# log panel has to be listening to THIS battle's stream by now, or it
	# starts mid-sentence. (`battle_loaded`, at the end of this function, is
	# far too late — it fires after everything worth seeing has been emitted.)
	if overlay != null:
		overlay.attach_log_sink(combat_state.combat_log)
	# docs/09: a bout's seed is logged before anything else it does, so a bout is
	# replayable from its own log. taskblock-41 Pass D's bout-build log would
	# otherwise land ahead of it — the header is emitted here, structurally,
	# between attaching the sinks and building anything.
	#
	# **`BR52.11`: this used to be an OPTIONAL `header_event` argument, and the
	# comment above already argued it should not be** — *"rather than by whoever
	# happens to call this and remembers to do it afterwards"*. The signature did
	# not enforce what the comment asked for, and the bout-setup path did exactly
	# the thing the comment warned about: it called the two-argument form, so the
	# seed a player typed generated the whole bout and was then dropped. Because a
	# new bout **appends** to the same file (`FileSink`, supervisor's call), the log
	# then opened with the launch bout's seed and every later bout ran underneath it
	# with none of its own — a reader takes line 1 as the seed for the whole file
	# and is wrong. The argument is gone; the seed now rides on the state, and this
	# is the only place a header is emitted.
	_bout_start = _bout_start_event(combat_state.bout_seed)
	combat_state.combat_log.emit(_bout_start)

	board_view.build(combat_state.grid, combat_state.material_table, mission.team_extraction_cells)
	# tb35 Pass D (BR32.01/BR32.03): the wall-cutout feed must be re-pointed
	# for every bout, regardless of which overlay ends up active —
	# previously this only happened inside the player surface's own
	# battle_loaded handler, so starting/reloading a bout while staying in
	# the spectator surface (the default) left it pointing at whatever it held
	# before: null on first launch, or the PREVIOUS bout's own now-stale
	# units on a later one — a cutout at a cell with no unit there anymore,
	# carried over from a bout that no longer exists. Set once, here, the
	# one place that owns both `board_view` and `combat_state` for every
	# bout load path.
	board_view.wall_cutout_units = combat_state.units
	camera_rig.center_on(
		Vector3(
			(combat_state.grid.width - 1) * UnitGeometry.CELL_SIZE * 0.5,
			0.0,
			(combat_state.grid.rows - 1) * UnitGeometry.CELL_SIZE * 0.5
		)
	)

	for unit: Unit in combat_state.units:
		var view := HitVolumeView.new()
		add_child(view)
		view.setup(unit, combat_state.material_table)
		unit_views.append(view)

	# taskblock-27 Pass D2: correct from the very first turn too, not just
	# once `refresh_unit_views()` first runs post-turn.
	apply_active_turn_highlight()

	battle_loaded.emit()


## taskblock-22 Pass G2: the isolate camera's own lookup — InspectPanel
## asks for the LIVE HitVolumeView already rendering `unit_id` on the real
## board (not a fresh duplicate) so it can view the genuine article from
## a second camera. Null for an id with no live view (there never should
## be one mid-battle, but a caller with no live board at all — a bare
## unit test — has nothing to look up either).
func find_unit_view(unit_id: int) -> HitVolumeView:
	for view: HitVolumeView in unit_views:
		if view.unit != null and view.unit.id == unit_id:
			return view
	return null


## taskblock-30 follow-up (supervisor report): "spawn unit doesn't create
## a visual model, even though the inspect panel shows it." `BoutInjector.
## spawn_unit` adds a real unit straight into `combat_state.units` — every
## OTHER path that grows the roster runs through this scene's own
## `load_battle()` build loop above, once, at load time; nothing kept
## `unit_views` in sync with `combat_state.units` after that. Diffs the
## two and builds a fresh `HitVolumeView` (the exact same construction
## `load_battle()` already runs) for any unit that doesn't have one yet —
## a no-op once every unit already does, so safe to call after every debug
## verb, not just `spawn_unit`.
func sync_unit_views() -> void:
	for unit: Unit in combat_state.units:
		if _removed_unit_ids.has(unit.id) or find_unit_view(unit.id) != null:
			continue
		var view := HitVolumeView.new()
		add_child(view)
		view.setup(unit, combat_state.material_table)
		unit_views.append(view)


## taskblock-30 follow-up (supervisor): "remove... fully vanishing it" —
## the debug-only counterpart to `sync_unit_views()`'s creation side.
## Destroys `unit`'s own `HitVolumeView` entirely (not just re-rendered
## downed — that's `kill`'s own, narratively real, distinct debug verb)
## and remembers its id so a LATER debug verb's own `sync_unit_views()`
## pass never resurrects it. `CombatState.kill_unit`/`BoutInjector.
## remove_object` already handle the DATA side (mark dead, vacate the
## cell) — this is purely the view-layer half, since `BoutInjector` itself
## is view-agnostic and can't touch the SceneTree at all. No real gameplay
## path ever deletes a view this way — a debug-only visual operation, not
## a front for something real.
func remove_unit_view(unit: Unit) -> void:
	_removed_unit_ids[unit.id] = true
	if board_view != null:
		board_view.exclude_unit_from_occlusion(unit.id)
	for i in range(unit_views.size()):
		if unit_views[i].unit == unit:
			var view: HitVolumeView = unit_views[i]
			unit_views.remove_at(i)
			remove_child(view)
			view.queue_free()
			return


## taskblock-30 follow-up (supervisor report): `board_view.build()` was
## only ever called once, in `load_battle()` — the exact same "data
## changed, nothing rebuilds the view" gap `sync_unit_views()` already
## closed for units, just never noticed for `Grid.blockers`/`field_items`
## (a debug `place_cover`/`clear_cover`/`spawn_object`/`remove_object`/
## `move_object`-on-a-cell call mutates them correctly, but nothing ever
## redrew the board). `build()` already does a full clear-and-rebuild of
## its own static geometry from whatever `grid` currently holds — calling
## it again is the correct resync, not a parallel mechanism.
func sync_board_view() -> void:
	board_view.build(combat_state.grid, combat_state.material_table, mission.team_extraction_cells)


## Every HitVolumeView rebuilt from the unit it already tracks — a
## destroyed part disappears, a moved unit redraws at its new cell. Shared
## by every overlay that resolves a turn for real (docs/09: resolution
## already mutated combat_state synchronously by the time this is called).
##
## taskblock-19 Pass I2: `affected_unit_ids` (default null: every view,
## the safe fallback for a caller with no more precise signal) narrows
## this to just the units a turn's own events actually named
## (`LogPlayback.affected_unit_ids`) — `refresh()` tears down and
## rebuilds a unit's entire mesh subtree from its own socket tree, real
## work that a normal turn has no reason to repeat for every OTHER unit
## on the board that this turn never touched.
## tb32 Pass D (BR27.07): `apply_highlight` lets a caller defer the
## active-turn flip separately — `UnitInputModule._on_turn_ended()`
## does, until the previous unit's own action has actually finished
## animating (`await resolution_player.play(events)`); calling this with
## the flip still bundled in used to flip the indicator to the NEXT unit
## before that animation ever played, a real confirmed bug (docs/
## Bugs-add.md's own investigation). True by default so every other
## existing caller (`advance_ai_turns`, `PlaybackModule.advance()`)
## keeps its current "always stays in sync, no deferral" behavior
## unchanged.
## taskblock-42 Pass B (BR27.09 cost #2): tries the cheap transform-only path
## first and falls back to a full rebuild when the node set genuinely changed.
## The overwhelmingly common case here is a unit that MOVED — same parts, same
## boxes, same meshes, only transforms — for which the full teardown was pure
## waste. `refresh_transforms()` refuses on any structural difference, so the
## fallback is not a heuristic: it fires whenever reuse would be wrong.
func refresh_unit_views(affected_unit_ids: Variant = null, apply_highlight: bool = true) -> void:
	for view: HitVolumeView in unit_views:
		if affected_unit_ids == null or (view.unit != null and view.unit.id in affected_unit_ids):
			if not view.refresh_transforms():
				view.refresh()
	apply_batch_badges()
	if apply_highlight:
		apply_active_turn_highlight()


## Public (tb32 Pass D): a caller that deferred the flip via
## `refresh_unit_views(..., false)` calls this directly once it's actually
## safe to flip.
func apply_active_turn_highlight() -> void:
	var current: Unit = combat_state.current_unit() if combat_state != null else null
	for view: HitVolumeView in unit_views:
		view.set_active_turn(view.unit != null and view.unit == current)


## taskblock-43 Pass C: pushes each unit's batch badge — `B2` for a member of
## batch 2, `B2*` for whichever member is currently leading it, nothing at all
## for the independent (`batch_id == 0`) units that make up every bout until one
## is assigned by hand. Unconditional in `refresh_unit_views`, unlike the
## active-turn highlight: the badge is not a turn-ordering signal that a caller
## might want to defer until an animation finishes, it just says who is grouped
## with whom.
##
## Every decision here belongs to `BatchPlan.badge_for` and none of it to the
## view — CC cannot see the screen, so what the badge SAYS has to be answerable
## in a headless test, leaving this loop with nothing in it that could be
## subtly wrong.
func apply_batch_badges() -> void:
	if combat_state == null:
		return
	for view: HitVolumeView in unit_views:
		if view.unit == null:
			continue
		view.set_batch_badge(
			combat_state.batch_plans.badge_for(view.unit, combat_state.round_number)
		)


## Public (not just _ready-internal) so a headless caller/test can seed a
## battle without going through button input. A small hand-seeded fight,
## two squads of deep-struck cyborgs, wrapped in an empty-objectives
## MissionState (see `mission`'s own doc comment above).
func new_battle(seed_value: int) -> void:
	var state: CombatState = _seed_battle(seed_value)
	var fresh_mission := MissionState.new(RunState.new(), state)
	fresh_mission.objectives = []
	# docs/09 taskblock03 Pass B2: the seed is logged before the bout does anything,
	# so a bout is replayable from its own log alone. This scene has no separate
	# loadout selection to log (assemble_random draws everything — geometry,
	# loadout, the works — from this one seed already).
	# taskblock-52 `BR52.11`: no longer handed to `load_battle`. It rides on
	# `CombatState.bout_seed`, set in `_seed_battle` below, and `load_battle` emits
	# it unconditionally — so this path and the bout-setup mode's cannot disagree
	# about whether a bout logged its seed.
	load_battle(state, fresh_mission)


## `seed_value` is the ONE origin seed the whole bout derives from — map, loadouts
## and combat rolls all descend from it. It is taken here rather than a prebuilt
## `RandomNumberGenerator` precisely so the origin number is still in hand to stamp
## onto the state; `state.rng.seed` is a *derived* `rng.randi()` and would not
## regenerate this map (`BR52.11`).
func _seed_battle(seed_value: int) -> CombatState:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid: Grid = MapGen.generate(rng.randi(), GRID_WIDTH, GRID_HEIGHT)
	var pool: Array[Part] = DataLibrary.parts_pool()
	var spawn_a: Vector2i = _first_cell_of_marker(grid, Enums.SpawnMarker.SPAWN_A, Vector2i(2, 2))
	var spawn_b: Vector2i = _first_cell_of_marker(grid, Enums.SpawnMarker.SPAWN_B, Vector2i(9, 7))
	var units: Array[Unit] = [
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, spawn_a, 0),
		DeepStrike.assemble_random(Matrix.new(), 1.0, pool, rng, spawn_b, 1),
	]
	var state := CombatState.new(grid, units, rng.randi())
	state.bout_seed = seed_value
	# tb31 Pass B: every squad must be assigned explicitly now — squad 0
	# (the player's own squad, the same seam `toggle_blue_control()` already
	# flips) HUMAN, squad 1 AI. BR30.09's own root cause was this path
	# assigning nothing at all and silently inheriting a default.
	state.assign_rest_to_ai([0])
	return state


## runNotes.md: "the red unit may be spawning in a non-navigable space" —
## MapGen carves real SPAWN_A/SPAWN_B zones but its own `generate()` return
## signature only hands back the Grid, not the cells it placed them at
## (test files already re-derive them the same way, e.g.
## test_full_mission.gd's own spawn-cell finder). `fallback` only fires if
## a map somehow has no cell carrying that marker at all.
func _first_cell_of_marker(grid: Grid, marker: int, fallback: Vector2i) -> Vector2i:
	for y in range(grid.rows):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			if grid.get_spawn_marker(cell) == marker:
				return cell
	return fallback


## docs/09 taskblock03 Pass B2: "log the seed... so it is replayable from its own
## log file." unit_id -1: no specific unit caused this, same convention
## `log_impact_result` already uses for cover/terrain.
##
## **taskblock-52 `BR52.11`: `session_start` became `bout_start`.** The old name
## was accurate when a log file held exactly one bout. It does not any more — a new
## bout appends to the same file (`FileSink`, supervisor's call), so one file
## routinely carries several, and a per-file "session" event could only ever
## describe the first of them. Calling the second one `session_start` would be the
## same misattribution the rename exists to fix. `docs/SUPERSEDED.md` records it.
func _bout_start_event(seed_value: int) -> LogEvent:
	return LogEvent.new(
		0, Enums.Phase.TACTICS, -1, &"bout_start", {"seed": seed_value}, "seed=%d" % seed_value
	)


func _exit_tree() -> void:
	if file_sink != null:
		file_sink.close()
	# taskblock-41 Pass B: stop feeding a log whose battle is gone. The tap
	# itself stays installed (it is process-global and shared); pointing it
	# at nothing makes it a silent no-op until the next `load_battle()`
	# claims it, which is what keeps a torn-down battle from collecting
	# diagnostics nobody will ever read.
	# Only if it is still pointed at THIS battle — a newer `load_battle()`
	# may already have claimed it, and stealing it back would silence the
	# live one.
	if combat_state != null and EngineErrorTap.shared().combat_log == combat_state.combat_log:
		EngineErrorTap.shared().stop_watching()
