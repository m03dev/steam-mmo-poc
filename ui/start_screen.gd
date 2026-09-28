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
@onready var _direct_address_input: LineEdit = %DirectAddressInput

## Set from the command line, then consumed once Steam is ready. See
## _read_launch_action().
var _launch_action: String = ""


func _ready() -> void:
	%PlayButton.pressed.connect(_play)
	%HostWorldButton.pressed.connect(_host.bind(NetworkManager.TYPE_WORLD))
	%HostDungeonButton.pressed.connect(_host.bind(NetworkManager.TYPE_DUNGEON))
	%AutoDungeonButton.pressed.connect(_auto_join.bind(NetworkManager.TYPE_DUNGEON))
	_join_button.pressed.connect(_on_join_pressed)
	%DirectHostButton.pressed.connect(_host_direct)
	%DirectJoinButton.pressed.connect(_join_direct)
	%OfflineButton.pressed.connect(_enter_game)
	%QuitButton.pressed.connect(get_tree().quit)

	NetworkManager.lobby_created.connect(_on_lobby_ready)
	NetworkManager.lobby_joined.connect(_on_lobby_ready)
	NetworkManager.lobby_create_failed.connect(_on_session_failed)
	NetworkManager.lobby_join_failed.connect(_on_session_failed)
	# Direct (non-Steam) sessions have no lobby, so they report through their own
	# signal; `connection_failed` is the shared "the dial went nowhere" case.
	NetworkManager.direct_session_started.connect(_on_direct_session_started)
	NetworkManager.connection_failed.connect(_on_direct_failed)
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
	for action: String in ["--host-world", "--host-dungeon", "--play", "--offline",
			"--host-direct"]:
		if args.has(action):
			return action
	# --join-direct carries an address, so it is matched by prefix:
	#   --join-direct=192.168.1.20      (bare --join-direct means localhost)
	for arg: String in args:
		if arg.begins_with("--join-direct"):
			return arg
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
		"--host-direct":
			_host_direct()
		_:
			if action.begins_with("--join-direct"):
				_join_direct_to(action.trim_prefix("--join-direct").trim_prefix("="))


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


## Host a direct-IP session: plain ENet, no Steam, no lobby. This is the path for
## someone who downloaded the game and does not use Steam at all.
func _host_direct() -> void:
	_set_status("Opening a direct session on UDP %d..." % NetworkManager.direct_port)
	NetworkManager.host_direct()


## Join by IP. Accepts "host", "host:port", or a bare IPv4 address.
func _join_direct() -> void:
	_join_direct_to(_direct_address_input.text)


func _join_direct_to(spec: String) -> void:
	var parsed: Dictionary = NetworkManager.parse_direct_address(spec, NetworkManager.direct_port)
	var address: String = str(parsed["address"])
	if address.is_empty():
		# An empty field usually means "the host is this machine", which is exactly
		# what someone testing alone on one computer wants.
		address = "127.0.0.1"
	var port: int = int(parsed["port"])
	_set_status("Connecting to %s:%d..." % [address, port])
	NetworkManager.join_direct(address, port)


func _on_direct_session_started(is_host: bool) -> void:
	if is_host:
		_enter_game()
		return
	_set_status("Connecting to the host...")
	# Let ENet finish before entering the game. A client that starts the shell while
	# still disconnected briefly believes it is peer 1 -- which is the server -- and
	# the Steam path never sees that because joining a lobby means already connected.
	if not multiplayer.connected_to_server.is_connected(_on_direct_connected):
		multiplayer.connected_to_server.connect(_on_direct_connected)


func _on_direct_connected() -> void:
	if multiplayer.connected_to_server.is_connected(_on_direct_connected):
		multiplayer.connected_to_server.disconnect(_on_direct_connected)
	_enter_game()


## A direct dial that went nowhere. There is no lobby list to blame it on, so name
## the two things that actually cause it.
func _on_direct_failed() -> void:
	if not NetworkManager.is_direct_session():
		return
	_set_status("Could not reach the host. Check the IP, and that port %d is open on "
			% NetworkManager.direct_port
			+ "the host (LAN works as-is; the open internet needs it forwarded).")


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
	# Deferred, not immediate: change_scene_to_file() removes the current scene right
	# away, and the scene tree refuses to be modified while it is still busy adding
	# children -- which is exactly where a launch action is when it starts this from
	# _ready. The Steam path never showed the bug only because its signals arrive a
	# frame later; a direct host and --offline both hit it head-on.
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


func _on_steam_initialized(success: bool) -> void:
	# Without Steam there is nothing to host or join with, so lock the network
	# controls and leave offline play as the way in.
	for button: Button in [%PlayButton, %HostWorldButton, %HostDungeonButton,
			%AutoDungeonButton, _join_button]:
		button.disabled = not success
	_lobby_id_input.editable = success
	# The direct-IP controls are NOT gated on Steam -- they exist for people who have
	# no Steam at all. They are gated on the platform instead: a browser cannot open
	# a raw UDP socket, so ENet cannot exist in a web build, and offering it there
	# would be a button that can never work.
	var web_build: bool = OS.has_feature("web")
	%DirectHostButton.disabled = web_build
	%DirectJoinButton.disabled = web_build
	_direct_address_input.editable = not web_build
	if web_build:
		_set_status("Browser build: single-player only (Play Offline). Steam and "
				+ "direct-IP multiplayer need a downloaded desktop build.")
	if success:
		# A lobby Steam named at launch is a command, not an offer: a friend pressed
		# "Join Game" for us, which is not something to be asked about. Straight in.
		if NetworkManager.requested_lobby_id != 0:
			_set_status("Joining a friend (lobby %d)..." % NetworkManager.requested_lobby_id)
			NetworkManager.join_lobby(NetworkManager.requested_lobby_id)
			return
		_set_status("PLAY joins the open world, or opens one if nobody is playing.")
		if NetworkManager.lobby_visibility == NetworkManager.LobbyVisibility.FRIENDS_ONLY:
			# On a friends-only app the lobby list cannot see a friend's session, so
			# say how to get into one instead of letting PLAY quietly open a second.
			_set_status("PLAY opens a private world. Friends join from the Steam "
					+ "friends list, or by pasting the lobby id.")
		_run_launch_action()
	else:
		_set_status("Steam is offline - direct IP and offline play still work.")
		# Neither of these needs Steam, so either can still start.
		if _launch_action == "--offline" or _launch_action == "--host-direct" \
				or _launch_action.begins_with("--join-direct"):
			_run_launch_action()


func _refresh_identity() -> void:
	if SteamManager.is_initialized:
		_identity.text = "Steam: %s   (id %d)" % [SteamManager.persona_name, SteamManager.steam_id]
	else:
		_identity.text = "Steam: not connected"


func _set_status(text: String) -> void:
	_status.text = text