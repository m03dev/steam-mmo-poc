extends Node3D
## Throwaway verification harness (NOT shipped).
## Tests the Step-5 LEVEL SWAP mechanics over plain ENet: two peers share a
## level, then both swap to the dungeon and back, and we check players respawn
## in the new level on both sides.

const WORLD: PackedScene = preload("res://scenes/World.tscn")
const DUNGEON: PackedScene = preload("res://scenes/Dungeon.tscn")

var _role: String = ""
var _holder: Node3D
var _type: String = "world"


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_role = "host" if args.has("--host") else "client"
	_holder = Node3D.new()
	_holder.name = "LevelHolder"
	add_child(_holder)
	var peer := ENetMultiplayerPeer.new()
	if _role == "host":
		peer.create_server(23457, 4)
		multiplayer.multiplayer_peer = peer
		_load("world")
		_schedule()
	else:
		peer.create_client("127.0.0.1", 23457)
		multiplayer.multiplayer_peer = peer
		await multiplayer.connected_to_server
		_load("world")


func _schedule() -> void:
	await get_tree().create_timer(6.0).timeout
	_swap.rpc("dungeon")
	await get_tree().create_timer(6.0).timeout
	_swap.rpc("world")


@rpc("authority", "call_local", "reliable")
func _swap(t: String) -> void:
	_load(t)


func _load(t: String) -> void:
	_type = t
	for c in _holder.get_children():
		c.queue_free()
	var scene: PackedScene = DUNGEON if t == "dungeon" else WORLD
	_holder.add_child(scene.instantiate())
	print("[p2/%s] loaded '%s'" % [_role, t])


func _process(_d: float) -> void:
	if Engine.get_process_frames() % 40 != 0:
		return
	var root_name: String = "Dungeon" if _type == "dungeon" else "World"
	var players: Node = _holder.get_node_or_null("%s/Players" % root_name)
	if players == null:
		return
	var parts: PackedStringArray = []
	for c in players.get_children():
		parts.append("%s@%s" % [c.name, str((c as Node3D).global_position.round())])
	print("[p2/%s] level=%s players=%d | %s" % [_role, _type, players.get_child_count(), " , ".join(parts)])