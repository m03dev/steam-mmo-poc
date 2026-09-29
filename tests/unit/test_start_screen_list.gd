extends GutTest
## The server list on the menu: rows you can click, and a line that distinguishes
## "nothing is open" from "I have not asked yet".
##
## The bug this replaces was not missing information, it was missing *actionability*: the player
## got a sentence about Steam and nothing to press. So the tests here are about rows existing,
## rows being wired, and the two states never being confused with each other.

const START_SCREEN := preload("res://ui/start_screen.tscn")
# The script too, by path: the start screen has no class_name, which is the convention here.
const START_SCREEN_SCRIPT := preload("res://ui/start_screen.gd")


func _screen() -> Control:
	var screen: Control = START_SCREEN.instantiate()
	add_child_autofree(screen)
	return screen


func _row(id: int, members: int, maximum: int, owner_name: String = "Zukei") -> Dictionary:
	return {"id": id, "name": "%s's world" % owner_name, "type": "world",
		"members": members, "max": maximum, "owner": owner_name}


#region The wording -----------------------------------------------------------------

func test_a_row_shows_who_and_how_full() -> void:
	assert_true(START_SCREEN_SCRIPT.lobby_row_text(_row(1, 2, 8)).contains("2/8"),
		"a player needs the player count to choose")


func test_a_full_lobby_says_full_rather_than_looking_joinable() -> void:
	var text: String = START_SCREEN_SCRIPT.lobby_row_text(_row(1, 8, 8))
	assert_true(text.contains("FULL"), "a full lobby must not look like a clickable invitation")


func test_a_row_without_a_name_still_reads_as_somebody() -> void:
	var anonymous: Dictionary = {"id": 1, "name": "", "type": "world", "members": 1, "max": 8,
		"owner": ""}
	var text: String = START_SCREEN_SCRIPT.lobby_row_text(anonymous)
	assert_true(text.contains("Someone"), "never a row that starts with a punctuation mark")


func test_asking_and_having_nothing_are_different_sentences() -> void:
	var asking: String = START_SCREEN_SCRIPT.lobby_list_status_text(-1, true)
	var nothing: String = START_SCREEN_SCRIPT.lobby_list_status_text(0, true)
	assert_ne(asking, nothing, "still searching must not read as no servers")
	assert_true(asking.contains("Looking"), "the waiting state says it is waiting")
	assert_true(nothing.contains("No open worlds"), "and the empty state says there are none")


func test_an_empty_list_points_at_the_way_to_make_one() -> void:
	# PLAY is join-or-host, so an empty list is not a dead end - and saying so matters, because
	# "no servers found" is exactly the message that made the old front door feel broken.
	assert_true(START_SCREEN_SCRIPT.lobby_list_status_text(0, true).contains("PLAY"),
		"it names the button that opens a world")


func test_without_steam_the_list_says_what_is_missing() -> void:
	var text: String = START_SCREEN_SCRIPT.lobby_list_status_text(3, false)
	assert_true(text.contains("Steam app"), "it names the Steam application, not 'offline'")
	assert_false(text.contains("click one"), "and it does not offer rows that cannot exist")


func test_the_count_is_pluralised_rather_than_mangled() -> void:
	assert_true(START_SCREEN_SCRIPT.lobby_list_status_text(1, true).contains("1 open world -"),
		"one world reads as a world")
	assert_true(START_SCREEN_SCRIPT.lobby_list_status_text(2, true).contains("2 open worlds"),
		"two read as worlds")


#endregion
#region The rows on screen ----------------------------------------------------------

func test_rows_appear_for_every_open_world() -> void:
	var screen: Control = _screen()
	screen._on_lobby_list_updated([_row(11, 1, 8), _row(22, 3, 8)] as Array[Dictionary])

	var box: VBoxContainer = screen.get_node("%LobbyListBox")
	assert_eq(box.get_child_count(), 2, "one row per open world")
	var first: Button = box.get_child(0)
	assert_true(first is Button, "a row is a button, because a row is something you click")
	assert_true(first.text.contains("1/8"), "and it shows that world's numbers")


func test_a_row_press_is_wired_to_joining() -> void:
	var screen: Control = _screen()
	screen._on_lobby_list_updated([_row(33, 1, 8)] as Array[Dictionary])
	var row: Button = screen.get_node("%LobbyListBox").get_child(0)
	assert_gt(row.pressed.get_connections().size(), 0, "the row does something when clicked")


