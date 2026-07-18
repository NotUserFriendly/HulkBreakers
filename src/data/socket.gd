class_name Socket
extends Resource

## Attachment is declared by the part, matched by the socket type — never
## keyed to a specific parent (docs/01):
##
##   legal(part, socket) := socket.socket_type in part.attaches_to
##                           and socket.occupant == null
##
## `socket_type` is an open StringName, never an enum — new content must
## never need a code edit.

@export var socket_type: StringName = &""
@export var occupant: Part = null

## WHICH socket this is, among possibly several of the same `socket_type` on
## one host part (docs/01 taskblock02 Pass B) — `&"ARMOR_FRONT"` vs.
## `&"ARMOR_REAR"`, `&"SHOULDER_L"` vs. `&"SHOULDER_R"`. `socket_type` alone
## governs legality (docs/01's inversion is untouched); `id` governs which
## one an assembler targets, via `PartGraph.find_socket`, instead of relying
## on declaration order (`find_free_socket` picking "whichever is free
## first" is a landmine: swap two lines in a pool and a plate silently
## mounts on the wrong face). Unique per host part, not globally — an open
## StringName, never an enum. Empty by default so un-migrated content
## doesn't need one; `find_free_socket` never looks at it.
@export var id: StringName = &""

## The attachment frame, in the HOST part's own local space (docs/02/10,
## Phase 12.0): where and how the occupant sits relative to the part this
## socket lives on. Identity by default, so un-migrated content still
## composes correctly — the occupant simply sits at the host's own origin.
@export var transform: Transform3D = Transform3D.IDENTITY

## taskblock-09 C0: runtime HP of THIS socket's own connection to whatever
## it holds — copied from the occupant's `Part.joint_hp` at attach time
## (`PartGraph.attach`), never authored here directly (docs/01's
## inversion: the CHILD declares how hard it is to sever, not the parent
## socket). 1/1 by default, matching `Part.joint_hp`'s own deliberately
## fragile default, so a socket whose occupant was set directly
## (`socket.occupant = x`, bypassing `PartGraph.attach` — most existing
## fixtures) still severs in one hit rather than reading 0/0.
@export var joint_hp: int = 1
@export var joint_hp_max: int = 1

## taskblock-09 D: a joint isn't a Part, but Region/HitResult are typed to
## carry one (`region.part`) — this is that placeholder identity, lazily
## created and cached so the SAME joint keeps the SAME object identity
## across every projection, never a real part in anyone's socket tree: no
## material, no hp, no volume of its own (BodyProjector supplies its own
## small synthetic box). `region.socket`, not `region.part`, is what tells
## resolve_shot this is a joint at all — this exists purely so existing
## Part-typed fields (logging text, HitResult.part) have something sane to
## show, never as a second way to detect a joint hit.
var _joint_handle: Part = null


func joint_handle() -> Part:
	if _joint_handle == null:
		_joint_handle = Part.new()
	_joint_handle.id = &"%s_joint" % occupant.id if occupant != null else &"empty_joint"
	return _joint_handle


func _init(
	p_socket_type: StringName = &"",
	p_transform: Transform3D = Transform3D.IDENTITY,
	p_id: StringName = &""
) -> void:
	socket_type = p_socket_type
	transform = p_transform
	id = p_id


## docs/09 taskblock06 Pass B: the seam a future rig posing system slots
## into. Today just `transform`, the authored static frame — later this
## returns the joint's actual POSED transform sampled from a rig, and the
## four places composing a socket-chain transform (BodyProjector,
## UnitGeometry, and anything reading a BoxPlacement built from either)
## change nothing, because they already call this instead of reading
## `transform` directly.
func current_transform() -> Transform3D:
	return transform
