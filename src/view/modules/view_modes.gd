class_name ViewModes
extends RefCounted

## taskblock-56 Pass D: **the table.** Every mode the game has, as data.
##
## | before | after |
## |---|---|
## | `SpectatorOverlay`, 718 lines | `spectator` — display modules, no unit input |
## | `SquadControlOverlay`, 942 lines | `player` — display + full unit input |
## | `SingleUnitOverlay`, 54 lines | `single_unit` — the above, scoped to one unit |
## | `GenerateBoutOverlay`, 373 lines | `bout_setup` — the roster menu, no board input |
##
## **`single_unit` is the entry that proves the point.** It was 54 lines only because inheritance
## happened to be available to it — it wanted everything `SquadControlOverlay` had. Here it is
## literally `player`'s module list with one field changed, which is what "a mode is a declaration"
## means when the declaration is honest.
##
## **Each mode is built by assigning fields rather than by one long constructor call**, so a comment
## can sit with the option it explains. That is not cosmetic: the options carry the *reasons* a mode
## differs from its neighbours, and those reasons are the only thing here that is not obvious from
## reading the names.
##
## **The module orders are load-bearing**, and each list says why above it. A module that reads
## another must be declared after it.

## Ordered: `unit_input` publishes the `TacticsController` every display module reads at its own
## mount time, so it is first; `tooltip` before the three modules that share its `TooltipView`;
## `stat_panels` before `resolution` (the resolution banner is the readout cluster's own label);
## `debug_panel` before `top_left_controls` (the Inject button routes into it). Not alphabetical.
##
## **taskblock-57 Pass C moved `action_bar` up to third**, and that is load-bearing rather than
## tidy: the bar publishes four slots, and taskblock-56's rule is that a provider must be declared
## before its dependants. The four surfaces that pin to it — unit resources, the UI buttons cluster,
## turn controls, the combat log — and Inspect's button all resolve their slot at their own mount
## time, so every one of them must come after it. Declared earlier, they would silently fall back to
## `ui_root` and anchor themselves in a corner.
const PLAYER_MODULES: Array[StringName] = [
	&"unit_input",
	&"tooltip",
	&"action_bar",
	&"unit_resources",
	&"stat_panels",
	&"resolution",
	# taskblock-57 Pass C3: before `inspect`, which takes this module's `BotViewer` at its own
	# mount time. Declared after, Inspect builds its own inside its body and the table's top-left
	# row stays empty — not broken, just the old layout.
	&"inspect_viewer",
	&"inspect",
	&"queue_panel",
	&"turn_controls",
	&"controls_legend",
	&"combat_log",
	&"debug_panel",
	# After `debug_panel`: it consumes the toggle that panel offers, and `link()` finds a module only
	# if it mounted. The readout's own lifetime is still independent — closing the menu leaves it up.
	&"perf_monitor",
	&"replay",
	&"top_left_controls",
	# Last: `ui_buttons` builds one toggle per collapsible module, so it wants every module mounted.
	# The sweep runs in `link()`, which is after all mounts, but declaring it last keeps the reason
	# visible where the order is read.
	&"ui_buttons",
]

## Ordered: `resolution` before `playback` (the tunables write into `ResolutionPlayer`'s own fields
## and the pacing loop awaits its playback); `inspect` before `board_inspect` (a click opens the
## panel); `debug_panel` before `top_left_controls`.
##
## **No input module appears here, and that IS the contract.** Before this pass the same fact was
## expressed by *not inheriting* the player overlay, which cost a 718-line copy of everything both
## views wanted.
## taskblock-57 Pass C adds `perf_monitor` after `debug_panel`. **Not a new surface here** — the
## readout was already mounted in this mode, inside `debug_panel`; splitting it out would otherwise
## have silently deleted it from the one view a framerate hunt is actually run in.
const SPECTATOR_MODULES: Array[StringName] = [
	&"combat_log",
	&"resolution",
	&"debug_panel",
	&"perf_monitor",
	&"replay",
	&"inspect",
	&"playback",
	&"board_inspect",
	&"top_left_controls",
]

## Pre-battle setup: the roster menu and nothing else. It never drives a unit's turn — Start Bout
## builds the matchup, installs it into the shared world and swaps to `spectator`. A transition, not
## a persistent mode.
const BOUT_SETUP_MODULES: Array[StringName] = [&"bout_setup"]

## taskblock-56 Pass F: **the editor, and the answer to the block's own question.**
##
## *"The editor mode should be a module set plus one new authoring module. If it is not — if it
## needs to subclass, or reach into another mode, or duplicate a panel — say so plainly."* Six of
## these seven rows already existed; `editor` is the one new module, and the chrome is the player
## mode's own `PLAYER_COLUMNS` rather than a seventh layout. **No subclass, no new chrome, no
## duplicated panel.**
##
## Ordered: `board_inspect` before `editor` (the editor arms its capture mode and connects to its
## click at link time, and a module can only find one that mounted before it); `claim_volumes`
## before `editor` for the same reason — the editor pushes its claims into it on every edit.
##
## **`claim_volumes` appears here and in no play mode**, which is exactly what Pass E built it for
## and what `test_view_gap_modules.gd` asserts the other half of: a claim is consumed at assembly
## and does not exist on an assembled board, so drawing one during a bout would be drawing
## something that is not there.
const EDITOR_MODULES: Array[StringName] = [
	&"camera_framing",
	&"claim_volumes",
	&"inspect",
	&"board_inspect",
	&"combat_log",
	&"editor",
]


