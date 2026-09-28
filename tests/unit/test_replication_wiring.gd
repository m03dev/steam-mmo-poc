extends GutTest

## Pins WHO is allowed to send which replicated property.
##
## Godot sends a MultiplayerSynchronizer's properties from that synchronizer's own
## multiplayer authority. A player node is owned by its player (so it can move),
## but its hit points and quest state are owned by the server. If both live in one
## synchronizer, the owning client becomes the sender for the server's own values
## and pushes its stale copy up -- the server's authoritative state gets clobbered
## by the peer it was supposed to be authoritative over.
##
## These tests fail loudly if that split is ever collapsed back into one
## synchronizer, or if a client-owned node's state synchronizer stops being
## server-authoritative.

const PLAYER_SCENE: String = "res://scenes/Player.tscn"
const ENEMY_SCENE: String = "res://scenes/Enemy.tscn"

## Peer id a client would have. Deliberately not 1, so "server" is distinguishable
## from "whatever authority happened to be default".
const CLIENT_ID: int = 42


func _paths(sync: MultiplayerSynchronizer) -> Array:
	var out: Array = []
	for path: NodePath in sync.replication_config.get_properties():
		out.append(String(path))
	out.sort()
	return out


func _player_owned_by(peer: int) -> Node:
	## Named before it enters the tree, so NetAdapter derives the owning peer from
	## the name exactly as it does in the running game.
	var player: Node = load(PLAYER_SCENE).instantiate()
	player.name = "player_%d" % peer
	add_child_autofree(player)
	return player


func test_movement_properties_belong_to_the_owner() -> void:
	var player: Node = _player_owned_by(CLIENT_ID)
	var sync: MultiplayerSynchronizer = player.get_node("Synchronizer")

	assert_eq(sync.get_multiplayer_authority(), CLIENT_ID,
		"the movement synchronizer must send from the peer that owns the body")
	var paths: Array = _paths(sync)
	assert_has(paths, ".:position", "position is the owner's to send")
	assert_has(paths, "VisualRoot:rotation", "facing is the owner's to send")


func test_state_properties_belong_to_the_server() -> void:
	var player: Node = _player_owned_by(CLIENT_ID)
	var state_sync: MultiplayerSynchronizer = player.get_node("Stats/StateSynchronizer")

	assert_eq(state_sync.get_multiplayer_authority(), 1,
		"a client-owned player's state synchronizer must still send from the server")
	assert_eq(player.get_node("Health").get_multiplayer_authority(), 1,
		"hit points are written by the server on every peer")


func test_movement_synchronizer_never_carries_server_state() -> void:
	var player: Node = load(PLAYER_SCENE).instantiate()
	add_child_autofree(player)

	var paths: Array = _paths(player.get_node("Synchronizer"))
	assert_false(paths.has("Stats:net_state"),
		"quest state must not ride the owner's synchronizer")
	assert_false(paths.has("Health:current"),
		"hit points must not ride the owner's synchronizer")


func test_state_synchronizer_carries_both_state_properties() -> void:
	var player: Node = load(PLAYER_SCENE).instantiate()
	add_child_autofree(player)

	var sync: MultiplayerSynchronizer = player.get_node("Stats/StateSynchronizer")
	assert_eq(sync.root_path, NodePath("../.."),
		"the state synchronizer's paths are written from the player root")
	var paths: Array = _paths(sync)
	assert_eq(paths, ["Health:current", "Stats:net_state"],
		"the server-owned synchronizer carries exactly the server-owned properties")

	for path: NodePath in sync.replication_config.get_properties():
		assert_true(sync.replication_config.property_get_spawn(path),
			"%s must be sent when a late joiner receives the player" % path)


func test_enemy_state_is_server_owned_and_self_describing() -> void:
	var enemy: Node = load(ENEMY_SCENE).instantiate()
	add_child_autofree(enemy)

	assert_eq(enemy.get_multiplayer_authority(), 1,
		"a mob's body is driven by the server, and says so on every peer")
	assert_eq(enemy.get_node("Health").get_multiplayer_authority(), 1,
		"a mob's hit points are the server's")

	var paths: Array = _paths(enemy.get_node("Synchronizer"))
	assert_has(paths, "Health:current",
		"a downed mob must look downed on every peer, so health has to replicate")