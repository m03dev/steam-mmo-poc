extends Node
## NetworkManager -- Autoload singleton named "NetworkManager".
## ============================================================================
## Owns the Steam lobby layer and bridges it onto Godot's HIGH-LEVEL
## multiplayer. Everything else (spawning, synchronizers, scenes) keeps talking
## to the normal `multiplayer` API -- this class only decides *who* we connect
## to. Swapping Steam for something else later means rewriting only this file.
##
## Two-layer design (seamless MMO feel, no server browser):
##   * "world"   lobby -> the shared open world, max MAX_MEMBERS players.
##   * "dungeon" lobby -> a private instance, max MAX_MEMBERS players.
## A player auto-joins the first open lobby of the wanted type, or creates one
## if none exists.
##
## All Steam lobby calls here are ASYNCHRONOUS: createLobby/joinLobby/
## requestLobbyList return nothing and deliver their result through the Steam
## signals handled at the bottom of this file.

signal lobby_created(lobby_id: int)
signal lobby_create_failed(reason: String)
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(reason: String)
signal lobby_list_received(lobbies: Array)
signal lobby_left
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed

const MAX_MEMBERS: int = 8

## Steam lobby metadata keys (stored as strings inside the lobby's data).
const KEY_TYPE: String = "lobby_type"
const KEY_VERSION: String = "game_version"
const KEY_PROTOCOL: String = "protocol"

## The release this build is. `tools/release.sh` keeps it in step with res://VERSION.
## It is baked in as a const on purpose: res://VERSION is a loose text file that may
## not be packed into an exported build, whereas a const always is. Published in the
## lobby and in each member's own data, so both sides can read what they are talking to.
const GAME_VERSION: String = "0.0006"

## Wire-protocol revision. Bump this when - and only when - the set of @rpc methods
## or their signatures changes. Two builds with the same protocol talk to each other
## whatever their version strings say, and a real mismatch is reported on join
## instead of surfacing later as a phantom bug.
const PROTOCOL_VERSION: int = 1

## Steam lobby metadata keys that let the HOST choose how the socket is opened and
## the CLIENT obey it, so only one end is ever configured.
const KEY_TRANSPORT: String = "transport"
const KEY_VPORT: String = "vport"

## How the SDR socket gets opened. Both go through SteamNetworkingSockets P2P; they
## differ in WHO decides the virtual port, and a mismatch there means the client
## dials a socket the host never opened - with no error on either side.
enum Transport {
	## host_with_lobby() / connect_to_lobby(): the lobby-bound helpers, which pick
	## the port themselves. This is what the project shipped with.
	LOBBY_HELPERS,
	## create_host() / create_client(): the documented siblings, with a port both
	## ends name explicitly.
	CANONICAL,
}

## Virtual port used in CANONICAL mode. SteamNetworkingSockets uses it only to
## demultiplex on the receiving side - it is not an OS port - but both ends must
## name the SAME number. Overridable with --vport=N.
const DEFAULT_VIRTUAL_PORT: int = 4800

## Steam result code: EResult.k_EResultOK == 1. Used to validate the async
## lobby create/join "tells". NOTE: the lobby *type* is passed as Steam's own
## enum (Steam.LOBBY_TYPE_PUBLIC), not a literal -- GDScript enforces the type.
const RESULT_OK: int = 1

## The two lobby "types" that back the two layers.
const TYPE_WORLD: String = "world"
const TYPE_DUNGEON: String = "dungeon"

var peer: SteamMultiplayerPeer = null
var current_lobby_id: int = 0
var current_lobby_type: String = ""
var is_host: bool = false

## Transport actually in use. The host picks it and publishes it in the lobby; a
## joiner reads the host's choice and matches it, so the two can never disagree.
var transport: Transport = Transport.LOBBY_HELPERS
var virtual_port: int = DEFAULT_VIRTUAL_PORT

## Peer diagnostics. 0 is off; set it with --steam-debug=N and the extension prints
## what SteamNetworkingSockets is doing - the only way to see a silently mismatched
## socket, since a failed P2P dial reports no error at all.
var steam_debug_level: int = 0

# Book-keeping for the async Steam calls.
var _pending_create_type: String = ""
var _pending_autojoin_type: String = ""

## How many times to re-check the lobby list before giving up and hosting. Stops
## two peers launched at the same instant from each seeing an empty list and
## hosting two separate lobbies they can never meet in.
const AUTOJOIN_RETRIES: int = 2
var _autojoin_attempt: int = 0


