# 09 — Combat Log & Turn Phases

## Turn phases: TACTICS then RESOLUTION
Turns are **queued, then paid off**. These are two distinct phases and the split is
structural, not cosmetic.

```
TACTICS     player queues an ordered action list per unit
            "go here, fire here, go here, fire here, end turn"
            → previews only. The authoritative state is NOT mutated.

RESOLUTION  on End Turn, the queue executes — until something interrupts it.
            → every mutation, every projectile, every explosion happens here.
```

Why it's built this way:
- **The payoff doesn't land while you're neck-deep in a stat panel.** Reading and watching are
  separated in time.
- **Multiplayer falls out cleanly.** Simultaneous turns need exactly this shape: collect
  intents → resolve authoritatively. Retrofitting it later means touching every action.

### Rules
- `ActionQueue`: an ordered list per unit. Queuing validates *optimistically* against a
  **speculative** state copy for previews.
- **RESOLUTION is a loop with re-entry (docs/10 taskblock06 Pass D), not one atomic pass:**
  `TACTICS → RESOLUTION → (interrupt) → TACTICS → RESOLUTION → ...`. `resolve_until()` is the
  real entry point (`resolve_turn()` is a thin void wrapper over it for callers that don't care
  about the outcome) and returns `{kind: COMPLETED}` or `{kind: STOPPED, unit, reason, refund:
  {ap, mp}}`.
