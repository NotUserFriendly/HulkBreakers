extends GutTest

## taskblock-57 Pass G1 — **what "searchable" means, asserted without a widget.**
##
## The taskblock's acceptance is *"the place-items list is searchable and offers every placeable
## part"*, which is two claims: the empty query returns everything, and a typed query narrows it.
## Both are properties of the rule, so both are testable here — `SearchableList` renders whatever
## this returns and is asserted separately for the rendering.

const PARTS: Array[StringName] = [
	&"ship_floor",
	&"ship_wall",
	&"barrel",
	&"crate_small",
	&"crate_large",
	&"rifle",
]


## **The half that makes "offers every placeable part" true.** A list that opened filtered would
## show a subset the author never asked for.
func test_an_empty_query_matches_everything() -> void:
	assert_eq(SearchFilter.matching(PARTS, ""), PARTS)
	assert_eq(SearchFilter.matching(PARTS, "   "), PARTS, "whitespace is not a query")


func test_a_query_narrows_to_the_entries_containing_it() -> void:
	assert_eq(
		SearchFilter.matching(PARTS, "crate"), [&"crate_small", &"crate_large"] as Array[StringName]
	)


## `_` reads as a space in both directions, which is what lets an author type what they see rather
## than what the id spells.
func test_an_underscore_reads_as_a_space() -> void:
	assert_eq(SearchFilter.matching(PARTS, "ship floor"), [&"ship_floor"] as Array[StringName])
	assert_eq(SearchFilter.matching(PARTS, "ship_floor"), [&"ship_floor"] as Array[StringName])


## Every term must appear, and the order they are typed in does not matter — a half-remembered id
## should still land.
func test_terms_match_in_any_order_and_all_must_appear() -> void:
	assert_eq(SearchFilter.matching(PARTS, "floor ship"), [&"ship_floor"] as Array[StringName])
	assert_eq(
		SearchFilter.matching(PARTS, "ship barrel").size(),
		0,
		"both terms must appear in the SAME entry"
	)


func test_matching_is_case_insensitive() -> void:
	assert_eq(SearchFilter.matching(PARTS, "BARREL"), [&"barrel"] as Array[StringName])


## Results keep the caller's own order. A set that reshuffles as you type is one you cannot click
## on reliably — the row under the cursor becomes a different row between keystrokes.
func test_results_preserve_the_order_they_were_given_in() -> void:
	var scrambled: Array[StringName] = [&"crate_large", &"crate_small"]
	assert_eq(SearchFilter.matching(scrambled, "crate"), scrambled)


func test_a_query_matching_nothing_returns_nothing_rather_than_everything() -> void:
	assert_eq(SearchFilter.matching(PARTS, "nothing_is_called_this").size(), 0)


## The filter never hands back the caller's own array, so a caller that mutates the result cannot
## corrupt the source list it is filtering.
func test_the_unfiltered_answer_is_a_copy_not_the_source_array() -> void:
	var source: Array[StringName] = [&"a", &"b"]
	var result: Array[StringName] = SearchFilter.matching(source, "")
	result.append(&"c")
	assert_eq(source.size(), 2, "the source list was mutated through its own filter result")
