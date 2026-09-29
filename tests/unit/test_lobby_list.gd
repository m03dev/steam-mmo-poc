extends GutTest
## The menu's view of the open lobbies.
##
## The point of this API is that the UI never touches Steam directly: it asks, and it gets rows.
## What can be tested without a lobby list to look at is the ordering rule, the contract of the
## row itself, and the answer given when there is no Steam at all - which is the case a menu must
## not hang on, because no callback is ever coming.

const NETWORK_MANAGER_SCRIPT := "res://autoload/NetworkManager.gd"


func _row(id: int, members: int, maximum: int) -> Dictionary:
	return {"id": id, "name": "x", "type": "world", "members": members, "max": maximum, "owner": "y"}


func test_a_lobby_with_room_comes_before_a_full_one() -> void:
	# The whole point of a server list is joining something. A full lobby is not joinable, so it
	# belongs below an open one no matter how busy it is.
	var full: Dictionary = _row(10, 8, 8)
	var open: Dictionary = _row(99, 1, 8)
	var ordered: Array[Dictionary] = NetworkManager.order_summaries([full, open])
	assert_eq(int(ordered[0]["id"]), 99, "the joinable lobby is first")
	assert_eq(int(ordered[1]["id"]), 10, "the full one is last")


func test_the_busiest_joinable_lobby_comes_first() -> void:
	var busy: Dictionary = _row(1, 6, 8)
	var quiet: Dictionary = _row(2, 1, 8)
	var ordered: Array[Dictionary] = NetworkManager.order_summaries([quiet, busy])
	assert_eq(int(ordered[0]["id"]), 1, "most players first among those with room")


func test_equally_busy_lobbies_do_not_swap_places() -> void:
	# A list that reorders itself every refresh is a list nobody can click. Ties break on id.
	var first: Dictionary = _row(5, 2, 8)
	var second: Dictionary = _row(7, 2, 8)
	for _pass in range(3):
		var ordered: Array[Dictionary] = NetworkManager.order_summaries([second, first])
		assert_eq(int(ordered[0]["id"]), 5, "the lower id is consistently first")
		assert_eq(int(ordered[1]["id"]), 7, "and the higher id consistently second")


func test_ordering_does_not_disturb_the_callers_list() -> void:
	var rows: Array[Dictionary] = [_row(2, 1, 8), _row(1, 1, 8)]
	var ordered: Array[Dictionary] = NetworkManager.order_summaries(rows)
	assert_eq(int(rows[0]["id"]), 2, "the input keeps its original order")
	assert_eq(int(ordered[0]["id"]), 1, "and the result is ordered separately")


func test_nothing_to_show_is_an_empty_list_not_a_crash() -> void:
	var empty: Array[Dictionary] = []
	assert_eq(NetworkManager.order_summaries(empty).size(), 0, "an empty list survives ordering")


func test_without_steam_the_menu_is_answered_immediately() -> void:
	# No Steam means no callback will EVER arrive, so an unanswered request would leave the menu
	# spinning forever. It must be told "nothing" at once.
	var was_initialized: bool = SteamManager.is_initialized
	SteamManager.is_initialized = false
	watch_signals(NetworkManager)
	NetworkManager.refresh_lobby_list()
	SteamManager.is_initialized = was_initialized

	assert_signal_emitted(NetworkManager, "lobby_list_updated",
		"the menu is answered rather than left waiting")
	var params: Array = get_signal_parameters(NetworkManager, "lobby_list_updated", 0)
	assert_eq(params.size(), 1, "with one argument")
	assert_eq((params[0] as Array).size(), 0, "an empty list")


func test_the_row_keys_are_the_frozen_contract() -> void:
	# Pollux builds against these names, so they are pinned in source: a rename here would break
	# his half silently, and no behaviour test would notice until a real lobby list arrived.
	var source: String = FileAccess.get_file_as_string(NETWORK_MANAGER_SCRIPT)
	for key: String in ["\"id\"", "\"name\"", "\"type\"", "\"members\"", "\"max\"", "\"owner\""]:
		assert_true(source.contains(key + ":"), "the row still carries %s" % key)
	assert_true(source.contains("func refresh_lobby_list()"),
		"and the refresh entry point keeps its name")


func test_a_lobby_that_is_not_ours_is_not_a_world() -> void:
	# Found by actually running the menu: App ID 480 is Valve's shared test app, so the public
	# lobby list contained fifty unjoinable lobbies belonging to strangers. A row that cannot be
	# joined is worse than no row, so only lobbies carrying our own keys count.
	assert_true(NetworkManager.is_our_lobby("world", "0.0015", "3"), "our world lobby is ours")
	assert_true(NetworkManager.is_our_lobby("dungeon", "0.0015", "3"), "and so is a dungeon")
	assert_false(NetworkManager.is_our_lobby("", "0.0015", "3"), "a lobby with no type for us is not")
	assert_false(NetworkManager.is_our_lobby("ynx2_seamless_master_lobby", "", ""),
		"nor is another project's lobby that merely shares a key name")
	assert_false(NetworkManager.is_our_lobby("world", "", "3"),
		"nor a 'world' with no build behind it to join")


func test_an_older_build_of_ours_is_still_a_world() -> void:
	# Filtering must not hide a friend who simply has not updated: that is what the row's
	# version note is for.
	assert_true(NetworkManager.is_our_lobby("world", "0.0012", "3"),
		"an old build of ours is still ours")


func test_a_build_we_cannot_join_sorts_below_one_we_can() -> void:
	var old: Dictionary = _row(1, 5, 8)
	old["compatible"] = false
	old["version"] = "0.0012"
	var current: Dictionary = _row(2, 1, 8)
	current["compatible"] = true
	var ordered: Array[Dictionary] = NetworkManager.order_summaries([old, current])
	assert_eq(int(ordered[0]["id"]), 2, "the joinable build is offered first")
	assert_eq(int(ordered[1]["id"]), 1, "and the incompatible one is still visible, just lower")