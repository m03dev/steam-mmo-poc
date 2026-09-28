extends GutTest
## The player's half of a fight: what a swing is allowed to do, and what happens
## when the player is the one who goes down.
##
## The point of these tests is the authorisation, not the arithmetic: a swing is a
## request the server re-checks, so "too far away", "not your character" and "not
## yet" all have to fail even when the caller goes straight to the resolver and
## skips the input and the range check on the client side.

const EnemyScene: PackedScene = preload("res://scenes/Enemy.tscn")
const HealthScript: GDScript = preload("res://scripts/health.gd")
const PlayerStateScript: GDScript = preload("res://scripts/player_state.gd")
const CombatScript: GDScript = preload("res://scripts/player_combat.gd")

var _root: Node3D
var _player: Node3D
var _combat
var _health
var _state
var _enemy: CharacterBody3D


func before_each() -> void:
	_root = Node3D.new()
	_root.name = "CombatTest"
	add_child_autofree(_root)
	_player = _add_player()


func after_each() -> void:
	if is_instance_valid(_player):
		WorldState.unregister_entity(WorldState.KIND_PLAYER, _player)


func _add_player(peer_id: int = 1) -> Node3D:
	var player: Node3D = Node3D.new()
	player.name = "player_%d" % peer_id
	_health = HealthScript.new()
	_health.name = "Health"
	_health.maximum = 100
	_health.current = 100
	_state = PlayerStateScript.new()
	_state.name = "Stats"
	_combat = CombatScript.new()
	_combat.name = "Combat"
	player.add_child(_health)
	player.add_child(_state)
	player.add_child(_combat)
	_root.add_child(player)
	WorldState.register_entity(WorldState.KIND_PLAYER, player)
	return player


func _add_enemy(at: Vector3, hp: int = 60) -> CharacterBody3D:
	_enemy = EnemyScene.instantiate()
	_enemy.position = at
	# Into the tree first: the mob's @onready health is not there until then.
	_root.add_child(_enemy)
	_enemy.health.current = hp
	return _enemy


#region Swinging -----------------------------------------------------------------

func test_a_swing_at_a_mob_in_reach_takes_its_damage() -> void:
	_add_enemy(Vector3(0.0, 0.0, 2.0))
	assert_true(_combat.attack(), "there is something to hit, so a swing happens")
	assert_eq(_enemy.health.current, 60 - _combat.damage, "and it lands")


func test_a_swing_with_nothing_in_reach_does_nothing_at_all() -> void:
	_add_enemy(Vector3(0.0, 0.0, 12.0))
	assert_false(_combat.attack(), "nothing within reach means no swing")
	assert_eq(_enemy.health.current, 60, "and no damage anywhere")


func test_the_nearest_mob_is_the_one_that_gets_hit() -> void:
	var near: CharacterBody3D = _add_enemy(Vector3(0.0, 0.0, 1.0))
	var far: CharacterBody3D = _add_enemy(Vector3(0.0, 0.0, 2.6))
	assert_eq(_combat.nearest_enemy(), near, "the closer one is the target")
	_combat.attack()
	assert_lt(near.health.current, far.health.current, "and the closer one took the hit")


func test_a_swing_is_gated_by_its_cooldown() -> void:
	_add_enemy(Vector3(0.0, 0.0, 2.0))
	assert_true(_combat.attack(), "first swing")
	assert_false(_combat.attack(), "the second, immediately after, must be refused")
	assert_eq(_enemy.health.current, 60 - _combat.damage, "so only one landed")


func test_a_dead_mob_is_not_a_target() -> void:
	var enemy: CharacterBody3D = _add_enemy(Vector3(0.0, 0.0, 2.0))
	enemy.health.apply_damage(999)
	assert_null(_combat.nearest_enemy(), "a corpse is not a target")
	assert_false(_combat.attack())


#endregion


#region What the server refuses --------------------------------------------------

func test_the_server_refuses_a_hit_on_something_out_of_reach() -> void:
	var enemy: CharacterBody3D = _add_enemy(Vector3(0.0, 0.0, 30.0))
	# Skip the client's range check entirely and go straight at the resolver, the
	# way a modified client would.
	_combat._resolve_swing(enemy.get_path(), 1)
	assert_eq(enemy.health.current, 60, "the reach check is the server's, and it held")


func test_the_server_refuses_a_swing_for_somebody_elses_character() -> void:
	var enemy: CharacterBody3D = _add_enemy(Vector3(0.0, 0.0, 2.0))
	_combat._resolve_swing(enemy.get_path(), 5)
	assert_eq(enemy.health.current, 60, "peer 5 does not get to swing with player_1")
	assert_push_warning("tried to act for",
			"and the refusal is announced rather than passing silently")


func test_the_server_refuses_a_nonsense_target() -> void:
	_add_enemy(Vector3(0.0, 0.0, 2.0))
	_combat._resolve_swing(NodePath("/root/does/not/exist"), 1)
	assert_eq(_enemy.health.current, 60, "a path that resolves to nothing is not a hit")


#endregion


#region Killing ------------------------------------------------------------------

func test_killing_a_mob_pays_the_player_who_did_it() -> void:
	var enemy: CharacterBody3D = _add_enemy(Vector3(0.0, 0.0, 2.0))
	enemy.health.current = 5
	_combat.attack()
	assert_eq(_state.progress.xp, enemy.xp_reward,
		"a kill is worth the mob's XP, on the player's own stats node")
	assert_false(enemy.health.is_alive(), "and the mob is down")


#endregion


#region Dying --------------------------------------------------------------------

func test_a_player_at_zero_hit_points_is_defeated() -> void:
	_add_enemy(Vector3(0.0, 0.0, 2.0))
	_health.apply_damage(100)
	assert_false(_health.is_alive())
	assert_true(_combat._dead, "the combat node should be watching its own health")


func test_asking_to_get_up_restores_the_hit_points() -> void:
	_add_enemy(Vector3(0.0, 0.0, 2.0))
	_health.apply_damage(100)
	_combat.request_respawn()
	assert_eq(_health.current, 100, "the server puts the player back on their feet")
	assert_false(_combat._dead, "and stops treating them as down")


func test_a_respawn_request_from_a_healthy_player_is_refused() -> void:
	_add_enemy(Vector3(0.0, 0.0, 2.0))
	_health.apply_damage(10)
	_combat.request_respawn()
	assert_eq(_health.current, 90, "you cannot heal yourself by asking to respawn")

#endregion