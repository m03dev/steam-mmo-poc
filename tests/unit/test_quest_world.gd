extends GutTest
## Integration coverage for the quest loop: a real player node carrying its real
## Stats and Interactor children, plus real quest givers and pickups, driven
## through the same methods the game calls.
##
## No networking is involved, and none is needed: with Godot's default offline
## peer `is_server()` is true, so `PlayerState.request_*()` runs the very same
## server path it runs while hosting -- including the ownership check and the
## pickup consumption. This proves the loop and its wiring end to end; the
## transport is proven separately by the two-peer harness and the Steam test.

const PlayerStateScript: GDScript = preload("res://scripts/player_state.gd")
const InteractorScript: GDScript = preload("res://scripts/player_interactor.gd")
const QuestGiverScript: GDScript = preload("res://scripts/quest_giver.gd")
const ItemPickupScript: GDScript = preload("res://scripts/item_pickup.gd")
const QuestDatabaseScript: GDScript = preload("res://scripts/quest_database.gd")
const ProgressScript: GDScript = preload("res://scripts/player_progress.gd")

var _root: Node3D
var _player: Node3D
var _state
var _interactor


func before_each() -> void:
	_root = Node3D.new()
	_root.name = "QuestWorldTest"
	add_child_autofree(_root)

	_player = Node3D.new()
	_player.name = "player_1"
	var stats = PlayerStateScript.new()
	stats.name = "Stats"
	var interactor = InteractorScript.new()
	interactor.name = "Interactor"
	interactor.scan_interval = 0.0  # scan every frame so tests never wait on a timer
	_player.add_child(stats)
	_player.add_child(interactor)
	_root.add_child(_player)
	_state = stats
	_interactor = interactor


func _add_giver(at: Vector3):
	var giver = QuestGiverScript.new()
	giver.name = "Giver"
	giver.quest_id = QuestDatabaseScript.starter_quest_id()
	giver.display_name = "Trader Vex"
	giver.marker_text = "!"
	giver.position = at
	_root.add_child(giver)
	return giver


func _add_pickup(at: Vector3):
	var pickup = ItemPickupScript.new()
	pickup.name = "Pickup%d_%d" % [int(at.x), int(at.z)]
	pickup.item_id = "wolf_pelt"
	pickup.position = at
	_root.add_child(pickup)
	return pickup


## Move the player and re-scan from the new spot.
##
## The frame is waited out FIRST, so anything the last interaction freed is really
## gone before we look again -- otherwise a dying pickup could still be the nearest
## thing and get collected twice.
func _stand(at: Vector3) -> void:
	await wait_physics_frames(1)
	_player.position = at
	_interactor.refresh()


#region Walking up to things ----------------------------------------------------

func test_nothing_in_range_means_no_prompt_and_no_effect() -> void:
	var giver = _add_giver(Vector3(0.0, 0.0, 20.0))
	await _stand(Vector3.ZERO)
	assert_null(_interactor.current, "a giver 20m away is out of range")
	assert_eq(_interactor.prompt(), "", "and offers no prompt")
	_interactor.interact()
	assert_false(_state.progress.has_accepted(giver.quest_id),
			"pressing the key with nothing in range must do nothing at all")


func test_walking_up_to_the_giver_offers_the_quest() -> void:
	_add_giver(Vector3(0.0, 0.0, 2.0))
	await _stand(Vector3.ZERO)
	assert_not_null(_interactor.current, "the giver is now the nearest interactable")
	assert_true(_interactor.prompt().contains("Accept"),
			"the prompt should offer the quest, got '%s'" % _interactor.prompt())


func test_the_nearest_interactable_wins() -> void:
	var far = _add_pickup(Vector3(0.0, 0.0, 2.8))
	var near = _add_pickup(Vector3(0.0, 0.0, 0.5))
	await _stand(Vector3.ZERO)
	assert_eq(_interactor.current, near, "the closer pickup must be the one offered")
	assert_ne(_interactor.current, far)


#endregion


#region Accepting ---------------------------------------------------------------

