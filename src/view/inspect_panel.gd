class_name InspectPanel
extends PanelContainer

## taskblock-21 Pass A: "wounds, deflections, per-part damage, and nested
## internals (tb20) now exist and are untrackable. This panel is what makes
## them legible." A self-contained, modal-style component — `open(unit)`
## shows it populated for that unit, `close()` hides it and emits `closed`
## — so any host (SquadControlOverlay, SpectatorOverlay/Pass B) can wire it
## in without this file knowing which one it's hosted by. Reuses, never
## reinvents: `HitVolumeView.show_assembly` for the bot viewer (same
## SubViewportContainer/Camera3D/pivot scaffold the Resource Editor's own
## preview already established — that preview is baked directly into
## `ResourceEditorScene`, not a shared component, so this is a parallel
## build of the same PATTERN, not a shared call), `InspectRows`/`WeaponRows`
## for the inventory tree, `TooltipBuilder`/`TooltipData`/
## `TooltipView.to_bbcode` for the info panel's own rendering (docs/08: no
## number is born in the view).
##
## Scope fence (taskblock21 "Out"): no authored per-type info shapes (every
## hovered thing renders through the same generic TooltipBuilder rows) and
## no per-item 3D view in the item-viewer sub-region (A5 itself flags this
## as a later addition) — the item-viewer sub-region exists as a labeled
## placeholder only.

signal closed

const VIEWER_WIDTH := 260
const VIEWER_HEIGHT := 420
const ROTATE_SPEED := 0.5
const DRAG_SENSITIVITY := 0.01
const CAMERA_TARGET := Vector3(0.0, 0.8, 0.0)
const CAMERA_DIRECTION := Vector3(0.0, 0.25, 1.0)
const CAMERA_DISTANCE_FACTOR := 2.2
const CAMERA_MIN_RADIUS := 0.4
const PIVOT_Y_OFFSET := 0.0
const COL_PART := 0
## taskblock-22 Pass E3/G: "Repair with Scrap" is the first NON-debug
## option in the right-click menu, added before Reset/Zero/Ammo — a real,
## AP-costing, legality-gated RepairAction, queued through `_selection`,
## never a debug-style direct mutation.
const REPAIR_ITEM_ID := 200
## taskblock-22 Pass G4: "Inflict Status: Burn" stack choices. No status-
## magnitude storage exists on Part/Unit yet (taskblock21 scope fence) —
## each choice is a one-shot "as if this much Burn had just accumulated"
## through WoundEffects.apply_if_status_crosses_threshold (tb10's own
## status hook), not a persistent stack. BURN_WOUND_ID/BURN_THRESHOLD are
## flagged placeholders (CLAUDE.md: never invent balance numbers) —
## `burnt_electronics` is the one already-authored wound with burn-like
## semantics (data/wounds/burnt_electronics.tres); the threshold (1.0) is
## picked only so 0.5 Stacks visibly does NOT cross it while every other
## choice does, exercising the hook's own gate rather than always firing.
const BURN_STACK_VALUES: Array[float] = [0.5, 1.0, 5.0, 10.0]
const BURN_STACK_LABELS: Array[String] = ["0.5 Stacks", "1 Stack", "5 Stacks", "10 Stacks"]
const BURN_WOUND_ID := &"burnt_electronics"
const BURN_THRESHOLD := 1.0

var _material_table: MaterialTable
var _unit: Unit = null
## taskblock-22 Pass G2: optional — a host with a live board
## (SquadControlOverlay/SpectatorOverlay, both backed by a real
## BattleScene) passes `battle.find_unit_view` (Callable(int) ->
## HitVolumeView, the unit's own id — see open()'s call site), letting the
## isolate camera (see `_isolate_focus`) render the ACTUAL unit already
## on the field instead of rebuilding a disconnected copy. A caller with
## no live board at all (every existing test, a hypothetical standalone
## viewer) leaves this unset and gets the old isolated-fresh-copy
## behavior unchanged.
var _live_view_lookup: Callable = Callable()
## taskblock-22 Pass I: optional — a host with a real TacticsController
## (SquadControlOverlay's own player view; SpectatorOverlay has none and
## leaves this null) gets the same bidirectional part-highlight
## InventoryPanel used to (docs/10 taskblock05 C/taskblock07 Pass C):
## hovering a row highlights that part in the world, hovering a part in
## the world highlights its row. `null` just skips both directions —
## same "optional, degrades gracefully" posture as `_selection`.
var _tactics: TacticsController = null

