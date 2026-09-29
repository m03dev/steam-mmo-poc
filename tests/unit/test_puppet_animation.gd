extends GutTest
## The animation half of "other players look static".
##
## Replicating a name is not the same as moving a model, and this failure was invisible for
## a long time precisely because the two were confused: the value looked right and the
## avatar stood still. So the tests below split into the two questions that matter:
##   1. does a replicated value actually reach the SKIN (the thing that animates)? and
##   2. is the name we replicate a state the model really has?
## Replicating "Inair" - the state machine's name - instead of "fall" - the animation's
## name - would pass any test that only checks the wire and still leave the avatar frozen,
## which is why question 2 is asked against the loaded AnimationTree, not against a list.

const PLAYER_SCENE := "res://scenes/Player.tscn"
# Loaded by path rather than by class_name, which is the convention here.
const NET_ADAPTER := preload("res://scripts/net_player.gd")


## Records what it was asked to play, so the wiring can be checked without the real model.
class SpySkin:
	extends Node
	var calls: PackedStringArray = []

	func set_state(state_name: String) -> void:
		calls.append(state_name)


## Every player in these tests is named the way authority reads it, so the adapter really
## behaves as a puppet (authority is derived from the name, and the test peer is null).
func _spawn_puppet(suffix: String = "7") -> Node3D:
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	player.name = "player_" + suffix
	add_child_autofree(player)
	await get_tree().process_frame
	return player


func _adapter(player: Node3D) -> Node:
	return player.get_node("NetAdapter")


func test_a_puppet_actually_plays_what_it_was_told_to_play() -> void:
	var player: Node3D = await _spawn_puppet()
	var adapter: Node = _adapter(player)
	var spy := SpySkin.new()
	add_child_autofree(spy)
	adapter._skin = spy

	adapter.anim_state = "walk"

	assert_eq(spy.calls.size(), 1, "the replicated value reaches the skin exactly once")
	assert_eq(spy.calls[0], "walk", "and it is the value that arrived")


func test_the_owner_ignores_the_replicated_value_so_it_cannot_be_played_twice() -> void:
	# The owner's own state machine is already driving the model. Playing the replicated
	# value as well would fight it, so the owner keeps the value and drops the playback.
	var player: Node3D = await _spawn_puppet("8")
	var adapter: Node = _adapter(player)
	var spy := SpySkin.new()
	add_child_autofree(spy)
	adapter._skin = spy
	adapter._is_local = true

	adapter.anim_state = "run"

	assert_eq(spy.calls.size(), 0, "the owner never replays its own published animation")
	assert_eq(adapter.anim_state, "run", "but it does keep the value for the synchronizer")


func test_the_default_pose_is_played_once_so_a_still_puppet_is_not_frozen_upright() -> void:
	# A puppet's first replicated value can arrive before the node is ready and be dropped,
	# so the puppet says its current pose once on creation. Without this, a player whose
	# owner never moves holds its spawn pose forever - the reported bug, in its simplest form.
	var player: Node3D = await _spawn_puppet("9")
	var adapter: Node = _adapter(player)
	var spy := SpySkin.new()
	add_child_autofree(spy)
	var skin: Node = player.get_node("VisualRoot/GodotPlushSkin")
	assert_true(skin.has_method("set_state"), "the model exposes the animation entry point")

	adapter._skin = spy
	adapter._make_puppet()

	assert_eq(spy.calls.size(), 1, "creating a puppet plays its current pose once")
	assert_eq(spy.calls[0], "idle", "which is idle until told otherwise")


func test_the_replicated_names_are_states_the_model_really_has() -> void:
	# The bug's actual shape: the state machine's names and the animation's names differ
	# ("Inair" versus "fall"), so a mapping that looks right can name a state that does not
	# exist. travel() to an unknown state is a warning and no animation at all.
	var player: Node3D = await _spawn_puppet("10")
	var skin: Node = player.get_node("VisualRoot/GodotPlushSkin")
	var tree: AnimationTree = skin.find_child("AnimationTree", true, false)
	assert_not_null(tree, "the model ships an AnimationTree")
	var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/StateMachine/playback")
	assert_not_null(playback, "and a state machine to travel")

	var adapter: Node = _adapter(player)
	# "fall" is what the mapping turns the state machine's "Inair" into; if the model had no
	# such state, the Avatar would silently keep its previous animation.
	adapter.anim_state = "fall"
	var arrived: String = await _await_state(playback, "fall")

	assert_eq(arrived, "fall", "every name we replicate exists in the model")


