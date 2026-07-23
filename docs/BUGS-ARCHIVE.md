# BUGS — Archive (closed entries)

Closed bug reports, moved out of `docs/BUGS.md` so the live ledger holds only what is still open.
**`docs/BUGS.md` is the working file; this is the history.** An entry lands here only once it is
`Resolved` — supervisor-confirmed for `SUPERVISOR`-sourced bugs, per the provenance gate. Nothing
is derived or generated: an entry is moved once, verbatim, and never edited again.

Full text is preserved for every entry — investigations, dead ends, and hypotheses included, since
those are exactly what a future session needs when a bug turns out not to be as dead as it looked.

---

### BR26.01 — Resolved — owner: `SUPERVISOR`
**Opposing team teleports before the player's own attack lands**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the last blue unit took its turn and the opposing team
  appeared to jump to new positions before that unit's attack animation resolved."
- **Root cause:** `SquadControlOverlay._on_turn_ended` called `advance_ai_turns(battle)` — which
  fast-forwards every AI turn with NO animation at all, a single instant `refresh_unit_views` at its
  own end — BEFORE the human's own turn had even started its own animated `resolution_player.play()`,
  and that `play()` call wasn't even awaited.
- **Fix:** reordered so the human's own turn is fully awaited through its complete animated playback
  before `advance_ai_turns` runs at all.
