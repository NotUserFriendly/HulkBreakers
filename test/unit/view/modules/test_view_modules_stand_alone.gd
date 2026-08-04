extends GutTest

## taskblock-56 Pass C — **THE ACCEPTANCE.** "A module can be instantiated with no overlay at all —
## if a module needs its parent, it is not a module."
##
## The pass's own stop condition is *"Pass C finds a module that cannot stand alone. That is the
## collapse failing its own premise and it changes the rest of the block."* So this file is the
## thing that would have to fail for the rest of taskblock-56 to be wrong, and it is deliberately
## brutal about it: every module in `ModuleCatalog` is mounted against a `ModuleContext` whose
## **every field is null** — no battle, no UI root, no host, no tactics, no slots — and then
## unmounted.
##
## **Exhaustive by construction, not by hand-listing.** The whole reason `ModuleCatalog` exists is
## that a test naming six modules proves it for six modules. Iterating the catalog means a module
## added in Pass E or F is covered the day it is added, or fails `test_the_catalog_builds_every_id`
## for not being registered.
##
## **Why an empty context is the right torture and not an unrealistic one.** Three of the four modes
## genuinely hit pieces of it: `SquadControlOverlay._build_ui` has always had to run before a battle
## exists, because the session-start log line needs a live sink the instant it is emitted; a
## display-only mode really does have `tactics == null`; and Pass F's editor mounts display modules
## against a board with no `CombatState` behind it. A module that needs its parent would have needed
## it in production too, just later and less visibly.


func before_each() -> void:
	DataLibrary.reset()
	DataLibrary.load_all()


func after_each() -> void:
	DataLibrary.reset()


## Every registered id builds. A null here means the catalog lists something it cannot make, which
## would make the acceptance below silently skip it.
func test_the_catalog_builds_every_id() -> void:
	for id: StringName in ModuleCatalog.IDS:
		var module: ViewModule = ModuleCatalog.build(id)
		assert_not_null(module, "ModuleCatalog cannot build its own registered id %s" % id)
		if module != null:
			assert_eq(module.module_id(), id, "%s reports a different module_id" % id)
			module.free()


## An id nobody registered is a mode without that module, not a crash — the same "no further action,
## no silent rollback" posture `ActionCatalog.build_firing_action` already has.
func test_an_unknown_id_builds_nothing_rather_than_crashing() -> void:
	assert_null(ModuleCatalog.build(&"a_module_that_does_not_exist"))


## **The acceptance.** Mount, then unmount, against an entirely empty context.
func test_every_module_mounts_against_an_empty_context() -> void:
	for id: StringName in ModuleCatalog.IDS:
		var module: ViewModule = ModuleCatalog.build(id)
		add_child_autofree(module)
		var context := ModuleContext.new()
		module.mount(context)
		assert_eq(module.context, context, "%s did not take the context it was mounted with" % id)
		assert_true(context.has_module(id), "%s did not register itself in the context" % id)
		module.unmount()
		assert_null(module.context, "%s kept its context after unmount" % id)
		assert_false(context.has_module(id), "%s stayed registered after unmount" % id)
		gut.p("%s mounts and unmounts with no overlay, no battle, no UI root" % id)


## The lifecycle hooks a host drives every frame and every battle load must also survive an empty
## context — a module that mounts and then dies on the first `rebind` has only moved the failure.
func test_every_module_survives_rebind_and_tick_with_nothing_wired() -> void:
	for id: StringName in ModuleCatalog.IDS:
		var module: ViewModule = ModuleCatalog.build(id)
		add_child_autofree(module)
		module.mount(ModuleContext.new())
		module.rebind()
		module.tick(0.016)
		module.unmount()
	assert_true(true, "every module's rebind and tick are no-ops with nothing wired")


## A double mount is a host bug, and building a second copy of every panel is a worse answer than
## ignoring it.
func test_mounting_twice_is_ignored() -> void:
	var module: ViewModule = ModuleCatalog.build(&"combat_log")
	add_child_autofree(module)
	var first := ModuleContext.new()
	module.mount(first)
	module.mount(ModuleContext.new())
	assert_eq(module.context, first, "a second mount must not replace the first context")


## Unmounting something never mounted is a no-op, not an error — teardown runs on paths that may not
## have completed setup.
func test_unmounting_without_mounting_is_a_no_op() -> void:
	var module: ViewModule = ModuleCatalog.build(&"combat_log")
	add_child_autofree(module)
	module.unmount()
	assert_null(module.context)


## **The two axes, asserted as a partition.** Every module answers exactly one of DISPLAY/INPUT, and
## the input set is exactly the three that end in `ActionQueue.enqueue`. Pinned as a list because
## the whole point of the axis is that a mode can be checked against it — Pass D asserts "a mode
## with no input modules cannot mutate state through the view", and that assertion is worth
## nothing if a module's kind can drift.
func test_the_input_modules_are_exactly_the_ones_that_queue_actions() -> void:
	var expected: Array[StringName] = [&"unit_input", &"action_bar", &"turn_controls"]
	var found: Array[StringName] = []
	for id: StringName in ModuleCatalog.IDS:
		var module: ViewModule = ModuleCatalog.build(id)
		if module.is_input():
			found.append(id)
		module.free()
	found.sort()
	expected.sort()
	gut.p("input modules: %s" % ", ".join(found))
	assert_eq(
		found, expected, "the input set changed -- see ViewModule's note on where the line is"
	)
