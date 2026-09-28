class_name Health
extends Node
## Health -- hit points for anything that can be hit.
##
## Rules only; there is no networking in this file, and that is deliberate.
## `current` is an ordinary exported property, which means a MultiplayerSynchronizer
## on an authoritative node replicates it for free -- and because Godot runs the
## setter on the receiving side too, every peer's health bar is driven by the same
## `changed` signal the server uses. One code path, no client/server special cases,
## and no hand-written "sync my health" packet to get wrong.

signal changed(current: int, maximum: int)
signal damaged(amount: int, attacker_peer: int)
signal died(killer_peer: int)

@export var maximum: int = 100
## Replicated. Writing it on a client is possible but pointless -- the server's next
## update overwrites it; that is why nothing but the server ever does.
@export var current: int = 100:
	set(value):
		var clamped: int = clampi(value, 0, maximum)
		if clamped == current:
			return
		current = clamped
		changed.emit(current, maximum)


func _enter_tree() -> void:
	# Hit points are only ever written by the server -- a client that could write its
	# own would be a client that cannot be killed. Pinning authority here states that,
	# and it is also what lets a server-owned MultiplayerSynchronizer sit under this
	# node and replicate `current` downwards while the character it belongs to is
	# owned by a player.
	set_multiplayer_authority(WorldState.SERVER_ID)


func _ready() -> void:
	current = clampi(current, 0, maximum)


func is_alive() -> bool:
	return current > 0


func fraction() -> float:
	if maximum <= 0:
		return 0.0
	return float(current) / float(maximum)


## The one way hit points go down. Returns what was actually taken, so a caller can
## tell a kill from a graze and the combat log can say which.
func apply_damage(amount: int, attacker_peer: int = 0) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var taken: int = mini(amount, current)
	current = current - taken
	damaged.emit(taken, attacker_peer)
	if not is_alive():
		died.emit(attacker_peer)
	return taken


## Back to full. Used when a player gets up again.
func restore() -> void:
	current = maximum


## Put a number back to where it started, ignoring the clamp order above.
func set_maximum(value: int, refill: bool = true) -> void:
	maximum = maxi(value, 1)
	var wanted: int = maximum if refill else mini(current, maximum)
	current = wanted
	changed.emit(current, maximum)