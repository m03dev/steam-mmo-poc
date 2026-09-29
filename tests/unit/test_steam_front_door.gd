extends GutTest
## The front door: what happens when the Steam CLIENT is not running.
##
## This is the bug a friend hits first, and it was invisible in every test we had, because the
## tests all ran with Steam up. A player who was signed in to Steam *in a browser* (not the
## client) got five greyed-out buttons and the sentence "Steam is offline - direct IP and offline
## play still work." - which names the wrong cause and offers no way out. The tests below hold
## both halves of the fix: the explanation must name the real cause, and no button may be dead.

const START_SCREEN := preload("res://ui/start_screen.tscn")
const STEAM_MANAGER := preload("res://autoload/SteamManager.gd")
const SCREEN_SCRIPT := "res://ui/start_screen.gd"

## The wording that caused the dead end. Nothing we say now may be this, because it does not
## tell a player that the Steam APPLICATION is missing.
const MISLEADING_WORDING := "Steam is offline - direct IP and offline play still work."


func _screen() -> Control:
	var screen: Control = START_SCREEN.instantiate()
	add_child_autofree(screen)
	return screen


## The buttons that still exist. The overrides (Host New World, Host Dungeon, Auto-Join Dungeon,
## Join-by-Lobby-ID) are gone from the menu on Mohamed's instruction - "all of that shouldn't be
## there, make it simple and minimal" - so the rule that no button is ever dead applies to what is
## left, plus the row buttons the list builds at runtime.
func _steam_buttons(screen: Control) -> Array[Button]:
	return [
		screen.get_node("%PlayButton"),
		screen.get_node("%LobbyRefreshButton"),
	]


#region The sentence -------------------------------------------------------------

func test_no_steam_client_says_so_and_says_what_to_do() -> void:
	var hint: String = STEAM_MANAGER.start_problem(true, false, "")
	assert_true(hint.contains("Steam app"), "it names the Steam APPLICATION as the missing thing")
	assert_true(hint.contains("Retry"), "and tells the player they can try again from here")
	assert_false(hint.contains("offline play"), "it never sends them to single-player as the answer")


func test_steam_running_but_not_signed_in_is_a_different_sentence() -> void:
	# Two different problems must not read as one. "Open Steam" is useless advice to someone
	# whose Steam is already open.
	var hint: String = STEAM_MANAGER.start_problem(true, true, "Not logged on")
	assert_false(hint.contains("is not running"), "Steam IS running, so do not tell them to open it")
	assert_true(hint.contains("Not logged on"), "the reason Steam gave is passed through")
	assert_true(hint.contains("Retry"), "and the way out is still named")


func test_a_missing_addon_is_its_own_sentence_with_a_working_fallback() -> void:
	var hint: String = STEAM_MANAGER.start_problem(false, false, "")
	assert_true(hint.contains("add-on"), "a missing add-on is not a missing Steam client")
	assert_true(hint.contains("Offline"), "and offline play is the real fallback in that case")


func test_no_sentence_is_the_old_misleading_one() -> void:
	for hint: String in [
			STEAM_MANAGER.start_problem(true, false, ""),
			STEAM_MANAGER.start_problem(true, true, "whatever Steam said"),
			STEAM_MANAGER.start_problem(true, true, ""),
			STEAM_MANAGER.start_problem(false, false, ""),
		]:
		assert_false(hint.contains(MISLEADING_WORDING), "never the wording that caused the dead end")
		assert_false(hint.is_empty(), "and never silent")


func test_asking_whether_the_client_runs_is_answerable_and_safe() -> void:
	# Called before Steam init this must answer, not crash: it is what decides the sentence.
	var running: Variant = SteamManager.steam_client_running()
	assert_true(running is bool, "it answers with a yes/no about this machine")


#endregion
#region No dead buttons ----------------------------------------------------------

func test_a_steam_failure_leaves_every_network_button_pressable() -> void:
	var screen: Control = _screen()
	screen._on_steam_initialized(false)

	for button: Button in _steam_buttons(screen):
		assert_false(button.disabled,
			"'%s' must stay pressable: a disabled button cannot explain itself" % button.name)


