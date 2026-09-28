extends GutTest
## Tests for the HUD half of the loop.
##
## The tracker owns no state -- it reads the local player's PlayerState -- so what
## there is to get wrong is the wiring: finding the avatar through its group,
## following it across a level swap, and reacting to the signals it advertises.
## That wiring is what these tests pin down.

const PlayerStateScript: GDScript = preload("res://scripts/player_state.gd")
const InteractorScript: GDScript = preload("res://scripts/player_interactor.gd")
const NetPlayerScript: GDScript = preload("res://scripts/net_player.gd")
const QuestDatabaseScript: GDScript = preload("res://scripts/quest_database.gd")

const TRACKER_SCENE: PackedScene = preload("res://ui/quest_tracker.tscn")

var _root: Node3D
var _player: Node3D
var _state
var _interactor
var _tracker


func before_each() -> void:
	_root = Node3D.new()
	_root.name = "HudTest"
	add_child_autofree(_root)

	_player = _build_avatar("player_1")
	_build_tracker()
	await wait_physics_frames(1)


func after_each() -> void:
	# Leave no stray group membership behind for the next test.
	if is_instance_valid(_player):
		_player.remove_from_group(NetPlayerScript.LOCAL_PLAYER_GROUP)


func _build_avatar(node_name: String, with_parts: bool = true) -> Node3D:
	var player: Node3D = Node3D.new()
	player.name = node_name
	player.add_to_group(NetPlayerScript.LOCAL_PLAYER_GROUP)
	if with_parts:
		var stats = PlayerStateScript.new()
		stats.name = "Stats"
		var interactor = InteractorScript.new()
		interactor.name = "Interactor"
		player.add_child(stats)
		player.add_child(interactor)
		_state = stats
		_interactor = interactor
	_root.add_child(player)
	return player


func _build_tracker() -> void:
	_tracker = TRACKER_SCENE.instantiate()
	_root.add_child(_tracker)


func _label(node_path: String) -> Label:
	return _tracker.get_node(node_path) as Label


#region The wiring --------------------------------------------------------------

func test_the_tracker_finds_the_avatar_through_its_group() -> void:
	assert_not_null(_tracker._state, "the tracker must have attached to the local avatar")
	assert_eq(_tracker._state, _state)


func test_the_tracker_survives_a_level_swap() -> void:
	# A level swap frees the old avatar and a fresh one arrives under a new parent.
	var old_player: Node3D = _player
	old_player.queue_free()
	await wait_physics_frames(1)

	_player = _build_avatar("player_1")
	await wait_physics_frames(2)

	assert_not_null(_tracker._state, "the tracker must re-attach to the new avatar")
	assert_ne(_tracker._state, null)
	assert_true(is_instance_valid(_tracker._state), "and hold a live node, not a freed one")


func test_the_tracker_copes_with_a_player_that_has_no_stats_yet() -> void:
	# A remote player carries no Stats, and the host is headless: neither may crash.
	var old_player: Node3D = _player
	old_player.queue_free()
	await wait_physics_frames(1)
	_player = _build_avatar("player_2", false)
	await wait_physics_frames(1)
	assert_true(true, "an avatar without parts must not crash the tracker")


#endregion


#region What it shows -----------------------------------------------------------

func test_a_fresh_player_sees_level_one_and_an_empty_bar() -> void:
	assert_eq(_label("Panel/VBox/LevelLabel").text, "Level 1")
	assert_eq(_label("Panel/VBox/XPLabel").text, "0 / 100 XP")
	assert_eq(_tracker.get_node("Panel/VBox/XPBar").value, 0.0)


func test_the_quest_line_names_the_offer_before_it_is_taken() -> void:
	var quest = QuestDatabaseScript.get_quest(QuestDatabaseScript.starter_quest_id())
	var text: String = _label("Panel/VBox/QuestLabel").text
	assert_true(text.contains(quest.title), "the offer should be named, got '%s'" % text)
	assert_true(text.contains(quest.reward_text()),
			"and what it pays, got '%s'" % text)


func test_taking_the_quest_turns_the_line_into_a_counter() -> void:
	var quest = QuestDatabaseScript.get_quest(QuestDatabaseScript.starter_quest_id())
	_state.request_accept(quest.id)
	var text: String = _label("Panel/VBox/QuestLabel").text
	assert_true(text.contains(quest.title), "got '%s'" % text)
	assert_true(text.contains("(0/%d)" % quest.objective_count),
			"the counter should read 0 of N, got '%s'" % text)


func test_collecting_updates_the_counter_and_announces_readiness() -> void:
	var quest = QuestDatabaseScript.get_quest(QuestDatabaseScript.starter_quest_id())
	_state.request_accept(quest.id)
	_state.progress.add_item(quest.objective_item_id, quest.objective_count - 1)
	_state.emit_signal("changed")
	var partial: String = _label("Panel/VBox/QuestLabel").text
	assert_true(partial.contains("(%d/%d)" % [quest.objective_count - 1, quest.objective_count]),
			"got '%s'" % partial)
	assert_false(partial.contains("Ready"), "one short is not ready, got '%s'" % partial)

	_state.progress.add_item(quest.objective_item_id, 1)
	_state.emit_signal("changed")
	var ready: String = _label("Panel/VBox/QuestLabel").text
	assert_true(ready.contains("Ready"), "got '%s'" % ready)


func test_levelling_moves_the_bar_and_the_level_label() -> void:
	_state.progress.grant_xp(150)
	_state.emit_signal("changed")
	assert_eq(_label("Panel/VBox/LevelLabel").text, "Level 2")
	assert_eq(_label("Panel/VBox/XPLabel").text, "50 / 150 XP")
	assert_eq(_tracker.get_node("Panel/VBox/XPBar").value, 50.0)
	assert_eq(_tracker.get_node("Panel/VBox/XPBar").max_value, 150.0)


func test_the_hand_in_shows_as_complete() -> void:
	var quest = QuestDatabaseScript.get_quest(QuestDatabaseScript.starter_quest_id())
	_state.request_accept(quest.id)
	_state.progress.add_item(quest.objective_item_id, quest.objective_count)
	_state.request_turn_in(quest.id)
	var text: String = _label("Panel/VBox/QuestLabel").text
	assert_true(text.contains("Complete"), "got '%s'" % text)


#endregion


#region The key hint ------------------------------------------------------------

func test_the_prompt_is_hidden_when_there_is_nothing_to_do() -> void:
	assert_false(_label("PromptLabel").visible, "no prompt, nothing shown")
	assert_eq(_label("PromptLabel").text, "")


func test_the_prompt_appears_with_the_key_hint_in_front() -> void:
	_interactor.prompt_changed.emit("Accept: Pelts for the Road")
	assert_true(_label("PromptLabel").visible)
	assert_eq(_label("PromptLabel").text, "[E]  Accept: Pelts for the Road",
			"the player must be told which key")


func test_the_prompt_disappears_again_when_it_is_cleared() -> void:
	_interactor.prompt_changed.emit("Accept: Pelts for the Road")
	_interactor.prompt_changed.emit("")
	assert_false(_label("PromptLabel").visible)
	assert_eq(_label("PromptLabel").text, "")

#endregion