static func player() -> ViewMode:
	var mode := ViewMode.new()
	mode.id = &"player"
	mode.display_name = "Player"
	# taskblock-57 Pass C: **the layout goes live here.** `BATTLE_LAYOUT` builds every rect in the
	# block's placement table from `BattleLayout`, which is pure arithmetic over the screen size —
	# where `PLAYER_COLUMNS` built four anchored regions whose only test was a screenshot.
	mode.chrome = ModeChrome.BATTLE_LAYOUT
	mode.modules = PLAYER_MODULES
	mode.turn_policy = ViewMode.TurnPolicy.HUMAN_SQUADS
	# The one inventory surface in the player view, opened on demand for whatever is selected.
	mode.options[&"inspect"] = {&"with_button": true}
	mode.options[&"top_left_controls"] = {&"include_new_battle": true, &"watch_label": "Watch"}
	# **Spectator-only while the bug hunt runs.** The replay panels crowd the surfaces the hunt
	# reproduces against, and a run is watched from the spectator view regardless. The Inject panel
	# is deliberately NOT gated this way: it is a hunting tool, not a test surface.
	mode.options[&"replay"] = {&"enabled": SuiteRunPanel.SHOW_IN_PLAYER_VIEW}
	return mode


static func spectator() -> ViewMode:
	var mode := ViewMode.new()
	mode.id = &"spectator"
	mode.display_name = "Spectator"
	mode.chrome = ModeChrome.TOP_LEFT_ROWS
	mode.modules = SPECTATOR_MODULES
	mode.turn_policy = ViewMode.TurnPolicy.NONE
	# A spectated bout has no "New Battle" concept of its own; the toggle goes the other way.
	mode.options[&"top_left_controls"] = {
		&"include_new_battle": false, &"watch_label": "Assume Control"
	}
	# **Every outcome says something here.** Silence after a run is indistinguishable from a broken
	# replay, which is exactly what the supervisor could not tell apart.
	mode.options[&"replay"] = {&"announce_passes": true}
	return mode


## `player`'s modules and chrome, with the turn policy narrowed. **One field.** That is the whole
## of what used to be a subclass, and the reason it is worth pointing at: the 54-line file was not
## small because the mode was small, it was small because inheritance let it take everything.
static func single_unit() -> ViewMode:
	var mode: ViewMode = player()
	mode.id = &"single_unit"
	mode.display_name = "Single Unit"
	mode.turn_policy = ViewMode.TurnPolicy.SINGLE_UNIT
	return mode


static func bout_setup() -> ViewMode:
	var mode := ViewMode.new()
	mode.id = &"bout_setup"
	mode.display_name = "Generate Bout"
	mode.chrome = ModeChrome.CENTERED_MENU
	mode.modules = BOUT_SETUP_MODULES
	mode.turn_policy = ViewMode.TurnPolicy.NONE
	return mode


## **The editor.** A `ViewMode` built exactly like the other four — which is the whole claim Pass F
## had to make good on, and the reason this function is six lines rather than a file.
##
## `TurnPolicy.NONE`: an authoring surface drives no unit's turn. It is not a display-only *mode* in
## the spectator's sense — it authors a board — but the axis `TurnPolicy` measures is who plays the
## battle, and the answer here is nobody.
static func editor() -> ViewMode:
	var mode := ViewMode.new()
	mode.id = &"editor"
	mode.display_name = "Editor"
	mode.chrome = ModeChrome.PLAYER_COLUMNS
	mode.modules = EDITOR_MODULES
	mode.turn_policy = ViewMode.TurnPolicy.NONE
	# The board is the thing being authored, so a click on it must reach the editor rather than
	# open a modal over it. The inspect panel stays mounted and reachable by its own button.
	mode.options[&"inspect"] = {&"with_button": true}
	return mode


## **The empty surface: no modules, no chrome, no turn policy.**
##
## This is what a bare `ControlOverlay` used to be before Pass D — the base class built nothing and
## `wants_turn_for` was unconditionally false — and it is a real mode rather than a null check,
## because several fixtures install one deliberately to neutralise `BattleScene._ready()`'s own
## default before loading a battle of their own.
##
## **Defaulting a modeless surface to `player()` instead would be actively wrong**, and was,
## briefly: the player mode has unit input, so `_on_battle_loaded` drives the AI batch, and a
## fixture that installed a placeholder found its bout one turn further on than it expected, with
## units standing somewhere else.
static func empty() -> ViewMode:
	var mode := ViewMode.new()
	mode.id = &"empty"
	mode.display_name = "Empty"
	mode.turn_policy = ViewMode.TurnPolicy.NONE
	return mode


## Every mode, for tests and for anything that wants to enumerate them.
static func all() -> Array[ViewMode]:
	return [player(), spectator(), single_unit(), bout_setup(), editor(), empty()]


## The mode named `id`, or null. **Null rather than a default**, so a caller naming a mode that does
## not exist gets a refusal it can see instead of silently landing in the player view.
static func by_id(id: StringName) -> ViewMode:
	for mode: ViewMode in all():
		if mode.id == id:
			return mode
	return null
