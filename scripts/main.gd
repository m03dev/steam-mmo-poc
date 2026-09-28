extends Node3D
## Main -- the persistent game shell.
##
## Keeps the debug LobbyUI alive and swaps the level underneath it when the
## networking session moves between lobby types (world <-> dungeon). Step 5 of
## the design: the scene change follows NetworkManager's `lobby_joined`, never
## the other way round.

const WORLD: PackedScene = preload("res://scenes/World.tscn")
const DUNGEON: PackedScene = preload("res://scenes/Dungeon.tscn")

@onready var level_holder: Node3D = $Level


func _ready() -> void:
	# A peer that CREATES the target lobby emits `lobby_created`; a peer that
	# joins one emits `lobby_joined`. Both must swap the level, so listen to both.
	NetworkManager.lobby_joined.connect(_on_lobby_ready)
	NetworkManager.lobby_created.connect(_on_lobby_ready)
	_load_level(NetworkManager.current_lobby_type)


func _on_lobby_ready(_lobby_id: int) -> void:
	_load_level(NetworkManager.current_lobby_type)


func _load_level(level_type: String) -> void:
	for child in level_holder.get_children():
		child.queue_free()
	var scene: PackedScene = DUNGEON if level_type == NetworkManager.TYPE_DUNGEON else WORLD
	level_holder.add_child(scene.instantiate())
	print("[Main] Loaded '%s' level." % ("dungeon" if level_type == NetworkManager.TYPE_DUNGEON else "world"))