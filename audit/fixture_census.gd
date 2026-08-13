extends SceneTree

## taskblock-68 Pass A2 — **the fixture census: one row per test file, mechanical columns only.**
##
##     godot --headless --path . -s res://audit/fixture_census.gd
##
## Writes `audit/fixture_census.csv`. **Regenerable, never hand-maintained** — except for the two
## judgement columns, which are carried forward exactly the way `tools/run_suite.gd` carries
## `description` and `rule_guarded` through a regeneration of `suite_audit.csv`.
##
## ## Why a second CSV rather than more columns on the first
##
## `suite_audit.csv` is **one row per test** and `TEST-AUDIT.md` is emphatic that it must stay
## that way — a per-file summary there would be a directory listing with extra steps. But the
## question this census asks is a **per-file** question: *does this file build its units out of
## hand-made `Part`s?* That is a property of the fixture the file authors, not of any one test,
## and a per-test copy of it would repeat the same answer forty times down a file.
##
## ## What it is for
##
## **192 test files call `Part.new()` directly.** Finding "the cheats" is not the point: a test of
## a pure function over two positions needs no shell, and forcing one on it is slower and less
## focused. The point is to narrow 192 files down to the ones where a hand-built stand-in could be
## **hiding** something, so the judgement in Pass B is spent on a candidate set rather than
## spread thin over a directory listing.
##
## The receipt for why that matters is in `BUGS-ARCHIVE.md`: a cost probe measured a **one-box**
## body, reported 41 usec per unit, and the next live session came back at **13 fps**. A real
## assembled shell is 48 boxes and `placements_aabb` costs eight corner transforms per box. The
## whole suite was green throughout, which is the part no existing mechanism could have caught.
##
## ## The discriminator, and its limits
##
## `shape` is **mechanical, not a judgement.** It reads the source text, so it says what a file
## *constructs*, never whether that was the right call:
##
## - **`no_unit`** — never constructs a `Unit` by any route. The rule under test is below the
##   level at which a body has structure at all.
## - **`real_unit`** — every unit it uses comes off a real definition: a preset, the reference
##   humanoid, the scrap-heap landing, or a bout builder's roster.
## - **`hand_built`** — it calls `Unit.new(`, so it assembles at least one unit itself, out of
##   parts it authored.
##
## ## `real_ids` and `conflicts` — the borrowed-id scan
##
## `DRIFTED` has two halves and this emits the one a scan can settle. A test that writes
## `gun.id = &"pistol"` has borrowed a name the game defines; if it then writes `gun.damage =
## 20.0` where the real pistol does 4, it has authored a **pistol that could not occur**.
## `real_ids` counts the borrowed names, `conflicts` counts the fields that disagree, and the
## disagreements themselves are written to `fixture_conflicts.csv` — because a count is not
## evidence and the `outcome` column has to be arguable from something.
##
## **A conflict is a fact, not a verdict.** Borrowing `chaingun` as a bare label for "some
## weapon" is ordinary and correct; borrowing it and then asserting against a damage figure the
## game contradicts is not. Which one a row is, is Pass B's judgement.
##
## ## `hand_built` is the candidate set and nothing more
##
## A file lands there for calling one constructor, which is exactly as much as a text scan can
## know; whether the fixture is right is the `outcome` column's job and Pass B's work.
##
## ## What the scan does and does not see
##
## Whole-line comments are stripped — prose naming `Part.new()` is documentation, and this file's
## own header would otherwise count itself. **Inline trailing comments are not stripped**, and
## neither are string literals: cutting at an unquoted `#` needs a tokeniser, and the error it
## would prevent is a construction spelled inside a comment on the same line as code. If that ever
## starts mattering, the `shape` column is where it shows up, as a file classified `hand_built`
## with no fixture in it.

const TEST_ROOT := "res://test"
const PROFILE_PATH := "res://test/suite_profile.json"
const OUT_PATH := "res://audit/fixture_census.csv"
const CONFLICTS_PATH := "res://audit/fixture_conflicts.csv"

const HEADER := (
	"origin_file,part_new,unit_new,real_build,bout_build,data_library,shape,real_ids,conflicts,"
	+ "usec,turns,spawns,shot_planes,candidates,outcome,evidence"
)

const CONFLICT_HEADER := "origin_file,part_id,field,fixture_value,real_value"

