# Taskblock 40 Report — Multi-level Pass E: view-layer legibility

All four passes landed in order (A→B→C→D), each committed separately, full suite green throughout:
2125/2125 at the end (started at 2121). Closes `PLAN.md`'s "Multi-level maps — Pass E" item outright.
Pass D also surfaced a real, unfixed camera-solver bug (`BR40.01`) — flagged, not fixed, per the
pass's own scope.

## Decisions made without asking

- **Pass A: `move_action.gd`'s prose rewritten to literally cite `-> void` rather than paraphrase
  around it.** A doc comment describing a hook typed to return nothing used the phrase "a void hook,"
  which trips the acceptance grep despite being a legitimate reference to the return annotation, not
  the retired physical-absence sense. Rewrote it to name the actual annotation (`` a hook typed `->
  void` ``) instead of inventing a paraphrase — this is the same pattern the acceptance grep already
  exempts, applied honestly rather than danced around.
- **Pass B: no code change, per the pass's own explicit fence.** The height-delta matrix showed every
  hard invariant (both-fit, never-below-body, continuity) holding cleanly at every delta tested,
  including ±6 — the one soft number (vertical look angle growing to ~25–34° at a 6-level delta) is
  real but bounded, and the taskblock was explicit that "aesthetic, not broken" isn't CC's call to
  make unilaterally. Left entirely to Pass D's checklist rather than applying the B4 midpoint-anchor
  idea speculatively against numbers that didn't ask for it.
- **Pass C: no new `docs/BUGS.md` entry.** Reasoned that elevation gives BR32.05's existing coarse
  heuristic a structurally new way to misfire (an elevated wall reading as Euclidean-nearer than a low
  target despite sitting horizontally behind it — impossible on a flat map) but concluded it's the
  same root cause and same candidate fix BR32.05 already names, so a finding was appended there
  instead of opening a duplicate.
- **Pass D: built through the existing checkpoint infrastructure (`checkpoint_8.gd`,
  `./checkpoint.sh 8`), not a new one-off harness or the full "shared scenario format"
  `docs/PLAN.md`'s tester-ergonomics item still wants.** That format doesn't exist yet (confirmed by
  a repo-wide search before writing anything) and building it in full is its own, larger, unscoped
  item. Checkpoints are this repo's own established "load a real thing, hand it to the supervisor,
  hard stop" mechanism (checkpoints 1–7 already do exactly this), so checkpoint 8 is a real instance
  of the down payment the taskblock asked for, not a parallel format.
- **Pass D: this sandbox turned out to have a real GPU + X11 display, so the scenario was actually
  rendered and inspected (via the Read tool's image support) rather than handed off unverified.**
  CLAUDE.md's "you cannot see the game" is the default assumption, not a hard constraint that held
  here — verified first with a throwaway run of the existing checkpoint 6, which is how `BR40.02`
  (below) was found before checkpoint 8 was even written. Everything mechanically checkable was
  checked before this reached the report.
- **Pass D: kept the "target below" screenshot as-is instead of re-shooting it with a bigger platform
  once `BR40.01` was found.** The natural 3×3 platform genuinely walks the camera off its own edge for
  this pair; enlarging the platform until the symptom disappeared would have hidden real evidence
  instead of documenting it, and cost the bug its own live repro. The checklist says so explicitly
  rather than presenting a silently-avoided case as a clean sample.
- **Pass D: `BR40.01` filed as `Active`, not `Suspected`, despite being found via one engineered
  scenario.** The mechanism is root-caused and numerically confirmed (the exact solved camera position
  sits past the platform's own edge), not a hunch — `Suspected` would undersell evidence that's
  already a full description with a reproducible repro command.
- **Pass D: an unrelated staleness bug (`BR40.02` — `checkpoint_6.gd`/`checkpoint_7.gd` crash outright,
  referencing the long-renamed `UnitView` class) was filed and left unfixed**, not silently repaired
  mid-pass and not ignored. Confirmed via `grep` that `UnitView` no longer exists anywhere in `src/`;
  `checkpoint_8.gd` was written fresh against the current `HitVolumeView`/`load_battle()` path, so it
  isn't affected, but 6 and 7 need their own pass.

## Tests that failed, then were corrected

One, caught before commit:

1. **Pass B's own new same-level regression guard** (`test_pass_b_same_level_solve_is_pinned_as_a_
   regression_guard`) was written first with hand-guessed expected yaw/pitch/zoom values, which is
   exactly the trap the test exists to avoid — three assertions failed against the real solver's
   actual output. Corrected by reading the real values back from a run and pinning those instead of a
   second, independently-typed copy of the formula's expected result.

## `SUPERVISOR`-owned entries moved to `Pending`

None — no entry in `docs/BUGS.md` was closed this taskblock. `BR32.05` (`SUPERVISOR`-owned) gained a
Pass C finding, not a closure. `BR40.01`/`BR40.02` are new, `CC`-owned, and still open.

## Open questions

- **`BR40.01`'s fix direction** — cap `_solve_back`'s search at the shooter's own floored extent, or a
  real occlusion check against placed `Surface`s/`Grid.blockers` (the same class of fix `BR32.05`
  already wants, possibly shareable). Not chosen; a supervisor call on priority and approach would
  help, alongside checklist item 5 (how often this comes up on real generated maps versus a
  deliberately narrow fixture).
- **Whether `BR40.02` (stale checkpoints 6/7) is worth its own follow-up pass now or can wait** —
  neither script is on the `run_tests.sh` gate, so nothing forces the question, but they've been
  silently broken since whatever taskblock renamed `UnitView` and nobody would know without this one
  having run one by hand.
- **The actual point of this taskblock — does the framing and the wall cutout look right —** is
  entirely the supervisor's own call now. `./checkpoint.sh 8` and its generated checklist are the
  hand-off; nothing further from CC until that's been looked at.
