extends CanvasLayer
## DevHud -- the one small overlay the game shows while developing.
## ============================================================================
## Deliberately tiny: frame timing, who we are on the network, the lobby, and
## the local avatar's motion state. The vendored character ships a large debug
## panel of its own; scripts/net_player.gd switches that off and this replaces
## it, so there is exactly one place to read dev state from.
##
## F3 hides/shows the whole overlay. "Menu" leaves the session and returns to
## the start screen -- the only way back while playing.

## The overlay is not worth re-laying-out every frame; 10 Hz reads fine.
const REFRESH_INTERVAL: float = 0.1

const START_SCENE: String = "res://ui/start_screen.tscn"

@onready var _fps_value: Label = %FpsValue
@onready var _net_value: Label = %NetValue
@onready var _lobby_value: Label = %LobbyValue
@onready var _ping_value: Label = %PingValue
@onready var _avatar_value: Label = %AvatarValue
@onready var _peers_header: Label = %PeersHeader
@onready var _peer_list: VBoxContainer = %PeerList

var _elapsed: float = 0.0
var _local_player: Node3D = null
## peer_id -> that peer's row label, so the list is rebuilt only when peers come
## or go rather than every refresh.
var _peer_rows: Dictionary = {}


func _ready() -> void:
	%MenuButton.pressed.connect(_on_menu_pressed)
	%InviteButton.pressed.connect(_on_invite_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_dev_hud"):
		visible = not visible


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_refresh()


func _refresh() -> void:
	_show_frame_timing()
	_show_network()
	_show_peers()
	_show_ping()
	_show_avatar()


func _show_frame_timing() -> void:
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / fps if fps > 0.0 else 0.0
	_fps_value.text = "%d fps   %.1f ms" % [roundi(fps), frame_ms]


func _show_network() -> void:
	_net_value.text = "%s   peer %d%s" % [
			_session_role().to_upper(), multiplayer.get_unique_id(), _steam_suffix()]

	if NetworkManager.current_lobby_id == 0:
		# A direct-IP session has no lobby by design, so the lobby check alone cannot
		# tell it from a genuinely offline game: without the transport test below,
		# a live peer-to-peer session reported itself as "offline".
		_lobby_value.text = ("direct ip   port %d" % NetworkManager.direct_port
				if NetworkManager.is_direct_session() else "no lobby")
		%InviteButton.disabled = true
		return
	%InviteButton.disabled = not SteamManager.is_initialized
	_lobby_value.text = "%s   %d   %d/%d" % [
			NetworkManager.current_lobby_type,
			NetworkManager.current_lobby_id,
			NetworkManager.get_player_count(),
			NetworkManager.MAX_MEMBERS]


## Who we are in this session, for the NET row. A direct-IP session never gets a
## Steam lobby id, so it must be identified by the transport rather than the lobby.
func _session_role() -> String:
	return session_role(NetworkManager.current_lobby_id,
			NetworkManager.is_direct_session(), NetworkManager.is_host)


## The mapping above, kept pure so a unit test can pin it without a display or a
## live peer. "offline" is reserved for a game with no session at all.
static func session_role(lobby_id: int, is_direct: bool, is_host: bool) -> String:
	if lobby_id == 0 and not is_direct:
		return "offline"
	var role: String = "host" if is_host else "client"
	return "%s (direct)" % role if is_direct else role


## Our own account, so a screenshot of this panel identifies the peer: Steam's name
## for the account plus its SteamID64, not just the number. Only meaningful when
## Steam is up -- a direct-IP session run without Steam has no account to show, and
## the transport is already named on the LOBBY row.
func _steam_suffix() -> String:
	if not SteamManager.is_initialized:
		return ""
	return "   " + SteamManager.identity_for(multiplayer.get_unique_id())


## Round-trip summary. The per-peer detail lives in the PEERS rows; this line is
## the one-glance answer to "how bad is my connection".
func _show_ping() -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		_ping_value.text = "offline"
		return
	var rows: Array[Dictionary] = NetStats.report()
	if multiplayer.is_server():
		if rows.is_empty():
			_ping_value.text = "no clients yet"
			return
		var worst: int = -1
		for row: Dictionary in rows:
			worst = maxi(worst, int(row["ping"]))
		_ping_value.text = "%d client(s)   worst %s" % [rows.size(), _format_ms(worst)]
		return
	# A client cares about its own trip to the host above all else.
	_ping_value.text = "to host %s   (%d other)" % [
			_format_ms(NetStats.ping_to(1)), maxi(rows.size() - 1, 0)]


## One row per remote peer. Rows are created and freed only when the set of peers
## changes, so the panel does not churn every refresh.
func _show_peers() -> void:
	var rows: Array[Dictionary] = NetStats.report()
	_peers_header.visible = not rows.is_empty()
	_peer_list.visible = not rows.is_empty()

	var live: Array[int] = []
	for row: Dictionary in rows:
		var peer_id: int = int(row["peer_id"])
		live.append(peer_id)
		var label: Label = _peer_rows.get(peer_id)
		if label == null:
			label = Label.new()
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", Color(0.749, 0.831, 0.898))
			_peer_list.add_child(label)
			_peer_rows[peer_id] = label
		label.text = _peer_line(row)

	# Keys() is a copy, so erasing while iterating is safe.
	for peer_id: int in _peer_rows.keys():
		if not live.has(peer_id):
			_peer_rows[peer_id].queue_free()
			_peer_rows.erase(peer_id)


## "<name> (<SteamID64>)  <ping> [steam <ping>] [q <quality>]".
##
## The account number is the point of this row. A multiplayer peer id is a
## truncated SteamID64, so printing it (324528183) tells the reader nothing they can
## check against a real account -- while 76561198632049032 is the actual Steam
## account on the other machine. NetStats already carries that id; nothing showed
## it until now. A peer with no Steam identity at all (direct-IP/ENet) falls back to
## the replication name "player_<peer id>", which is at least the id the code uses.
func _peer_line(row: Dictionary) -> String:
	var peer_id: int = int(row["peer_id"])
	var peer_name: String = str(row["name"])
	var steam_id: int = int(row["steam_id"])
	var parts: PackedStringArray = PackedStringArray()
	# When Steam's name could not be read, NetStats falls back to the id itself;
	# passing that as the persona too would print the number twice.
	var persona: String = "" if peer_name == str(steam_id) else peer_name
	parts.append(SteamManager.identity_text(peer_id, steam_id, persona))
	parts.append(_format_ms(int(row["ping"])))
	var steam_ping: int = int(row["steam_ping"])
	if steam_ping >= 0:
		parts.append("steam %d ms" % steam_ping)
	var quality: float = float(row["quality"])
	if quality >= 0.0:
		parts.append("q %.0f%%" % (quality * 100.0))
	return "  ".join(parts)


func _format_ms(ms: int) -> String:
	return "--" if ms < 0 else "%d ms" % ms


## The avatar line needs the local player, which only exists once the level has
## spawned it. net_player.gd adds whoever owns the input to the "local_player"
## group, so this stays decoupled from the level's node layout.
func _show_avatar() -> void:
	var avatar: Node3D = _local_avatar()
	if avatar == null:
		_avatar_value.text = "waiting for spawn"
		return
	var body: CharacterBody3D = avatar as CharacterBody3D
	var state_machine: Node = avatar.get_node_or_null("StateMachine")
	var state: String = str(state_machine.curr_state_name) if state_machine != null else "-"
	_avatar_value.text = "%s   v %.2f   %s" % [
			state, body.velocity.length(), "floor" if body.is_on_floor() else "air"]


func _local_avatar() -> Node3D:
	if _local_player != null and is_instance_valid(_local_player):
		return _local_player
	_local_player = get_tree().get_first_node_in_group("local_player") as Node3D
	return _local_player


func _on_menu_pressed() -> void:
	NetworkManager.leave_lobby()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(START_SCENE)


## Steam draws the friends list itself, so this is the whole invite feature: hand
## Steam the lobby id and let it do the work. Nothing happens if there is no lobby
## (the button is disabled then) or if Steam is down.
func _on_invite_pressed() -> void:
	if not NetworkManager.invite_friends():
		_lobby_value.text = "nothing to invite to yet"