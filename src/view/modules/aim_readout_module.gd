class_name AimReadoutModule
extends ViewModule

## taskblock-57 Pass D2: **the aim readout, which `stat_panels` used to carry.**
##
## The READING/RESOLVES text beside the dartboard: which body is being read, what the reticle
## resolves to, how many scatter rings and how wide. Every number comes from
## `AimController.resolve()` through `AimView` — this module owns nothing but the label it is
## written into (`docs/08`: no number is born in the view).
##
## ## Why it exists at all
##
## Pass D retires `stat_panels_module`, and the aim readout was a panel inside it. The taskblock's
## own stop-and-report rule is that **a retirement must not silently lose coverage**; it names
## `queue_panel`'s confirmation role, and this is the same shape one module over. Losing it would
## have left the dartboard drawing rings with nothing saying what they resolve to.
##
## ## This is a UI module and the aim view is not, which is not a contradiction
##
## The taskblock says *"the aim view and dartboard are not UI modules and do not become ones — they
## are what the mode switches to."* That is about the `Node3D` geometry: the window quad, the decal,
## the targeting line, all owned by `UnitInputModule` alongside the controller that drives them. **A
## text panel is an ordinary `Control` and an ordinary module**, and making it one is what lets the
## aim mode place it while the battle mode does not have it at all.
##
## ## Placement
##
## The placement table describes the *battle* surface and has no row for this, because it is a
## surface only one mode has. It anchors itself along the bottom of the safe rect — the band the aim
## mode frees by turning the action bar off — and that is **a starting position, not a decision**:
## the supervisor's fine-tuning pass owns where it sits.
##
## Display: it renders what the aim resolved to. It queues nothing.

## Wide enough for the longest READING/RESOLVES line without the panel resizing as the numbers
## change width. Carried over from the panel this replaces rather than re-picked.
const READOUT_SIZE := Vector2(320, 60)

var readout: RichTextLabel = null


func module_id() -> StringName:
	return &"aim_readout"


func _mount() -> void:
	readout = RichTextLabel.new()
	readout.bbcode_enabled = false
	readout.custom_minimum_size = READOUT_SIZE
	readout.add_theme_color_override("default_color", HulkTheme.FOREGROUND)
	# A readout is text, never a target — it must not eat a click meant for the board underneath.
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root: Control = context.ui_root
	if root == null:
		# The stand-alone case taskblock-56 Pass C's acceptance requires: the label is real and the
		# aim view can still write into it; it simply has nowhere to be drawn.
		add_child(readout)
		return
	root.add_child(readout)
	var safe: Rect2 = UiLayout.safe_rect(root.size)
	readout.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	readout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	readout.grow_vertical = Control.GROW_DIRECTION_BEGIN
	readout.position = Vector2(
		safe.get_center().x - READOUT_SIZE.x * 0.5, safe.end.y - READOUT_SIZE.y
	)


## **Handed to whoever owns the dartboard**, exactly as `stat_panels` used to do it. `AimView` lives
## with `UnitInputModule` because it is driven by that module's controller; the two are joined here
## rather than by one owning the other, and either end being absent is legal.
func link() -> void:
	var input: ViewModule = context.module(&"unit_input")
	if input != null and (input as UnitInputModule).aim_view != null:
		(input as UnitInputModule).aim_view.set_readout(readout)


## The aim view writes into this label for as long as it holds it, so a module going away has to
## take the reference with it — otherwise the next aim writes into a freed node.
func _unmount() -> void:
	var input: ViewModule = context.module(&"unit_input")
	if input != null and (input as UnitInputModule).aim_view != null:
		(input as UnitInputModule).aim_view.set_readout(null)
