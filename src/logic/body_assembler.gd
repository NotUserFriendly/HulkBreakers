class_name BodyAssembler
extends RefCounted

## Builds a `Unit` from a `ShellTemplate` (structure) + `Loadout`
## (discretionary fill) + a named part pool (docs/01 taskblock02 Pass B).
## Template = structure, loadout = fill; loadout wins on conflict. Replaces
## the old imperative, hand-written `assemble_reference_humanoid()` body —
## same shape, same numbers, now data instead of control flow, so a second
## armament is a second `Loadout`, not a second function.
##
## A missing pool id, an illegal `attaches_to` match, or an occupied socket
## is `push_error`'d with a named reason and fails the whole assembly
## (`null`) — never a silent skip. Deep strike's own scrap-heap scavenging
## (`DeepStrike.assemble_random`) is deliberately not rehomed onto this: it
## fills whatever's free with no fixed skeleton to speak of, which is a
## different algorithm, not a template/loadout pair.

## docs/01 taskblock02 Pass B: the shell root's own surrogate cavity is a
## fixed, well-known socket ID — same idea as `MATRIX` for a bot — so a
## shell built around, say, a SPINAL-sized cavity always exposes it as
## `&"SURROGATE"`, whatever `socket_type` (cavity SIZE) that particular
## template happens to declare.
const SURROGATE_SOCKET_ID := &"SURROGATE"


## `occupant` docks directly into the assembled root part's own `MATRIX`
## socket — a bot (docs/00: matrix + shell, no surrogate). For a cyborg
## (shell + surrogate + matrix), see `assemble_cyborg`, which docks the
## matrix into a surrogate first and attaches THAT into the shell.
static func assemble(
	template: ShellTemplate,
	loadout: Loadout,
	pool: Dictionary,
	occupant: Matrix,
	cell: Vector2i,
	squad_id: int = 0
) -> Unit:
	var root: Part = _build_root(template, pool)
	if root == null:
		return null
	if not root.dock_matrix(occupant):
		push_error("BodyAssembler: root part %s cannot host a matrix" % root.id)
		return null
	return _finish(root, template, loadout, pool, occupant, cell, squad_id)


## docs/04 taskblock02 Pass D1: a cyborg — `matrix` docks inside a
## freshly-built surrogate at `tier` (`SurrogateLadder.build_surrogate`),
## and that whole surrogate (not the bare matrix) attaches into the shell
## root's own `SURROGATE_SOCKET_ID` socket via the ordinary
## `socket_type in attaches_to` legality check (docs/04 Pass D2: the
## tier's `attaches_to` is derived from `ladder`, so this is legal exactly
## when the tier actually fits the cavity's own size). Everything past
## that point — mounts, loadout — is identical to `assemble`.
static func assemble_cyborg(
	template: ShellTemplate,
	loadout: Loadout,
	pool: Dictionary,
	matrix: Matrix,
	tier: SurrogateTier,
	ladder: Array[SurrogateTier],
	cell: Vector2i,
	squad_id: int = 0
) -> Unit:
	var root: Part = _build_root(template, pool)
	if root == null:
		return null

	var surrogate: Part = SurrogateLadder.build_surrogate(tier, ladder)
	surrogate.dock_matrix(matrix)
	var socket: Socket = PartGraph.find_socket(root, SURROGATE_SOCKET_ID)
	if socket == null:
		push_error("BodyAssembler: %s has no socket id %s" % [root.id, SURROGATE_SOCKET_ID])
		return null
	if not PartGraph.is_legal_attachment(surrogate, socket):
		push_error(
			(
				"BodyAssembler: %s surrogate cannot attach to socket %s (cavity %s) on %s"
				% [tier.id, SURROGATE_SOCKET_ID, socket.socket_type, root.id]
			)
		)
		return null
	if not PartGraph.attach(surrogate, root, socket):
		push_error(
			(
				"BodyAssembler: attach failed for surrogate %s onto %s#%s"
				% [surrogate.id, root.id, SURROGATE_SOCKET_ID]
			)
		)
		return null

	return _finish(root, template, loadout, pool, matrix, cell, squad_id)


