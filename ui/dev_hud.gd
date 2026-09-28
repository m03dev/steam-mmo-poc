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
@onready var _avatar_value: Label = %AvatarValue

var _elapsed: float = 0.0
var _local_player: Node3D = null


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
	_show_avatar()


func _show_frame_timing() -> void:
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / fps if fps > 0.0 else 0.0
	_fps_value.text = "%d fps   %.1f ms" % [roundi(fps), frame_ms]


func _show_network() -> void:
	var role: String = "offline"
	if NetworkManager.current_lobby_id != 0:
		role = "host" if NetworkManager.is_host else "client"
	_net_value.text = "%s   peer %d" % [role.to_upper(), multiplayer.get_unique_id()]

	if NetworkManager.current_lobby_id == 0:
		_lobby_value.text = "no lobby"
		return
	_lobby_value.text = "%s   %d   %d/%d" % [
			NetworkManager.current_lobby_type,
			NetworkManager.current_lobby_id,
			NetworkManager.get_player_count(),
			NetworkManager.MAX_MEMBERS]


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