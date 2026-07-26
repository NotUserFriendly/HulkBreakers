extends SceneTree

## Checkpoint 9: the spectator view's combat log, after it was converted from a
## bare `RichTextLabel` to the shared `CombatLogPanel` (supervisor request,
## post-taskblock-41). Exists because the panel is laid out completely
## differently here — absolutely positioned against the bottom-left corner
## rather than sitting in a column — and every panel bug this session has had
## was a layout bug that only a rendered frame showed.
##
## Run via `./checkpoint.sh 9`. Needs a real GPU frame, never `--headless`.

const README := """# Checkpoint 9 — the spectator combat log

The same `CombatLogPanel` the player view uses, now in `SpectatorOverlay`, which positions it
absolutely against the bottom-left corner instead of in a column. Every combat-log defect this
session has been a layout or event-routing bug invisible to headless assertions, so this frame is
the check that the conversion actually looks right in its new home.

- **`spectator_log.png`** — a real bout under `SpectatorOverlay`.

Look for:
1. Is the panel there at all, bottom-left, at roughly half the screen width?
2. Does the title bar read `Combat Log`, with the FPS readout and a `[-]` button on its right?
3. Is the log body below it, on a real dark background, with text not cut off?
4. Does anything overlap it — the play/pause/step controls, the status line?

Headless coverage for what a frame cannot show — wheel absorption at the content's ends, drag
resize, minimize/restore height — lives in `test/unit/view/test_combat_log_panel.gd` and
`test/unit/view/overlays/test_spectator_overlay.gd`.
"""

const DEFAULT_OUT_DIR := "out/checkpoints/09"

var _out_dir: String
var _battle_scene: Node3D
var _elapsed := 0.0
var _step := 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else DEFAULT_OUT_DIR

	var packed: PackedScene = load("res://src/view/battle_scene.tscn")
	_battle_scene = packed.instantiate()
	root.add_child(_battle_scene)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < 0.6:
		return false

	match _step:
		0:
			# The real spectator path: a generated bout, then the overlay swap
			# `GenerateBoutOverlay` performs.
			var built: Dictionary = BoutSetup.build_bout(_roster(), _roster(), 11)
			if built.get("error", "") != "":
				push_error("checkpoint_9: %s" % built["error"])
				return true
			(_battle_scene as BattleScene).load_battle(built["state"], built["mission"])
			(_battle_scene as BattleScene).set_overlay(SpectatorOverlay.new())
		1:
			var image: Image = root.get_texture().get_image()
			image.save_png("%s/spectator_log.png" % _out_dir)
			print("SAVED spectator_log.png")
			var file := FileAccess.open("%s/README.md" % _out_dir, FileAccess.WRITE)
			if file != null:
				file.store_string(README)
				file.close()
			print("CHECKPOINT_9_DONE")
			return true

	_step += 1
	_elapsed = 0.0
	return false


func _roster() -> Array[BoutRosterEntry]:
	var presets: Array[BotPreset] = DataLibrary.presets_pool()
	var roster: Array[BoutRosterEntry] = []
	for i in range(2):
		var entry := BoutRosterEntry.new()
		entry.profile = presets[i % presets.size()]
		roster.append(entry)
	return roster
