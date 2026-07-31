class_name DebugUiElements
extends RefCounted

## taskblock-51: **the table of UI elements the debug panel can switch on and off.**
##
## `DebugVerbs.all()` is the same shape one layer down: the debug panel builds its whole
## surface from a table rather than one hand-written control per thing, so **a new toggleable
## element is a new row here, never new UI code** in `DebugControlPanel`.
##
## The performance readout is the first entry and the reason this exists. It was briefly a
## single hardcoded checkbox, which had to live *somewhere* in a two-column panel that has no
## third place to put it — and the place it ended up captioned every verb in the list. The
## answer was not a better corner for one checkbox; it was admitting that "which debug
## surfaces are up" is its own kind of control, with its own entry in the list.
##
## ## Ids are an open `StringName` vocabulary
##
## Per `CLAUDE.md`: enums are for closed engine states, and this is not one. An element id is
## a `StringName` so a later element can be added as a row, and whoever owns the node maps the
## id to it. This table deliberately does **not** know what any element *is* — no node paths,
## no scene references. It names things; the overlays own them.

## The live framerate readout (`PerfPanel`), mounted by both overlays.
const PERF_PANEL := &"perf_panel"


## Every toggleable element, in the order the panel lists them.
##
## `shown` is the state the element starts a session in, not a preference that persists — the
## debug panel is a per-session tool and a readout that came back on its own after being
## dismissed would be a small recurring annoyance.
static func all() -> Array[Dictionary]:
	return [
		_element(
			PERF_PANEL,
			"Performance Monitor",
			"Live framerate readout, top right. Stays up when this panel closes.",
			false
		),
	]


## Looks an element up by id, or `{}` — callers that hold an id from somewhere other than
## this table need to be able to ask without guessing.
static func find(id: StringName) -> Dictionary:
	for element: Dictionary in all():
		if element.id == id:
			return element
	return {}


static func _element(id: StringName, label: String, hint: String, shown: bool) -> Dictionary:
	return {"id": id, "label": label, "hint": hint, "shown": shown}
