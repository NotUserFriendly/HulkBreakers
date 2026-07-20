# BUGS.md — Bug Ledger

**The single place a bug's status lives.** New and resolved, with a rough report time and (for recent
ones) the taskblock in play. Its job: **a resolved bug must have a closure marker here**, so an old
report — still readable in `taskblock_done/`, still describing acceptance criteria — is never
re-derived as open. If you fixed something, mark it RESOLVED here, even if the fix landed as a plain
commit outside the taskblock cadence. That out-of-cadence gap is exactly what let stale reports
recur.

**Convention:** newest at the top of each section. Recent entries get a timecode + taskblock; older
migrated ones get a rough date. `RESOLVED` entries name the fixing commit(s)/taskblock so the closure
is verifiable.

**Every bug carries a `source`:**
- **`CC`** — found by CC during its own work (usually a pure-code bug). CC owns the whole loop
  (sees it, fixes it, tests it), so **CC may mark a `CC`-sourced bug `RESOLVED` directly.**
- **`SUPERVISOR`** — reported by the supervisor (the human overseeing the project). CC often
  *can't see* what was reported (a visual glitch, a "feels wrong" behavior), so it may have fixed
  the wrong thing. **CC may NEVER write plain `RESOLVED` on a `SUPERVISOR`-sourced bug.** The most
  it may write is **`RESOLVED-PENDING-CONFIRMATION`** (fix committed, CC believes it's done,
  awaiting the supervisor's verification). Only the supervisor promotes `PENDING-CONFIRMATION` →
  `RESOLVED`, and only after seeing the fix work.

**Session stamps.** CC has no sequential session counter — what it *does* have is a **session
UUID** embedded in its scratchpad directory path (e.g. `.../83fb8082-732a-4a4f-a726-04186087ef69/
scratchpad`). CC stamps its closure marks with that UUID — the short prefix is enough to read at a
glance (e.g. `RESOLVED-PENDING-CONFIRMATION [CC 83fb8082]`). If CC is refreshed it gets a *new* UUID,
so a later session reading an earlier session's `PENDING-CONFIRMATION` sees a **different** stamp than
its own — that's the signal it's *another instance's* unverified claim. It must NOT promote it to
`RESOLVED` on the strength of a prior CC's word, only on the supervisor's. A pending mark whose UUID
isn't your current one is a claim to re-check, not a closure to trust.

**End-of-taskblock digest.** At the end of each taskblock, CC lists every `SUPERVISOR`-sourced bug
it moved to `RESOLVED-PENDING-CONFIRMATION` this block — a "here's what I think I fixed, please
confirm" roll-up — so pending items surface at a natural review point without interrupting mid-work.

---

## ✅ Resolved

### Resource Editor — four layout bugs (stale-report source)  ·  source: `SUPERVISOR`
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

### Waist-line of impacts — the shot-plane Z-discard  ·  source: `SUPERVISOR`
- **Reported:** through mid-2026-07 review passes ("a line of impacts across the waist"; "only seeing
  ~20% of shots"; "no ricochets").
- **Symptom:** projection collapsed `Vector3 → Vector2(x, z)`, dropping the height axis — so vertical
  scatter collapsed to a horizontal band and tracers/ricochets pinned to one height.
- **RESOLVED** in **taskblock 23** (true-3D shot resolution): projection retains height, the dartboard
  scatters in 3D, `resolve_ray` accepts vertical shots, tracers draw the real 3D path. Tagged in
  `docs/CHANGELOG.md`.

### `los.gd` `range`-shadow (v1)  ·  source: `CC`
- **Symptom:** a param named `range` shadowed the builtin, failing at load/call time.
- **RESOLVED** in the v1 foundation work (noted historically in `docs/SUPERSEDED.md`). `gdlint` now
  catches this class faster than the engine does (see `docs/TOOLING.md` gotchas).

---

## ⏳ Resolved — pending supervisor confirmation
*(CC-fixed `SUPERVISOR` bugs awaiting verification. CC writes here, never straight to Resolved;
the supervisor promotes confirmed ones up to Resolved. None currently.)*

---

## 🔧 Active / Open
*(none currently tracked — add here with `source`, timecode + taskblock as they're reported)*

---

## Notes on scope
- **Design reversals** (a decision that changed shape) go in `docs/SUPERSEDED.md`, not here — that's
  "the design used to be X, now it's Y," not "something was broken."
- **Known-limitations that are deferred by choice** (a stubbed system awaiting its phase) live in
  `docs/PLAN.md`, not here — they aren't bugs, they're unbuilt work.
- This file is only for **things that were broken**: reported defects and their closure.
