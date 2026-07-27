# Taskblock 44 Report — AI v2, part one: measure, invert, seam

Passes A–D all landed, in order. Suite 2301/2301.

**Two things are worth reading before the rest.** The block's own premise about where AI time goes was
right for the first time in four taskblocks — and acting on it revealed that the project had never
been exported, which turned out to matter more than the optimisation did.

## Where the number stands

The pass's own question — how much of the hitch is the game and how much is the debug harness — is
answered. Same bench, same seeds, same steps:

| build | ms per AI step |
|---|---|
| `editor_debug` — every historical figure this project has ever recorded | ~686–712 |
| `exported_debug` | ~665 |
| **`exported_release`** | **~530–554** |

**Release is ~1.29× faster, and that is the unwelcome answer.** The hoped-for result was "most of the
cost is the harness"; roughly 78% of it survives into a real player build. The AI planning cost is
genuine and Pass B's urgency is unchanged. `candidates_skipped` was identical (2306) across all three
builds — the cross-check that the same deterministic work ran in each, rather than three different
trajectories being compared.

## Pass B: the cost moved rather than vanished, and that is the finding

**~686–712ms → ~523–528ms per AI step (~24%)** on `editor_debug`; **~412ms** exported release. Full
suite green including `test_full_mission.gd` and the byte-identical seeded-bout tests, which is the
stated acceptance — the field only prefilters and `ShotPlane` still confirms, so no decision may
change.

The per-turn profile is where the interesting part is:

| | before | after |
|---|---|---|
| `field_build` | — | **4.2ms** |
| `any_lof_scan` | 271.9ms | **77.8ms** |
| `engagement_search` | 98.3ms | **251.2ms** |
| `nearest_enemy` | 15.0ms | 14.9ms |
| `Pathfinder.reachable` | 2.5ms | 2.5ms |

**`engagement_search` did not get slower — it was being subsidised.** The old scan built a
`ShotPlane` for nearly every reachable cell and left them in the per-turn memo, so the scorer ran
warm off work the scan had already paid for. Now the scan short-circuits on the field and the scorer
pays for its own casts on the cells the field allows. **The remaining cost is per-candidate casts
inside `_engagement_score`, not the prefilter** — which is the answer B4 asks for before Pass D, and
it says the per-unit plan is still far above D2's ~100ms threshold.

## Pass C: the seam, with the boundary drawn where review put it

The planner takes a `WorldView`; `CombatState` is reachable only through
`canonical_state_for_resolvers()`. Today it returns everything — a doorway, not a behaviour change —
and a seeded bout is byte-identical.

Supervisor review corrected the shape in three places before it was built, and the first was a hole I
would otherwise have shipped:

- **`grid` is not geometry.** `Grid` carries `occupant_id`/`get_occupant_id()` beside `blockers` and
  `surfaces`, so a raw grid lets the planner read the position of every unit on the board — including
  ones `units_visible_to` just filtered out. My proposed guard watched only the four `CombatState`
  fields and would have passed it clean. Took the cheaper of the two fixes deliberately: the guard
  refuses occupancy reads from the planner path.
- **`batch_plans` is gated information, not infrastructure** — the blackboard is Trained-and-above, so
  it sits on the observer-parameterised side. I gated the write as well as the read; a unit that could
  set a plan it cannot read back would be worse than one that plans for itself.
- **The resolver door needed a guard on derived access.** `canonical_state_for_resolvers()` may appear
  only as a bare argument, never followed by a dot.

The framing sentence is written at the seam because it is what tells part two where new fields go:
**the boundary is knowledge-about-units versus everything else, and that line runs through `Grid` and
through `BatchPlan` rather than around them.**

## Pass D: not faster, navigable

The planner yields mid-plan every `chunk` candidates and names the acting unit while it thinks. **This
makes nothing faster and is not meant to.** taskblock-42 Pass D yielded *between* steps and bought
nothing, because one step is the entire think.

**The chain became coroutines because GDScript forced it, and I probed rather than assumed:** a
conditional `await` is rejected at parse time — any function containing one is a coroutine and every
caller must await. The alternatives were a second synchronous planner (two code paths deciding one
thing) or no mid-plan yield. The upside is that the parser enumerated every call site, so the
conversion could not be silently incomplete.

