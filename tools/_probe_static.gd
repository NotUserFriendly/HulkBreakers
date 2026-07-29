extends SceneTree


func _init() -> void:
	DataLibrary.load_all()
	var run := SuiteRun.new()
	run.ingest(
		(
			"= Run Summary\nres://test/unit/logic/test_replay_handle.gd\n"
			+ "- test_a_handle_rebuilds_the_fixture_its_test_built\n"
			+ "Passing Tests      1\nFailing Tests         1\n__SUITE_EXIT__=1\n"
		)
	)
	print("lines: ", run.lines)
	print("failures: ", run.failures())
	print("handles: ", ReplayCatalog.handles_for(run.failures()).size())
	quit()
