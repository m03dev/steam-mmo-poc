extends CanvasLayer
## CombatLog -- the panel that reads WorldState's combat log.
##
## It owns no events of its own: the world broadcasts each line, so what two peers
## read here is the same list in the same order -- there is one log, the server
## writes it, and this only draws it. Old lines dim towards the top so the newest
## hit is always the brightest thing on the panel.

const MAX_ROWS: int = 6

@onready var _rows: VBoxContainer = $Panel/VBox/Rows

var _recent: Array[String] = []


func _ready() -> void:
	WorldState.combat_event.connect(_on_event)
	_recent = WorldState.recent(MAX_ROWS)
	_rebuild()


func _on_event(text: String) -> void:
	_recent.append(text)
	while _recent.size() > MAX_ROWS:
		_recent.pop_front()
	_rebuild()


func _rebuild() -> void:
	for child: Node in _rows.get_children():
		# Detach before freeing: queue_free() alone leaves the old rows in the
		# container until the end of the frame, and they would flash alongside the
		# new ones.
		_rows.remove_child(child)
		child.queue_free()
	if _recent.is_empty():
		_add_row("Nothing yet.", 0.4)
		return
	var count: int = _recent.size()
	for i in count:
		var age: float = float(count - 1 - i)
		_add_row(_recent[i], clampf(1.0 - age * 0.14, 0.28, 1.0))


func _add_row(text: String, alpha: float) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1.0, 1.0, 1.0, alpha)
	_rows.add_child(label)