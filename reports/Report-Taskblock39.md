# Taskblock 39 Report — Retire the legacy grid model

All four passes landed in order (A→B→C→D), each committed separately, full suite green throughout:
2120/2120 at the end. `GridLegacyBridge`'s own burn-down counter reached zero before it was deleted
(down from tb38's 4,318,367 hits); a final grep sweep finds no surviving `Grid.level`, retired
`TerrainType` value, or `GridLegacyBridge` reference anywhere, tests included.

## Decisions made without asking

- **Dropped the height-formula comparison from the surfaces/terrain cross-check test, rather than
  re-deriving it.** `test_generated_map_surfaces_match_terrain_and_level_cell_for_cell` originally
  compared a placed `Surface`'s height against `grid.get_level(cell) * LEVEL_HEIGHT` (+ ramp offset)
  computed by hand in the test. With `Grid.level` deleted there's nothing left to compare against
  except hand-reconstructing `MapGenScratch.place_surface`'s own formula a second time inside the
  test — exactly the "a formula that looks plausible on paper, and a test that re-derives it, agree
  with each other and with nothing else" trap CLAUDE.md calls out for view math. Narrowed the test
  (renamed `test_generated_map_cells_carry_at_most_one_correctly_typed_floor_surface`) to what's
  checkable without a second copy of the formula: exactly one surface per floored cell, correct part
  id via the shared `Surface.is_ramp_at`. Less coverage than before, but the alternative was a second
  formula that could silently drift from the real one.
- **Renamed `BoardView`'s `_build_void_indicators`/`VOID_*` constants to `_build_empty_indicators`/
  `EMPTY_*`, but left `MapGen._finalize_walls_and_void` and its doc comment's function name
  unchanged.** Drew the line at "does this identifier assert 'void' as the CURRENT term for the
  physical state" (glyph names, marker constants, test names — yes) versus "is this a private helper
  name where renaming touches call sites for no acceptance-relevant gain" (no, matching a judgment
  call already made for `_finalize_walls_and_void` earlier in this same pass). Flagged below as an
  inconsistency worth a second look rather than silently left unremarked.
- **Deleted `test_dup_copies_level` outright instead of migrating it.** `Grid.level` and `dup()`'s own
  level-cloning behavior no longer exist — there's no equivalent behavior left to test, so this
  followed CLAUDE.md's "delete completely" guidance for confirmed-unused code rather than inventing a
  substitute assertion the taskblock never asked for.
- **Dropped the "no raw WALL cell may survive generate()" half of the wall/void resolution test.**
  `Grid`'s enum no longer has any WALL-shaped concept to assert against at all post-rename — renamed
  the test (`test_generate_resolves_every_cell_into_a_destructible_wall_part_or_empty_space`) and kept
  only the half still expressible: the settled floored+wall-Part / unfloored split the real placement
  output actually produces.

## Tests that failed, then were corrected

Five, spanning the whole taskblock, none a regression outside this taskblock's own new work:

1. **`test_climb_action.gd`'s ramp-climb-cost test** was pinned against `GridLegacyBridge`'s
   superseded flat `+0.5` ramp offset (tb37). Migrating onto a real placed ramp `Surface` changed the
   asserted cost from 2 MP to 3 MP — matching `RampGeometry.STANDING_OFFSET`, tb38 Pass C's already-
   corrected value. The test was stale, not the game; renamed and the expected cost corrected rather
   than silently re-pinned.
2. **`test_squad_control_overlay.gd`'s real-raycast click test** broke once its wall fixture got real
   3D blocker geometry — `PartPicker.hit()` can report a closer blocker hit than a unit hit, and the
   fixture's wall sat on the shooter/enemy's shared view-axis column, occluding the click. Root-caused
   via camera-position math and `PartPicker`'s own blocker-priority logic; fixed by reorienting the
   fixture perpendicular to the camera's default view axis, not by weakening the assertion.
3. **`test_unit_ai.gd`'s covered-aggressive-unit test** — `GridFixture.place_wall` for a row meant to
   only constrain pathing width also tripped `UnitAI.is_covered_from`'s separate `grid.blockers` raymarch,
   unlike the old terrain-code-only wall it replaced. Fixed with `grid.clear_surfaces(cell)` (an
   unfloored gap — impassable, no blocker, no opacity) instead of a real wall for that row.
4. **`test_determinism_check.gd`'s own custom-compare-fn test** broke on the first full-suite run
   after the `Grid.terrain`→`Grid.spawn_marker` rename — a stale `a.terrain`/`b.terrain` field read in
   its own lambda, missed by the earlier method-call grep sweep since it's a direct field access, not
   a `get_terrain(`/`set_terrain(` call. Worth noting: this single stale reference was enough to
   silently truncate the *entire* suite with no Run Summary (Godot's `-d` flag turns any uncaught
   script error into an interactive debugger break, which hangs given closed stdin here) — fixed by
   updating the field name, confirmed by a subsequent full green run.
5. **This taskblock's own new `test_map_gen_touches_grids_spawn_marker_api_only_in_spawn_marking`**
   failed against its own first draft — an overly broad `"Grid.level" in line` substring check flagged
   plain doc-comment prose mentioning the retired field name for historical context, not just live
   code. A false positive in newly-written test code, not a regression; narrowed to the four literal
   method-call patterns (`grid.set_terrain(`/`get_terrain(`/`set_level(`/`get_level(`), which is
   sufficient since the field itself no longer exists to be silently reintroduced as a bare access.

## `SUPERVISOR`-owned entries moved to `Pending`

None — this taskblock didn't touch `docs/BUGS.md`; nothing here closes a tracked defect. All bugs
found above (items 1–3) were introduced and fixed within this same taskblock's own migration, never
externally reported.

## Open questions

- **The `_finalize_walls_and_void`/`_build_void_indicators` naming split.** This pass renamed
  `BoardView`'s void-named constants/function but left `MapGen._finalize_walls_and_void` as-is — both
  are private, both use "void" as a historical/English word choice rather than a live retired-enum
  reference, so neither strictly violates the taskblock's own grep-strict acceptance (which targets
  `Grid.level`/`TerrainType` values/`GridLegacyBridge`, not arbitrary identifier spelling). Worth a
  supervisor call on whether full identifier-level consistency is wanted here, or whether "no code or
  comment uses void for the physical state" was always meant to be a prose/vocabulary rule rather than
  a rename-every-private-symbol one.
- **taskblock-37 Pass E's two open items** (camera framing at height, the wall cutout against
  elevation) are untouched by this block and remain pending supervisor attention, carried forward from
  `docs/PLAN.md`.
