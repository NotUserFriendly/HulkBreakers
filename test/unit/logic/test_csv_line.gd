extends GutTest

## taskblock-49 Pass B: the CSV field codec.
##
## This exists because a hand-rolled `split(",")` read the suite audit wrong the moment
## the audit's own vocabulary contained a comma. The cases below are the ones that
## distinguish a real CSV reader from a `split` — quoted separators, doubled quotes,
## trailing empties — and each of them appears in `test/suite_audit.csv` for real.


func test_a_plain_record_splits_on_commas() -> void:
	assert_eq(
		CsvLine.split("a,b,c"), PackedStringArray(["a", "b", "c"]), "no quoting, no surprises"
	)


## The failing case from the real file: a rule sentence with a comma in it.
func test_a_quoted_field_keeps_its_own_commas() -> void:
	var line := 'test_foo.gd,test_bar,,120,"a debug verb reuses the real path, never a shortcut"'
	var cells: PackedStringArray = CsvLine.split(line)
	assert_eq(cells.size(), 5, "five fields, not six")
	assert_eq(cells[3], "120", "the numeric column stays put beside a quoted field")
	assert_eq(cells[4], "a debug verb reuses the real path, never a shortcut")


func test_a_doubled_quote_reads_as_one_literal_quote() -> void:
	var cells: PackedStringArray = CsvLine.split('a,"he said ""three rings"" here",b')
	assert_eq(cells[1], 'he said "three rings" here')
	assert_eq(cells[2], "b", "and the field after it is still reachable")


## **Trailing empties survive.** `rule_guarded` is the last column and was empty on every
## row until Pass B; a reader that dropped trailing fields would report the column missing
## rather than empty, which is a different and more confusing failure.
func test_trailing_empty_fields_are_kept() -> void:
	assert_eq(CsvLine.split("a,b,,").size(), 4, "two trailing empties are two fields")
	assert_eq(CsvLine.split(",").size(), 2, "even when the whole record is empty fields")


func test_escape_quotes_only_what_needs_it() -> void:
	assert_eq(CsvLine.escape("plain"), "plain", "an ordinary value stays bare and diffable")
	assert_eq(CsvLine.escape("a,b"), '"a,b"')
	assert_eq(CsvLine.escape('say "hi"'), '"say ""hi"""')


## The property that actually matters: whatever a rule string contains, writing it and
## reading it back yields the same string, in the same column.
func test_any_field_round_trips_through_join_and_split() -> void:
	var awkward := PackedStringArray(
		[
			"unit/logic/test_thing.gd",
			"test_a_name",
			'name cites "the taskblock", which is deleted',
			"120",
			"a debug verb reuses the real gameplay path, never a shortcut",
			"",
		]
	)
	assert_eq(CsvLine.split(CsvLine.join(awkward)), awkward, "round trip is the identity")