func _ready() -> void:
	# Identity first, so every log carries the build that produced it.
	print("[NetworkManager] SteamMMO v%s | netcode protocol %d" % [GAME_VERSION, PROTOCOL_VERSION])
	_parse_transport_args()
	# MultiplayerAPI signal, not the peer's, so this survives every peer swap.
	multiplayer.peer_connected.connect(_on_multiplayer_peer_connected)

	# Steam-side signals: lobby results.
	if Engine.has_singleton("Steam"):
		Steam.lobby_created.connect(_on_steam_lobby_created)
		Steam.lobby_joined.connect(_on_steam_lobby_joined)
		Steam.lobby_match_list.connect(_on_steam_lobby_match_list)
	# Godot-side signals: peer join/leave + connection state. These live on the
	# default MultiplayerAPI and stay valid even as we swap the underlying peer.
	var api: MultiplayerAPI = multiplayer
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	api.connected_to_server.connect(_on_connected_to_server)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_disconnected)


#region Public API -------------------------------------------------------------

## Create a new PUBLIC lobby of `lobby_type` and host it. Result arrives via the
## `lobby_created` / `lobby_create_failed` signals.
func create_lobby(lobby_type: String) -> void:
	if not _require_steam("create_lobby"):
		return
	if current_lobby_id != 0:
		push_warning("[NetworkManager] Already in lobby %d; leave first." % current_lobby_id)
		return
	_pending_create_type = lobby_type
	print("[NetworkManager] Creating public lobby (type='%s', max=%d)..." % [lobby_type, MAX_MEMBERS])
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_MEMBERS)  # async


## Join an existing lobby by its Steam lobby ID. Result arrives via the
## `lobby_joined` / `lobby_join_failed` signals.
func join_lobby(lobby_id: int) -> void:
	if not _require_steam("join_lobby"):
		return
	if current_lobby_id != 0:
		push_warning("[NetworkManager] Already in lobby %d; leave first." % current_lobby_id)
		return
	print("[NetworkManager] Requesting to join lobby %d..." % lobby_id)
	Steam.joinLobby(lobby_id)  # async


## Ask Steam for the lobby list. Results arrive via `lobby_list_received`.
func request_lobby_list() -> void:
	if not _require_steam("request_lobby_list"):
		return
	Steam.requestLobbyList()  # async -> _on_steam_lobby_match_list


## Join the first open lobby of `lobby_type`, or create one if none exists.
## This is the "just works" entry point the shipped game calls on launch.
func auto_join_first_open(lobby_type: String) -> void:
	if not _require_steam("auto_join_first_open"):
		return
	_pending_autojoin_type = lobby_type
	_autojoin_attempt = 0
	print("[NetworkManager] Auto-join: looking for an open '%s' lobby..." % lobby_type)
	Steam.requestLobbyList()  # async -> _on_steam_lobby_match_list


## Fully tear the current session down: detach Godot's multiplayer, close the
## SDR peer, and leave the Steam lobby.
func leave_lobby() -> void:
	# ORDER MATTERS: detach from Godot's multiplayer FIRST so nothing tries to
	# send packets over a peer we are about to close; then close the peer; then
	# tell Steam we left. Reversing this can leave remote peers hanging on a
	# dead ID and produces "Trying to send to a removed peer" spam.
	if peer != null:
		# `multiplayer` is null once this node is out of the tree, which is the
		# state we are in when SteamManager tears us down from _exit_tree.
		# Detaching is only an optimisation; CLOSING THE PEER is the part that
		# matters -- skip the detach and still close, or Steam shuts down with a
		# live SDR peer and the process segfaults on exit.
		if multiplayer != null:
			multiplayer.multiplayer_peer = null
		peer.close()
		peer = null
	var was_in_lobby: bool = current_lobby_id != 0
	if was_in_lobby:
		Steam.leaveLobby(current_lobby_id)
		print("[NetworkManager] Left lobby %d." % current_lobby_id)
	current_lobby_id = 0
	current_lobby_type = ""
	is_host = false
	if was_in_lobby:
		lobby_left.emit()


