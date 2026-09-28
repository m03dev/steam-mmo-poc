extends CharacterBody3D
## Player -- one box per peer.
##
## The peer that OWNS a player simulates it; a MultiplayerSynchronizer
## replicates position + rotation to everyone else. Authority is derived from
## the node name ("player_<peer_id>") in _enter_tree, so every peer computes the
## same owner with no networked handoff.

const SPEED: float = 6.0
const GRAVITY: float = 22.0

@onready var camera: Camera3D = $Camera3D


func _enter_tree() -> void:
	var owner_id: int = int(String(name).trim_prefix("player_"))
	set_multiplayer_authority(owner_id)


func _ready() -> void:
	# Position/rotation replication is declared in Player.tscn, so the config
	# exists before any peer starts syncing this node. Here we only pick the
	# camera the local peer looks through.
	camera.current = is_multiplayer_authority()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	velocity.x = input.x * SPEED
	velocity.z = input.y * SPEED
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Safety net: if we walk off the edge, drop back into the level instead of
	# falling forever (which would look like the box simply vanished).
	if global_position.y < -20.0:
		global_position = Vector3(0.0, 3.0, 0.0)
		velocity = Vector3.ZERO
	if input != Vector2.ZERO:
		rotation.y = atan2(input.x, input.y)