## Routes that build a body through **the game's own assembly path** rather than by handing
## `Unit.new` a part: a preset, the one hardcoded reference template, the scrap-heap landing, or
## `BodyAssembler` directly.
##
## **`BodyAssembler.assemble` is the loose one and it is kept deliberately.** The first three read
## real data; the fourth assembles whatever `ShellTemplate` it is given, and the four files that
## call it are the assembler's own tests, feeding it templates they authored. So `real_unit` means
## *assembled by the game's code*, which is not the same claim as *out of the game's data* — and
## the difference is visible in the same row, as a non-zero `part_new` beside it.
const REAL_BUILD := [
	"assemble_from_preset",
	"assemble_reference_humanoid",
	"assemble_random",
	"BodyAssembler.assemble",
	"RealUnit.build",
]

## Bout builders. A file that stands a bout up never authors its units at all — the roster comes
## off presets — so these are a real-definition route too, one level further out.
const BOUT_BUILD := ["BoutSetup", "BoutCorpus", "ScriptedCorpus"]

## The profile counters carried onto each row. `usec` is what the file costs; the rest are the
## counters that move when a body's box count moves — a shot plane projects every box, a spawn
## and a turn each walk the placement tree, and a candidate is scored against unit geometry. A
## file with a hand-built fixture and a large number in one of these is measuring that fixture.
const CARRIED := ["usec", "turns", "spawns", "shot_planes", "candidates"]


func _init() -> void:
	DataLibrary.load_all()
	var profile: Dictionary = _profile()
	var paths: Array[String] = _test_scripts()
	paths.sort()

	var rows: Array[String] = [HEADER]
	var conflict_rows: Array[String] = [CONFLICT_HEADER]
	var kept: Dictionary = _existing_judgements()
	var shapes: Dictionary = {"no_unit": 0, "real_unit": 0, "hand_built": 0}
	var part_new_files: int = 0
	var conflicting_files: int = 0
	var missing_from_profile: Array[String] = []

	for path: String in paths:
		var origin: String = path.replace("res://test/", "")
		var source: String = _code_only(FileAccess.get_file_as_string(path))

		var part_new: int = source.count("Part.new()")
		var unit_new: int = source.count("Unit.new(")
		var real_build: int = _count_any(source, REAL_BUILD)
		var bout_build: int = _count_any(source, BOUT_BUILD)
		var data_library: int = 1 if source.contains("DataLibrary") else 0

		var shape := "no_unit"
		if unit_new > 0:
			shape = "hand_built"
		elif real_build > 0 or bout_build > 0:
			shape = "real_unit"
		shapes[shape] = int(shapes[shape]) + 1
		if part_new > 0:
			part_new_files += 1

		var borrowed: Dictionary = _borrowed_ids(source)
		var conflicts: Array[Dictionary] = _conflicts(borrowed)
		if not conflicts.is_empty():
			conflicting_files += 1
		for conflict: Dictionary in conflicts:
			var cells := PackedStringArray(
				[
					origin,
					String(conflict["part_id"]),
					String(conflict["field"]),
					String(conflict["fixture"]),
					String(conflict["real"]),
				]
			)
			conflict_rows.append(CsvLine.join(cells))

		var measured: Dictionary = profile.get(path, {})
		if measured.is_empty():
			missing_from_profile.append(origin)

		var judgement: Array = kept.get(origin, ["", ""])
		var fields := PackedStringArray(
			[
				origin,
				str(part_new),
				str(unit_new),
				str(real_build),
				str(bout_build),
				str(data_library),
				shape,
				str(borrowed.size()),
				str(conflicts.size()),
			]
		)
		for key: String in CARRIED:
			fields.append(str(int(measured.get(key, -1))))
		fields.append(String(judgement[0]))
		fields.append(String(judgement[1]))
		rows.append(CsvLine.join(fields))

	if not _write(OUT_PATH, rows) or not _write(CONFLICTS_PATH, conflict_rows):
		quit(2)
		return

	print("wrote %s and %s" % [OUT_PATH, CONFLICTS_PATH])
	print("  %d test files, %d of them calling Part.new()" % [paths.size(), part_new_files])
	print(
		(
			"  %d file(s) hand-build a part under a REAL part's id and disagree with it: %d fields"
			% [conflicting_files, conflict_rows.size() - 1]
		)
	)
	print(
		(
			"  shape: %d no_unit, %d real_unit, %d hand_built  <- the candidate set is hand_built"
			% [shapes["no_unit"], shapes["real_unit"], shapes["hand_built"]]
		)
	)
	# **A `-1` in a carried column is a stale profile, not a free file.** Said out loud here
	# because a reader sorting the CSV by `usec` would otherwise see those rows float to the top
	# as the cheapest in the suite.
	if not missing_from_profile.is_empty():
		print(
			(
				"  %d file(s) absent from the committed profile — their carried counters are -1:"
				% missing_from_profile.size()
			)
		)
		for origin: String in missing_from_profile:
			print("    %s" % origin)
	quit(0)


