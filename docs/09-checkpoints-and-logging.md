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
  neither one renders anything the other doesn't also get. A `session_start` event carries the
  seed as the file's first line, so a human session is a regression fixture too, not just a
  headless test run: it's replayable from the log file alone.

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

## Checkpoints — retired
The checkpoint ritual (five committed-artifact gates at foundation phases, each a `./checkpoint.sh N`
hard stop for human review) is **retired**. It was a from-scratch-foundation mechanism; the review it
performed — a human reading a committed artifact to catch a silent geometry or randomization bug — is
now done live by the supervisor (playing, bug-hunting in spectator, doc review) plus tester-mode
(`TESTING.md`: force the condition, watch it). CC was long ago told to prefer clean reports over
generated artifacts, so the ritual sat unused across ~30 taskblocks before being cut here — see
`docs/SUPERSEDED.md`.

The foundation baselines it wrapped (`test/checkpoints/test_checkpoint_1–4.gd`) survive as ordinary
regression tests in the GUT suite — they still run every `./run_tests.sh`, they're just no longer
"checkpoints." The old checkpoint 5 was the hand-built `test_full_mission`, which retires with that
harness (`docs/PLAN.md`).

## Why this matters for CC specifically
CC cannot see the game. The ASCII dumps and the combat log **are** its eyes — and they're the
same artifacts you review. One channel, two consumers. Build them in Phase 0 and use them in
every phase; a spatial system without a dump is a system nobody can verify.
