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
const RESET_TURN_KEY := KEY_R
## docs/10 taskblock03 J: "toggleable with H."
const TOGGLE_KEY := KEY_H
## docs/09 taskblock06 Pass I1: "toggleable" — a dev tool/player option, own
## key distinct from TOGGLE_KEY (this overlay's help legend), so hiding one
## never hides the other.
const TOGGLE_HIT_VOLUMES_KEY := KEY_V
## taskblock-14 Pass D: "reachable from a debug key now" — the Simulate Bout
## menu, same dev-tool status as TOGGLE_HIT_VOLUMES_KEY, own key so it never
## collides with a bound gameplay verb.
const SIMULATE_BOUT_KEY := KEY_B


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
		{"trigger": "Click action, then enemy", "action": "aim"},
		{"trigger": "Scroll", "action": "dartboard layer"},
		# taskblock-18 D2 (taskblock-19 Pass B: Lean -> Step Out rename):
		# "mouse-wheel cycles other valid cells" — the SAME physical wheel
		# gesture as the row above, active while choosing a step out's own
		# firing cell instead of aiming.
		{"trigger": "Scroll", "action": "cycle step-out cell (while stepping out)"},
		{"trigger": "button", "action": "end turn"},
		{"trigger": "button", "action": "hold (act after the next ally)"},
		{"trigger": "RMB drag", "action": "orbit (locked while aiming)"},
		{"trigger": "MMB drag", "action": "pan (locked while aiming)"},
		{"trigger": "Scroll", "action": "zoom (while not aiming)"},
		{"trigger": _key(TOGGLE_KEY), "action": "toggle this help"},
		{"trigger": _key(TOGGLE_HIT_VOLUMES_KEY), "action": "toggle hit volumes"},
		{"trigger": _key(SIMULATE_BOUT_KEY), "action": "simulate bout"},
		{"trigger": "log", "action": log_path},
	]


static func _key(keycode: Key) -> String:
	return OS.get_keycode_string(keycode)
