class_name BuildIdentity
extends RefCounted

## taskblock-44 Pass A: **which build produced this number.**
##
## Every performance figure this project has recorded — BR26.02, BR27.09, tb35's
## 2023ms→974ms, tb43's bench — came from a debug run, and nobody has ever
## checked how much of the hitch is the game versus GDScript's per-line debug
## overhead. taskblock-43's report then had to explain at length why its figures
## were not continuous with the historical series, because neither the old
## numbers nor the new ones said where they came from.
##
## **A measurement that does not carry its own provenance is a measurement
## somebody has to defend in prose later.** So every instrument that records a
## number stamps this alongside it, and the question stops being askable.
##
## Pure derivation over `OS`/`Engine`, no SceneTree — so the classification is
## itself headlessly testable, rather than being something only a human running
## two builds could check.

## The closed set of builds this project can produce a number from. An enum
## would be wrong here for the usual reason (`CLAUDE.md`: enums are for engine
## states), but this genuinely IS one — it is not content a designer extends, it
## is the fixed set of ways Godot can be running. Kept as `StringName` anyway so
## it lands in a `LogEvent`'s data dictionary without conversion.
##
## - `editor_debug` — run from the editor or a tools binary (`--headless -s ...`,
##   and every GUT run). **This is what every historical number in this project
##   was taken on.**
## - `exported_debug` — an exported build with debug enabled: templates, but
##   still carrying the per-line overhead.
## - `exported_release` — an exported release build. The only one that reflects
##   what a player actually runs.
const EDITOR_DEBUG: StringName = &"editor_debug"
const EXPORTED_DEBUG: StringName = &"exported_debug"
const EXPORTED_RELEASE: StringName = &"exported_release"


## Which of the three above is running.
##
## `OS.has_feature("editor")` is the tools/template split — true for the editor
## binary in any mode, including `--headless -s`, which is how every bench and
## every test in this project runs. `OS.is_debug_build()` then separates an
## exported debug template from an exported release one.
static func kind() -> StringName:
	if OS.has_feature("editor"):
		return EDITOR_DEBUG
	return EXPORTED_DEBUG if OS.is_debug_build() else EXPORTED_RELEASE


## True only for the one build whose numbers mean what a player would feel.
## Everything else carries GDScript's debug per-line cost by an unmeasured
## factor — unmeasured because taskblock-44 Pass A could not export in CC's
## environment (no templates installed); see that pass's report.
static func is_representative_of_play() -> bool:
	return kind() == EXPORTED_RELEASE


## One line, safe to print at the top of a bench or stamp into a log event:
## the build kind, the engine version, and the platform. Deliberately stable in
## shape so two runs can be diffed by eye.
static func describe() -> String:
	var version: Dictionary = Engine.get_version_info()
	return (
		"build=%s godot=%s platform=%s" % [kind(), version.get("string", "unknown"), OS.get_name()]
	)


## The same facts as `describe()` in machine-readable form, for a `LogEvent`'s
## own data dictionary — so a log reader never has to parse the prose, the same
## convention `FpsDumpSink.data.offset_ms` already follows.
static func as_data() -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	return {
		"build": kind(),
		"godot": version.get("string", "unknown"),
		"platform": OS.get_name(),
		"representative": is_representative_of_play(),
	}