- **2026-07-20:** supervisor could not verify — blocked by a separate, new issue encountered during
  the attempt. **Verification deferred to the next taskblock** (supervisor's own call) rather than
  chased now; still pending either way.
- **RESOLVED** 2026-07-21 — supervisor could not reproduce on retry. taskblock-26 Pass B1.
- **2026-07-21, follow-up:** the underlying "AI batch is one synchronous, unanimated block" mechanism
  this bug's own fix left in place resurfaced as a heavy hitch instead of a teleport — see **BR27.09**,
  which now carries the live investigation.

### BR27.05 — Resolved — owner: `SUPERVISOR`
**Action bar items still selectable without enough AP**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20 (tb27 review). The tb27 Pass D3 fix (dim/disable unaffordable action-bar
  slots) **did not hold** — slots are still clickable/armable when the unit can't afford them.
- **Root cause (2026-07-21, tb30):** `ActionBar.refresh()`/`_on_box_gui_input()` both compared against
  `tactics.selection.selected_unit.ap` — the raw, un-queued unit. Per docs/09's own "queuing mutates
  nothing," `unit.ap` never drops for an action that's merely queued this turn, only once it resolves
  — so any AP already committed to an earlier queued action (e.g. a move that burned AP once MP ran
  out) was invisible to a LATER slot's own affordability check, which kept comparing against the
  unit's full starting AP.
- **Fix:** both call sites now read `tactics.selection.previewed_unit()` instead — the same source
  `SelectionController.reachable_cells()` already uses for the identical reason (it replays the
  current queue and returns what's actually left).
- **RESOLVED** 2026-07-21 — supervisor confirms: "I just cleared it visually." Commit `1c13ae5`. New
  regression test queues a move that burns AP via 0 MP, confirmed it fails without the fix and passes
  with it (`test_action_bar.gd::test_an_action_already_queued_this_turn_counts_against_a_later_
  affordability_check`). 1861/1861 green.

### BR27.06 — Resolved — owner: `SUPERVISOR`
**Step Out no longer occurs at all**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20 (tb27 review). After the tb27 Pass B flow restructure (BR27.01), Step Out
  now **doesn't happen at all** for the player — a regression past the original four symptoms.
- **Status:** reopened, and likely *the* blocker that stopped the supervisor verifying BR27.01/BR26.01
  ("blocked by a new, separate bug encountered during the attempt"). The split-flow restructure
  (confirm-cell → free out-leg → aim mode → fire → free return) probably breaks such that no step-out
  path completes. High priority — it gates confirmation of two other pending bugs.
- **2026-07-21 (taskblock-30): could not reproduce through any headless path — logged as a real
  negative result, not a fix.** Three new regression tests, each a strictly more realistic
  reproduction of the reported click sequence than the last, all pass on the SAME covered-corridor
  geometry `test_tactics_controller_step_out.gd` already used:
  1. `test_a_real_mouse_click_on_a_covered_enemy_also_enters_step_out_mode` — a real
     `InputEventMouseButton` through a real camera raycast into `TacticsController._handle_mouse_
     button` (every pre-existing test in the file drove `click_cell()` directly instead — a real,
     previously-uncovered code path, just not the bug).
  2. `test_action_bar.gd::test_clicking_an_affordable_action_still_arms_it` (already existed, already
     green) — a real ActionBar slot click arms `&"shoot"` correctly.
  3. `test_squad_control_overlay.gd::test_the_real_production_wiring_enters_step_out_on_a_covered_
     enemy` — the full real `SquadControlOverlay`/`TacticsController`/`ActionBar`/`CameraRig` wiring
     (`_build_ui`'s own construction, not a bare `TacticsController.new()`), driven by a real
     action-bar click THEN a real raycast-driven board click, end to end.
  - **Every layer of the reported click sequence checks out correctly in isolation and combined.**
    Two live hypotheses left, neither confirmable headlessly: (a) the trigger condition
    (`UnitAI.is_covered_from` + at least one legal `StepOutPlanner` candidate) may simply be too rare
    on REAL `MapGen`-generated maps to ever fire in practice — reading as "never occurs" without being
    a code regression; (b) the supervisor's own repro used a different weapon/geometry/click sequence
    than this fixture reproduces. **Needs either a more specific repro (which map/weapon/exact
    clicks) or a real-map rarity sweep before further guessing is worth the cost** — not chased
    further this cycle, per tb30's "don't loop within a block" instruction. Still open.
- **2026-07-21 (taskblock-30, same-day follow-up): hypothesis (a) disproved, root cause found.** A
  60-seed sweep of real `MapGen` maps driven through full AI-vs-AI bouts (`BoutSetup.build_bout` +
  `BoutRunner`) found ~1850 genuine covered-with-a-legal-candidate encounters across those 60 seeds —
  not rare at all. `MapGen._scatter_cover` never sets `grid.opacity` (only `blockers`), so the
  overwhelming majority of those are also plainly LOS-visible and clickable, not "no LOS at all" edge
  cases. That ruled out (a) and pointed back at the code path itself — same bug class as BR27.05:
  `TacticsController._enter_aim_or_step_out_mode` read `selection.selected_unit` directly. Per
  docs/09's own "queuing mutates nothing," that stays at wherever the shooter started the turn until
  the queue resolves — so a player who moves toward/into cover and THEN arms a shot had cover
  evaluated from the STALE pre-move cell, silently falling through to ordinary aim mode instead of the
  step-out the shooter's real, about-to-be-true position warranted. Every existing test in
  `test_tactics_controller_step_out.gd` armed+clicked from the shooter's own turn-start cell, never
  after a queued move — the exact gap that let this ship unnoticed.
- **Fix:** swapped to `selection.previewed_unit()` — the same source `reachable_cells()` already
  reads for the identical reason.
- **RESOLVED** 2026-07-21 — supervisor confirms: "step-out is occurring." Commit `d42f744`. New
  regression test queues a move from an uncovered cell into the same covered cell every other test in
  the file starts at, then arms+clicks: confirmed it fails without the fix (falls into ordinary aim
  mode) and passes with it. 1862/1862 green.

### BR30.01 — Resolved — owner: `SUPERVISOR`
**Debug-spawned unit renders no visual model**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, live bout review). "Spawn unit does not create a visual
  model, but the inspect shows it, indicating something all the debug options use is the issue."
- **Root cause:** `BattleScene.unit_views` was only ever populated once, in `load_battle()`'s own build
  loop. `BoutInjector.spawn_unit` adds a unit straight into `combat_state.units` — real data, inspect
  panel reads it fine — but nothing ever constructed a `HitVolumeView` for it.
- **Fix:** new `BattleScene.sync_unit_views()` diffs `combat_state.units` against `unit_views` and
  builds the missing view(s), the exact same construction `load_battle()` runs. Both overlays'
  `_on_debug_panel_applied` call it before `refresh_unit_views()`.
- **RESOLVED** 2026-07-21 — supervisor confirms: "Fixed for spawning units."

### BR30.03 — Resolved — owner: `SUPERVISOR`
**Debug-removed unit never visually looks dead**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-21 (tb30 follow-up, same review as BR30.01/BR30.02): "clicking remove on a
  unit is removing it data side, but not visually."
- **Root cause:** `HitVolumeView.is_downed()` (the one check `refresh()` makes to pick the DOWN pose)
  reads `Unit.resolve_matrix() == null`, never `alive` directly — the same thing a REAL kill leaves
  behind (`DamageResolver.eject_matrix_if_needed` nulls the hosting part's own `hosted_matrix`, drops
  it as a loose `Grid.field_items` entry, THEN calls `kill_unit`). `BoutInjector.remove_unit` only ever
  did the `kill_unit` half — `resolve_matrix()` kept finding the still-docked matrix, so the view never
  changed.
- **Fix (first pass):** `remove_unit` now ejects the hosted matrix the same way first (drops it as a
  real field item at the unit's own cell), then kills as before.
- **Renamed to `kill` (2026-07-21, same-day follow-up):** the supervisor's own next request split debug
  removal into two distinct verbs — "Kill is a new feature, that forces matrix ejection the way you
  designed," separate from a generalized `remove_object` ("fully vanishing it," BR30.02's own report
  covers the move/spawn/remove-object round). This fix's own behavior is unchanged, just renamed
  `BoutInjector.kill` — `remove_object` (new) is debug-only cleanup with no matrix ejection at all.
- **RESOLVED** 2026-07-21 — supervisor confirms: "looks fixed." Commit `c930930` (original fix),
  renamed in `6f42a4f`, 1860/1860 green.

### BR31.01 — Resolved — owner: `SUPERVISOR`
**Bottom-right turn controls and tooltip popups fight over clicks**
- **Source:** `SUPERVISOR`
- **Confirmed fixed by the supervisor (2026-07-22).**
- **Reported:** 2026-07-22 (tb31 review), long-standing: "the controls on the bottom right of the
  player view don't block the tooltip popups, making them difficult to click."
- **Symptom (supervisor's words, exact interaction TBC before fixing):** the bottom-right controls
  (`turn_controls_column` — Resolve to Here / End Turn / Reset Turn) and the tooltip popup layer
  (`TooltipController`/`TooltipView`) overlap, and the tooltip's presence makes the controls hard to
  click. Not yet pinned to which layer intercepts which.
- **Candidate mechanism (do not blind-fix — confirm first):** a `mouse_filter`/z-order interaction
  between the tooltip layer and `turn_controls_column`, the same class as Pass A's own
  `TopLeftControls` STOP→IGNORE fix and BR30.05 (debug-panel click bleed-through). Likely the tooltip
  popup sits over the controls with a filter that swallows the click, or the controls' own hover
  raises a tooltip that then covers them. Reproduce and read the real node rects/filters back (docs/10
  standing rule 2) before changing anything.
- **2026-07-22 (tb32 Pass D) — reproduced, root cause is NOT mouse_filter:** a real synthetic click
  (`InputEventMouseButton` pushed through the real `Viewport`, `test_battle_scene_input.gd`, the one
  file that routes input through the actual Control tree rather than `click_cell()`) proves End Turn
  still receives the click even with the tooltip visually positioned directly over it —
  `TooltipView`/its label both already carry `MOUSE_FILTER_IGNORE`. The real bug: nothing ever hides a
  STALE tooltip left over from hovering the 3D board right before the cursor crosses onto a
  turn-control button. `TacticsController`'s own hover tracking (`update_hover()`, which would clear
  it) lives in `_unhandled_input`, which never fires while the cursor sits over a Control with the
  default `MOUSE_FILTER_STOP` (every `Button`) — Godot's GUI input layer consumes the motion event
  first. `QueuePanel`'s tree (`mouse_exited`) and `ApMpPipRow`'s AP/MP containers
  (`mouse_entered`/`mouse_exited`) already needed and got this exact fix for the same reason; the three
  `turn_controls_column` buttons never did. **Fix:** each button's own `mouse_entered` now calls
  `SquadControlOverlay._hide_stale_tooltip()`. Proven both ways in `test_battle_scene_input.gd`: a real
  click reaches End Turn regardless (confirms mouse_filter was never the problem), and a real
  `mouse_entered` on End Turn now hides a tooltip that was previously left stuck open.

### BR32.06 — Resolved — owner: `SUPERVISOR`
**Performance drop when orbiting the camera *and* a unit is selected**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22 (tb32 review). Framerate took a hit specifically when **both** were true:
  camera orbiting **and** a unit selected. Either alone was fine.
- **Resolved (supervisor-confirmed, 2026-07-22):** on re-check the hit is gone — it was incidentally
  knocked out during the BR32.02 cutout/shader troubleshooting (the depth-source rewrite changed the
  per-frame cutout work). Filed for the record; already fixed by the time it was written up. If aiming
  FPS regresses again, it belongs with the standing BR26.02 (low fps while aiming), same path.

### BR27.08 — Resolved — owner: `SUPERVISOR`
**"Resolve to here" has never worked**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 — RESOLVED, supervisor-confirmed [HBPaR2].** Worked through directly by the supervisor
  and confirmed working.
- **Reported:** 2026-07-20 (logged now; long-standing — backburnered since the button's introduction).
  The "Resolve to here" turn-control (resolve queued actions up to a chosen point) has never
  functioned. Logged here now that the ledger exists so it stops being an untracked known-broken.
- **Status:** open, not yet investigated.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** traces clean
  end-to-end now — button (`squad_control_overlay.gd:445-449`) → `QueuePanel._on_resolve_pressed`
  (`queue_panel.gd:104-107`) → `tactics.resolve_to_marker(_marker_index)`
  (`tactics_controller.gd:1006-1041`), which does slice the queue to a checkpoint index and resolve
  through it. Git history shows commit `888a25f` ("Resolve to Here now actually enables") already
  fixed the historical "button never enables" defect, with passing coverage in `test_queue_panel.gd`.
  **This ledger entry looks stale, not live — worth a quick supervisor re-check before spending
  further investigation on it.**
- **2026-07-22 (tb32 Pass D):** re-verified rather than blind-fixed — `resolve_to_marker()` still
  traces clean end-to-end, and `test_tactics_controller_resolve_to.gd::
  test_resolve_to_marker_applies_only_the_prefix_through_the_marker` is a real queue-then-resolve
  test (queues two move legs, resolves to the first marker, asserts the unit's own `.cell` actually
  only advanced one leg) — not a UI-state check that could pass while the real resolve silently
  no-ops. Nothing changed; this looks like it was already fixed by `888a25f` and the ledger simply
  never caught up. Marked pending, not `RESOLVED` outright, per the provenance gate (SUPERVISOR-sourced) —
  needs the supervisor to actually click the button and confirm.
- **2026-07-22 (supervisor correction): still active — the prior "already fixed" call was wrong.**
  `resolve_to_marker()` working correctly when called directly proves the RESOLUTION logic is fine,
  but says nothing about whether a real player can ever get a `_marker_index` set in the first place
  through the actual `QueuePanel` UI — that path was never exercised, in this session or (per
  `test_queue_panel.gd`) apparently ever with a real queue-then-resolve assertion. Re-opening for a
  real investigation of the click-to-select-a-row → `_marker_index` → resolve-button-enabled chain,
  not just the logic `resolve_to_marker()` itself already had coverage for.
- **2026-07-22, later: reproduced live by the supervisor** — "grayed out and unclickable," matching
  the original report exactly.
- **2026-07-22, follow-up investigation — a real, confirmed test-coverage gap found and closed, but
  the reported symptom itself still not reproduced:** every existing test in `test_queue_panel.gd`
  drove the marker via a helper explicitly documented as "the same path a real click does... without
  needing a live viewport" — `tree.get_root().get_child(index).select(...)` followed by manually
  calling `panel._on_item_selected()` directly. That is NOT the same path: it bypasses the `Tree`
  widget's own hit-testing and its `item_selected` signal entirely. **Nothing, ever, had verified that
  a real click on a real row in the real running game actually fires that signal at all** — exactly
  the class of gap that let BR27.06/BR30.02 hide before (a test that re-derives the behavior instead
  of reading the real thing back).
  - First built the naive version of this test against `test_queue_panel.gd`'s own bare fixture
    (`Tree.new()` with no size, added directly with no parent container) — it FAILED. Looked like a
    smoking gun, but turned out to be a fixture artifact, not the real bug: a bare `Tree` with no
    `custom_minimum_size` lays out at a tiny size, and `get_item_area_rect()` reported a row extending
    below the Tree's own visible rect — a click there falls outside `Control.has_point()`'s test and
    never reaches the Tree at all, regardless of any real production bug. Confirmed via a throwaway
    diagnostic (not committed): giving the same bare Tree the real production `custom_minimum_size =
    Vector2(320, 100)` (`squad_control_overlay.gd:397`) made the identical click resolve correctly.
  - Rebuilt the test against the FULL real `BattleScene`/`SquadControlOverlay` construction instead —
    real Tree sizing, real container hierarchy, a real `InputEventMouseButton` pushed through the real
    `Viewport` at the row's own real, laid-out screen rect (`test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_row_enables_resolve_to_here`). **This passes** — a real click on the
    first row of a freshly-queued single move correctly fires `item_selected` and enables the button.
    Also tried clicking the SECOND row of a 2-entry queue (a throwaway diagnostic, not committed,
    since "resolve to here" is presumably most useful mid-queue, not on the first entry) — also
    correctly selects/enables.
  - **So the click-to-enable mechanism itself checks out in every configuration tried so far, and the
    resolve-when-clicked logic already checked out in tb32 Pass D. Both halves work; the reported
    symptom still hasn't been reproduced by CC.** New regression coverage added either way (a real
    gap closes regardless of whether it's THIS bug): `test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_row_enables_resolve_to_here` (real click, full production wiring) and
    `test_queue_panel.gd::test_a_real_click_on_a_queue_row_enables_resolve_to_here` (same real-click
    proof against the bare fixture, given its own proper size this time — documents the fixture
    sizing gotcha inline so it isn't rediscovered blind next time).
  - **Not chased further blind — needs a few specific details to build a matching failing fixture:**
    (a) which overlay — ordinary `SquadControlOverlay`, or `SingleUnitOverlay`? (b) how many actions
    were queued, and which row (first / a later one) was clicked? (c) fresh turn, or after cycling
    through End Turn/Reset Turn at least once first? (d) does the ROW itself visibly highlight/select
    when clicked (proving the click reaches the Tree) while the button alone stays gray — or does
    NOTHING happen at all, row included? That last one matters most: if the row selects but the button
    doesn't, the bug is almost certainly cosmetic/redraw-timing in `_update_resolve_button()`'s effect
    on the real `Button` node — something no headless test can see (the FRAGCOORD/BR32.02 class of
    bug). If the row itself never highlights, the click isn't reaching the Tree at all in the live
    game, which every test above says shouldn't be possible — meaning something about the live render/
    input path differs from headless in a way not yet identified.
- **2026-07-22, supervisor's answers — every remaining code-level hypothesis ruled out:** (1) both
  `SquadControlOverlay` and `SingleUnitOverlay` show the identical symptom. (2) 1, 2, or 3 actions
  queued, moves interspersed with other action types or not — no difference. (3) fresh turn AND after
  cycling End Turn/Reset Turn — both. (4) **"I don't see any color, or opacity change" — nothing
  happens at all, including the row.** ("Grayed out" was also corrected to "alpha'd out" — the
  button's own look, not necessarily relevant to the row question, but the row-highlight answer is the
  load-bearing one.) This rules out queue length, action type, overlay variant, and turn-state as
  variables, and confirms it's the FIRST half (click never reaches Tree selection) rather than the
  second (selection works, only the button's own redraw is stuck) — narrowing but not yet solving it.
  - Tried two more hypotheses this round, both also ruled out by direct test:
    1. **A real mouse hover immediately before the click** (what an actual player does — move onto the
       row, which triggers `_on_tree_gui_input`'s own tooltip-on-hover, THEN click) rather than a cold
       click with no preceding motion event. Building this properly surfaced a real headless-testing
       limitation, not a game bug: `Viewport.get_mouse_position()` — which `_on_tree_gui_input` itself
       reads to position the tooltip (`tooltip_view.show_data(data, tree.get_viewport().
       get_mouse_position())`) — does **not** update from a synthetic `push_input()`-delivered
       `InputEventMouseMotion` the way a real OS cursor would; it read back `(0, 0)` regardless of the
       motion event's own `.position`. Worked around it by calling `tooltip_view.show_data()` directly
       with the row's real screen position instead, forcing the tooltip genuinely visible at (as close
       as achievable to) the real click point, THEN performing the real click. Still enables the
       button correctly — the (already `MOUSE_FILTER_IGNORE`) tooltip doesn't block the click, matching
       BR31.01's own finding for the turn-control buttons.
    2. Confirmed `HulkTheme` has **no override at all** for a `Tree` row's selection style
       (`selected`/`selected_focus`), nor for `Button`'s `disabled` state — both rely entirely on
       Godot's own default theme. Not a confirmed cause (the default selection highlight is normally a
       distinctly-colored fill, not something that should blend into this theme), but flagged as a
       secondary, unverified possibility: if the default highlight ever reads as visually identical to
       unselected in this specific dark theme, that alone could produce "I see no color change" even if
       the click IS registering underneath. Can't be ruled in or out without eyes on the real render.
  - **Genuinely exhausted what headless GUT can check here.** Every code-level variable tried
    (queue/overlay/turn-state/tooltip-overlap/theme-override-absence) either doesn't reproduce it or
    can't be tested without a real window. This now reads like the same class of bug as BR32.02's own
    shader saga — something only visible in a real, rendered, real-input build.
- **2026-07-22, decision: remove and rebuild rather than keep chasing an unreproducible root cause.**
  The `Tree`+marker+global-button mechanism was never conclusively root-caused despite an extensive
  investigation across several taskblocks, and the supervisor's own repeated live reproduction ruled
  out every code-level variable this session could construct — the strongest remaining signal was
  simply that nothing else in this codebase drives something this important through a `Tree`'s own
  click/selection signal, and every plain `Button`-based control in the same general screen region
  (End Turn, Reset Turn, action bar boxes) has never shown this class of problem. Rather than keep
  guessing at a live-only cause with no further lead, removed the whole `Tree`/marker mechanism and
  rebuilt the same capability on primitives with no such history: each queued action is now its own
  row with its own real "Resolve" button (`QueuePanel._entry_row()`), wired directly to
  `tactics.resolve_to_marker(index)` — no marker state, no `Tree`, no separate global button. Follows
  the same "clear every child, rebuild fresh from an array" convention
  `GenerateBoutOverlay._rebuild_team()`/`_entry_row()` already established, rather than inventing a new
  shape. Full design/rationale in `docs/SUPERSEDED.md`.
  - Verified with a real synthetic click (matching this session's own established rigor) against the
    FULL real `BattleScene`/`SquadControlOverlay` construction — `test_battle_scene_input.gd::
    test_a_real_click_on_a_queue_rows_resolve_button_resolves_through_it` — and against a bare
    `QueuePanel` fixture — `test_queue_panel.gd`'s own suite, five tests covering empty-queue/N-rows/
    real-click-resolves-the-right-prefix/refresh-rebuilds-with-fresh-indices.
  - **Caught a real, separate layout bug while building this**, exactly the kind of thing only a real
    click test surfaces: the row's own expanding "what" label had no width bound inside its
    `ScrollContainer` (nothing forced a maximum, since `SIZE_EXPAND_FILL` is only well-defined once
    something bounds the available width), so the whole row — button included — landed hundreds of
    pixels past the right edge of a 1920-wide viewport. Fixed by disabling the `ScrollContainer`'s own
    horizontal scrolling, which makes it clamp its child to its own real width instead.
  - **A second, unrelated gotcha found and fixed in the test fixture itself, not the game:** the
    default headless GUT test viewport is tiny (64×64) — a row built wide enough to hold real text
    lands well outside that by construction, and a real click there is legitimately outside the
    viewport's own bounds, not a bug. Fixed by resizing the test viewport to `1920×1080`, matching the
    existing convention `test_tooltip_view.gd` already established for the identical reason.
  - **Not fixed in place — this is a replacement, not a patch**, precisely because the original bug's
    root cause was never conclusively identified. Marked `RESOLVED-PENDING-CONFIRMATION`, not plain
    `RESOLVED`, per the provenance gate — this still needs the supervisor's own live click to actually
    close it, since headless tests said the OLD mechanism should have worked too.
- **2026-07-22, supervisor review of the rebuild — two refinements, same session:**
  1. **"Resolving to an earlier point should keep the later queued items in the queue."** The prior
     behavior (inherited unchanged from the original `Tree`-based mechanism, itself dating to
     taskblock06/07) discarded EVERYTHING queued past the marker, not just the resolved prefix —
     `resolve_to_marker()`'s own `selection.reset_turn()` call erased the whole remaining queue.
     Replaced with new `SelectionController.keep_queue_suffix(from_index)`, which drops only the
     resolved prefix; the surviving suffix replays unmodified against the just-updated real state —
     safe since every `CombatAction` already re-validates itself against whatever `state` it's handed
     at apply time, never a captured reference (docs/09). A real design reversal, not a bug fix —
     logged in `docs/SUPERSEDED.md`.
  2. **"The coord info can be an on hover event for the MoveAction term... long paths make the readout
     stretch across the display."** New `CombatAction.short_describe()` (defaults to `describe()`
     unchanged for every action type) — `MoveAction` overrides it to drop only the unbounded `path=...`
     term (`"MoveAction(unit=%d)"`, matching every sibling action's own `ClassName(unit=%d, ...)` style
     — supervisor's own follow-up: "I'm okay with it saying MoveAction, it's just a stream of coords
     that look messy," so only the coordinate stream itself was cut, not the class-name format). The
     full `describe()` still surfaces as an extra "Detail" tooltip row whenever it actually differs
     (`TooltipBuilder.for_queue_entry()`) — the coordinate detail is still reachable, just on hover, not
     stretching every row by construction.
- **2026-07-22, supervisor report: "Hovering anywhere in the combat readout gives me the details of
  things behind it."** A real, confirmed bug in the rebuild, same class as the already-fixed action-bar
  case (`test_a_click_on_an_action_bar_box_never_reaches_the_board_underneath`) — a queue row's own
  `MOUSE_FILTER_PASS` correctly fired its own `mouse_entered`/`mouse_exited` (its own tooltip was never
  the problem), but PASS never marks a motion event handled, so it ALSO reached `TacticsController.
  _unhandled_input`'s `update_hover()` — a pure 3D ray-cast against the board at that screen position
  with no awareness of what UI is drawn there — showing whatever unit/tile sat behind the deliberately
  translucent readout panel instead of just the row's own tooltip. Confirmed live via a direct
  `mouse_moved` signal check (fires with PASS, silent with STOP) before touching anything. Fixed the
  same way the action bar was: `QueuePanel._entry_row()`'s own row is now `MOUSE_FILTER_STOP`, not
  PASS — still gets its own `mouse_entered`/`mouse_exited` (confirmed), never lets the same motion reach
  the board. `test_battle_scene_input.gd`'s own structural test (every non-interactive Control must not
  default to STOP) widened to also recognize a real `mouse_entered` connection as genuine interactivity,
  the same way it already recognized a real `gui_input` connection — a Control deliberately wired for
  hover is exactly as intentional as one wired for clicks. **Not fixed here, flagged as a related, not-
  yet-reported instance of the identical bug:** `ApMpPipRow`'s own AP/MP pip containers use the same
  `PASS` + `mouse_entered`/`mouse_exited` shape with no `gui_input` — likely has the same latent leak,
  just not yet reported, possibly because that row rarely sits over visible board content in practice.
### BR30.07 / BR30.08 — Resolved — owner: `CC`
**Pass D audit: `selected_unit` staleness, same class as BR27.05/BR27.06**
- **Source:** `CC`
- **Found:** 2026-07-21, taskblock-30 Pass D (a supervisor-authored audit task): "BR27.05 and BR27.06
  were the same bug in two places: view code read `selection.selected_unit` (raw, turn-start state)
  during the TACTICS phase, where — per docs/09's 'queuing mutates nothing' — `.cell`/`.ap` don't
  reflect queued-but-unresolved actions. ... Two instances days apart means this is a pattern, not two
  isolated bugs. Audit the rest." Every suspect read from the addendum's own list was checked (state vs
  identity), and none blind-fixed — each confirmed with a failing-then-passing test first.
- **BR30.07 — `TacticsController._confirm_step_out()` computed the outbound path from the stale
  cell:** `Pathfinder.astar(shooter.cell, firing_cell)` used `selection.selected_unit.cell` directly.
  `MoveAction.is_legal()` requires `path[0] == actual.cell` against wherever the unit's real
  (previewed) position is by validation time — so a move queued before triggering step-out silently
  failed `enqueue()` and fell through to `cancel_step_out()`, with no visible step-out at all. Every
  existing test armed+clicked from the shooter's own turn-start cell — the exact gap that also hid
  BR27.06 itself, in a spot BR27.06's own fix never reached (a different function). **State read,
  confirmed.** Fix: path from the queue's own preview instead, matching
  `_append_step_out_return_leg()`'s already-correct sibling pattern. Verified failing without the fix
  (silent cancel; queue only ever got 1 of the expected 2 entries) and passing with it.
  **RESOLVED** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit `8457ff0`, 1864/1864 green.
- **BR30.08 — `TooltipController.refresh()` showed LOS from the stale cell:** passed the raw
  `selected_unit` into `TileInspection.inspect()`, whose `visible_from_selected` field runs a real LOS
  check from `selected.cell` directly. A move queued toward a cell with different sightlines left the
  tooltip stuck showing visibility from the turn-start position. **State read, confirmed.** Fix:
  `previewed_unit()` instead. Verified failing without the fix and passing with it (an opaque cell
  blocks LOS from the start cell but not the queued destination). **RESOLVED**
  [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit `8457ff0`, 1864/1864 green.
- **Checked, not a bug:** `TacticsController.step_out_exposure()`/`_refresh_overlay()`'s
  `Overwatch.would_trigger_at()`/`all_threatened_cells()` calls also read `selected_unit` directly, but
  tracing `would_trigger_at()`'s own general-case branch shows it always re-resolves the mover by `id`
  and explicitly relocates the CLONE to the candidate cell before checking arc/range/LOS, regardless of
  what the passed reference's own `.cell` says — the stale reference only changes which internal branch
  runs, never the final answer. A direct empirical probe (temporary diagnostic, not committed) confirmed
  no output difference. No entry filed.
- **Confirmed correct as-is, no change needed:** `MoveHooks.new(selected_unit.cell)` (both call sites)
  — these run during REAL `resolve_until()`, where `selected_unit.cell` genuinely IS the live starting
  cell, not a preview concern; `confirm_shot()`'s own `shooter` reference and `_append_step_out_
  return_leg()` (both already use raw `selected_unit` ONLY for `.id`/identity, deferring all real
  geometry to previewed state — the correct split); `ap_mp_pip_row.gd` (already reads `previewed_unit()`
  — pre-existing correct pattern); `weapon_panel.gd` (purely structural shell/part reads — hp, wounds,
  manipulators — no position or queue dependency).
### BR30.11 — Resolved — owner: `SUPERVISOR`
**Burst: shown as affordable without enough AP; step-out silently drops the shot**
- **Source:** `SUPERVISOR`
- **2026-07-23 (supervisor confirmation — Resolved, both halves).** Confirmed fixed. *Process note
  from the supervisor: bundling two separately-observed symptoms into a single entry because they
  shared a root is "not really how a bug should be constructed" — the shared root belongs in the
  investigation notes, not in the entry's identity. File one entry per observed symptom in future,
  and cross-link.*
- **Reported:** 2026-07-21, two symptoms the supervisor flagged separately, turned out to be one root
  cause: (1) "actions selectable when not enough AP available still," and (2) "step out seems to be
  working with shoot, but not with burst."
- **Root cause:** `ActionBar._can_afford()` (`src/view/action_bar.gd`) compared the unit's AP against
  the providing weapon's plain `provider.ap_cost` for EVERY action id, but `BurstAction` has always
  charged its own, usually-higher `weapon.weapon_def.burst_ap_cost` when authored
  (`BurstAction._ap_cost`, e.g. `data/parts/chaingun.tres`: `ap_cost = 2`, `weapon_def.burst_ap_cost =
  4`). A unit with enough AP for the plain cost but not the real burst cost saw (and could arm) BURST
  as affordable — only to have the actual shot silently rejected at `enqueue()` time
  (`BurstAction.is_legal()` correctly checks the real cost), with no visible error either way.
- **Step-out's own part in this:** proved, not assumed — `_enter_aim_or_step_out_mode`'s entry into
  step-out mode is genuinely action-id-agnostic (a direct test arming `&"burst"` against the same
  covered-corridor fixture `test_tactics_controller_step_out.gd` already used for `&"shoot"` entered
  step-out mode correctly, no fix needed there). What actually "doesn't work" with burst: a shooter
  steps out for free (the outbound leg never costs AP), then the SAME `confirm_shot()` -> `enqueue()`
  gate silently drops the real attack for the reason above — the unit holds the stepped-out position
  with nothing ever firing, reading as "step out doesn't work" when the move itself queued fine.
- **Fix:** `ActionCatalog.ap_cost_for(action_id, provider)` (new) — the one seam: `&"burst"` returns
  `weapon_def.burst_ap_cost` when authored, else falls back to `provider.ap_cost`, same as every other
  action. `ActionBar._can_afford()` and `BurstAction._ap_cost()` (now a one-line delegate) both read
  this instead of duplicating the branch — the "two parallel systems" trap this project's own
  convention warns against.
- **Verified:** `test_action_bar.gd::test_burst_dims_using_its_own_higher_ap_cost_not_the_weapons_
  plain_one` (fails without the fix, passes with it — confirmed via `git stash`) and
  `test_tactics_controller_step_out.gd::test_firing_burst_after_step_out_is_silently_rejected_with_
  insufficient_real_ap` (documents the exact silent-rejection mechanism: queue stays at 1 action, the
  free out-leg, burst never gets added). 1868/1869 green (the one failure is the unrelated,
  already-flagged `test_full_mission.gd`, BR30.10 above).
- **RESOLVED-PENDING-CONFIRMATION** [CC a90c45b3-a806-42f8-b1d3-ea8bdc511a9a] — commit pending.

---
### BR31.02 — Resolved — owner: `SUPERVISOR`
**Wall/void generation cascaded through solid rock**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor confirmation — Resolved).** Confirmed fixed. *Process note: the write-up
  was "a very complicated description for a simple bug." Investigation depth is welcome in the notes;
  the description line should stay plain enough to recognise the bug from.*
- **Backfilled 2026-07-22** (retroactive ledger pass, CLAUDE.md rule 8 applied historically) —
  reported and fixed live during taskblock-31 itself; `docs/CHANGELOG.md` and
  `taskblock_done/Report-Taskblock31.md` both recorded it at the time, but it never got a `BR` id or
  an entry in this ledger. Filed now so a resolved bug's closure marker exists here too, per this
  file's own stated job.
- **Reported:** 2026-07-21, live play testing of tb31 Pass C's new wall/void model: "walls are
  generating where voids should [be]... there should be a single layer of walls."
- **Root cause:** `MapGen._finalize_walls_and_void()` classified AND mutated each `WALL` cell in the
  same scan pass — converting an exposed cell to `OPEN` made it read as a non-WALL neighbor for
  whatever `WALL` cell got scanned next, so exposure cascaded outward from every real opening through
  however much solid rock the scan order happened to reach. A real ASCII dump (seed 2, 40×30 —
  `BattleScene`'s own defaults) confirmed it: walls many tiles thick, effectively zero `VOID` anywhere
  on the map.
- **Fix:** split into two passes — classify every `WALL` cell's exposure against the grid's own
  untouched layout first, then apply every mutation in a second pass. Re-dumped the same seed: clean
  single-tile wall rings with real void space.
- **Verified:** re-confirmed via the same real ASCII dump technique, not just re-reading the code.
  Commit `9909d73`.
### BR31.03 — Obsolete — owner: `SUPERVISOR`
**Wall fading never visibly occluded anything**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 — closed OBSOLETE, not Resolved [HBPaR2].** This entry can no longer be confirmed,
  because the code it describes no longer exists: its fix was `BoardView._set_wall_alpha()` /
  `WALL_FADE_ALPHA`, the per-object alpha-blend fade, and **tb32 Pass A retired that mechanism
  entirely** in favour of the dither cutout shader (`docs/SUPERSEDED.md`; both symbols now survive
  only in comments describing what replaced them). Marking it `Resolved` would assert a verification
  that never happened. The question it asked — "does wall occlusion actually reveal anything?" — is
  now BR32.02's, with the live faults tracked by BR32.01/BR32.03.
- **Backfilled 2026-07-22** (retroactive ledger pass) — same gap as BR31.02 above: reported and fixed
  live during taskblock-31, never given a `BR` id or an entry here until now.
- **Reported:** 2026-07-21, live play testing tb31 Pass C's wall-fade legibility feature: "I can't see
  wall fading doing anything" — then again, after a first fix attempt, "the wall fading is still not
  occurring, is it drawing between the camera and the orbited point, or is it something else?"
- **First root cause, fixed:** the occlusion check was world-space — "is this wall within 1 unit of the
  straight 3D line from camera to the focal unit." The tactical camera sits well above/back from the
  board, so that line spends almost its whole length far above wall height; the check essentially
  never fired for any wall more than a cell or two from the unit, the exact case that matters. Rewrote
  `WallLegibility.occludes()` → `occludes_on_screen()`: project both the wall and the focal unit
  through the real camera (`Camera3D.unproject_position()`), compare 2D screen distance, require the
  wall nearer in depth — the question a player would actually answer by eye, independent of camera
  angle. Commit `662e8d2`.
- **Second root cause, found when the supervisor reported it still wasn't working:** traced the whole
  pipeline end to end through the real production path (real `BattleScene`/`SquadControlOverlay`, real
  click-to-select, real `CameraRig` framing) and confirmed every intermediate value was already correct
  — `focal_unit` wiring, camera ownership, `unproject_position()`/depth math all checked out. The one
  link never directly verified: whether `GeometryInstance3D.transparency` alone renders a visible
  effect against an otherwise-opaque, `SHADING_MODE_PER_PIXEL` (lit) material — it doesn't. Switched to
  real alpha blending (`BaseMaterial3D.TRANSPARENCY_ALPHA` + `albedo_color.a`), the same mechanism
  `show_unit_ghost()` already proves renders correctly in this project, just kept lit (docs/10: real
  geometry stays lit). New `BoardView._set_wall_alpha()`, `WALL_FADE_ALPHA := 0.25`. Commit `dda90d4`.
- **Verified:** confirmed working in player view after the second fix. Moot in practice either way —
  this whole alpha-blend mechanism is itself superseded by tb32 A's per-fragment discard shader
  (`docs/SUPERSEDED.md`).
### BR32.02 — Resolved — owner: `SUPERVISOR`
**Wall cutout never visibly appears near real units**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor confirmation — Resolved as written, but read the next line).** The cutout
  does now appear near real units; the bug as described is genuinely fixed. **However the underlying
  cause is not gone — it continues as BR32.03.** What was fixed here was the depth-source half; the
  feed-timing half (when `update_wall_cutout()` reads, and from what) is the same root and is still
  live. Closing this entry is not evidence the cutout system is healthy — BR32.01 and BR32.03 are.
- **Reported:** 2026-07-22 (same live-bout review as BR32.01). "I rotated the camera around the
  units, they were still in their original spawn locations, next to walls. No culling observed at
  all."
- **First theory, tried and EMPIRICALLY DISPROVEN:** hypothesized (from Godot's own documentation —
  "FRAGCOORD... use[s] the same coordinate system" as `gl_FragCoord`, bottom-left origin) that
  `FRAGCOORD` and `Camera3D.unproject_position()` (top-left origin) disagreed on Y and needed a flip.
  Added the flip; the supervisor tested live and reported the cutout became visible but **detached
  from any unit, drifting/spiraling independently as the camera orbited** — worse, not fixed. A real
  orbiting-camera test proved the GDScript-side feed (position/depth/radius) tracks the unit
  correctly and stably at every angle, ruling that layer out. Two live, hardcoded-position diagnostic
  builds (a fixed hole at viewport center, then at a corner) settled it empirically: **`FRAGCOORD` is
  actually top-left-origin, Y-down — the SAME convention `unproject_position()` already uses.** No
  flip was ever needed; documentation for a different rendering context/shader type doesn't
  necessarily transfer, and this class of bug is entirely invisible to headless testing (dummy
  rendering never executes a fragment shader) — only live, real rendering could have caught it, and
  did, twice. **The flip has been reverted** (`update_wall_cutout()` feeds `unproject_position()`'s
  own output unchanged).
- **Second theory, tried and confirmed via a sequence of live diagnostic builds (all uncommitted,
  shader-file-only, removed once each landed):**
  1. Unconditional discard whenever `unit_count > 0` (ignoring all per-fragment math) made ALL walls
     vanish, not just ones near units — expected, since every wall shares ONE material/uniform set;
     confirmed the uniform data genuinely reaches the shader (not a wiring bug).
  2. Disabling the depth-compare entirely produced a correctly-positioned, correctly-sized porthole
     at every unit — confirmed the distance/radius/dither math is correct, and narrowed the bug to
     depth-compare specifically.
  3. Flipping the depth-compare direction (`<=` instead of `>=`) was wrong in BOTH directions — ruled
     out a simple sign flip; the depth VALUE itself (`frag_depth = length(VERTEX)`) had to be wrong,
     not just its comparison.
  4. `VERTEX` is documented to already arrive in view space by the time `fragment()` reads it — that
     documentation already failed once this investigation (`FRAGCOORD`'s own origin), and evidently
     doesn't hold here either. Replaced with true view-space depth reconstructed directly from the
     hardware depth buffer (`FRAGCOORD.z` + `INV_PROJECTION_MATRIX`, Godot's own standard recipe) —
     confirmed live: culling from the correct side (wall genuinely between camera and unit) now works
     as expected.
- **Fix:** `wall_cutout.gdshader`'s `fragment()` now computes `frag_depth` via the depth-buffer
  reconstruction above instead of `length(VERTEX)`. No GDScript changes needed — this was entirely a
  shader-side depth source bug.
- **Deferred, not a regression from this fix — logged, not chased further per instruction:** with the
  camera and unit on the SAME side of a wall (nothing should occlude at all), the cutout still fires
  and over-cuts neighboring wall segments, confirmed live via screenshot. See
  `taskblock_done/Report-Taskblock32.md` for the fuller writeup and a candidate cause — likely
  inherent to this shader's own 2D screen-space heuristic (nearer-than-unit + within-screen-radius),
  not a new bug introduced by this fix.
- **Both halves of this investigation (BR32.02's flip revert and this fix) were only possible because
  the supervisor tested live and reported back precisely** — no headless test can exercise a fragment
  shader at all (dummy/headless rendering never executes one), so every claim here was confirmed
  against a real, rendered build, not GUT.

## Legacy (predates the `BR<taskblock>.<seq>` ID convention; IDs assigned retroactively)
*(Kept in their own trailing block rather than resorted into the main ascending sequence above —
same relative order this ledger has always kept them in, oldest work first. All `Resolved`.)*

### BR26.03 — Resolved — owner: `SUPERVISOR`
**Muzzle origin inside the shooter's own armor**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the muzzle originates at the shoulder socket's center
  ('the literal shoulder, not *from* the shoulder'), so the ray starts inside the shooter's own
  geometry and can hit its own armor."
- **First attempt (taskblock-26 Pass A2):** `UnitGeometry.muzzle_point` returned the weapon's own box
  CENTER, not its forward emission point. **Reported still present.**
- **Second attempt (taskblock-27):** re-diagnosed — the first fix touched a function no real firing
  action actually consumed for its horizontal origin; every real attack built the shot plane from the
  shooter's own bare cell center instead. All five action files now anchor the shot plane on
  `Vector2(muzzle.x, muzzle.z) / UnitGeometry.CELL_SIZE`, the shouldered muzzle position, computed
  before the plane is built.
- **RESOLVED** 2026-07-20 — supervisor confirms shots now consistently originate from outside the
  unit's own armor. taskblock-27 Pass A1 (fixing the chaingun-backward report, above) also removed a
  remaining anchor mismatch between `origin` and `direction` that had been obscuring a clean read on
  this one.

### BR26.04 — Resolved — owner: `SUPERVISOR`
**Extract-tile marker / facing-indicator z-fight**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26 (bout review), "same class as tb23's floor/indicator z-fighting."
- **First two attempts (taskblock-26 Pass A3, twice):** bumped `FACING_WEDGE_Y` in isolation each
  time. Both **reported still present.**
- **Third attempt (taskblock-27 Pass C2):** stopped bumping one marker in isolation and enumerated
  the whole ground-overlay height ladder instead. Found a real, previously unreported co-planar pair
  no prior test had ever checked: `TEAM_MARKER_Y` (0.01) was IDENTICAL to `EXTRACTION_TILE_HEIGHT`
  (0.010) — every unit standing on its own extraction tile z-fought, independent of the facing wedge
  entirely. Re-spaced all four named overlays as one ordered ladder with real clearance: extraction
  tile (0.010, unchanged) → team marker (0.06) → overwatch arc (0.09) → facing wedge (0.17).
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass C2.

### BR27.10 — Resolved — owner: `SUPERVISOR`
**Spectator combat log word-wraps**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27 D1a: the spectator's own log label wraps lines; the player view's log
  already doesn't.
- **Fix:** `log_label.autowrap_mode = TextServer.AUTOWRAP_OFF`, the same setting the player-view log
  already carried — a direct port, not a new mechanism.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D1a.

### BR27.11 — Resolved — owner: `SUPERVISOR`
**Inspect-on-hover missing in spectator view**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27 D1c (tb17-era note): inspect-on-hover should be on the shared control
  layer so both spectator and player view have it. Spectator view had none at all.
- **Fix:** `SpectatorOverlay._unhandled_input()` now routes `InputEventMouseMotion` to a new
  `_update_hover()`, reusing the same `UnitPicker.hit()` ray-pick the click handler already calls —
  whichever unit the cursor is actually over highlights (no "selected unit" gate; spectator view has
  no selection concept), mirroring `SquadControlOverlay._on_highlight_changed()`'s own
  clear-every-other-view behavior.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D1c.

### BR27.12 — Resolved — owner: `SUPERVISOR`
**Wall tiles inspectable → opens the tile inspector**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-27 D5: clicking a wall tile opens the tile inspector.
- **Fix:** `SpectatorOverlay`'s tile-click path now guards on `TerrainType.WALL` before ever calling
  `open_tile()` — a wall click is a real no-op, the same posture a miss off the board already had.
- **RESOLVED** 2026-07-20 — confirmed by the supervisor. taskblock-27 Pass D5. (The garbage-viewport
  symptom this report also showed was a distinct, deeper bug — see the next entry, found and closed
  by CC in the same pass.)

### BR27.13 — Resolved — owner: `CC`
**InspectPanel's null-root branch leaked stale isolate-viewport state ("garbage inspector")**
- **Source:** `CC`
- **Found:** while root-causing the wall-tile report above. `Grid.blockers` returns null identically
  for a wall cell and bare floor, so the tile lookup itself was never the bug. The real defect:
  `InspectPanel.open()`'s null-root branch (reached whenever `unit.shell.root == null`, which
  includes "no unit/object at this tile") never reset the preview viewport's own
  `own_world_3d`/isolate-focus state — so a "nothing to show" case could render an uncontrolled slice
  of the live board, carried over from whatever a PRIOR inspect had left the viewport in.
- **Fix:** the null-root branch now resets `_preview_viewport.own_world_3d = true` and calls
  `show_assembly(null, ...)`, so a "nothing to show" case can never leak the live-board state
  regardless of which caller reaches it.
- **RESOLVED** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — taskblock-27 Pass D5, proven both ways
  (fails without the fix, passes with it) by `test_inspect_panel.gd`'s new
  null-root-resets-viewport-state test. CC-sourced: found, fixed, and tested entirely by CC in one
  pass, no supervisor confirmation gate applies.

### BR11.01 — Resolved — owner: `SUPERVISOR`
**Resource Editor — four layout bugs (stale-report source)**
- **Source:** `SUPERVISOR`
- **Reported:** recurring through 2026-07-20 (arrived repeatedly as a `## User Request` to launch
  `run_resource_editor.sh` and screenshot the bugs). Era: taskblock 11 was the active block when
  first reported.
- **Symptoms:** (1) nothing resized/expanded on window resize; (2) no visible column-resize grab
  handles in the Tree header; (3) header bar changed height/width while interacting; (4) 3D preview
  z-fought the ground disc (needed zoom-in + upward offset).
- **RESOLVED** 2026-07-18, ~101 commits before the last stale re-report, in three commits:
  - `713f411` — layout never resized, columns wouldn't drag, preview mis-framed
  - `1bff29b` — garbage edits, silent save loss, header jitter
  - `944d019` — preview: drop the dummy-matrix carrier, add `show_assembly`
- **Verified** both in code and by direct supervisor observation of the corrected tool — so this
  `SUPERVISOR`-sourced bug is legitimately `RESOLVED` (the gate was satisfied: the supervisor
  confirmed it).
- **Why it kept recurring:** the fixes landed as plain bugfix commits *outside* the "Taskblock N Pass
  X" cadence, so the usual "update CHANGELOG on landing" never fired. With no closure marker anywhere
  and the tb11 spec still on disk in `taskblock_done/` (gitignored-but-not-deleted, per repo
  convention), the taskblock-generating instance treated the living docs as authority, found nothing,
  and re-derived "go verify the Resource Editor" as open. **This ledger is the fix for that class.**

### BR22.01 — Resolved — owner: `SUPERVISOR`
**Waist-line of impacts — the shot-plane Z-discard**
- **Source:** `SUPERVISOR`
- **Reported:** through mid-2026-07 review passes ("a line of impacts across the waist"; "only seeing
  ~20% of shots"; "no ricochets").
- **Symptom:** projection collapsed `Vector3 → Vector2(x, z)`, dropping the height axis — so vertical
  scatter collapsed to a horizontal band and tracers/ricochets pinned to one height.
- **RESOLVED** in **taskblock 23** (true-3D shot resolution): projection retains height, the dartboard
  scatters in 3D, `resolve_ray` accepts vertical shots, tracers draw the real 3D path. Tagged in
  `docs/CHANGELOG.md`.

### BR00.01 — Resolved — owner: `CC`
**`los.gd` `range`-shadow (v1)**
- **Source:** `CC`
- **Symptom:** a param named `range` shadowed the builtin, failing at load/call time.
- **RESOLVED** in the v1 foundation work (noted historically in `docs/SUPERSEDED.md`). `gdlint` now
  catches this class faster than the engine does (see `docs/TOOLING.md` gotchas).

### BR26.05 — Resolved — owner: `SUPERVISOR`
**Deflect tracers never drawn**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26 (bout review): "the resolver produces DEFLECT outcomes (a review bout
  logged 25), but resolution_player.gd references DEFLECT zero times — the bounced secondary ray is
  computed, logged, never drawn."
- **Fix:** `taskblock-26 Pass A1` (commit `7c07445`) — every DEFLECT-outcome impact event now
  carries its own `deflect_end_x/y/height`, drawn as a second, visually distinct tracer segment.
- **RESOLVED** — confirmed by the supervisor.

### BR26.06 — Resolved — owner: `SUPERVISOR`
**Bout maker AI dropdown missing new playstyles**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26: tb24/tb25 added playstyles (overwatch-capable set, PSYCHOTIC, TURTLE)
  but the bout setup menu's own AI dropdown was a hardcoded, independently-maintained list.
- **Fix:** `taskblock-26 Pass C1` (commit `67c7ca8`) — `GenerateBoutOverlay.PLAYSTYLES` is now a
  direct reference to `UnitAI.PLAYSTYLES`, not a hardcoded copy.
- **RESOLVED** — confirmed by the supervisor.

### BR26.07 — Resolved — owner: `SUPERVISOR`
**Bout menu jumpy add/duplicate, not truly centered**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26: adding/duplicating a roster entry reflows jarringly; the menu reads as
  intended-centered but isn't.
- **Fix:** `taskblock-26 Pass C2` (commit `67c7ca8`) — anchors pinned to 0.5 with
  `GROW_DIRECTION_BOTH` (no baked offset); every row reserves the same `ROW_MIN_HEIGHT`.
- **RESOLVED** — confirmed by the supervisor.

### BR26.08 — Resolved — owner: `SUPERVISOR`
**Inspect header shows only the variant, not unit id/squad**
- **Source:** `SUPERVISOR`
- **Reported:** taskblock-26: the inspect panel showed the bot's variant but not which unit/squad
  this actually was in the current bout — two units built from the same variant read identically.
- **Fix:** `taskblock-26 Pass C3` (commit `67c7ca8`) — the title bar now reads "INSPECT — Unit N
  (Squad M) — <variant>" once a unit is open.
- **RESOLVED** — confirmed by the supervisor.

### BR27.14 — Resolved — owner: `CC`
**Stab's slide-deflect could land back on the shooter's own body**
- **Source:** `CC`
- **Found:** while re-diagnosing A2 above (see that entry) — `DamageResolver._resolve_slide` (stab's
  own DEFLECT_MODE_SLIDE response) re-searches the WHOLE plane from index 0 with a lateral nudge, but
  hardcoded an EMPTY exclude list on that re-search, unlike every other plane lookup in `resolve_shot`.
  A stab that deflects and slides at point-blank range could therefore land back on the shooter's own
  body (which sits at the ray's own near-zero depth), the one lookup `resolve_shot`'s own first-hop
  exclusion never covered.
- **Fix:** `_resolve_slide` now takes `exclude_parts` and passes it through to its own `_find_next`
  call, the same shooter-parts list `resolve_shot` itself was given.
- **RESOLVED** [CC 83fb8082-732a-4a4f-a726-04186087ef69] — proven both ways (fails without the fix,
  passes with it) by
  `test_damage_resolver_deflect_modes.gd::test_slide_deflect_never_lands_back_on_the_shooters_own_excluded_body`.

---

### BR32.01 — Resolved — owner: `SUPERVISOR`
**Stray wall-cutout hole at a cell with no unit**
- **Source:** `SUPERVISOR`  ·  **CC session:** `a90c45b3-a806-42f8-b1d3-ea8bdc511a9a`
- **2026-07-23 (supervisor re-check — REOPENED, and merged in understanding with BR32.03).** Still
  reproduces. The description here is almost certainly the *same phenomenon* BR32.03 describes from
  the other side: a "stray cutout at a cell with no unit" is what a cutout that **carried over from a
  previous bout** looks like once the unit that justified it is gone. Treat BR32.01 and BR32.03 as one
  defect with two observed faces — fix the feed-refresh boundary (bout load, unit spawn, unit removal)
  once and both should fall. Do not fix them as separate bugs.
- **Reported:** 2026-07-22 (live bout, tb32 review). "A stray culling around cell 2,18, with no unit
  to produce that effect... that is the ONLY culling step I see, it's not showing on the units."
- **Root cause, confirmed by reading the code (no live repro available to me — this session has no
  Xvfb/GPU, so I can't run the actual bout myself):** `BoardView.wall_cutout_units` is a live
  reference to `CombatState.units`, fed unfiltered into the wall-cutout shader
  (`BoardView.update_wall_cutout`) every frame. Two ways a unit can leave the board while STAYING in
  that array at its own stale `.cell` forever: (a) **extraction** (`MissionState.extract_unit()` sets
  `alive = false`/`extracted = true` but never clears `.cell`, and nothing in the view layer ever
  read `.extracted` before this fix — the unit's own `HitVolumeView` doesn't even get hidden,
  a separate, more visible latent issue flagged below); (b) the **debug panel's "remove object" verb**
  on a unit (`BoutInjector.remove_object` → `CombatState.kill_unit` — same `alive = false`, cell
  untouched — plus `BattleScene.remove_unit_view()`, which DOES destroy the `HitVolumeView`,
  tracked in `_removed_unit_ids`). Either way, the cutout shader keeps cutting a hole at that unit's
  last position indefinitely, with nothing visibly there to explain it — exactly the reported
  symptom. ("Not showing on the units" is very likely just describing that no *currently on-board*
  unit happens to be behind a wall from the camera's current angle right now — not itself a bug,
  though unconfirmed without seeing the bout.)
- **Fix:** `update_wall_cutout()` now skips any unit with `.extracted == true`. A new
  `BoardView.exclude_unit_from_occlusion(unit_id)` (cleared on every `build()`, so a fresh battle
  never inherits a stale exclusion) is called from `BattleScene.remove_unit_view()` — the same
  `_removed_unit_ids` moment — and checked alongside `.extracted` in the cutout feed. Pass B's own
  `BattleScene._occluding_friendlies()` (same `wall_cutout_units` list, same class of bug for the
  friendly-fade effect) got the matching `.extracted` filter too, since an extracted friendly's own
  `HitVolumeView` stays live (extraction never calls `remove_unit_view`) and would otherwise visibly
  fade as if still standing there.
- **Separate, more visible latent issue flagged, not yet fixed:** nothing in the view layer reads
  `Unit.extracted` at all outside this fix — an extracted unit's own `HitVolumeView` never gets
  hidden or specially posed, so its body may just keep standing there, fully rendered, indefinitely.
  Worth a supervisor look independent of this ticket.
- **Not yet confirmed which of the two mechanisms (a)/(b) actually produced the (2,18) hole** — both
  are now fixed regardless, but knowing which would confirm the diagnosis. Did a unit get extracted
  or debug-removed near that cell?
- **2026-07-22 (supervisor):** if extraction/debug-removal was the cause, it happened on a PRIOR
  bout, not this one — the stray hole was already present on loading into the current bout. See
  **BR32.03** below — a distinct, not-yet-investigated angle (does something carry over across a
  "New Battle" that shouldn't?), since this fix's own `_excluded_from_occlusion` is cleared on every
  `BoardView.build()` and `wall_cutout_units` is reassigned fresh from the new `CombatState.units` on
  load, so neither of the mechanisms fixed here should be ABLE to survive a bout transition as
  currently understood — worth a real look, just not yet.
- **2026-07-23 (tb35 Pass D — the "should be impossible" gap found and fixed)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. The prior note's own "reassigned fresh from the new
  `CombatState.units` on load" premise was checked directly and is **false in the common case**:
  `wall_cutout_units` is set in exactly ONE place in the entire codebase —
  `SquadControlOverlay._on_battle_loaded()`. `SpectatorOverlay` (the DEFAULT overlay every fresh bout
  and every "New Battle" starts in, unless the Generate Bout menu's own "Assume Control" checkbox was
  ticked) has no `battle_loaded` handler at all and never touches it.
  `BattleScene.load_battle()` itself — the one function that runs for every bout, every overlay —
  rebuilds `board_view`'s static geometry (`board_view.build(...)`) but never re-points
  `wall_cutout_units`. So starting or reloading a bout while staying in Spectator mode (the ordinary,
  default path) leaves the feed pointing at whatever it held before: `null`/empty on first launch, or
  the PREVIOUS bout's own now-orphaned `combat_state.units` array on any later one — exactly "a stray
  cutout at a cell with no unit" (this entry) and "carried over from a previous bout" (BR32.03,
  confirmed the same defect). This is also precisely why clicking "Assume Control" (either the bout-
  start checkbox or a mid-bout control-assumption) "snaps the culls into place": either path installs
  a real `SquadControlOverlay` for the first time against the *current* `battle`, which is the ONLY
  code path that ever sets the feed — not a coincidence, the actual mechanism.
  - **Fix:** `board_view.wall_cutout_units = combat_state.units` moved into `BattleScene.
    load_battle()` itself, right after `board_view.build(...)` — set once, canonically, for every
    overlay, every bout. `SquadControlOverlay`'s own now-redundant assignment removed (one source of
    truth, not two agreeing by coincidence).
  - **Verified (headless):** new
    `test_battle_scene.gd::test_load_battle_repoints_the_wall_cutout_feed_even_in_spectator_mode` —
    loads a bout while in `SpectatorOverlay`, confirms the feed points at that bout's own units;
    loads a SECOND bout, confirms the feed re-points to the new state's units and the first bout's
    own (now-stale) array is no longer the feed.
  - Marked Pending, not Resolved — this needs a live look (start a bout, stay in Spectator, confirm no
    stray cutout) before promotion, same as every other `SUPERVISOR`-owned entry this session.
- **RESOLVED** [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — confirmed live by the supervisor (2026-07-23).

### BR32.03 — Resolved — owner: `SUPERVISOR`
**Wall cutout carries over across a bout transition; new units get none**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-22. The supervisor noticed BR32.01's own "stray culling, no unit there"
  symptom immediately on loading into the current bout — if extraction/debug-removal was the actual
  cause (BR32.01's own fix), it would have happened on a PRIOR bout, meaning something about that
  stale state survived a "New Battle" transition into this fresh one.
- **Explicitly not investigated yet, by instruction** — do not look into this until the supervisor's
  own review pass. Filed only so it isn't lost.
- **Why this looks surprising against BR32.01's own fix (not a contradiction, just unexplained):**
  `BoardView.wall_cutout_units` is reassigned fresh from the NEW `CombatState.units` on every
  `_on_battle_loaded()`, and `_excluded_from_occlusion` is cleared on every `BoardView.build()` — on
  paper, neither of BR32.01's two mechanisms should be able to survive a bout transition at all. If
  this reproduces again, that gap between "should be impossible" and "was observed" is the actual
  bug.
- **2026-07-22 (supervisor review — confirmed, promoted Suspected→Active):** reproduces. The cutout
  from the *prior* match persists into a new bout — old culling never cleared, and the new bout's own
  units get no cutout at all (the only hole visible is the stale one). So it's not just a leftover: what
  survives the transition also prevents the fresh feed from taking effect.
- **Key diagnostic — clicking "Assume Control" snaps the culls to their proper location.** So the feed
  isn't permanently broken, it's *stale until an event forces a re-read*: whatever Assume-Control does
  (re-selects/re-projects the live units) is exactly the refresh the bout-load path is missing. Same
  feed-timing family as **BR32.04** (cutout jumps to the resolved cell ahead of the move animation) —
  both are "`update_wall_cutout()` reads/refreshes at the wrong moment." The bout-load path (and unit
  spawn) needs to trigger the same re-feed Assume-Control already does.
- **2026-07-23 (tb35 Pass D — confirmed as the SAME defect as BR32.01, one fix closes both)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. This entry's own diagnostic was exactly right: the
  bout-load path never re-fed `wall_cutout_units` at all unless `SquadControlOverlay` happened to be
  active — see BR32.01's own dated note above for the full mechanism and the fix
  (`BattleScene.load_battle()` now re-points the feed itself, for every overlay). Not a separate bug
  needing its own fix — merged, per this entry's own instruction to treat BR32.01/03 as one defect.
  Marked Pending alongside BR32.01, same reasoning.
- **RESOLVED** [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — confirmed live by the supervisor (2026-07-23).

### BR34.06 — Resolved — owner: `SUPERVISOR`
**AI passes its turn, in bout matches only — BLOCKER**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-23 (post-tb34 check). Every AI unit passes its turn in bout matches. The
  qualifier matters: **bouts specifically**, which is the mode used for essentially all live
  verification.
- **This blocks confirmation of at least BR32.10 and BR27.07**, and makes bouts near-useless as a
  testing surface — which is why it should be treated as the highest-priority open entry rather than
  one bug among several.
- **Strong prior hypothesis — this is probably not new, and probably not a bout-setup bug.** CC's own
  tb33 follow-up investigation reported exactly this symptom while re-measuring the BR30.10 wall-hit
  ratio: *"zero impacts in 400 turns… every unit holds every turn, the whole mission long."* At the
  time it was attributed to one enemy spawning in a geometric nook with no clean line anywhere, and
  written off as a bad seed. The same symptom appearing across bout matches generally says it is
  **systemic, not seed-specific** — and the obvious candidate is tb33's own LOF work: either
  `has_clear_line_of_fire` returns false far more often than it should (walls are dense and
  full-height post-tb31, so a strict first-hit-must-be-the-target test may almost never pass), or the
  Pass B approach fallback isn't engaging when it should, leaving the unit with nothing to do and
  holding.
- **Where to start:** log the AI's own decision per unit per turn (which branch it took, and why LOF
  said no) — the intent/outcome logging idea in `docs/PLAN.md` is exactly the tool this needs. Do not
  fix by loosening the LOF gate until the log says that's the cause; tb33's correctness fix should not
  be undone to paper over a fallback that isn't firing.
- **2026-07-23 (tb35 Pass A/B, root cause found and fixed) — RESOLVED-PENDING-CONFIRMATION**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. Confirmed the LOF-too-strict half of the prior
  hypothesis, not the fallback-not-engaging half: `ShotPlane.build`'s own depth-sort
  (`shot_plane.gd:45`) has no floor at zero, by design — a region behind the ray's own origin is
  legitimately present (the aim window reads it). But `LineOfFire._first_hit_excluding`,
  `ShotPlane.resolve_projectile`, and `DamageResolver._find_next` are three independent
  "walk the depth-sorted plane, return the first match" implementations that all inherited that
  same unfloored sort with no floor of their own — so a wall many tiles BEHIND the shooter (still
  in the plane on purpose) sorted first and won almost every resolution, including
  `has_clear_line_of_fire`'s own. That's why LOF read false almost everywhere post-tb31's dense
  walls: not because real geometry blocked every shot, but because the resolver was picking the
  wrong region. Live-diagnosed on a real `BoutSetup`-built bout (not a synthetic fixture): a unit
  reading zero clear cells even with an UNCAPPED search before the fix found one real cell
  (`(27, 16)`) after it.
  - **Fix, scoped as tight as possible:** `resolve_projectile` gained an opt-in `floor_at_zero`
    parameter (default false — every existing raw/body-local-plane caller, including this file's
    own test suite, is unaffected). `self_obstruction` and `region_at` opt in; `resolve_ray`'s own
    inline loop and `DamageResolver._find_next` (both always fed a real shooter-anchored
    `ShotPlane.build` plane, never a raw body-local one) floor unconditionally.
    `LineOfFire._first_hit_excluding` likewise floors unconditionally — a THIRD parallel
    implementation of the same rect-walk, not named in this taskblock's own audit list, found and
    fixed on the same pass.
  - **Second, distinct gap found and fixed once the LOF predicate was genuinely correct:**
    `LineOfFire.approach_path` (tb33 Pass B, BR32.10's own fix) is deliberately capped at
    `weapon.max_range + APPROACH_MARGIN` — a unit starting genuinely far from the nearest real LOF
    cell (more common than expected: mission-start positions are often tens of cells apart) found
    nothing within that cap and held forever even after the depth-floor fix, since nothing was
    LEFT to fall back to. Added `LineOfFire.closing_path`: real A* toward a cell adjacent to the
    enemy, no LOF requirement — deliberately NOT a greedy per-turn distance scorer (tried first,
    reverted: it reproduces BR32.10's own concave/U-shaped-wall freeze, since a one-step
    hill-climb can permanently stall the instant no reachable cell reduces raw distance further,
    where real A* just routes around).
  - **Verified live:** a 60-turn, 6-unit `BoutSetup` bout that previously showed 100% `held` turns
    (confirmed both before AND immediately after the depth-floor fix alone) now shows real
    movement, `burst_fired`/`impact`/`part_destroyed`/`part_mangled`/kills across the whole run
    once `closing_path` was added. Headless coverage:
    `test_shot_plane.gd::test_self_obstruction_never_resolves_to_a_wall_behind_the_shooter`,
    `test_shot_plane.gd::test_resolve_projectile_floor_at_zero_is_opt_in`,
    `test_line_of_fire.gd::test_first_hit_never_resolves_to_a_wall_behind_the_shooter` (a
    reconstructed BR27.02-shaped fixture), `test_line_of_fire.gd::test_closing_path_*` (progress
    toward a far enemy; routes around a concave wall instead of freezing).
  - **A1's decision log now exists** (`AiDecisionLog.emit`, `src/logic/ai/ai_decision_log.gd`): one
    `&"ai_decision"` event per unit-turn, branch taken + fired/held + hold reason, greppable off
    `combat.log` or a `MemorySink` in tests. **Not yet done:** the two framerate dumps (aim entry,
    turn start) A1 also called for are view-layer work, not logic, and remain open; so does BR27.09
    (A3). Marked Pending, not Resolved: this needs a live bout watched by the supervisor before
    promotion, same as BR32.10/BR27.07 below.
- **RESOLVED** [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — confirmed live by the supervisor (2026-07-23).

### BR27.02 — Resolved — owner: `SUPERVISOR`
**Chaingun bursts fire half-backward (visual only, hits are correct)**
- **Source:** `SUPERVISOR`
- **Reported:** 2026-07-20, observed watching a live bout play out — "the most recent two chaingun
  bursts look odd, both look like half the burst is going backward."
- **First fix (taskblock-27 Pass A1):** every attack action's shot-plane `direction` was cell-anchored
  while `origin` was muzzle-anchored — two different anchors for the same ray, which could resolve a
  target at negative depth and animate as the round travelling backward. Both now share the muzzle
  anchor. **RESOLVED-PENDING-CONFIRMATION** [CC 83fb8082-732a-4a4f-a726-04186087ef69] at the time,
  proven via a constructed overshoot-geometry test.
- **2026-07-20: supervisor reports still visually backward** — but with a key new detail: "those
  backwards shots do seem to be hitting the things they're drawn as hitting." The actual hit
  resolution (which part takes the damage) is correct; only the drawn tracer/animation direction
  still reads as backward. This means the Pass A1 fix (a `ShotPlane`/`AttackAction` geometry fix)
  either isn't the code path driving the visible tracer, or there's a second, separate anchor
  mismatch specifically in the rendering path (`resolution_player.gd`'s own tracer-drawing code, not
  yet audited against this same origin/direction-anchor class of bug). **Reopened — not
  investigated further this pass**, per instruction to just log and wait.
- **2026-07-20 (taskblock-28 Pass C):** not investigated or fixed this pass either — but
  `out/combat.log` now prints every impact/miss event's own real origin/hit geometry (was already in
  `data` since tb22/23; `LogEvent._to_string()` just never rendered it, and `Overwatch._fire`'s own
  separate impact path had no geometry at all until this pass routed it through the shared logger).
  A future session chasing this bug can read the geometry straight from the log text instead of
  re-deriving it or relying on live playback. Still open; still unconfirmed.
- **2026-07-21 (read-only investigation, `docs/Bugs-add.md`, rolled in here):** primary tracer
  read/write anchors now match (post first-fix) — no mismatch there. Suspect is the DEFLECT
  bounce-continuation segment: `resolution_player.gd:464-478` draws from the hit point to
  `deflect_end_*`, computed in `shot_resolution.gd:225-232` as `hit_point + reflected_dir *
  void_range`. `reflected_dir`'s sign/normal convention (`damage_resolver.gd:118-131`) has not been
  audited against this bug class — a flipped convention there would draw a visibly backward secondary
  ray for DEFLECT-outcome shots while leaving the real hit correct, matching "half the burst backward,
  hits correct" exactly. **Bonus find (separate, same bug class):** `overwatch.gd:264-265` still
  computes `origin` as a raw cell-center — never migrated to the muzzle-anchor fix `AttackAction`
  received in Pass A1. A second live instance of the exact same anchor-mismatch class, in a different
  code path. Neither finding implemented or tested yet.
- **2026-07-23 (live playtest, `out/combat.log`, units 0/1/2 supervisor-controlled) — a new angle,
  not yet reconciled with the 2026-07-21 suspects above.** Unit 0's 12-round chaingun burst at
  `(6, 19)`, fired from roughly `(4, 17)`: **all 12 of 12 pulls resolve `DEFLECT on wall`**, every one
  clustering around hit point `~(0.3-0.8, 13.7-14.8)` —
  e.g. `DEFLECT on wall [origin (3.95, 17.26)@1.53 -> hit (0.67, 13.80)@1.71]`. That hit point sits in
  the OPPOSITE quadrant from the aimed target: origin-to-target is `+x, +y`; origin-to-hit is
  `-x, -y`. Every pull agrees on roughly the same wrong-direction spot (scatter alone wouldn't do
  that), and — unlike the two-hop chain logged minutes later for unit 2 (`DEFLECT` immediately
  followed by its own `STOP_DEAD` continuation, sharing an origin/hit boundary) — each of these 12
  pulls logs exactly ONE impact event, no continuation segment. That means the anomaly sits in the
  FIRST forward ray-cast (muzzle to first wall) itself, not in the `reflected_dir` bounce-continuation
  segment the 2026-07-21 note suspected (which only governs what happens AFTER the first hit) — a
  candidate for a still-live anchor mismatch in the primary ray itself, distinct from that suspect,
  not yet root-caused. Logged only — not investigated or fixed this pass.
- **2026-07-23 (follow-up, read-only code investigation — no fix attempted): a concrete hypothesis
  for the first-segment anomaly above, arithmetically consistent with the logged numbers.**
  `damage_resolver.gd::resolve_shot` computes each hop's own logged point as
  `origin + dir * region.depth + perp * point.x` (`dir`/`perp` from the outer call's own `direction`,
  never re-derived per hop). Solving that equation backward for the unit-0 example above
  (`origin (3.95, 17.26)`, `dir` normalized toward `(6, 19)` ≈ `(0.76, 0.65)`, `hit (0.67, 13.80)`)
  requires `region.depth ≈ -4.3 to -5.3` — genuinely **negative**, i.e. the resolved region sits
  BEHIND the shooter along this shot's own fire line, not in front of it.
  **Why a negative-depth region could win at all:** `ShotPlane.build` (`shot_plane.gd:45`) sorts the
  whole plane with a bare `a.depth < b.depth` — no floor at zero anywhere — and `_find_next`
  (`damage_resolver.gd:837`) just walks that sorted array and returns the FIRST region whose rect
  overlaps the aim point. Negative-depth regions are a known, INTENTIONAL part of the plane (`docs/09`
  taskblock06 Pass H's own `AimController.window_depth` doc comment: "a body positioned behind the
  shooter along the fire line still gets a Region... so its own frontmost depth can be small or even
  negative") — but that fact was only ever handled defensively on the AIM-WINDOW side
  (`window_depth`'s own `MIN_WINDOW_DEPTH` clamp) and the SHOOTER's-own-body self-exclusion
  (`_first_hit_excluding`/`self_obstruction`, by identity). Neither guard stops a DIFFERENT body's
  region — a wall, say — from sorting first purely because its projected depth happens to be more
  negative than every real, forward obstacle, then winning `_find_next`'s linear scan if the aim
  point's lateral/height coordinates happen to fall inside that region's rect (which a wide/tall wall
  segment's own rect can do regardless of which side of the shooter it's actually on). If real, this
  would be a genuine RESOLUTION bug (which region gets picked), not merely a rendering-direction one —
  which would refine, not just extend, the 2026-07-20 report's own claim that "hit resolution... is
  correct; only the drawn tracer direction is backward" (that may hold for whatever case prompted that
  original report, but doesn't appear to hold for this DEFLECT case). **Not verified against a
  constructed fixture — this is a read-through-the-code hypothesis from one live example's own
  arithmetic, not a proven root cause.** No fix attempted.
- **2026-07-23 (tb35 Pass B — this hypothesis confirmed and fixed, advancing but not closing)**
  [CC 16507d21-1035-4b1c-a0fe-72a911df7403]. The 2026-07-23 read-only hypothesis above was exactly
  right: `_find_next` (and `ShotPlane.resolve_projectile`, and a third independent implementation,
  `LineOfFire._first_hit_excluding`, discovered on the same pass) all walked the unfloored,
  negative-depth-inclusive plane with no floor of their own. Fixed by flooring the RESOLVING path at
  `depth >= 0` (opt-in on `resolve_projectile`, unconditional on the other two, which are always fed
  a real shooter-anchored plane) while leaving `ShotPlane.build`'s own sort and the aim window's
  `window_depth` reading untouched, per this same bug's own 2026-07-23 note above. Headless
  regression: `test_line_of_fire.gd::test_first_hit_never_resolves_to_a_wall_behind_the_shooter`
  reconstructs this exact shape (real target ahead, wall several cells behind the shooter, present in
  the plane on purpose) and asserts the resolved hit is the target, not the wall. **Stays Active, one
  entry** (this taskblock's own scope fence, per the supervisor's ruling): this fixes the resolution
  mechanism the hypothesis named, but the original report was about the drawn TRACER direction
  specifically, and that rendering path (`resolution_player.gd`) has not been re-checked live against
  this fix — needs a live bout to confirm the visual symptom is actually gone, not just the
  resolution math underneath it.
- **2026-07-23 (supervisor request, `out/combat.log` read) — positive resolution-side evidence, not a
  closure.** The most recent chaingun burst in the log (12-round burst at cell (25,4), shooter muzzle
  (17.83, 5.47)): all 12 pulls landed, and every hit point clusters tightly around (24.7–26.9,
  4.0–4.3) — on and just past the aimed cell, `dx` ≈ +7 to +9 in the actual aimed direction. Several
  pulls deflect and continue on to a wall further in that SAME forward direction; none land in the
  opposite quadrant. This is the exact shape the depth-floor fix predicts, and the opposite of this
  entry's own original 12/12-pulls-in-the-wrong-quadrant case. Still only resolution data, not the
  drawn tracer — stays Active, one entry, pending a live look at an actual burst's own tracer.
- **RESOLVED** [CC 16507d21-1035-4b1c-a0fe-72a911df7403] — confirmed live by the supervisor (2026-07-23), after watching a dozen real bursts post-depth-floor-fix.

