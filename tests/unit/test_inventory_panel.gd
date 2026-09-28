extends GutTest
## Tests for the inventory panel -- the readout that proves collection happened.
##
## Like the quest tracker it owns no state, so what is worth testing is that it
## follows the server's copy of the bag: appears, counts up, and empties again when
## a hand-in takes the goods.

const PlayerStateScript: GDScript = preload("res://scripts/player_state.gd")
const InteractorScript: GDScript = preload("res://scripts/player_interactor.gd")
const NetPlayerScript: GDScript = preload("res://scripts/net_player.gd")
const QuestDatabaseScript: GDScript = preload("res://scripts/quest_database.gd")
const ItemDatabaseScript: GDScript = preload("res://scripts/item_database.gd")

const PANEL_SCENE: PackedScene = preload("res://ui/inventory_panel.tscn")

var _root: Node3D
var _player: Node3D
var _state
var _panel


func before_each() -> void:
	_root = Node3D.new()
	_root.name = "InventoryTest"
	add_child_autofree(_root)

	_player = Node3D.new()
	_player.name = "player_1"
	_player.add_to_group(NetPlayerScript.LOCAL_PLAYER_GROUP)
	var stats = PlayerStateScript.new()
	stats.name = "Stats"
	var interactor = InteractorScript.new()
	interactor.name = "Interactor"
	_player.add_child(stats)
	_player.add_child(interactor)
	_root.add_child(_player)
	_state = stats

	_panel = PANEL_SCENE.instantiate()
	_root.add_child(_panel)
	await wait_physics_frames(1)


func after_each() -> void:
	if is_instance_valid(_player):
		_player.remove_from_group(NetPlayerScript.LOCAL_PLAYER_GROUP)


func _rows() -> VBoxContainer:
	return _panel.get_node("Panel/VBox/Rows") as VBoxContainer


func _row_ids() -> Array:
	var ids: Array = []
	for row: Node in _rows().get_children():
		ids.append(String(row.name))
	return ids


func _row(item_id: String) -> Node:
	return _rows().get_node_or_null(NodePath(item_id))


func _count_text(item_id: String) -> String:
	var row: Node = _row(item_id)
	if row == null:
		return ""
	return (row.get_node("Count") as Label).text


func _name_text(item_id: String) -> String:
	var row: Node = _row(item_id)
	if row == null:
		return ""
	return (row.get_node("Name") as Label).text


## Bank an item the way the server would, then let the panel hear about it.
func _give(item_id: String, amount: int) -> void:
	_state.progress.add_item(item_id, amount)
	_state.emit_signal("changed")


#region Empty and filled --------------------------------------------------------

func test_an_empty_bag_says_so_rather_than_showing_nothing() -> void:
	assert_eq(_rows().get_child_count(), 0, "no rows yet")
	assert_true((_panel.get_node("Panel/VBox/Empty") as Label).visible,
			"an empty panel with no words in it looks broken")
	assert_eq((_panel.get_node("Panel/VBox/Title") as Label).text, "Inventory")


func test_the_first_item_becomes_a_row_with_its_display_name() -> void:
	_give("wolf_pelt", 1)
	assert_eq(_row_ids(), ["wolf_pelt"])
	assert_eq(_name_text("wolf_pelt"), "Wolf Pelt",
			"the row must show the catalogue name, not the wire id")
	assert_eq(_count_text("wolf_pelt"), "x1")
	assert_false((_panel.get_node("Panel/VBox/Empty") as Label).visible,
			"the empty-state line must go away once there is something to show")
	assert_eq((_panel.get_node("Panel/VBox/Title") as Label).text, "Inventory (1)")


func test_up_to_two_stacks_are_listed_in_a_stable_order() -> void:
	_give("wolf_pelt", 3)
	_give("bread", 2)
	assert_eq(_row_ids(), ["bread", "wolf_pelt"], "sorted, so the list never jumps about")
	assert_eq(_count_text("bread"), "x2")
	assert_eq(_name_text("bread"), "Crusty Bread")


#endregion


#region Following the server ----------------------------------------------------

func test_collecting_more_raises_the_count_on_the_same_row() -> void:
	_give("wolf_pelt", 1)
	_give("wolf_pelt", 2)
	assert_eq(_row_ids(), ["wolf_pelt"], "still one stack, not two rows")
	assert_eq(_count_text("wolf_pelt"), "x3")


func test_an_emptied_stack_leaves_no_ghost_row() -> void:
	_give("wolf_pelt", 2)
	_state.progress.remove_item("wolf_pelt", 2)
	_state.emit_signal("changed")
	assert_eq(_row_ids(), [], "the row must go when the last one does")
	assert_true((_panel.get_node("Panel/VBox/Empty") as Label).visible)


func test_a_hand_in_swaps_the_pelts_for_the_reward() -> void:
	var quest = QuestDatabaseScript.get_quest(QuestDatabaseScript.starter_quest_id())
	_state.request_accept(quest.id)
	_give(quest.objective_item_id, quest.objective_count)
	assert_eq(_count_text(quest.objective_item_id), "x3", "three pelts going in")

	_state.request_turn_in(quest.id)
	assert_eq(_row(quest.objective_item_id), null,
			"the server consumed the pelts, so they leave the panel")
	assert_eq(_count_text(quest.reward_item_id), "x%d" % quest.reward_item_count,
			"and the reward shows up instead")


#endregion


#region Behaviour ---------------------------------------------------------------

func test_the_bag_starts_open_and_the_key_folds_it_away() -> void:
	assert_true(_panel.is_open(), "the panel demonstrates itself without being asked")
	_panel.toggle()
	assert_false(_panel.is_open())
	assert_false(_panel.visible, "and it is actually hidden, not just flagged")
	_panel.toggle()
	assert_true(_panel.is_open())


func test_it_re_attaches_after_a_level_swap() -> void:
	var old_player: Node3D = _player
	old_player.queue_free()
	await wait_physics_frames(1)

	_player = Node3D.new()
	_player.name = "player_1"
	_player.add_to_group(NetPlayerScript.LOCAL_PLAYER_GROUP)
	var stats = PlayerStateScript.new()
	stats.name = "Stats"
	_player.add_child(stats)
	_root.add_child(_player)
	_state = stats
	_give("wolf_pelt", 1)
	await wait_physics_frames(2)

	assert_eq(_count_text("wolf_pelt"), "x1",
			"the panel must follow the new avatar, not sit on the freed one")


func test_an_avatar_without_stats_is_survivable() -> void:
	# A remote player's copy has no Stats, and the host is headless: neither may crash.
	var old_player: Node3D = _player
	old_player.queue_free()
	await wait_physics_frames(1)
	var plain: Node3D = Node3D.new()
	plain.name = "player_2"
	plain.add_to_group(NetPlayerScript.LOCAL_PLAYER_GROUP)
	_root.add_child(plain)
	_player = plain
	await wait_physics_frames(1)
	assert_true(true, "an avatar with no Stats must not bring the panel down")

#endregion