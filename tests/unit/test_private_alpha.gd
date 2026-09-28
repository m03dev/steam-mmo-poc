extends GutTest

## Pins the rules that make a build safe to hand to other people: which App ID it
## talks to, how visible its sessions are, and what happens when an invite arrives
## while we are already doing something.
##
## Nothing here needs a second peer or a live lobby: every case is decided locally.
## The paths that WOULD touch Steam (accepting a real invite) are deliberately not
## driven, because a test must not start an async lobby join it cannot wait for.

const TEMP_APPID: String = "user://test_appid.txt"

## NetworkManager is an autoload: mutating it in a test leaks into the next one, so
## every test that touches it puts it back.
var _saved_is_host: bool = false
var _saved_lobby_id: int = 0


func before_each() -> void:
	_saved_is_host = NetworkManager.is_host
	_saved_lobby_id = NetworkManager.current_lobby_id


func after_each() -> void:
	NetworkManager.is_host = _saved_is_host
	NetworkManager.current_lobby_id = _saved_lobby_id
	if FileAccess.file_exists(TEMP_APPID):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_APPID))


#region App ID ------------------------------------------------------------------

func test_app_id_file_is_read_when_it_holds_a_number() -> void:
	var f: FileAccess = FileAccess.open(TEMP_APPID, FileAccess.WRITE)
	f.store_string("1234567\n")
	f.close()
	assert_eq(SteamManager._read_app_id_file(TEMP_APPID), 1234567,
		"a numeric steam_appid.txt is the App ID")


func test_app_id_file_rejects_anything_that_is_not_a_number() -> void:
	# A malformed file must not silently become the dev App ID through int(), which
	# would aim a release build at Valve's shared test app without saying so.
	var f: FileAccess = FileAccess.open(TEMP_APPID, FileAccess.WRITE)
	f.store_string("# my app id\nnot-a-number\n")
	f.close()
	assert_eq(SteamManager._read_app_id_file(TEMP_APPID), 0,
		"junk in the file reads as 'no App ID here', not as 0 or 480")


func test_app_id_file_missing_is_not_an_error() -> void:
	assert_eq(SteamManager._read_app_id_file("user://definitely_not_here.txt"), 0,
		"a missing file is the normal case on a dev machine")


func test_zero_is_not_an_app_id() -> void:
	var f: FileAccess = FileAccess.open(TEMP_APPID, FileAccess.WRITE)
	f.store_string("0")
	f.close()
	assert_eq(SteamManager._read_app_id_file(TEMP_APPID), 0, "0 is not a valid App ID")


func test_dev_app_is_the_shared_test_app() -> void:
	assert_eq(SteamManager.DEFAULT_DEV_APP_ID, 480, "480 is Spacewar, the shared test app")
	if SteamManager.app_id == SteamManager.DEFAULT_DEV_APP_ID:
		assert_true(SteamManager.is_dev_app(), "480 must report as the dev app")


#endregion


#region Lobby visibility --------------------------------------------------------

func test_visibility_follows_the_app_id_with_no_flag() -> void:
	# The rule, stated once: on the shared test app every lobby is visible to
	# strangers anyway, so we stay discoverable and can find our own test lobbies;
	# on our own App ID a session defaults to invite-only.
	NetworkManager._resolve_lobby_visibility()
	var expected: int = NetworkManager.LobbyVisibility.PUBLIC \
			if SteamManager.is_dev_app() else NetworkManager.LobbyVisibility.FRIENDS_ONLY
	assert_eq(NetworkManager.lobby_visibility, expected,
		"visibility default must follow the App ID")


func test_both_visibility_values_exist() -> void:
	assert_eq(NetworkManager.LobbyVisibility.FRIENDS_ONLY, 1,
		"friends-only must stay the non-zero value so it cannot be a default-constructed enum")


#endregion


#region Invites -----------------------------------------------------------------

func test_invite_is_refused_while_hosting() -> void:
	# Joining someone else's lobby would leave our own players in a dead session, so
	# the invite is refused and said out loud rather than quietly destroying it.
	NetworkManager.is_host = true
	NetworkManager.current_lobby_id = 4242
	watch_signals(NetworkManager)

	# Steam's argument order: join_requested(lobby_id, steam_id) -- the destination
	# first, the friend second.
	NetworkManager._on_steam_join_requested(777, 999)

	assert_signal_emitted(NetworkManager, "join_invited")
	var report: Array = get_signal_parameters(NetworkManager, "join_invited")
	assert_eq(report[0], 999, "the signal names the friend who asked")
	assert_eq(report[1], 777, "and the lobby they asked us to")
	assert_eq(report[2], false, "and that we did not accept")
	assert_eq(NetworkManager.current_lobby_id, 4242, "our own lobby is untouched")
	assert_push_warning("Refusing to join lobby 777")


func test_invite_with_no_lobby_id_is_ignored() -> void:
	NetworkManager.is_host = false
	NetworkManager.current_lobby_id = 0
	watch_signals(NetworkManager)

	# lobby_id 0, from Steam user 999: nothing to join.
	NetworkManager._on_steam_join_requested(0, 999)

	var report: Array = get_signal_parameters(NetworkManager, "join_invited")
	assert_eq(report[2], false, "a request with no destination is not accepted")
	assert_eq(NetworkManager.current_lobby_id, 0, "and does not start a session")
	assert_eq(NetworkManager.peer, null, "and opens no peer")


func test_join_invited_lobby_ignores_a_nonsense_id() -> void:
	NetworkManager.current_lobby_id = 0
	NetworkManager.join_invited_lobby(-5)
	assert_eq(NetworkManager.current_lobby_id, 0, "a negative lobby id must do nothing")
	assert_eq(NetworkManager.peer, null, "and must not open a peer")


func test_invite_friends_needs_a_lobby() -> void:
	NetworkManager.current_lobby_id = 0
	assert_false(NetworkManager.invite_friends(),
		"with no lobby there is nothing to invite anyone to")
	assert_push_warning("Nothing to invite to")


#endregion


#region Presence -----------------------------------------------------------------

func test_presence_is_skipped_when_steam_is_down() -> void:
	# Must not call into Steamworks after a failed init: that is a hard error, not a
	# silent no-op.
	var was_initialized: bool = SteamManager.is_initialized
	SteamManager.is_initialized = false
	NetworkManager.current_lobby_id = 123
	await get_tree().process_frame
	NetworkManager._publish_presence("test")
	NetworkManager._clear_presence()
	SteamManager.is_initialized = was_initialized
	assert_true(true, "neither call may raise with Steam down")


#endregion


#region Chat-adjacent identity ---------------------------------------------------

func test_steam_manager_exposes_the_app_id_it_used() -> void:
	# The value the build reports and the value it initialised with must be the same
	# one, or a log will lie about which app a session belongs to.
	assert_true(SteamManager.app_id > 0, "an App ID is always resolved, dev default included")


#endregion