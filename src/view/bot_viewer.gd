class_name BotViewer
extends SubViewportContainer

## taskblock-57 Pass C3: **the 3D subject view, split out of `InspectPanel`.**
##
## docs/10, *"a bot's whole assembly, rotates, drag to spin"*. Every line here was `InspectPanel`'s
## and is moved rather than rewritten — including the four bug histories that are the reason most of
## it looks the way it does. The behaviour is unchanged; what changed is that it can now be
## somewhere else on the screen.
##
## ## Why it left the panel
##
## Two reasons, and the second is the one that forced it.
##
## 1. Pass C's placement table gives the **Inspect viewer** its own row — *"top-left, ~2/3 tall,
##    half as wide — the 3D view, split out so the centre stays clear"* — while Inspect itself is
##    top-right. A subview cannot be in a different corner from the panel that owns its nodes.
## 2. `inspect_panel.gd` was **992 lines against a limit of 1000**, and the block's own first
##    edits to it pushed it over. That is pressure this relieves on its own terms. (The 1000 is
##    the cap as it stood then; the live value is `gdlintrc`'s `max-file-lines` and has risen.)
##
## ## Two rendering paths, and the difference is which World3D
##
## - **Isolate (taskblock-22 G2)** — the viewport stays world-SHARED so this camera sees the same
##   live `HitVolumeView` the board camera does, at its real board position. `ISOLATE_LAYER` plus a
##   matching cull mask hide everything else in that world. The camera orbits the subject.
## - **Fresh copy** — no live view to isolate against (cover, a loose part, a bare cell), so the
##   viewport takes a world of its own and this renders its own assembly, spinning the mesh.
##
## **The lighting state is a pure function of who owns the world**, which is `BR48.01` and the whole
## reason `_set_world_shared` exists. See its own comment.

## Right-clicked, with an absolute screen position. **Emitted rather than handled**: the debug menu
## it opens is about a *unit*, and which unit is being inspected is the panel's business, not this
## view's. `taskblock-22 G1`: the position is absolute because `mb.position` is local to this
## container and the popup needs a screen coordinate.
signal debug_menu_requested(at_position: Vector2)

## docs/10 "a bot's whole assembly, rotates, drag to spin" — the Resource Editor's own preview
## scaffold, ported (not shared: the two have diverged and neither is the other's special case).
const VIEWER_WIDTH := 260
const VIEWER_HEIGHT := 420
const ROTATE_SPEED := 0.5
const DRAG_SENSITIVITY := 0.01
const CAMERA_TARGET := Vector3(0.0, 0.8, 0.0)
const CAMERA_DIRECTION := Vector3(0.0, 0.25, 1.0)
const CAMERA_DISTANCE_FACTOR := 2.2
const CAMERA_MIN_RADIUS := 0.4
const PIVOT_Y_OFFSET := 0.0

## Whether a right-click offers the debug menu at all. Set by the host — a cell or a loose part has
## no unit to inject into, so the menu would be about nothing.
var allow_debug_menu: bool = false

var viewport: SubViewport = null
var camera: Camera3D = null
var pivot: Node3D = null
var view: HitVolumeView = null

var _rotating: bool = true
var _dragging: bool = false
## The LIVE view currently isolated (taskblock-22 G2), or null when showing a fresh copy instead.
## `_isolate_center`/`_isolate_radius`/`_isolate_yaw` are the isolate camera's own orbit state.
var _isolated_view: HitVolumeView = null
var _isolate_center: Vector3 = Vector3.ZERO
var _isolate_radius: float = 0.5
var _isolate_yaw: float = 0.0
var _default_cull_mask: int = 0
## `BR48.01`: the preview's own lighting, withdrawn whenever the viewport shares the battle's
## `World3D`. See `_set_world_shared`.
var _environment: WorldEnvironment = null
var _light: DirectionalLight3D = null
var _own_environment: Environment = null


