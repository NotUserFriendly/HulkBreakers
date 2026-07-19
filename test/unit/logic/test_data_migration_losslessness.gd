extends GutTest

## taskblock-10 Pass C: "the migration must be provably lossless." The
## fixture below is a hand-authored snapshot of what
## `DeepStrike.default_part_pool()` / `MaterialTable.default_table()`
## produced the moment `tools/migrate_data.gd` walked them into
## `res://data/` — transcribed from that code, not re-derived from it, per
## CLAUDE.md ("if a test needs a concrete list, the test authors it as a
## fixture"). Both hardcoded generators are gone; this is what guards
## against silent drift in the checked-in `.tres` files from here on,
## independent of them ever existing again.
##
## taskblock-12 Pass C: a fixture checked only against itself (the .tres
## data compared to a second hand-typed copy of the same values) can't
## catch a value mis-transcribed into both — it proves internal
## consistency, not a faithful port. Closed by actually re-running the
## real deleted generators — restored verbatim from git commit
## eb939471637d79b868b73fe93cd12c58ad4b0a69 (the parent of 5ed60b8, which
## deleted them) — and diffing their live output against every dict below,
## field by field, socket by socket, box by box: zero mismatches. This
## fixture is confirmed to BE that generators' real output, not a
## plausible-looking re-typing of it.

