class_name InjectionEvents
extends RefCounted

## `BR51.21`: **which of an injection's log events are its effects, and which are bookkeeping
## about it.**
##
## `BoutInjector` emits three kinds that describe the *call* rather than anything that happened on
## the board: `CommandLog`'s `command`/`command_outcome` audit pair, which every verb emits before
## anything can refuse it and after it resolves, and `_log_injection`'s own `inject` marker.
##
## **They are present on every verb, including one that changes nothing**, and that is the whole
## reason this class exists. A caller capturing the log around a verb — `DebugControlPanel` does,
## so an injection can be animated — cannot ask *"did this produce anything to watch"* with
## `events.is_empty()` when three lines are always there. Without the distinction,
## `ResolutionPlayer.play` would raise its RESOLUTION banner and sit through `RESOLVE_LEAD_IN`
## every time anyone pressed Apply on a verb with no visible effect at all.
##
## ## Why it is its own file
##
## It was written on `BoutInjector` first, which is where the vocabulary belongs, and that file was
## already at **998 against a cap of 1000** — the addition put it at 1026. (Both figures are as
## they stood then; the live cap is `gdlintrc`'s `max-file-lines`.) The alternative
## was paying for it by shortening comments, which taskblock-61 has already done once to
## `board_view.gd` and recorded as the worst of the available trades: recorded reasoning deleted to
## satisfy a line count. **Splitting a genuinely separable question out is the honest way to pay**,
## and "effect versus bookkeeping" is one job with one caller-facing function.

## The kinds that describe the injection rather than its consequences.
##
## Read from `CommandLog`'s own constants rather than re-typed, so renaming either cannot leave
## this list silently behind. `inject` has no constant to read — it is a bare `StringName` at
## `BoutInjector._log_injection`'s single emit site.
const AUDIT_KINDS: Array[StringName] = [
	CommandLog.COMMAND_KIND,
	CommandLog.OUTCOME_KIND,
	&"inject",
]


## The events a verb actually caused, with the bookkeeping about the verb removed.
##
## An empty return is the honest answer to *"this verb did nothing worth watching"* — which is what
## lets the animate-or-not decision be a property of the verb's own output rather than a table of
## animatable verbs somebody has to keep in step with `DebugVerbs`.
static func effects(events: Array[LogEvent]) -> Array[LogEvent]:
	return events.filter(func(event: LogEvent) -> bool: return not AUDIT_KINDS.has(event.kind))
