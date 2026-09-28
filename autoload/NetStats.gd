extends Node
## NetStats -- live connection quality for the peers we are actually talking to.
## ============================================================================
## Two sources, on purpose:
##
##   * Ping comes from an RPC round trip, which works on ANY MultiplayerPeer --
##     Steam's relay, plain ENet, the two-peer test harness. The stamp travels
##     out with the probe and straight back, so the reply is timed against the
##     sender's own clock and no clock sync is needed. The server measures every
##     client and broadcasts its table, so host and clients agree on the numbers;
##     a client also times its own trip to the server, so it has a figure before
##     the first table arrives.
##
##   * Steam's own per-connection status ENRICHES that report when the peer
##     really is a SteamMultiplayerPeer: Socket-layer ping, link quality and
##     throughput. Every Steam field is read through Dictionary.get() with a
##     fallback, so a key this build does not send reads as unknown rather than
##     erroring.
##
## Sampled on timers, never per frame.

## How often the server pings each client.
const PING_INTERVAL: float = 1.0
## How often the server pushes its ping table to the clients.
const TABLE_INTERVAL: float = 2.0
## Samples averaged per peer: one ping is jittery, an average is readable.
const SAMPLE_COUNT: int = 5
## How often the Steam-side detail is refreshed (it moves slowly).
const STEAM_INTERVAL: float = 1.0

## peer_id -> averaged round trip in ms. The server owns this; clients receive it.
var ping_ms: Dictionary = {}
## peer_id -> normalised Steam detail. Empty for non-Steam peers.
var steam_detail: Dictionary = {}

var _samples: Dictionary = {}
## One-shot log guards, so something that never arrives cannot spam the log.
var _logged_raw: Dictionary = {}
var _logged_note: Dictionary = {}
var _ping_timer: float = 0.0
var _table_timer: float = 0.0
var _steam_timer: float = 0.0


func _process(delta: float) -> void:
	if not _online():
		return
	if multiplayer.is_server():
		_ping_timer += delta
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			for peer_id: int in multiplayer.get_peers():
				_probe(peer_id)
		_table_timer += delta
		if _table_timer >= TABLE_INTERVAL and not multiplayer.get_peers().is_empty():
			_table_timer = 0.0
			_publish.rpc(ping_ms.duplicate())
	else:
		# A client only needs its own trip to the server; the server's table
		# fills in everybody else.
		_ping_timer += delta
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			_probe(1)

	_steam_timer += delta
	if _steam_timer >= STEAM_INTERVAL:
		_steam_timer = 0.0
		_prune()
		_refresh_steam()


## Ping to one peer in ms, or -1 while it is still unknown.
func ping_to(peer_id: int) -> int:
	return int(ping_ms.get(peer_id, -1))


