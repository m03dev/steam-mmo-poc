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

## Set from the command line, then consumed once Steam is ready. See
## _read_launch_action().
var _launch_action: String = ""


func _ready() -> void:
	%PlayButton.pressed.connect(_play)
	%HostWorldButton.pressed.connect(_host.bind(NetworkManager.TYPE_WORLD))
	%HostDungeonButton.pressed.connect(_host.bind(NetworkManager.TYPE_DUNGEON))
	%AutoDungeonButton.pressed.connect(_auto_join.bind(NetworkManager.TYPE_DUNGEON))
	_join_button.pressed.connect(_on_join_pressed)
	%OfflineButton.pressed.connect(_enter_game)
	%QuitButton.pressed.connect(get_tree().quit)

	NetworkManager.lobby_created.connect(_on_lobby_ready)
	NetworkManager.lobby_joined.connect(_on_lobby_ready)
	NetworkManager.lobby_create_failed.connect(_on_session_failed)
	NetworkManager.lobby_join_failed.connect(_on_session_failed)
	# A friend pressed "Join Game" for us while we were still sitting on this menu.
	# That is a complete instruction, so it bypasses the menu entirely.
	NetworkManager.join_invited.connect(_on_join_invited)
	SteamManager.steam_initialized.connect(_on_steam_initialized)

	_launch_action = _read_launch_action()
	_refresh_identity()
	# SteamManager is an autoload, so it may already have resolved before this
	# scene ran; apply the current state rather than waiting for a signal.
	_on_steam_initialized(SteamManager.is_initialized)


## Dev convenience: skip the menu from the command line, so a host can be left
## running unattended for other peers to auto-join.
##   Godot --path <project> res://ui/start_screen.tscn -- --host-world
## --host-dungeon, --play and --offline are accepted too.
func _read_launch_action() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for action: String in ["--host-world", "--host-dungeon", "--play", "--offline"]:
		if args.has(action):
			return action
	return ""


## Runs once, as soon as we know whether Steam is up. Offline play still works
## without Steam, so it is handled in both branches of _on_steam_initialized.
func _run_launch_action() -> void:
	var action: String = _launch_action
	_launch_action = ""
	match action:
		"--host-world":
			_host(NetworkManager.TYPE_WORLD)
		"--host-dungeon":
			_host(NetworkManager.TYPE_DUNGEON)
		"--play":
			_play()
		"--offline":
			_enter_game()


## The one button a player actually needs.
##
## PLAY joins the open world, and opens one if nobody is playing -- that join-or-
## host decision is already NetworkManager's, so this button is never a dead end
## and there is no "no servers found" state to explain. The buttons below it are
## the deliberate overrides.
func _play() -> void:
	_set_status("Looking for an open world...")
	NetworkManager.auto_join_first_open(NetworkManager.TYPE_WORLD)


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


## Someone invited us (or we accepted an invite) and Steam told us where to go.
## `accepted` is false when we could not act on it -- for instance when we are
## already hosting and joining would have dropped our own players.
func _on_join_invited(_steam_id: int, lobby_id: int, accepted: bool) -> void:
	if not accepted:
		_set_status("Invite ignored: already in a session of our own.")
		return
	_set_status("Joining a friend (lobby %d)..." % lobby_id)
	# _on_lobby_ready does the handover once Steam confirms, so nothing to do here.


func _enter_game() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_steam_initialized(success: bool) -> void:
	# Without Steam there is nothing to host or join with, so lock the network
	# controls and leave offline play as the way in.
	for button: Button in [%PlayButton, %HostWorldButton, %HostDungeonButton,
			%AutoDungeonButton, _join_button]:
		button.disabled = not success
	_lobby_id_input.editable = success
	if success:
		_set_status("PLAY joins the open world, or opens one if nobody is playing.")
		_run_launch_action()
	else:
		_set_status("Steam is offline - multiplayer disabled. Use Play Offline.")
		# Offline play needs nothing from Steam, so it can still start.
		if _launch_action == "--offline":
			_run_launch_action()


func _refresh_identity() -> void:
	if SteamManager.is_initialized:
		_identity.text = "Steam: %s   (id %d)" % [SteamManager.persona_name, SteamManager.steam_id]
	else:
		_identity.text = "Steam: not connected"


func _set_status(text: String) -> void:
	_status.text = text