func _write(path: String, lines: Array[String]) -> bool:
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("fixture_census: cannot write %s" % path)
		return false
	for line: String in lines:
		out.store_line(line)
	out.close()
	return true


## ---------------------------------------------------------------------------------------------
## The borrowed-id scan: **the half of `DRIFTED` that a text scan can decide on its own.**
##
## `DRIFTED` is "the test passes against a unit that could not occur", and it has two halves. One
## is *a real unit breaks it*, which needs the substitution and is Pass B's work. The other is
## *the fixture asserts something the game's own data contradicts* — and that half is decidable
## here, because the game's own data is right there in `DataLibrary`.
##
## A test that writes `gun.id = &"pistol"` and then `gun.damage = 20.0` has authored a pistol that
## does not exist: the real one does 4. Whether that matters is a judgement (`chaingun` as a bare
## label for "some weapon" is fine; a damage figure the test then asserts against is not) — but
## **the disagreement itself is a fact, and it belongs in the evidence column rather than in
## anyone's reading of the file.**
##
## **What the scan does not see.** It follows direct `var x := Part.new()` / `x.field = literal`
## assignment only. A fixture built inside a helper that takes its values as arguments is
## invisible to it, as is any value that is not a literal. So `conflicts` is a floor, never a
## total — an empty cell means *nothing was found here*, not *nothing is here*.
## ---------------------------------------------------------------------------------------------


## `part_id` -> {field: literal text}, for every hand-built `Part` in `source` whose id is a real
## part's. Assignments are tracked per variable and reset at each `Part.new()`, so a file that
## builds several fixtures — interleaved or reusing a name — attributes each field to the right
## one.
func _borrowed_ids(source: String) -> Dictionary:
	var construct := RegEx.create_from_string(
		"^\\s*(?:var\\s+)?([A-Za-z_]\\w*)\\s*(?::=|:\\s*Part\\s*=|=)\\s*Part\\.new\\(\\)"
	)
	var assign := RegEx.create_from_string("^\\s*([A-Za-z_]\\w*)\\.(\\w+)\\s*=\\s*(.+?)\\s*$")

	var tracked: Dictionary = {}
	var borrowed: Dictionary = {}
	for line: String in source.split("\n"):
		var built: RegExMatch = construct.search(line)
		if built != null:
			tracked[built.get_string(1)] = {"id": "", "fields": {}}
			continue
		var set_field: RegExMatch = assign.search(line)
		if set_field == null or not tracked.has(set_field.get_string(1)):
			continue
		var fixture: Dictionary = tracked[set_field.get_string(1)]
		var field: String = set_field.get_string(2)
		var value: String = _literal(set_field.get_string(3))
		if field == "id":
			fixture["id"] = value
			if DataLibrary.get_part(StringName(value)) != null:
				borrowed[value] = fixture["fields"]
		elif String(fixture["id"]) != "":
			(fixture["fields"] as Dictionary)[field] = value
		else:
			# Set before its `id` line: keep it, and it joins `borrowed` when the id arrives,
			# because `fields` is the same Dictionary by reference.
			(fixture["fields"] as Dictionary)[field] = value
	return borrowed