## id -> {hp, mass, ram_cost, material, attaches_to, tags, sockets:
## [[type, id], ...], volume_sizes: [Vector3, ...], failure_mode,
## mangles_into, detonate_damage, detonate_radius, meltdown_turns, damage,
## capabilities, requires, provides_actions, scatter_count, ap_cost}
## Every key defaults to Part.new()'s own default when omitted below.
const EXPECTED_PARTS: Dictionary = {
	&"torso":
	{
		"hp": 12,
		"mass": 20.0,
		"ram_cost": 5.0,
		"material": &"artificial_bone",
		"tags": [&"ROOT"],
		"sockets":
		[
			[&"ARMOR", &"ARMOR_FRONT"],
			[&"ARMOR", &"ARMOR_REAR"],
			[&"SHOULDER", &"SHOULDER_L"],
			[&"SHOULDER", &"SHOULDER_R"],
			[&"HIP", &"HIP_L"],
			[&"HIP", &"HIP_R"],
			[&"NECK", &"NECK"],
			[&"BACK", &"BACK"],
			[&"MATRIX", &"MATRIX"],
			[&"CLADDING_TORSO", &"CLADDING"],
		],
		# taskblock-20 Pass A: "the torso is a skeleton, not a solid box" —
		# a deliberate, documented rebuild
		# (tools/author_taskblock20_skeleton.gd), not drift. The single
		# solid box (0.50 x 0.70 x 0.28) that used to hide the reactor/
		# matrix behind geometry is now three thin struts (spine, shoulder
		# brace, hip brace).
		"volume_sizes":
		[Vector3(0.1, 0.6, 0.1), Vector3(0.4, 0.08, 0.08), Vector3(0.3, 0.08, 0.08)],
	},
	&"head":
	{
		"hp": 6,
		"mass": 3.0,
		"ram_cost": 1.0,
		"material": &"artificial_bone",
		"attaches_to": [&"NECK"],
		"sockets": [[&"ARMOR", &"ARMOR"], [&"MATRIX", &"MATRIX"], [&"CLADDING_HEAD", &"CLADDING"]],
		"volume_sizes": [Vector3(0.22, 0.24, 0.22)],
	},
	&"arm":
	{
		"hp": 6,
		"mass": 3.0,
		"material": &"artificial_bone",
		"attaches_to": [&"SHOULDER"],
		"sockets": [[&"ARMOR", &"ARMOR"], [&"FOREARM", &"FOREARM"], [&"CLADDING_ARM", &"CLADDING"]],
		"volume_sizes": [Vector3(0.14, 0.34, 0.14)],
	},
	&"forearm":
	{
		"hp": 5,
		"mass": 2.5,
		"material": &"artificial_bone",
		"attaches_to": [&"FOREARM"],
		"sockets":
		[
			[&"ARMOR", &"ARMOR"],
			[&"FOREARM_TOOL", &"FOREARM_TOOL"],
			[&"WRIST", &"WRIST"],
			[&"CLADDING_FOREARM", &"CLADDING"],
		],
		"volume_sizes": [Vector3(0.12, 0.34, 0.12)],
	},
	&"hand":
	{
		"hp": 3,
		"mass": 1.0,
		"ram_cost": 1.0,
		"material": &"artificial_muscle",
		"attaches_to": [&"WRIST"],
		"capabilities": [&"TRIGGER", &"GRIP", &"POWER"],
		"sockets": [[&"GRIP", &"GRIP"]],
		"volume_sizes": [Vector3(0.10, 0.10, 0.10)],
	},
	&"saw_hand":
	{
		"hp": 4,
		"mass": 1.2,
		"material": &"artificial_muscle",
		"attaches_to": [&"WRIST"],
		"capabilities": [&"SUPPORT"],
		"provides_actions": [&"saw"],
		"volume_sizes": [Vector3(0.10, 0.10, 0.10)],
	},
	&"leg":
	{
		"hp": 6,
		"mass": 6.0,
		"material": &"artificial_bone",
		"attaches_to": [&"HIP"],
		"sockets": [[&"ARMOR", &"ARMOR"], [&"CLADDING_LEG", &"CLADDING"]],
		"volume_sizes": [Vector3(0.16, 0.90, 0.16)],
	},
	&"plate_large_steel":
	{
		"hp": 8,
		"mass": 4.0,
		"material": &"steel",
		"attaches_to": [&"ARMOR"],
		"mangles_into": &"metal_scraps",
		"volume_sizes": [Vector3(0.54, 0.66, 0.05)],
	},
	&"plate_large_sheet_steel":
	{
		"hp": 5,
		"mass": 2.0,
		"material": &"sheet_steel",
		"attaches_to": [&"ARMOR"],
		"mangles_into": &"metal_scraps",
		"volume_sizes": [Vector3(0.54, 0.66, 0.03)],
	},
	&"plate_small_ceramic":
	{
		"hp": 4,
		"mass": 1.0,
		"material": &"ceramic",
		"attaches_to": [&"ARMOR"],
		"mangles_into": &"metal_scraps",
		"volume_sizes": [Vector3(0.24, 0.20, 0.04)],
	},
	&"plate_small_steel":
	{
		"hp": 4,
		"mass": 1.5,
		"material": &"steel",
		"attaches_to": [&"ARMOR"],
		"mangles_into": &"metal_scraps",
		"volume_sizes": [Vector3(0.16, 0.30, 0.04)],
	},
	&"plate_medium_sheet_steel":
	{
		"hp": 5,
		"mass": 2.0,
		"material": &"sheet_steel",
		"attaches_to": [&"ARMOR"],
		"mangles_into": &"metal_scraps",
		"volume_sizes": [Vector3(0.18, 0.70, 0.04)],
	},
	&"torso_cladding":
	{
		"hp": 6,
		"mass": 3.0,
		"material": &"sheet_steel",
		"attaches_to": [&"CLADDING_TORSO"],
		"mangles_into": &"twisted_sheet_metal",
		"volume_sizes": [Vector3(0.53, 0.73, 0.31)],
	},
	&"head_cladding":
	{
		"hp": 3,
		"mass": 0.5,
		"material": &"sheet_steel",
		"attaches_to": [&"CLADDING_HEAD"],
		"mangles_into": &"twisted_sheet_metal",
		"volume_sizes": [Vector3(0.25, 0.27, 0.25)],
	},
	&"arm_cladding":
	{
		"hp": 3,
		"mass": 1.0,
		"material": &"sheet_steel",
		"attaches_to": [&"CLADDING_ARM"],
		"mangles_into": &"twisted_sheet_metal",
		"volume_sizes": [Vector3(0.17, 0.37, 0.17)],
	},
	&"forearm_cladding":
	{
		"hp": 3,
		"mass": 0.8,
		"material": &"sheet_steel",
		"attaches_to": [&"CLADDING_FOREARM"],
		"mangles_into": &"twisted_sheet_metal",
		"volume_sizes": [Vector3(0.15, 0.37, 0.15)],
	},
	&"leg_cladding":
	{
		"hp": 4,
		"mass": 1.5,
		"material": &"sheet_steel",
		"attaches_to": [&"CLADDING_LEG"],
		"mangles_into": &"twisted_sheet_metal",
		"volume_sizes": [Vector3(0.19, 0.93, 0.19)],
	},
	&"ammo_rack":
	{
		"hp": 4,
		"mass": 3.0,
		"material": &"sheet_steel",
		"attaches_to": [&"BACK"],
		"tags": [&"VOLATILE"],
		"failure_mode": &"DETONATE",
		"detonate_damage": 5.0,
		"detonate_radius": 2.0,
		"volume_sizes": [Vector3(0.20, 0.30, 0.10)],
	},
	&"reactor":
	{
		"hp": 5,
		"mass": 4.0,
		"material": &"sheet_steel",
		"attaches_to": [&"BACK"],
		"tags": [&"POWER_SOURCE", &"VOLATILE"],
		"failure_mode": &"MELTDOWN",
		"meltdown_turns": 2,
		"detonate_damage": 6.0,
		"detonate_radius": 2.0,
		"volume_sizes": [Vector3(0.18, 0.26, 0.10)],
	},
	&"pistol":
	{
		"hp": 3,
		"mass": 1.5,
		"material": &"steel",
		"attaches_to": [&"GRIP"],
		"requires": {&"TRIGGER": 1},
		"damage": 4.0,
		"ap_cost": 1,
		"scatter_count": 2,
		"provides_actions": [&"shoot", &"overwatch"],
		"volume_sizes": [Vector3(0.1, 0.2, 0.4)],
	},
	&"rifle":
	{
		"hp": 4,
		"mass": 3.0,
		"material": &"steel",
		"attaches_to": [&"GRIP"],
		"requires": {&"TRIGGER": 1, &"SUPPORT": 1},
		"damage": 6.0,
		"ap_cost": 2,
		# taskblock-21 Pass H1: "the dartboard reads N rings... re-author each
		# gun's scatter as three: outer/middle/inner" — was 2, deliberately
		# rebuilt to 3, not drift.
		"scatter_count": 3,
		"provides_actions": [&"shoot", &"overwatch"],
		"volume_sizes": [Vector3(0.12, 0.15, 0.7)],
	},
	&"two_handed_sword":
	{
		"hp": 5,
		"mass": 4.0,
		"material": &"steel",
		"attaches_to": [&"GRIP"],
		"requires": {&"GRIP": 1, &"POWER": 1},
		"damage": 8.0,
		"ap_cost": 2,
		"scatter_count": 1,
		"volume_sizes": [Vector3(0.1, 0.1, 1.0)],
	},
}

