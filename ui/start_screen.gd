extends Control
## StartScreen -- the game's front door.
## ============================================================================
## Host or join a Steam lobby, or drop straight into an offline world to test
## without Steam. As soon as a session exists (or offline play is chosen) the
## game hands over to scenes/Main.tscn, which owns the level; this scene never
## loads a level itself.

const GAME_SCENE: String = "res://scenes/Main.tscn"
# Loaded by path rather than reached through the autoload instance, because the sentence below is a
# static function and calling it on an instance is a warning.
const STEAM_MANAGER := preload("res://autoload/SteamManager.gd")

@onready var _status: Label = %Status
@onready var _steam_banner: PanelContainer = %SteamBanner
@onready var _steam_problem: Label = %SteamProblem
@onready var _lobby_list_box: VBoxContainer = %LobbyListBox
@onready var _lobby_list_status: Label = %LobbyListStatus

## How often the server list asks Steam what is open. Slow enough to be free, fast enough that a
## friend you are waiting for appears while you are still looking at the menu.
const LIST_REFRESH_SECONDS: float = 4.0
var _lobby_timer: Timer = null

## Set from the command line, then consumed once Steam is ready. See
## _read_launch_action().
var _launch_action: String = ""


func _ready() -> void:
	%PlayButton.pressed.connect(_play)
	%OfflineButton.pressed.connect(_enter_game)
	%QuitButton.pressed.connect(get_tree().quit)
	# The two ways out of a failed Steam start, both live from the menu: open the client the
	# player probably has not started, and try again without relaunching the game.
	%OpenSteamButton.pressed.connect(SteamManager.open_steam_client)
	%SteamRetryButton.pressed.connect(SteamManager.retry)

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

	# The server list: rows a player can click, which is the whole point of it. A Timer rather
	# than a loop in _process, because this is for a human deciding, not a frame-rate concern,
	# and asking Steam every frame would cost something for nothing.
	%LobbyRefreshButton.pressed.connect(_refresh_lobbies)
	NetworkManager.lobby_list_updated.connect(_on_lobby_list_updated)
	_lobby_timer = Timer.new()
	_lobby_timer.wait_time = LIST_REFRESH_SECONDS
	_lobby_timer.timeout.connect(_refresh_lobbies)
	add_child(_lobby_timer)
	_lobby_timer.start()

	_launch_action = _read_launch_action()
	# SteamManager is an autoload, so it may already have resolved before this
	# scene ran; apply the current state rather than waiting for a signal.
	_on_steam_initialized(SteamManager.is_initialized)
	_refresh_lobbies()


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
	if not _steam_ready():
		return
	_set_status("Looking for an open world...")
	NetworkManager.auto_join_first_open(NetworkManager.TYPE_WORLD)


func _host(lobby_type: String) -> void:
	if not _steam_ready():
		return
	_set_status("Creating a public '%s' lobby..." % lobby_type)
	NetworkManager.create_lobby(lobby_type)


## There is deliberately NO override row any more: no Host New World, no Host Dungeon, no
## auto-join-a-dungeon, no join-by-lobby-id, no direct-IP fields. Mohamed's words were "all of that
## shouldn't be there, make it simple and minimal, get rid of the auto join dungeon". PLAY is
## join-or-host, which is the only decision a player actually has to make, and the open-world list
## is the only other one. The removed paths stay reachable from the command line for testing
## (--host-world, --host-dungeon, --host-direct, --join-direct=<address>), which is where they
## belong: they are for us, not for someone's first run.


## Whether a Steam-backed action can run, and the whole point of the fix.
##
## These buttons used to be DISABLED when Steam was not up, which is a dead end that teaches
## nobody anything: a friend whose Steam app was closed (being signed in to Steam in a browser is
## not the Steam client) saw five grey buttons and the sentence "Steam is offline - direct IP and
## offline play still work." Now every button stays pressable and answers with the real cause and
## the two things that fix it. A button that cannot work should say so, not vanish.
func _steam_ready() -> bool:
	if SteamManager.is_initialized:
		return true
	_show_steam_banner()
	return false


