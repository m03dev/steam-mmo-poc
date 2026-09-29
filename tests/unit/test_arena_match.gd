extends GutTest
## The 1v1 arena: Pollux's pure rulebook, the offline round flow, and the asset contract
## the wiring in main.gd depends on.
##
## The rulebook is pure on purpose, so most of this needs no game at all - and the parts
## that do need one are checked as contracts (does the arena really declare itself as the
## 'arena' level, does the shell really contain the panel) rather than by reading code.

const RULES := preload("res://scripts/arena/match_rules.gd")
const ARENA := preload("res://scenes/Arena.tscn")
const MAIN_SCENE := preload("res://scenes/Main.tscn")


#region The rulebook -----------------------------------------------------------------

func test_a_fresh_round_has_its_whole_length_left() -> void:
	assert_eq(RULES.remaining(100.0, 100.0), RULES.DURATION, "a round starts full")


func test_the_countdown_counts_down() -> void:
	assert_eq(RULES.remaining(100.0, 110.0), 20.0, "ten seconds in, twenty left")


func test_the_countdown_never_goes_negative() -> void:
	# The clock keeps running past the whistle, so a countdown that did not clamp would
	# show the player a negative number in the frame or two before the round is torn down.
	assert_eq(RULES.remaining(100.0, 131.0), 0.0, "clamped at zero, not -1")


func test_the_round_is_finished_exactly_at_its_length() -> void:
	assert_false(RULES.is_finished(100.0, 129.9), "not finished a moment early")
	assert_true(RULES.is_finished(100.0, 130.0), "finished on the whistle")


func test_progress_is_a_fraction_of_the_round() -> void:
	assert_almost_eq(RULES.progress(100.0, 115.0), 0.5, 0.0001, "halfway through is a half")
	assert_eq(RULES.progress(100.0, 100.0), 0.0, "as it starts")
	assert_eq(RULES.progress(100.0, 130.0), 1.0, "and done at the end")


func test_progress_cannot_exceed_one() -> void:
	assert_eq(RULES.progress(100.0, 999.0), 1.0, "a bar cannot overflow")


#endregion
#region A round, offline ------------------------------------------------------------

func test_asking_for_a_match_offline_starts_one() -> void:
	# Offline play has no rpc to carry the request, which is why the manager runs it
	# locally. Without this, pressing the button in a single-player session would do
	# nothing at all - the exact class of bug this project keeps finding in the UI.
	watch_signals(Match)
	assert_false(Match.in_match, "no round is running to begin with")
	Match.request_match()
	assert_true(Match.in_match, "the round is running")
	assert_signal_emitted(Match, "match_started", "and every peer was told")


func test_a_started_round_reports_time_left() -> void:
	assert_gt(Match.remaining(), 0.0, "a running round has time left on it")


func test_the_round_ends_and_says_so() -> void:
	# The 30s clock is the server's alarm; this drives the last step without waiting
	# half a minute for it, which is the difference between a test people run and one
	# they skip.
	watch_signals(Match)
	Match._finish()
	assert_false(Match.in_match, "the round is over")
	assert_signal_emitted(Match, "match_ended", "and returning to the lobby was announced")
	assert_eq(Match.remaining(), 0.0, "with no time left to draw")


func test_a_second_round_cannot_start_on_top_of_the_first() -> void:
	Match.request_match()
	var started: int = get_signal_emit_count(Match, "match_started")
	Match.request_match()
	assert_eq(get_signal_emit_count(Match, "match_started"), started,
		"pressing twice does not stack rounds")
	Match._finish()


#endregion
#region The contract main.gd wires against -----------------------------------------

func test_the_arena_declares_itself_as_the_arena_level() -> void:
	# main.gd loads a level by TYPE, and level.gd behaves differently per type; if the
	# scene's own type drifted, the arena would silently load as a world.
	var arena: Node = ARENA.instantiate()
	add_child_autofree(arena)
	assert_eq(arena.get("level_type"), "arena", "the arena knows what it is")


func test_the_arena_has_no_portal() -> void:
	# Which is exactly why level.gd had to learn to survive a level without one.
	assert_null(arena_trigger(), "an arena is entered by the match button, not by walking")


func test_the_arena_spawns_players_inside_itself() -> void:
	var arena: Node = ARENA.instantiate()
	add_child_autofree(arena)
	assert_not_null(arena.get_node_or_null("Players"), "there is somewhere to put the combatants")
	assert_not_null(arena.get_node_or_null("Spawner"), "and something to replicate them with")


func test_the_arena_leaves_its_spawn_point_clear_of_its_own_geometry() -> void:
	var arena: Node = ARENA.instantiate()
	var spawn: Vector3 = arena.get("spawn_point")
	assert_ne(spawn, Vector3.ZERO, "a spawn point at the origin would be inside the floor")


func test_the_game_shell_carries_the_match_panel() -> void:
	var shell: Node = MAIN_SCENE.instantiate()
	assert_true(shell.has_node("MatchPanel"), "the button lives in the shell, so it survives "
		+ "a level swap into the arena and back")
	assert_true(shell.has_node("MatchPanel/Margin/VBox/MatchButton"), "with a button to press")
	shell.free()


func arena_trigger() -> Node:
	var arena: Node = ARENA.instantiate()
	add_child_autofree(arena)
	return arena.get_node_or_null("Trigger")

#endregion