func _init() -> void:
	custom_minimum_size = Vector2(VIEWER_WIDTH, VIEWER_HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	viewport = SubViewport.new()
	# **`BR48.01`'s actual root: `SubViewport.own_world_3d` defaults to FALSE**, and this is
	# set **before the viewport enters the tree** so no scenario attach/detach ever runs.
	#
	# On the default, this view's private `WorldEnvironment` and `DirectionalLight3D` sit in
	# the **battle's** `World3D` from the moment it is built — the board has been lit by the
	# inspector as well as by itself, without anything asking for it. Nothing looked wrong,
	# because the extra light only ever made the board brighter.
	#
	# It becomes visible the first time a subject takes the fallback path (a cell, cover, a loose
	# item), which sets `own_world_3d = true` and takes that lighting **out** of the battle world.
	# The board drops to its real, single-light level and stays there, because clearing the isolate
	# never restores the flag. A new bout rebuilds this and the accidental second light returns —
	# which is precisely the supervisor's *"starting a new bout does fix it"*.
	#
	# The flag itself is left at its default — **assigning it runs Godot's scenario attach/detach
	# and errors where no scenario exists yet** — so the leak is closed by withdrawing the lighting
	# instead, below, which needs no transition at all.
	viewport.size = Vector2i(VIEWER_WIDTH, VIEWER_HEIGHT)
	add_child(viewport)
	_environment = WorldPalette.world_environment()
	_light = WorldPalette.directional_light()
	_own_environment = _environment.environment
	viewport.add_child(_environment)
	viewport.add_child(_light)
	# The world is shared at birth (Godot's default), so the preview's lighting starts
	# withdrawn — it is restored only by a path that gives this viewport a world of its own.
	_apply_lighting(viewport.own_world_3d)

	camera = Camera3D.new()
	viewport.add_child(camera)
	# taskblock-23 Pass E2: "reads unlit... a directional light alone with no ambient leaves the
	# shadowed side black." This viewport's own WorldEnvironment above is correct for the fallback
	# path (its own isolated World3D) — but the isolate-camera path (G2) shares the REAL battle's
	# own World3D, where a second WorldEnvironment node isn't a well-defined "also applies"
	# situation. A per-camera `environment` override is unconditional regardless of which
	# WorldEnvironment (if any) actually governs whatever World3D this camera ends up in.
	# **Brighter than the board's, and only for this camera.** See
	# `WorldPalette.PREVIEW_AMBIENT_ENERGY`: sharing the battle's world means this view withdraws its
	# own light, so a subject seen from a preview angle is lit by the board's light from the board's
	# angle — dark, about half the time. A per-camera override cannot reach the board.
	camera.environment = WorldPalette.environment(WorldPalette.PREVIEW_AMBIENT_ENERGY)
	# G2: captured BEFORE any isolate ever narrows it — clearing restores exactly this, never a
	# re-derived/guessed "everything" mask.
	_default_cull_mask = camera.cull_mask
	camera.position = CAMERA_TARGET + CAMERA_DIRECTION

	pivot = Node3D.new()
	pivot.position.y = PIVOT_Y_OFFSET
	viewport.add_child(pivot)

	view = HitVolumeView.new()
	pivot.add_child(view)


## **The one construction step that cannot happen in `_init`.**
##
## `Node3D.look_at` resolves a global transform, so it errors outright on a node that is not in the
## tree — *"Node not inside tree. Use look_at_from_position() instead."* This used to be hidden by
## `InspectPanel` building the whole viewer inside `setup()`, which its own header records as a
## load-bearing ordering rule: *"Added to the tree BEFORE `setup()`... getting this backwards
## produces an error at construction, not at first open."*
##
## Splitting the viewer out moved construction earlier, so the rule has to be kept explicitly.
## **Everything else stays in `_init`** so every field is non-null the instant the object exists —
## a module that mounts against an empty context still hands a real viewer to the panel.
func _ready() -> void:
	camera.look_at(CAMERA_TARGET, Vector3.UP)


## True while the live-board isolate path is the one being rendered.
func is_isolating() -> bool:
	return _isolated_view != null


## Starts a fresh subject: auto-rotating, not dragging, nothing isolated. Called before either
## `show_live` or `show_copy`, exactly as the panel's `open()` always did.
func begin() -> void:
	_rotating = true
	_dragging = false
	clear_subject()


## taskblock-22 Pass G2: the real isolate-camera path — the viewport stays world-SHARED (
## `own_world_3d` left false, Godot's default) so this camera can see the SAME live `subject` the
## board camera does, at its real board position; `HitVolumeView.ISOLATE_LAYER` plus a matching
## cull_mask are what keep everything ELSE sharing that world (terrain, cover, other units) from
## drawing through it — "culling anything between the camera and the subject," the strongest form:
## not rendered at all, rather than occluding normally the way the main camera would.
##
## Simplification, flagged: "fading other models" is implemented as fully culling them, not a true
## alpha-fade — that needs a second render/compositing pass this doesn't build.
func show_live(subject: HitVolumeView) -> void:
	_set_world_shared(true)
	_isolated_view = subject
	subject.set_isolated(true)
	camera.cull_mask = 0
	camera.set_cull_mask_value(HitVolumeView.ISOLATE_LAYER, true)
	# taskblock-23 Pass E2: the model was floating in empty space — cull_mask=0 plus only the
	# subject's own layer excluded the real board cell beneath it too. `BoardView.FLOOR_LAYER` is
	# deliberately a SEPARATE layer from `ISOLATE_LAYER` (not the same bit) — other units/blockers
	# never carry either, so they stay excluded exactly as G2 already fixed.
	camera.set_cull_mask_value(BoardView.FLOOR_LAYER, true)
	_frame_isolated_camera(subject)


## The fallback: no live board to isolate against, so this renders its own copy in its OWN isolated
## `World3D`. taskblock-22 G2: a shared, never-overridden world is what let a fresh copy built at
## `Vector2i.ZERO` leak into the real board's camera in the first place.
##
## `root` may be null, which is a real state — a bare cell must show a genuinely EMPTY preview
## rather than whatever the previous subject left behind. `show_assembly(null, ...)` already clears
## its own children and returns early; reused here, not re-derived.
func show_copy(root: Part, material_table: MaterialTable, color: Color) -> void:
	_set_world_shared(false)
	view.show_assembly(root, material_table, color)
	if root != null:
		_frame_camera()


## Always safe to call even when nothing is focused — clearing BEFORE a new subject is what stops a
## previous unit's own isolate-layer tag from bleeding into whatever is framed next.
##
## **Deliberately never touches `own_world_3d`**, so the viewport stays world-shared after a live
## inspect. `BR48.01` is fixed by keeping the preview's own lighting out of a shared world entirely
## (`_set_world_shared`), which holds whether the panel is open or closed; flipping the world back
## here instead asked Godot to detach a viewport from a scenario it had already left, which errors
## rather than no-ops.
func clear_subject() -> void:
	if _isolated_view != null:
		_isolated_view.set_isolated(false)
	_isolated_view = null
	camera.cull_mask = _default_cull_mask


## Re-renders whichever path is actually active, so a debug mutation is visible without re-opening
## the panel.
func refresh(root: Part, material_table: MaterialTable, color: Color) -> void:
	if _isolated_view != null:
		_isolated_view.refresh()
	elif root != null:
		view.show_assembly(root, material_table, color)


func _process(delta: float) -> void:
	# `is_visible_in_tree`, not `visible`: this may be a child of a hidden panel (its own slot is
	# absent) or a sibling of one (the placement table's own top-left slot). Only the tree knows.
	if not is_visible_in_tree() or not _rotating or _dragging:
		return
	if _isolated_view != null:
		_isolate_yaw += ROTATE_SPEED * delta
		_update_isolate_camera_position()
	elif pivot != null:
		pivot.rotate_y(ROTATE_SPEED * delta)


## "click-drag interrupts the auto-rotate to inspect, releases back to rotating" — the same
## interaction the Resource Editor's own toggle button approximates with a manual switch; this reads
## the drag directly.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_rotating = not mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and allow_debug_menu:
			debug_menu_requested.emit(get_screen_position() + mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if _isolated_view != null:
			_isolate_yaw += mm.relative.x * DRAG_SENSITIVITY
			_update_isolate_camera_position()
		else:
			pivot.rotate_y(mm.relative.x * DRAG_SENSITIVITY)


## **The preview's lighting must not leak into the board.**
##
## `BR48.01`, and the supervisor's own diagnosis: *"this may not be a UI issue, it may be lighting
## as the inspect panel draws the clicked item, and then said lighting doesn't get reset to board
## style."* It is exactly that.
##
## This viewport holds a `WorldEnvironment` **and** a `DirectionalLight3D` for the fallback path,
## where it renders a fresh copy in its own isolated world. The isolate-camera path needs the
## opposite — `own_world_3d = false`, so this camera can see the real unit at its real board
## position — and that puts **both of those nodes into the battle's World3D**, a second environment
## and an extra directional light over the whole board.
##
## So while the world is shared, both are withdrawn: this camera's own `environment` override
## already gives it the right ambient regardless of which world it ends up in, and the subject is
## lit by the board's real lighting because it *is* on the board. **The lighting state is a pure
## function of who owns the world**, which is what makes the fix hold while the panel is closed as
## well as open. Assigning `own_world_3d` re-runs Godot's scenario attach/detach even when
## unchanged, so only a genuine change is written.
func _set_world_shared(shared: bool) -> void:
	if viewport.own_world_3d == shared:
		viewport.own_world_3d = not shared
	_apply_lighting(not shared)


## Lit only when this viewport owns its world. **In a shared world the board supplies the light** —
## the subject is a real unit standing on the real board — and anything added there would be
## lighting the whole battle.
func _apply_lighting(owns_world: bool) -> void:
	if _light != null:
		_light.visible = owns_world
	if _environment != null:
		_environment.environment = _own_environment if owns_world else null


## docs/02 "read the real node back": the same AABB-readback framing the Resource Editor's own
## `_frame_preview_camera` uses, reading `HitVolumeView`'s own composed mesh geometry instead of
## re-deriving a bounding box from Part volumes by hand. Fallback-path only.
func _frame_camera() -> void:
	var combined: AABB
	var has_any := false
	for meshes: Array in view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			var world_aabb: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
			combined = world_aabb if not has_any else combined.merge(world_aabb)
			has_any = true
	var center: Vector3 = combined.get_center() if has_any else CAMERA_TARGET
	var radius: float = maxf(combined.size.length() / 2.0, CAMERA_MIN_RADIUS) if has_any else 0.5
	camera.position = center + CAMERA_DIRECTION * radius * CAMERA_DISTANCE_FACTOR
	camera.look_at(center, Vector3.UP)


## Same AABB-readback convention as `_frame_camera`, against the LIVE view's own real mesh instances
## (real board position) instead of the isolated fallback copy's recentered-to-origin ones.
func _frame_isolated_camera(subject: HitVolumeView) -> void:
	var combined: AABB
	var has_any := false
	for meshes: Array in subject._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			var world_aabb: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
			combined = world_aabb if not has_any else combined.merge(world_aabb)
			has_any = true
	_isolate_center = combined.get_center() if has_any else subject.global_transform.origin
	_isolate_radius = maxf(combined.size.length() / 2.0, CAMERA_MIN_RADIUS) if has_any else 0.5
	_isolate_yaw = 0.0
	_update_isolate_camera_position()


## The isolate camera orbits `_isolate_center` (the mesh itself, a LIVE node this does not own and
## never rotates) — `pivot.rotate_y` is the fallback path's own equivalent, spinning the mesh
## instead since that copy genuinely is this view's to spin.
func _update_isolate_camera_position() -> void:
	var direction: Vector3 = CAMERA_DIRECTION.rotated(Vector3.UP, _isolate_yaw)
	camera.position = _isolate_center + direction * _isolate_radius * CAMERA_DISTANCE_FACTOR
	camera.look_at(_isolate_center, Vector3.UP)
