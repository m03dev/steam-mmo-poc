class_name Enemy
extends CharacterBody3D
## Enemy -- a server-owned mob: it notices players, walks at them, and hits them.
##
## There is no "am I allowed to run the AI?" code in here. The server owns the node
## (authority 1, which is what a MultiplayerSpawner-spawned node gets by default),
## so _physics_process returns immediately on every other peer and they hold a
## puppet that follows the replicated transform and the replicated Health. A mob's
## security model is one early return.
##
## Movement is CharacterBody3D + move_and_slide, and position/rotation/health are
## replicated by the scene's MultiplayerSynchronizer. Nothing about motion or
## replication is hand-written here.

@export var display_name: String = "Forest Wolf"
@export var max_health: int = 60
@export var damage: int = 9

@export_group("Behaviour")
## Reach for its own swing.
@export var attack_range: float = 2.2
@export var attack_cooldown: float = 1.6
## How close a player has to come before it notices at all.
@export var aggro_radius: float = 12.0
## How far it will chase from where it spawned before giving up and walking back --
## the leash, in one number.
@export var leash_radius: float = 20.0
## How long it sulks at home after a leash breaks. Without this the walk home
## re-aggros the same player on the very next frame and the mob never resets.
@export var evade_time: float = 3.0
@export var move_speed: float = 2.6
@export var xp_reward: int = 40
@export var respawn_delay: float = 8.0

## Which of the level's spawn points this mob belongs to, so the level can put it
## back. Assigned by the level when it spawns us.
var spawn_id: int = -1

@onready var health: Health = $Health
@onready var _nameplate: Label3D = $Nameplate
@onready var _bar: MeshInstance3D = $HealthBar

const BAR_WIDTH: float = 1.6

var _home: Vector3 = Vector3.ZERO
var _target: Node3D = null
var _cooldown: float = 0.0
var _evade: float = 0.0
var _bar_material: StandardMaterial3D = null


func _enter_tree() -> void:
	# A mob is owned by the server on every peer, stated rather than assumed -- the
	# same rule NetPlayer derives from the player's name, for a node whose owner is
	# always the same.
	set_multiplayer_authority(WorldState.SERVER_ID)


func _ready() -> void:
	_home = global_position
	# The group name comes from WorldState so the two sides of a fight agree on it
	# without one script having to preload the other.
	add_to_group(WorldState.KIND_ENEMY)
	health.set_maximum(max_health)

	_bar_material = StandardMaterial3D.new()
	_bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.material_override = _bar_material

	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_on_health_changed(health.current, health.maximum)


func _exit_tree() -> void:
	WorldState.unregister_entity(WorldState.KIND_ENEMY, self)


#region Thinking (server only) --------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if not health.is_alive():
		return
	_cooldown = maxf(0.0, _cooldown - delta)

	# Sulking after a broken leash: walk home and pay no attention to anyone.
	if _evade > 0.0:
		_evade = maxf(0.0, _evade - delta)
		_target = null
		_go_home()
		return

	if _target != null and not _is_valid_target(_target):
		_target = null
	if _target == null:
		_target = _find_target()

	if _target == null:
		_go_home()
		return

	var distance: float = global_position.distance_to(_target.global_position)
	if global_position.distance_to(_home) > leash_radius:
		# Chased far enough. Drop it, forget it for a moment, and go back to the post.
		_target = null
		_evade = evade_time
		_go_home()
		return
	if distance > attack_range:
		_step_towards(_target.global_position)
		return
	velocity = Vector3.ZERO
	_swing()


## Nearest living player inside the aggro radius, found through the world registry
## rather than by walking the tree -- which is what the registry is for.
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_distance: float = aggro_radius
	for node: Node in WorldState.entities_in(WorldState.KIND_PLAYER):
		var body: Node3D = node as Node3D
		if not _is_valid_target(body):
			continue
		var distance: float = global_position.distance_to(body.global_position)
		if distance <= best_distance:
			best = body
			best_distance = distance
	return best


