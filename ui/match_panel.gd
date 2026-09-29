extends CanvasLayer
## MatchPanel -- the in-game 1v1 matchmaking button and round countdown.
## ============================================================================
## Lives in the game shell (scenes/Main.tscn), so it is present in the world, the
## dungeon and the arena alike. Pressing the button asks Match for a round; the server
## answers by starting one, and this panel just reflects the state.
##
## Written by Pollux; landed by Castor.

@onready var _button: Button = %MatchButton
@onready var _label: Label = %MatchLabel


func _ready() -> void:
	_button.pressed.connect(_on_pressed)
	Match.match_started.connect(_on_match_started)
	Match.match_ended.connect(_on_match_ended)
	_show_idle()


func _process(_delta: float) -> void:
	if Match.in_match:
		_label.text = "MATCH - %d" % int(ceil(Match.remaining()))


func _on_pressed() -> void:
	Match.request_match()


func _on_match_started(_duration: float) -> void:
	_button.disabled = true


func _on_match_ended() -> void:
	_button.disabled = false
	_show_idle()


func _show_idle() -> void:
	if Match.in_match:
		return
	var players: int = NetworkManager.get_player_count()
	if players < 2:
		_label.text = "Waiting for another player (%d in the lobby)." % players
	else:
		_label.text = "Press for a 1v1 round in the arena."