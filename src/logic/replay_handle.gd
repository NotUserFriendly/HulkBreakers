class_name ReplayHandle
extends RefCounted

## taskblock-48 Pass B2: **how a test says "here is what I built, go and look at it."**
##
## ## The problem this exists for
##
## The suite runs as a subprocess, so its maps and bouts are built in *that* process's
## memory. The running game has nothing to show — not an oversight, a consequence. A
## subprocess launcher can only ever be a terminal in a window, and no amount of
## display filtering changes that.
##
## The fix is a second execution model: **things worth looking at get rebuilt inside
## the game.**
##
## ## A replay rebuilds the fixture; it does not re-run the test
##
## The headless run already knows which test failed and why. What is missing is *what
## the test built*. So a handle is a way to reconstruct the fixture, and the game
## presents it — which also sidesteps hosting `GutRunner` in the live scene tree,
## where it would manage its own root and fight the running game for it.
##
## `BattleScene.load_battle(state, mission)` already takes exactly what a fixture
## produces; `checkpoint_9.gd` has driven it that way from `GridFixture` for blocks.
## This gives that path a caller.
##
## ## Declaring one is opting in, and having none is an answer
##
## **A test with no handle has no visual form**, and the replay skips it. A failed
## assertion about a dictionary has nothing to show. That makes the filter
## self-declaring rather than a registry someone has to remember to maintain — and
## `docs/00`'s rule that a spatial system without a dump is one nobody can verify is
## the same idea pointed at tests.

## Something a table can key on. An int for a seed, a String otherwise — both are
## usable as `Dictionary` keys, which is what `WatchedRun` records results against.
var key: Variant = 0
## Shown in the table. Short: this is a row label, not a description.
var label: String = ""
## Lines the panel prints above the table, for handles that want to explain their own
## criteria. Empty for most.
var description: Array[String] = []
## The seed, when there is one. `-1` means "this handle is not seed-shaped", which the
## panel uses to decide whether re-deriving from a seed is meaningful.
var seed_value: int = -1

var _builder: Callable = Callable()


## The common case: a bout that a map seed fully determines.
##
## `CompletionSampler.build_for_seed` takes nothing but the seed — rosters and presets
## are constants inside it — so the seed alone is a complete reproduction handle. That
## is the property taskblock-47 Pass D was built on and it is why no capture format
## exists anywhere near this.
static func from_seed(map_seed: int) -> ReplayHandle:
	var handle := ReplayHandle.new()
	handle.key = map_seed
	handle.label = "seed %d" % map_seed
	handle.seed_value = map_seed
	handle._builder = func() -> Dictionary: return CompletionSampler.build_for_seed(map_seed)
	return handle


## The general case: anything that can hand back `{state, mission}`.
static func of(handle_key: Variant, handle_label: String, builder: Callable) -> ReplayHandle:
	var handle := ReplayHandle.new()
	handle.key = handle_key
	handle.label = handle_label
	handle._builder = builder
	return handle


func is_valid() -> bool:
	return _builder.is_valid()


## Rebuilds the fixture. **Returns `{}` rather than a half-built board** when the
## builder fails or was never set — a replay that shows something other than what
## failed is worse than no replay, so "cannot rebuild this" has to be distinguishable
## from "here it is".
func build() -> Dictionary:
	if not _builder.is_valid():
		return {}
	var built: Variant = _builder.call()
	if not built is Dictionary:
		return {}
	var result: Dictionary = built
	if result.get("error", "") != "":
		return {}
	if not result.has("state") or not result.has("mission"):
		return {}
	return result