func test_accepting_puts_the_quest_in_the_log_and_changes_the_prompt() -> void:
	var giver = _add_giver(Vector3(0.0, 0.0, 2.0))
	await _stand(Vector3.ZERO)
	_interactor.interact()
	assert_true(_state.progress.has_accepted(giver.quest_id), "the quest is now in progress")

	await _stand(Vector3.ZERO)
	assert_null(_interactor.current, "with the objective unmet there is nothing to do here")
	assert_eq(giver.marker_for(_state.progress)[0], "?",
			"the marker switches to the in-progress glyph")


func test_an_accepted_quest_is_not_offered_again() -> void:
	_add_giver(Vector3(0.0, 0.0, 2.0))
	await _stand(Vector3.ZERO)
	_interactor.interact()
	_interactor.interact()
	assert_eq(_state.progress.state_of(QuestDatabaseScript.starter_quest_id()),
			ProgressScript.QuestState.IN_PROGRESS, "the second press must not restart it")


#endregion


#region Collecting --------------------------------------------------------------

func test_collecting_a_pickup_banks_the_item_and_removes_the_object() -> void:
	var pickup = _add_pickup(Vector3(0.0, 0.0, 2.0))
	await _stand(Vector3.ZERO)
	assert_not_null(_interactor.current, "the pickup is in range")
	assert_true(_interactor.prompt().contains("Pick up"), "got '%s'" % _interactor.prompt())

	_interactor.interact()
	assert_eq(_state.progress.item_count("wolf_pelt"), 1, "the item is in the bag")

	await wait_physics_frames(2)
	assert_true(not is_instance_valid(pickup),
			"the server frees the pickup, and it is gone on this peer too")


#endregion


#region The whole loop ----------------------------------------------------------

func test_the_whole_loop_accept_collect_hand_in_reward() -> void:
	var quest = QuestDatabaseScript.get_quest(QuestDatabaseScript.starter_quest_id())
	var giver = _add_giver(Vector3(0.0, 0.0, 2.0))
	var pelts: Array = []
	for i: int in range(quest.objective_count):
		pelts.append(_add_pickup(Vector3(8.0 + float(i) * 4.0, 0.0, 6.0)))

	# 1. Accept.
	await _stand(Vector3.ZERO)
	_interactor.interact()
	assert_true(_state.progress.has_accepted(quest.id), "1. accepted")

	# 2. Collect every pelt, walking to each in turn.
	for i: int in range(pelts.size()):
		await _stand(pelts[i].position)
		assert_not_null(_interactor.current, "pelt %d should be in range" % i)
		_interactor.interact()
	assert_eq(_state.progress.item_count(quest.objective_item_id), quest.objective_count,
			"2. every pelt collected")

	# 3. Walk back and hand in.
	await _stand(Vector3.ZERO)
	assert_true(_interactor.prompt().contains("Hand in"),
			"the prompt should now offer the hand-in, got '%s'" % _interactor.prompt())
	_interactor.interact()

	# 4. Reward.
	assert_eq(_state.progress.state_of(quest.id), ProgressScript.QuestState.TURNED_IN,
			"3. turned in")
	assert_eq(_state.progress.level, 2, "4. the reward was worth a level")
	assert_eq(_state.progress.xp, quest.xp_reward - ProgressScript.xp_needed_for_level(1),
			"4. the XP landed and the surplus carried")
	assert_eq(_state.progress.item_count(quest.reward_item_id), quest.reward_item_count,
			"4. the item reward landed too")
	assert_eq(_state.progress.item_count(quest.objective_item_id), 0,
			"the pelts were taken in payment")


func test_the_giver_is_finished_with_us_after_the_hand_in() -> void:
	var giver = _add_giver(Vector3(0.0, 0.0, 2.0))
	await _stand(Vector3.ZERO)
	_interactor.interact()  # accept
	_state.progress.add_item("wolf_pelt",
			QuestDatabaseScript.get_quest(giver.quest_id).objective_count)
	await _stand(Vector3.ZERO)
	_interactor.interact()  # hand in
	await _stand(Vector3.ZERO)
	assert_null(_interactor.current, "nothing left to offer")
	assert_eq(giver.marker_for(_state.progress)[0], QuestGiverScript.DONE_MARKER,
			"and the marker must change to the done glyph rather than disappear")

#endregion