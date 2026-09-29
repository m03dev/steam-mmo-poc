extends Node3D
## Main -- the persistent game shell.
##
## Keeps the dev overlay alive and swaps the level underneath it when the
## networking session moves between lobby types (world <-> dungeon). Step 5 of
## the design: the scene change follows NetworkManager's `lobby_joined`, never
## the other way round.
##
## This scene is only ever reached with a session already established -- either
## the player picked a lobby on StartScreen, or chose offline play.

const WORLD: PackedScene = preload("res://scenes/World.tscn")
const DUNGEON: PackedScene = preload("res://scenes/Dungeon.tscn")
const ARENA: PackedScene = preload("res://scenes/Arena.tscn")

## Level key for the 1v1 arena. Not a lobby type: a match stays inside the SAME session
## and only swaps the scene underneath it, so nobody is ever re-lobbied mid-round.
const MATCH_LEVEL: String = "arena"

@onready var level_holder: Node3D = $Level


func _ready() -> void:
	# A peer that CREATES the target lobby emits `lobby_created`; a peer that
	# joins one emits `lobby_joined`. Both must swap the level, so listen to both.
	NetworkManager.lobby_joined.connect(_on_lobby_ready)
	NetworkManager.lobby_created.connect(_on_lobby_ready)
	# A 1v1 round swaps the level for the round and back; it never touches the session.
	Match.match_started.connect(_on_match_started)
	Match.match_ended.connect(_on_match_ended)
	_load_level(NetworkManager.current_lobby_type)


func _on_lobby_ready(_lobby_id: int) -> void:
	_load_level(NetworkManager.current_lobby_type)


## A round began: every peer swaps to the arena. The session is untouched.
func _on_match_started(_duration: float) -> void:
	_load_level(MATCH_LEVEL)


## The round ended: back to whatever level the session is on.
func _on_match_ended() -> void:
	_load_level(_lobby_level())


func _load_level(level_type: String) -> void:
	for child in level_holder.get_children():
		child.queue_free()
	var scene: PackedScene = WORLD
	var name_of_level: String = NetworkManager.TYPE_WORLD
	match level_type:
		NetworkManager.TYPE_DUNGEON:
			scene = DUNGEON
			name_of_level = NetworkManager.TYPE_DUNGEON
		MATCH_LEVEL:
			scene = ARENA
			name_of_level = MATCH_LEVEL
	level_holder.add_child(scene.instantiate())
	print("[Main] Loaded '%s' level." % name_of_level)


## Which level the SESSION calls for, as opposed to a match. An empty type means world:
## offline play and direct play have no lobby to have a type.
func _lobby_level() -> String:
	return NetworkManager.current_lobby_type if not NetworkManager.current_lobby_type.is_empty() \
			else NetworkManager.TYPE_WORLD