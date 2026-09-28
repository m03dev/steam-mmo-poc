extends GutTest
## Tests for the deterministic spawn spread both levels share.

## Preloaded rather than referenced through class_name, so this suite does not
## depend on the global class cache being warm.
const LevelScript: GDScript = preload("res://scripts/level.gd")


func test_spawn_offset_is_deterministic() -> void:
	for peer_id: int in [1, 2, 3, 4, 42]:
		assert_eq(LevelScript.spawn_offset_for(peer_id),
				LevelScript.spawn_offset_for(peer_id),
				"the same peer id must always land on the same spot")


func test_first_four_peers_get_four_distinct_spots() -> void:
	var seen: Dictionary = {}
	for peer_id: int in [1, 2, 3, 4]:
		seen[LevelScript.spawn_offset_for(peer_id)] = true
	assert_eq(seen.size(), 4, "peers must not spawn inside each other")


func test_spawn_offset_keeps_peers_clearly_apart() -> void:
	for peer_id: int in [1, 2, 3]:
		var here: Vector3 = LevelScript.spawn_offset_for(peer_id)
		var next: Vector3 = LevelScript.spawn_offset_for(peer_id + 1)
		assert_gt(absf(next.x - here.x), 1.0, "spawns need a gap wider than the avatar")


func test_spawn_offset_wraps_after_four_peers() -> void:
	assert_eq(LevelScript.spawn_offset_for(5), LevelScript.spawn_offset_for(1))
	assert_eq(LevelScript.spawn_offset_for(8), LevelScript.spawn_offset_for(4))


func test_spawn_offset_never_lifts_a_peer_off_the_ground() -> void:
	for peer_id: int in [1, 2, 3, 4]:
		assert_eq(LevelScript.spawn_offset_for(peer_id).y, 0.0,
				"the level's spawn_point owns the height")