class_name ItemPickup
extends "res://scripts/interactable.gd"
## ItemPickup -- a thing lying on the ground that adds an item to your bag.
##
## The client asks; the server decides. The server is the only peer allowed to
## make the pickup disappear, and it tells everyone at once, so two players
## sprinting at the same pickup cannot both collect it: whoever's request the
## server handles first wins, and the second is handed a freed node.

## Item id from ItemDatabase.
@export var item_id: String = "wolf_pelt"
@export var amount: int = 1
## How high above the origin the object floats, for the spinning bob.
@export var spin_speed: float = 1.4

var _spin: float = 0.0


func _process(delta: float) -> void:
	_spin += delta * spin_speed
	rotation.y = _spin


func prompt_text(_progress: PlayerProgress) -> String:
	var label: String = ItemDatabase.display_name(item_id)
	return "Pick up %s" % (label if amount <= 1 else "%d x %s" % [amount, label])


func marker_for(_progress: PlayerProgress) -> Array:
	return ["", marker_color]


## Send the request to the server, naming this node so the server can free the
## right one. The path is identical on every peer because the level scene is.
func activate(state: PlayerState) -> void:
	if state == null:
		return
	state.request_pickup(item_id, amount, str(get_path()))


## Free this pickup on every peer. Only the server calls this -- see
## PlayerState._handle_pickup.
func consume_everywhere() -> void:
	if multiplayer.get_peers().is_empty():
		# Nobody else to tell (offline, or the only peer in the session).
		consume()
	else:
		consume.rpc()


@rpc("authority", "call_local", "reliable")
func consume() -> void:
	queue_free()