A hard turn budget backs the label, because a thinking state that never ends is worse than a freeze.
Aborting is safe at any iteration by construction: the incumbent is the unit's own cell until
strictly beaten, so a cut-off scan returns a legitimate answer rather than a partial one.

## Decisions made without asking

- **Fixed BR44.01 rather than working around it, and it is the block's most consequential find so
  far.** The first-ever export of this project loaded **no data at all** — no parts, ammo, presets,
  materials or variant families. `DataLibrary._load_dir` filtered directory entries on
  `ends_with(".tres")`, true in the editor and false in every export, because
  `convert_text_resources_to_binary` defaults on and ships `crab.res` + `crab.tres.remap`. I could
  have made the bench work by disabling that conversion in the preset; that would have produced a
  release number from a build configured unlike any real one, and left the actual bug in place. The
  fix normalises directory entries back to the authored `.tres` name and loads by that path, so
  `ResourceLoader` resolves the remap and one code path serves editor and export alike.
- **A bare `.res` with no sibling remap is deliberately NOT handled.** Converted resources always ship
  with a remap, so that branch would be speculative handling for a case this project's data cannot
  currently produce — and it would need `_load_file` restructured to load by a path different from the
  one it keys on. Ignored exactly as it was before, which is a no-op change for it.
- **A `bench` custom feature and a per-feature `run/main_scene` override, rather than a second
  project.** An export template ignores `-s res://...` — it is tools-only — so the release bench needed
  a main-scene entry point. Alternatives considered: a separate project file (duplicated config that
  would drift), or making the real main scene detect a flag (putting bench concerns in the game's
  boot path). The feature-tag override is Godot's own mechanism for exactly this and leaves the
  ordinary game export untouched.
- **Two bench entry points, one implementation.** `AiPlanningBench` holds the body;
  `bench_ai_planning.gd` (SceneTree, `-s`) and `bench_main.gd` (Node, main scene) are three lines
  each. A bench whose debug and release paths could drift measures nothing, which is the entire point
  of the exercise.
- **`bench_release.sh` refuses to report a number** unless the binary itself declares
  `build=exported_release`. Inspecting the export command is not evidence about what actually ran, and
  a debug binary silently standing in for a release one is the one failure mode that would invalidate
  the whole measurement.
- **The export script is in `tools/`, not `run_tests.sh`.** An export takes real time and this is a
  measurement, not a gate — the same reasoning that keeps visual checkpoints off the test path.
- **`export_presets.cfg` stays gitignored; a committed `.example` carries what is shared.** Export
  paths are per-machine, but the preset *name* `bench_release.sh` passes to `--export-release`, and
  the `bench` feature without which the export boots the game instead of the bench, are not.
- **Pass B: the field occludes on opacity AND a projecting blocker, never opacity alone.** Opacity
  alone is not merely coarse, it is wrong: `Grid.opacity` is never cleared when a wall is destroyed,
  so a dead wall would occlude in the field while shots pass straight through it. That is
  under-inclusion, the one failure mode the design cannot tolerate. `BodyProjector.projects` was
  extracted from `project_part`'s body so there is one answer to "is this blocker still real" rather
  than two that could drift.
- **Pass B: no shadowcast.** The block specifies "one symmetric shadowcast"; the field instead runs
  the same `Grid.line` supercover walk `LoS` already uses, per cell, with a strictly weaker occluder
  test. The reason is that the containment obligation is the acceptance, and matching the walk the
  rest of the codebase already means by "a line between two cells" makes soundness inspectable rather
  than argued. The asymptotic win — one field per target instead of a cast per candidate — is fully
  realised either way; a shadowcast would further reduce the field's *own* build cost, which the
  profile now measures at **4.2ms** and is therefore not where the remaining time is. Worth revisiting
  only if that line grows.
