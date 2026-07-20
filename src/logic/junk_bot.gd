class_name JunkBot
extends RefCounted

## taskblock-28 Pass A: a small, standalone body shape purpose-built to
## exercise seeded variant generation — distinct from `DeepStrike`'s own
## "reference humanoid" (docs/01's known-good, fully-clad, fully-armed
## body every other fixture assumes). A junk_bot is deliberately thinner
## (torso, head, two arms, two legs — no forearms/hands/weapons; it's
## scrap, not a combatant) and, critically, gives EVERY limb's own
## ARMOR/CLADDING socket a UNIQUE id (`ARMOR_ARM_L` vs `ARMOR_ARM_R`, not
## a shared `&"ARMOR"` both sides collide on) so a flat `Loadout` can
## address — and a `VariantFamily` can independently omit/swap — one
## limb's plating without touching its mirror. The reference humanoid
## deliberately keeps its own arm/forearm ARMOR/CLADDING ids generic
## (nothing before this pass ever needed to address them independently);
## retrofitting that shared content was out of scope for landing seeded
## variation, so this is new, narrow content instead, the same
## `reference_humanoid_pool()` "duplicate + rename this copy's own socket
## ids" trick already uses for `hand_l`/`hand_r`/`LEG_ARMOR`.

const TEMPLATE_ID := &"junk_bot"


static func template() -> ShellTemplate:
	var arm_mount := func(shoulder_id: StringName, side: String) -> Mount:
		return Mount.new(
			shoulder_id,
			StringName("arm_%s" % side),
			[
				Mount.new(StringName("ARMOR_ARM_%s" % side.to_upper()), &"plate_small_steel"),
				Mount.new(StringName("CLADDING_ARM_%s" % side.to_upper()), &"arm_cladding"),
			]
		)
	var leg_mount := func(hip_id: StringName, side: String) -> Mount:
		return Mount.new(
			hip_id,
			StringName("leg_%s" % side),
			[
				Mount.new(StringName("ARMOR_LEG_%s" % side.to_upper()), &"plate_medium_sheet_steel"),
				Mount.new(StringName("CLADDING_LEG_%s" % side.to_upper()), &"leg_cladding"),
			]
		)

	return ShellTemplate.new(
		&"torso",
		[
			(
				Mount
				. new(
					&"NECK",
					&"head",
					[
						Mount.new(&"ARMOR", &"plate_small_ceramic"),
						Mount.new(&"CLADDING", &"head_cladding"),
					]
				)
			),
			arm_mount.call(&"SHOULDER_L", "l"),
			arm_mount.call(&"SHOULDER_R", "r"),
			leg_mount.call(&"HIP_L", "l"),
			leg_mount.call(&"HIP_R", "r"),
			Mount.new(&"ARMOR_FRONT", &"plate_large_steel"),
			Mount.new(&"CLADDING", &"torso_cladding"),
		],
		DeepStrike.DEFAULT_MAX_MASS,
		DeepStrike.DEFAULT_MAX_RAM
	)


## `DataLibrary.parts_pool()` plus four renamed duplicates of `arm`/`leg` —
## one per side, each with its own limb's ARMOR/CLADDING socket ids
## rewritten to the unique `_L`/`_R` variants `template()` mounts against.
## Same trick, same reasoning, as `DeepStrike.reference_humanoid_pool()`'s
## own `hand_l`/`hand_r`/renamed-`LEG_ARMOR` copies.
static func pool() -> Dictionary:
	var built_pool: Dictionary = {}
	for part_template: Part in DataLibrary.parts_pool():
		built_pool[part_template.id] = part_template

	for side in ["l", "r"]:
		var arm: Part = (built_pool[&"arm"] as Part).duplicate(true)
		arm.id = StringName("arm_%s" % side)
		_rename_socket(arm, &"ARMOR", StringName("ARMOR_ARM_%s" % side.to_upper()))
		_rename_socket(arm, &"CLADDING", StringName("CLADDING_ARM_%s" % side.to_upper()))
		built_pool[arm.id] = arm

		var leg: Part = (built_pool[&"leg"] as Part).duplicate(true)
		leg.id = StringName("leg_%s" % side)
		_rename_socket(leg, &"ARMOR", StringName("ARMOR_LEG_%s" % side.to_upper()))
		_rename_socket(leg, &"CLADDING", StringName("CLADDING_LEG_%s" % side.to_upper()))
		built_pool[leg.id] = leg

	return built_pool


static func _rename_socket(part: Part, from_id: StringName, to_id: StringName) -> void:
	for socket: Socket in part.sockets:
		if socket.id == from_id:
			socket.id = to_id


## The undistorted base — every limb fully armored and clad, nothing
## omitted or swapped. `VariantGenerator` mutates a COPY of this preset's
## own loadout; this is never mutated itself.
static func base_preset() -> BotPreset:
	return BotPreset.new("junk_bot", TEMPLATE_ID, Loadout.new({}), &"IDLE", &"junk_bot", "")


static func assemble(matrix: Matrix, cell: Vector2i, squad_id: int = 0) -> Unit:
	return BodyAssembler.assemble(template(), Loadout.new({}), pool(), matrix, cell, squad_id)


## `DeepStrike.assemble_from_preset`'s own mirror, but pooled against
## `JunkBot.pool()` (never `reference_humanoid_pool()` — that pool has no
## `arm_l`/`arm_r`/`leg_l`/`leg_r` entries at all, so a junk_bot preset's
## own loadout overrides would fail to resolve through it). A separate
## entry point, not a change to `DeepStrike.assemble_from_preset` itself —
## that function's one hardcoded pool is exactly right for every OTHER
## preset (every template that exists before this pass draws from the
## reference humanoid's own skeleton); junk_bot is the first template
## that needs a different one.
static func assemble_from_preset(
	preset: BotPreset, matrix: Matrix, cell: Vector2i, squad_id: int = 0
) -> Unit:
	return BodyAssembler.assemble(template(), preset.loadout, pool(), matrix, cell, squad_id)
