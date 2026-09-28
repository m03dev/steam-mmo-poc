extends CanvasLayer
## In-game chat box. Built in code so the layout cannot drift from the script
## and so it can be instantiated headlessly for a smoke check.

const MARGIN: int = 12
const BOX_W: int = 400
const BOX_H: int = 150

var _log: RichTextLabel
var _entry: LineEdit


func _ready() -> void:
	layer = 10
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	# Bottom-centre: bottom-left is the combat log, bottom-right is where the
	# player's own frame reads from, and the chat line wants the middle anyway.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = MARGIN
	panel.offset_top = -BOX_H - MARGIN
	panel.offset_right = MARGIN + BOX_W
	panel.offset_bottom = -MARGIN
	add_child(panel)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	_log = RichTextLabel.new()
	_log.name = "Log"
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_log)
	_entry = LineEdit.new()
	_entry.name = "Entry"
	_entry.placeholder_text = "press Enter to chat"
	_entry.text_submitted.connect(_on_submitted)
	vbox.add_child(_entry)
	Chat.message_received.connect(_on_message)
	Chat.system_message.connect(_on_system)
	_on_system("chat ready")


func _on_submitted(text: String) -> void:
	Chat.say(text)
	_entry.clear()


func _on_message(_from_id: int, from_name: String, text: String) -> void:
	_log.append_text("<%s> %s\n" % [from_name, text])


func _on_system(text: String) -> void:
	_log.append_text("-- %s --\n" % text)