func _show_steam_banner() -> void:
	_steam_banner.visible = true
	_steam_problem.text = SteamManager.problem_hint if not SteamManager.problem_hint.is_empty() \
			else STEAM_MANAGER.start_problem(true, SteamManager.steam_client_running(), "")
	_set_status(_steam_problem.text)


## Host a direct-IP session: plain ENet, no Steam, no lobby. This is the path for
## someone who downloaded the game and does not use Steam at all.
func _host_direct() -> void:
	_set_status("Opening a direct session on UDP %d..." % NetworkManager.direct_port)
	NetworkManager.host_direct()


## Join by IP, from the command line only ("host", "host:port", or a bare IPv4 address). There is no
## address field on the menu any more, but the transport stays reachable for testing a LAN without
## Steam - which is the whole reason it exists.
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


## Ask Steam what is open, and answer immediately when there is nothing to ask with.
func _refresh_lobbies() -> void:
	if not SteamManager.is_initialized:
		_show_lobby_rows([])
		_lobby_list_status.text = lobby_list_status_text(0, false)
		return
	_lobby_list_status.text = lobby_list_status_text(-1, true)
	NetworkManager.refresh_lobby_list()


func _on_lobby_list_updated(summaries: Array[Dictionary]) -> void:
	_show_lobby_rows(summaries)
	_lobby_list_status.text = lobby_list_status_text(summaries.size(), true,
		joinable_count(summaries), mine_count(summaries))


## Rows rather than a sentence, because that is the difference between being told a world exists
## and being able to join it. Rebuilt on every refresh, so a world that closed disappears.
func _show_lobby_rows(summaries: Array[Dictionary]) -> void:
	for child: Node in _lobby_list_box.get_children():
		child.queue_free()
	for row: Dictionary in summaries:
		var button := Button.new()
		button.text = lobby_row_text(row)
		# Two rows are shown but not pressable, for the same reason: a click that is certain to
		# fail is not a choice. "mine" is the world you are already in - pressing it would mean
		# leaving and rejoining your own session - and an incompatible row is a friend on a build
		# you cannot enter. Both stay visible because both are information.
		button.disabled = bool(row.get("mine", false)) \
				or not bool(row.get("compatible", true))
		button.pressed.connect(_join_from_list.bind(int(row.get("id", 0))))
		_lobby_list_box.add_child(button)


## Clicking a row is the same intention as typing a lobby id, so it takes the same path - and the
## same gate, so a row press without Steam explains instead of doing nothing.
func _join_from_list(lobby_id: int) -> void:
	if not _steam_ready() or lobby_id == 0:
		return
	_set_status("Joining lobby %d..." % lobby_id)
	NetworkManager.join_lobby(lobby_id)


## One row's text. Pure, so the wording is testable without a lobby list to look at.
static func lobby_row_text(row: Dictionary) -> String:
	var owner_name: String = str(row.get("owner", ""))
	if owner_name.is_empty():
		owner_name = "Someone"
	# "name" is a Node property, so this local is named for what it is.
	var label: String = str(row.get("name", ""))
	if label.is_empty():
		label = "%s's world" % owner_name
	# Saying which build is useless without saying HOW it is useless: a friend on the old build
	# appearing in the list and then refusing the join is worse than not seeing them at all.
	if not bool(row.get("compatible", true)):
		return "%s  -  different version (%s)" % [label, str(row.get("version", "?"))]
	var members: int = int(row.get("members", 0))
	var maximum: int = int(row.get("max", 0))
	var text: String = label
	if maximum > 0 and members >= maximum:
		text += "  -  FULL (%d/%d)" % [members, maximum]
	else:
		text += "  -  %d/%d" % [members, maximum]
	# Who is actually in there. A player deciding between two worlds is deciding who to play with,
	# and a head-count alone cannot say that.
	var players: Array = row.get("players", [])
	if players.size() > 0:
		text += "  (%s)" % ", ".join(players)
	if bool(row.get("mine", false)):
		return "YOUR WORLD  -  %s" % text
	return text


