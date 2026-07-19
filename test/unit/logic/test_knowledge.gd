extends GutTest

## taskblock-20 Pass B: the whole of `Knowledge` today — a single flagged
## checkpoint, defaulted true, since no sensor/scan system exists yet to
## gate real internal-visibility on.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


func test_knows_internal_defaults_to_true_with_no_sensor_system_to_gate_on() -> void:
	var torso: Part = DataLibrary.get_part(&"torso")
	var reactor: Part = DataLibrary.get_part(&"reactor")
	var observer := Unit.new(Matrix.new(), Shell.new(DataLibrary.get_part(&"torso")), Vector2i(0, 0))
	var target := Unit.new(Matrix.new(), Shell.new(torso), Vector2i(1, 0))
	var state := CombatState.new(Grid.new(3, 3), [observer, target])

	assert_true(Knowledge.knows_internal(state, observer, target, reactor))
