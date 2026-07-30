extends GutTest

## taskblock-49 Pass A: the per-test audit CSV.
##
## ## The acceptance, and why one half of it is structural
##
## The pass asks that per-test counts sum to the file-level counts. **They do, and they
## cannot do otherwise**: taskblock-47 made a file's counters the *sum of its tests'*
## precisely because the outer script window was corrupted by `before_each` resets. So
## asserting that sum checks arithmetic, not attribution, and this file says so rather
## than presenting it as evidence it is not.
##
## What is genuinely independent is the **row count against the source**: one row per
## `func test_` on disk, counted by reading the files rather than by trusting the
## profiler's own bookkeeping. If the profiler dropped a test — a skipped script, a
## boundary it missed — that is where it shows.
##
## The other real number is the **wall-clock gap**. `before_all` and script load land in
## no test's window, so the per-test seconds are less than the per-file seconds, and the
## size of that difference is the honest cost of per-file setup.

const CSV_PATH := "res://test/suite_audit.csv"
const PROFILE_PATH := "res://test/suite_profile.json"
const EXPECTED_HEADER := (
	"origin_file,test_name,description,usec,bouts,turns,candidates,floods,plans,"
	+ "shot_planes,rule_guarded"
)


func _lines() -> Array[String]:
	if not FileAccess.file_exists(CSV_PATH):
		return []
	var out: Array[String] = []
	# A trailing `\r` is dropped rather than trusted: a CRLF writer put one on the last
	# column, so its header key read `rule_guarded\r` and every lookup of the real name
	# raised — which under `-d` is a debugger break, not a red test.
	for line: String in FileAccess.get_file_as_string(CSV_PATH).replace("\r\n", "\n").split("\n"):
		if line.strip_edges() != "":
			out.append(line)
	return out


## Parsed through `CsvLine`, not a bare `split(",")`.
##
## Pass B's `rule_guarded` values are sentences, and sentences contain commas, so the
## writer quotes them. A naive split shifted every numeric column one place right and this
## file read `bouts` as 8697 against a true 56 — a red run that looked like a profiler bug
## and was a parser bug. One codec now writes and reads these fields.
func _rows() -> Array[Dictionary]:
	var lines: Array[String] = _lines()
	var rows: Array[Dictionary] = []
	if lines.is_empty():
		return rows
	var header: PackedStringArray = CsvLine.split(lines[0])
	for i in range(1, lines.size()):
		var cells: PackedStringArray = CsvLine.split(lines[i])
		var row: Dictionary = {}
		for c in range(header.size()):
			row[header[c]] = cells[c] if c < cells.size() else ""
		rows.append(row)
	return rows