## How many listed rows are worlds we can join. Our own is not one of them: we are already in it.
static func joinable_count(rows: Array[Dictionary]) -> int:
	var total: int = 0
	for row: Dictionary in rows:
		if bool(row.get("compatible", true)) and not bool(row.get("mine", false)):
			total += 1
	return total


## How many listed rows are the world we are already in - at most one, but counted rather than
## assumed, so a stale duplicate cannot silently make the menu lie.
static func mine_count(rows: Array[Dictionary]) -> int:
	var total: int = 0
	for row: Dictionary in rows:
		if bool(row.get("mine", false)):
			total += 1
	return total


## The line under the list. A count of -1 means the answer has not arrived yet, which is a
## different state from "there is nothing open" and must never read as one.
static func lobby_list_status_text(count: int, steam_ready: bool, joinable: int = -1,
		mine: int = 0) -> String:
	if not steam_ready:
		return "Sign in to the Steam app to see open worlds here."
	if count < 0:
		return "Looking for open worlds..."
	if count == 0:
		return "No open worlds yet. PLAY opens one, and friends will see it here."
	# A host cannot be shown their own world by Steam, so it is pinned above this list by hand.
	# When it is the only row, the honest line is not "none you can join" but "this is yours".
	if mine > 0 and joinable == 0:
		return "You are hosting a world - it is shown above. Friends see it in their list."
	# A list of worlds you cannot enter is not an invitation, so the line must not promise one.
	if joinable == 0:
		return "%d open world%s, but none this build can join - they are a different version." % [
			count, "" if count == 1 else "s"]
	return "%d open world%s - click one to join." % [count, "" if count == 1 else "s"]


func _on_steam_initialized(success: bool) -> void:
	# NO button is ever disabled here, on any branch. A disabled button cannot explain itself, and
	# the reason Steam is unavailable is the one thing the player needs to know: the buttons stay
	# pressable and answer through _steam_ready() with the real cause and the way out.
	#
	# Direct-IP play still runs without Steam from the command line, so this is not a gate on the
	# transport - the menu simply stops OFFERING it. Mohamed: "make it simple and minimal".
	var web_build: bool = OS.has_feature("web")

	if success:
		_steam_banner.visible = false
	else:
		_show_steam_banner()
	if web_build:
		_set_status("Browser build: single-player only (Play Offline). Steam multiplayer needs a "
				+ "downloaded desktop build.")
	if success:
		# A lobby Steam named at launch is a command, not an offer: a friend pressed
		# "Join Game" for us, which is not something to be asked about. Straight in.
		if NetworkManager.requested_lobby_id != 0:
			_set_status("Joining a friend (lobby %d)..." % NetworkManager.requested_lobby_id)
			NetworkManager.join_lobby(NetworkManager.requested_lobby_id)
			return
		if not web_build:
			_set_status("PLAY joins the open world, or opens one if nobody is playing.")
		if NetworkManager.lobby_visibility == NetworkManager.LobbyVisibility.FRIENDS_ONLY:
			# On a friends-only app the lobby list cannot see a friend's session, so say how to
			# get into one instead of letting PLAY quietly open a second.
			_set_status("PLAY opens a private world. Friends see it in their list, or join from "
					+ "the Steam friends list.")
		_run_launch_action()
	else:
		# Offline and direct play need no Steam, so a command-line launch of either still runs.
		if _launch_action == "--offline" or _launch_action == "--host-direct" \
				or _launch_action.begins_with("--join-direct"):
			_run_launch_action()


func _set_status(text: String) -> void:
	_status.text = text