- **Re-validate at resolution.** The world moved. **Stop the instant the next thing to happen is
  no longer legal — never "abort this one and keep going."** (This reverses the older rule this
  section used to state; taskblock02 F's "abort, log, continue" is gone.) A queued move is
  re-checked at cell granularity too, not just between actions — a lost leg can turn the rest of
  an already-approved path illegal even though the path itself never changed. **AP already
  spent stays spent** (it already bought whatever MP got used); **MP is refunded** as whatever
  the interrupted unit's own pool holds at the stopping point. **Only the interrupted unit
  returns to TACTICS** — every other unit's own queued resolution is unaffected.
- Resolution order is deterministic and seeded.
- No mutation ever escapes RESOLUTION. If a system mutates during TACTICS, that's a bug.

This stays out of scope for netcode (`99`) — but `CombatState` must remain serializable and
every mutation must flow through a queued Action, so a future authoritative host could replay
one turn's queues.

## The combat log
A **rolling, structured log** — a real game feature, and simultaneously CC's and your
monitoring channel.

```
LogEvent: { turn, phase, unit_id, kind: StringName, data: Dictionary, text: String }
CombatLog.emit(event)
```

**Sinks are pluggable** (this is the open-ended bit — do not hardcode a destination):

| Sink | Use |
|---|---|
| `MemorySink` | tests assert on the event stream |
| `StdoutSink` | CC reads it in the test log |
| `FileSink` | appends to `out/combat.log` — **you `tail -f` it** |
| `UISink` | the in-game rolling log panel (Phase 10+) |

Rules:
- Log **events, not strings**. `text` is rendered from `data` via the description builder
  (`08`), so the log and the tooltips can never disagree.
- Every projectile, deflection, ricochet, penetration, cook-off, abort-reason, and matrix
  ejection emits an event. If it changed the world, it's in the log.
- Same seed → byte-identical log. That makes the log a **regression fixture**: diff two runs.
- **One stream, many sinks — never two streams** (taskblock03 Pass B). `BattleScene` registers
  both `UISink` and `FileSink` on the *same* `CombatLog`, so the on-screen panel and
  `out/combat.log` are the identical event stream by construction — they cannot drift, because
  neither one renders anything the other doesn't also get. A **`bout_start`** event carries the
  seed as that bout's first line, so a human session is a regression fixture too, not just a
  headless test run: it's replayable from the log file alone.
- **A log file holds several bouts, and every one of them logs its own seed** (taskblock-52,
  `BR52.11`). A new bout **appends**; only a new process rotates the file. So the header is
  per-**bout**, not per-file — it was called `session_start` back when one file meant one bout,
  and a file's first seed line describes only the first bout in it.
- **The seed logged is the ORIGIN seed** — the one number a whole bout derives from — carried on
  `CombatState.bout_seed` and emitted by `BattleScene.load_battle` itself, unconditionally.
  Deliberately not `rng.seed`, which is a *derived* `randi()` and would not regenerate the map:
  it would look right in the log and replay nothing. And deliberately not an argument a caller
  passes, because a caller that forgets produces a bout with no record of how to reproduce it —
  which is precisely what the Simulate Bout menu did for five blocks (then
  `GenerateBoutOverlay`, now `BoutSetupModule` — taskblock-56 Pass D).

## Diagnostics ride the same stream (taskblock-41 Pass B)
Engine and script errors are **combat-log events**, not a second log. `EngineErrorTap` is a real
Godot `Logger` registered with `OS.add_logger`; every error it sees becomes a `LogEvent` of kind
`diagnostic`, emitted onto whichever `CombatLog` is current. **Conflated on purpose, separable on
demand** — `LogSink.wants(event)` is the opt-out, checked once in `CombatLog.emit()`, and
`LogEvent.is_diagnostic()` is the question a sink asks. Declining is filtering one stream, never
subscribing to a different one.

`data` carries `severity` (`error` / `warning` / `script` / `shader`), plus the raw `function`,
`file`, `line`, `code` and `rationale` — nothing is collapsed away.

**What this actually reaches, verified empirically against 4.7 headless — not read off an API page:**

| Source | Reached? |
|---|---|
| `push_error` / `push_warning` | **yes** |
| **GDScript runtime errors** (null deref, bad index) — with the real script file and line | **yes** |
| Engine-internal C++ `ERR_FAIL_*` | **yes** |
| Shader compile failures | expected (same callback, own severity) |
| **A hard crash — segfault, OOM, abort** | **NO** |
| Anything raised before `install()` | **NO** |

**The boundary is load-bearing: a crash log that goes silent exactly when it matters most is worse
than no crash log.** A segfault kills the process before any GDScript sink runs, and no in-process
hook can change that — catching it needs an **external wrapper** around the engine (a shell runner
capturing stdout, or a core-dump handler). What does survive is everything written up to the instant
of death: `FileSink` flushes per line, so `out/combat.log` is a real pre-crash trail.

Two further behaviours worth knowing before reading a log: one engine failure can produce **several**
callbacks as the C++ error chain unwinds (a single missing resource produced three), and these are
reported faithfully rather than deduplicated; and `_log_message` is deliberately **not** hooked,
because `print()` routes through it and `StdoutSink` prints every event it receives — capturing
messages would be an unbounded loop.

## Two framerate numbers, and they are SUPPOSED to disagree (taskblock-41 Pass F)
There are two, deliberately, and they answer different questions:

- **`FpsDumpSink`** samples a fixed delay *after* `turn_start` — past the turn-boundary hitch, into
  settled steady state — and emits a `fps_dump` event into the log. It answers **"is the game slow in
  general,"** for CC to grep out of `out/combat.log`.
- **The on-screen readout** (`FpsMeter`, drawn over the combat-log panel) does the opposite: it shows
  the hitch **as it happens**, instantaneous alongside a rolling one-second average, for a human
  watching the screen.

**This divergence is intended and must not be reconciled. Keep the dump exactly as it is.** When the
two agree, that is a positive indicator. When they disagree, **the disagreement is itself the clue**
— the gap between them measures transient cost that neither number shows alone. A later pass that
"fixes" the discrepancy by making them sample the same way deletes the only signal that distinguishes
BR26.02 (slow in general) from BR27.09 (a hitch at a boundary).

The readout shows both its own numbers for the same reason: a single blended figure hides the gap
between "right now" and "over the last second". The rolling window is time-bounded, not
frame-bounded, so one second means one second at 5 FPS and at 500 FPS alike.

## Checkpoints — an ordinary tool (taskblock-41 Pass E)
What was retired was the **gate**, not the capability. The original ritual was five
committed-artifact checkpoints, each ending in "stop and wait for a go" — that stalled the pipeline
and deserved to go, and `SUPERSEDED.md` records it. The underlying ability never stopped being
valuable: drive the real `BattleScene` through a real GPU frame and capture what it actually looks
like.

It pays for itself. **BR40.01** — the attack camera solving a position past the far edge of the
platform the shooter stands on, filling the frame with that platform's own mass — was found by
rendering, not by testing. The headless height-delta matrix passed every invariant it checks: both
bodies fit, the camera never dropped below the lower body, continuity held across the zero crossing.
The frame was still garbage. **Numerically clean and visually broken is exactly the gap a screenshot
closes and a test cannot.**

How it works now:
- **CC authors a checkpoint whenever it judges one useful.** No permission step, no hard stop. The
  supervisor looks at it when convenient.
- `./checkpoint.sh N` runs `tools/checkpoints/checkpoint_N.gd` against a real display driver. The
  driver script is generic; **the scenario owns its own README and checklist**, so the description
  and the code it describes cannot drift apart.
- **`out/checkpoints/` is local only** (`.gitignore`). Images are large and cheap to regenerate.
  **The durable artifact is the answers, not the images** — a checklist worked through by the
  supervisor belongs in `reports/Report-TaskblockN.md`, which is committed. To keep one specific
  image, copy it into `out/checkpoints-kept/`, which is tracked; copying it *is* the decision.
- **A parse guard runs in `run_tests.sh`, and it is the load-bearing piece.** Visual checkpoints sit
  outside the headless gate by necessity, so nothing re-runs them — which is why a `UnitView` rename
  orphaned two scripts for ~15 taskblocks (BR40.02) with no test going red. Rendering can't happen in
  CI; **parsing can**. `tools/checkpoints/parse_guard.gd` loads every scenario and fails the build on
  a parse error or a script that has stopped being a `SceneTree` entry point. It runs *without* `-d`
  and *before* GUT: under the debugger a parse error raises a break that waits for input, so the
  guard would hang the build rather than fail it.

The foundation baselines the old ritual wrapped survive as ordinary regression tests in the GUT
suite — `test/baselines/test_map_generation_baseline.gd` and friends, renamed out of the checkpoint
frame because the names implied a gate that no longer exists. They run every `./run_tests.sh`, and
always did.

## Why this matters for CC specifically
CC cannot see the game. The ASCII dumps and the combat log **are** its eyes — and they're the
same artifacts you review. One channel, two consumers. Build them in Phase 0 and use them in
every phase; a spatial system without a dump is a system nobody can verify.
