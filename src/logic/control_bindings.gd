class_name ControlBindings
extends RefCounted

## docs/10 taskblock03 J: the single source every bound key comes from —
## "generate it from the binding table, not a hand-written string, or it
## will drift the first time a key changes." Living in the logic layer
## (CLAUDE.md: logic is view-agnostic, zero SceneTree dependency) rather
## than on TacticsController/ControlsOverlay themselves means the
## dependency runs the correct direction: the VIEW Nodes that actually
## match input against these keycodes import them from here, and the
## on-screen overlay reads the exact same constants — never two copies of
## "which key is reset turn" that could quietly fall out of sync.

const DESELECT_KEY := KEY_ESCAPE
const FACE_NUDGE_CCW_KEY := KEY_Q
const FACE_NUDGE_CW_KEY := KEY_E
const RESET_FRAMING_KEY := KEY_F
const RESET_TURN_KEY := KEY_R
## docs/10 taskblock03 J: "toggleable with H."
const TOGGLE_KEY := KEY_H


## `{"trigger": String, "action": String}`, in the order docs/10 taskblock03
## J's own list gives them. `log_path` is Pass B2's "log: <path>" line,
## folded in here rather than hand-appended by the view, so this stays the
## one place the whole overlay's content comes from. Mouse-button entries
## are plain strings: there's no keycode constant for "RMB" to derive from,
## and no rebind risk for a fixed mouse convention.
static func all(log_path: String) -> Array[Dictionary]:
	return [
		{"trigger": "Click unit or tile", "action": "select"},
		{"trigger": "Click cell", "action": "move"},
		{"trigger": "RMB", "action": "undo last action"},
		{"trigger": "%s / button" % _key(RESET_TURN_KEY), "action": "reset turn"},
		{
			"trigger": "drag / %s, %s" % [_key(FACE_NUDGE_CCW_KEY), _key(FACE_NUDGE_CW_KEY)],
			"action": "face"
		},
		{"trigger": "Click enemy", "action": "aim"},
		{"trigger": "Scroll", "action": "dartboard layer"},
		{"trigger": _key(RESET_FRAMING_KEY), "action": "reset framing (while aiming)"},
		{"trigger": "button", "action": "end turn"},
		{"trigger": "RMB drag", "action": "orbit"},
		{"trigger": "MMB drag", "action": "pan"},
		{"trigger": "Scroll", "action": "zoom (while not aiming)"},
		{"trigger": _key(TOGGLE_KEY), "action": "toggle this help"},
		{"trigger": "log", "action": log_path},
	]


static func _key(keycode: Key) -> String:
	return OS.get_keycode_string(keycode)
