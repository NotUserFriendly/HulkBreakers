extends GutTest

## taskblock-44 Pass A: **a measurement that does not carry its own provenance is
## one somebody has to defend in prose later.**
##
## Every performance number this project has recorded came from a debug run, and
## taskblock-43's report had to spend a paragraph explaining why its figures were
## not continuous with the historical series. `BuildIdentity` exists so that
## question stops being askable, and these tests pin that the answer is *total* —
## a run in any mode describes itself, rather than only being interpretable by a
## human who remembers how they launched it.
##
## The suite itself runs on a tools binary under `--headless -s`, so
## `EDITOR_DEBUG` is the value asserted below. That is not a limitation of the
## test: it is the whole point being pinned. **Every number in this repository's
## history was taken in exactly this mode**, and the test says so out loud.


func test_the_build_kind_is_one_of_the_three_known_builds() -> void:
	var known: Array[StringName] = [
		BuildIdentity.EDITOR_DEBUG, BuildIdentity.EXPORTED_DEBUG, BuildIdentity.EXPORTED_RELEASE
	]

	assert_has(known, BuildIdentity.kind(), "never an unclassified build")


## The suite runs on the editor/tools binary, which is also how the bench runs
## and how every historical figure was taken.
func test_the_test_suite_itself_reports_the_editor_debug_build() -> void:
	assert_eq(BuildIdentity.kind(), BuildIdentity.EDITOR_DEBUG)
	assert_false(
		BuildIdentity.is_representative_of_play(),
		"a tools binary carries GDScript's debug per-line overhead — its numbers are not play numbers"
	)


## The claim that matters for the report: only an exported release build is
## allowed to describe itself as representative.
func test_only_an_exported_release_build_counts_as_representative() -> void:
	assert_eq(
		BuildIdentity.is_representative_of_play(),
		BuildIdentity.kind() == BuildIdentity.EXPORTED_RELEASE
	)


## Self-describing means the line actually names the build, not that it is merely
## non-empty — a stamp that says nothing is the failure mode being guarded here.
func test_the_description_names_the_build_the_version_and_the_platform() -> void:
	var described: String = BuildIdentity.describe()

	assert_string_contains(described, String(BuildIdentity.kind()))
	assert_string_contains(described, str(Engine.get_version_info().get("string", "")))
	assert_string_contains(described, OS.get_name())


## The machine-readable half, for a log reader that must never parse prose — the
## same split `FpsDumpSink.data.offset_ms` already follows.
func test_the_data_form_carries_the_same_facts_as_the_prose() -> void:
	var data: Dictionary = BuildIdentity.as_data()

	assert_eq(data["build"], BuildIdentity.kind())
	assert_eq(data["representative"], BuildIdentity.is_representative_of_play())
	assert_eq(data["platform"], OS.get_name())
	assert_true(data.has("godot"), "the engine version rides along too")
