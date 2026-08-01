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
