# reports/ — after-action reports

One report per taskblock, written when that block finishes. **These are not living documents and are
never current-state authority.** A report describes what one block did at the moment it finished;
later blocks may have reversed or re-diagnosed any of it. If a report and a living doc disagree, the
living doc wins.

The authorities are `docs/CHANGELOG.md` (what exists now), `docs/SUPERSEDED.md` (what was reversed),
`docs/BUGS.md` + `docs/BUGS-ARCHIVE.md` (defects), `docs/PLAN.md` (what's unbuilt).

## What goes in one
A report is written to be reviewed once, then it's spent. It answers "what did you decide on your
own, and what should I look at?" Four things, all of which have no other home:

- Decisions made without asking
- Tests that failed, then were corrected
- `SUPERVISOR`-owned entries moved to `Pending`
- Open questions needing a supervisor call

Everything else has a canonical home and shouldn't be repeated here: test counts and commits
(`git log`), files touched (`git diff --stat`), what got built (`docs/CHANGELOG.md`), seed re-picks
(the test file's header), bugs (`docs/BUGS.md`). Two records of the same thing eventually disagree.

## Rolling window
Keep the five most recent. After writing `Report-TaskblockN.md`, delete
`Report-Taskblock(N-5).md` in the same commit.

Nothing is lost — every report is committed before it's removed, so git history keeps them all
(`git log --diff-filter=D --name-only -- reports/` to list, `git show <commit>:<path>` to read).
Deletion is mechanical, not a judgement call: it's safe because durable content was moved to the
living docs when the report was written.

## Don't cite a report by filename
The window rolls, so a path that works today breaks later. Carry the fact inline instead. Provenance
tags (`tb31 C`, `taskblock-27 Pass A`) are fine — they're labels, not links.
