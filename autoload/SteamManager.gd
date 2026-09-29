extends Node
## SteamManager -- Autoload singleton named "SteamManager".
## ============================================================================
## Owns the Steamworks lifecycle: initializes the API, pumps callbacks every
## frame, and exposes ONE source of truth for "is Steam usable?".
##
## No lobby or networking logic lives here -- that is NetworkManager's job.
##
## Everything downstream must check `SteamManager.is_initialized` (or await the
## `steam_initialized` signal) before calling any `Steam.*` function: calling
## Steamworks before a successful init is a hard error, not a silent no-op.

## Emitted once, after initialization is attempted. `success` tells you whether
## Steam is usable. Subscribers may also just read `is_initialized`.
signal steam_initialized(success: bool)

## 480 = "Spacewar", Valve's public test app. It grants every Steam user access
## to SDR / P2P relaying for free, so we can test real multiplayer today with no
## port forwarding and without owning a real App ID yet.
##
## It is only a DEFAULT. Every Spacewar user on Steam shares it, which is fine for
## two developers testing and wrong for handing a build to friends: the App ID has
## to be the game's own before a build leaves this machine. See `app_id` below.
const DEFAULT_DEV_APP_ID: int = 480

## The App ID this process is actually running as. Resolved before Steam init, from
## the first of these that answers:
##   1. `--appid=N`            a one-off run against a different app
##   2. steam_appid.txt        beside the executable, then the project root
##   3. 480                    the dev default
## Kept out of the code so switching to the real app is a file change, not an edit
## hunt: the Steam client hands a launched game its App ID, and a file is how you
## tell GodotSteam the same thing when it is started directly.
var app_id: int = DEFAULT_DEV_APP_ID

## ESteamAPIInitResult values, returned inside the dictionary from steamInitEx().
## NOTE: success is 0 here (not EResult's 1) because this is the *init* result
## enum, not the general Steam result enum.
const INIT_OK: int = 0
const INIT_NO_STEAM_CLIENT: int = 2

var is_initialized: bool = false
var steam_id: int = 0
var persona_name: String = ""
var last_error: String = ""
## The player-facing sentence for a failed start, set whenever init fails and read by the
## start screen. The menu used to invent its own wording, which is how a missing Steam
## client ended up described as "Steam is offline".
var problem_hint: String = ""
var _shutting_down: bool = false


func _ready() -> void:
	_initialize()


## True when this process is talking to Valve's shared test app. Anything that
## only makes sense for a real release -- a private lobby, a version shown to
## friends -- keys off this rather than off a hardcoded 480 scattered around.
func is_dev_app() -> bool:
	return app_id == DEFAULT_DEV_APP_ID


## Where the App ID comes from, in order. A command-line value wins so a run can be
## pointed at a different app without editing files; after that the conventional
## `steam_appid.txt`, beside the executable first (that is how a shipped build is
## configured) and then in the project (that is how it is configured in the editor).
func _resolve_app_id() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--appid="):
			var from_arg: int = int(arg.trim_prefix("--appid="))
			if from_arg > 0:
				return from_arg
	var exe_side: String = OS.get_executable_path().get_base_dir().path_join("steam_appid.txt")
	for path: String in [exe_side, "res://steam_appid.txt"]:
		var from_file: int = _read_app_id_file(path)
		if from_file > 0:
			return from_file
	return DEFAULT_DEV_APP_ID