## Network half of the world<->dungeon transition.
##
## Step 5 calls this; the actual level/scene swap happens THERE, not here. This
## function only moves the networking session to a lobby of the new type.
##
## EXACT order (do not reorder -- this is the make-or-break part):
##   1. leave_lobby()               -> full teardown of the old session.
##   2. auto_join_first_open(type)  -> discover + join, or host, the target.
func transition_to_lobby_type(new_type: String) -> void:
	if not _require_steam("transition_to_lobby_type"):
		return
	print("[NetworkManager] Transition '%s' -> '%s'." % [current_lobby_type, new_type])
	leave_lobby()
	auto_join_first_open(new_type)


## Number of players currently in our lobby (0 if not in one).
func get_player_count() -> int:
	if current_lobby_id == 0:
		return 0
	return Steam.getNumLobbyMembers(current_lobby_id)


## Steam IDs of every member in our lobby.
func get_lobby_ids() -> Array[int]:
	var ids: Array[int] = []
	if current_lobby_id != 0:
		var count: int = Steam.getNumLobbyMembers(current_lobby_id)
		for i in count:
			ids.append(Steam.getLobbyMemberByIndex(current_lobby_id, i))
	return ids

#endregion


#region Steam callback handlers ------------------------------------------------

func _on_steam_lobby_created(connect_result: int, lobby_id: int) -> void:
	if connect_result != RESULT_OK:
		var reason: String = "Steam could not create the lobby (EResult %d)." % connect_result
		push_error("[NetworkManager] " + reason)
		lobby_create_failed.emit(reason)
		return

	current_lobby_id = lobby_id
	current_lobby_type = _pending_create_type
	is_host = true

	# Tag the lobby BEFORE hosting so joiners can find/identify it by type.
	Steam.setLobbyData(lobby_id, KEY_TYPE, current_lobby_type)
	Steam.setLobbyData(lobby_id, KEY_VERSION, GAME_VERSION)
	Steam.setLobbyData(lobby_id, KEY_PROTOCOL, str(PROTOCOL_VERSION))
	Steam.setLobbyMemberLimit(lobby_id, MAX_MEMBERS)
	Steam.setLobbyJoinable(lobby_id, true)
	Steam.setLobbyMemberData(lobby_id, "name", SteamManager.persona_name)
	_publish_member_build(lobby_id)
	# The host decides how the socket is opened and the joiners follow, so only one
	# end is ever configured and the two cannot disagree about the virtual port.
	Steam.setLobbyData(lobby_id, KEY_TRANSPORT,
			"canonical" if transport == Transport.CANONICAL else "lobby")
	Steam.setLobbyData(lobby_id, KEY_VPORT, str(virtual_port))

	# Create the SDR peer and host it on this lobby.
	peer = _make_peer()
	var err: int = OK
	if transport == Transport.CANONICAL:
		err = peer.create_host(virtual_port)
		print("[NetworkManager] host: create_host(%d)" % virtual_port)
	else:
		err = peer.host_with_lobby(lobby_id)
		print("[NetworkManager] host: host_with_lobby(%d)" % lobby_id)
	if err != OK:
		var reason: String = "SteamMultiplayerPeer host failed (error %d)." % err
		push_error("[NetworkManager] " + reason)
		Steam.leaveLobby(lobby_id)
		current_lobby_id = 0
		current_lobby_type = ""
		is_host = false
		peer = null
		lobby_create_failed.emit(reason)
		return

	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] Hosting '%s' lobby %d. My peer id: %d." % [
			current_lobby_type, lobby_id, multiplayer.get_unique_id()])
	lobby_created.emit(lobby_id)


