class_name TooltipModule
extends ViewModule

## taskblock-56 Pass C: THE one tooltip renderer, plus the controller that decides what it says.
##
## **One instance, shared by every panel that wants a tooltip** — taskblock-07 Pass F1/F2's rule,
## and the reason this is a module rather than a field on each panel. `ActionBarModule`,
## `QueuePanelModule` and `InspectModule` all look it up through `ModuleContext` instead of each
## constructing one, which is what keeps a single tooltip on screen at a time.
##
## **Mount this before anything that wants it.** A mode's module list is ordered, and a module that
## reads another must come after it. `_tooltip_view()` on the readers degrades to null rather than
## erroring, so getting the order wrong loses tooltips rather than crashing — worth knowing, since
## the failure is quiet.
##
## **`view` is added to `ui_root` last**, so it draws above every other panel. That is the whole
## reason `SquadControlOverlay` constructed it early and parented it at the very end of `_build_ui`;
## the module keeps both halves by constructing in `_mount` and re-parenting in `raise`.

var view: TooltipView = null
var controller: TooltipController = null


func module_id() -> StringName:
	return &"tooltip"


func _mount() -> void:
	view = TooltipView.new()
	controller = TooltipController.new()
	add_child(controller)
	if context.tactics != null:
		controller.setup(context.tactics, view, DataLibrary.material_table())
	# Parented immediately so the module stands alone; `raise()` moves it to the top of the draw
	# order once the mode has finished mounting everything else.
	var root: Control = context.ui_root
	if root != null:
		root.add_child(view)
	else:
		add_child(view)


## Moves the tooltip to the end of `ui_root`'s children, so it draws over every panel mounted after
## it. Called once by the mode when its module list is exhausted.
func raise() -> void:
	var root: Control = context.ui_root if context != null else null
	if root != null and view != null and view.get_parent() == root:
		root.move_child(view, root.get_child_count() - 1)


## `BR31.01`: a stale tooltip left over from hovering the 3D board right before the cursor crossed
## onto a Control. `TacticsController`'s hover tracking lives in `_unhandled_input`, which never
## fires while the cursor sits over a Control with the default `STOP` filter — every `Button` — so
## nothing ever told the tooltip to go away. Panels connect their own `mouse_entered` to this.
func hide_stale() -> void:
	if view != null:
		view.hide_tooltip()
