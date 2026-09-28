extends CanvasLayer
## InventoryPanel -- what the player is carrying.
##
## The missing quarter of the loop: the quest could ask you to collect three pelts
## and you could do it, but nothing on screen ever admitted you had. It owns no
## state -- it reads the local player's replicated PlayerState exactly as the quest
## tracker does, so the two can never disagree about what is in the bag.
##
## Contents are server truth. When a hand-in consumes the pelts they leave this
## panel because the server says they left, not because the UI predicted it, which
## makes the panel a live readout of authority rather than decoration.

const NetPlayerScript: GDScript = preload("res://scripts/net_player.gd")
const ItemDatabaseScript: GDScript = preload("res://scripts/item_database.gd")

@onready var _title: Label = $Panel/VBox/Title
@onready var _empty: Label = $Panel/VBox/Empty
@onready var _rows: VBoxContainer = $Panel/VBox/Rows

var _state: PlayerState = null
## What is currently drawn, as "id:count," repeated. Compared before rebuilding, so
## the rows are only ever thrown away when the bag really changed.
var _signature: String = ""


func _ready() -> void:
	_watch_local_player()


func _process(_delta: float) -> void:
	# A level swap frees the avatar we were attached to; re-find it, as the tracker does.
	if _state == null or not is_instance_valid(_state):
		_watch_local_player()


## Fold the bag away or bring it back. Bound to the inventory key.
func toggle() -> void:
	visible = not visible


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()


func _watch_local_player() -> void:
	var avatar: Node = get_tree().get_first_node_in_group(NetPlayerScript.LOCAL_PLAYER_GROUP)
	if avatar == null:
		return
	var stats: PlayerState = avatar.get_node_or_null("Stats") as PlayerState
	if stats == null:
		return
	_state = stats
	_state.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _state == null:
		return
	var inventory: Dictionary = _state.progress.inventory

	# Sorted so the list does not jump around as the dictionary reorders itself.
	var held: Array[String] = []
	var counts: Dictionary = {}
	for id: Variant in inventory.keys():
		var count: int = int(inventory[id])
		if count <= 0:
			continue
		var key: String = str(id)
		held.append(key)
		counts[key] = count
	held.sort()

	var signature: String = ""
	for id: String in held:
		signature += "%s:%d," % [id, counts[id]]
	if signature == _signature:
		return
	_signature = signature

	_clear_rows()
	_empty.visible = held.is_empty()
	_title.text = "Inventory" if held.is_empty() else "Inventory (%d)" % held.size()
	for id: String in held:
		_rows.add_child(_make_row(id, int(counts[id])))


## One row per stack: name on the left, count on the right.
func _make_row(item_id: String, count: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = item_id

	var item_name: Label = Label.new()
	item_name.name = "Name"
	item_name.text = ItemDatabaseScript.display_name(item_id)
	item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var amount: Label = Label.new()
	amount.name = "Count"
	amount.text = "x%d" % count

	row.add_child(item_name)
	row.add_child(amount)
	return row


func _clear_rows() -> void:
	# Detach as well as free: a queued-for-deletion child is still a child until the
	# frame ends, which would make a test (or a fast second refresh) count ghosts.
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()