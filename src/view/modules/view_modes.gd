class_name ViewModes
extends RefCounted

## taskblock-56 Pass D: **the table.** Every mode the game has, as data.
##
## | before | after |
## |---|---|
## | `SpectatorOverlay`, 718 lines | `spectator` — display modules, no unit input |
## | `SquadControlOverlay`, 942 lines | `player` — display + full unit input |
## | `GenerateBoutOverlay`, 373 lines | `bout_setup` — the roster menu, no board input |
##
## **`single_unit` was here and is gone.** taskblock-56 kept it as `player`'s list with one field
## changed, which made the point that a mode is a declaration. taskblock-57 Pass D collapses it into
## `player` outright: *"with one unit the behaviour was already identical"*, and the one thing it
## really did — pre-select the unit whose turn it is — is now what the player mode does for
## everybody. A mode that differs from another by nothing a player can see is a second name for one
## thing.
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
	&"resolution",
	# taskblock-57 Pass C3: before `inspect`, which takes this module's `BotViewer` at its own
	# mount time. Declared after, Inspect builds its own inside its body and the table's top-left
	# row stays empty — not broken, just the old layout.
	&"inspect_viewer",
	&"inspect",
	&"turn_controls",
	&"controls_legend",
	&"combat_log",
	# taskblock-57 Pass E: a second view of the same stream. Order does not matter — it reads the
	# `CombatLog` directly rather than any module — but it sits beside the log it mirrors.
	&"announcements",
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
##
## **taskblock-57 Pass G1: `spectator_bar` is first, and that is load-bearing.** It is this mode's
## bar, so it publishes the four satellite slots the combat log, Inspect's button and the UI buttons
## resolve at their own mount time — plus `pacing_row` and `tunables`, which is how `playback` and
## `top_left_controls` land in the bar rather than in a corner. Declared later, every one of them
## would silently fall back to `ui_root` and stack at (0,0). `playback` still precedes
## `top_left_controls` so the transport controls read left-to-right before the shared cluster.
##
## `ui_buttons` is last and is new here: this mode now has edge-pinned surfaces (Inspect, the debug
## menu, its own bar), and A2's rule is that every one of them is collapsible — which needs the
## toggle to exist.
const SPECTATOR_MODULES: Array[StringName] = [
	# Before every module that hovers: the UI buttons cluster describes itself on a 1.5 s dwell and
	# reads the shared `TooltipView` at its own link time. A mode without it gets working buttons
	# and no hover text, which is a worse surface rather than a broken one.
	&"tooltip",
	&"spectator_bar",
	&"combat_log",
	&"announcements",
	&"resolution",
	&"debug_panel",
	&"perf_monitor",
	&"replay",
	&"inspect",
	&"playback",
	&"board_inspect",
	&"top_left_controls",
	&"ui_buttons",
]