var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_pivot: Node3D
var _preview_view: HitVolumeView
var _rotating: bool = true
var _dragging: bool = false
## taskblock-22 Pass G2: the live HitVolumeView currently isolated (see
## `_isolate_focus`/`_isolate_clear`), or null when the panel is showing
## its own fallback fresh-copy assembly instead. `_isolate_center`/
## `_isolate_radius`/`_isolate_yaw` are the isolate camera's own orbit
## state — set once per `_isolate_focus` call, advanced by `_process`/
## drag exactly like `_preview_pivot.rotate_y` already does for the
## fallback path, just orbiting the CAMERA instead of spinning the mesh
## (the live unit's own transform isn't this panel's to rotate).
var _isolated_view: HitVolumeView = null
var _isolate_center: Vector3 = Vector3.ZERO
var _isolate_radius: float = 0.5
var _isolate_yaw: float = 0.0
var _default_cull_mask: int = 0

var _status_wound_column: VBoxContainer
var _matrix_label: RichTextLabel
var _inventory_tree: Tree
## taskblock-22 Pass I: "mass/RAM constraints" — InventoryPanel's own
## feature (docs/05's three constraints), ported here since InspectPanel
## now supersedes it everywhere.
var _inventory_footer: Label
var _info_panel: RichTextLabel

var _rows_by_part: Dictionary = {}  # Part -> InventoryRow, for the info panel's own hover
var _debug_menu: PopupMenu = null
## taskblock-22 Pass G1: the exact absolute position the last `popup()`
## call actually requested, BEFORE Godot's own "keep the window on
## screen" clamp can move it — see `_open_debug_menu`'s own doc comment.
var _last_requested_menu_position: Vector2 = Vector2.ZERO
## taskblock-22 Pass E3/G: optional — only a player-driven host
## (SquadControlOverlay) has a real queue to repair against; SpectatorOverlay's
## own read-only usage passes none, same "null skips it" posture every other
## optional mission/selection thread-through in this codebase already has.
var _selection: SelectionController = null


func _init() -> void:
	visible = false
	# test_battle_scene_input.gd's own audit (taskblock-17-1): a plain
	# container defaults to STOP and silently swallows board clicks under
	# it — the same convention TooltipView (also a PanelContainer) already
	# follows. The panel's genuinely interactive regions (the bot viewer,
	# the inventory tree) each carry their own real gui_input/Tree handling
	# and stay clickable regardless of this container's own filter.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## taskblock-22 Pass G1: re-clamps on every viewport resize, not just at
## open() — a window resized WHILE the panel is open must never leave it
## sitting outside the new bounds.
func _ready() -> void:
	get_viewport().size_changed.connect(_clamp_to_viewport)


func setup(
	material_table: MaterialTable,
	selection: SelectionController = null,
	live_view_lookup: Callable = Callable(),
	tactics: TacticsController = null
) -> void:
	_material_table = material_table
	_selection = selection
	_live_view_lookup = live_view_lookup
	_tactics = tactics
	if _tactics != null:
		_tactics.highlight_changed.connect(_on_highlight_changed)
	var title_bar := Label.new()
	title_bar.text = "INSPECT"
	title_bar.add_theme_color_override("font_color", HulkTheme.FOREGROUND)

	var close_button := Button.new()
	close_button.text = "x"
	close_button.pressed.connect(close)

	var title_row := HBoxContainer.new()
	title_row.add_child(title_bar)
	title_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(close_button)

	var root := VBoxContainer.new()
	add_child(root)
	root.add_child(title_row)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_build_bot_viewer(body)
	_build_status_wound_column(body)

	var right_column := VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_column)

	_build_matrix_area(right_column)
	_build_inventory_tree(right_column)
	_build_inventory_footer(right_column)
	_build_info_panel(right_column)


