class_name ResourceEditorScene
extends Control

## taskblock-11: a standalone tool for viewing and tuning every game
## definition — parts, ammo, materials. Named for what it does: it edits
## Godot Resources.
##
## Pass A: a SEPARATE scene, its own PROCESS — launched as its own
## instance of the game executable (`godot --path . <this scene>`), not a
## Godot `EditorPlugin` (a plugin is stripped from exports and can never
## ship to players; this can). It reads and writes `.tres` through the
## SAME `DataLibrary`/`DataValidator` the game uses — editor output and
## game input are identical by construction, the bot-builder discipline
## (use the real system, never a parallel one) applies here too. Writes
## go to `user://data/` only; `res://data/` is read-only once exported.
## No live hot-reload: the running GAME picks up a save on its own next
## boot/sim run (`DataLibrary._loaded` isn't touched by anything here) —
## that's the requested workflow, not a limitation.

var current_type: StringName = DataLibrary.TYPE_PARTS
var theme_root: Control


func _ready() -> void:
	theme_root = self
	theme = HulkTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	load_data()


## Pass A TEST: "the editor loads via DataLibrary." Every definition of
## `current_type`, id -> resource — the same call the table (Pass C)
## re-reads on a type switch.
func load_data() -> Dictionary:
	return DataLibrary.resources_of_type(current_type)


## Pass A TEST: "saving writes a valid `.tres` to `user://data/`; a saved
## file reloads identically." A thin pass-through to `DataLibrary.save` —
## the editor never writes a `.tres` any other way.
func save_resource(resource: Resource) -> Array[ValidationError]:
	return DataLibrary.save(current_type, resource)


func set_current_type(type_key: StringName) -> void:
	current_type = type_key
	load_data()