## Every `func test_` declared under `test/`, counted from the source.
func _declared_tests() -> Dictionary:
	var counts: Dictionary = {}
	var pending: Array[String] = ["res://test"]
	while not pending.is_empty():
		var path: String = pending.pop_back()
		var dir := DirAccess.open(path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			var full: String = path.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(full)
			elif entry.ends_with(".gd"):
				var found := 0
				for line: String in FileAccess.get_file_as_string(full).split("\n"):
					if line.begins_with("func test_"):
						found += 1
				if found > 0:
					counts[full.replace("res://test/", "")] = found
			entry = dir.get_next()
		dir.list_dir_end()
	return counts


# --- the independent check ----------------------------------------------------------


## **One row per test, for every file the snapshot covers.**
##
## Counted from the source, so a test the profiler dropped shows up rather than the
## profiler agreeing with itself.
##
## ## Why absent files are not a failure
##
## `TEST-AUDIT.md` is explicit that the CSV is a snapshot, is not maintained, and that
## **nothing gates on it**. A test that went red whenever a new test file appeared would
## gate on it — it would make every future test-adding commit require regenerating an
## artifact the procedure says to let go stale.
##
## So a file the snapshot has never seen is reported and skipped; a file it *has* seen
## with the wrong row count is a failure. That keeps the independent check — did the
## profiler drop a test it ran — without turning a deliberately stale artifact into a
## gate. This file itself was the first absentee, having been written after the snapshot.
func test_the_csv_has_one_row_per_declared_test() -> void:
	var rows: Array[Dictionary] = _rows()
	assert_gt(rows.size(), 0, "the audit CSV must exist — regenerate with WRITE_PROFILE=1")
	if rows.is_empty():
		return
	var declared: Dictionary = _declared_tests()
	var expected := 0
	for file: String in declared:
		expected += int(declared[file])

	var per_file: Dictionary = {}
	for row: Dictionary in rows:
		var file: String = String(row["origin_file"])
		per_file[file] = int(per_file.get(file, 0)) + 1

	gut.p(
		"%d rows against %d declared tests in %d files" % [rows.size(), expected, declared.size()]
	)
	var mismatched: Array[String] = []
	var absent: Array[String] = []
	for file: String in declared:
		var seen: int = int(per_file.get(file, 0))
		if seen == 0:
			absent.append(file)
			continue
		if seen != int(declared[file]):
			mismatched.append("%s: %d rows, %d declared" % [file, seen, int(declared[file])])
	if not absent.is_empty():
		gut.p("not in this snapshot (added since it was taken): %s" % [absent])
	assert_eq(
		mismatched,
		[] as Array[String],
		"the snapshot covers these files but with the wrong row count: %s" % [mismatched]
	)
	# Everything the snapshot covers must be covered completely — the count it should
	# equal is the tests in the files it has rows for, not every test that now exists.
	var covered := 0
	for file: String in declared:
		if int(per_file.get(file, 0)) > 0:
			covered += int(declared[file])
	assert_eq(rows.size(), covered, "no row belongs to a test that is not declared")
	assert_gt(
		float(rows.size()) / float(expected),
		0.95,
		"and the snapshot still describes essentially the whole suite — regenerate it if not"
	)


func test_the_csv_carries_the_columns_the_audit_expects() -> void:
	var lines: Array[String] = _lines()
	assert_gt(lines.size(), 1, "the CSV has a header and rows")
	if lines.is_empty():
		return
	assert_eq(lines[0], EXPECTED_HEADER, "the header matches TEST-AUDIT.md's schema")


## **`rule_guarded` is filled everywhere; `description` is a defect list and stays sparse.**
##
## `TEST-AUDIT.md` is explicit about the shape of a useful classification: a rule per row,
## a small number of distinct rules, and a `description` column that is mostly empty
## because "the test names in this repo are already sentences". If `description` ever comes
## back mostly full it is being used to restate names, and the rows are worthless — so the
## sparseness is asserted rather than hoped for.
##
## The distinct-rule ratio is the one that catches a paraphrased column: if every row had
## its own rule, sorting by it would surface no clusters and the audit would have produced
## nothing. Bounded loosely, because the right number is a judgement, not a target.
func test_the_judgement_columns_carry_a_real_classification() -> void:
	var rows: Array[Dictionary] = _rows()
	if rows.is_empty():
		return
	assert_true(rows[0].has("description"), "description is a column")
	assert_true(rows[0].has("rule_guarded"), "rule_guarded is a column")

	var described := 0
	var ruled := 0
	var distinct: Dictionary = {}
	for row: Dictionary in rows:
		if String(row["description"]).strip_edges() != "":
			described += 1
		var rule: String = String(row["rule_guarded"]).strip_edges()
		if rule != "":
			ruled += 1
			distinct[rule] = true

	gut.p(
		(
			"%d/%d rows ruled over %d distinct rules; %d descriptions filled"
			% [ruled, rows.size(), distinct.size(), described]
		)
	)
	assert_eq(ruled, rows.size(), "every row carries a rule")
	assert_lt(
		float(distinct.size()) / float(rows.size()),
		0.25,
		"and the rules cluster rather than paraphrasing one test each"
	)
	assert_lt(
		float(described) / float(rows.size()),
		0.05,
		"description stays a defect list, not a second copy of the test names"
	)


## **A rule is a sentence, and sentences contain commas.** The classification must survive
## a round trip through the file, which is the bug this pins: the writer quoted correctly,
## the reader split on `,`, and every numeric column shifted one place right.
func test_a_rule_containing_a_comma_survives_the_file() -> void:
	var rows: Array[Dictionary] = _rows()
	if rows.is_empty():
		return
	var with_comma := 0
	for row: Dictionary in rows:
		if String(row["rule_guarded"]).contains(","):
			with_comma += 1
			# The shifted-column failure showed up here first: a quoted rule ate the
			# following field, so the last column read back as a fragment of the rule.
			assert_false(
				String(row["usec"]).contains(" "),
				"usec stays numeric beside a quoted rule: %s" % row["test_name"]
			)
	gut.p("%d rows carry a rule containing a comma" % with_comma)
	assert_gt(with_comma, 0, "the vocabulary is sentences, not comma-free labels")


# --- the sums --------------------------------------------------------------------


## The counter sums, asserted with their own caveat: a file's counts **are** the sum of
## its tests', so this is arithmetic rather than corroboration. It still earns its place —
## a CSV that dropped a column or mis-mapped one would show here.
func test_per_test_counters_sum_to_the_file_level_profile() -> void:
	var rows: Array[Dictionary] = _rows()
	if rows.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not parsed is Dictionary:
		return
	var totals: Dictionary = (parsed as Dictionary).get("totals", {})

	for counter: String in ["bouts", "turns", "floods", "plans", "shot_planes", "candidates"]:
		var summed := 0
		for row: Dictionary in rows:
			summed += int(row[counter])
		assert_eq(summed, int(totals.get(counter, -1)), "%s sums to the file-level total" % counter)


## A test that builds no bout reports zero — the counters are per test, not smeared over
## the file they live in.
func test_a_test_that_builds_no_bout_reports_zero_bouts() -> void:
	var rows: Array[Dictionary] = _rows()
	if rows.is_empty():
		return
	var zero := 0
	var nonzero := 0
	for row: Dictionary in rows:
		if int(row["bouts"]) == 0:
			zero += 1
		else:
			nonzero += 1

	gut.p("%d rows build no bout, %d build at least one" % [zero, nonzero])
	assert_gt(zero, nonzero, "the overwhelming majority of tests build no bout")
	assert_gt(nonzero, 0, "and the ones that do are attributed, not lost")


## **The unattributed remainder, measured.** `before_all` and script load fall in no
## test's window, so per-test seconds are less than per-file seconds. Bounded rather than
## pinned: what matters is that setup is a small share, because a large one would mean
## per-test cost was mostly fiction.
func test_unattributed_setup_is_a_small_share_of_wall_clock() -> void:
	var rows: Array[Dictionary] = _rows()
	if rows.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not parsed is Dictionary:
		return
	var file_usec := 0
	for file_row: Dictionary in (parsed as Dictionary).get("files", []):
		file_usec += int(file_row.get("usec", 0))
	var test_usec := 0
	for row: Dictionary in rows:
		test_usec += int(row["usec"])

	var gap: float = float(file_usec - test_usec) / maxf(1.0, float(file_usec))
	gut.p(
		(
			"tests %.1fs of files %.1fs — %.1f%% unattributed setup"
			% [float(test_usec) / 1e6, float(file_usec) / 1e6, gap * 100.0]
		)
	)
	assert_gt(file_usec, test_usec, "per-file wall-clock includes setup no test owns")
	assert_lt(gap, 0.15, "and that share stays small enough for per-test cost to mean something")
