class_name ResolutionModule
extends ViewModule

## taskblock-56 Pass C: resolution playback — the cosmetic replay of a turn's `LogEvent` stream.
##
## Both overlays owned a `ResolutionPlayer` and differed only in what they handed it: the player
## view passed `TacticsController.unlock_input` and a banner `Label`, the spectator passed neither
## because it has no input to unlock and shows its state in a status line instead. Both are
## preserved — the banner comes from whichever module offers a `banner` label, and the unlock
## callback from `context.tactics` if the mode has input.
##
## **The view replays the log; it does not drive the simulation** (docs/10). `resolve_turn()` is
## already atomic and has already finished by the time anything here runs. That is also why a future
## multiplayer replay is the same code.

var player: ResolutionPlayer = null


func module_id() -> StringName:
	return &"resolution"


func _mount() -> void:
	player = ResolutionPlayer.new()
	add_child(player)
	rebind()


## Re-points at whichever battle is current. The spectator's replay path needs exactly this and
## nothing else — its own `rebind_to_battle` called `resolution_player.setup(battle)` for the same
## reason.
func rebind() -> void:
	if player == null or context == null or context.battle == null:
		return
	var unlock: Callable = context.tactics.unlock_input if context.tactics != null else Callable()
	player.setup(context.battle, unlock, _banner())


## Plays `events` and returns when the animation has finished. Awaited by every caller, which is
## what stops the AI batch snapping into place before the human's own tracer has fired.
func play(events: Array[LogEvent]) -> void:
	if player != null:
		await player.play(events)


func set_speed(multiplier: float) -> void:
	if player != null:
		player.speed = multiplier


func _banner() -> Label:
	var module: ViewModule = context.module(&"stat_panels")
	# taskblock-57 Pass D retired `stat_panels`, which was the only module that ever offered one.
	# Asked for by name rather than by type so a later module can offer a banner without this file
	# learning its class — and null is a legal answer, which is what every mode gets today.
	if module == null:
		return null
	var offered: Variant = module.get(&"banner")
	return offered as Label if offered is Label else null
