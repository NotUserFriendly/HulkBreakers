class_name BuilderController
extends RefCounted

## docs/10 taskblock05 G: a UI over ShellTemplate + Loadout + BodyAssembler
## and nothing more — "the builder is the best test the assembler will
## ever get." Every assembly goes through BodyAssembler, the exact same
## call the game itself makes; there is no parallel path. Pure, headless-
## testable — BuilderScene only ever reads this and draws what it says.

var template_id: StringName = ShellTemplates.DEFAULT_ID
var loadout: Loadout = Loadout.new()
var pose_id: StringName = &"IDLE"
## part_id -> Part template. Defaults to the reference humanoid's own pool
## (docs/01) since that's the only real body shape today; a builder for a
## different template swaps this in along with template_id.
var pool: Dictionary = DeepStrike.reference_humanoid_pool()

var _matrix: Matrix = Matrix.new()


## Structurally identical to what BodyAssembler would build in code for
## this same template+loadout, because it IS that same call — null if the
## template id is unknown or the assembly is illegal (BodyAssembler's own
## push_error already named why, on stderr).
func assemble() -> Unit:
	var template: ShellTemplate = ShellTemplates.by_id(template_id)
	if template == null:
		return null
	var unit: Unit = BodyAssembler.assemble(template, loadout, pool, _matrix, Vector2i.ZERO)
	if unit != null:
		unit.pose = Poses.by_id(pose_id)
	return unit


## Click an empty socket -> part picker -> attach: sets the loadout entry
## and lets the next assemble() pick it up. Click a filled socket -> this
## same call replaces it (loadout wins on conflict, BodyAssembler's own
## rule) — a builder never has to detach before reattaching.
func set_part(socket_id: StringName, part_id: StringName) -> void:
	loadout.entries[socket_id] = part_id


## Click a filled socket -> remove: erases the loadout override. Only a
## genuinely EMPTY result for a loadout-only socket (docs/01 taskblock02
## Pass B — a hand's GRIP, say, which BodyAssembler's own
## _fill_loadout_only_sockets treats as "still empty" absent an entry). A
## Mount-covered structural socket has no "unmounted" state at all in this
## data model — the fixed skeleton always attaches its own default — so
## clearing one of those just reverts to whatever the template itself
## puts there, an honest limit of the model, not something to fake around.
func clear_socket(socket_id: StringName) -> void:
	loadout.entries.erase(socket_id)


## docs/10 taskblock05 G4: "the picker earns its keep by showing what
## DOESN'T fit." Every pool part against one socket, split into legal
## (attaches on click) and illegal (greyed, with the reason a designer
## would need to fix the data) — checked against `shell`, the already-
## assembled unit's own shell, so mass/RAM projections are real numbers,
## not guesses.
func candidates_for(shell: Shell, socket: Socket) -> Dictionary:
	var legal: Array[Part] = []
	var illegal: Array[Dictionary] = []
	for part_id: StringName in pool:
		var candidate: Part = pool[part_id] as Part
		var reason: String = _illegal_reason(candidate, socket, shell)
		if reason == "":
			legal.append(candidate)
		else:
			illegal.append({"part": candidate, "reason": reason})
	return {"legal": legal, "illegal": illegal}


static func _illegal_reason(candidate: Part, socket: Socket, shell: Shell) -> String:
	if socket.occupant != null:
		return "socket occupied"
	if not (socket.socket_type in candidate.attaches_to):
		return (
			"wrong attaches_to: socket wants %s, part attaches to %s"
			% [socket.socket_type, candidate.attaches_to]
		)
	var projected_mass: float = shell.carried_mass() + candidate.mass
	if projected_mass > shell.max_mass:
		return "would exceed max_mass by %.1f" % (projected_mass - shell.max_mass)
	var projected_ram: float = shell.total_ram() + candidate.ram_cost
	if projected_ram > shell.max_ram:
		return "would exceed max_ram by %.1f" % (projected_ram - shell.max_ram)
	return ""


## docs/10 taskblock05 G3: live validation against the three constraints
## (docs/05) plus armed status and inert parts — every number from Shell's
## own resolvers or DeepStrike's existing fuzz-test checks, never
## re-summed here.
func validate(unit: Unit) -> Dictionary:
	if unit == null:
		return {
			"mass": 0.0,
			"max_mass": 0.0,
			"ram": 0.0,
			"max_ram": 0.0,
			"armed": false,
			"violations": ["no unit assembled"],
		}
	return {
		"mass": unit.shell.carried_mass(),
		"max_mass": unit.shell.max_mass,
		"ram": unit.shell.total_ram(),
		"max_ram": unit.shell.max_ram,
		"armed": DeepStrike.is_armed(unit),
		"violations": DeepStrike.validate_assembly(unit),
	}


## docs/10 taskblock05 G5: "load a live unit into the builder to inspect
## or edit it." Records only genuinely loadout-addressable sockets (never
## Mount-covered ones) — a socket `id` is only unique WITHIN one part's
## own sockets list (docs/01 taskblock02 Pass B: `find_socket` is never
## cross-part), so several different parts perfectly legitimately reuse
## the same id (every cladding socket in the reference humanoid is plainly
## `&"CLADDING"`). `_fill_loadout_only_sockets` and `_mount_children`'s own
## override check both match `Loadout.entries` GLOBALLY by that id, so
## recording one of those non-unique ids here would silently force every
## OTHER socket sharing it (an arm's cladding, say) to whatever the last
## one visited happened to be. Skipping Mount-covered sockets entirely
## keeps this to the same discretionary set default_loadout() itself
## would ever set (GRIP_L/GRIP_R), the only ids this template actually
## keeps unique on purpose.
func load_from_unit(unit: Unit) -> void:
	var mount_covered: Dictionary = {}  # socket_id -> true
	var template: ShellTemplate = ShellTemplates.by_id(template_id)
	if template != null:
		_collect_mount_ids(template.mounts, mount_covered)

	var entries: Dictionary = {}
	for part: Part in PartGraph.walk(unit.shell.root):
		for socket: Socket in part.sockets:
			if socket.occupant == null or socket.id == &"" or mount_covered.has(socket.id):
				continue
			entries[socket.id] = socket.occupant.id
	loadout = Loadout.new(entries)


static func _collect_mount_ids(mounts: Array[Mount], out: Dictionary) -> void:
	for mount: Mount in mounts:
		out[mount.socket_id] = true
		_collect_mount_ids(mount.children, out)


## docs/10 taskblock05 G5: presets feed everything through this one path —
## save/load never touches a serialized Unit, only template+loadout+pose,
## so "load a preset" and "load from battle" both end up producing
## whatever assemble() would build for that data, nothing hidden.
func apply_preset(preset: BotPreset) -> void:
	template_id = preset.template_id
	loadout = preset.loadout
	pose_id = preset.pose_id


func to_preset(preset_name: String) -> BotPreset:
	return BotPreset.new(preset_name, template_id, loadout, pose_id)
