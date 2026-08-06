class_name PartsListModule
extends ViewModule

## **The editor's parts list, in the Inspect slot.** taskblock-58 Pass E.
##
## The taskblock: *"Every Place tool opens a parts list on the right, in the Inspect slot,
## toggleable from UI buttons."*
##
## ## Why it shares Inspect's slot, said where the sharing happens
##
## **While placing you cannot be selecting.** That was the taskblock's argument and it was a claim
## about the author's intent; Pass D made it a claim about the code. `select` and the three
## `place_*` verbs are entries in one vocabulary and `active_tool` holds exactly one of them, so
## "the author is placing" and "the author is selecting" are mutually exclusive **by construction**
## rather than by convention. Two surfaces answering two halves of one state can share a rect
## without a conflict, and `_yield_inspect` is where that is enforced rather than assumed.
##
## Read this before deciding the two collide: `test_surfaces_do_not_overlap.gd` resolves a module's
## rect only when its control `is_visible_in_tree()`, so the exclusion below is exactly what keeps
## the shared slot honest there.
##
## ## One widget, two callers
##
## `EditorBarModule` used to build its own centred `SearchableList` and open it for both the place
## verbs and Load. **That list moved here rather than being duplicated** — the bar asks the context
## for this module and opens the same widget. Load opens it too, in this slot, which is the one
## oddity of the arrangement and is deliberate: a second list would be two widgets to keep in step
## for a board picker that behaves identically.

## The one searchable list. Public because the bar drives it and the tests read back what it offers
## rather than re-deriving the filter.
var list: SearchableList = null


func module_id() -> StringName:
	return &"parts_list"


## The same slot `InspectModule` takes. See the class note — the two are mutually exclusive by
## construction, so this is a share rather than a collision.
func preferred_slot() -> StringName:
	return ModuleSlots.INSPECT_PANEL


func is_showing() -> bool:
	return list != null and list.visible


func _mount() -> void:
	list = SearchableList.new()
	var slot: Control = context.slots.get(preferred_slot()) if context != null else null
	if slot != null:
		slot.add_child(list)
		list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	elif context != null and context.ui_root != null:
		# The stand-alone case: the list is real and can still be opened and read back; it simply
		# has nowhere of its own to be drawn. Same degradation `EditorBarModule` kept when it owned
		# this widget.
		context.ui_root.add_child(list)
		list.set_anchors_preset(Control.PRESET_CENTER)
		list.position = context.ui_root.size * 0.5 - SearchableList.PANEL_SIZE * 0.5
	else:
		add_child(list)
	list.close()


## Opens the list on `entries`, and takes the slot from Inspect while it is up.
func open(title: String, entries: Array[StringName]) -> void:
	if list == null:
		return
	_yield_inspect()
	list.open(title, entries)


func close() -> void:
	if list != null:
		list.close()


## **The exclusion, in one place.** Inspect is closed rather than merely drawn under, because two
## surfaces stacked in one rect is the collision the shared slot is only safe without.
func _yield_inspect() -> void:
	if context == null:
		return
	var inspect: InspectModule = context.module(&"inspect") as InspectModule
	if inspect != null and inspect.panel != null and inspect.panel.visible:
		inspect.panel.close()