## docs/10 "a bot's whole assembly, rotates, drag to spin" — the Resource
## Editor's own preview scaffold, ported (not shared — see file header).
func _build_bot_viewer(parent: Control) -> void:
	_preview_container = SubViewportContainer.new()
	_preview_container.custom_minimum_size = Vector2(VIEWER_WIDTH, VIEWER_HEIGHT)
	_preview_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_preview_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview_container.stretch = true
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.gui_input.connect(_on_preview_gui_input)
	parent.add_child(_preview_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(VIEWER_WIDTH, VIEWER_HEIGHT)
	_preview_container.add_child(_preview_viewport)
	_preview_viewport.add_child(WorldPalette.world_environment())
	_preview_viewport.add_child(WorldPalette.directional_light())

	_preview_camera = Camera3D.new()
	_preview_viewport.add_child(_preview_camera)
	# taskblock-23 Pass E2: "reads unlit... a directional light alone with
	# no ambient leaves the shadowed side black." This viewport's own
	# WorldEnvironment above (real ambient, WorldPalette.AMBIENT_COLOR/
	# ENERGY) is correct for the fallback path (its own isolated World3D,
	# see open()) — but the isolate-camera path (G2) shares the REAL
	# battle's own World3D, where a second WorldEnvironment node isn't a
	# well-defined "also applies" situation. A per-camera `environment`
	# override is unconditional regardless of which WorldEnvironment (if
	# any) actually governs whatever World3D this camera ends up in —
	# same ambient/background either way, no guessing about Godot's own
	# multi-WorldEnvironment resolution.
	_preview_camera.environment = WorldPalette.environment()
	# G2: captured BEFORE _isolate_focus ever narrows it — _isolate_clear()
	# restores exactly this, never a re-derived/guessed "everything" mask.
	_default_cull_mask = _preview_camera.cull_mask
	_preview_camera.position = CAMERA_TARGET + CAMERA_DIRECTION
	_preview_camera.look_at(CAMERA_TARGET, Vector3.UP)

	_preview_pivot = Node3D.new()
	_preview_pivot.position.y = PIVOT_Y_OFFSET
	_preview_viewport.add_child(_preview_pivot)

	_preview_view = HitVolumeView.new()
	_preview_pivot.add_child(_preview_view)


## taskblock-22 Pass G1: "falls off the bottom of the screen" traced back
## to this column specifically — one Label per unique wound id, no cap,
## no scroll, so enough wounds push the WHOLE panel's own required
## minimum height past whatever the outer viewport-clamp (see
## `_clamp_to_viewport`) can still fit AFTER the fact. A ScrollContainer
## caps the DEMANDED height here at the source, at the column's own
## custom_minimum_size — the clamp is the general-case backstop, this is
## the actual reproducible cause.
func _build_status_wound_column(parent: Control) -> void:
	var scroll := ScrollContainer.new()
	# A ScrollContainer only actually caps what it demands from ITS OWN
	# parent when given a real, nonzero custom_minimum_size for the
	# scrolling axis — a bare 0 (this constant's own prior value) falls
	# through to sizing off the child's full content instead, discovered
	# empirically (200 synthetic wounds still demanded ~5400px tall
	# before this fix). VIEWER_HEIGHT-scaled, not a design number.
	scroll.custom_minimum_size = Vector2(48, 120)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	_status_wound_column = VBoxContainer.new()
	_status_wound_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_status_wound_column)


## taskblock-22 Pass G1: THE actual, reproducible "falls off the bottom of
## the screen" cause — found empirically (CLAUDE.md: "read the real node
## back"), not the wound column (that one's real too, see
## _build_status_wound_column, but this is the dominant one). A
## RichTextLabel with `fit_content = true` and a ZERO-width
## `custom_minimum_size.x` computes its own wrapped height against a
## near-zero width — six short lines of plain matrix info were reporting
## a combined minimum height of ~2000px (confirmed: the same text against
## a real width computes ~140px). A real minimum width fixes the wrap
## computation at the source; VIEWER_WIDTH-matched (this column sits
## beside the bot viewer), not a tuned design number.
func _build_matrix_area(parent: Control) -> void:
	_matrix_label = RichTextLabel.new()
	_matrix_label.bbcode_enabled = true
	_matrix_label.fit_content = true
	_matrix_label.custom_minimum_size = Vector2(VIEWER_WIDTH, 90)
	_matrix_label.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	_matrix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_matrix_label)


func _build_inventory_tree(parent: Control) -> void:
	_inventory_tree = Tree.new()
	_inventory_tree.columns = 2
	_inventory_tree.column_titles_visible = true
	_inventory_tree.set_column_title(0, "Part")
	_inventory_tree.set_column_title(1, "Condition")
	_inventory_tree.hide_root = true
	_inventory_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_tree.gui_input.connect(_on_tree_gui_input)
	# taskblock-22 Pass I: same convention InventoryPanel's own mouse_exited
	# handler used — leaving the tree entirely must clear the 3D highlight,
	# not just stop updating it.
	_inventory_tree.mouse_exited.connect(
		func() -> void:
			if _tactics != null:
				_tactics.hover_part(null)
	)
	parent.add_child(_inventory_tree)


func _build_inventory_footer(parent: Control) -> void:
	_inventory_footer = Label.new()
	_inventory_footer.add_theme_color_override("font_color", HulkTheme.DIM)
	_inventory_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_inventory_footer)


func _build_info_panel(parent: Control) -> void:
	_info_panel = RichTextLabel.new()
	_info_panel.bbcode_enabled = true
	_info_panel.custom_minimum_size = Vector2(0, 100)
	_info_panel.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_info_panel)