## taskblock-57 Pass F: **what is visible while aiming, as a table entry someone can read.**
##
## The taskblock: *"Most modules turn off when the camera drops to over-the-shoulder or sniper
## view. That is a module set, so it is a mode."* Thirteen of the player mode's seventeen modules
## are absent here, which is the whole point — aiming is a committed framing, and the chrome around
## it is in the way.
##
## **The four that stay are here for correctness, not taste.** Each would break something real if
## the switch tore it down:
##
## - `unit_input` — owns the `TacticsController` that IS the aim, and the `AimView` dartboard you
##   are aiming with. Unmounting it mid-aim would destroy the aim in order to render the aim.
## - `aim_readout` — the READING/RESOLVES text. The one thing you are actually reading while
##   aiming, and a surface only this mode has: `stat_panels` carried it until Pass D retired that
##   module, so it is its own now.
## - `resolution` — the shot resolves the instant aim ends, and a playback torn down as it starts is
##   a resolution nobody sees.
## - `combat_log` — **not for looks.** Its sink attaches to the live `CombatLog` at mount and is
##   rebuilt empty on remount, so turning it off and on would clear the visible log every time
##   anyone aimed. The history is not the aim mode's to discard.
##
## **The aim view and the dartboard are not modules and did not become ones**, which the taskblock
## says outright. They are `Node3D` world geometry owned by `unit_input`; this set is what stops
## drawing over them.
const AIM_MODULES: Array[StringName] = [
	&"unit_input",
	&"aim_readout",
	&"resolution",
	&"combat_log",
	# taskblock-57 Pass E: an announcement is what the game shouts, and aiming is exactly when you
	# most want to be told that the thing you are aiming at has just died.
	&"announcements",
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
## **taskblock-57 Pass G1 adds `editor_bar`, and it is first for the ordinary reason**: it is this
## mode's bar, so it publishes the four satellite slots `combat_log` and Inspect's button resolve at
## their own mount time.
##
## The claim above — *"exactly one module in the editor's set is new"* — is now two, and that is a
## deliberate change rather than a drift. Pass G's whole subject is that the editor needs a surface
## of its own shape, and *"three action bars, not one with three contents"* says outright that the
## second one is a module. `test_editor_mode.gd` counts them and names both.
##
## **taskblock-57 Pass G2 adds three, and only one of them is new code.**
##
## - `announcements` and `ui_buttons` are the player mode's own modules, declared here because G2
##   gives this mode something for each to do: *"the significant ones surface as announcements"*,
##   and *"section details ... with a toggle in UI buttons"*.
## - `editor_coords` is the coordinate readout, and it is the one module written for G2. It replaces
##   `unit_resources` in the shared `action_bar_top_left` slot — *"same slot, different module"* —
##   which is exactly the split Pass C made that slot for.
##
## `editor_coords` after `board_inspect`, whose hover it follows, and after `editor`, whose model it
## names cells from. Both reads happen in `link()` rather than at mount, so this order is for a
## reader rather than for the machine; `ui_buttons` last is not — it sweeps every mounted module for
## the toggles it builds.
## **taskblock-57 Pass H puts `gizmo` before `board_inspect`, and that order is load-bearing.**
## The host offers raw input to modules in this order and stops at the first that consumes it. A
## press that grabs a handle must not also reach the board picker and author a placement on the cell
## underneath — so the gizmo is offered the event first, and consumes only the presses it actually
## grabbed something with.
const EDITOR_MODULES: Array[StringName] = [
	# As in the spectator's set: the cluster's hover descriptions need the shared renderer.
	&"tooltip",
	&"editor_bar",
	&"camera_framing",
	&"claim_volumes",
	&"inspect",
	&"gizmo",
	&"board_inspect",
	&"combat_log",
	&"announcements",
	&"editor",
	&"editor_coords",
	&"ui_buttons",
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
	# taskblock-57 Pass F: aim is a mode, and which mode is data rather than a branch in the host.
	mode.aim_mode_id = &"aim"
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
	# taskblock-57 Pass G1: **the battle layout, because a spectated battle is a battle.** Pass C's
	# table describes the battle surface — the log left of the bar, announcements at the top, the
	# perf readout in the true corner — and none of that was reachable from `TOP_LEFT_ROWS`, which
	# publishes two rows in a corner and lets everything else anchor itself. The spectator's bar is
	# what makes the switch possible: the four satellite slots have a provider here now.
	mode.chrome = ModeChrome.BATTLE_LAYOUT
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


## **The aim surface.** Same chrome as the mode it is entered from, deliberately: the switch is a
## change of module set, not of layout, and rebuilding the chrome would drop every published slot
## under the modules that stayed mounted.
##
## `TurnPolicy.HUMAN_SQUADS` because the human is still driving this unit's turn — aiming is part
## of taking it, and a policy change mid-turn would hand the unit to the AI planner while the
## player was lining up a shot.
static func aim() -> ViewMode:
	var mode := ViewMode.new()
	mode.id = &"aim"
	mode.display_name = "Aim"
	mode.chrome = ModeChrome.BATTLE_LAYOUT
	mode.modules = AIM_MODULES
	mode.turn_policy = ViewMode.TurnPolicy.HUMAN_SQUADS
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
	# taskblock-57 Pass G1: **the battle layout, for the same reason the spectator took it.** Pass F
	# reused `PLAYER_COLUMNS` because that was the player mode's layout at the time and the editor
	# genuinely needed no chrome of its own; Pass C moved the player mode off it, and reusing an
	# abandoned layout is not the same claim as reusing the one everything else is on. The editor's
	# own surfaces land in the placement table's slots — its bar in the action row, the section
	# details where the Inspect viewer sits — so it is the table it needs.
	mode.chrome = ModeChrome.BATTLE_LAYOUT
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
	return [player(), spectator(), bout_setup(), editor(), aim(), empty()]


## The mode named `id`, or null. **Null rather than a default**, so a caller naming a mode that does
## not exist gets a refusal it can see instead of silently landing in the player view.
static func by_id(id: StringName) -> ViewMode:
	for mode: ViewMode in all():
		if mode.id == id:
			return mode
	return null
