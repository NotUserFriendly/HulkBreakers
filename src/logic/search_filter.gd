class_name SearchFilter
extends RefCounted

## taskblock-57 Pass G1: **what "searchable" means, as arithmetic over strings.**
##
## The taskblock asks the editor's bar for *"a centred, searchable list of every part placeable on a
## tile"*, and the acceptance is *"the place-items list is searchable and offers every placeable
## part"*. Searching is a rule about text, so it is logic (CLAUDE.md) — the list widget renders
## whatever this returns and decides nothing.
##
## ## The rule
##
## **Every whitespace-separated term in the query must appear somewhere in the entry**, compared
## case-insensitively with `_` read as a space. So `ship floor` finds `ship_floor`, `floor ship`
## finds it too, and `hip` finds it as well — the terms are substrings, not word prefixes, because
## an author who half-remembers a part id should still land on it.
##
## **An empty query matches everything.** That is what makes "offers every placeable part" and
## "is searchable" the same list rather than two: the list opens unfiltered and narrows as you type.
##
## An id is the only thing matched. Parts have no display names — `Part.id` is what the whole
## project names them by — and inventing one here would be a second vocabulary for the same thing.


## The entries of `entries` matching `query`, in their original order. Order is preserved rather
## than ranked: the caller sorts its own list once, and a result set that reshuffles as you type is
## one you cannot click on reliably.
static func matching(entries: Array[StringName], query: String) -> Array[StringName]:
	var terms: PackedStringArray = terms_of(query)
	if terms.is_empty():
		return entries.duplicate()
	var kept: Array[StringName] = []
	for entry: StringName in entries:
		if matches(entry, terms):
			kept.append(entry)
	return kept


## True if `entry` contains every term. `terms` comes from `terms_of`, already normalised.
static func matches(entry: StringName, terms: PackedStringArray) -> bool:
	var normalised: String = normalise(String(entry))
	for term: String in terms:
		if not normalised.contains(term):
			return false
	return true


## `query` split into normalised terms. Empty for a query that is blank or only separators, which
## is the "match everything" case.
static func terms_of(query: String) -> PackedStringArray:
	return normalise(query).split(" ", false)


## Lower-cased, with `_` and `-` read as spaces. **Both directions go through this**, so a query and
## an entry are always compared in the same shape — comparing a raw id against a normalised query is
## the bug this exists to make impossible.
static func normalise(text: String) -> String:
	return text.to_lower().replace("_", " ").replace("-", " ").strip_edges()
