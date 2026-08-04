class_name ModuleSlots
extends RefCounted

## taskblock-56 Pass C: the named places a mode may publish for its modules to mount into.
##
## **Open `StringName`s, not an enum**, per CLAUDE.md's standing rule: a mode is data and a new mode
## may want a slot nobody has thought of. These constants exist so the four modes shipping today
## agree on spelling, not to close the set — `ModuleContext.set_slot` takes any name, and a module
## asking for a slot no mode published gets its fallback rather than an error.
##
## Every one of these is optional. A module must render somewhere sensible when its slot is absent,
## because the stand-alone acceptance mounts every module against a context with no slots at all.

## The full-height left column. Historically the inventory/weapons list, the Inspect button and the
## combat log, in that order.
const LEFT_COLUMN := &"left_column"
## The row inside the left column that the weapons list sits in.
const INVENTORY_ROW := &"inventory_row"
## Top-right, growing down: the keybindings toggle and the H-help legend under it.
const TOP_RIGHT := &"top_right"
## Bottom-right, growing up: the readout panel, then the action bar / turn controls row.
const BOTTOM_RIGHT := &"bottom_right"
## Inside the bottom-right readout panel: header, banner, aim readout, stat block, queue list.
const READOUT_COLUMN := &"readout_column"
## The horizontal row holding the action column on the left and the turn controls on the right.
const ACTION_ROW := &"action_row"
## Top-left, the corner `DebugControlPanel`'s own centering already steers clear of. Play/Step/Speed
## and the shared Inject/New Battle/Watch cluster.
const TOP_LEFT := &"top_left"
## A second top-left row under the first — the spectator's tunable timing fields.
const TUNABLES := &"tunables"