func test_a_steam_failure_shows_the_reason_the_player_can_act_on() -> void:
	var screen: Control = _screen()
	screen._on_steam_initialized(false)

	var banner: Control = screen.get_node("%SteamBanner")
	assert_true(banner.visible, "the banner is shown")
	var problem: String = screen.get_node("%SteamProblem").text
	assert_true(problem.contains("Retry"), "it offers the way out: %s" % problem)
	assert_false(problem.contains(MISLEADING_WORDING), "and does not use the old wording")


func test_a_working_steam_hides_the_banner() -> void:
	var screen: Control = _screen()
	screen._on_steam_initialized(false)
	assert_true(screen.get_node("%SteamBanner").visible, "shown while Steam is broken")
	screen._on_steam_initialized(true)
	assert_false(screen.get_node("%SteamBanner").visible, "hidden once Steam is up")


func test_pressing_play_without_steam_explains_instead_of_looking_busy() -> void:
	# The button used to be disabled, so pressing it did nothing at all. If it is pressable it
	# must not quietly pretend to search for a world it cannot reach.
	var screen: Control = _screen()
	var was_initialized: bool = SteamManager.is_initialized
	SteamManager.is_initialized = false
	screen._play()
	SteamManager.is_initialized = was_initialized

	var status: String = screen.get_node("%Status").text
	assert_false(status.contains("Looking for an open world"),
		"it must not claim to be searching without Steam")
	assert_true(status.contains("Retry"), "it explains and offers the way out: %s" % status)
	assert_true(screen.get_node("%SteamBanner").visible, "and shows the banner")


func test_the_ways_out_are_wired_to_real_functions() -> void:
	var screen: Control = _screen()
	assert_true(screen.get_node("%SteamRetryButton").pressed.is_connected(SteamManager.retry),
		"Retry calls the manager's retry()")
	assert_true(screen.get_node("%OpenSteamButton").pressed.is_connected(
			SteamManager.open_steam_client), "Open Steam opens the client")


func test_the_old_disabling_line_cannot_come_back() -> void:
	# A pin, because this exact line is the bug: it made five buttons dead and taught nobody
	# anything. Reading the source is the honest way to hold a rule about code that removed a
	# feature, since no behaviour test can prove the absence of a line.
	var source: String = FileAccess.get_file_as_string(SCREEN_SCRIPT)
	assert_false(source.contains("disabled = not success"),
		"the start screen must never disable the network buttons on a failed Steam start")
	assert_true(source.contains("func _steam_ready()"), "it uses the gate that explains instead")


func test_retrying_an_already_good_steam_is_harmless() -> void:
	# Retry is pressable at any time, so it must not re-run Steam's init on a healthy session.
	watch_signals(SteamManager)
	var was_initialized: bool = SteamManager.is_initialized
	SteamManager.is_initialized = true
	SteamManager.retry()
	SteamManager.is_initialized = was_initialized
	assert_signal_emitted_with_parameters(SteamManager, "steam_initialized", [true])


#endregion
#region The minimal menu ----------------------------------------------------------

## Mohamed, verbatim: "rework the ui, all of that shouldn't be there, make it simple and minimal,
## get rid of the auto join dungeon." A menu grows back one button at a time, so the removals are
## held by name: if any of these returns, it has to return past this test and the reason it exists.
const REMOVED_NODES := [
	"HostWorldButton", "HostDungeonButton", "AutoDungeonButton",
	"LobbyIdInput", "JoinButton",
	"DirectHostButton", "DirectJoinButton", "DirectAddressInput",
	"Subtitle", "Identity", "Controls",
]


func test_the_menus_removed_clutter_stays_removed() -> void:
	var screen: Control = _screen()
	for node_name: String in REMOVED_NODES:
		assert_null(screen.find_child(node_name, true, false),
			"'%s' was removed on purpose: it is a testing override, not a choice a player makes"
			% node_name)


func test_the_menu_still_offers_every_choice_a_player_needs() -> void:
	# The other half of a minimal menu: not only what went, but that nothing else went with it.
	var screen: Control = _screen()
	for node_name: String in ["PlayButton", "OfflineButton", "QuitButton",
			"LobbyListBox", "LobbyRefreshButton", "LobbyListStatus",
			"SteamBanner", "OpenSteamButton", "SteamRetryButton", "Status"]:
		assert_not_null(screen.find_child(node_name, true, false),
			"'%s' must survive the tidy-up" % node_name)


#endregion
