extends GutTest
## The level's side of the mob system: spawning them by index, putting a killed one
## back where it came from, and the player's own death and return.
##
## A Level node is built by hand rather than loaded from World.tscn so the spawn
## points and respawn delay are the ones this test chose -- the scene's authored
## values are content, and content should not decide whether the logic works.

const LevelScript: GDScript = preload("res://scripts/level.gd")

const SPAWNS: Array[Vector3] = [Vector3(2.0, 1.0, 0.0), Vector3(-3.0, 1.0, 4.0)]

var _root: Node3D
var _level
var _enemies: Node3D


func before_each() -> void:
	_root = Node3D.new()
	_root.name = "LevelTest"
	add_child_autofree(_root)
	_level = _build_level(SPAWNS)
	_enemies = _level.get_node("Enemies")


func after_each() -> void:
	if is_instance_valid(_level.get_node_or_null("Players/player_1")):
		WorldState.unregister_entity(WorldState.KIND_PLAYER, _level.get_node("Players/player_1"))


## A level with exactly the children its script expects, wired the way the scene
## file wires them -- including the two MultiplayerSpawners.
func _build_level(spawns: Array[Vector3]) -> Node:
	var level: Node3D = LevelScript.new()
	level.name = "Level"
	# Far from the spawn points on purpose: a mob that noticed the player would walk
	# off its mark, and these tests are about where mobs stand.
	level.spawn_point = Vector3(0.0, 1.0, 60.0)
	level.enemy_spawns = spawns
	level.enemy_respawn_delay = 0.0

	var players: Node3D = Node3D.new()
	players.name = "Players"
	var enemy_root: Node3D = Node3D.new()
	enemy_root.name = "Enemies"
	var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Players")
	var enemy_spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	enemy_spawner.name = "EnemySpawner"
	enemy_spawner.spawn_path = NodePath("../Enemies")

	level.add_child(players)
	level.add_child(enemy_root)
	level.add_child(spawner)
	level.add_child(enemy_spawner)
	level.add_child(Area3D.new())  # Trigger; the level connects to it on ready
	level.get_child(4).name = "Trigger"
	_root.add_child(level)
	return level


#region Spawning -----------------------------------------------------------------

func test_a_mob_is_spawned_for_every_spawn_point() -> void:
	assert_eq(_enemies.get_child_count(), SPAWNS.size(),
			"one mob per declared spawn point")
	for i in SPAWNS.size():
		var enemy: Node3D = _enemies.get_node_or_null("enemy_%d" % i)
		assert_not_null(enemy, "mob %d should exist under the level's Enemies node" % i)
		assert_eq(enemy.global_position, SPAWNS[i], "and stand on its spawn point")


func test_a_mob_carries_its_own_spawn_index() -> void:
	for i in SPAWNS.size():
		assert_eq(_enemies.get_node("enemy_%d" % i).spawn_id, i,
				"otherwise a respawn could not know where to put it back")


func test_a_level_with_no_spawn_points_has_no_mobs() -> void:
	# This is how the dungeon declares itself enemy-free.
	var plain = _build_level([] as Array[Vector3])
	assert_eq(plain.get_node("Enemies").get_child_count(), 0)


func test_the_mobs_are_in_the_group_the_player_searches() -> void:
	assert_eq(get_tree().get_nodes_in_group(WorldState.KIND_ENEMY).size(), SPAWNS.size(),
			"a player has to be able to find them to swing at them")

#endregion


#region Coming back --------------------------------------------------------------

func test_killing_a_mob_asks_for_it_to_come_back() -> void:
	var pending_before: int = WorldState.pending_timers()
	_enemies.get_node("enemy_0").health.apply_damage(999, 1)
	assert_gt(WorldState.pending_timers(), pending_before,
			"the level should have a revival on the world clock now")


func test_a_fallen_mob_leaves_the_world_and_comes_back_on_its_timer() -> void:
	var enemy: Node3D = _enemies.get_node("enemy_0")
	enemy.health.apply_damage(999, 1)
	assert_false(enemy.visible, "a fallen mob is gone from the world")
	assert_true(is_instance_valid(enemy), "but it is not destroyed -- nothing to re-spawn")

	WorldState._process(0.1)  # the level's respawn delay is zero in this test
	assert_true(enemy.visible, "it is back")
	assert_eq(enemy.health.current, enemy.health.maximum, "at full health")
	assert_eq(enemy.global_position, SPAWNS[0], "and back at its own spawn point")


func test_a_mob_revives_where_it_was_killed_not_where_it_was_standing() -> void:
	# It may have chased someone across the arena before going down; home is home.
	var enemy: Node3D = _enemies.get_node("enemy_0")
	enemy.global_position = Vector3(30.0, 1.0, 30.0)
	enemy.health.apply_damage(999, 1)
	WorldState._process(0.1)
	assert_eq(enemy.global_position, SPAWNS[0], "the spawn point, not the corpse's spot")


func test_the_mobs_that_were_not_killed_are_left_alone() -> void:
	_enemies.get_node("enemy_0").health.apply_damage(999, 1)
	WorldState._process(0.1)
	assert_true(_enemies.get_node("enemy_1").visible, "the other mob never moved")
	assert_eq(_enemies.get_node("enemy_1").global_position, SPAWNS[1])

#endregion


#region The player's own death ---------------------------------------------------

func test_a_defeated_player_comes_back_at_the_spawn_point() -> void:
	var player: Node3D = _level.get_node("Players/player_1")
	assert_not_null(player, "the level should have spawned a local player offline")
	var combat = player.get_node("Combat")
	var health = player.get_node("Health")

	player.global_position = Vector3(9.0, 1.0, 9.0)
	health.apply_damage(999)
	assert_false(health.is_alive(), "down")

	combat.request_respawn()
	assert_eq(health.current, health.maximum, "back on their feet")
	assert_eq(player.global_position, _level.spawn_point,
			"and put back at the level's spawn point, not where they fell")

#endregion