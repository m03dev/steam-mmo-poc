extends Node3D
## Level -- blockout used for both the open world and the dungeon.
##
## The host (Godot server) owns the MultiplayerSpawner and is the only peer that
## spawns players. Each spawned player is named "player_<peer_id>" so every peer
## derives the same authority. Walking into $Trigger starts a lobby transition
## (the network half lives in NetworkManager; the level swap lives in main.gd).

@export var level_type: String = "world"
## Where players appear in this level. Spread out per peer so two boxes never
## spawn inside each other (which makes physics fling them apart).
@export var spawn_point: Vector3 = Vector3(0.0, 1.0, 0.0)

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")

var _transitioning: bool = false

@onready var spawner: MultiplayerSpawner = $Spawner
@onready var players: Node3D = $Players
@onready var trigger: Area3D = $Trigger


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	trigger.body_entered.connect(_on_trigger_entered)

	# Offline / editor: no peer, so just spawn a local player to walk around.
	if multiplayer.multiplayer_peer == null:
		_spawn_local()
		return

	# Only the server spawns; clients receive the spawns.
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_spawn)
		multiplayer.peer_disconnected.connect(_despawn)
		_spawn(multiplayer.get_unique_id())
		for id in multiplayer.get_peers():
			_spawn(id)


func _spawn_player(data: Variant) -> Node:
	var player: Node3D = PLAYER_SCENE.instantiate()
	var id: int = int(data)
	player.name = "player_%d" % id
	# Deterministic per-peer offset: every peer computes the same spot, so the
	# spawn position agrees across the network without extra traffic.
	player.position = spawn_point + Vector3(float(id % 4) * 2.0 - 3.0, 0.0, 0.0)
	return player


func _spawn(id: int) -> void:
	if id <= 0:
		return
	if players.has_node("player_%d" % id):
		return
	spawner.spawn(id)


func _despawn(id: int) -> void:
	var node: Node = players.get_node_or_null("player_%d" % id)
	if node != null:
		node.queue_free()


func _spawn_local() -> void:
	var player: Node3D = PLAYER_SCENE.instantiate()
	player.name = "player_1"
	player.position = spawn_point
	players.add_child(player)


func _on_trigger_entered(body: Node3D) -> void:
	# Only the local owner reacts, and only once, so a body sitting in the
	# volume does not retrigger the transition every physics frame.
	if _transitioning:
		return
	if body is CharacterBody3D and body.is_multiplayer_authority():
		_transitioning = true
		var target: String = NetworkManager.TYPE_DUNGEON if level_type == NetworkManager.TYPE_WORLD else NetworkManager.TYPE_WORLD
		print("[Level] '%s' trigger hit -> transitioning to '%s'." % [level_type, target])
		NetworkManager.transition_to_lobby_type(target)