func _read_app_id_file(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var text: String = FileAccess.get_file_as_string(path).strip_edges()
	# Ignore anything that is not a plain positive integer, including the comments
	# people leave in this file -- a malformed App ID must not silently become 480.
	if not text.is_valid_int():
		return 0
	var value: int = int(text)
	return value if value > 0 else 0


## True when the Steam CLIENT -- the app, signed in -- is running on this machine.
##
## This is the difference between "you are not signed in" and "Steam is not open at all", and it
## is the question a friend stuck at the menu actually has. It is also the distinction the old
## menu could not make: they were signed in to Steam *in a browser*, which is not the client, so
## every network button was dead and the only explanation pointed at the wrong cause.
func steam_client_running() -> bool:
	if not Engine.has_singleton("Steam"):
		return false
	return bool(Steam.isSteamRunning())


## The sentence a player needs when Steam did not come up.
##
## Pure on purpose: this is the substance of the reported dead end, and as a pure function every
## cause can be tested without a Steam client in any particular state.
static func start_problem(present: bool, client_running: bool, verbal: String) -> String:
	if not present:
		return ("The Steam add-on is missing from this build, so multiplayer cannot start. "
				+ "Play Offline still works.")
	if not client_running:
		return ("The Steam app is not running. Open Steam, sign in, then press Retry - "
				+ "you do not need to relaunch the game.")
	if not verbal.is_empty():
		return "Steam would not start: %s. Sign in to the Steam app, then press Retry." % verbal
	return "Steam did not start. Sign in to the Steam app, then press Retry."


## Try Steam again, without relaunching the game.
##
## A player who started the game before the Steam app had a dead end here: the only way out was
## to quit and launch again. Now the menu can fix itself, which is what the Retry button calls.
func retry() -> void:
	if is_initialized:
		steam_initialized.emit(true)
		return
	_initialize()


## Open the Steam client, best effort. If nothing on this machine handles the URL, the player
## still has the sentence above telling them what to do.
func open_steam_client() -> void:
	OS.shell_open("steam://open/")


func _initialize() -> void:
	# The GDExtension registers a global `Steam` object. If it is missing the
	# addon did not load (wrong platform binary, addon removed, etc.).
	if not Engine.has_singleton("Steam"):
		last_error = "GodotSteam singleton not available (addon not loaded?)"
		problem_hint = start_problem(false, false, "")
		push_error("[SteamManager] " + last_error)
		steam_initialized.emit(false)
		return

	app_id = _resolve_app_id()

	# embed_callbacks=false -> callbacks are NOT pumped for us, so we run
	# Steam.run_callbacks() ourselves in _process(). Returns a dictionary:
	#     { "status": int, "verbal": String }
	# where status == INIT_OK (0) means everything worked.
	var response: Dictionary = Steam.steamInitEx(app_id, false)
	var status: int = int(response.get("status", -1))
	var verbal: String = str(response.get("verbal", ""))

	if status != INIT_OK:
		is_initialized = false
		last_error = verbal if not verbal.is_empty() else "unknown error (status %d)" % status
		problem_hint = start_problem(true, steam_client_running(), verbal)
		if status == INIT_NO_STEAM_CLIENT:
			push_warning("[SteamManager] Steam client is not running (App ID %d). " % app_id
					+ "Start Steam and log in to test multiplayer; local code still runs.")
		else:
			push_error("[SteamManager] Steam init failed: " + last_error)
		steam_initialized.emit(false)
		return

	is_initialized = true
	problem_hint = ""
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	print("[SteamManager] OK | GodotSteam v%s | App ID %d%s | user '%s' (%d)" % [
			Steam.get_godotsteam_version(), app_id,
			" (DEV: Spacewar)" if is_dev_app() else "", persona_name, steam_id])
	steam_initialized.emit(true)


func _process(_delta: float) -> void:
	# Pump Steam callbacks every frame. Without this, NO lobby or P2P signal
	# (lobby_created, lobby_joined, peer connections, ...) ever fires.
	if is_initialized and not _shutting_down:
		Steam.run_callbacks()


func _exit_tree() -> void:
	_shutdown()


## Order matters here. The SteamMultiplayerPeer (and the Steam networking
## callbacks it drives) must be torn down BEFORE steamShutdown(); if it is still
## alive afterwards it touches SteamNetworkingSockets on a shut-down Steamworks
## and the whole process segfaults (signal 11).
func _shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager != null and network_manager.has_method("leave_lobby"):
		network_manager.leave_lobby()
	if is_initialized:
		Steam.steamShutdown()
		is_initialized = false


#region Peer identity -----------------------------------------------------------
#
# One place that answers "who is this peer, in human terms", so the name tag over
# a player, the dev HUD's PEERS rows and the NET row cannot drift apart.
#
# A peer id is an implementation detail: it is 1 for the host on every client, and
# a truncated number for everyone else. Nobody can confirm two players are two
# accounts from an id like that. The SteamID64 (7656119...) and Steam's own name
# for that account are the things a screenshot can actually prove, so both are
# shown wherever a peer is named.
#
# The two formatters are `static` and take their inputs as arguments ON PURPOSE:
# the shape of these strings is pinned by a unit test with no Steam running and no
# peer at all, which the live lookup functions could not be.

## The SteamID64 behind a multiplayer peer id, or 0 when there is no Steam identity
## to report (direct-IP/ENet session, Steam down, or a peer Steam does not know yet).
func peer_steam_id(peer_id: int) -> int:
	if not is_initialized:
		return 0
	# Our own peer id needs no lookup, and asking Steam about it is the one case
	# where a miss would mislabel the player looking at the screen.
	if peer_id == multiplayer.get_unique_id():
		return steam_id
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer is SteamMultiplayerPeer:
		return (peer as SteamMultiplayerPeer).get_steam_id_for_peer_id(peer_id)
	return 0


## Steam's name for an account, "" when it cannot be read (not a friend, no cache).
func persona_for(steam_id: int) -> String:
	if steam_id == 0 or not is_initialized:
		return ""
	return Steam.getFriendPersonaName(steam_id)


## "Zukei (76561198063757123)", or "player_7" for a peer with no Steam identity.
static func identity_text(peer_id: int, steam_id: int, persona: String) -> String:
	if steam_id == 0:
		return "player_%d" % peer_id
	if persona.is_empty():
		return str(steam_id)
	return "%s (%d)" % [persona, steam_id]


## The floating tag over a player, two lines so the long number never crowds the
## name: name on top, SteamID64 underneath, "(you)" on the local avatar. Falls back
## to the replication name in a session with no Steam behind it.
static func name_tag_text(peer_id: int, steam_id: int, persona: String, is_local: bool) -> String:
	if steam_id == 0:
		var bare: String = "player_%d" % peer_id
		if is_local:
			bare += "\n(you)"
		return bare
	var head: String = persona if not persona.is_empty() else "player_%d" % peer_id
	var tag: String = "%s\n%d" % [head, steam_id]
	if is_local:
		tag += "\n(you)"
	return tag


## The live version of the two formatters above, for a peer in this session.
func identity_for(peer_id: int) -> String:
	var sid: int = peer_steam_id(peer_id)
	return identity_text(peer_id, sid, persona_for(sid))


func name_tag_for(peer_id: int) -> String:
	var sid: int = peer_steam_id(peer_id)
	return name_tag_text(peer_id, sid, persona_for(sid), peer_id == multiplayer.get_unique_id())

#endregion


## Small convenience used by UI/debug code.
func is_steam_available() -> bool:
	return is_initialized