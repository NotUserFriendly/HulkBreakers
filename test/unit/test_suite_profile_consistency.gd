extends GutTest

## taskblock-53 Pass A: **the profiler's own internal-consistency check, with no audit
## attached to it.**
##
## ## What this replaces, and why it moved
##
## `test_suite_audit_csv.gd` used to own this assertion and summed the **audit CSV's**
## per-test rows against `suite_profile.json`'s totals. That made a committed snapshot an
## *input to the ordinary suite*: the CSV and the profile had to agree, so the moment a
## test was added to a file the snapshot covered, the gate went red until someone
## regenerated both. taskblock-52 hit exactly that and could not preserve the CSV's
## deliberate staleness — regenerating the profile forces regenerating the CSV.
##
## The audit is a tool the supervisor reaches for, not something the project runs
## (`docs/TEST-AUDIT.md`). It now lives in `res://audit/` with its own entry point, and
## **nothing under `res://test/` reads it.**
##
## ## Why the assertion is still worth having
##
## It is the load-bearing check *of the profiler*, so it stays — pointed at the profiler
## instead of at a snapshot. `suite_profile.json` carries both halves already: a `files`
## array of per-file rows and a `totals` dictionary. Summing the first must reproduce the
## second. That is genuinely self-checking — a counter dropped, mis-keyed, or added to the
## per-file rows without being added to the totals shows up here, which is the failure
## `IDENTITY_KEYS` exists to prevent (`order` and `test` once leaked into the totals as
## though they were work).
##
## **Its own caveat, kept from the original:** a file's counts *are* the sum of its tests'
## by construction (taskblock-47), so this is arithmetic rather than corroboration. It
## earns its place by catching a **wiring** mistake, not a measurement one.
##
## **Reads the committed profile, never writes one.** Regenerating is `WRITE_PROFILE=1`
## and deliberately manual — a test that regenerated its own input could not fail.

const PROFILE_PATH := "res://test/suite_profile.json"

## Every counter the profiler sums. `usec` is included deliberately: it is summed the same
## way and a wall-clock total that stopped matching its parts would be the same wiring bug
## wearing a different name.
const COUNTERS: Array[String] = [
	"bouts",
	"turns",
	"floods",
	"plans",
	"shot_planes",
	"candidates",
	"dups",
	"ui_builds",
	"lookahead_fields",
	"usec",
]


func _profile() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


func test_every_per_file_counter_sums_to_the_profiles_own_total() -> void:
	var profile: Dictionary = _profile()
	if profile.is_empty():
		return
	var files: Array = profile.get("files", [])
	var totals: Dictionary = profile.get("totals", {})
	assert_gt(files.size(), 0, "sanity: the profile carries per-file rows to sum")

	for counter: String in COUNTERS:
		var summed := 0
		for row: Variant in files:
			summed += int((row as Dictionary).get(counter, 0))
		assert_eq(
			summed,
			int(totals.get(counter, -1)),
			"%s: per-file rows must sum to the profile's own total" % counter
		)


## **Every counter in the totals is one the per-file rows actually carry.** This is the
## direction the sum alone cannot catch: a totals key with no per-file source sums to zero
## and would only fail if the total happened to be non-zero. `IDENTITY_KEYS` decides what
## counts as a measurement rather than a label, and a field added on one side only is the
## exact mistake that put `order` (2 953 665) and `test` (135 744) into a committed
## profile's totals as though they were work.
func test_the_totals_carry_no_counter_the_per_file_rows_do_not() -> void:
	var profile: Dictionary = _profile()
	if profile.is_empty():
		return
	var files: Array = profile.get("files", [])
	var totals: Dictionary = profile.get("totals", {})
	if files.is_empty():
		return

	var per_file_keys: Dictionary = {}
	for row: Variant in files:
		for key: String in (row as Dictionary).keys():
			per_file_keys[key] = true

	for key: String in totals.keys():
		assert_true(
			per_file_keys.has(key),
			"totals carries '%s', which no per-file row provides — a summed label, not work" % key
		)


## **`path` is an identity field and must never be summed.** The guard above proves every
## total has a source; this proves the identity fields did not become totals. Named
## explicitly rather than derived from `IDENTITY_KEYS`, so the test states the rule itself
## instead of restating the implementation and agreeing with it by construction.
func test_identity_fields_never_appear_as_totals() -> void:
	var profile: Dictionary = _profile()
	if profile.is_empty():
		return
	var totals: Dictionary = profile.get("totals", {})
	for identity: String in ["path", "script", "test", "order"]:
		assert_false(
			totals.has(identity), "'%s' identifies a row; it is not a counter to sum" % identity
		)


## **The ordinary suite must not read the audit.** taskblock-53 Pass A's acceptance is that
## `res://audit/` can be deleted outright and the suite still passes, and the way that
## silently regresses is one convenient `res://audit/...` constant appearing in a test.
##
## Asserted by reading the tree rather than by remembering: every `.gd` under `res://test/`
## is scanned for the audit path. A file that wants the audit belongs in the audit tree.
##
## **Comment lines are stripped before matching**, and that is not a convenience — this
## file's own doc comment names the path it forbids, and so will the next one explaining
## why the rule exists. A path in prose is documentation; a path in code is a dependency,
## and only the second is what the acceptance is about. Excluding *this file* by name would
## have been the lazier fix and would stop it policing itself.
func test_no_test_under_the_ordinary_tree_reads_the_audit() -> void:
	var offenders: Array[String] = []
	_scan_for_audit_reads("res://test", offenders)
	assert_eq(
		offenders,
		[] as Array[String],
		"these files under the ordinary test tree reference the audit tree: %s" % str(offenders)
	)


## True only if a **non-comment** line names the audit tree. Built as the audit path in two
## halves so this function does not trip the very check it implements — the string it looks
## for must not appear literally in a scanned file's code.
func _references_audit_in_code(path: String) -> bool:
	var needle: String = "res://" + "audit/"
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return true
	return false


func _scan_for_audit_reads(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_for_audit_reads(full, offenders)
		elif entry.ends_with(".gd"):
			if _references_audit_in_code(full):
				offenders.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