## id -> {dt, deflect_threshold_deg, color}
const EXPECTED_MATERIALS: Dictionary = {
	&"flesh": {"dt": 0.0, "color": Color("#C98A7A")},
	&"artificial_muscle": {"dt": 1.0, "color": Color("#7A3B33")},
	&"artificial_bone": {"dt": 2.0, "color": Color("#D8CFB4")},
	&"sheet_steel": {"dt": 3.0, "color": Color("#6E7276")},
	&"steel": {"dt": 6.0, "color": Color("#8C949C")},
	&"ceramic": {"dt": 9.0, "color": Color("#C6C9C2")},
	&"reactive": {"dt": 12.0, "color": Color("#C9A227")},
	&"hull_plate": {"dt": 3.0, "color": Color("#6B4A2F")},
}


## "Lossless" means every MIGRATED part survives, unchanged — not that
## `res://data/parts/` may never grow. Real new content (taskblock-13's
## own guns, e.g.) is expected to accumulate on top of the migrated set
## over time; this only asserts the migrated subset is still intact, one
## copy each, never that the pool's total size stays frozen at 22.
func test_every_expected_part_id_is_present_exactly_once() -> void:
	var pool: Array[Part] = DataLibrary.parts_pool()
	var ids: Array = []
	for part: Part in pool:
		ids.append(part.id)
	for expected_id: StringName in EXPECTED_PARTS:
		assert_eq(ids.count(expected_id), 1, "%s must appear exactly once" % expected_id)