## Populates every region for `unit` and shows the panel.
func open(unit: Unit) -> void:
	_unit = unit
	visible = true
	_rotating = true
	_dragging = false
	_isolate_clear()
	if unit.shell.root != null:
		var live_view: HitVolumeView = (
			_live_view_lookup.call(unit.id) if _live_view_lookup.is_valid() else null
		)
		if live_view != null:
			_isolate_focus(live_view)
		else:
			# No live board to isolate against (a bare/standalone panel) —
			# the old fresh-copy path, now in its OWN isolated World3D (G2:
			# this is what actually fixes "renders at ~0,0 on the actual
			# field" — a shared, never-overridden World3D is what let a
			# fresh copy built at Vector2i.ZERO leak into the real board's
			# own camera in the first place).
			_preview_viewport.own_world_3d = true
			_preview_view.show_assembly(
				unit.shell.root, _material_table, WorldPalette.team_color(unit.squad_id)
			)
			_frame_camera()
	_refresh_status_wound_column()
	_refresh_matrix_area()
	_refresh_inventory_tree()
	_show_info_placeholder()
	# G1: layout (wound count, matrix text length) only settles after this
	# frame's own deferred calls run — clamp against the REAL post-layout
	# size, not a guess at what it's about to become.
	call_deferred(&"_clamp_to_viewport")


func close() -> void:
	visible = false
	_unit = null
	_isolate_clear()
	closed.emit()


func _process(delta: float) -> void:
	if not visible or not _rotating or _dragging:
		return
	if _isolated_view != null:
		_isolate_yaw += ROTATE_SPEED * delta
		_update_isolate_camera_position()
	elif _preview_pivot != null:
		_preview_pivot.rotate_y(ROTATE_SPEED * delta)