static func _build_root(template: ShellTemplate, pool: Dictionary) -> Part:
	var root: Part = _duplicate_from_pool(pool, template.root_part_id)
	if root == null:
		push_error("BodyAssembler: unknown pool part id %s (root)" % template.root_part_id)
	return root


static func _finish(
	root: Part,
	template: ShellTemplate,
	loadout: Loadout,
	pool: Dictionary,
	occupant: Matrix,
	cell: Vector2i,
	squad_id: int
) -> Unit:
	if not _mount_children(root, template.mounts, loadout, pool):
		return null
	if not _fill_loadout_only_sockets(root, loadout, pool):
		return null

	var shell := Shell.new(root)
	shell.max_mass = template.max_mass
	shell.max_ram = template.max_ram
	shell.shell_reach = template.shell_reach
	return Unit.new(occupant, shell, cell, squad_id)


static func _duplicate_from_pool(pool: Dictionary, part_id: StringName) -> Part:
	var template: Part = pool.get(part_id)
	if template == null:
		return null
	return template.duplicate(true) as Part


## Attaches every Mount under `host`, recursively. A Mount's own `part_id`
## is the default; a `Loadout` entry keyed to that exact `socket_id`
## overrides it (loadout wins on conflict).
static func _mount_children(
	host: Part, mounts: Array[Mount], loadout: Loadout, pool: Dictionary
) -> bool:
	for mount: Mount in mounts:
		var socket: Socket = PartGraph.find_socket(host, mount.socket_id)
		if socket == null:
			push_error("BodyAssembler: %s has no socket id %s" % [host.id, mount.socket_id])
			return false

		var part_id: StringName = mount.part_id
		if loadout != null and loadout.entries.has(mount.socket_id):
			part_id = loadout.entries[mount.socket_id]

		var child: Part = _duplicate_from_pool(pool, part_id)
		if child == null:
			push_error("BodyAssembler: unknown pool part id %s" % part_id)
			return false
		if not PartGraph.is_legal_attachment(child, socket):
			push_error(
				(
					"BodyAssembler: %s cannot attach to socket %s (type %s) on %s"
					% [child.id, mount.socket_id, socket.socket_type, host.id]
				)
			)
			return false
		if not PartGraph.attach(child, host, socket):
			push_error(
				(
					"BodyAssembler: attach failed for %s onto %s#%s"
					% [child.id, host.id, mount.socket_id]
				)
			)
			return false

		if not _mount_children(child, mount.children, loadout, pool):
			return false
	return true


## Fills every still-empty socket, anywhere in the already-mounted tree,
## whose own `id` a `Loadout` entry names — the discretionary sockets a
## Mount never touched (a hand's GRIP: which weapon, if any, is not part of
## the fixed skeleton).
static func _fill_loadout_only_sockets(root: Part, loadout: Loadout, pool: Dictionary) -> bool:
	if loadout == null:
		return true
	for part: Part in PartGraph.walk(root):
		for socket: Socket in part.sockets:
			if socket.occupant != null or socket.id == &"" or not loadout.entries.has(socket.id):
				continue
			var part_id: StringName = loadout.entries[socket.id]
			var child: Part = _duplicate_from_pool(pool, part_id)
			if child == null:
				push_error("BodyAssembler: unknown pool part id %s" % part_id)
				return false
			if not PartGraph.is_legal_attachment(child, socket):
				push_error(
					(
						"BodyAssembler: %s cannot attach to socket %s (type %s) on %s"
						% [child.id, socket.id, socket.socket_type, part.id]
					)
				)
				return false
			if not PartGraph.attach(child, part, socket):
				push_error(
					(
						"BodyAssembler: attach failed for %s onto %s#%s"
						% [child.id, part.id, socket.id]
					)
				)
				return false
	return true