func test_every_part_matches_its_pre_migration_snapshot() -> void:
	for id: StringName in EXPECTED_PARTS:
		var expected: Dictionary = EXPECTED_PARTS[id]
		var part: Part = DataLibrary.get_part(id)
		assert_not_null(part, "%s must load from the migrated .tres" % id)
		if part == null:
			continue
		assert_eq(part.hp, expected.get("hp", 1), "%s.hp" % id)
		assert_eq(part.max_hp, expected.get("hp", 1), "%s.max_hp" % id)
		assert_eq(part.mass, expected.get("mass", 0.0), "%s.mass" % id)
		assert_eq(part.ram_cost, expected.get("ram_cost", 0.0), "%s.ram_cost" % id)
		assert_eq(part.material, expected.get("material", &""), "%s.material" % id)
		assert_eq(
			part.attaches_to,
			expected.get("attaches_to", [] as Array[StringName]),
			"%s.attaches_to" % id
		)
		assert_eq(part.tags, expected.get("tags", [] as Array[StringName]), "%s.tags" % id)
		assert_eq(
			part.capabilities,
			expected.get("capabilities", [] as Array[StringName]),
			"%s.capabilities" % id
		)
		assert_eq(part.requires, expected.get("requires", {}), "%s.requires" % id)
		assert_eq(
			part.provides_actions,
			expected.get("provides_actions", [] as Array[StringName]),
			"%s.provides_actions" % id
		)
		assert_eq(
			part.failure_mode, expected.get("failure_mode", &"MANGLE"), "%s.failure_mode" % id
		)
		assert_eq(part.mangles_into, expected.get("mangles_into", &""), "%s.mangles_into" % id)
		assert_eq(
			part.detonate_damage, expected.get("detonate_damage", 0.0), "%s.detonate_damage" % id
		)
		assert_eq(
			part.detonate_radius, expected.get("detonate_radius", 0.0), "%s.detonate_radius" % id
		)
		assert_eq(part.meltdown_turns, expected.get("meltdown_turns", 0), "%s.meltdown_turns" % id)
		assert_eq(part.damage, expected.get("damage", 0.0), "%s.damage" % id)
		assert_eq(part.ap_cost, expected.get("ap_cost", 1), "%s.ap_cost" % id)
		assert_eq(part.joint_hp, 1, "%s.joint_hp (no pool part migrates a non-default)" % id)

		var expected_sockets: Array = expected.get("sockets", [])
		assert_eq(part.sockets.size(), expected_sockets.size(), "%s socket count" % id)
		for i in range(min(part.sockets.size(), expected_sockets.size())):
			var socket: Socket = part.sockets[i]
			var expected_socket: Array = expected_sockets[i]
			assert_eq(socket.socket_type, expected_socket[0], "%s socket %d type" % [id, i])
			assert_eq(socket.id, expected_socket[1], "%s socket %d id" % [id, i])

		var expected_volumes: Array = expected.get("volume_sizes", [])
		assert_eq(part.volume.size(), expected_volumes.size(), "%s volume box count" % id)
		for i in range(min(part.volume.size(), expected_volumes.size())):
			assert_eq(part.volume[i].size, expected_volumes[i], "%s volume box %d size" % [id, i])

		var expected_scatter: int = expected.get("scatter_count", 0)
		assert_eq(part.scatter.size(), expected_scatter, "%s scatter ring count" % id)


func test_every_expected_material_id_is_present_exactly_once() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	assert_eq(table.entries.size(), EXPECTED_MATERIALS.size())
	for expected_id: StringName in EXPECTED_MATERIALS:
		assert_true(table.entries.has(expected_id), "%s must be present" % expected_id)


func test_every_material_matches_its_pre_migration_snapshot() -> void:
	var table: MaterialTable = DataLibrary.material_table()
	for id: StringName in EXPECTED_MATERIALS:
		var expected: Dictionary = EXPECTED_MATERIALS[id]
		var entry: MaterialEntry = table.get_entry(id)
		assert_eq(entry.dt, expected.dt, "%s.dt" % id)
		assert_eq(entry.deflect_threshold_deg, 30.0, "%s.deflect_threshold_deg" % id)
		assert_eq(entry.color, expected.color, "%s.color" % id)