func test_a_world_that_closed_disappears_from_the_list() -> void:
	var screen: Control = _screen()
	screen._on_lobby_list_updated([_row(1, 1, 8), _row(2, 1, 8)] as Array[Dictionary])
	screen._on_lobby_list_updated([_row(2, 1, 8)] as Array[Dictionary])
	# queue_free() is deferred, so the old rows are still children for a frame.
	await get_tree().process_frame
	var box: VBoxContainer = screen.get_node("%LobbyListBox")
	var live: int = 0
	for child: Node in box.get_children():
		if not child.is_queued_for_deletion():
			live += 1
	assert_eq(live, 1, "the stale row is gone rather than clickable into a dead lobby")


func test_an_empty_list_leaves_no_rows_behind_and_says_so() -> void:
	var screen: Control = _screen()
	screen._on_lobby_list_updated([_row(1, 1, 8)] as Array[Dictionary])
	screen._on_lobby_list_updated([] as Array[Dictionary])
	await get_tree().process_frame
	var box: VBoxContainer = screen.get_node("%LobbyListBox")
	var live: int = 0
	for child: Node in box.get_children():
		if not child.is_queued_for_deletion():
			live += 1
	assert_eq(live, 0, "no rows")
	assert_true(screen.get_node("%LobbyListStatus").text.contains("No open worlds"),
		"and the line says there are none, rather than looking broken")


func test_clicking_a_row_without_steam_explains_instead_of_failing_silently() -> void:
	var screen: Control = _screen()
	var was_initialized: bool = SteamManager.is_initialized
	SteamManager.is_initialized = false
	screen._join_from_list(123456)
	SteamManager.is_initialized = was_initialized

	var status: String = screen.get_node("%Status").text
	assert_true(status.contains("Retry"), "it offers the way out: %s" % status)
	assert_true(screen.get_node("%SteamBanner").visible, "and shows the banner")


func test_a_row_from_a_build_we_cannot_join_says_so() -> void:
	# A friend on the old build showing up as a normal row and then refusing the join is worse
	# than not seeing them: the list would be lying about a choice it is offering.
	var old: Dictionary = _row(1, 1, 8)
	old["compatible"] = false
	old["version"] = "0.0012"
	var text: String = START_SCREEN_SCRIPT.lobby_row_text(old)
	assert_true(text.contains("different version"), "the row says why: %s" % text)
	assert_true(text.contains("0.0012"), "and which build it is")
	assert_false(text.contains("/8"), "it does not advertise player slots it cannot offer")


func test_a_row_without_a_compatibility_key_is_treated_as_current() -> void:
	# The older row shape must still draw as a normal row rather than as an error.
	assert_false(START_SCREEN_SCRIPT.lobby_row_text(_row(1, 1, 8)).contains("different version"),
		"an unspecified build is not an incompatible one")


func test_a_row_we_cannot_join_is_visible_but_not_pressable() -> void:
	# Seen live: another lobby of ours on build 0.0008. A friend on the old build is information
	# worth showing - but a click that is certain to fail is not a choice, so it is not offered.
	var screen: Control = _screen()
	var old: Dictionary = _row(1, 1, 8)
	old["compatible"] = false
	old["version"] = "0.0008"
	screen._on_lobby_list_updated([old] as Array[Dictionary])
	var row: Button = screen.get_node("%LobbyListBox").get_child(0)
	assert_true(row.disabled, "the row is shown but cannot be pressed")
	assert_true(row.text.contains("0.0008"), "and it says which build it is")
	assert_true(screen.get_node("%LobbyListStatus").text.contains("none this build can join"),
		"the line above it does not promise a join it cannot deliver")


func test_a_mixed_list_keeps_the_good_row_pressable() -> void:
	var screen: Control = _screen()
	var old: Dictionary = _row(1, 1, 8)
	old["compatible"] = false
	old["version"] = "0.0008"
	screen._on_lobby_list_updated([old, _row(2, 1, 8)] as Array[Dictionary])
	var joinable: Button = screen.get_node("%LobbyListBox").get_child(1)
	assert_false(joinable.disabled, "the row we can join stays clickable")
	assert_eq(START_SCREEN_SCRIPT.joinable_count([old, _row(2, 1, 8)] as Array[Dictionary]), 1,
		"and only one of the two counts as joinable")

#endregion