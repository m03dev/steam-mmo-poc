extends Control
## StartScreen -- the game's front door.
## ============================================================================
## Host or join a Steam lobby, or drop straight into an offline world to test
## without Steam. As soon as a session exists (or offline play is chosen) the
## game hands over to scenes/Main.tscn, which owns the level; this scene never
## loads a level itself.

const GAME_SCENE: String = "res://scenes/Main.tscn"

@onready var _identity: Label = %Identity
@onready var _status: Label = %Status
@onready var _lobby_id_input: LineEdit = %LobbyIdInput
@onready var _join_button: Button = %JoinButton


func _ready() -> void:
	%HostWorldButton.pressed.connect(_host.bind(NetworkManager.TYPE_WORLD))
	%HostDungeonButton.pressed.connect(_host.bind(NetworkManager.TYPE_DUNGEON))
	%AutoWorldButton.pressed.connect(_auto_join.bind(NetworkManager.TYPE_WORLD))
	%AutoDungeonButton.pressed.connect(_auto_join.bind(NetworkManager.TYPE_DUNGEON))
	_join_button.pressed.connect(_on_join_pressed)
	%OfflineButton.pressed.connect(_enter_game)
	%QuitButton.pressed.connect(get_tree().quit)

	NetworkManager.lobby_created.connect(_on_lobby_ready)
	NetworkManager.lobby_joined.connect(_on_lobby_ready)
	NetworkManager.lobby_create_failed.connect(_on_session_failed)
	NetworkManager.lobby_join_failed.connect(_on_session_failed)
	SteamManager.steam_initialized.connect(_on_steam_initialized)

	_refresh_identity()
	# SteamManager is an autoload, so it may already have resolved before this
	# scene ran; apply the current state rather than waiting for a signal.
	_on_steam_initialized(SteamManager.is_initialized)


func _host(lobby_type: String) -> void:
	_set_status("Creating a public '%s' lobby..." % lobby_type)
	NetworkManager.create_lobby(lobby_type)


func _auto_join(lobby_type: String) -> void:
	_set_status("Looking for an open '%s' lobby..." % lobby_type)
	NetworkManager.auto_join_first_open(lobby_type)


func _on_join_pressed() -> void:
	var text: String = _lobby_id_input.text.strip_edges()
	if not text.is_valid_int():
		_set_status("Enter a numeric Lobby ID first.")
		return
	_set_status("Joining lobby %s..." % text)
	NetworkManager.join_lobby(int(text))


## A lobby was created or joined -- the session now exists, so start the game.
func _on_lobby_ready(_lobby_id: int) -> void:
	_enter_game()


func _on_session_failed(reason: String) -> void:
	_set_status(reason)


func _enter_game() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_steam_initialized(success: bool) -> void:
	# Without Steam there is nothing to host or join with, so lock the network
	# controls and leave offline play as the way in.
	for button: Button in [%HostWorldButton, %HostDungeonButton,
			%AutoWorldButton, %AutoDungeonButton, _join_button]:
		button.disabled = not success
	_lobby_id_input.editable = success
	if success:
		_set_status("Steam ready. Host a world, or join one with a Lobby ID.")
	else:
		_set_status("Steam is offline - multiplayer disabled. Use Play Offline.")


func _refresh_identity() -> void:
	if SteamManager.is_initialized:
		_identity.text = "Steam: %s   (id %d)" % [SteamManager.persona_name, SteamManager.steam_id]
	else:
		_identity.text = "Steam: not connected"


func _set_status(text: String) -> void:
	_status.text = text