extends GutTest
## The mob's mind: when it ignores you, when it comes at you, when it swings, and
## when it decides you are not worth the walk.
##
## Runs the REAL Enemy scene in the tree with its real _physics_process, because the
## thing being tested is exactly that method -- its early return for non-authority
## peers, its aggro radius, its leash. Only the world registry is faked, by
## registering a stand-in player the same way NetPlayer registers a real one.

const EnemyScene: PackedScene = preload("res://scenes/Enemy.tscn")
const HealthScript: GDScript = preload("res://scripts/health.gd")
const PlayerStateScript: GDScript = preload("res://scripts/player_state.gd")

var _root: Node3D
var _enemy: CharacterBody3D
var _target: Node3D
var _target_health
var _target_state


func before_each() -> void:
	_root = Node3D.new()
	_root.name = "EnemyAiTest"
	add_child_autofree(_root)


func after_each() -> void:
	# The registry is a singleton, so leave nothing of ours in it.
	if is_instance_valid(_target):
		WorldState.unregister_entity(WorldState.KIND_PLAYER, _target)


func _add_enemy(at: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	_enemy = EnemyScene.instantiate()
	_enemy.position = at
	_root.add_child(_enemy)
	return _enemy


func _add_player(at: Vector3, peer_id: int = 7) -> Node3D:
	_target = Node3D.new()
	_target.name = "player_%d" % peer_id
	_target.position = at
	_target_health = HealthScript.new()
	_target_health.name = "Health"
	_target_health.maximum = 100
	_target_health.current = 100
	_target_state = PlayerStateScript.new()
	_target_state.name = "Stats"
	_target.add_child(_target_health)
	_target.add_child(_target_state)
	_root.add_child(_target)
	WorldState.register_entity(WorldState.KIND_PLAYER, _target)
	return _target


func _distance() -> float:
	return _enemy.global_position.distance_to(_target.global_position)


#region Noticing -----------------------------------------------------------------

func test_a_mob_ignores_a_player_outside_its_aggro_radius() -> void:
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 30.0))
	await wait_physics_frames(5)
	assert_eq(_enemy.velocity, Vector3.ZERO, "it should not have moved")
	assert_eq(_target_health.current, 100, "and it should not have swung")


func test_a_mob_never_even_looks_for_a_target_when_it_is_not_the_authority() -> void:
	# A puppet: another peer's copy of this mob. It must not think, move or swing --
	# its whole job is to show what the server sent.
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 1.0))
	_enemy.set_multiplayer_authority(2)
	await wait_physics_frames(3)
	assert_eq(_target_health.current, 100, "a puppet must not deal damage")
	assert_eq(_enemy.velocity, Vector3.ZERO)


#endregion


#region Chasing and swinging -----------------------------------------------------

func test_a_mob_walks_at_a_player_that_comes_close_enough() -> void:
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 9.0))
	var before: float = _distance()
	await wait_physics_frames(10)
	assert_lt(_distance(), before, "it should be closing the gap")
	assert_gt(_enemy.velocity.length(), 0.0, "and moving, not standing there")


func test_a_mob_hits_inside_its_reach() -> void:
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 1.5))
	await wait_physics_frames(2)
	assert_eq(_target_health.current, 91, "one swing, for its own damage figure")
	assert_eq(_enemy.velocity, Vector3.ZERO, "and it stops to fight rather than walking")


func test_a_mob_waits_out_its_cooldown_between_swings() -> void:
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 1.5))
	await wait_physics_frames(2)
	assert_eq(_target_health.current, 91, "first swing lands")
	await wait_physics_frames(3)
	assert_eq(_target_health.current, 91, "the next few frames must not land another")
	# Now let the cooldown run out and check that it swings again on its own.
	await wait_seconds(1.8)
	assert_eq(_target_health.current, 82, "and then it swings again")


func test_a_mob_stops_swinging_at_a_target_it_has_killed() -> void:
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 1.5))
	_target_health.apply_damage(95)  # down to 5
	await wait_physics_frames(10)
	assert_false(_target_health.is_alive(), "the target goes down")
	assert_eq(_target_health.current, 0, "and stays down rather than being hit past zero")


#endregion


#region Leashing -----------------------------------------------------------------

func test_a_mob_gives_up_a_chase_that_drags_it_too_far_from_home() -> void:
	var enemy: CharacterBody3D = _add_enemy(Vector3(0.0, 0.0, -4.0))
	enemy.leash_radius = 1.0
	_add_player(Vector3(0.0, 0.0, 4.0))
	# A second of physics at 2.6 m/s: comfortably past the 1m leash above, so this
	# is the walking that trips it rather than a first-frame decision.
	await wait_physics_frames(60)
	assert_null(enemy._target, "it should have dropped the target it chased too far")
	assert_lt(enemy.global_position.distance_to(Vector3(0.0, 0.0, -4.0)), 3.0,
			"and be heading back towards where it spawned")


func test_a_mob_that_just_gave_up_does_not_re_engage_the_same_target() -> void:
	# Without the sulk, the walk home puts it back inside its own aggro radius and it
	# visibly yo-yos: chase, leash, chase, leash. It should stay home instead.
	var enemy: CharacterBody3D = _add_enemy(Vector3(0.0, 0.0, -4.0))
	enemy.leash_radius = 1.0
	_add_player(Vector3(0.0, 0.0, 4.0))
	await wait_physics_frames(60)
	assert_gt(enemy._evade, 0.0, "it should be sulking")
	assert_null(enemy._target, "and ignoring the player it just broke off from")

	await wait_physics_frames(30)
	assert_null(enemy._target, "still ignoring them a moment later")


func test_the_sulk_wears_off_and_the_mob_pays_attention_again() -> void:
	var enemy: CharacterBody3D = _add_enemy()
	enemy._evade = 0.05
	_add_player(Vector3(0.0, 0.0, 4.0))
	await wait_physics_frames(6)
	assert_eq(enemy._evade, 0.0, "the sulk runs out")
	await wait_physics_frames(3)
	assert_not_null(enemy._target, "and by then the mob is looking for players again")


#endregion


#region Dying --------------------------------------------------------------------

func test_a_killing_blow_pays_the_killer_and_takes_the_body_out_of_the_world() -> void:
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 20.0))  # far away: this is not the mob's fight
	_enemy.health.apply_damage(999, 7)
	assert_eq(_target_state.progress.xp, _enemy.xp_reward,
		"the killer named in the hit is paid the mob's XP")
	assert_false(_enemy.visible, "and the fallen mob is out of the world")
	assert_false(_enemy.is_queued_for_deletion(),
		"nothing is despawned: a revival is only a change of hit points")


func test_a_mob_killed_by_nobody_pays_nobody() -> void:
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 20.0))
	_enemy.health.apply_damage(999)
	assert_eq(_target_state.progress.xp, 0, "no killer, no payment")


func test_the_health_bar_only_shows_once_something_has_happened() -> void:
	_add_enemy()
	_add_player(Vector3(0.0, 0.0, 20.0))
	var bar: MeshInstance3D = _enemy.get_node("HealthBar")
	assert_false(bar.visible, "a healthy mob shows no bar")
	_enemy.health.apply_damage(20)
	assert_true(bar.visible, "a wounded one does")
	assert_lt(bar.scale.x, 1.0, "and the bar is shorter than a full one")
	assert_true((_enemy.get_node("Nameplate") as Label3D).text.contains("Forest Wolf"),
		"and the nameplate carries the name")

#endregion