func _is_valid_target(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var other: Health = _health_of(node)
	return other != null and other.is_alive()


func _step_towards(point: Vector3) -> void:
	var direction: Vector3 = point - global_position
	direction.y = 0.0
	if direction.length() < 0.05:
		velocity = Vector3.ZERO
		return
	direction = direction.normalized()
	velocity = direction * move_speed
	# Face the way we are going. Rotation is replicated too, so the puppet turns
	# without any extra syncing of its own.
	var yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, 0.15)
	move_and_slide()


func _go_home() -> void:
	if global_position.distance_to(_home) < 0.5:
		velocity = Vector3.ZERO
		return
	_step_towards(_home)


func _swing() -> void:
	if _cooldown > 0.0 or _target == null:
		return
	var victim: Health = _health_of(_target)
	if victim == null:
		return
	_cooldown = attack_cooldown
	var taken: int = victim.apply_damage(damage)
	if taken > 0:
		WorldState.log_event("%s hits %s for %d." % [
				display_name, _label_of(_target), taken])

#endregion


#region Dying -------------------------------------------------------------------

func _on_died(killer_peer: int) -> void:
	# The server applied the killing blow, so only the server hears this on its own
	# authority -- but be explicit rather than lucky.
	if not is_multiplayer_authority():
		return
	velocity = Vector3.ZERO
	_target = null
	_evade = 0.0
	WorldState.log_event("%s dies." % display_name)
	_award_killer(killer_peer)
	# Down, but not gone. Health is replicated, so a zero is enough for every peer to
	# hide the body and stop thinking about it; restoring it later is the revival.
	# No despawn, no spawn: one less thing to get out of step between peers.
	var level: Node = _owning_level()
	if level != null and level.has_method("respawn_enemy"):
		level.respawn_enemy(self)


## Back on your feet at the post, at full health. Server-side only, because this is
## a hit-point change and the server owns those.
func revive() -> void:
	if not is_multiplayer_authority():
		return
	global_position = _home
	velocity = Vector3.ZERO
	_target = null
	health.restore()
	WorldState.log_event("%s is back on its feet." % display_name)


## Credit the kill. Player nodes are named player_<peer_id> on every peer, so the
## registry plus that one naming rule is enough to find who to pay.
func _award_killer(killer_peer: int) -> void:
	if killer_peer <= 0:
		return
	for node: Node in WorldState.entities_in(WorldState.KIND_PLAYER):
		if node.name != "player_%d" % killer_peer:
			continue
		var state: PlayerState = node.get_node_or_null("Stats") as PlayerState
		if state != null:
			state.award_xp(xp_reward, "killed %s" % display_name)
		return


func _owning_level() -> Node:
	return get_tree().get_first_node_in_group(WorldState.KIND_LEVEL)

#endregion


#region Looking the part --------------------------------------------------------

func _on_health_changed(current: int, maximum: int) -> void:
	_nameplate.text = "%s\n%d / %d" % [display_name, current, maximum]
	var fraction: float = 0.0 if maximum <= 0 else float(current) / float(maximum)
	# A full-health bar is noise: show it once something has happened to this mob.
	_bar.visible = current < maximum
	# Shrink from the right: scaling alone would pull both ends inwards.
	_bar.scale = Vector3(maxf(fraction, 0.001), 1.0, 1.0)
	_bar.position.x = -(1.0 - fraction) * BAR_WIDTH * 0.5
	if _bar_material != null:
		_bar_material.albedo_color = Color(0.85, 0.12, 0.1).lerp(Color(0.2, 0.8, 0.3), fraction)
	# A fallen mob is not in the world any more, and every peer can work that out for
	# itself from the hit points it was sent.
	visible = current > 0
	if not health.is_alive():
		_nameplate.text = "%s\n(defeated)" % display_name


func _health_of(node: Node3D) -> Health:
	if node == null:
		return null
	return node.get_node_or_null("Health") as Health


func _label_of(node: Node3D) -> String:
	var state: PlayerState = node.get_node_or_null("Stats") as PlayerState
	if state != null:
		return "player_%d" % state.peer_id()
	return String(node.name)

#endregion