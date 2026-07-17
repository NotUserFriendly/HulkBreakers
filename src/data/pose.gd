class_name Pose
extends Resource

## docs/10 taskblock05 F2: a pose is socket transform overrides — nothing
## else. Applied when composing the tree (Phase 12.0 already composes
## socket transforms), so this is the whole feature: snap, no animation,
## no interpolation. Keyed by socket id (docs/01 taskblock02 Pass B) — the
## same id Mount/find_socket already target, open StringName vocabulary,
## so adding a pose is data, never a code change.
##
## An override COMPOSES onto the socket's own authored transform
## (`socket.transform * overrides[socket.id]`), never replaces it — a
## pose stays correct regardless of where a given template actually put
## that socket, since it only adds a local delta on top.
##
## The reserved id `Poses.ROOT_SOCKET_ID` is a socket id no real part ever
## declares — it composes onto the WHOLE assembly's own placement (applied
## before any child socket), the only way a pose can move the root's own
## boxes at all, since the root has no incoming socket of its own to
## override.
@export var overrides: Dictionary = {}  # StringName socket_id -> Transform3D
