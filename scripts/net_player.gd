class_name NetPlayer
extends Node
## Network adapter for the vendored third-person character.
## ============================================================================
## PlayerCharacter/ is a SINGLE-PLAYER controller: it reads the keyboard
## directly, captures the mouse, runs its own state machine and draws a debug
## HUD. This adapter makes exactly ONE instance the real player -- the one whose
## node name matches our peer id ("player_<peer_id>"), the same rule the old box
## player used -- and silences every other instance, so remote players become
## puppets driven purely by the MultiplayerSynchronizer.

## DevHud finds the local avatar through this group, which keeps the overlay
## decoupled from the level's node layout.
const LOCAL_PLAYER_GROUP: String = "local_player"

@export_group("Camera feel")
## Radians of camera rotation per pixel of mouse motion (the asset ships 0.005).
@export var mouse_sensitivity: float = 0.0025
## How far the camera sits behind the character in metres (the asset ships 8).
@export var camera_distance: float = 6.0
## Pitch limits in degrees. Looking DOWN lifts the camera away from the avatar,
## so there is room to spare; looking UP drops it toward the floor, which is why
## the asset keeps that side tight. Widen these if the camera feels cramped.
@export var camera_pitch_down_degrees: float = -80.0
@export var camera_pitch_up_degrees: float = 10.0

@onready var _character: CharacterBody3D = get_parent()
@onready var _camera_holder: Node = _character.get_node("CameraHolder")
@onready var _state_machine: Node = _character.get_node("StateMachine")
@onready var _visual_root: Node3D = _character.get_node("VisualRoot")
@onready var _skin: Node = _character.get_node_or_null("VisualRoot/GodotPlushSkin")
@onready var _hud: CanvasLayer = _character.get_node("HUD")
@onready var _camera: Camera3D = _character.get_node("CameraHolder/SpringArm3D/Camera3D")

## The animation the model should be playing, replicated from whoever owns the
## character. WHY THIS EXISTS: the vendored state scripts call
## `godot_plush_skin.set_state(...)` themselves, but a puppet's state machine is switched
## off (it must not read the LOCAL keyboard), so that call never happens on a remote peer
## and every other player stood frozen in its spawn pose while sliding around the map.
## The state name is the one fact only the owner has, so it is the thing worth sending.
@export var anim_state: String = "idle" : set = _set_anim_state

var _is_local: bool = false
var _pose_age: float = 0.0


## The vendored state machine names differ from the model's animation names ("Inair" is
## the state, "fall" is the animation), so the mapping lives in exactly one place.
static func animation_for_state(state_name: String) -> String:
	match state_name:
		"Walk":
			return "walk"
		"Run":
			return "run"
		"Jump":
			return "jump"
		"Inair":
			return "fall"
		_:
			return "idle"


## Runs on the OWNER when it publishes the state, and on every PUPPET when that value
## arrives. Only the puppet acts on it: the owner's state machine has already driven the
## model itself, and asking for the same animation twice would fight it.
## How often a puppet re-states its pose. It cannot be "only when the value changes",
## because the model pulls the pose away on its own - see _renew_puppet_pose.
const POSE_RENEW_SECONDS: float = 0.4


## Whether a puppet is due to state its pose again. Pure, so the rule is testable without a
## model and without waiting in real time.
static func pose_renew_due(seconds_since_last: float, interval: float) -> bool:
	return seconds_since_last >= interval


func _set_anim_state(value: String) -> void:
	anim_state = value
	_pose_age = 0.0
	if _is_local or not is_node_ready():
		return
	if _skin != null and _skin.has_method("set_state"):
		_skin.set_state(value)


## A puppet has no movement input of its own: the vendored state scripts that set the model's
## parameters are switched off, which is exactly what makes it a puppet. The model's state
## machine has transitions of its own, so a pose set once gets pulled back to idle about a
## second later - mid-stride, while the owner keeps walking. That was the reported bug in its
## second form: the animation NAME arrived and the avatar froze anyway. Renewing the pose on a
## slow interval holds it, and stays clear of the model's blends, which are much shorter.
func _renew_puppet_pose(delta: float) -> void:
	_pose_age += delta
	if not pose_renew_due(_pose_age, POSE_RENEW_SECONDS):
		return
	_pose_age = 0.0
	if _skin != null and _skin.has_method("set_state"):
		_skin.set_state(anim_state)


func _enter_tree() -> void:
	# Authority is derived from the node name, so every peer computes the same
	# owner locally and no handoff over the network is needed.
	var character: Node = get_parent()
	character.set_multiplayer_authority(int(String(character.name).trim_prefix("player_")))


func _ready() -> void:
	# Every copy of a player, including the puppets, announces itself to the world
	# registry. On the server that is the complete cast, which is what the enemy AI
	# reads instead of hunting through the scene tree.
	WorldState.register_entity(WorldState.KIND_PLAYER, _character)
	_retire_asset_hud()
	# A null peer only happens mid-transition; is_multiplayer_authority() errors
	# on it, so check first.
	_is_local = multiplayer.multiplayer_peer != null and _character.is_multiplayer_authority()
	if _is_local:
		_setup_local_player()
		return
	_make_puppet()


func _exit_tree() -> void:
	WorldState.unregister_entity(WorldState.KIND_PLAYER, _character)


## The asset ships a large debug panel of its own; ui/dev_hud.tscn replaces it
## with one small overlay, so silence the bundled one on EVERY instance and stop
## its _process work too.
func _retire_asset_hud() -> void:
	_hud.visible = false
	_hud.set_process(false)


func _setup_local_player() -> void:
	_apply_camera_taste()
	# The plush model is authored facing +Z, so a fresh spawn stares straight
	# into the camera. Face it away from the camera instead; the asset only
	# re-orients the model once you actually move (see modify_model_orientation).
	_visual_root.rotation.y = PI
	_camera.current = true
	_character.add_to_group(LOCAL_PLAYER_GROUP)


## Camera taste, local player only. Both values are exported so they can be
## dialled in from the inspector without touching the vendored asset.
func _apply_camera_taste() -> void:
	_camera_holder.set("mouse_sensibility", mouse_sensitivity)
	_camera_holder.set("min_limit_x", camera_pitch_down_degrees)
	_camera_holder.set("max_limit_x", camera_pitch_up_degrees)
	var spring_arm: SpringArm3D = _camera_holder.get_node("SpringArm3D")
	spring_arm.spring_length = camera_distance


## Strip everything a remote player must not do locally.
func _make_puppet() -> void:
	_character.set_physics_process(false)
	_character.set_process(false)
	_state_machine.set_physics_process(false)
	_state_machine.set_process(false)
	_camera_holder.set("active", false)  # stops its _input/_process
	_camera.current = false
	# The first replicated value can arrive before this node is ready, and the setter
	# drops anything that early, so say the current pose once here. Without this a
	# puppet whose owner is standing still would hold its spawn pose forever.
	if _skin != null and _skin.has_method("set_state"):
		_skin.set_state(anim_state)


func _process(delta: float) -> void:
	if _is_local:
		# The asset's camera scene ships with current=true, so a remote player that
		# spawns after us briefly steals the viewport camera. Re-assert ours.
		if not _camera.current:
			_camera.current = true
		# Only the owner can see its own state machine, so it is the one that publishes
		# the animation. Assigning through the setter is what the synchronizer carries.
		var derived: String = animation_for_state(str(_state_machine.curr_state_name))
		if derived != anim_state:
			anim_state = derived
		return
	# The puppet's half of the same sentence: hold the pose the owner published.
	_renew_puppet_pose(delta)