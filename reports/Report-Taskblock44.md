# Taskblock 44 Report — AI v2, part one: measure, invert, seam

**IN PROGRESS — Passes A and B.** C and D are not started. `taskblock44.md` is in the tree and is
still the authority on what they are; this file records what landed.

**The rolling-five window is deliberately NOT rolled yet.** `Report-Taskblock39.md` stays until this
block finishes — deleting it for a one-pass stub would trade a complete record for an incomplete one.
Roll it when the block closes.

Suite 2279/2279 at Pass B. Commits `c7d6afe` and `7c6dab0` (Pass A), `89070ec` (Pass B).

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

## `SUPERVISOR`-owned entries moved to `Pending`

**None.** `BR27.09` gained the completed release-vs-debug measurement and its status is untouched, per
the block's own instruction that CC appends numbers and the supervisor closes. `BR44.01` was found by
CC, is `CC`-owned, and was resolved and archived directly.

## Open questions

- **The release number does not reduce Pass B's urgency, and the supervisor's call is whether it
  changes anything else.** ~1.29× was the optimistic scenario failing; the planning cost is real.
- **Nothing else is open on Pass A.** Both halves are done: the provenance stamp and the measurement.
