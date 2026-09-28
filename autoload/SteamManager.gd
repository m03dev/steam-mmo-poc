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


func _initialize() -> void:
	# The GDExtension registers a global `Steam` object. If it is missing the
	# addon did not load (wrong platform binary, addon removed, etc.).
	if not Engine.has_singleton("Steam"):
		last_error = "GodotSteam singleton not available (addon not loaded?)"
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
		if status == INIT_NO_STEAM_CLIENT:
			push_warning("[SteamManager] Steam client is not running (App ID %d). " % app_id
					+ "Start Steam and log in to test multiplayer; local code still runs.")
		else:
			push_error("[SteamManager] Steam init failed: " + last_error)
		steam_initialized.emit(false)
		return

	is_initialized = true
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


## Small convenience used by UI/debug code.
func is_steam_available() -> bool:
	return is_initialized