extends GutTest

## `BR57.02` — **the inspect viewer's isolate camera and the board's directional light.**
##
## Its own file rather than more of `test_inspect_panel.gd`, which stands at 927 of `gdlint`'s
## 1000-line cap and went over when these were appended to it. **The third file in taskblock-61 to
## hit that cap**, after `board_view.gd` and `bout_injector.gd`, and paid the same way: extract the
## separable thing rather than shorten comments to fit. What is separable here is a real seam —
## these ask about render layers and lighting, where the rest of that file asks about a panel's
## content and layout.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## The same minimal real-geometry unit `test_inspect_panel.gd` uses — a torso with an actual `Box`,
## so `HitVolumeView.setup` produces real mesh instances to tag with a render layer.
func _unit_with_geometry() -> Unit:
	var torso := Part.new()
	torso.id = &"torso"
	torso.hp = 10
	torso.max_hp = 10
	torso.volume = [Box.new(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 0.6))]
	return Unit.new(Matrix.new(), Shell.new(torso), Vector2i(0, 0), 0)


## `BR57.02` — **the isolate camera was culling the board's directional light along with the
## geometry it meant to hide.**
##
## *"No light source when viewing units, and all of a unit's faces are identically shaded."* Every
## face identically shaded means the directional term contributes **nothing** — which is what
## ambient alone looks like — rather than contributing from an awkward angle. That ruled out the
## ambient raise the first attempt made.
##
## **A `DirectionalLight3D` is a `VisualInstance3D`, so `Camera3D.cull_mask` culls the light too.**
## `BotViewer.show_live` sets `cull_mask = 0` and then re-admits exactly `HitVolumeView.
## ISOLATE_LAYER` and `BoardView.FLOOR_LAYER`. The board's light sat on the default layer 1 and was
## on neither, so the isolate camera simply had no directional light in it at all.
##
## **This is the same defect tb23 Pass E2 already fixed once, for geometry** — the floor vanished
## from this camera for exactly this reason and was given `FLOOR_LAYER` to be seen again. The light
## was never given anything, and the entry's own suspects table checked `light_cull_mask` (which
## objects the light lights) rather than `layers` (which cameras keep the light).
##
## Read off the real nodes: the board's actual light against the viewer's actual camera.
func test_the_isolate_camera_keeps_the_boards_directional_light() -> void:
	var board_light: DirectionalLight3D = WorldPalette.directional_light(
		WorldPalette.BOARD_LIGHT_ENERGY
	)
	add_child_autofree(board_light)
	var unit: Unit = _unit_with_geometry()
	var live_view := HitVolumeView.new()
	add_child_autofree(live_view)
	live_view.setup(unit, DataLibrary.material_table())
	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(
		DataLibrary.material_table(), null, func(_id: int) -> HitVolumeView: return live_view
	)

	panel.open(unit)

	var camera: Camera3D = panel.viewer.camera
	gut.p("camera cull_mask %d, board light layers %d" % [camera.cull_mask, board_light.layers])
	assert_false(panel.viewer.viewport.own_world_3d, "sanity: the isolate path shares the world")
	assert_ne(
		camera.cull_mask & board_light.layers,
		0,
		(
			"the isolate camera culls every layer the board's light is not on — with no overlap "
			+ "the light is not in this camera's render at all, and the subject is lit by ambient "
			+ "alone, which is exactly 'every face identically shaded'"
		)
	)


## The narrowing is still real — this must not have been "fixed" by widening the cull mask, which
## would let every other unit and blocker draw through the preview again and undo tb22 G2.
func test_the_isolate_camera_still_excludes_everything_it_was_narrowed_against() -> void:
	var unit: Unit = _unit_with_geometry()
	var live_view := HitVolumeView.new()
	add_child_autofree(live_view)
	live_view.setup(unit, DataLibrary.material_table())
	var panel := InspectPanel.new()
	add_child_autofree(panel)
	panel.setup(
		DataLibrary.material_table(), null, func(_id: int) -> HitVolumeView: return live_view
	)

	panel.open(unit)

	var camera: Camera3D = panel.viewer.camera
	assert_true(
		camera.get_cull_mask_value(HitVolumeView.ISOLATE_LAYER), "the subject is still admitted"
	)
	assert_true(camera.get_cull_mask_value(BoardView.FLOOR_LAYER), "and the floor under it")
	assert_false(
		camera.get_cull_mask_value(1),
		(
			"layer 1 must stay excluded — that is what keeps other units and blockers out of the "
			+ "preview, and the light is kept by putting the LIGHT on more layers, never by "
			+ "widening this mask"
		)
	)