## Waits for the state machine to BE in that state, rather than assuming how long the model's
## blends take. Some travels land on the next frame and some cross a transition with a real
## duration, so a fixed number of frames is a test of the model's blend times, not of the
## mapping. What is being checked is that the state ARRIVES at all: an unknown state is a
## warning and no animation, so it never would.
func _await_state(playback: AnimationNodeStateMachinePlayback, wanted: String, frames: int = 45) -> String:
	for _i in frames:
		if playback.get_current_node() == wanted:
			return wanted
		await get_tree().process_frame
	return playback.get_current_node()


func test_the_mapping_never_names_a_state_the_model_lacks() -> void:
	var player: Node3D = await _spawn_puppet("11")
	var skin: Node = player.get_node("VisualRoot/GodotPlushSkin")
	var tree: AnimationTree = skin.find_child("AnimationTree", true, false)
	var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/StateMachine/playback")
	var adapter: Node = _adapter(player)

	# Every state the vendored state machine can report must map to an animation the model
	# really has. Existence is checked against the state machine itself, not by travelling:
	# whether a given travel lands depends on the model's own transitions and their blends,
	# which is not what is being asked here. "fall" is the surprising one - the state machine
	# calls it "Inair" - and it would be invisible if we replicated the state name raw.
	var blend_root: AnimationNodeBlendTree = tree.tree_root
	assert_not_null(blend_root, "the tree root is a blend tree that hosts the state machine")
	var machine: AnimationNodeStateMachine = blend_root.get_node("StateMachine")
	assert_not_null(machine, "the state machine is inside it, which is where the playback path points")
	for state_name in ["Idle", "Walk", "Run", "Jump", "Inair", "somethingUnheardOf"]:
		var animation: String = adapter.animation_for_state(state_name)
		assert_not_null(machine.get_node(animation),
			"state '%s' maps to animation '%s', which the model really has" % [state_name, animation])


## The property that actually matters, and the one a name-only test would miss: a puppet told
## to walk has to STILL BE WALKING while its owner walks. The model's state machine has its own
## transitions, and a puppet has no movement parameters of its own - the vendored state scripts
## that would set them are switched off, which is the whole point of a puppet. So a state that
## was set once can be pulled away again by the model's own logic, and the avatar freezes
## mid-stride while the owner keeps walking: the reported bug, one layer deeper.
func test_a_moving_puppet_keeps_moving() -> void:
	var player: Node3D = await _spawn_puppet("12")
	var skin: Node = player.get_node("VisualRoot/GodotPlushSkin")
	var tree: AnimationTree = skin.find_child("AnimationTree", true, false)
	var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/StateMachine/playback")
	var adapter: Node = _adapter(player)

	# Walk and run both, because the drift is not specific to one pose: the model pulled
	# whatever it was told back to idle once nothing kept saying otherwise.
	for pose in ["walk", "run"]:
		adapter.anim_state = pose
		assert_eq(await _await_state(playback, pose), pose, "it starts %s" % pose)

		# Longer than the renew interval and far longer than the model's blends, so this is
		# real elapsed time in which the model used to drift away.
		await get_tree().create_timer(1.2).timeout

		assert_eq(playback.get_current_node(), pose,
			"a puppet whose owner is still %s must still be %s over a second later" % [pose, pose])


func test_the_renew_rule_is_an_interval_not_a_per_frame_call() -> void:
	assert_false(NET_ADAPTER.pose_renew_due(0.0, 0.4), "not the same frame it was set")
	assert_false(NET_ADAPTER.pose_renew_due(0.39, 0.4), "not before the interval is up")
	assert_true(NET_ADAPTER.pose_renew_due(0.4, 0.4), "due once the interval is up")
	assert_true(NET_ADAPTER.pose_renew_due(9.0, 0.4), "and stays due if a frame was long")