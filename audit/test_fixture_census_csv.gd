extends GutTest

## taskblock-68 Pass A2: the checks on `fixture_census.csv`.
##
## **Run deliberately, with the rest of the audit tree** — never by the ordinary gate, which is
## `--dir=res://test` and cannot see this file:
##
##     godot --headless --path . -s res://tools/run_suite.gd -- --dir=res://audit
##
## **A failure here is a report, not a broken build**, exactly as `TEST-AUDIT.md` argues for
## `test_suite_audit_csv.gd`: the census is a snapshot taken to answer a question and allowed to go
## stale, so `test_the_census_has_one_row_per_test_script` going red *is* the signal "regenerate
## before you trust this".
##
## ## What is worth checking and what is not
##
## Re-asserting the emitter's own arithmetic would prove nothing — the same walk, run twice, agrees
## with itself. What is independent is the **row count against the source**: the scripts are counted
## by reading the directory tree here, and the `Part.new()` files by reading every file's text, so a
## directory the emitter's walk missed is what shows up. That the answer is **192** is the one
## number the taskblock arrived carrying, and it is checked against the files rather than quoted.

const CSV_PATH := "res://audit/fixture_census.csv"
const PROFILE_PATH := "res://test/suite_profile.json"
const TEST_ROOT := "res://test"
const EXPECTED_HEADER := (
	"origin_file,part_new,unit_new,real_build,bout_build,data_library,shape,real_ids,conflicts,"
	+ "usec,turns,spawns,shot_planes,candidates,outcome,evidence"
)
const CONFLICTS_PATH := "res://audit/fixture_conflicts.csv"
const CONFLICT_HEADER := "origin_file,part_id,field,fixture_value,real_value"
const SHAPES := ["no_unit", "real_unit", "hand_built"]


func _lines() -> Array[String]:
	if not FileAccess.file_exists(CSV_PATH):
		return []
	var out: Array[String] = []
	for line: String in FileAccess.get_file_as_string(CSV_PATH).replace("\r\n", "\n").split("\n"):
		if line.strip_edges() != "":
			out.append(line)
	return out


func _rows() -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var lines: Array[String] = _lines()
	for i in range(1, lines.size()):
		out.append(CsvLine.split(lines[i]))
	return out


## An independent walk — the point is to disagree with the emitter's if it ever misses a subtree.
func _scripts_on_disk(dir_path: String = TEST_ROOT) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub: String in dir.get_directories():
		found.append_array(_scripts_on_disk("%s/%s" % [dir_path, sub]))
	for file_name: String in dir.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			found.append("%s/%s" % [dir_path, file_name])
	return found


func test_the_census_exists_and_carries_the_documented_header() -> void:
	var lines: Array[String] = _lines()
	assert_gt(
		lines.size(), 1, "no census — run `godot --headless -s res://audit/fixture_census.gd`"
	)
	if lines.is_empty():
		return
	assert_eq(lines[0], EXPECTED_HEADER, "the header is the column contract")


func test_the_census_has_one_row_per_test_script() -> void:
	var disk: Array[String] = _scripts_on_disk()
	assert_eq(
		_rows().size(),
		disk.size(),
		"one row per test_*.gd under res://test — regenerate the census if this is off"
	)


func test_every_row_names_a_script_that_exists() -> void:
	var missing: Array[String] = []
	for row: PackedStringArray in _rows():
		if not FileAccess.file_exists("res://test/%s" % row[0]):
			missing.append(row[0])
	assert_eq(missing, [] as Array[String], "a row for a deleted file is a stale census")


func test_every_row_carries_one_of_the_three_shapes() -> void:
	var bad: Array[String] = []
	for row: PackedStringArray in _rows():
		if not SHAPES.has(row[6]):
			bad.append("%s -> %s" % [row[0], row[6]])
	assert_eq(bad, [] as Array[String], "shape is a closed mechanical vocabulary")


## The number the taskblock arrived with, recounted from the files rather than quoted.
func test_the_part_new_column_agrees_with_the_source_files() -> void:
	var counted: int = 0
	for path: String in _scripts_on_disk():
		var code: Array[String] = []
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if not line.strip_edges().begins_with("#"):
				code.append(line)
		if "\n".join(code).count("Part.new()") > 0:
			counted += 1

	var claimed: int = 0
	for row: PackedStringArray in _rows():
		if int(row[1]) > 0:
			claimed += 1

	assert_eq(claimed, counted, "files calling Part.new(), census against a fresh recount")
	gut.p("files calling Part.new(): %d" % counted)


## The suite's own file count. **A mismatch means the profile is older than the tree**, which is
## what makes every carried `usec` on this census a number from a different suite.
func test_the_census_covers_the_same_files_the_profile_measured() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "the profile must be readable")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var measured: int = ((parsed as Dictionary)["files"] as Array).size()
	assert_eq(
		_rows().size(),
		measured,
		"census rows against profile files — run ./run_tests.sh profile if the tree moved"
	)


## No row may silently read as free. `-1` is the emitter's marker for "this file is not in the
## profile at all", and it is the only negative allowed.
func test_carried_counters_are_never_negative_except_the_stale_marker() -> void:
	var bad: Array[String] = []
	for row: PackedStringArray in _rows():
		for column in range(9, 14):
			if int(row[column]) < -1:
				bad.append("%s column %d = %s" % [row[0], column, row[column]])
	assert_eq(bad, [] as Array[String], "a carried counter is a count or the -1 stale marker")


## ## The conflict table, and the one thing it must never do
##
## `conflicts` on the census is a **count**; the disagreements themselves live in
## `fixture_conflicts.csv`, one row per field, because a count is not evidence. The two are
## written by the same run and must agree — a census claiming conflicts the table cannot show is
## worse than either file alone.
func test_the_conflict_table_accounts_for_every_conflict_the_census_counts() -> void:
	var claimed: int = 0
	for row: PackedStringArray in _rows():
		claimed += int(row[8])

	var lines: Array[String] = []
	for line: String in FileAccess.get_file_as_string(CONFLICTS_PATH).replace("\r\n", "\n").split(
		"\n"
	):
		if line.strip_edges() != "":
			lines.append(line)

	assert_gt(lines.size(), 0, "no conflict table — regenerate the census")
	if lines.is_empty():
		return
	assert_eq(lines[0], CONFLICT_HEADER, "the conflict table's header is a contract too")
	assert_eq(lines.size() - 1, claimed, "one row per field the census counted as conflicting")
	gut.p("field-level conflicts with real data: %d" % claimed)


## Every conflict must name a part the game actually defines — that is the entire claim being
## made. A row for an id `DataLibrary` does not know is a scanner bug, not a finding.
func test_every_conflict_names_a_part_that_really_exists() -> void:
	DataLibrary.load_all()
	var unknown: Array[String] = []
	var first := true
	for line: String in FileAccess.get_file_as_string(CONFLICTS_PATH).replace("\r\n", "\n").split(
		"\n"
	):
		if line.strip_edges() == "":
			continue
		if first:
			first = false
			continue
		var cells: PackedStringArray = CsvLine.split(line)
		if DataLibrary.get_part(StringName(cells[1])) == null:
			unknown.append("%s -> %s" % [cells[0], cells[1]])
	DataLibrary.reset()
	assert_eq(unknown, [] as Array[String], "a conflict is against a real part or it is nothing")
