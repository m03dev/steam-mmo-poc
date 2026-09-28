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
	var role: String = "offline"
	if NetworkManager.current_lobby_id != 0:
		role = "host" if NetworkManager.is_host else "client"
	_net_value.text = "%s   peer %d%s" % [role.to_upper(), multiplayer.get_unique_id(), _steam_suffix()]

	if NetworkManager.current_lobby_id == 0:
		_lobby_value.text = "no lobby"
		return
	_lobby_value.text = "%s   %d   %d/%d" % [
			NetworkManager.current_lobby_type,
			NetworkManager.current_lobby_id,
			NetworkManager.get_player_count(),
			NetworkManager.MAX_MEMBERS]


## Our own Steam account, so a screenshot of this panel identifies the peer.
func _steam_suffix() -> String:
	return "   %d" % SteamManager.steam_id if SteamManager.is_initialized else ""


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


## "<peer id> <name> <ping> [steam <ping>] [q <quality>]" -- only the parts we
## actually have. The peer id leads because that is the id replication uses.
func _peer_line(row: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray([
			str(int(row["peer_id"])), str(row["name"]), _format_ms(int(row["ping"]))])
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