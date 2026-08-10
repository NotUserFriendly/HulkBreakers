extends GutTest

## taskblock-63 Pass A: **the linter's file cap is a project decision, and this is
## what keeps it one.**
##
## `max-file-lines` was `1000` — **gdlint's own default, inherited rather than
## chosen.** This project already overrides `max-returns` and `max-public-methods`
## for stated reasons, so the one rule nobody had argued for was the one doing the
## damage. `BR62.02` records it biting three source files inside a single taskblock
## and **twice the cost was paid out of documentation**, because the cheapest thing
## to cut when a file is one line over the cap is the explanation of why the code is
## as it is — and this project deliberately carries its rules in doc comments.
##
## **A line count cannot tell code from comments.** That is the whole defect: the cap
## penalised exactly the files that explain themselves.
##
## **Everything else gdlint does is untouched and still gates the build** — parse
## errors in ~6 s with no Godot launch, builtin shadowing (which caught `los.gd`'s
## `range` parameter), naming, class-definition order. The tool was never the
## problem; the one rule was.
##
## **Why this is asserted at all.** taskblock-45 Pass E put a cap assertion in a test
## so the number could not quietly drift — it had been raised eight times, always for
## one file, always on a promise. That mechanism is worth keeping even though its
## original subject (the retired planner, see `test_retired_planner_sweep.gd`) is
## gone: **a cap that moves should move in a diff someone had to explain**, not in a
## config edit nobody reads. Changing this constant means changing this test, and
## that is the point.

## The cap, as gdlintrc must spell it. Deliberately the literal line rather than a
## parsed value: gdlintrc is YAML that only gdlint reads, and standing up a parser
## to check one integer is more machinery than the fact is worth.
const EXPECTED_CAP_LINE := "max-file-lines: 2500"


func test_the_file_cap_is_the_projects_chosen_number_not_gdlints_default() -> void:
	var file: FileAccess = FileAccess.open("res://gdlintrc", FileAccess.READ)
	assert_not_null(file, "gdlintrc must be readable")
	if file == null:
		return

	assert_true(
		file.get_as_text().contains(EXPECTED_CAP_LINE),
		(
			"gdlintrc must carry '%s'. If the cap is being changed, change it here too and "
			+ "say why — the 1000 it replaced was gdlint's default that nobody chose (BR62.02)."
		) % EXPECTED_CAP_LINE
	)


## A guard that can only ever pass is not a guard. gdlint's default is 1000, so the
## file naming a *different* number is the evidence the project decided one.
func test_the_cap_is_not_gdlints_default() -> void:
	var file: FileAccess = FileAccess.open("res://gdlintrc", FileAccess.READ)
	assert_not_null(file, "gdlintrc must be readable")
	if file == null:
		return

	assert_false(
		file.get_as_text().contains("max-file-lines: 1000"),
		"1000 is gdlint's inherited default — a project that means it says so with its own number"
	)
