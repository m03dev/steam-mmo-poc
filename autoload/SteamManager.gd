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
const APP_ID: int = 480

## ESteamAPIInitResult values, returned inside the dictionary from steamInitEx().
## NOTE: success is 0 here (not EResult's 1) because this is the *init* result
## enum, not the general Steam result enum.
const INIT_OK: int = 0
const INIT_NO_STEAM_CLIENT: int = 2

var is_initialized: bool = false
var steam_id: int = 0
var persona_name: String = ""
var last_error: String = ""


func _ready() -> void:
	_initialize()


func _initialize() -> void:
	# The GDExtension registers a global `Steam` object. If it is missing the
	# addon did not load (wrong platform binary, addon removed, etc.).
	if not Engine.has_singleton("Steam"):
		last_error = "GodotSteam singleton not available (addon not loaded?)"
		push_error("[SteamManager] " + last_error)
		steam_initialized.emit(false)
		return

	# embed_callbacks=false -> callbacks are NOT pumped for us, so we run
	# Steam.run_callbacks() ourselves in _process(). Returns a dictionary:
	#     { "status": int, "verbal": String }
	# where status == INIT_OK (0) means everything worked.
	var response: Dictionary = Steam.steamInitEx(APP_ID, false)
	var status: int = int(response.get("status", -1))
	var verbal: String = str(response.get("verbal", ""))

	if status != INIT_OK:
		is_initialized = false
		last_error = verbal if not verbal.is_empty() else "unknown error (status %d)" % status
		if status == INIT_NO_STEAM_CLIENT:
			push_warning("[SteamManager] Steam client is not running (App ID %d). " % APP_ID
					+ "Start Steam and log in to test multiplayer; local code still runs.")
		else:
			push_error("[SteamManager] Steam init failed: " + last_error)
		steam_initialized.emit(false)
		return

	is_initialized = true
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	print("[SteamManager] OK | GodotSteam v%s | App ID %d | user '%s' (%d)" % [
			Steam.get_godotsteam_version(), APP_ID, persona_name, steam_id])
	steam_initialized.emit(true)


func _process(_delta: float) -> void:
	# Pump Steam callbacks every frame. Without this, NO lobby or P2P signal
	# (lobby_created, lobby_joined, peer connections, ...) ever fires.
	if is_initialized:
		Steam.run_callbacks()


func _exit_tree() -> void:
	# Clean shutdown so the Steam client does not think we are still playing.
	if is_initialized:
		Steam.steamShutdown()
		is_initialized = false


## Small convenience used by UI/debug code.
func is_steam_available() -> bool:
	return is_initialized