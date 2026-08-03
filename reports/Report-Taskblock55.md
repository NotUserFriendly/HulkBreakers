# Taskblock 55 Report — Only parts carry height, and sections learn to declare

**Pass A landed and is green. Passes B–E are not started, and that was a deliberate hand-off**
rather than a stall — see *Open questions*. Suite green with Pass A in.

## Decisions made without asking

- **The shared helper owns the directory walk as well as the boundary.** The pass asked for "one
  shared boundary helper"; all three guards had also grown their own copy of the same recursive
  scan, which is the same drift risk one level down. `VocabularySweep` owns both, and each guard
  keeps only its own **policy** — which allowlist applies, whether `-> void` is exempt, whether a
  hit is checked per-occurrence. Those genuinely differ, and forcing them into the shared class
  would have been a worse coupling than the duplication it replaced.
- **`VocabularySweep` is exempt from every sweep it runs**, stated once in the class rather than
  added to three allowlists. Each guard already exempts its own `SELF_PATH` for the same reason —
  explaining a rule means naming the word it forbids — and this file explains three at once. It
  is a permission for *a file that is part of the mechanism*, not for a word; conflating those is
  how an allowlist grows entries nobody can justify later.
- **The `HULK_` guard's own scanner was deleted rather than left beside the shared one.** Once the
  shared walk replaced it, `_scan_dir`/`_scan_file` were dead code that still looked authoritative.
- **The dangling reference was fixed, not just de-worded.** `grid_fixture.gd` named
  `MapGen._finalize_walls_and_void`, which is both retired vocabulary *and* a function that no
  longer exists — it is `_finalize_walls_and_empty`. Renaming the comment to match the real
  function was the actual fix; removing the word alone would have left a comment pointing at
  nothing.

## Tests that failed, then were corrected

1. **The shared helper failed two of the three guards it serves.** Its doc comment necessarily
   names all three retired words, and two of those guards scan it. Fixed by the exemption above
   rather than by rewording, because naming all three in one place is precisely this file's job.
2. **Then the guards failed *each other*.** My new comments in the `void` and `HULK_` guards
   referred to the others by their reserved words. Reworded to "the other two vocabulary guards" —
   the shared helper is the one place allowed to spell them. **This is the second block running in
   which vocabulary guards have caught each other**, which is a good sign the rules are real and a
   standing hazard when writing about them.
3. **`gdlint` gates the build and rejected two comment lines over 100 characters** — introduced by
   the rewording above. Worth noting only because the failure arrives as a build failure rather
   than a test failure, and the suite output shows nothing else.

## Open questions

- **Passes B–E are unstarted, by agreement.** The judgement was that this session did not have the
  context left to do Pass C — the section authoring vocabulary — at the standard the format
  deserves. It is the largest pass in the block, it is a *format* decision that D, E, the editor
  and the generator all build on, and the taskblock itself flags that `SectionSerializer`'s
  delegation to `MapSerializer` has to become partial there. Getting that shape wrong is expensive
  in a way that Pass A's mechanical sweep is not.
- **Pass A found less than expected, and that is itself a result.** The corrected boundary caught
  **one** line for the retired absence word and **zero** for the `HULK_` prefix. The `HULK_` guard
  was never vulnerable — a prefix pattern with no lookbehind matches *more*, not less — so the
  taskblock's premise that "both earlier sweeps used the same pattern" holds for one of the two.
  The sweep still earns its place: the one hit was a dangling function reference, and all three
  guards now share a boundary that cannot drift.
- **The allowlists did shrink, as predicted.** The retired-absence guard needs **no** allowlist at
  all now — `avoid` and `devoid` are excluded by the boundary itself, because each has a letter
  before the word. Only the `tile` guard keeps one entry (`tileable`), and the `HULK_` guard keeps
  its one domain constant.
