class_name ResolutionPlayer
extends Node

## docs/10 Phase 12.4: plays back a resolved turn's captured log purely as
## a cosmetic replay — by the time play() runs, resolve_turn() has already
## mutated the real state synchronously (TacticsController.end_turn()).
## This Node never drives the sim; it only holds the RESOLUTION banner and
## keeps input locked for LogPlayback's own total_duration(), then hands
## control back to TACTICS. Per-cue tracer/impact visuals are deferred (see
## AimView's own note on ghosting) — the timing/locking contract is what
## Phase 12.4's acceptance actually grades, and it's covered headlessly on
## LogPlayback itself.

const TACTICS_BANNER := "TACTICS"
const RESOLUTION_BANNER := "RESOLUTION"

var banner: Label
var tactics: TacticsController


func setup(p_banner: Label, p_tactics: TacticsController) -> void:
	banner = p_banner
	tactics = p_tactics
	banner.text = TACTICS_BANNER


func play(events: Array[LogEvent]) -> void:
	banner.text = RESOLUTION_BANNER
	var duration: float = LogPlayback.total_duration(events)
	await get_tree().create_timer(duration).timeout
	banner.text = TACTICS_BANNER
	tactics.unlock_input()
