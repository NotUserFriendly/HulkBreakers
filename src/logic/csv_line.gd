class_name CsvLine
extends RefCounted

## taskblock-49 Pass B: **one CSV field codec, used by everything that reads or writes
## `test/suite_audit.csv`.**
##
## Pass B filled the audit's `rule_guarded` column with real sentences, and system rules
## are sentences with commas in them — *"a debug verb reuses the real gameplay path, never
## a shortcut"*. The writer quoted them correctly and the reader split naively on `,`,
## which shifted every numeric column one place right: the audit test read `bouts` as
## **8697** against a true total of **56** and went red.
##
## The fix is not to ban commas from the vocabulary — that would let the file's format
## dictate the classification. It is to write CSV and read CSV, from one place. A second
## hand-rolled splitter somewhere else is the same bug waiting again.

const QUOTE := '"'
const SEPARATOR := ","


## Split one CSV record into fields, honouring quoted fields and doubled quotes.
##
## Trailing empty fields survive: `"a,b,,"` is four fields, not two. That matters here
## because the two judgement columns are frequently empty and one of them is last.
static func split(line: String) -> PackedStringArray:
	var fields := PackedStringArray()
	var current := ""
	var quoted := false
	var i := 0
	while i < line.length():
		var ch: String = line[i]
		if quoted:
			if ch == QUOTE:
				# A doubled quote inside a quoted field is one literal quote.
				if i + 1 < line.length() and line[i + 1] == QUOTE:
					current += QUOTE
					i += 1
				else:
					quoted = false
			else:
				current += ch
		elif ch == QUOTE:
			quoted = true
		elif ch == SEPARATOR:
			fields.append(current)
			current = ""
		else:
			current += ch
		i += 1
	fields.append(current)
	return fields


## Quote a field only when it needs it — a comma, a quote, or a newline in the value.
## Leaving ordinary fields bare keeps the committed artifact diffable by eye.
static func escape(field: String) -> String:
	if (
		field.contains(SEPARATOR)
		or field.contains(QUOTE)
		or field.contains("\n")
		or field.contains("\r")
	):
		return QUOTE + field.replace(QUOTE, QUOTE + QUOTE) + QUOTE
	return field


## Join fields into one record, escaping each.
static func join(fields: PackedStringArray) -> String:
	var out: PackedStringArray = PackedStringArray()
	for field: String in fields:
		out.append(escape(field))
	return SEPARATOR.join(out)
