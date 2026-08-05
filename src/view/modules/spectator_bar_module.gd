class_name SpectatorBarModule
extends BarModule

## taskblock-57 Pass G1: **the spectator's bar — playback controls, plus the old top-left cluster.**
##
## The taskblock: *"Spectator — playback controls, plus the old top-left cluster."* And Pass D's one
## remaining line: *"`top_left_controls_module` → the spectator action bar"*, which had nowhere to
## go until this module existed.
##
## ## It publishes two slots and builds nothing else
##
## Play / Pause / Step / Speed and the status line belong to `PlaybackModule`; Inject / New Battle /
## Watch belong to `TopLeftControlsModule`. Both already existed, both already mounted into a named
## slot, and **neither is edited by this pass** — the bar publishes `PACING_ROW` and `TUNABLES` and
## the two modules land in the bar instead of in a corner, without either of them learning that a
## bar exists.
##
## That is the module system's own premise applied to the one case it was written for: *"where a
## panel sits is a property of the surface, not of the panel."* The spectator's controls moved
## across the screen and the modules that draw them did not change a line.
##
## **The slot was renamed rather than reused under a lying name.** It was `top_left`, which is a
## position; the same row is now bottom-centre. `pacing_row` says what it is for, which is the only
## description that survives being moved.
##
## ## Two rows, because the tunables are a second row and always were
##
## `TOP_LEFT_ROWS` published a pacing row and a tunables row under it. The bar keeps that shape —
## the timing knobs are a long row of labelled `SpinBox`es, and putting them beside the transport
## controls would push the transport controls off the bar.
##
## Display: it draws nothing itself and queues nothing. A spectator watches a bout and cannot play
## it, which is unchanged by the controls having moved.

## The transport controls and the shared cluster. Public so a test reads back what was published.
var pacing_row: HBoxContainer = null
## The timing knobs, under them.
var tunables_row: HBoxContainer = null


func module_id() -> StringName:
	return &"spectator_bar"


## The four satellite slots every bar publishes, plus the two this one folded in.
##
## **Merged rather than replaced**, so the combat log still pins left of the spectator's bar exactly
## as it pins left of the player's. A bar that published only its own rows would take the whole
## placement table down with it in this mode.
func published_slots() -> Dictionary:
	var slots: Dictionary = super()
	slots[ModuleSlots.PACING_ROW] = pacing_row
	slots[ModuleSlots.TUNABLES] = tunables_row
	return slots


## Two rows of real controls. **`MOUSE_FILTER_STOP`, unlike the wrapping containers around them** —
## these carry buttons and spin boxes, and a pass-through row is one whose clicks land on the board
## behind it. The same distinction `ModeChrome._button_row` drew when it owned these rows.
func _fill_bar(column: VBoxContainer) -> void:
	pacing_row = _control_row(column)
	tunables_row = _control_row(column)


func _control_row(column: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(row)
	return row