## "click-drag interrupts the auto-rotate to inspect, releases back to
## rotating" — the same interaction the Resource Editor's own toggle button
## approximates with a manual switch; this reads the drag directly.
func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_rotating = not mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _unit != null:
			# G1: `mb.position` is local to `_preview_container`, not to this
			# panel — the popup needs an absolute screen position (see
			# `_open_debug_menu`'s own doc comment for why the old
			# `get_screen_position() + at_position` math was wrong).
			_open_debug_menu_for_unit(_preview_container.get_screen_position() + mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if _isolated_view != null:
			_isolate_yaw += mm.relative.x * DRAG_SENSITIVITY
			_update_isolate_camera_position()
		else:
			_preview_pivot.rotate_y(mm.relative.x * DRAG_SENSITIVITY)


## docs/02 "read the real node back": the same AABB-readback framing the
## Resource Editor's own `_frame_preview_camera` uses (not shared code —
## see file header), reading `HitVolumeView`'s own composed mesh geometry
## instead of re-deriving a bounding box from Part volumes by hand.
## Fallback-path only (the isolated-fresh-copy case) — see
## `_frame_isolated_camera` for G2's real-unit equivalent.
func _frame_camera() -> void:
	var combined: AABB
	var has_any := false
	for meshes: Array in _preview_view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			var world_aabb: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
			combined = world_aabb if not has_any else combined.merge(world_aabb)
			has_any = true
	var center: Vector3 = combined.get_center() if has_any else CAMERA_TARGET
	var radius: float = maxf(combined.size.length() / 2.0, CAMERA_MIN_RADIUS) if has_any else 0.5
	_preview_camera.position = center + CAMERA_DIRECTION * radius * CAMERA_DISTANCE_FACTOR
	_preview_camera.look_at(center, Vector3.UP)


## taskblock-22 Pass G2: the real isolate-camera path — `_preview_viewport`
## stays world-SHARED (own_world_3d left false, Godot's default) so
## `_preview_camera` can see the SAME live `view` CameraRig does, at its
## real board position; `HitVolumeView.ISOLATE_LAYER` + a matching
## cull_mask are what keep everything ELSE sharing that world (terrain,
## cover, other units) from drawing through it — "culling anything
## between the camera and the subject," the strongest form: not rendered
## at all, rather than occluding normally the way the main camera would.
## Simplification, flagged: "fading other models" is implemented as fully
## culling them, not a true alpha-fade — that needs a second
## render/compositing pass this doesn't build. Reversible follow-up.
func _isolate_focus(view: HitVolumeView) -> void:
	_preview_viewport.own_world_3d = false
	_isolated_view = view
	view.set_isolated(true)
	_preview_camera.cull_mask = 0
	_preview_camera.set_cull_mask_value(HitVolumeView.ISOLATE_LAYER, true)
	# taskblock-23 Pass E2: "the model floats in a void" — cull_mask=0 plus
	# only the subject's own layer excluded the real board tile beneath it
	# too. BoardView.FLOOR_LAYER is deliberately a SEPARATE layer from
	# ISOLATE_LAYER (not the same bit) — other units/blockers never carry
	# either, so they stay excluded exactly as G2 already fixed.
	_preview_camera.set_cull_mask_value(BoardView.FLOOR_LAYER, true)
	_frame_isolated_camera(view)


## Always safe to call even when nothing is focused (open()/close() both
## call it unconditionally) — clearing BEFORE a new focus is what stops a
## previous unit's own isolate-layer tag from bleeding into whatever's
## framed next.
func _isolate_clear() -> void:
	if _isolated_view != null:
		_isolated_view.set_isolated(false)
	_isolated_view = null
	_preview_camera.cull_mask = _default_cull_mask


## Same AABB-readback convention as `_frame_camera`, against the LIVE
## view's own real mesh instances (real board position) instead of the
## isolated fallback copy's recentered-to-origin ones.
func _frame_isolated_camera(view: HitVolumeView) -> void:
	var combined: AABB
	var has_any := false
	for meshes: Array in view._meshes_by_part.values():
		for mesh_instance: MeshInstance3D in meshes:
			var world_aabb: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
			combined = world_aabb if not has_any else combined.merge(world_aabb)
			has_any = true
	_isolate_center = combined.get_center() if has_any else view.global_transform.origin
	_isolate_radius = maxf(combined.size.length() / 2.0, CAMERA_MIN_RADIUS) if has_any else 0.5
	_isolate_yaw = 0.0
	_update_isolate_camera_position()


## The isolate camera orbits `_isolate_center` (the mesh itself, a LIVE
## node this panel doesn't own, never rotates) — `_preview_pivot.rotate_y`
## is the fallback path's own equivalent, spinning the mesh instead since
## that copy genuinely is this panel's to spin.
func _update_isolate_camera_position() -> void:
	var direction: Vector3 = CAMERA_DIRECTION.rotated(Vector3.UP, _isolate_yaw)
	_preview_camera.position = (
		_isolate_center + direction * _isolate_radius * CAMERA_DISTANCE_FACTOR
	)
	_preview_camera.look_at(_isolate_center, Vector3.UP)


## taskblock-22 Pass G1: "constrain it to the viewport (anchor/clamp so it
## fits regardless of resolution)." No anchors preset is used for this
## panel at all (see the two hosts' own `setup()` call sites) — position/
## size are plain absolute values this function alone owns, re-centered
## and shrunk to fit whenever they'd otherwise exceed the real viewport.
func _clamp_to_viewport() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	size = Vector2(minf(size.x, viewport_size.x), minf(size.y, viewport_size.y))
	position = ((viewport_size - size) / 2.0).max(Vector2.ZERO)


## A2: "a vertical column that fills with statuses above, wounds below...
## <5-char short blurb now... hovering an entry fills the info panel."
func _refresh_status_wound_column() -> void:
	for child: Node in _status_wound_column.get_children():
		child.queue_free()
	if _unit == null or _unit.shell.root == null:
		return
	# No status effect system exists yet (taskblock21 scope fence) — the
	# statuses half of the column is structurally ready and simply empty
	# until one does.
	var seen: Dictionary = {}  # StringName -> true, dedupe across parts
	for part: Part in _unit.shell.all_parts():
		for wound_id: StringName in part.wounds:
			if seen.has(wound_id):
				continue
			seen[wound_id] = true
			_add_wound_entry(wound_id)


func _add_wound_entry(wound_id: StringName) -> void:
	var def: WoundDef = DataLibrary.get_wound_def(wound_id)
	var label := Label.new()
	label.text = def.short_label() if def != null else String(wound_id).left(5).to_upper()
	label.add_theme_color_override(
		"font_color", HulkTheme.DAMAGE if (def != null and def.disables) else HulkTheme.WARN
	)
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_entered.connect(func() -> void: _show_info(TooltipBuilder.for_wound(wound_id)))
	_status_wound_column.add_child(label)


## A3: "name, personal_speed, playstyle, perks, link/base state."
func _refresh_matrix_area() -> void:
	if _unit == null:
		_matrix_label.text = ""
		return
	var matrix: Matrix = _unit.matrix
	var lines: Array[String] = []
	if matrix == null:
		lines.append("[i]no matrix docked[/i]")
	else:
		var name: String = matrix.display_name if matrix.display_name != "" else String(matrix.id)
		lines.append("[b]%s[/b]" % name)
		lines.append("personal_speed: %.1f" % matrix.personal_speed)
		lines.append("playstyle: %s" % String(matrix.playstyle))
		var perks: Array[StringName] = matrix.active_perks()
		lines.append("perks: %s" % (", ".join(perks) if not perks.is_empty() else "none"))
		lines.append("link: %s" % ("yes" if matrix.base != null else "no (base)"))
		lines.append("recovery: %s" % Enums.RecoveryState.keys()[matrix.recovery_state])
	_matrix_label.text = "\n".join(lines)


## A4: InspectRows' own strong sort (Weapons -> Containers -> Body), each
## group a real TreeItem parent so the tree stays genuinely tree'd, not
## flattened with a label prefix standing in for structure.
func _refresh_inventory_tree() -> void:
	_inventory_tree.clear()
	_rows_by_part.clear()
	if _unit == null or _unit.shell.root == null:
		_inventory_footer.text = ""
		return
	_inventory_footer.text = _footer_text(_unit.shell)
	var root: TreeItem = _inventory_tree.create_item()
	for group: InspectRow.Group in [
		InspectRow.Group.WEAPONS, InspectRow.Group.CONTAINERS, InspectRow.Group.BODY
	]:
		var label: String = ["Weapons", "Containers", "Body"][group]
		var group_item: TreeItem = _inventory_tree.create_item(root)
		group_item.set_text(0, label)
		var depth_items: Dictionary = {0: group_item}  # depth -> most recent TreeItem, this group only
		for inspect_row: InspectRow in InspectRows.build(_unit, _material_table):
			if inspect_row.group != group:
				continue
			var row: InventoryRow = inspect_row.row
			var parent_item: TreeItem = depth_items.get(row.depth, group_item)
			var item: TreeItem = _inventory_tree.create_item(parent_item)
			var part_name: String = (
				row.part.display_name if row.part.display_name != "" else String(row.part.id)
			)
			if row.kind == InventoryRow.Kind.CONTENTS:
				part_name = "» %s" % part_name
			item.set_text(0, part_name)
			item.set_text(1, "%d/%d" % [row.part.hp, row.part.max_hp])
			if row.part.hp < row.part.max_hp:
				item.set_custom_color(1, HulkTheme.DAMAGE)
			item.set_metadata(COL_PART, row.part)
			_rows_by_part[row.part] = row
			depth_items[row.depth + 1] = item


## taskblock-22 Pass I: "the three constraints" (docs/05) — mass and RAM,
## straight from Shell's own resolvers, never re-summed here. Ported
## verbatim from InventoryPanel's own _footer_text.
func _footer_text(shell: Shell) -> String:
	return (
		"mass %.1f/%.1f   ram %.1f/%.1f"
		% [shell.carried_mass(), shell.max_mass, shell.total_ram(), shell.max_ram]
	)


## taskblock-22 Pass I: bidirectional — a 3D hover highlights this row.
## Same convention InventoryPanel's own version used: walks every row
## rather than tracking one "currently highlighted" item, since
## _refresh_inventory_tree rebuilds the tree wholesale and any cached
## TreeItem reference from a previous highlight would already be stale.
func _on_highlight_changed() -> void:
	var item: TreeItem = _inventory_tree.get_root()
	while item != null:
		var is_highlighted: bool = (
			_tactics.highlighted_part != null
			and item.get_metadata(COL_PART) == _tactics.highlighted_part
		)
		if is_highlighted:
			item.set_custom_bg_color(COL_PART, HulkTheme.HIGHLIGHT.darkened(0.6))
		else:
			item.clear_custom_bg_color(COL_PART)
		item = item.get_next_in_tree()


## A6: "hovering an entry fills the info panel... mousing into a dead zone
## leaves the info put." No branch here ever CLEARS the info panel — only
## a genuine hoverable target (a real Part under the cursor) repopulates
## it; a dead zone (empty tree space) is simply a no-op. Right-click opens
## the same A7 debug menu the bot viewer does, scoped to just this row's
## own part.
func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var item: TreeItem = _inventory_tree.get_item_at_position(motion.position)
		if item == null:
			# G's own A6 rule (info panel: a dead zone is a no-op) is about
			# the INFO TEXT specifically — the 3D highlight still clears
			# here, same as InventoryPanel's own dead-zone handling did.
			if _tactics != null:
				_tactics.hover_part(null)
			return
		var part: Variant = item.get_metadata(COL_PART)
		if _tactics != null:
			_tactics.hover_part(part if part is Part else null)
		if not (part is Part):
			return
		var row: InventoryRow = _rows_by_part.get(part)
		_show_info(TooltipBuilder.for_part(part, _material_table, row))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
			return
		var item: TreeItem = _inventory_tree.get_item_at_position(mb.position)
		if item == null:
			return
		var part: Variant = item.get_metadata(COL_PART)
		if part is Part:
			# G1: same fix as the bot viewer — `mb.position` is local to
			# `_inventory_tree`, not this panel.
			_open_debug_menu([part as Part], _inventory_tree.get_screen_position() + mb.position)


func _show_info(data: TooltipData) -> void:
	_info_panel.text = TooltipView.to_bbcode(data)


func _show_info_placeholder() -> void:
	_info_panel.text = "[i]hover a part, wound, or status to inspect it[/i]"


## A7: "on a bot/part: Reset Health, Set Health to 0, and on placeholder
## guns Set Ammo Type." Debug-only — mutates the real Part(s) directly,
## never through a CombatAction (this isn't a combat move, it's the
## developer poking data). Right-clicking the BOT VIEWER (no specific row
## under the cursor) scopes Reset/Zero Health to every part on the unit;
## right-clicking one inventory row scopes it to just that part.
func _open_debug_menu_for_unit(at_position: Vector2) -> void:
	_open_debug_menu(_unit.shell.all_parts(), at_position)


## G1: `at_position` is now an ABSOLUTE screen position (both call sites
## already add their own control's real `get_screen_position()` to the
## click-local coordinate before calling this) — the old
## `get_screen_position() + at_position` here mixed THIS panel's own
## screen origin with a coordinate local to a CHILD control
## (`_preview_container`/`_inventory_tree`, never this panel directly),
## landing the menu wherever the panel's own corner plus a small local
## offset happened to fall instead of the actual cursor. G3: non-debug
## items (Repair with Scrap) are added first, `[*]`-marked debug items
## (Reset/Zero/Ammo/Burn/Create Part) after — real developer tools, per
## A7's own doc comment below, never a combat move.
func _open_debug_menu(parts: Array[Part], at_position: Vector2) -> void:
	if _debug_menu != null:
		_debug_menu.queue_free()
	_debug_menu = PopupMenu.new()
	add_child(_debug_menu)

	var repairing: Part = _add_repair_menu_item(parts)

	_debug_menu.add_item("[*] Reset Health", 0)
	_debug_menu.add_item("[*] Set Health to 0", 1)
	var ammo_ids: Array[StringName] = []
	if parts.size() == 1 and parts[0].damage > 0.0:
		for ammo_id: StringName in DataLibrary.resources_of_type(DataLibrary.TYPE_AMMO):
			ammo_ids.append(ammo_id)
			_debug_menu.add_item("[*] Set Ammo: %s" % ammo_id, 100 + ammo_ids.size() - 1)
	if parts.size() == 1:
		_add_burn_submenu(parts[0])
		_add_create_part_submenu(parts[0])

	_debug_menu.id_pressed.connect(_on_debug_menu_id_pressed.bind(parts, ammo_ids, repairing))
	_debug_menu.close_requested.connect(_debug_menu.queue_free)
	_debug_menu.id_pressed.connect(_debug_menu.queue_free, CONNECT_DEFERRED)
	# `Window.popup()` clamps its own final on-screen position to stay
	# within the real screen (harmless/expected — a tiny headless test
	# screen clamps far more aggressively than a real 1920x1080+ one ever
	# would) — `_last_requested_menu_position` is the exact, unclamped
	# value this call actually asked for, so a test can verify the MATH
	# independent of that runtime repositioning.
	_last_requested_menu_position = at_position
	_debug_menu.popup(Rect2i(Vector2i(at_position), Vector2i.ZERO))


## G4: "[*] Inflict Status: Burn" -> a submenu of stack counts. A
## submenu's own item clicks fire ITS OWN `id_pressed`, never the parent
## menu's — connected here, independent of `_on_debug_menu_id_pressed`.
func _add_burn_submenu(target: Part) -> void:
	# add_submenu_node_item takes ownership/parents this itself — it
	# errors ("already has a different parent") if we add_child it first.
	var submenu := PopupMenu.new()
	for i in range(BURN_STACK_LABELS.size()):
		submenu.add_item(BURN_STACK_LABELS[i], i)
	submenu.id_pressed.connect(_on_burn_submenu_id_pressed.bind(target))
	submenu.id_pressed.connect(submenu.queue_free, CONNECT_DEFERRED)
	_debug_menu.add_submenu_node_item("[*] Inflict Status: Burn", submenu)


## G4: "[*] Create Part" -> a submenu of parts valid to attach at the
## selected socket. Scope simplification, flagged: uses `target`'s own
## FIRST empty socket — there is no "currently selected socket" concept
## anywhere in this panel yet, and a part rarely exposes more than one
## meaningfully-open socket at once. Refine into a real socket-picker if
## that stops holding. Silently adds nothing if `target` has no empty
## socket, or no authored part is legal to attach at the one found.
func _add_create_part_submenu(target: Part) -> void:
	var socket: Socket = null
	for candidate: Socket in target.sockets:
		if candidate.occupant == null:
			socket = candidate
			break
	if socket == null:
		return
	var candidates: Array[Part] = []
	for part_id: StringName in DataLibrary.resources_of_type(DataLibrary.TYPE_PARTS):
		var candidate_part: Part = DataLibrary.get_part(part_id)
		if PartGraph.is_legal_attachment(candidate_part, socket):
			candidates.append(candidate_part)
	if candidates.is_empty():
		return
	var submenu := PopupMenu.new()
	for i in range(candidates.size()):
		var label: String = (
			candidates[i].display_name
			if candidates[i].display_name != ""
			else String(candidates[i].id)
		)
		submenu.add_item(label, i)
	submenu.id_pressed.connect(_on_create_part_submenu_id_pressed.bind(target, socket, candidates))
	submenu.id_pressed.connect(submenu.queue_free, CONNECT_DEFERRED)
	_debug_menu.add_submenu_node_item("[*] Create Part", submenu)


## Adds the "Repair with Scrap" item when relevant, greyed if unavailable
## — returns the part it would repair (for `_on_debug_menu_id_pressed`),
## or null if the item wasn't added at all (more than one part selected,
## no selection controller to queue against, or nothing to repair here).
func _add_repair_menu_item(parts: Array[Part]) -> Part:
	if parts.size() != 1 or _selection == null or _unit == null:
		return null
	# Repairing queues against `_selection.selected_unit` (whichever unit is
	# actually armed in TACTICS) — inspecting some OTHER unit (an ally not
	# currently acting, an enemy) must never let a right-click here queue an
	# action against a unit that isn't even the one being inspected.
	if _selection.selected_unit != _unit:
		return null
	var target: Part = parts[0]
	if target.hp <= 0 or target.hp >= target.max_hp:
		return null
	var cost: int = RepairResolver.scrap_cost_for(target)
	var scrap_id: StringName = RepairResolver.scrap_resource_id_for(target)
	var mission: MissionState = _selection.mission
	var available: int = int(mission.gathered_resources.get(scrap_id, 0)) if mission != null else 0
	_debug_menu.add_item("Repair with Scrap (%d %s)" % [cost, scrap_id], REPAIR_ITEM_ID)
	var can_repair: bool = RepairResolver.can_repair_with(_unit) and available >= cost
	if not can_repair:
		_debug_menu.set_item_disabled(_debug_menu.get_item_index(REPAIR_ITEM_ID), true)
	return target


func _on_debug_menu_id_pressed(
	id: int, parts: Array[Part], ammo_ids: Array[StringName], repairing: Part
) -> void:
	if id == REPAIR_ITEM_ID and repairing != null:
		var welder: Part = RepairResolver.find_operable_welder(_unit)
		if welder != null:
			_selection.queue_repair(welder.id, repairing.id)
	elif id == 0:
		for part: Part in parts:
			part.hp = part.max_hp
	elif id == 1:
		for part: Part in parts:
			part.hp = 0
	elif id >= 100 and id - 100 < ammo_ids.size():
		parts[0].ammo_id = ammo_ids[id - 100]
	_refresh_inventory_tree()
	_refresh_status_wound_column()
	_refresh_bot_viewer()


## G4: `target` is whichever single part the Burn submenu was opened
## against — see `_add_burn_submenu`.
func _on_burn_submenu_id_pressed(id: int, target: Part) -> void:
	if id < 0 or id >= BURN_STACK_VALUES.size():
		return
	WoundEffects.apply_if_status_crosses_threshold(
		target, BURN_STACK_VALUES[id], BURN_THRESHOLD, BURN_WOUND_ID
	)
	_refresh_inventory_tree()
	_refresh_status_wound_column()


## G4: attaches the chosen candidate at the socket `_add_create_part_submenu`
## already found empty on `target` — a real PartGraph.attach, never a
## bespoke direct-assignment shortcut.
func _on_create_part_submenu_id_pressed(
	id: int, target: Part, socket: Socket, candidates: Array[Part]
) -> void:
	if id < 0 or id >= candidates.size():
		return
	PartGraph.attach(candidates[id], target, socket)
	_refresh_inventory_tree()
	_refresh_status_wound_column()
	_refresh_bot_viewer()


## Shared by every debug/G4 handler above — re-renders whichever bot-
## viewer path is actually active (the live isolate view if focused, the
## fallback fresh copy otherwise) so a debug mutation is visible without
## re-opening the panel.
func _refresh_bot_viewer() -> void:
	if _unit == null or _unit.shell.root == null:
		return
	if _isolated_view != null:
		_isolated_view.refresh()
	else:
		_preview_view.show_assembly(
			_unit.shell.root, _material_table, WorldPalette.team_color(_unit.squad_id)
		)
