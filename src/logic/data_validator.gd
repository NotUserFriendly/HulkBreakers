class_name DataValidator
extends RefCounted

## taskblock-10 Pass D: "the validator is shared with the Resource Editor
## (taskblock-11) — one module, two callers" (editor validates on save,
## `DataLibrary` validates on load). Dispatches on the resource's own
## GDScript type (`is`), never a separate closed `kind` enum — adding a
## new definition type means one more branch here, not a new module.

## docs/03/taskblock-09 A0: Part.failure_mode's own closed vocabulary.
const FAILURE_MODES: Array[StringName] = [
	&"MANGLE", &"DISABLE", &"DETONATE", &"FRAGMENT", &"MELTDOWN"
]
## taskblock-10 Pass A: Part.render_primitive's own closed vocabulary.
const RENDER_PRIMITIVES: Array[StringName] = [&"BOX", &"CYLINDER", &"SPHERE", &"CAPSULE"]
## The ammo draft's own stack_type vocabulary (taskblock-10 Pass E,
## HOOK ONLY — no system reads these yet).
const STACK_TYPES: Array[StringName] = [&"", &"BURN", &"BLEED"]


## Empty array = valid. Never throws, never silently drops a bad row —
## every failure comes back as a named `ValidationError`.
static func validate(resource: Resource) -> Array[ValidationError]:
	if resource is Part:
		return _validate_part(resource as Part)
	if resource is AmmoDef:
		return _validate_ammo(resource as AmmoDef)
	if resource is MaterialEntry:
		return _validate_material(resource as MaterialEntry)
	if resource is BotPreset:
		return _validate_preset(resource as BotPreset)
	if resource is WoundDef:
		return _validate_wound(resource as WoundDef)
	if resource is VariantFamily:
		return _validate_variant_family(resource as VariantFamily)
	return []


static func _validate_part(part: Part) -> Array[ValidationError]:
	var errors: Array[ValidationError] = []
	var row_id: StringName = part.id
	if part.id == &"":
		errors.append(ValidationError.new(row_id, &"id", "id must not be empty"))
	if part.failure_mode not in FAILURE_MODES:
		errors.append(
			ValidationError.new(
				row_id,
				&"failure_mode",
				"'%s' is not one of %s" % [part.failure_mode, FAILURE_MODES]
			)
		)
	if part.render_primitive not in RENDER_PRIMITIVES:
		errors.append(
			ValidationError.new(
				row_id,
				&"render_primitive",
				"'%s' is not one of %s" % [part.render_primitive, RENDER_PRIMITIVES]
			)
		)
	# Referential check, not a format check — an empty material is legal
	# (docs/10's "no pool part may have material == ''" is a runtime
	# assembly invariant, DeepStrike.validate_assembly's own job, not an
	# authoring-time one); only a NON-empty material must resolve.
	if part.material != &"" and DataLibrary.get_material(part.material) == null:
		errors.append(
			ValidationError.new(
				row_id, &"material", "references unknown material '%s'" % part.material
			)
		)
	# taskblock-13 Pass B: same referential posture as `material` above —
	# empty (unloaded) is legal, only a non-empty id must resolve. Whether
	# it actually CHAMBERS (family/length match) is a separate, load-time
	# check — WeaponResolver.chamber_error — not an authoring-time one.
	if part.ammo_id != &"" and DataLibrary.get_ammo(part.ammo_id) == null:
		errors.append(
			ValidationError.new(row_id, &"ammo_id", "references unknown ammo '%s'" % part.ammo_id)
		)
	return errors


static func _validate_ammo(ammo: AmmoDef) -> Array[ValidationError]:
	var errors: Array[ValidationError] = []
	var row_id: StringName = ammo.id
	if ammo.id == &"":
		errors.append(ValidationError.new(row_id, &"id", "id must not be empty"))
	if ammo.stack_type not in STACK_TYPES:
		errors.append(
			ValidationError.new(
				row_id, &"stack_type", "'%s' is not one of %s" % [ammo.stack_type, STACK_TYPES]
			)
		)
	if ammo.projectile_num < 1:
		errors.append(ValidationError.new(row_id, &"projectile_num", "must be at least 1"))
	if ammo.case_length < 0.0:
		errors.append(ValidationError.new(row_id, &"case_length", "must not be negative"))
	return errors


static func _validate_material(material: MaterialEntry) -> Array[ValidationError]:
	var errors: Array[ValidationError] = []
	var row_id: StringName = material.id
	if material.id == &"":
		errors.append(ValidationError.new(row_id, &"id", "id must not be empty"))
	var previous_thickness: float = -INF
	for point: Vector2 in material.dt_curve:
		if point.x <= previous_thickness:
			errors.append(
				ValidationError.new(
					row_id,
					&"dt_curve",
					(
						"thickness %.2f is not strictly ascending after %.2f"
						% [point.x, previous_thickness]
					)
				)
			)
		previous_thickness = point.x
	return errors


static func _validate_wound(wound: WoundDef) -> Array[ValidationError]:
	var errors: Array[ValidationError] = []
	var row_id: StringName = wound.id
	if wound.id == &"":
		errors.append(ValidationError.new(row_id, &"id", "id must not be empty"))
	if wound.repair_difficulty < 0.0:
		errors.append(ValidationError.new(row_id, &"repair_difficulty", "must not be negative"))
	return errors


## taskblock-14 Pass A1: a reference profile must actually assemble —
## `template_id` is the one referential check (`ShellTemplates.by_id`);
## `loadout`'s own part ids are validated for free the moment something
## tries to assemble through `BodyAssembler` (a missing/illegal part is
## `BodyAssembler.assemble`'s own null-return, not re-checked here).
static func _validate_preset(preset: BotPreset) -> Array[ValidationError]:
	var errors: Array[ValidationError] = []
	var row_id: StringName = StringName(preset.preset_name)
	if preset.preset_name == "":
		errors.append(ValidationError.new(row_id, &"preset_name", "preset_name must not be empty"))
	if ShellTemplates.by_id(preset.template_id) == null:
		errors.append(
			ValidationError.new(
				row_id, &"template_id", "references unknown template '%s'" % preset.template_id
			)
		)
	return errors


## taskblock-28 Pass A: `variation_amount` is a probability, never a raw
## unbounded number — outside [0, 1] it isn't a "more/less variation" dial
## anymore, it's nonsense (a >1 draw always fires, matching 1.0's own
## already-maximal behavior, but authoring it that way is a content bug,
## not a valid extreme).
static func _validate_variant_family(family_def: VariantFamily) -> Array[ValidationError]:
	var errors: Array[ValidationError] = []
	var row_id: StringName = family_def.id
	if family_def.id == &"":
		errors.append(ValidationError.new(row_id, &"id", "id must not be empty"))
	if family_def.variation_amount < 0.0 or family_def.variation_amount > 1.0:
		errors.append(
			ValidationError.new(
				row_id,
				&"variation_amount",
				"%.2f must be within [0, 1]" % family_def.variation_amount
			)
		)
	return errors
