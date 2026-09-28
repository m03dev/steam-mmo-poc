class_name Level
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
## Client-only overview camera shown until the host spawns our own box.
var _fallback_cam: Camera3D = null

@onready var spawner: MultiplayerSpawner = $Spawner
@onready var players: Node3D = $Players
@onready var trigger: Area3D = $Trigger


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	trigger.body_entered.connect(_on_trigger_entered)
	# NOTE: Godot's default multiplayer_peer is an OfflineMultiplayerPeer, NOT
	# null. Testing `== null` alone would make every peer think it is the server,
	# so "are we actually connected to anyone?" must name that class explicitly.
	var offline: bool = multiplayer.multiplayer_peer == null \
			or multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	print("[Level/%s] ready | offline=%s server=%s my_id=%d" % [
			level_type, str(offline), str(multiplayer.is_server()), multiplayer.get_unique_id()])

	# Offline / editor: no real connection, so just spawn a local player.
	if offline:
		_spawn_local()
		return

	if multiplayer.is_server():
		# Host: it is the only peer that spawns; clients receive the spawns.
		multiplayer.peer_connected.connect(_spawn)
		multiplayer.peer_disconnected.connect(_despawn)
		_spawn(multiplayer.get_unique_id())
		for id in multiplayer.get_peers():
			_spawn(id)
	else:
		# Client: the host spawns our box and replicates it. Until that arrives
		# we would be staring at a black screen, so watch from a fixed overview
		# camera; our player's camera takes over the moment it spawns.
		_show_fallback_camera()


func _spawn_player(data: Variant) -> Node:
	print("[Level/%s] spawning player_%s" % [level_type, str(data)])
	var player: Node3D = PLAYER_SCENE.instantiate()
	var id: int = int(data)
	player.name = "player_%d" % id
	player.position = spawn_point + spawn_offset_for(id)
	_label_player(player, id)
	return player


## Deterministic per-peer offset: every peer derives the same spot from the id
## alone, so spawn positions agree across the network with no extra traffic.
## Static and pure, which also makes the spread unit-testable.
static func spawn_offset_for(peer_id: int) -> Vector3:
	return Vector3(float(peer_id % 4) * 2.0 - 3.0, 0.0, 0.0)


func _spawn(id: int) -> void:
	if id <= 0:
		return
	if players.has_node("player_%d" % id):
		return
	print("[Level/%s] server spawn request for %d" % [level_type, id])
	spawner.spawn(id)


func _despawn(id: int) -> void:
	var node: Node = players.get_node_or_null("player_%d" % id)
	if node != null:
		node.queue_free()


func _spawn_local() -> void:
	var player: Node3D = PLAYER_SCENE.instantiate()
	player.name = "player_1"
	player.position = spawn_point
	_label_player(player, 1)
	players.add_child(player)


## Float a coloured name tag over every player -- pure testing clarity, so it is
## obvious which character is yours and which belongs to the other peer.
func _label_player(player: Node3D, id: int) -> void:
	var label: Label3D = Label3D.new()
	label.name = "NameTag"
	label.text = "player_%d" % id
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.from_hsv(float(abs(id) % 12) / 12.0, 0.65, 1.0)
	label.position = Vector3(0.0, 2.15, 0.0)
	player.add_child(label)


## Client-side overview camera, used only until our own box is spawned by the
## host. Without it a just-joined client renders nothing at all.
func _show_fallback_camera() -> void:
	if _fallback_cam != null:
		return
	_fallback_cam = Camera3D.new()
	_fallback_cam.name = "FallbackCamera"
	_fallback_cam.position = Vector3(0.0, 12.0, 16.0)
	_fallback_cam.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	add_child(_fallback_cam)
	_fallback_cam.current = true


func _on_trigger_entered(body: Node3D) -> void:
	# Only the local owner reacts, and only once, so a body sitting in the
	# volume does not retrigger the transition every physics frame.
	if _transitioning:
		return
	if body is CharacterBody3D and multiplayer.multiplayer_peer != null \
			and body.is_multiplayer_authority():
		_transitioning = true
		var target: String = NetworkManager.TYPE_DUNGEON if level_type == NetworkManager.TYPE_WORLD else NetworkManager.TYPE_WORLD
		print("[Level] '%s' trigger hit -> transitioning to '%s'." % [level_type, target])
		NetworkManager.transition_to_lobby_type(target)