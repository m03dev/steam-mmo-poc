extends Node
## Dev harness (NOT shipped) for the Steam two-peer test, driven headlessly.
##   Godot --headless --path . res://tests/steam_client.tscn -- --host
##   Godot --headless --path . res://tests/steam_client.tscn -- --join <lobbyid>
##   Godot --headless --path . res://tests/steam_client.tscn -- --autojoin
##   Godot --headless --path . res://tests/steam_client.tscn -- --diag
##
## Writes nothing and changes nothing: it only drives NetworkManager and reports
## what the multiplayer layer actually does, so a two-peer Steam run can be
## observed without clicking anything.

var _role: String = ""
var _t: float = 0.0
var _elapsed: float = 0.0
var _warned: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var join_id: int = 0
	for i in args.size():
		if args[i] == "--join" and i + 1 < args.size():
			join_id = int(args[i + 1])
	if not SteamManager.is_initialized:
		await SteamManager.steam_initialized
	if not SteamManager.is_initialized:
		print("[steam_client] Steam NOT initialized; abort")
		return
	print("[steam_client] Steam OK persona='%s' steamid=%d" % [
			SteamManager.persona_name, SteamManager.steam_id])
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.peer_connected.connect(
			func(id: int) -> void: print("[steam_client] * PEER CONNECTED %d *" % id))
	multiplayer.connected_to_server.connect(
			func() -> void: print("[steam_client] * CONNECTED TO SERVER *"))
	multiplayer.connection_failed.connect(
			func() -> void: print("[steam_client] * CONNECTION FAILED *"))
	multiplayer.server_disconnected.connect(
			func() -> void: print("[steam_client] * SERVER DISCONNECTED *"))
	if args.has("--host"):
		_role = "host"
		NetworkManager.create_lobby(NetworkManager.TYPE_WORLD)
	elif args.has("--autojoin"):
		_role = "autojoin"
		NetworkManager.auto_join_first_open(NetworkManager.TYPE_WORLD)
	elif args.has("--diag"):
		_role = "diag"
	elif join_id != 0:
		_role = "client"
		NetworkManager.join_lobby(join_id)
	else:
		print("[steam_client] no mode given; init check only")


func _on_lobby_created(id: int) -> void:
	print("[steam_client] CREATED lobby %d owner=%d" % [id, Steam.getLobbyOwner(id)])


func _on_lobby_joined(id: int) -> void:
	print("[steam_client] JOINED lobby %d owner=%d members=%d" % [
			id, Steam.getLobbyOwner(id), Steam.getNumLobbyMembers(id)])
	for i in Steam.getNumLobbyMembers(id):
		print("[steam_client]   member[%d] steamid=%d" % [
				i, Steam.getLobbyMemberByIndex(id, i)])


func _process(delta: float) -> void:
	if _role.is_empty():
		return
	_elapsed += delta
	_t += delta
	if _t < 3.0:
		return
	_t = 0.0
	var pr: MultiplayerPeer = multiplayer.multiplayer_peer
	var extra: String = "none"
	if pr is SteamMultiplayerPeer:
		extra = "SteamMPP status=%d" % (pr as SteamMultiplayerPeer).get_connection_status()
	var relay: String = "n/a"
	if Engine.has_singleton("Steam") and Steam.has_method("getRelayNetworkStatus"):
		relay = str(Steam.getRelayNetworkStatus())
	print("[steam_client/%s] t=%.0fs lobby=%d peers=%s peer_obj=%s relay=%s" % [
			_role, _elapsed, NetworkManager.current_lobby_id,
			str(multiplayer.get_peers()), extra, relay])
	if _role != "diag" and _elapsed > 20.0 and not _warned \
			and multiplayer.get_peers().is_empty():
		_warned = true
		print("[steam_client] !! NO SDR PEER after 20s (lobby joined but sockets never connected)")