- **Pass B: the 3D index carries one real distinction today.** `i = x + y*W + z*W*H` over a
  `PackedInt64Array` as instructed, but occlusion data in this project is 2D (`Grid.opacity` is per
  cell, no per-level component), so the z axis currently encodes exactly one thing: a cell at a
  different elevation from the target is always allowed, because a wall "at" a cell says nothing
  reliable about a shot passing over it. That is over-inclusion and therefore sound, and the
  representation is the part that has to be right now — a per-level structure with a cross-level path
  bolted on later is the thing that gets rewritten.

## Tests that failed, then were corrected

**None.** No test failed during this pass. The failures here were all at the export/run level and are
worth recording anyway, because two of them cost real time and neither was a test:

1. **Exit 139 (SIGSEGV), no output.** The exported game booting `battle_scene.tscn` headlessly. This
   was misread at first as `-s` being honoured and the bench crashing; it was the main scene, because
   `-s` was never read.
2. **Exit 136 (SIGFPE), no output, no banner.** BR44.01. An empty data pool makes `i % pool.size()` an
   integer modulo by zero, which a release build traps at the CPU with no message at all. **A
   missing-data bug presenting as a bare hard crash** is the single thing that made this slow, and the
   debug export — which reports it as an ordinary GDScript error with a backtrace — is what broke it
   open. Exporting debug *and* release is now the first diagnostic move, not the last.

The one methodological correction worth naming: I initially assumed `-s` was honoured in export
templates. Rather than keep guessing I passed `-s` a **nonexistent** script path — identical crash,
which proves the argument was never read. That is now recorded at the seam in `AiPlanningBench`.

**Pass B had one, and the premise was mine.** The containment sweep failed on two cells that were
themselves walls. `Grid.line`'s supercover picks up the neighbouring wall cells along the same wall,
while the real plane resolving from a position *inside* that wall does not. No call site can pose
that question — candidates come from `Pathfinder.reachable`, which never returns a live-blocker cell
— so the sweep is now scoped to standable cells and the disagreement is recorded at the contract
rather than papered over. A second failure was the bench itself: `--profile` was still calling the
pre-inversion path, and would have reported that Pass B changed nothing.

- **Pass D: `yields` is cumulative, `aborted` is per-turn.** They started as one reset-together pair
  and that made a bout-level "is slicing firing" assertion impossible — it could only ever see the
  last unit's count. "Did this unit overrun" and "is the mechanism working at all" are different
  questions and should not share a counter.
- **`gdlintrc max-file-lines` 1300 → 1350 → 1400, and I am flagging it rather than defending it.**
  That is the eighth bump for `unit_ai.gd`. The justification each time is that part two replaces this
  planner outright so a split would be discarded work — but that justification has now been used three
  times across two blocks, and it stops being true the moment part two slips. Passes B and C both took
  the other option first and put their logic in new files (`visibility_field.gd`, `world_view.gd`,
  `plan_pacer.gd`); what remains in `unit_ai.gd` is threading, which cannot leave without making
  private helpers public.

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** `BR27.09` gained the completed release-vs-debug measurement and its status is untouched, per
the block's own instruction that CC appends numbers and the supervisor closes. `BR44.01` was found by
CC, is `CC`-owned, and was resolved and archived directly.

## Open questions

- **BR27.09 is much smaller but not closed, and closing it is the supervisor's call.** ~700ms → ~525ms
  debug, ~412ms release, and the freeze is now a navigable wait. Whether that clears the bar the bug
  was filed against is a judgement about how it *feels*, which is exactly the kind of thing this
  ledger says CC does not get to decide.
- **The remaining cost has a name and it is not the prefilter.** Per-candidate `ShotPlane` casts
  inside `_engagement_score`, ~251ms per repositioning turn. Part two's scorer replaces that code
  entirely, so the honest question is whether to spend anything more on it first.
- **`unit_ai.gd` is at 1400 lines after eight cap bumps.** Worth an explicit decision: either part two
  starts soon and the file is genuinely throwaway, or it gets split. It should not quietly take a
  ninth bump.
- **Batches are still dormant** (taskblock-43 Pass C/D) and now so is the restriction flag — both are
  built, tested, and off. That is correct for a seam landed ahead of its consumer, but it is two
  mechanisms whose first real exercise is part two.
