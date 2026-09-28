extends Node
## Network adapter for the vendored third-person character.
## ============================================================================
## PlayerCharacter/ is a SINGLE-PLAYER controller: it reads the keyboard
## directly, captures the mouse, runs its own state machine and draws a debug
## HUD. This adapter makes exactly ONE instance the real player -- the one whose
## node name matches our peer id ("player_<peer_id>"), the same rule the old box
## player used -- and silences every other instance, so remote players become
## puppets driven purely by the MultiplayerSynchronizer.

@export_group("Camera feel")
## Radians of camera rotation per pixel of mouse motion (the asset ships 0.005).
@export var mouse_sensitivity: float = 0.0025
## How far the camera sits behind the character in metres (the asset ships 8).
@export var camera_distance: float = 6.0

@onready var _character: CharacterBody3D = get_parent()
@onready var _camera_holder: Node = _character.get_node("CameraHolder")
@onready var _state_machine: Node = _character.get_node("StateMachine")
@onready var _visual_root: Node3D = _character.get_node("VisualRoot")
@onready var _hud: CanvasLayer = _character.get_node("HUD")
@onready var _camera: Camera3D = _character.get_node("CameraHolder/SpringArm3D/Camera3D")

var _is_local: bool = false


func _enter_tree() -> void:
	# Authority is derived from the node name, so every peer computes the same
	# owner locally and no handoff over the network is needed.
	var character: Node = get_parent()
	character.set_multiplayer_authority(int(String(character.name).trim_prefix("player_")))


func _ready() -> void:
	# A null peer only happens mid-transition; is_multiplayer_authority() errors
	# on it, so check first.
	_is_local = multiplayer.multiplayer_peer != null and _character.is_multiplayer_authority()
	if _is_local:
		_apply_camera_taste()
		# The plush model is authored facing +Z, so a fresh spawn stares straight
		# into the camera. Face it away from the camera instead; the asset only
		# re-orients the model once you actually move (see modify_model_orientation).
		_visual_root.rotation.y = PI
		_camera.current = true
		return
	_make_puppet()


## Camera taste, local player only. Both values are exported so they can be
## dialled in from the inspector without touching the vendored asset.
func _apply_camera_taste() -> void:
	_camera_holder.set("mouse_sensibility", mouse_sensitivity)
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
	_hud.visible = false
	_hud.set_process(false)


func _process(_delta: float) -> void:
	# The asset's camera scene ships with current=true, so a remote player that
	# spawns after us briefly steals the viewport camera. Re-assert ours.
	if _is_local and not _camera.current:
		_camera.current = true