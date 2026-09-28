extends CanvasLayer
## QuestTracker -- the player-facing half of the quest loop.
##
## Lives in Main.tscn, not in a level, so it survives the world <-> dungeon swap.
## It owns no state: everything on screen is read from the local player's
## replicated PlayerState, so the HUD cannot disagree with the server.
##
## The avatar it watches is found through the group NetPlayer puts it in, and
## re-found whenever the level swaps the old node away, which keeps this scene
## completely decoupled from the level's node layout.

@onready var _level_label: Label = $Panel/VBox/LevelLabel
@onready var _hp_bar: ProgressBar = $Panel/VBox/HPBar
@onready var _hp_label: Label = $Panel/VBox/HealthLabel
@onready var _xp_bar: ProgressBar = $Panel/VBox/XPBar
@onready var _xp_label: Label = $Panel/VBox/XPLabel
@onready var _quest_label: Label = $Panel/VBox/QuestLabel
@onready var _prompt_label: Label = $PromptLabel

## By path, not by class name -- see the note in interactable.gd.
const NetPlayerScript: GDScript = preload("res://scripts/net_player.gd")

var _state: PlayerState = null
var _interactor: PlayerInteractor = null
var _health: Health = null


func _ready() -> void:
	_watch_local_player()


func _process(_delta: float) -> void:
	# A level swap frees the old avatar, so re-attach whenever what we hold is gone.
	if _state == null or not is_instance_valid(_state):
		_watch_local_player()


func _watch_local_player() -> void:
	var avatar: Node = get_tree().get_first_node_in_group(NetPlayerScript.LOCAL_PLAYER_GROUP)
	if avatar == null:
		return
	var stats: PlayerState = avatar.get_node_or_null("Stats") as PlayerState
	if stats == null:
		return
	_state = stats
	_state.changed.connect(_refresh)

	var interactor: PlayerInteractor = avatar.get_node_or_null("Interactor") as PlayerInteractor
	if interactor != null:
		_interactor = interactor
		_interactor.prompt_changed.connect(_on_prompt_changed)
		_on_prompt_changed(interactor.prompt())

	# Hit points ride the same node as everything else the player owns, and are
	# refreshed by Health's own signal -- whether the change came from the server
	# or arrived over the wire, the tracker cannot tell and does not care.
	_health = avatar.get_node_or_null("Health") as Health
	if _health != null:
		_health.changed.connect(_refresh_health)
		_refresh_health(_health.current, _health.maximum)

	_refresh()


func _refresh_health(current: int, maximum: int) -> void:
	_hp_bar.max_value = float(maxi(maximum, 1))
	_hp_bar.value = float(current)
	_hp_label.text = "%d / %d HP" % [current, maximum]
	if current <= 0:
		_hp_label.text = "Defeated - recovering..."


func _refresh() -> void:
	if _state == null:
		return
	var progress: PlayerProgress = _state.progress
	_level_label.text = "Level %d" % progress.level
	_xp_bar.max_value = float(progress.xp_to_next())
	_xp_bar.value = float(progress.xp)
	_xp_label.text = "%d / %d XP" % [progress.xp, progress.xp_to_next()]
	_quest_label.text = _quest_text(progress)


## One line per state, reading straight off the rule enum -- so the tracker shows
## exactly what the server thinks, with no second copy of the rules.
func _quest_text(progress: PlayerProgress) -> String:
	var quest: QuestDef = QuestDatabase.get_quest(QuestDatabase.starter_quest_id())
	if quest == null:
		return ""
	match progress.state_of(quest.id):
		PlayerProgress.QuestState.NOT_STARTED:
			return "%s\n%s" % [quest.title, quest.reward_text()]
		PlayerProgress.QuestState.IN_PROGRESS:
			var line: String = "%s\n%s (%d/%d)" % [
					quest.title, quest.objective_text(),
					progress.objective_progress(quest), quest.objective_count]
			if progress.objective_met(quest):
				line += "\nReady to hand in"
			return line
		_:
			return "%s\nComplete" % quest.title


func _on_prompt_changed(text: String) -> void:
	_prompt_label.visible = text != ""
	_prompt_label.text = "" if text == "" else "[E]  " + text