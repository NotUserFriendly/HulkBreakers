class_name ModuleCatalog
extends RefCounted

## taskblock-56 Pass C: every `ViewModule` the project has, by id.
##
## **This exists so the acceptance can be exhaustive rather than a sample.** Pass C's acceptance is
## "a module can be instantiated with no overlay at all", and a test that hand-lists six modules
## proves it for six modules. `test_view_modules_stand_alone.gd` iterates this instead, so a module
## added later is covered the day it is added or fails the registry test for not being here.
##
## **A factory, not a singleton table.** Every call to `build` constructs a fresh instance —
## modules are `Node`s with real children and real signal connections, and a shared one would be a
## second overlay-shaped bug wearing a new hat.
##
## Open `StringName` keys, per CLAUDE.md: a mode names the modules it wants as data, and adding a
## module is a row here plus a file, never a change to any mode that does not want it.

const IDS: Array[StringName] = [
	&"unit_input",
	&"tooltip",
	&"resolution",
	&"combat_log",
	&"debug_panel",
	&"replay",
	&"inspect",
	&"stat_panels",
	&"action_bar",
	&"queue_panel",
	&"turn_controls",
	&"controls_legend",
	&"top_left_controls",
	&"playback",
	&"board_inspect",
	&"bout_setup",
]


## A fresh module for `id`, or null for an id this catalog does not know. **Null is a legitimate
## answer** — a mode listing an unknown id gets a mode without that module rather than a crash, the
## same "no further action, no silent rollback" posture `ActionCatalog.build_firing_action` has.
static func build(id: StringName) -> ViewModule:
	match id:
		&"unit_input":
			return UnitInputModule.new()
		&"tooltip":
			return TooltipModule.new()
		&"resolution":
			return ResolutionModule.new()
		&"combat_log":
			return CombatLogModule.new()
		&"debug_panel":
			return DebugPanelModule.new()
		&"replay":
			return ReplayModule.new()
		&"inspect":
			return InspectModule.new()
		&"stat_panels":
			return StatPanelsModule.new()
		&"action_bar":
			return ActionBarModule.new()
		&"queue_panel":
			return QueuePanelModule.new()
		&"turn_controls":
			return TurnControlsModule.new()
		&"controls_legend":
			return ControlsLegendModule.new()
		&"top_left_controls":
			return TopLeftControlsModule.new()
		&"playback":
			return PlaybackModule.new()
		&"board_inspect":
			return BoardInspectModule.new()
		&"bout_setup":
			return BoutSetupModule.new()
	return null