func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# HOSTING GOTCHA: Steam fires LobbyCreated_t and THEN LobbyEnter_t when you
	# create a lobby, so GodotSteam emits BOTH lobby_created and lobby_joined for
	# the SAME lobby. _on_steam_lobby_created has already hosted it; trying to
	# connect_to_lobby on top of our own listen socket fails (ERR_CANT_CREATE,
	# error 20) and then tears the good session down. Ignore a "join" of the
	# lobby we are already in.
	if current_lobby_id != 0 and current_lobby_id == lobby_id:
		return
	if response != RESULT_OK:
		var reason: String = "Steam refused the join (EResult %d)." % response
		push_error("[NetworkManager] " + reason)
		lobby_join_failed.emit(reason)
		return

	current_lobby_id = lobby_id
	current_lobby_type = Steam.getLobbyData(lobby_id, KEY_TYPE)
	is_host = false
	Steam.setLobbyMemberData(lobby_id, "name", SteamManager.persona_name)
	_publish_member_build(lobby_id)
	_report_host_build(lobby_id)
	# Obey the host's transport choice, so a joiner needs no flags of its own.
	if Steam.getLobbyData(lobby_id, KEY_TRANSPORT) == "canonical":
		transport = Transport.CANONICAL
	var published_port: String = Steam.getLobbyData(lobby_id, KEY_VPORT)
	if published_port != "":
		virtual_port = int(published_port)

	peer = _make_peer()
	var err: int = OK
	if transport == Transport.CANONICAL:
		var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
		err = peer.create_client(host_steam_id, virtual_port)
		print("[NetworkManager] client: create_client(%d, %d)" % [host_steam_id, virtual_port])
	else:
		err = peer.connect_to_lobby(lobby_id)
		print("[NetworkManager] client: connect_to_lobby(%d)" % lobby_id)
	if err != OK:
		var reason: String = "SteamMultiplayerPeer connect failed (error %d)." % err
		push_error("[NetworkManager] " + reason)
		Steam.leaveLobby(lobby_id)
		current_lobby_id = 0
		current_lobby_type = ""
		peer = null
		lobby_join_failed.emit(reason)
		return

	multiplayer.multiplayer_peer = peer
	print("[NetworkManager] Joined '%s' lobby %d. My peer id: %d." % [
			current_lobby_type, lobby_id, multiplayer.get_unique_id()])
	lobby_joined.emit(lobby_id)


#region Build identity -----------------------------------------------------------

## Tell the rest of the lobby which build this is. Member data is read by the host
## when someone connects, so a mismatch is visible from the host's own log.
func _publish_member_build(lobby_id: int) -> void:
	Steam.setLobbyMemberData(lobby_id, "version", GAME_VERSION)
	Steam.setLobbyMemberData(lobby_id, "protocol", str(PROTOCOL_VERSION))


## Read the HOST's advertised build and print it beside our own. The host's copy is
## lobby data written before hosting, so it is the one side of the comparison that
## is reliably available the moment we join.
func _report_host_build(lobby_id: int) -> void:
	var host_game: String = Steam.getLobbyData(lobby_id, KEY_VERSION)
	var host_protocol: String = Steam.getLobbyData(lobby_id, KEY_PROTOCOL)
	print("[NetworkManager] Build check - host: game %s protocol %s | ours: game %s protocol %d" % [
			host_game if host_game != "" else "unknown",
			host_protocol if host_protocol != "" else "unknown",
			GAME_VERSION, PROTOCOL_VERSION])
	if host_protocol != "" and int(host_protocol) != PROTOCOL_VERSION:
		push_error("[NetworkManager] BUILD MISMATCH: host speaks protocol %s, this build speaks %d. The @rpc set differs, so one of the two is stale." % [
				host_protocol, PROTOCOL_VERSION])


## Host side: say who attached and what they claimed to be. What the peer published
## may not have reached us yet, so "unreported" is not a failure - the peer's own
## "Build check" line is the authoritative one.
func _on_multiplayer_peer_connected(peer_id: int) -> void:
	if not is_host or current_lobby_id == 0:
		return
	var steam_id: int = 0
	if peer is SteamMultiplayerPeer:
		steam_id = (peer as SteamMultiplayerPeer).get_steam_id_for_peer_id(peer_id)
	var who: String = "peer %d" % peer_id
	var build: String = "unreported"
	if steam_id != 0:
		who = Steam.getFriendPersonaName(steam_id)
		var their_game: String = Steam.getLobbyMemberData(current_lobby_id, steam_id, "version")
		var their_protocol: String = Steam.getLobbyMemberData(current_lobby_id, steam_id, "protocol")
		if their_game != "" or their_protocol != "":
			build = "game %s protocol %s" % [their_game, their_protocol]
	print("[NetworkManager] %s attached (peer %d, steamid %d) - its build: %s" % [
			who, peer_id, steam_id, build])
	if build.contains("protocol") and not build.ends_with(str(PROTOCOL_VERSION)):
		push_error("[NetworkManager] BUILD MISMATCH on peer %d: it reports %s, we speak protocol %d." % [
				peer_id, build, PROTOCOL_VERSION])

#endregion


#region Transport ---------------------------------------------------------------

