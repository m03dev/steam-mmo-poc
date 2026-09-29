extends GutTest

## Pins two things that were both silently broken in the same way - a value nobody
## carried from the peer that knows it to the peer that needs it.
##
## 1. REMOTE ANIMATION. The vendored state scripts drive the model themselves, but only
##    on the owner: a puppet's state machine is switched off so it cannot read the LOCAL
##    keyboard, which also switched off the animation. Every other player stood frozen in
##    its spawn pose while sliding across the map. The fix replicates the animation NAME.
##
## 2. HOST DEPARTURE. The host leaving ended the session and logged the survivor out,
##    even though Steam had already handed them the lobby and their character, progress
##    and world were all still valid. The fix is host migration.
##
## What is NOT claimed here: a real takeover, two peers leaving one session and meeting in
## the next. That is a live test on two machines and is arranged with the Windows peer.
## What is pinned is the decision and the wiring - including the wiring in the SCENE FILE,
## because "the property is replicated" is not something the code can show by itself.

const PLAYER_SCENE_PATH: String = "res://scenes/Player.tscn"


#region Remote animation ---------------------------------------------------------

func test_the_animation_names_are_the_models_own() -> void:
	# The state machine's names and the model's animation names differ, which is exactly
	# the sort of mapping that gets guessed at in two places. This is the one place.
	assert_eq(NetPlayer.animation_for_state("Idle"), "idle")
	assert_eq(NetPlayer.animation_for_state("Walk"), "walk")
	assert_eq(NetPlayer.animation_for_state("Run"), "run")
	assert_eq(NetPlayer.animation_for_state("Jump"), "jump")


func test_the_falling_state_maps_to_the_fall_animation() -> void:
	# The mismatch that would otherwise be found by watching a puppet fall in slow motion.
	assert_eq(NetPlayer.animation_for_state("Inair"), "fall")


func test_an_unknown_state_falls_back_to_idle_rather_than_nothing() -> void:
	# The state machine's name is empty until its first state enters, and a puppet that
	# asked the AnimationTree to travel to "" would freeze rather than look idle.
	assert_eq(NetPlayer.animation_for_state(""), "idle")
	assert_eq(NetPlayer.animation_for_state("SomethingNew"), "idle")


func test_the_animation_state_is_actually_replicated() -> void:
	# The half that no code can demonstrate: the property has to be in the scene's
	# replication config or it never leaves the machine that owns the character.
	var scene: String = FileAccess.get_file_as_string(PLAYER_SCENE_PATH)
	assert_true(scene.contains('NodePath("NetAdapter:anim_state")'),
			"anim_state must be listed in the Player synchronizer's replication config")
	assert_true(scene.contains("properties/3/replication_mode = 2"),
			"and on-change, so a standing player sends nothing at all")


#endregion


#region Host migration -----------------------------------------------------------

func test_a_direct_session_has_nothing_to_migrate_to() -> void:
	# A direct-IP session is one host, one port, no lobby: there is nobody to promote.
	assert_eq(NetworkManager.migration_plan(true, true, true),
			NetworkManager.MigrationPlan.END_SESSION)


func test_no_lobby_means_no_session_to_continue() -> void:
	assert_eq(NetworkManager.migration_plan(false, false, false),
			NetworkManager.MigrationPlan.END_SESSION)


func test_the_promoted_peer_takes_the_session_over() -> void:
	# Steam hands the lobby to a remaining member when the owner leaves; that member is
	# the one who can keep the session alive, so it becomes the host.
	assert_eq(NetworkManager.migration_plan(false, true, true),
			NetworkManager.MigrationPlan.TAKE_OVER)


func test_a_non_owner_follows_whoever_was_promoted() -> void:
	assert_eq(NetworkManager.migration_plan(false, true, false),
			NetworkManager.MigrationPlan.FOLLOW_OWNER)


func test_migration_is_a_separate_signal_from_the_session_ending() -> void:
	# `lobby_left` means the session is over and sends a listener back to the menu.
	# Migration means the opposite, so a listener must be able to tell them apart.
	assert_true(NetworkManager.has_signal("host_migrated"),
			"host_migrated must exist as its own signal")
	assert_true(NetworkManager.has_signal("lobby_left"))


func test_the_host_disconnect_handler_tries_to_migrate_before_ending() -> void:
	# Order matters and is invisible in the diff: attempting migration AFTER emitting
	# lobby_left would log the player out and then try to continue a session they have
	# already been thrown out of.
	var source: String = FileAccess.get_file_as_string("res://autoload/NetworkManager.gd")
	var fn_start: int = source.find("func _on_server_disconnected(")
	assert_gt(fn_start, 0, "the handler must exist")
	var body: String = source.substr(fn_start, 900)
	var try_at: int = body.find("_try_host_migration()")
	var end_at: int = body.find("lobby_left.emit()")
	assert_gt(try_at, 0, "the handler must try to keep the session")
	assert_gt(end_at, 0, "and must still be able to end it")
	assert_lt(try_at, end_at, "migration is attempted BEFORE the session is declared over")


func test_the_level_takes_over_the_node_name_the_authority_is_derived_from() -> void:
	# The node surgery lives in the level, and losing it would leave the survivor owning
	# a session as peer 1 while its own avatar was still called something else.
	var source: String = FileAccess.get_file_as_string("res://scripts/level.gd")
	assert_true(source.contains("func _on_host_migrated("))
	assert_true(source.contains('mine.name = "player_1"'),
			"the local avatar must take the host's name")
	assert_true(source.contains("NetworkManager.host_migrated.connect"),
			"and the level must be listening for it")


#endregion