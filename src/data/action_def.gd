class_name ActionDef
extends Resource

## taskblock-07 Pass E1: one row in the action bar's own catalog. `id` is an
## open StringName, never an enum (CLAUDE.md: "open StringName vocabularies
## for content") — new actions are addable as data, no code edit. Matches
## `Socket.socket_type`'s own convention (docs/01).

@export var id: StringName
@export var display_name: String = ""
## Placeholder box art until Pass F's tooltips carry the rest (taskblock-07
## E1: "Placeholder art: the action's initials; details on hover").
@export var initials: String = ""
## docs/01's `requires` shape (StringName capability -> count), independent
## of any single providing part. taskblock-07 E1 names this field but every
## action shipped so far is backed by a part whose OWN `requires` already
## gates it (PartGraph.can_operate, see ActionCatalog.actions_for) — no
## shipped action needs a second, part-independent gate yet. Reserved for a
## future action with no part backing at all; a flagged hook, not invented
## behavior (CLAUDE.md "ask, don't invent").
@export var requires: Dictionary = {}
## e.g. overwatch's &"shoot" — "only available if something else already
## provides shoot" (taskblock-07 E3). Empty (&"") means no such dependency.
@export var requires_action: StringName = &""
## taskblock-08 A (tb31 Pass D): how arming this action from the bar
## actually behaves (`Enums.TargetingMode` — BOARD/NONE/PART_PICKER).
## Replaces the old `requires_target: bool`, which only ever expressed two
## shapes (board-targeted or not) when there are three — the missing
## third shape (a picker, never a board click) is what pushed both
## overwatch (NONE) and repair (PART_PICKER) off the action bar entirely
## and onto bespoke, bolted-on overlay buttons instead of arming here like
## every other action.
@export var targeting_mode: Enums.TargetingMode = Enums.TargetingMode.BOARD


func _init(
	p_id: StringName = &"",
	p_display_name: String = "",
	p_initials: String = "",
	p_requires: Dictionary = {},
	p_requires_action: StringName = &"",
	p_targeting_mode: Enums.TargetingMode = Enums.TargetingMode.BOARD
) -> void:
	id = p_id
	display_name = p_display_name
	initials = p_initials
	requires = p_requires
	requires_action = p_requires_action
	targeting_mode = p_targeting_mode
