extends GutTest

## tb66 Pass F — **the aggregated verdict, and the three ways it could lie.**
##
## `tools/merge_shards.py` turns eight shard logs into one report. **Readable failure is what makes
## people keep a sharded gate**, so what is asserted here is not that the merge sums correctly — it
## is that the merge cannot report green when it should not.
##
## **Driven against crafted logs rather than a real sharded run.** A killed shard and a split corpus
## both take minutes to produce for real and are awkward to produce *reliably*; as fixtures they are
## a few lines and they test the exact branch. The real sharded gate is what proves the happy path.

const MERGER := "tools/merge_shards.py"

var _dir: String = ""


func before_each() -> void:
	_dir = "%s/tb66_merge_%d" % [OS.get_temp_dir(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	if _dir != "":
		OS.move_to_trash(ProjectSettings.globalize_path(_dir))


## A shard log that finished, with the counter line the merger reads.
func _log(name: String, tests: int, failures: int, extra: String = "") -> String:
	var path: String = "%s/%s" % [_dir, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_line("--- suite cost ---")
	file.store_line("1 script(s), %d test(s), %d failure(s), 12.3 s" % [tests, failures])
	file.store_line(
		(
			"bouts 1  turns 4  plans 4  candidates 9  shot_planes 2  floods 7  "
			+ "ui_builds 0  escaped 0  maps 3  spawns 0  sampled_turns 0"
		)
	)
	if extra != "":
		file.store_line(extra)
	file.close()
	return path


func _run(paths: Array[String]) -> Dictionary:
	var args: Array[String] = [MERGER]
	args.append_array(paths)
	var out: Array = []
	var code: int = SuiteProcess.execute("python3", args, out, true)
	return {"code": code, "text": "\n".join(PackedStringArray(out))}


## **Never `gut.p` the merger's raw output, and this is not fastidiousness.**
##
## The fixtures below deliberately contain the exact markers `merge_shards.py` scans for —
## `seeds to first completion`, `[Failed]` — because that is what they are testing. Echoing the
## merged text into this script's stdout puts those markers in *this shard's* log, where the real
## merge then reads them back as a second corpus draw and a phantom failure message.
##
## **It happened.** The first sharded gate after this file landed reported *"MORE THAN ONE SHARD
## DREW"* against a perfectly co-located map. A test that prints what a parser looks for is a
## self-reference hazard, and the fix is to assert on the text without republishing it.
func _summarise(result: Dictionary) -> String:
	return "exit %d, %d line(s)" % [result["code"], (result["text"] as String).split("\n").size()]


## The happy path, so the failures below mean something.
func test_two_clean_shards_merge_to_a_pass() -> void:
	var result: Dictionary = _run([_log("s0.log", 10, 0), _log("s1.log", 20, 0)])

	gut.p(_summarise(result))
	assert_eq(result["code"], 0, "two green shards are a green gate")
	assert_true("30 test(s), 0 failure(s)" in result["text"], "and the tests are summed")


## **A failure in any shard fails the gate and names itself.** A merged report that summed counters
## but lost the message would make a red gate something you have to go and find.
func test_a_failure_in_one_shard_fails_the_gate_and_is_named() -> void:
	var result: Dictionary = _run(
		[
			_log("s0.log", 10, 0),
			_log("s1.log", 20, 1, "    [Failed]:  expected 3 to equal 4:  the board moved"),
		]
	)

	gut.p(_summarise(result))
	assert_eq(result["code"], 1, "one failing shard fails the whole gate")
	assert_true("the board moved" in result["text"], "and the message survives the merge")
	assert_true("shard 1" in result["text"], "attributed to the shard it came from")


## **The one that matters most: a shard that died must not read as a shard that passed.**
##
## A crashed process writes a log with no `--- suite cost ---` line. A merger that sums whatever it
## finds would report the surviving shards' totals and exit 0 — a green gate that ran seven eighths
## of the suite, which is exactly the failure `run_tests.sh`'s completion guard already exists for
## on the single-process path and the easy bug to ship here.
func test_a_shard_that_never_finished_fails_the_gate() -> void:
	var killed: String = "%s/s1.log" % _dir
	var file := FileAccess.open(killed, FileAccess.WRITE)
	file.store_line("== running ==")
	file.store_line("Segmentation fault (core dumped)")
	file.close()

	var result: Dictionary = _run([_log("s0.log", 10, 0), killed])

	gut.p(_summarise(result))
	assert_eq(result["code"], 1, "a dead shard is a failed gate, not a missing section")
	assert_true("DID NOT FINISH" in result["text"], "and it says so by name")


## **A log that is not there at all is the same class of failure**, and it is the shape a mistyped
## shard map or a lost temp directory takes.
func test_a_missing_shard_log_fails_the_gate() -> void:
	var result: Dictionary = _run([_log("s0.log", 10, 0), "%s/never_written.log" % _dir])

	assert_eq(result["code"], 1, "an absent shard cannot be assumed empty")
	assert_true("DID NOT FINISH" in result["text"])


## **More than one corpus draw means co-location broke**, and the merged completion report would
## then describe one of several samples with nothing saying so. `test_shard_map.gd` prevents it
## structurally; this is the runtime backstop for a hand-edited map.
func test_two_shards_drawing_a_corpus_sample_fails_the_gate() -> void:
	var result: Dictionary = _run(
		[
			_log("s0.log", 10, 0, "seeds to first completion: 3 (cap 9)"),
			_log("s1.log", 10, 0, "seeds to first completion: 7 (cap 9)"),
		]
	)

	gut.p(_summarise(result))
	assert_eq(result["code"], 1, "two draws in one gate is a broken shard map")
	assert_true("MORE THAN ONE SHARD DREW" in result["text"], "and it is named, not inferred")


## **Output order follows the shard index, never arrival.** Shards finish in whatever order the
## scheduler gives, and a report that reordered between runs could not be diffed — which is how a
## real regression hides in noise.
func test_the_report_orders_by_shard_index_not_by_argument_luck() -> void:
	var a: String = _log("a.log", 11, 0)
	var b: String = _log("b.log", 22, 0)

	var forward: Dictionary = _run([a, b])
	var backward: Dictionary = _run([b, a])

	var first_forward: int = (forward["text"] as String).find("shard 0")
	var second_forward: int = (forward["text"] as String).find("shard 1")
	assert_lt(first_forward, second_forward, "shard 0 is printed before shard 1")
	assert_eq(
		(forward["text"] as String).count("shard "),
		(backward["text"] as String).count("shard "),
		"the same shards are reported either way round"
	)
