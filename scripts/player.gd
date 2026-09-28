extends CharacterBody3D
## Player -- one box per peer.
##
## The peer that OWNS a player simulates it; a MultiplayerSynchronizer
## replicates position + rotation to everyone else. Authority is derived from
## the node name ("player_<peer_id>") in _enter_tree, so every peer computes the
## same owner with no networked handoff.

const SPEED: float = 5.5
const ACCELERATION: float = 34.0
const TURN_SPEED: float = 12.0
const GRAVITY: float = 22.0
const CAMERA_HEIGHT: float = 1.6

## Mouse-look limits. The camera orbits the box and is deliberately INDEPENDENT
## of the body's facing (the rig is top_level), which is what makes it possible
## to pivot freely and walk in any direction. This decoupled-orbit + SpringArm3D
## setup follows GDQuest's open-source third-person controller (MIT).
const MOUSE_SENSITIVITY: float = 0.0022
const PITCH_MIN: float = -1.0
const PITCH_MAX: float = 1.0

@onready var camera: Camera3D = $CameraRig/Pivot/SpringArm3D/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var camera_pivot: Node3D = $CameraRig/Pivot
@onready var spring_arm: SpringArm3D = $CameraRig/Pivot/SpringArm3D

## Camera orbit, owned locally by each peer (deliberately NOT synced -- everyone
## is free to look around independently).
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.25


func _enter_tree() -> void:
	var owner_id: int = int(String(name).trim_prefix("player_"))
	set_multiplayer_authority(owner_id)


func _ready() -> void:
	# Position/rotation replication is declared in Player.tscn, so the config
	# exists before any peer starts syncing this node. Here we only pick the
	# camera the local peer looks through.
	var is_mine: bool = _is_local_owner()
	camera.current = is_mine
	print("[Player] %s auth=%d camera_current=%s" % [
			name, get_multiplayer_authority(), str(is_mine)])
	# Stop the camera's SpringArm3D from colliding with our own box (otherwise
	# the camera would be shoved into our face).
	spring_arm.add_excluded_object(get_rid())
	if is_mine:
		# Grab the mouse so it turns the camera (Esc gives it back for the UI).
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## True when THIS machine owns the box. Unlike a bare is_multiplayer_authority()
## call, this is safe mid-transition: leave_lobby() briefly leaves the peer null,
## and the engine errors on get_unique_id() in that state.
func _is_local_owner() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_owner():
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		# Look with the mouse while it is grabbed; if the cursor has been freed
		# (Esc, to click the debug buttons) hold the right button to look instead.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_cam_yaw -= mm.relative.x * MOUSE_SENSITIVITY
			_cam_pitch = clampf(_cam_pitch - mm.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	elif event.is_action_pressed("ui_cancel"):
		# Esc releases the mouse so the debug lobby buttons can be clicked.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
				and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			# Left-click anywhere that is not UI to grab the mouse back.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not _is_local_owner():
		return
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Move relative to where the camera is looking, not the world axes.
	var dir: Vector3 = Basis(Vector3.UP, _cam_yaw) * Vector3(input.x, 0.0, input.y)
	# Ease into and out of motion instead of snapping to full speed.
	velocity.x = move_toward(velocity.x, dir.x * SPEED, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, dir.z * SPEED, ACCELERATION * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Safety net: if we walk off the edge, drop back into the level instead of
	# falling forever (which would look like the box simply vanished).
	if global_position.y < -20.0:
		global_position = Vector3(0.0, 3.0, 0.0)
		velocity = Vector3.ZERO
	# Turn smoothly toward the way we are walking (what others see us do).
	if dir.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), TURN_SPEED * delta)
	# The rig is top_level, so our facing does not touch it: place it at head
	# height and drive its rotation purely from the mouse.
	camera_rig.global_position = global_position + Vector3.UP * CAMERA_HEIGHT
	camera_rig.rotation.y = _cam_yaw
	camera_pivot.rotation.x = _cam_pitch