## Transport flags, read from this process's own command line.
##
##   --transport-canonical   use create_host/create_client instead of the lobby helpers
##   --transport-lobby       force the lobby helpers (the shipped default)
##   --vport=N               virtual port for canonical mode (both ends must match)
##   --steam-debug=N         let the extension print SDR diagnostics
##
## Only the HOST needs these: a joiner reads the host's choice out of the lobby. That
## is deliberate - the client half is the half we cannot test on our own machines, so
## it must not depend on anyone remembering to pass a flag.
func _parse_transport_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--transport-canonical":
			transport = Transport.CANONICAL
		elif arg == "--transport-lobby":
			transport = Transport.LOBBY_HELPERS
		elif arg.begins_with("--vport="):
			virtual_port = int(arg.trim_prefix("--vport="))
		elif arg.begins_with("--steam-debug="):
			steam_debug_level = int(arg.trim_prefix("--steam-debug="))
	if transport == Transport.CANONICAL or steam_debug_level > 0:
		print("[NetworkManager] transport=%s virtual_port=%d steam_debug=%d" % [
				"canonical" if transport == Transport.CANONICAL else "lobby-helpers",
				virtual_port, steam_debug_level])


## The single place a peer is configured, so host and client cannot drift apart.
func _make_peer() -> SteamMultiplayerPeer:
	var new_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	new_peer.set_server_relay(true)  # force Valve relay: no port forwarding, no NAT pain
	if steam_debug_level > 0:
		new_peer.set_debug_level(steam_debug_level)
	return new_peer

#endregion


func _on_steam_lobby_match_list(lobbies: Array) -> void:
	lobby_list_received.emit(lobbies)
	if _pending_autojoin_type.is_empty():
		return
	var wanted: String = _pending_autojoin_type
	_pending_autojoin_type = ""
	var found: int = _first_open_lobby(lobbies, wanted)
	if found != 0:
		print("[NetworkManager] Found open '%s' lobby %d -> joining." % [wanted, found])
		join_lobby(found)
		return
	if _autojoin_attempt < AUTOJOIN_RETRIES:
		_autojoin_attempt += 1
		# Both peers launched at once both saw an empty list. Rather than host
		# immediately (and never meet), wait a randomised moment and ask again;
		# only host if there is STILL nothing to join.
		var delay: float = randf_range(0.5, 1.2) * float(_autojoin_attempt)
		print("[NetworkManager] No open '%s' lobby; re-checking in %.1fs (attempt %d/%d)..." % [
				wanted, delay, _autojoin_attempt, AUTOJOIN_RETRIES])
		await get_tree().create_timer(delay).timeout
		_pending_autojoin_type = wanted
		Steam.requestLobbyList()
		return
	print("[NetworkManager] No open '%s' lobby -> hosting a new one." % wanted)
	create_lobby(wanted)

#endregion


#region Godot multiplayer handlers ---------------------------------------------

func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected: %d (total %d)." % [id, multiplayer.get_peers().size()])
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer disconnected: %d." % id)
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("[NetworkManager] Connected to host. My peer id: %d." % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	push_error("[NetworkManager] Failed to connect to host.")
	connection_failed.emit()


func _on_server_disconnected() -> void:
	push_warning("[NetworkManager] Host disconnected; session ended.")
	lobby_left.emit()

#endregion


#region Helpers ----------------------------------------------------------------

func _require_steam(action: String) -> bool:
	if not SteamManager.is_initialized:
		push_warning("[NetworkManager] Cannot %s: Steam is not initialized." % action)
		return false
	return true


## Pull a lobby ID out of one entry of the Steam lobby-match list. GodotSteam
## hands back an Array of Dictionaries ({ "lobby_id": int, "lobby_data": {...} }),
## but we also accept a bare int so a format change never crashes us.
func _lobby_id_of(entry: Variant) -> int:
	match typeof(entry):
		TYPE_INT:
			return int(entry)
		TYPE_DICTIONARY:
			var d: Dictionary = entry
			for key in ["lobby_id", "steam_id", "id"]:
				if d.has(key):
					return int(d[key])
	return 0


## First lobby of `wanted_type` that still has a free slot.
func _first_open_lobby(lobbies: Array, wanted_type: String) -> int:
	for entry in lobbies:
		var lobby_id: int = _lobby_id_of(entry)
		if lobby_id == 0:
			continue
		var ltype: String = Steam.getLobbyData(lobby_id, KEY_TYPE)
		if not wanted_type.is_empty() and ltype != wanted_type:
			continue
		var members: int = Steam.getNumLobbyMembers(lobby_id)
		var limit: int = Steam.getLobbyMemberLimit(lobby_id)
		if limit <= 0:
			limit = MAX_MEMBERS
		if members < limit:
			return lobby_id
	return 0

#endregion
