class_name PlayerCombat
extends Node
## PlayerCombat -- the player's swing, and what happens when the player loses.
##
## The swing is a REQUEST, not an action. The local player decides it wants to hit
## something and asks the server, which re-checks everything (is that really your
## character, is that really within reach, has it swung too recently) before a
## single hit point moves. A client is never handed the damage number -- that is
## the entire reason this file has an RPC in it.
##
## Dying obeys the authority split the rest of the player already obeys: the server
## owns hit points, so the server decides when you are alive again; the client owns
## its position, so the client walks itself back to the spawn point when it sees
## its health come back.

const SERVER_ID: int = 1

@export var damage: int = 14
## Reach of a swing, in metres.
@export var melee_range: float = 3.0
## Slack on the server's reach check: a client's idea of where things are is a
## round trip out of date, and a hit that visibly connected must not be refused.
@export var range_slack: float = 1.0
@export var cooldown: float = 1.1
## Seconds to lie there before getting up again.
@export var death_delay: float = 4.0

## Emitted on the peer that actually swung, for a HUD to highlight the target.
signal attacked(target: Node3D)

var _character: Node3D = null
var _health: Health = null
var _cooldown: float = 0.0
var _dead: bool = false
var _death_timer: float = 0.0
## Server-side rate limit, per peer: a client that spams the RPC still gets one
## swing per cooldown, whatever its own timer believes.
var _last_swing: Dictionary = {}


func _ready() -> void:
	_character = get_parent() as Node3D
	if _character == null:
		return
	_health = _character.get_node_or_null("Health") as Health
	if _health != null:
		_health.changed.connect(_on_health_changed)
	set_process_unhandled_input(is_local_owner())


## The peer that drives this character: ours offline, the owner over the network.
func is_local_owner() -> bool:
	if _character == null:
		return false
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return true
	return _character.is_multiplayer_authority()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and attack():
		get_viewport().set_input_as_handled()


## Swing at the nearest enemy in reach. Returns whether anything was attempted, and
## is public so a HUD button or a test can swing without synthesising an event.
func attack() -> bool:
	if not is_local_owner() or _character == null or _health == null:
		return false
	if not _health.is_alive() or _cooldown > 0.0:
		return false
	var target: Node3D = nearest_enemy()
	if target == null:
		return false
	_cooldown = cooldown
	_request_swing(target)
	attacked.emit(target)
	return true


## Nearest living mob inside swing range, found by group -- which works on any peer,
## unlike the server-only world registry.
func nearest_enemy() -> Node3D:
	if _character == null:
		return null
	var best: Node3D = null
	var best_distance: float = melee_range
	for node: Node in get_tree().get_nodes_in_group(WorldState.KIND_ENEMY):
		var enemy: Node3D = node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var other: Health = enemy.get_node_or_null("Health") as Health
		if other == null or not other.is_alive():
			continue
		var distance: float = _character.global_position.distance_to(enemy.global_position)
		if distance <= best_distance:
			best = enemy
			best_distance = distance
	return best


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not _dead or not is_local_owner():
		return
	_death_timer -= delta
	if _death_timer <= 0.0:
		# Ask again only after a full delay, so a slow answer does not turn into a
		# request storm.
		_death_timer = death_delay
		request_respawn()


#region Swinging ----------------------------------------------------------------

func _request_swing(target: Node3D) -> void:
	if WorldState.is_server():
		_resolve_swing(target.get_path(), _peer_id())
	else:
		_net_swing.rpc_id(SERVER_ID, target.get_path())


@rpc("any_peer", "call_remote", "reliable")
func _net_swing(enemy_path: NodePath) -> void:
	_resolve_swing(enemy_path, multiplayer.get_remote_sender_id())


## The server's version of a swing. It trusts nothing the client said except the
## identity Godot already verified for us.
func _resolve_swing(enemy_path: NodePath, attacker: int) -> void:
	if not _may_act_for(attacker) or _character == null:
		return
	var now: float = WorldState.world_time
	if now - float(_last_swing.get(attacker, -999.0)) < cooldown:
		return
	var enemy: Node3D = get_node_or_null(enemy_path) as Node3D
	if enemy == null:
		return
	if _character.global_position.distance_to(enemy.global_position) > melee_range + range_slack:
		return
	var victim: Health = enemy.get_node_or_null("Health") as Health
	if victim == null or not victim.is_alive():
		return
	_last_swing[attacker] = now
	var taken: int = victim.apply_damage(damage, attacker)
	if taken > 0:
		WorldState.log_event("%s hits %s for %d." % [
				_label(), _label_of(enemy), taken])

#endregion


#region Dying and getting up ----------------------------------------------------

func _on_health_changed(current: int, _maximum: int) -> void:
	if current > 0:
		if _dead and is_local_owner():
			_return_to_spawn()
		_dead = false
		return
	if _dead:
		return
	_dead = true
	_death_timer = death_delay
	if WorldState.is_server():
		WorldState.log_event("%s is defeated." % _label())


## Ask to be put back on your feet. The server restores the hit points; the client
## moves itself home when the restore arrives.
func request_respawn() -> void:
	if WorldState.is_server():
		_handle_respawn(multiplayer.get_unique_id())
	else:
		_net_respawn.rpc_id(SERVER_ID)


@rpc("any_peer", "call_remote", "reliable")
func _net_respawn() -> void:
	if WorldState.is_server():
		_handle_respawn(multiplayer.get_remote_sender_id())


func _handle_respawn(sender: int) -> void:
	if not _may_act_for(sender) or _health == null:
		return
	if _health.is_alive():
		return
	_health.restore()
	WorldState.log_event("%s is back on their feet." % _label())


func _return_to_spawn() -> void:
	var level: Node = _owning_level()
	if level == null:
		return
	var point: Vector3 = level.get("spawn_point") if level.get("spawn_point") != null else Vector3.ZERO
	_character.global_position = point
	_character.velocity = Vector3.ZERO

#endregion


#region Identity ----------------------------------------------------------------

## Only the owner of a character may act for it; 0 means the server acting on its
## own player, which is legitimate. Same rule as PlayerState, deliberately.
func _may_act_for(sender: int) -> bool:
	if sender == 0 or sender == _peer_id():
		return true
	push_warning("[PlayerCombat] peer %d tried to act for player_%d" % [sender, _peer_id()])
	return false


func _peer_id() -> int:
	if _character == null:
		return 0
	return int(String(_character.name).trim_prefix("player_"))


func _label() -> String:
	return "player_%d" % _peer_id()


func _label_of(node: Node3D) -> String:
	var enemy: Enemy = node as Enemy
	if enemy != null:
		return enemy.display_name
	return String(node.name)


func _owning_level() -> Node:
	return get_tree().get_first_node_in_group(WorldState.KIND_LEVEL)

#endregion