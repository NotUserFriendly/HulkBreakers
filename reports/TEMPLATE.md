# Taskblock N Report — <title>

<!--
Written for review, not for history. Four sections; delete any that's empty rather than padding it.
Don't include test counts, commit lists, files touched, a pass-by-pass build narrative, seed
re-picks, bugs found, or what's still open — each has a canonical home (git, docs/CHANGELOG.md, the
test file's header, docs/BUGS.md). See reports/README.md.
-->

One or two lines: which passes landed, in what order, whether the suite is green.

## Decisions made without asking
Anything decided unilaterally that the supervisor might have decided differently — a design call the
spec didn't cover, scope taken on or dropped, an approach chosen over a named alternative. What was
decided, what the alternative was, why. This is the section the report exists for.

## Tests that failed, then were corrected
Up to five, with how many were failing before correction. What broke, the real root cause, the fix.
If a test failed because the change was right and the fixture held an old assumption, say so — that's
the most useful kind here.

## `SUPERVISOR`-owned entries moved to `Pending`
One line each, with what the supervisor needs to do to see it work. These can't close without them.

## Open questions
Anything blocked on a supervisor call, or a fork left open. Give the options and which way the
evidence points.
