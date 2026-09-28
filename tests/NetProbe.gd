extends Node3D
## Throwaway verification harness (NOT shipped).
## Proves the MultiplayerSpawner + MultiplayerSynchronizer layer replicates over
## a plain ENet peer, independent of Steam. Run two copies of the project:
##   Godot --headless --path <proj> res://tests/NetProbe.tscn -- --host
##   Godot --headless --path <proj> res://tests/NetProbe.tscn -- --client

const LEVEL: PackedScene = preload("res://scenes/World.tscn")

var _role: String = ""


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_role = "host" if args.has("--host") else "client"
	var peer := ENetMultiplayerPeer.new()
	if _role == "host":
		peer.create_server(23456, 4)
		multiplayer.multiplayer_peer = peer
		print("[probe] HOST listening on 23456, id=%d" % multiplayer.get_unique_id())
		add_child(LEVEL.instantiate())
	else:
		peer.create_client("127.0.0.1", 23456)
		multiplayer.multiplayer_peer = peer
		print("[probe] CLIENT created, id pending")
		await multiplayer.connected_to_server
		print("[probe] CLIENT connected, id=%d" % multiplayer.get_unique_id())
		add_child(LEVEL.instantiate())
	multiplayer.peer_connected.connect(func(id: int) -> void:
		print("[probe/%s] peer_connected %d" % [_role, id]))
	multiplayer.connected_to_server.connect(func() -> void:
		print("[probe/%s] connected_to_server id=%d" % [_role, multiplayer.get_unique_id()]))


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 30 != 0:
		return
	var players: Node = get_node_or_null("World/Players")
	if players == null:
		return
	var parts: PackedStringArray = []
	for child in players.get_children():
		parts.append("%s pos=%s auth=%d" % [
				child.name, str((child as Node3D).global_position.round()), child.get_multiplayer_authority()])
	print("[probe/%s] players=%d | %s" % [_role, players.get_child_count(), " , ".join(parts)])