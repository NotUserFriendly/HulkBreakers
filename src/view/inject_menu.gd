class_name InjectMenu
extends RefCounted

## taskblock-30: the ONE injection-menu item list/dispatch, shared by
## `SpectatorOverlay` (hover-targeted — spectator has no selection concept)
## and `SquadControlOverlay` (selection-targeted — a player bout has a real
## one) — CLAUDE.md "no parallel systems": two overlays offering the same
## debug verbs must never mean two independently-maintained copies of
## "what does Inject do." Each overlay still owns its own button/PopupMenu
## instance (a `PopupMenu` is a `Node`, needs a real parent in ITS OWN
## tree) and its own target resolution; this owns only the shared item
## list and the dispatch into `BoutInjector` — the exact same calls
## programmatic/scripted use already makes, never a UI-only mutation.
##
## A handful of representative verbs (the taskblock's own worked
## examples: force current, force a state, force overwatch), not a full
## form-builder for every `BoutInjector` verb.

const ITEMS: Array[String] = [
	"[*] Force Current Unit",
	"[*] Set HP to 0 (root part)",
	"[*] Force Overwatch Arm (first weapon)",
]


static func populate(menu: PopupMenu) -> void:
	for i in range(ITEMS.size()):
		menu.add_item(ITEMS[i], i)


static func handle_id(id: int, injector: BoutInjector, target: Unit) -> void:
	match id:
		0:
			injector.force_current_unit(target)
		1:
			injector.set_part_hp(target, target.shell.root.id, 0)
		2:
			var weapon: Part = DeepStrike.find_operable_weapon(target)
			if weapon != null:
				injector.force_overwatch_arm(target, weapon.id)