## One row per field where the hand-built part and the real part of that id disagree.
func _conflicts(borrowed: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for part_id: String in borrowed:
		var real: Part = DataLibrary.get_part(StringName(part_id))
		var properties: Dictionary = {}
		for entry: Dictionary in real.get_property_list():
			properties[String(entry["name"])] = int(entry["type"])
		for field: String in borrowed[part_id]:
			if not properties.has(field):
				continue
			# Scalars only. An array or a resource has no single literal to have disagreed with,
			# and a fixture authoring its own `volume` is the normal, correct thing to do.
			if not [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME].has(
				properties[field]
			):
				continue
			var fixture_value: String = String(borrowed[part_id][field])
			var real_value: String = _scalar(real.get(field))
			if fixture_value == "" or _agree(fixture_value, real_value):
				continue
			var row := {
				"part_id": part_id,
				"field": field,
				"fixture": fixture_value,
				"real": real_value,
			}
			found.append(row)
	return found


## A literal's value as written — trailing comment dropped, `&` and quotes stripped — or `""` if
## the right-hand side is not a literal at all.
##
## **The empty return is the important half.** `gun.damage = damage` assigns a parameter, and the
## first version of this scan reported it as a fixture damage of "damage" disagreeing with the
## real 4.0. That is not a disagreement; it is a value the scan cannot read, and eight rows of it
## were sitting in the conflict table looking exactly like evidence. Literal-ness has to be
## decided **before** the quotes come off, because `&"steel"` and a bare `steel` are the same
## seven characters afterwards.
func _literal(text: String) -> String:
	var stripped: String = RegEx.create_from_string("\\s+#.*$").sub(text, "", true).strip_edges()
	if stripped == "true" or stripped == "false":
		return stripped
	if stripped.is_valid_float() or stripped.is_valid_int():
		return stripped
	if stripped.begins_with("&"):
		stripped = stripped.substr(1)
	if stripped.length() >= 2 and stripped.begins_with('"') and stripped.ends_with('"'):
		return stripped.substr(1, stripped.length() - 2)
	return ""


func _scalar(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return "true" if value else "false"
	return String(str(value))


func _agree(fixture_value: String, real_value: String) -> bool:
	if fixture_value == real_value:
		return true
	# `4` against `4.0` is the same number written two ways, and a fixture is free to write either.
	if fixture_value.is_valid_float() and real_value.is_valid_float():
		return absf(fixture_value.to_float() - real_value.to_float()) < 0.000001
	return false


## Every `test_*.gd` under `res://test`, which is the set the profile measures — the support
## helpers beside them are not test scripts and are not rows.
func _test_scripts() -> Array[String]:
	var found: Array[String] = []
	_walk(TEST_ROOT, found)
	return found


func _walk(dir_path: String, into: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			_walk(full, into)
		elif name.begins_with("test_") and name.ends_with(".gd"):
			into.append(full)
		name = dir.get_next()
	dir.list_dir_end()


## `path` -> its row in the committed profile.
func _profile() -> Dictionary:
	var by_path: Dictionary = {}
	if not FileAccess.file_exists(PROFILE_PATH):
		push_error("fixture_census: no profile at %s — run ./run_tests.sh profile" % PROFILE_PATH)
		return by_path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return by_path
	for row: Variant in (parsed as Dictionary).get("files", []):
		by_path[String((row as Dictionary)["path"])] = row
	return by_path


## Source with whole-line comments removed. Header prose in this repo routinely names the exact
## constructors being counted — `TEST-AUDIT.md` strips comments for the same reason when it asks
## whether anything under `test/` depends on the audit tree.
func _code_only(text: String) -> String:
	var kept: Array[String] = []
	for line: String in text.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


func _count_any(source: String, needles: Array) -> int:
	var total: int = 0
	for needle: String in needles:
		total += source.count(needle)
	return total


## Judgement cells already in the committed CSV, keyed by `origin_file`.
##
## **Regenerating the mechanical columns must not erase the classification.** Same hazard
## `tools/run_suite.gd` documents for `suite_audit.csv`: a writer that always emitted the
## judgement columns blank would destroy the audit on the next regeneration, with everything
## green either way.
func _existing_judgements() -> Dictionary:
	var kept: Dictionary = {}
	if not FileAccess.file_exists(OUT_PATH):
		return kept
	var first := true
	for line: String in FileAccess.get_file_as_string(OUT_PATH).replace("\r\n", "\n").split("\n"):
		if line.strip_edges() == "":
			continue
		if first:
			first = false
			continue
		var cells: PackedStringArray = CsvLine.split(line)
		if cells.size() < 16:
			continue
		if cells[14] == "" and cells[15] == "":
			continue
		kept[cells[0]] = [cells[14], cells[15]]
	return kept
