extends GutTest

## taskblock-51 Pass C (`BR27.03` / `BR34.01`): **a hop is not a new shot.**
##
## > *"All shots would land and tracers flash, THEN the deflections would flash, even though
## > logically a shot would land and deflect right after each other."*
##
## One trigger pull produces one `ImpactResult` per hop — a wall, then cover, then the target —
## and `ResolutionPlayer` inserted `INTER_SHOT_BREAK_MS` between every consecutive impact. So a
## round that hit a wall and carried on read as two separate gunshots a tenth of a second
## apart, and the continuation looked like a reply rather than the same bullet still moving.


func _event(hop_index: int) -> LogEvent:
	return LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"impact", {"hop_index": hop_index}, "impact")


## The rule, stated once: hop 0 opens a pull, anything above it continues one.
func test_only_the_first_hop_starts_a_new_pull() -> void:
	assert_true(ResolutionPlayer.starts_a_new_pull(_event(0)), "the shot itself")
	assert_false(ResolutionPlayer.starts_a_new_pull(_event(1)), "its ricochet is the same bullet")
	assert_false(ResolutionPlayer.starts_a_new_pull(_event(2)), "and so is the next hop")


## **An event with no `hop_index` opens a pull.** Every impact that is not part of a resolved
## hop chain — a fragment, a `miss`, anything logged before this field existed — is its own
## shot, and defaulting the other way would silently glue unrelated events together.
func test_an_event_without_a_hop_index_is_its_own_shot() -> void:
	var bare := LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"impact", {}, "impact")

	assert_true(ResolutionPlayer.starts_a_new_pull(bare))


## **A pull's hops flash together.** *"Deflect and penetrate tracers ... flash at the same time
## as their initial hit."* One trigger pull is one visual event: the primary bright, its
## continuations alongside it, not a stutter of separate flashes. An event whose successor
## continues it is drawn without being awaited, so only the last hop of a pull is waited on.
func test_a_hop_followed_by_another_hop_is_not_awaited() -> void:
	var events: Array[LogEvent] = [_event(0), _event(1), _event(2)]

	assert_true(
		ResolutionPlayer._next_event_continues_this_pull(events, 0), "the primary waits for nobody"
	)
	assert_true(ResolutionPlayer._next_event_continues_this_pull(events, 1), "nor does hop 1")
	assert_false(
		ResolutionPlayer._next_event_continues_this_pull(events, 2), "the last hop is awaited"
	)


## **A new pull is never folded into the one before it.** Two separate shots must stay two
## separate flashes, or the fix for a stutter becomes a fix that hides real shots.
func test_a_following_shot_does_not_get_swallowed_by_the_previous_pull() -> void:
	var events: Array[LogEvent] = [_event(0), _event(1), _event(0)]

	assert_true(ResolutionPlayer._next_event_continues_this_pull(events, 0))
	assert_false(
		ResolutionPlayer._next_event_continues_this_pull(events, 1),
		"hop 1 is awaited, because what follows is a different shot"
	)


## A non-impact event between hops ends the pull — a `move` or a `faced` is not a continuation,
## and treating it as one would draw a tracer concurrently with an unrelated animation.
func test_only_an_impact_can_continue_a_pull() -> void:
	var events: Array[LogEvent] = [
		_event(0),
		LogEvent.new(1, Enums.Phase.RESOLUTION, 0, &"move", {"hop_index": 1}, "move"),
	]

	assert_false(ResolutionPlayer._next_event_continues_this_pull(events, 0))
