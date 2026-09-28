extends GutTest
## The world globals themselves: the registry systems find each other through, the
## one clock the timers run on, and the combat log both peers read.
##
## WorldState is an autoload, so these tests deliberately talk to the live singleton
## -- that is the thing in use at runtime. Anything they add is cleaned up after
## each test, because the next test would otherwise inherit it.

const HealthScript: GDScript = preload("res://scripts/health.gd")

var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	_root.name = "WorldStateTest"
	add_child_autofree(_root)


#region The registry ------------------------------------------------------------

func test_a_registered_entity_can_be_found_again() -> void:
	var node: Node3D = Node3D.new()
	node.name = "thing"
	_root.add_child(node)
	WorldState.register_entity("test_kind", node)
	assert_true(WorldState.entities_in("test_kind").has(node), "it should be listed")
	assert_eq(WorldState.count_of("test_kind"), 1)
	WorldState.unregister_entity("test_kind", node)


func test_registering_the_same_node_twice_lists_it_once() -> void:
	var node: Node3D = Node3D.new()
	_root.add_child(node)
	WorldState.register_entity("test_kind", node)
	WorldState.register_entity("test_kind", node)
	assert_eq(WorldState.entities_in("test_kind").size(), 1, "no duplicates")
	WorldState.unregister_entity("test_kind", node)


func test_a_freed_entity_is_dropped_from_the_list() -> void:
	# The whole reason this registry is worth having: callers never have to defend
	# against holding a node that has since been freed.
	_register_then_free("test_kind")
	assert_eq(WorldState.entities_in("test_kind").size(), 0,
			"a dead node must not come back out of the registry")


## Registered and freed inside one call, so the test itself never holds the corpse.
func _register_then_free(kind: String) -> void:
	var node: Node3D = Node3D.new()
	_root.add_child(node)
	WorldState.register_entity(kind, node)
	node.free()


func test_an_unknown_kind_is_simply_empty() -> void:
	assert_eq(WorldState.entities_in("never_registered").size(), 0)


#endregion


#region The clock and its timers ------------------------------------------------

func test_a_scheduled_call_runs_once_its_time_comes() -> void:
	var calls: Array[int] = []
	WorldState.schedule(func() -> void: calls.append(1), 0.5)
	var pending: int = WorldState.pending_timers()
	WorldState._process(0.4)
	assert_eq(calls.size(), 0, "not yet")
	assert_eq(WorldState.pending_timers(), pending, "and still waiting")
	WorldState.schedule(func() -> void: calls.append(2), 0.0)
	WorldState._process(0.0)
	assert_eq(calls, [2], "a timer that is due runs")


func test_a_due_timer_is_forgotten_after_it_runs() -> void:
	# Counts its own calls rather than the global queue: other tests leave timers
	# of their own pending, and this must not care about them.
	var calls: Array[int] = []
	var counter: Callable = func() -> void: calls.append(1)
	WorldState.schedule(counter, 0.0)
	WorldState._process(0.5)
	assert_eq(calls.size(), 1, "it ran")
	WorldState._process(0.5)
	assert_eq(calls.size(), 1, "and it must not run again")


func test_the_world_clock_only_moves_forward() -> void:
	var before: float = WorldState.world_time
	WorldState._process(0.25)
	assert_almost_eq(WorldState.world_time, before + 0.25, 0.0001)


#endregion


#region The combat log ----------------------------------------------------------

func test_a_line_lands_in_the_log_and_is_announced() -> void:
	watch_signals(WorldState)
	var marker: String = "test hit for 3 (%d)" % randi()
	WorldState.log_event(marker)
	assert_true(WorldState.recent(80).has(marker), "the line should be readable back")
	assert_signal_emitted(WorldState, "combat_event", "and broadcast to the HUD")


func test_recent_returns_the_newest_lines_last() -> void:
	var first: String = "first %d" % randi()
	var second: String = "second %d" % randi()
	WorldState.log_event(first)
	WorldState.log_event(second)
	var tail: Array[String] = WorldState.recent(2)
	assert_eq(tail, [first, second] as Array[String], "oldest first, newest last")


func test_the_log_does_not_grow_without_limit() -> void:
	for i in 200:
		WorldState.log_event("filler %d" % i)
	assert_lte(WorldState.combat_log.size(), WorldState.LOG_LIMIT,
			"the log must stay bounded")


func test_a_log_of_zero_lines_reads_back_empty() -> void:
	assert_eq(WorldState.recent(0).size(), 0)

#endregion