## One row per remote peer, ready for a debug overlay.
func report() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for peer_id: int in multiplayer.get_peers():
		var detail: Dictionary = steam_detail.get(peer_id, {})
		rows.append({
			"peer_id": peer_id,
			"steam_id": _steam_id_for(peer_id),
			"name": _name_for(peer_id),
			"ping": ping_to(peer_id),
			"steam_ping": int(detail.get("ping", -1)),
			"quality": float(detail.get("quality", -1.0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["peer_id"]) < int(b["peer_id"]))
	return rows


#region Probing -----------------------------------------------------------------

## Godot 4.7 always has a peer object, even with no network, so "is there a
## peer" is the wrong question -- "is it offline" is the right one.
func _online() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


func _probe(peer_id: int) -> void:
	if peer_id <= 0 or peer_id == multiplayer.get_unique_id():
		return
	_echo.rpc_id(peer_id, Time.get_ticks_msec())


@rpc("any_peer", "unreliable", "call_remote")
func _echo(stamp: int) -> void:
	# Unreliable on both legs: this is a latency probe, not game state, and a
	# retransmit would report a round trip the player never experienced.
	_echo_reply.rpc_id(multiplayer.get_remote_sender_id(), stamp)


@rpc("any_peer", "unreliable", "call_remote")
func _echo_reply(stamp: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender > 0:
		_note(sender, Time.get_ticks_msec() - stamp)


@rpc("authority", "unreliable", "call_remote")
func _publish(table: Dictionary) -> void:
	# Merge rather than replace: the client's own measurement of the server
	# (keyed by the server's id) is not in the server's table.
	for peer_id: int in table:
		ping_ms[peer_id] = int(table[peer_id])


func _note(peer_id: int, ms: int) -> void:
	var history: Array = _samples.get(peer_id, [])
	history.append(ms)
	while history.size() > SAMPLE_COUNT:
		history.pop_front()
	_samples[peer_id] = history
	var total: int = 0
	for sample: int in history:
		total += sample
	ping_ms[peer_id] = int(round(float(total) / float(history.size())))

#endregion


#region Steam enrichment --------------------------------------------------------

func _refresh_steam() -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if not (peer is SteamMultiplayerPeer) or not SteamManager.is_initialized:
		return
	var steam_peer: SteamMultiplayerPeer = peer
	for peer_id: int in multiplayer.get_peers():
		# Only ask once the RPC probe proves there is a real link; before that
		# Steam just answers with nothing.
		if not ping_ms.has(peer_id):
			continue
		var steam_id: int = steam_peer.get_steam_id_for_peer_id(peer_id)
		if steam_id == 0:
			continue
		# Session info hands back the socket handle for that SteamID; the
		# real-time status is what carries ping/quality/throughput.
		var session: Dictionary = Steam.getSessionConnectionInfo(steam_id, true, true)
		var handle: int = int(session.get("connection", 0))
		if handle == 0:
			_note_once(peer_id, "no Steam socket handle yet")
			continue
		var raw: Dictionary = Steam.getConnectionRealTimeStatus(handle, 0, true)
		steam_detail[peer_id] = {
			"ping": int(raw.get("ping", -1)),
			"quality": float(raw.get("local_quality", -1.0)),
			"in_kbps": float(raw.get("bytes_in_per_second", 0.0)) / 1024.0,
			"out_kbps": float(raw.get("bytes_out_per_second", 0.0)) / 1024.0,
		}
		_log_raw_once(peer_id, raw)


## Print each peer's RAW Steam status exactly once. If a field above ever reads
## as unknown, this line is the record of what this engine build really sends.
func _log_raw_once(peer_id: int, raw: Dictionary) -> void:
	if _logged_raw.has(peer_id):
		return
	_logged_raw[peer_id] = true
	print("[NetStats] peer %d Steam status: %s" % [peer_id, raw])


func _note_once(peer_id: int, message: String) -> void:
	if _logged_note.has(peer_id):
		return
	_logged_note[peer_id] = true
	print("[NetStats] peer %d: %s" % [peer_id, message])


## Forget peers that have gone, so someone who left does not linger in the panel.
func _prune() -> void:
	var live: Array[int] = [multiplayer.get_unique_id()]
	if multiplayer.is_server():
		for peer_id: int in multiplayer.get_peers():
			live.append(peer_id)
	else:
		live.append(1)
		for peer_id: int in multiplayer.get_peers():
			live.append(peer_id)
	for peer_id: int in ping_ms.keys():
		if not live.has(peer_id):
			ping_ms.erase(peer_id)
			_samples.erase(peer_id)
			steam_detail.erase(peer_id)
			_logged_raw.erase(peer_id)
			_logged_note.erase(peer_id)


func _steam_id_for(peer_id: int) -> int:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer is SteamMultiplayerPeer:
		return (peer as SteamMultiplayerPeer).get_steam_id_for_peer_id(peer_id)
	return 0


## Best-effort display name: what the peer published in the lobby, else Steam's
## own name for that account, else nothing usable.
func _name_for(peer_id: int) -> String:
	var steam_id: int = _steam_id_for(peer_id)
	if steam_id == 0 or not SteamManager.is_initialized:
		return "?"
	if NetworkManager.current_lobby_id != 0:
		var published: String = Steam.getLobbyMemberData(
				NetworkManager.current_lobby_id, steam_id, "name")
		if published != "":
			return published
	var persona: String = Steam.getFriendPersonaName(steam_id)
	return persona if persona != "" else str(steam_id)

#endregion